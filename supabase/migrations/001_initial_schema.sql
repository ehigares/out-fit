-- =============================================================
-- Out-Fit MVP — Initial Supabase Schema + RLS Policies
-- Apply via: Supabase Dashboard > SQL Editor > Run
-- Or: supabase db push (if using Supabase CLI)
-- =============================================================

-- -----------------------------------------------------------
-- EXTENSIONS
-- -----------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -----------------------------------------------------------
-- HELPER: auto-update updated_at
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------
-- TABLE: profiles
-- References auth.users (managed by Supabase Auth)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id                    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name             TEXT NOT NULL,
  email                 TEXT NOT NULL,
  -- Phone is private: NEVER exposed in public queries or join results
  phone_private         TEXT NOT NULL,
  is_18_plus            BOOLEAN NOT NULL DEFAULT FALSE,
  home_location_label   TEXT,
  location_mode         TEXT NOT NULL DEFAULT 'radius'
                        CHECK (location_mode IN ('radius', 'city', 'state')),
  radius_miles          INT,
  city                  TEXT,
  state                 TEXT,
  workout_preferences   TEXT[] NOT NULL DEFAULT '{}',
  intensity_preferences TEXT[] NOT NULL DEFAULT '{}',
  equipment_preferences TEXT[] NOT NULL DEFAULT '{}',
  -- Admin and host flags — toggled manually by DB admin or via admin UI
  is_admin              BOOLEAN NOT NULL DEFAULT FALSE,
  is_trusted_host       BOOLEAN NOT NULL DEFAULT FALSE,
  verification_badge    TEXT NOT NULL DEFAULT 'none'
                        CHECK (verification_badge IN ('none', 'verified')),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- -----------------------------------------------------------
-- TABLE: clubs
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.clubs (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id          UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  description       TEXT,
  primary_category  TEXT,
  home_base_location TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_clubs_updated_at
  BEFORE UPDATE ON public.clubs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- -----------------------------------------------------------
-- TABLE: events
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.events (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  creator_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  club_id         UUID REFERENCES public.clubs(id) ON DELETE SET NULL,
  title           TEXT NOT NULL,
  location_text   TEXT NOT NULL,
  starts_at       TIMESTAMPTZ NOT NULL,
  ends_at         TIMESTAMPTZ,
  price_cents     INT NOT NULL DEFAULT 0 CHECK (price_cents >= 0),
  currency        TEXT NOT NULL DEFAULT 'USD',
  category        TEXT NOT NULL,
  max_occupancy   INT NOT NULL CHECK (max_occupancy > 0),
  overview        TEXT NOT NULL,
  equipment_needed TEXT[] NOT NULL DEFAULT '{}',
  skill_level     TEXT NOT NULL CHECK (skill_level IN ('beginner', 'intermediate', 'advanced')),
  intensity_level TEXT NOT NULL CHECK (intensity_level IN ('low', 'medium', 'high')),
  -- status is set by trigger on insert based on creator's trusted_host flag
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('draft', 'pending', 'approved', 'rejected', 'cancelled')),
  approved_by     UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_at     TIMESTAMPTZ,
  -- event_type placeholder for future pickup sports extensibility
  -- event_type TEXT NOT NULL DEFAULT 'fitness' CHECK (event_type IN ('fitness')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_events_updated_at
  BEFORE UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Trigger: auto-set event status on INSERT based on creator's trusted_host flag
CREATE OR REPLACE FUNCTION public.set_event_status_on_insert()
RETURNS TRIGGER AS $$
DECLARE
  creator_is_trusted BOOLEAN;
BEGIN
  SELECT is_trusted_host INTO creator_is_trusted
    FROM public.profiles
    WHERE id = NEW.creator_id;

  IF creator_is_trusted IS TRUE THEN
    NEW.status := 'approved';
    NEW.approved_by := NEW.creator_id;
    NEW.approved_at := NOW();
  ELSE
    NEW.status := 'pending';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_set_event_status
  BEFORE INSERT ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.set_event_status_on_insert();

-- -----------------------------------------------------------
-- TABLE: event_rsvps
-- RSVP list is PRIVATE: only attendee, event creator, and admins can see it.
-- This is enforced via RLS below.
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_rsvps (
  id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id  UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status    TEXT NOT NULL DEFAULT 'going' CHECK (status IN ('going', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (event_id, user_id)
);

-- -----------------------------------------------------------
-- TABLE: event_reviews
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_reviews (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id    UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  reviewer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating      INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (event_id, reviewer_id)
);

-- -----------------------------------------------------------
-- VIEW: event_rating_summary
-- -----------------------------------------------------------
CREATE OR REPLACE VIEW public.event_rating_summary AS
SELECT
  event_id,
  ROUND(AVG(rating)::NUMERIC, 1) AS avg_rating,
  COUNT(*)                        AS review_count
FROM public.event_reviews
GROUP BY event_id;

-- -----------------------------------------------------------
-- INDEXES (performance)
-- -----------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_events_status         ON public.events(status);
CREATE INDEX IF NOT EXISTS idx_events_starts_at      ON public.events(starts_at);
CREATE INDEX IF NOT EXISTS idx_events_creator_id     ON public.events(creator_id);
CREATE INDEX IF NOT EXISTS idx_event_rsvps_event_id  ON public.event_rsvps(event_id);
CREATE INDEX IF NOT EXISTS idx_event_rsvps_user_id   ON public.event_rsvps(user_id);
CREATE INDEX IF NOT EXISTS idx_event_reviews_event_id ON public.event_reviews(event_id);

-- =============================================================
-- ROW LEVEL SECURITY
-- =============================================================

-- -----------------------------------------------------------
-- RLS: profiles
-- -----------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Users can read their own profile; admins can read all profiles.
-- NOTE: phone_private is in this table — non-admin users only access their own row.
CREATE POLICY "profiles: own row read"
  ON public.profiles FOR SELECT
  USING (
    auth.uid() = id
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  );

-- Users can insert their own profile (id must match auth.uid())
CREATE POLICY "profiles: own row insert"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Users can update their own profile; admins can update any profile
CREATE POLICY "profiles: own row update"
  ON public.profiles FOR UPDATE
  USING (
    auth.uid() = id
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  )
  WITH CHECK (
    auth.uid() = id
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  );

-- -----------------------------------------------------------
-- RLS: clubs
-- Public read; owner or admin can write.
-- -----------------------------------------------------------
ALTER TABLE public.clubs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "clubs: public read"
  ON public.clubs FOR SELECT
  USING (TRUE);

CREATE POLICY "clubs: authenticated insert"
  ON public.clubs FOR INSERT
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "clubs: owner or admin update"
  ON public.clubs FOR UPDATE
  USING (
    auth.uid() = owner_id
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  );

CREATE POLICY "clubs: owner or admin delete"
  ON public.clubs FOR DELETE
  USING (
    auth.uid() = owner_id
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  );

-- -----------------------------------------------------------
-- RLS: events
-- Public read ONLY for approved events.
-- Creator reads their own events regardless of status.
-- Admins read all events.
-- -----------------------------------------------------------
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- SELECT: approved events are public; creator sees own; admins see all
CREATE POLICY "events: read approved or own or admin"
  ON public.events FOR SELECT
  USING (
    status = 'approved'
    OR auth.uid() = creator_id
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  );

-- INSERT: authenticated users; status will be auto-set by trigger
CREATE POLICY "events: authenticated insert"
  ON public.events FOR INSERT
  WITH CHECK (auth.uid() = creator_id);

-- UPDATE:
--   creator can edit draft/pending events (not approved/rejected by others)
--   admin can approve/reject (change status to approved/rejected)
--   creator can cancel their own approved events
CREATE POLICY "events: creator edit draft or pending"
  ON public.events FOR UPDATE
  USING (
    -- Creator edits draft or pending
    (auth.uid() = creator_id AND status IN ('draft', 'pending'))
    -- Creator cancels their own approved event
    OR (auth.uid() = creator_id AND status = 'approved')
    -- Admin can update any event (approve/reject/etc.)
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  );

-- DELETE: only admin can delete events
CREATE POLICY "events: admin delete"
  ON public.events FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  );

-- -----------------------------------------------------------
-- RLS: event_rsvps
-- CRITICAL PRIVACY: RSVP list is NOT public.
-- Only: the attendee themselves, the event creator, and admins.
-- -----------------------------------------------------------
ALTER TABLE public.event_rsvps ENABLE ROW LEVEL SECURITY;

-- SELECT: own RSVPs, or event creator's event RSVPs, or admins
CREATE POLICY "rsvps: private read — own, creator, admin"
  ON public.event_rsvps FOR SELECT
  USING (
    -- The RSVP owner
    auth.uid() = user_id
    -- The event creator (host)
    OR EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id AND e.creator_id = auth.uid()
    )
    -- Admins
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_admin = TRUE
    )
  );

-- INSERT: authenticated users may RSVP to approved events for themselves
CREATE POLICY "rsvps: authenticated insert own"
  ON public.event_rsvps FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id AND e.status = 'approved'
    )
  );

