/**
 * create_payment_intent — Supabase Edge Function
 *
 * Called by the Flutter client (authenticated) to begin the payment flow
 * for a paid event.
 *
 * Flow:
 *   1. Verify caller's JWT → obtain user.id
 *   2. Validate event exists, is approved, and is paid (price_cents > 0)
 *   3. Check for existing active/succeeded purchase (idempotency)
 *   4. Atomically reserve a seat via reserve_seat_if_available() DB function
 *      (uses FOR UPDATE on the events row to prevent oversubscription)
 *   5. Create a Stripe PaymentIntent with metadata linking it to the DB record
 *   6. Store Stripe IDs back on the purchase intent row
 *   7. Return { client_secret, purchase_intent_id } to the Flutter client
 *
 * The Flutter client then calls Stripe SDK with client_secret to collect
 * card details and confirm the payment.  The stripe_webhook function handles
 * the outcome.
 *
 * Security properties:
 *   • Only authenticated users can call this function (JWT required).
 *   • Seat reservation is atomic at the DB level — no TOCTOU race.
 *   • The partial unique index prevents one user holding two seats.
 *   • On any failure after reservation, the hold is cancelled so capacity
 *     is not leaked.
 *   • Stripe IDs are stored server-side; the client never writes to DB.
 */

import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'

// ---------------------------------------------------------------------------
// Initialise Stripe (secret key is injected at deploy time as an env secret)
// ---------------------------------------------------------------------------
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
  // Use the Fetch-based HTTP client compatible with Deno
  httpClient: Stripe.createFetchHttpClient(),
})

// ---------------------------------------------------------------------------
// CORS headers — adjust allowed origins for production
// ---------------------------------------------------------------------------
const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

