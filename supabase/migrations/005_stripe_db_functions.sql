-- =============================================================
-- Out-Fit — Migration 004: Stripe DB Functions + Hold Cleanup
--
-- Adds:
--   • get_seats_used()              — safe capacity calculation
--   • reserve_seat_if_available()   — atomic hold + capacity check (SECURITY DEFINER)
--   • confirm_paid_rsvp()           — webhook success handler (SECURITY DEFINER)
--   • release_purchase_hold()       — webhook failure/cancel/refund (SECURITY DEFINER)
--   • pg_cron schedule for expiring stale holds (commented; enable pg_cron first)
--
-- All SECURITY DEFINER functions run as the DB owner (bypasses RLS).
-- They are the ONLY code paths permitted to insert paid RSVPs or mutate
-- purchase intent status.  The service-role edge functions call these via
-- adminClient.rpc() — no client JWT can call them with elevated privilege
-- because the DB role is always set by the SECURITY DEFINER declaration.
--
-- Apply AFTER 003_stripe_tables_rls.sql.
-- =============================================================

-- -----------------------------------------------------------
-- FUNCTION: get_seats_used(p_event_id)
--
-- Returns the number of seats currently occupied for an event:
--   confirmed RSVPs (status = 'going')
--   + active unexpired holds (status = 'pending_payment' AND hold_expires_at > NOW())
--
-- This is the authoritative seat count used before inserting a new hold.
-- STABLE means Postgres can cache the result within a single statement
-- (safe; called once per reserve_seat_if_available transaction).
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_seats_used(p_event_id UUID)
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    -- Confirmed attendees
    COALESCE(
      (SELECT COUNT(*)
       FROM public.event_rsvps
       WHERE event_id = p_event_id
         AND status = 'going'),
      0
    )
    +
    -- Active (non-expired) capacity holds
    COALESCE(
      (SELECT COUNT(*)
       FROM public.event_purchase_intents
       WHERE event_id = p_event_id
         AND status = 'pending_payment'
         AND hold_expires_at > NOW()),
      0
    );
$$;

