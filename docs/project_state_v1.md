# 📘 Out-Fit — Project State Document (v1)
**Last Updated:** 2026-02-18
**Branch:** mvp-sprint-1
**Repo:** ehigares/out-fit
**Environment:** Supabase (Production project created)
---
# 1️⃣ Product Overview
## Product Name
Out-Fit
## Core Vision
Out-Fit is a mobile-first social fitness coordination platform that enables adults (18+) to:
- Discover local run clubs, hiking groups, cycling clubs, outdoor yoga, and fitness events
- Host their own structured outdoor workouts
- RSVP securely
- Build credibility as a host
- Participate in both free and paid events
Initial geographic focus: Bay Area (California)
---
# 2️⃣ MVP Scope (Current)
## Included in MVP
### User Accounts
- Supabase Auth (email/password)
- Profiles table
- 18+ required
- Location preferences
- Workout preferences
- Intensity preferences
- Equipment preferences
### Events
- Create events
- Admin approval system
- Host cancellation allowed
- Paid or free flag (price_cents)
- Category classification (running, cycling, etc.)
- Skill level + intensity
- Equipment required
- Max occupancy
- RSVP system (private list)
### Clubs
- Database-level support exists
- Club association via club_id
- Future expansion planned
### Security
- RLS fully enabled
- Self-approval exploit eliminated
- Creator spoofing prevented
- Private RSVP enforcement
- Admin capability separated via policy
### Host Moderation
- New hosts require approval
- Trusted hosts auto-approve (via profile flag)
- Admin approval required otherwise
---
# 3️⃣ Explicitly Out of Scope (For Now)
- Pickup sports module (deferred)
- Photo uploads
- Push notifications
- Recommendation engine v2
- Messaging system
- Stripe payments (not yet implemented)
- Web app (mobile-first only)
---
# 4️⃣ Technical Architecture
## Frontend
- Flutter
- Riverpod state management
- Supabase client SDK
## Backend
- Supabase
  - Postgres
  - RLS policies
  - Auth
  - Triggers
  - Migrations stored in repo
## Branch Strategy
- main → stable production
- mvp-sprint-1 → active development
- claude/... → scaffold history
---
# 5️⃣ Database Architecture Snapshot
## Core Tables
### profiles
- id (UUID, matches auth.users)
- email
- is_admin
- is_trusted_host
- is_18_plus
- workout_preferences[]
- intensity_preferences[]
- equipment_preferences[]
- location_mode
- radius_miles
### events
- id
- creator_id
- club_id
- title
- location_text
- starts_at
- ends_at
- price_cents
- currency
- category
- max_occupancy
- overview
- equipment_needed[]
- skill_level
- intensity_level
- status
- approved_by
- approved_at
- created_at
- updated_at
### event_rsvps
- event_id
- user_id
### event_reviews
- event_id
- reviewer_id
- rating
- comment
---
# 6️⃣ Migration History
## 001_initial_schema.sql
- Base schema
- Initial RLS
- Tables
- Core policies
## 002_rls_events_update_hardening.sql
- Split UPDATE policies
- Eliminated self-approval exploit
- Added WITH CHECK enforcement
- Explicit admin update policy
## 003_events_creator_id_autoset.sql
- BEFORE INSERT trigger: creator_id = auth.uid()
- Prevent creator spoofing
- Prevent creator_id updates
- Fixed INSERT RLS to allow null + trigger population
---
# 7️⃣ Security Posture (Verified)
## Real-World RLS Test Completed
✔ User creates event → status pending
✔ User cannot self-approve (blocked)
✔ Admin can approve
✔ Creator can cancel approved
✔ Approval metadata cannot be wiped
✔ creator_id cannot be spoofed
✔ Profiles recursion bug fixed
✔ RLS enforced via REST API (not just UI)
---
# 8️⃣ Architectural Principles
1. All security enforced at DB layer
2. Client is never trusted
3. creator_id never provided by client
4. Admin power explicitly defined
5. Approval metadata immutable post-approval
6. Every schema change stored as migration
7. GitHub is source of truth
8. Supabase is runtime
---
# 9️⃣ Known Gaps / Next Milestones
## Sprint 2 (Next Target)
Stripe Payment Integration
Must include:
- Payment intent creation
- Webhook validation
- Occupancy protection
- Prevent RSVP bypass
- Handle free vs paid events cleanly
## Sprint 3
- Recommendation engine v1
- Location radius filtering improvements
- Host credibility scoring
---
# 🔟 Current Development State
- Repo synchronized
- Supabase project configured
- Migrations applied
- RLS validated
- Local dev working
- Ready for feature expansion
