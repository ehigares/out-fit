# Out-Fit MVP

Bay Area outdoor fitness events and clubs — Flutter + Supabase MVP.

> **Active branch:** `claude/stripe-payment-integration-I1w1K` — Sprint 2: Stripe payment integration (backend-first).

---

## Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| Mobile | Flutter (Android + iOS) | Cross-platform, single codebase |
| Backend | Supabase (Auth + Postgres + RLS) | Managed DB + auth + real-time ready |
| State | Riverpod 2 | Strong typing, async support, testable |
| Navigation | go_router | Declarative, deep-link ready |

---

## Project Setup

### 1. Prerequisites

- Flutter SDK ≥ 3.3.0 ([install](https://docs.flutter.dev/get-started/install))
- A [Supabase](https://supabase.com) project (free tier works)
- `git`

### 2. Clone and install

```bash
git clone https://github.com/ehigares/out-fit.git
cd out-fit
git checkout mvp-sprint-1        # ← primary working branch (Sprint 1 + hardening)

# Generate Flutter platform files (Android + iOS stubs)
flutter create . --project-name out_fit --org com.outfit

# Install Dart dependencies
flutter pub get
```

> **Branch history:**
> `claude/scaffold-flutter-supabase-mvp-kAl8F` is the original scaffold branch
> (preserved as provenance). All active development is on `mvp-sprint-1`.

### 3. Configure environment

```bash
cp .env.example .env
# Edit .env with your Supabase project URL and anon key
```

```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=your-anon-public-key
```

> **Never commit `.env`** — it's in `.gitignore`.

### 4. Apply Supabase schema

Go to your Supabase project → **SQL Editor** → run each file **in order**:

```
supabase/migrations/001_initial_schema.sql   # tables, indexes, base RLS
supabase/migrations/002_rls_events_update_hardening.sql  # Sprint 1 hardening patch
```

Or use the Supabase CLI (runs all migrations in order):

```bash
supabase db push
```

### 5. Run the app

```bash
# Android
flutter run -d android

# iOS (Mac only)
flutter run -d ios

# Chrome (limited — Supabase auth works but some native features may differ)
flutter run -d chrome
```

---

## Architecture

```
lib/
├── main.dart                       # Entry point — init Supabase + dotenv
├── app.dart                        # MaterialApp.router
├── core/
│   ├── constants/app_constants.dart # Enums, categories, defaults
│   ├── theme/app_theme.dart         # Material 3 theme (forest green)
│   ├── router/app_router.dart       # go_router + auth guards
│   └── shell/main_shell.dart        # Bottom nav shell
├── shared/
│   └── models/                     # Pure data classes (fromJson/toJson)
│       ├── profile_model.dart
│       ├── club_model.dart
│       ├── event_model.dart
│       ├── rsvp_model.dart
│       └── review_model.dart
└── features/
    ├── auth/                        # Login + Signup
    ├── onboarding/                  # 4-step profile setup (18+ gate)
    ├── home/                        # Feed tabs: Nearby / Free / Paid / For You
    ├── clubs/                       # List, Detail, Create
    ├── events/                      # Detail, Create, RSVP attendees
    ├── reviews/                     # Submit/update review
    ├── profile/                     # User profile + my events
    └── admin/                       # Admin: approve/reject, manage users
```

---

## Key Features & Constraints

| Feature | Implemented |
|---|---|
| Email/password auth | ✅ |
| 18+ onboarding gate | ✅ — hard block, cannot skip |
| Phone number stored private | ✅ — never displayed to other users |
| Event approval workflow | ✅ — pending → approved/rejected by admin |
| Trusted host auto-publish | ✅ — DB trigger sets status=approved on insert |
| RSVP list private | ✅ — RLS + UI guard |
| Recommended feed | ✅ — deterministic preference filter (no ML) |
| Stripe payments | ✅ — Sprint 2: DB tables, RLS, edge functions, webhook idempotency |
| Pickup sports | ❌ — excluded per MVP spec (extensibility point in DB comment) |
| Social photo uploads | ❌ — excluded per MVP spec |
| Chat / DMs / Maps | ❌ — excluded per MVP spec |

---

## Supabase Schema

Tables: `profiles`, `clubs`, `events`, `event_rsvps`, `event_reviews`

View: `event_rating_summary`

### RLS Summary

| Table | Public read | Write |
|---|---|---|
| profiles | Own row + admin | Own row or admin |
| clubs | All rows | Owner or admin |
| events | Approved only; creator sees own; admin sees all | Creator insert; complex update rules |
| event_rsvps | **Private** — own + creator + admin only | Own only; only for approved events |
| event_reviews | Approved event reviews | Only attendees (RSVP required) |

---

## Manual Test Checklist (10+ steps)

Run these end-to-end to validate RLS and privacy:

### Auth
1. **Sign up** with a new email/password — confirm redirect to onboarding
2. **Complete onboarding** — confirm 18+ gate blocks progression if unchecked
3. **Sign out** and **sign in** — confirm redirect to home feed

### Events & Feed
4. **Create an event** as a non-trusted-host user — confirm status shows `pending` and event does NOT appear in public feed
5. **Approve the event** via admin panel — confirm it now appears in the home feed
6. **Filter the feed** by category — confirm only matching events appear
7. **View "For You" tab** — confirm events match your profile preferences

### RSVP Privacy (critical)
8. **RSVP to an approved event** as User A
9. **Sign in as User B** (not the host) → navigate to the event detail → confirm the "View Attendee List" button is NOT shown
10. **Attempt to directly fetch RSVPs via Supabase API** as User B:
    ```bash
    curl 'https://<project>.supabase.co/rest/v1/event_rsvps?event_id=eq.<id>' \
      -H 'apikey: <ANON_KEY>' \
      -H 'Authorization: Bearer <USER_B_JWT>'
    ```
    **Expected:** Empty array `[]` — RLS blocks the query.
11. **Sign in as the event creator** → confirm attendee list IS visible with names only (no phone numbers)
12. **Sign in as admin** → confirm attendee list is visible with email column shown

### Reviews
13. **As User A (RSVP'd)** — submit a review for the event → confirm it appears on event detail
14. **As User B (not RSVP'd)** — attempt to post a review → confirm it's blocked (RLS INSERT policy requires an active RSVP)

### Admin
15. **As admin** — reject a pending event → confirm it disappears from admin queue and does not appear in public feed
16. **Toggle trusted host** for a user → create an event as that user → confirm it auto-publishes (status=approved immediately)

### Privacy Verification (confirmed by RLS)

**Q: How does RLS prevent non-host users from fetching RSVP lists?**

The `event_rsvps` table has this SELECT policy:
```sql
USING (
  auth.uid() = user_id                                 -- own RSVP only
  OR EXISTS (SELECT 1 FROM events WHERE id = event_id
             AND creator_id = auth.uid())              -- event creator
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()
             AND is_admin = TRUE)                      -- admin
)
```
A user who is neither the attendee, the host, nor an admin will receive an empty result set. This is enforced at the Postgres level — it cannot be bypassed by the Flutter client or direct API calls using the anon key.

**Q: How does RLS ensure only approved events appear in the public feed?**
```sql
USING (
  status = 'approved'          -- public: only approved
  OR auth.uid() = creator_id  -- creator sees their own
  OR ...admin...               -- admin sees all
)
```

---

## Sprint 1 Hardening — RLS Self-Approval Fix

Migration `002_rls_events_update_hardening.sql` replaces the single combined
UPDATE policy (which had no `WITH CHECK`) with three narrowly-scoped policies.

### What the vulnerability was

The original policy:
```sql
-- ❌ VULNERABLE — no WITH CHECK
CREATE POLICY "events: creator edit draft or pending"
  ON public.events FOR UPDATE
  USING (
    (auth.uid() = creator_id AND status IN ('draft', 'pending'))
    OR (auth.uid() = creator_id AND status = 'approved')
    OR EXISTS (admin check)
  );
```
`USING` only gates *which rows* the caller can touch. Without `WITH CHECK`,
it placed no restriction on *what values* the caller could write. A creator
could run:
```sql
UPDATE events SET status = 'approved', approved_by = auth.uid() WHERE id = '<their pending event>';
```
This bypassed the admin-only approval requirement.

### The fix — three separate policies

| Policy | USING (OLD row gate) | WITH CHECK (NEW row gate) |
|---|---|---|
| **Admin update any** | `is_admin = TRUE` | `is_admin = TRUE` |
| **Creator edit draft/pending** | `creator_id = uid AND status IN ('draft','pending')` | `status IN ('draft','pending') AND approved_by IS NULL AND approved_at IS NULL` |
| **Creator cancel approved** | `creator_id = uid AND status = 'approved'` | `status = 'cancelled' AND approved_by IS NOT NULL AND approved_at IS NOT NULL` |

### Verification test plan

**Setup:** two Supabase users — User A (non-admin) and Admin.

| Step | Actor | Action | Expected result |
|---|---|---|---|
| 1 | User A | Create event | Status = `pending` (set by DB trigger) |
| 2 | User A | `UPDATE events SET status='approved' WHERE id=...` | **Blocked** — Policy B `WITH CHECK`: `status` must stay in `('draft','pending')` |
| 3 | User A | `UPDATE events SET approved_by='<admin-uuid>' WHERE id=...` | **Blocked** — Policy B `WITH CHECK`: `approved_by IS NULL` violated |
| 4 | Admin | `UPDATE events SET status='approved', approved_by=uid, approved_at=now() WHERE id=...` | **Succeeds** — Policy A allows admins unrestricted updates |
| 5 | User A | `UPDATE events SET status='cancelled' WHERE id=...` (event now approved) | **Succeeds** — Policy C allows `status='cancelled'` for own approved events |
| 6 | User A | `UPDATE events SET status='approved' WHERE id=...` (re-approve attempt) | **Blocked** — Policy C `WITH CHECK`: `status` must be `'cancelled'` |
| 7 | User A | `UPDATE events SET approved_by=NULL WHERE id=...` (tamper) | **Blocked** — Policy C `WITH CHECK`: `approved_by IS NOT NULL` violated |

**Quick SQL smoke test** (run in Supabase SQL Editor logged in as each user):
```sql
-- As User A (should fail with: new row violates row-level security policy)
UPDATE events SET status = 'approved' WHERE id = '<your-pending-event-id>';

-- As Admin (should succeed: UPDATE 1)
UPDATE events
SET status = 'approved',
    approved_by = auth.uid(),
    approved_at = now()
WHERE id = '<your-pending-event-id>';

-- As User A on now-approved event (should succeed: UPDATE 1)
UPDATE events SET status = 'cancelled' WHERE id = '<your-approved-event-id>';
```

### Why this is complete protection

Postgres evaluates `WITH CHECK` **after** `USING`. Even if a creator's row
matches the `USING` condition, the `WITH CHECK` on the resulting row must
also pass. Since no non-admin policy has a `WITH CHECK` that allows
`status = 'approved'`, self-approval is impossible regardless of how the
HTTP request is constructed — including direct PostgREST API calls.

---

## Sprint 2 — Stripe Payment Integration

### Migration plan

| File | What it does |
|---|---|
| `001_initial_schema.sql` | Base tables, indexes, RLS (Sprint 1) |
| `002_rls_events_update_hardening.sql` | Self-approval exploit fix (Sprint 1 patch) |
| `003_stripe_tables_rls.sql` | `purchase_status` enum, `event_purchase_intents`, `stripe_webhook_events`, RLS for both tables, patches `event_rsvps` INSERT policy to block paid-event RSVPs from clients |
| `004_stripe_db_functions.sql` | `get_seats_used()`, `reserve_seat_if_available()`, `confirm_paid_rsvp()`, `release_purchase_hold()` — all SECURITY DEFINER; pg_cron schedule for expired hold cleanup |

### Edge functions

| Function | Auth | Purpose |
|---|---|---|
| `create_payment_intent` | JWT required | Validates event + capacity, creates hold, creates Stripe PI, returns `client_secret` |
| `stripe_webhook` | No JWT (Stripe HMAC) | Idempotently processes Stripe events → RSVP confirm or hold release |

### How paid RSVPs are created (only valid path)

```
Flutter                  Edge Functions            DB / Stripe
  │                           │                       │
  │── POST /create_payment_intent ──────────────────> │
  │                           │  reserve_seat_if_available() ─> hold row inserted
  │                           │  stripe.paymentIntents.create() ─> PI created
  │<─ { client_secret } ──────│
  │
  │── Stripe SDK .confirmPayment(client_secret) ────────────────> Stripe
  │                                                               │
  │             Stripe ──── POST /stripe_webhook ─────────────>  │
  │                           │  verify HMAC signature
  │                           │  idempotency check
  │                           │  confirm_paid_rsvp() ──> event_rsvps row inserted
  │                           │  mark webhook processed
  │                           │<── 200 OK ──────────────────────
```

Direct REST call to `POST /rest/v1/event_rsvps` for a paid event returns **HTTP 403** — the RLS policy `"rsvps: authenticated insert own (free events only)"` blocks it at the Postgres level.

### Stripe configuration

**Environment secrets** (set in Supabase Dashboard → Edge Functions → Secrets):

| Secret | Where to get it |
|---|---|
| `STRIPE_SECRET_KEY` | Stripe Dashboard → Developers → API Keys → Secret key |
| `STRIPE_WEBHOOK_SECRET` | Stripe Dashboard → Developers → Webhooks → (your endpoint) → Signing secret |

**Webhook endpoint to register in Stripe Dashboard:**

```
https://<project-ref>.supabase.co/functions/v1/stripe_webhook
```

**Stripe events to subscribe to:**

- `payment_intent.succeeded`
- `payment_intent.payment_failed`
- `payment_intent.canceled`
- `charge.refunded`

**Local testing with Stripe CLI:**

```bash
# Forward Stripe events to your local Supabase (or ngrok tunnel)
stripe listen --forward-to https://<project-ref>.supabase.co/functions/v1/stripe_webhook

# The CLI prints: "Your webhook signing secret is whsec_…"
# Set that as STRIPE_WEBHOOK_SECRET in your local .env
```

**pg_cron for expired hold cleanup:**

1. Enable pg_cron in Supabase Dashboard → Database → Extensions → pg_cron
2. Uncomment the `SELECT cron.schedule(...)` block at the bottom of `004_stripe_db_functions.sql` and re-run it

---

## Sprint 2 — Test Plan

### DB-level tests (run in Supabase SQL Editor)

**Test 1: Client cannot RSVP to a paid event directly**

```sql
-- As any authenticated user via anon key (replace UUIDs)
INSERT INTO event_rsvps (event_id, user_id, status)
VALUES ('<paid-event-id>', auth.uid(), 'going');
-- Expected: ERROR 42501 new row violates row-level security policy
```

**Test 2: Free event RSVPs still work**

```sql
INSERT INTO event_rsvps (event_id, user_id, status)
VALUES ('<free-event-id>', auth.uid(), 'going');
-- Expected: INSERT 1
```

**Test 3: Capacity is enforced atomically**

```sql
-- Simulate a full event (max_occupancy = 1, one active hold exists)
-- Call reserve_seat_if_available for a second user:
SELECT * FROM reserve_seat_if_available(
  '<event-id>',
  '<user-id-2>',
  1000,   -- amount_cents
  'USD',
  15
);
-- Expected: { success: false, error_code: 'at_capacity' }
```

**Test 4: Confirm paid RSVP (webhook success path)**

```sql
-- As service role / SQL Editor:
SELECT confirm_paid_rsvp('<purchase-intent-id>');
-- Expected: 'confirmed'

-- Verify RSVP exists:
SELECT * FROM event_rsvps WHERE event_id = '<event-id>';
-- Expected: row with status = 'going'

-- Idempotency: call again
SELECT confirm_paid_rsvp('<purchase-intent-id>');
-- Expected: 'already_confirmed' (no error, no duplicate RSVP)
```

**Test 5: Payment failure releases hold**

```sql
SELECT release_purchase_hold('<purchase-intent-id>', 'failed');
-- Expected: 'released'

-- Verify purchase status:
SELECT status FROM event_purchase_intents WHERE id = '<purchase-intent-id>';
-- Expected: 'failed'

-- Verify capacity is freed (seats_used decreased):
SELECT get_seats_used('<event-id>');
```

**Test 6: Refund cancels RSVP**

```sql
-- First confirm the RSVP:
SELECT confirm_paid_rsvp('<purchase-intent-id>');
-- Now refund:
SELECT release_purchase_hold('<purchase-intent-id>', 'refunded');
-- Expected: 'released'

-- Verify RSVP is now cancelled:
SELECT status FROM event_rsvps WHERE event_id = '<event-id>' AND user_id = '<user-id>';
-- Expected: 'cancelled'
```

### Webhook simulation (Stripe CLI)

```bash
# Test payment_intent.succeeded
stripe trigger payment_intent.succeeded \
  --add payment_intent:metadata.purchase_intent_id=<uuid>

# Test payment_intent.payment_failed
stripe trigger payment_intent.payment_failed \
  --add payment_intent:metadata.purchase_intent_id=<uuid>

# Verify after each trigger:
# SELECT * FROM event_purchase_intents WHERE id = '<uuid>';
# SELECT * FROM stripe_webhook_events ORDER BY created_at DESC LIMIT 5;
```

### Concurrent oversubscription test

Simulate two concurrent `reserve_seat_if_available` calls for an event with `max_occupancy = 1`:

```sql
-- In two separate transactions opened simultaneously:
-- Tx1: BEGIN; SELECT * FROM reserve_seat_if_available('<event-id>', '<user-1>', 1000, 'USD', 15);
-- Tx2: BEGIN; SELECT * FROM reserve_seat_if_available('<event-id>', '<user-2>', 1000, 'USD', 15);
-- One succeeds with success=true, the other returns error_code='at_capacity' or 'duplicate_purchase'.
-- Both commit.
-- Expected: exactly ONE event_purchase_intents row with status='pending_payment'.
```

---

---

## Extending the MVP

- **Geo queries**: Add PostGIS extension + `location GEOGRAPHY` column to `events` for true radius filtering
- **Pickup sports**: Add `pickup_sport` to `event_type` enum (see commented placeholder in SQL)
- **Push notifications**: Use Supabase Realtime + Firebase FCM
- **Photo uploads**: Add `avatar_url` to `profiles` and `cover_image_url` to `events`, use Supabase Storage

---

## Environment Variables Reference

| Variable | Description |
|---|---|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_ANON_KEY` | Public anon key (safe to use in client) |
| `STRIPE_SECRET_KEY` | Stripe secret key — server-side only, never in Flutter |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret — used by stripe_webhook edge function |

> The service role key and Stripe secret key are **never** used in the Flutter client. They are injected as Supabase Edge Function secrets at deploy time.
