-- =============================================================
-- Out-Fit MVP — Migration 002: Events UPDATE RLS Hardening
-- Fixes: single combined UPDATE policy lacked WITH CHECK,
--        allowing a creator to self-approve events by escalating
--        `status` from 'pending' → 'approved'.
--
-- Apply AFTER 001_initial_schema.sql.
-- Apply via: Supabase Dashboard > SQL Editor > Run
-- =============================================================

-- =============================================================
-- WHY THIS PATCH IS NEEDED
-- =============================================================
-- The original policy "events: creator edit draft or pending" had only
-- a USING clause. In Postgres RLS:
--   USING  → filters which OLD rows the operation is allowed to touch.
--   WITH CHECK → validates the NEW row values after the update.
-- Without WITH CHECK, a creator whose row passes USING (old status=pending)
-- could write any new values — including status='approved' and
-- approved_by='<their own uuid>' — effectively self-approving.
--
-- This migration drops the combined policy and replaces it with three
-- narrowly-scoped UPDATE policies:
--   A) Admin update any    — admins can change anything
--   B) Creator edit own draft/pending — restricted new-value check
--   C) Creator cancel own approved    — only status='cancelled' allowed
-- =============================================================

-- -----------------------------------------------------------
-- STEP 1: Drop the vulnerable combined policy
-- -----------------------------------------------------------
DROP POLICY IF EXISTS "events: creator edit draft or pending" ON public.events;

-- -----------------------------------------------------------
-- STEP 2: Policy A — Admin can update any event
--
-- USING     (OLD row gate): caller is admin
-- WITH CHECK (NEW row gate): caller is still admin
-- Admins may set status to any value, including 'approved'/'rejected',
-- and may write approved_by / approved_at.
-- -----------------------------------------------------------
CREATE POLICY "events: admin update any"
  ON public.events FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  );

-- -----------------------------------------------------------
-- STEP 3: Policy B — Creator edits their own DRAFT or PENDING event
--
-- USING     (OLD row): event is owned by caller AND is in draft/pending
-- WITH CHECK (NEW row):
--   • creator_id must remain unchanged (cannot re-assign event)
--   • status must stay in ('draft','pending') — cannot escalate to approved/rejected
--   • approved_by must be NULL — creator cannot pre-set approval metadata
--   • approved_at must be NULL — same guard
--
-- This is the primary self-approval prevention: even if the caller
-- updates a pending event, they cannot write status='approved'.
-- -----------------------------------------------------------
CREATE POLICY "events: creator edit own draft or pending"
  ON public.events FOR UPDATE
  USING (
    auth.uid() = creator_id
    AND status IN ('draft', 'pending')
  )
  WITH CHECK (
    auth.uid() = creator_id
    AND status IN ('draft', 'pending')
    AND approved_by IS NULL
    AND approved_at IS NULL
  );

-- -----------------------------------------------------------
-- STEP 4: Policy C — Creator cancels their own APPROVED event
--
-- USING     (OLD row): event is owned by caller AND is currently approved
-- WITH CHECK (NEW row):
--   • creator_id unchanged
--   • status must be exactly 'cancelled' — no other transition allowed
--   • approved_by must remain non-null (cannot erase admin's approval record)
--   • approved_at must remain non-null (same)
--
-- Note on IS NOT DISTINCT FROM: In Postgres RLS WITH CHECK, only NEW row
-- values are visible, not OLD. We use IS NOT NULL to assert the admin-set
-- metadata is preserved. Since USING already confirmed OLD status='approved',
-- an approved event always has approved_by/approved_at set (by trigger for
-- trusted hosts, or by admin action for others), so IS NOT NULL is correct.
-- -----------------------------------------------------------
CREATE POLICY "events: creator cancel own approved"
  ON public.events FOR UPDATE
  USING (
    auth.uid() = creator_id
    AND status = 'approved'
  )
  WITH CHECK (
    auth.uid() = creator_id
    AND status = 'cancelled'
    -- Prevent creator from wiping admin-set approval metadata
    AND approved_by IS NOT NULL
    AND approved_at IS NOT NULL
  );

-- =============================================================
-- VERIFICATION GUIDE
-- =============================================================
-- See README.md §"Sprint 1 Hardening — RLS Verification" for the
-- full test plan. Quick SQL smoke tests:
--
-- 1. As non-admin creator (replace UUIDs as appropriate):
--    UPDATE events SET status = 'approved' WHERE id = '<pending-event-id>';
--    → Expected: ERROR 42501 new row violates row-level security policy
--
-- 2. As admin:
--    UPDATE events SET status = 'approved',
--      approved_by = auth.uid(), approved_at = now()
--      WHERE id = '<pending-event-id>';
--    → Expected: UPDATE 1
--
-- 3. As creator of an approved event:
--    UPDATE events SET status = 'cancelled' WHERE id = '<approved-event-id>';
--    → Expected: UPDATE 1   (cancellation succeeds)
--
-- 4. As creator of an approved event attempting self-re-approval:
--    UPDATE events SET status = 'approved' WHERE id = '<approved-event-id>';
--    → Expected: ERROR 42501 (Policy C WITH CHECK: status must be 'cancelled')
-- =============================================================
