/**
 * stripe_webhook — Supabase Edge Function
 *
 * Receives Stripe webhook events and updates the DB authoritatively.
 * This is the ONLY path that creates a paid RSVP.  The client can never
 * short-circuit this by calling the REST API directly because the RLS
 * INSERT policy on event_rsvps blocks paid events for authenticated clients.
 *
 * Supported Stripe events:
 *   payment_intent.succeeded      → confirm_paid_rsvp()   (creates RSVP)
 *   payment_intent.payment_failed → release_purchase_hold('failed')
 *   payment_intent.canceled       → release_purchase_hold('cancelled')
 *   charge.refunded               → release_purchase_hold('refunded') + cancels RSVP
 *
 * Security:
 *   • Stripe HMAC signature verified before any DB access.
 *   • JWT verification is DISABLED for this function (no user JWT; called by Stripe).
 *     Configure verify_jwt = false in supabase/config.toml.
 *   • All DB mutations use the service-role client → SECURITY DEFINER functions.
 *   • Idempotency: stripe_webhook_events.stripe_event_id is UNIQUE.
 *     processed = FALSE lets a re-delivered event retry if a previous attempt
 *     failed after the record was written.
 *
 * Idempotency contract:
 *   1. Check stripe_webhook_events for the event ID.
 *   2. If processed = TRUE  → return 200 immediately (Stripe stops retrying).
 *   3. If processed = FALSE → previous attempt failed mid-flight; re-run logic.
 *   4. If not found        → insert record (processed=false), run logic, mark done.
 *   5. On any processing error → return 500 so Stripe retries.
 */

import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'

// ---------------------------------------------------------------------------
// Stripe client — webhook secret used for signature verification
// ---------------------------------------------------------------------------
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

const WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET')!