-- -----------------------------------------------------------
-- FUNCTION: reserve_seat_if_available(...)
--
-- Atomically:
--   1. Locks the events row (FOR UPDATE) to serialize concurrent attempts.
--   2. Counts seats in use via get_seats_used().
--   3. If capacity available: inserts an event_purchase_intents row
--      (status = 'pending_payment') as a capacity hold.
--   4. Returns (success, purchase_intent_id, error_code).
--
-- The FOR UPDATE lock is held only for the duration of this function's
-- transaction, which completes before the edge function calls Stripe.
-- Subsequent capacity checks see the new hold row, preventing oversubscription
-- even after the lock is released.
--
-- Called exclusively by the create_payment_intent edge function via
-- service-role adminClient.rpc('reserve_seat_if_available', {...}).
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reserve_seat_if_available(
  p_event_id     UUID,
  p_user_id      UUID,
  p_amount_cents INT,
  p_currency     TEXT,
  p_hold_minutes INT DEFAULT 15
)
RETURNS TABLE (
  success            BOOLEAN,
  purchase_intent_id UUID,
  error_code         TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_occupancy INT;
  v_seats_used    BIGINT;
  v_purchase_id   UUID;
BEGIN
  -- Step 1: Lock the event row to serialize concurrent seat grabs.
  -- Any other call to reserve_seat_if_available for the same event will
  -- block here until this transaction commits or rolls back.
  SELECT max_occupancy INTO v_max_occupancy
  FROM public.events
  WHERE id = p_event_id
    AND status = 'approved'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'event_not_found'::TEXT;
    RETURN;
  END IF;

  -- Step 2: Count seats in use (RSVPs + unexpired holds).
  SELECT public.get_seats_used(p_event_id) INTO v_seats_used;

  IF v_seats_used >= v_max_occupancy THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'at_capacity'::TEXT;
    RETURN;
  END IF;

  -- Step 3: Insert the hold record.
  -- The partial unique index (event_id, user_id WHERE status IN
  -- ('pending_payment','succeeded')) prevents a user from holding two seats.
  BEGIN
    INSERT INTO public.event_purchase_intents (
      event_id,
      user_id,
      amount_cents,
      currency,
      status,
      hold_expires_at
    )
    VALUES (
      p_event_id,
      p_user_id,
      p_amount_cents,
      p_currency,
      'pending_payment',
      NOW() + (p_hold_minutes || ' minutes')::INTERVAL
    )
    RETURNING id INTO v_purchase_id;
  EXCEPTION WHEN unique_violation THEN
    -- User already has an active or succeeded purchase for this event.
    RETURN QUERY SELECT FALSE, NULL::UUID, 'duplicate_purchase'::TEXT;
    RETURN;
  END;

  RETURN QUERY SELECT TRUE, v_purchase_id, NULL::TEXT;
END;
$$;

-- -----------------------------------------------------------
-- FUNCTION: confirm_paid_rsvp(p_purchase_intent_id)
--
-- Called by the stripe_webhook edge function when Stripe fires
-- payment_intent.succeeded.
--
-- Atomically:
--   1. Locks the purchase intent row (FOR UPDATE).
--   2. If already 'succeeded': returns 'already_confirmed' (idempotent).
--   3. Updates purchase status → 'succeeded'.
--   4. Inserts (or upserts) the RSVP into event_rsvps.
--
-- SECURITY DEFINER allows this function to INSERT into event_rsvps for
-- paid events, bypassing the "free events only" RLS INSERT policy.
-- No authenticated client can trigger this directly; it is invoked
-- solely by the webhook edge function using the service-role key.
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirm_paid_rsvp(p_purchase_intent_id UUID)
RETURNS TEXT    -- 'confirmed' | 'already_confirmed' | 'not_found'
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id UUID;
  v_user_id  UUID;
  v_status   public.purchase_status;
BEGIN
  -- Lock the row to prevent concurrent confirmation (e.g., duplicate webhooks).
  SELECT event_id, user_id, status
  INTO   v_event_id, v_user_id, v_status
  FROM   public.event_purchase_intents
  WHERE  id = p_purchase_intent_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;

  -- Idempotent: payment already processed.
  IF v_status = 'succeeded' THEN
    RETURN 'already_confirmed';
  END IF;

  -- Transition purchase to succeeded.
  UPDATE public.event_purchase_intents
  SET    status     = 'succeeded',
         updated_at = NOW()
  WHERE  id = p_purchase_intent_id;

  -- Create the RSVP.  ON CONFLICT handles the edge case where an RSVP was
  -- manually inserted (e.g., admin action); we simply re-confirm it.
  INSERT INTO public.event_rsvps (event_id, user_id, status)
  VALUES (v_event_id, v_user_id, 'going')
  ON CONFLICT (event_id, user_id)
    DO UPDATE SET status = 'going';

  RETURN 'confirmed';
END;
$$;

-- -----------------------------------------------------------
-- FUNCTION: release_purchase_hold(p_purchase_intent_id, p_new_status)
--
-- Called by the stripe_webhook edge function for:
--   payment_intent.payment_failed  → p_new_status = 'failed'
--   payment_intent.canceled        → p_new_status = 'cancelled'
--   charge.refunded                → p_new_status = 'refunded'
--
-- For 'failed'/'cancelled': transitions from pending_payment → terminal state.
--   The hold row is marked terminal; get_seats_used() stops counting it,
--   releasing capacity for the next buyer.
--
-- For 'refunded': transitions from succeeded → refunded AND sets the
--   existing event_rsvps row to 'cancelled', removing the attendee.
--
-- Idempotent: safe to call multiple times for the same purchase.
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.release_purchase_hold(
  p_purchase_intent_id UUID,
  p_new_status         TEXT   -- 'failed' | 'cancelled' | 'refunded'
)
RETURNS TEXT    -- 'released' | 'already_released' | 'not_found' | 'invalid_status'
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status public.purchase_status;
  v_event_id       UUID;
  v_user_id        UUID;
  v_new_status     public.purchase_status;
BEGIN
  -- Validate requested terminal status.
  IF p_new_status NOT IN ('failed', 'cancelled', 'refunded') THEN
    RETURN 'invalid_status';
  END IF;

  v_new_status := p_new_status::public.purchase_status;

  -- Lock the row.
  SELECT status, event_id, user_id
  INTO   v_current_status, v_event_id, v_user_id
  FROM   public.event_purchase_intents
  WHERE  id = p_purchase_intent_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;

  -- Idempotent: already in a non-active terminal state.
  IF v_current_status IN ('failed', 'cancelled', 'refunded') THEN
    RETURN 'already_released';
  END IF;

  -- Transition to the requested terminal status.
  UPDATE public.event_purchase_intents
  SET    status     = v_new_status,
         updated_at = NOW()
  WHERE  id = p_purchase_intent_id;

  -- For refunds: the payment succeeded previously (RSVP exists).
  -- Cancel the RSVP to free the seat visually / for future reporting.
  IF p_new_status = 'refunded' THEN
    UPDATE public.event_rsvps
    SET    status = 'cancelled'
    WHERE  event_id = v_event_id
      AND  user_id  = v_user_id
      AND  status   = 'going';
  END IF;

  RETURN 'released';
END;
$$;

-- =============================================================
-- EXPIRED HOLD CLEANUP  (pg_cron — enable extension first)
--
-- get_seats_used() already excludes expired holds from the capacity
-- count, so stale pending_payment rows are harmless for correctness.
-- This job transitions them to 'cancelled' to keep the table clean and
-- make admin dashboards accurate.
--
-- To enable:
--   1. Enable the pg_cron extension in Supabase Dashboard →
--      Database → Extensions → pg_cron
--   2. Uncomment the SELECT cron.schedule(...) block below and re-run.
-- =============================================================

-- SELECT cron.schedule(
--   'expire-payment-holds',   -- job name (unique)
--   '* * * * *',              -- every minute
--   $$
--     UPDATE public.event_purchase_intents
--     SET    status     = 'cancelled',
--            updated_at = NOW()
--     WHERE  status         = 'pending_payment'
--       AND  hold_expires_at < NOW();
--   $$
-- );

-- =============================================================
-- END OF MIGRATION 004
-- =============================================================
