-- =============================================================
-- Out-Fit — Migration 003: Stripe Payment Tables + RLS
--
-- Adds:
--   • purchase_status enum
--   • event_purchase_intents table (capacity holds + payment tracking)
--   • stripe_webhook_events table (idempotency log / audit trail)
--   • RLS policies for both tables
--   • Patches event_rsvps INSERT policy to block paid-event RSVPs
--     from authenticated clients (paid RSVPs created only by webhook
--     via SECURITY DEFINER function, not by direct client insert)
--
-- Apply AFTER 002_rls_events_update_hardening.sql.
-- =============================================================

-- -----------------------------------------------------------
-- ENUM: purchase_status
-- -----------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.purchase_status AS ENUM (
    'pending_payment',   -- hold is active, awaiting Stripe webhook
    'succeeded',         -- payment confirmed; RSVP has been created
    'failed',            -- Stripe reported payment failure; hold released
    'cancelled',         -- hold expired or user/system cancelled
    'refunded'           -- payment was refunded after success; RSVP cancelled
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- -----------------------------------------------------------
-- TABLE: event_purchase_intents
--
-- One row per purchase attempt.  While status = 'pending_payment'
-- and hold_expires_at > NOW() the row acts as a capacity hold:
-- get_seats_used() counts it, preventing oversubscription before
-- the Stripe webhook arrives.
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_purchase_intents (
  id                        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id                  UUID        NOT NULL REFERENCES public.events(id)   ON DELETE CASCADE,
  user_id                   UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- Populated after the Stripe PaymentIntent is created (step 2 of create_payment_intent):
  stripe_payment_intent_id  TEXT,
  stripe_client_secret      TEXT,   -- returned to the Flutter client for payment confirmation
  amount_cents              INT         NOT NULL CHECK (amount_cents > 0),
  currency                  TEXT        NOT NULL DEFAULT 'USD',
  status                    public.purchase_status NOT NULL DEFAULT 'pending_payment',
  -- Capacity hold is valid until hold_expires_at.  Expired holds are excluded
  -- from get_seats_used() automatically; a pg_cron job (migration 004) cleans them up.
  hold_expires_at           TIMESTAMPTZ NOT NULL,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_purchase_intents_updated_at
  BEFORE UPDATE ON public.event_purchase_intents
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Only one active (pending or succeeded) purchase per user per event.
-- Failed/cancelled rows are excluded so the user can retry after failure.
CREATE UNIQUE INDEX idx_purchase_intents_active_unique
  ON public.event_purchase_intents (event_id, user_id)
  WHERE status IN ('pending_payment', 'succeeded');

-- Supporting indexes
CREATE INDEX idx_purchase_intents_event_id
  ON public.event_purchase_intents (event_id);

CREATE INDEX idx_purchase_intents_user_id
  ON public.event_purchase_intents (user_id);

CREATE INDEX idx_purchase_intents_stripe_pi_id
  ON public.event_purchase_intents (stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- Used by the cleanup job that expires stale holds
CREATE INDEX idx_purchase_intents_hold_expires
  ON public.event_purchase_intents (hold_expires_at)
  WHERE status = 'pending_payment';

-- -----------------------------------------------------------
-- TABLE: stripe_webhook_events
--
-- Idempotency log + audit trail for all Stripe webhook events
-- received by the stripe_webhook edge function.  The unique
-- constraint on stripe_event_id prevents double-processing.
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.stripe_webhook_events (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  stripe_event_id     TEXT        NOT NULL UNIQUE,
  event_type          TEXT        NOT NULL,
  purchase_intent_id  UUID        REFERENCES public.event_purchase_intents(id) ON DELETE SET NULL,
  -- processed = FALSE means the record was inserted but business logic
  -- has not yet completed (e.g., previous attempt failed).  Stripe will
  -- retry → edge function detects processed = FALSE and re-runs logic.
  processed           BOOLEAN     NOT NULL DEFAULT FALSE,
  processed_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_stripe_webhook_events_purchase_id
  ON public.stripe_webhook_events (purchase_intent_id)
  WHERE purchase_intent_id IS NOT NULL;

-- =============================================================
-- ROW LEVEL SECURITY
-- =============================================================

-- -----------------------------------------------------------
-- RLS: event_purchase_intents
-- -----------------------------------------------------------
ALTER TABLE public.event_purchase_intents ENABLE ROW LEVEL SECURITY;

-- Users can read their own purchase intents (to poll status in Flutter).
-- Admins can read all (for support / reconciliation).
-- Event creators can see intents for their events (to know who's paying).
CREATE POLICY "purchase_intents: own or admin read"
  ON public.event_purchase_intents FOR SELECT
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
    OR EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id AND e.creator_id = auth.uid()
    )
  );

-- NO INSERT policy for authenticated clients.
-- Inserts are performed exclusively by the create_payment_intent edge function
-- via the service role key (bypasses RLS) through reserve_seat_if_available().

-- NO UPDATE policy for authenticated clients.
-- Updates are performed exclusively by edge functions via service role.

-- NO DELETE policy.  Records are never deleted; they transition through statuses.

-- -----------------------------------------------------------
-- RLS: stripe_webhook_events
-- No client access.  Read-only for admins (audit / debugging).
-- -----------------------------------------------------------
ALTER TABLE public.stripe_webhook_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "webhook_events: admin read only"
  ON public.stripe_webhook_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  );

-- No INSERT/UPDATE/DELETE policies for any client role.
-- All writes are performed by the stripe_webhook edge function via service role.

-- =============================================================
-- PATCH: event_rsvps INSERT policy
--
-- The original policy allowed any authenticated user to INSERT an RSVP
-- for any approved event.  This must be tightened so that paid events
-- (price_cents > 0) can only receive RSVPs through the confirm_paid_rsvp()
-- SECURITY DEFINER function (called by the webhook handler with service role).
--
-- A user calling the REST API directly:
--   POST /rest/v1/event_rsvps body={"event_id":"…","user_id":"…"}
-- for a paid event will receive HTTP 403 (new row violates RLS policy).
-- =============================================================
DROP POLICY IF EXISTS "rsvps: authenticated insert own" ON public.event_rsvps;

-- Replacement: identical to original but with the additional guard
-- that the event must be free (price_cents = 0).
CREATE POLICY "rsvps: authenticated insert own (free events only)"
  ON public.event_rsvps FOR INSERT
  WITH CHECK (
    -- Must be inserting for yourself
    auth.uid() = user_id
    -- Event must be approved AND free
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.status = 'approved'
        AND e.price_cents = 0
    )
  );

-- =============================================================
-- END OF MIGRATION 003
-- =============================================================