// ---------------------------------------------------------------------------
// Typed result rows from our SECURITY DEFINER DB functions
// ---------------------------------------------------------------------------
type ReserveResult = {
  success: boolean
  purchase_intent_id: string | null
  error_code: string | null
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------
serve(async (req: Request) => {
  // ── 1. Read raw body BEFORE any parsing — required for HMAC verification ───
  // Stripe computes the signature over the exact bytes received.
  // Any re-serialisation (JSON.parse → JSON.stringify) would break it.
  const rawBody = await req.text()

  const sig = req.headers.get('stripe-signature')
  if (!sig) {
    return new Response('Missing Stripe-Signature header', { status: 400 })
  }

  // ── 2. Verify Stripe HMAC signature ──────────────────────────────────────
  // constructEventAsync is the async variant required in Deno (uses Web Crypto).
  // Any tampered payload or wrong secret → throws → 400.
  let event: Stripe.Event
  try {
    event = await stripe.webhooks.constructEventAsync(rawBody, sig, WEBHOOK_SECRET)
  } catch (err) {
    console.error('Stripe webhook signature verification failed:', err)
    return new Response('Invalid signature', { status: 400 })
  }

  // Service-role client for all DB operations (bypasses RLS; calls SECURITY DEFINER fns)
  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // ── 3. Idempotency check ──────────────────────────────────────────────────
  const { data: existingRecord } = await adminClient
    .from('stripe_webhook_events')
    .select('id, processed')
    .eq('stripe_event_id', event.id)
    .maybeSingle()

  if (existingRecord?.processed === true) {
    // Already processed successfully; acknowledge so Stripe stops retrying.
    return jsonResponse({ received: true, status: 'already_processed' })
  }

  // Extract the purchase_intent_id from Stripe metadata (set in create_payment_intent).
  const paymentIntent = event.data.object as Stripe.PaymentIntent
  const purchaseIntentId: string | undefined =
    paymentIntent.metadata?.purchase_intent_id

  // ── 4. Record the webhook event (audit log + idempotency anchor) ──────────
  // If already recorded (existingRecord with processed=false) we skip insert
  // and re-run processing to handle the retry case.
  if (!existingRecord) {
    const { error: insertErr } = await adminClient
      .from('stripe_webhook_events')
      .insert({
        stripe_event_id:   event.id,
        event_type:        event.type,
        purchase_intent_id: purchaseIntentId ?? null,
        processed:         false,
      })

    if (insertErr) {
      // Most likely a race: concurrent duplicate webhook inserted first.
      // Safe to return 200 — the other worker will process it.
      if (insertErr.code === '23505') {
        return jsonResponse({ received: true, status: 'concurrent_processing' })
      }
      console.error('Failed to insert stripe_webhook_events record:', insertErr)
      return new Response('DB error', { status: 500 })
    }
  }

  // ── 5. Route and process by event type ───────────────────────────────────
  try {
    switch (event.type) {

      // ── Payment succeeded → create RSVP ────────────────────────────────
      case 'payment_intent.succeeded': {
        if (!purchaseIntentId) {
          console.error(
            'payment_intent.succeeded: missing purchase_intent_id in metadata',
            { stripe_event_id: event.id, payment_intent_id: paymentIntent.id },
          )
          // Don't throw; mark processed so we don't retry endlessly for an
          // event we cannot match to our DB.  Log for manual reconciliation.
          break
        }

        const { data: result, error } = await adminClient
          .rpc('confirm_paid_rsvp', { p_purchase_intent_id: purchaseIntentId })
        if (error) throw error

        console.log(
          `confirm_paid_rsvp: purchase=${purchaseIntentId} result=${result}`,
        )
        break
      }

      // ── Payment failed → release capacity hold ──────────────────────────
      case 'payment_intent.payment_failed': {
        if (!purchaseIntentId) {
          console.error(
            'payment_intent.payment_failed: missing purchase_intent_id',
            { stripe_event_id: event.id },
          )
          break
        }

        const { data: result, error } = await adminClient
          .rpc('release_purchase_hold', {
            p_purchase_intent_id: purchaseIntentId,
            p_new_status:         'failed',
          })
        if (error) throw error

        console.log(
          `release_purchase_hold (failed): purchase=${purchaseIntentId} result=${result}`,
        )
        break
      }

      // ── PaymentIntent cancelled → release capacity hold ─────────────────
      case 'payment_intent.canceled': {
        if (!purchaseIntentId) {
          console.error(
            'payment_intent.canceled: missing purchase_intent_id',
            { stripe_event_id: event.id },
          )
          break
        }

        const { data: result, error } = await adminClient
          .rpc('release_purchase_hold', {
            p_purchase_intent_id: purchaseIntentId,
            p_new_status:         'cancelled',
          })
        if (error) throw error

        console.log(
          `release_purchase_hold (cancelled): purchase=${purchaseIntentId} result=${result}`,
        )
        break
      }

      // ── Charge refunded → cancel RSVP ───────────────────────────────────
      case 'charge.refunded': {
        // charge.refunded does not carry PaymentIntent metadata directly.
        // Look up the purchase intent via the Stripe PaymentIntent ID stored
        // in stripe_payment_intent_id column.
        const charge = event.data.object as Stripe.Charge
        const stripePaymentIntentId = charge.payment_intent as string | null

        if (!stripePaymentIntentId) {
          console.error('charge.refunded: no payment_intent on charge', {
            stripe_event_id: event.id,
            charge_id: charge.id,
          })
          break
        }

        const { data: purchase, error: lookupErr } = await adminClient
          .from('event_purchase_intents')
          .select('id')
          .eq('stripe_payment_intent_id', stripePaymentIntentId)
          .maybeSingle()

        if (lookupErr) throw lookupErr

        if (!purchase) {
          console.warn(
            'charge.refunded: no matching purchase intent for Stripe PI',
            { stripe_payment_intent_id: stripePaymentIntentId },
          )
          break
        }

        const { data: result, error } = await adminClient
          .rpc('release_purchase_hold', {
            p_purchase_intent_id: purchase.id,
            p_new_status:         'refunded',
          })
        if (error) throw error

        console.log(
          `release_purchase_hold (refunded): purchase=${purchase.id} result=${result}`,
        )
        break
      }

      default:
        // Stripe sends many event types (e.g., customer.created, invoice.*).
        // We subscribe only to the ones we need; log others and move on.
        console.log(`Unhandled Stripe event type: ${event.type} (${event.id})`)
    }
  } catch (processingErr) {
    console.error(
      `Error processing Stripe event ${event.id} (${event.type}):`,
      processingErr,
    )
    // Return 500 so Stripe schedules a retry.
    // The stripe_webhook_events row has processed=false, so the retry will
    // re-enter the processing block above.
    return new Response('Processing error; will retry', { status: 500 })
  }

  // ── 6. Mark webhook event as successfully processed ───────────────────────
  const { error: markErr } = await adminClient
    .from('stripe_webhook_events')
    .update({
      processed:    true,
      processed_at: new Date().toISOString(),
    })
    .eq('stripe_event_id', event.id)

  if (markErr) {
    // This is non-fatal: the business logic already succeeded.
    // Log the failure; on the next Stripe retry the idempotent DB functions
    // will no-op, and we'll attempt to mark processed again.
    console.error('Failed to mark webhook event as processed:', markErr)
  }

  return jsonResponse({ received: true })
})

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