// ---------------------------------------------------------------------------
// Helper response constructors
// ---------------------------------------------------------------------------
function errorResponse(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function okResponse(data: unknown): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------
serve(async (req: Request) => {
  // Pre-flight CORS request from Flutter web / browser
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // ── 1. Authenticate the request ─────────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return errorResponse(401, 'Missing Authorization header')
    }

    // userClient runs with the caller's JWT → RLS is enforced for all reads
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    )

    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) {
      return errorResponse(401, 'Unauthorized')
    }

    // adminClient uses the service-role key → bypasses RLS for privileged ops
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // ── 2. Parse & validate request body ────────────────────────────────────
    let event_id: string
    try {
      const body = await req.json()
      event_id = body?.event_id
    } catch {
      return errorResponse(400, 'Invalid JSON body')
    }
    if (!event_id || typeof event_id !== 'string') {
      return errorResponse(400, 'event_id is required')
    }

    // ── 3. Validate event via user's RLS context ─────────────────────────────
    // Using userClient ensures the caller can only see approved events they
    // have access to (RLS policy "events: read approved or own or admin").
    const { data: event, error: eventError } = await userClient
      .from('events')
      .select('id, title, price_cents, currency, max_occupancy, status')
      .eq('id', event_id)
      .eq('status', 'approved')
      .single()

    if (eventError || !event) {
      return errorResponse(404, 'Event not found or not approved')
    }
    if (event.price_cents === 0) {
      return errorResponse(400, 'This is a free event; no payment required')
    }

    // ── 4. Idempotency: check for existing active / succeeded purchase ────────
    const { data: existing } = await adminClient
      .from('event_purchase_intents')
      .select('id, status, stripe_client_secret, hold_expires_at')
      .eq('event_id', event_id)
      .eq('user_id', user.id)
      .in('status', ['pending_payment', 'succeeded'])
      .maybeSingle()

    if (existing?.status === 'succeeded') {
      return errorResponse(409, 'You have already purchased this event')
    }

    // Reuse a still-valid pending purchase so the user can return to the
    // payment sheet without creating a new Stripe PaymentIntent.
    if (existing?.status === 'pending_payment' && existing.stripe_client_secret) {
      const holdStillValid = new Date(existing.hold_expires_at) > new Date()
      if (holdStillValid) {
        return okResponse({
          client_secret: existing.stripe_client_secret,
          purchase_intent_id: existing.id,
        })
      }
      // Hold has expired but the cleanup job hasn't run yet.
      // Fall through to create a new hold (reserve_seat_if_available will
      // reject the old row via the partial unique index if it's still
      // pending_payment; the cleanup job will handle transition).
    }

    // ── 5. Reserve seat atomically ────────────────────────────────────────────
    // reserve_seat_if_available() acquires a FOR UPDATE lock on the events row,
    // counts seats in use, and inserts the hold row — all in one transaction.
    const { data: reservationRows, error: reserveError } = await adminClient
      .rpc('reserve_seat_if_available', {
        p_event_id:     event_id,
        p_user_id:      user.id,
        p_amount_cents: event.price_cents,
        p_currency:     event.currency,
        p_hold_minutes: 15,
      })

    if (reserveError) {
      console.error('reserve_seat_if_available DB error:', reserveError)
      return errorResponse(500, 'Failed to reserve seat; please try again')
    }

    // The function returns a set of rows; take the first (and only) row.
    const reservation = Array.isArray(reservationRows)
      ? reservationRows[0]
      : reservationRows

    if (!reservation?.success) {
      const code = reservation?.error_code
      if (code === 'at_capacity')       return errorResponse(409, 'Event is at capacity')
      if (code === 'event_not_found')   return errorResponse(404, 'Event not found or not approved')
      if (code === 'duplicate_purchase') return errorResponse(409, 'A purchase is already in progress for this event')
      console.error('reserve_seat_if_available unexpected error_code:', code)
      return errorResponse(500, code ?? 'Reservation failed')
    }

    const purchaseIntentId: string = reservation.purchase_intent_id

    // ── 6. Create the Stripe PaymentIntent ────────────────────────────────────
    // Metadata ties the Stripe object back to our DB records so the webhook
    // handler can update the correct rows.
    let stripePI: Stripe.PaymentIntent
    try {
      stripePI = await stripe.paymentIntents.create({
        amount:   event.price_cents,
        currency: event.currency.toLowerCase(),
        // Automatic payment methods simplifies the Flutter integration.
        automatic_payment_methods: { enabled: true },
        metadata: {
          purchase_intent_id: purchaseIntentId,
          event_id,
          user_id:     user.id,
          event_title: event.title.slice(0, 500), // Stripe cap: 500 chars per value
        },
      })
    } catch (stripeErr) {
      console.error('Stripe PaymentIntent creation failed:', stripeErr)
      // Roll back the hold so capacity is not leaked.
      await adminClient
        .from('event_purchase_intents')
        .update({ status: 'cancelled' })
        .eq('id', purchaseIntentId)
      return errorResponse(502, 'Payment provider error; please try again')
    }

    // ── 7. Store Stripe IDs in the purchase intent row ────────────────────────
    const { error: updateError } = await adminClient
      .from('event_purchase_intents')
      .update({
        stripe_payment_intent_id: stripePI.id,
        stripe_client_secret:     stripePI.client_secret,
      })
      .eq('id', purchaseIntentId)

    if (updateError) {
      console.error('Failed to store Stripe IDs in purchase intent:', updateError)
      // Stripe PI was created; attempt to cancel it to avoid orphaned intents.
      await stripe.paymentIntents.cancel(stripePI.id).catch((e) =>
        console.error('Failed to cancel orphaned Stripe PI:', e)
      )
      await adminClient
        .from('event_purchase_intents')
        .update({ status: 'cancelled' })
        .eq('id', purchaseIntentId)
      return errorResponse(500, 'Internal error; please try again')
    }

    // ── 8. Return client_secret to Flutter ────────────────────────────────────
    // Flutter passes client_secret to the Stripe SDK to display the payment
    // sheet.  The SDK confirms the payment; the outcome arrives via webhook.
    return okResponse({
      client_secret:      stripePI.client_secret,
      purchase_intent_id: purchaseIntentId,
    })
  } catch (err) {
    console.error('Unhandled error in create_payment_intent:', err)
    return errorResponse(500, 'Internal server error')
  }
})