-- UPDATE: only own RSVP (e.g., cancel)
CREATE POLICY "rsvps: own update"
  ON public.event_rsvps FOR UPDATE
  USING (auth.uid() = user_id);

-- DELETE: own RSVP only
CREATE POLICY "rsvps: own delete"
  ON public.event_rsvps FOR DELETE
  USING (auth.uid() = user_id);

-- -----------------------------------------------------------
-- RLS: event_reviews
-- Any user can read reviews for approved events.
-- Only attendees (RSVP exists) can create a review.
-- -----------------------------------------------------------
ALTER TABLE public.event_reviews ENABLE ROW LEVEL SECURITY;

-- SELECT: anyone can read reviews for approved events
CREATE POLICY "reviews: read for approved events"
  ON public.event_reviews FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id AND e.status = 'approved'
    )
  );

-- INSERT: only if the reviewer has an active RSVP for this event
CREATE POLICY "reviews: only attendees can review"
  ON public.event_reviews FOR INSERT
  WITH CHECK (
    auth.uid() = reviewer_id
    AND EXISTS (
      SELECT 1 FROM public.event_rsvps r
      WHERE r.event_id = event_id
        AND r.user_id = auth.uid()
        AND r.status = 'going'
    )
  );

-- UPDATE: only own review
CREATE POLICY "reviews: own update"
  ON public.event_reviews FOR UPDATE
  USING (auth.uid() = reviewer_id);

-- DELETE: only own review
CREATE POLICY "reviews: own delete"
  ON public.event_reviews FOR DELETE
  USING (auth.uid() = reviewer_id);

-- =============================================================
-- SEED DATA (optional — categories reference only; no real rows)
-- =============================================================
-- Default region in app code: "Bay Area, CA"
-- No seed rows needed for MVP; categories are defined as app constants.

-- =============================================================
-- END OF MIGRATION
-- =============================================================
