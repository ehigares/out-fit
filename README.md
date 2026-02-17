# Out-Fit MVP

Bay Area outdoor fitness events and clubs — Flutter + Supabase MVP.

> Sprint 1 scaffold: auth, profile onboarding, clubs, events, home feed, RSVP (private), reviews, and admin approval workflow.

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
git checkout claude/scaffold-flutter-supabase-mvp-kAl8F

# Generate Flutter platform files (Android + iOS stubs)
flutter create . --project-name out_fit --org com.outfit

# Install Dart dependencies
flutter pub get
```

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

Go to your Supabase project → **SQL Editor** → paste and run:

```
supabase/migrations/001_initial_schema.sql
```

Or use the Supabase CLI:

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
| Stripe payments | ⏳ — price field exists, UI placeholder shown |
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

## Payment Integration (deferred)

- `price_cents INT DEFAULT 0` column is present on `events`
- `currency TEXT DEFAULT 'USD'` column is present
- The UI shows a "Payment coming soon" placeholder for paid events
- To complete: integrate `stripe_flutter`, add `payment_intents` table, implement Stripe webhook in a Supabase Edge Function

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

> The service role key is **never** used in the Flutter client. If you need server-side operations, use Supabase Edge Functions.
