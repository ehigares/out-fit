-- 003_events_creator_id_autoset.sql
-- Purpose:
-- 1) Auto-set events.creator_id = auth.uid() on INSERT (prevents spoofing, removes need for client to send creator_id)
-- 2) Adjust INSERT RLS policy to allow creator_id to be omitted (NULL) so trigger can populate it
-- 3) Optionally prevent changing creator_id on UPDATE

begin;

-- -------------------------------------------------------------------
-- 1) BEFORE INSERT trigger to set/overwrite creator_id
-- -------------------------------------------------------------------
create or replace function public.set_event_creator_id()
returns trigger
language plpgsql
as $$
begin
  -- Always set creator_id from the authenticated user.
  -- This prevents client spoofing and allows client to omit creator_id.
  new.creator_id := auth.uid();
  return new;
end;
$$;

drop trigger if exists trg_set_event_creator_id on public.events;

create trigger trg_set_event_creator_id
before insert on public.events
for each row
execute function public.set_event_creator_id();

-- -------------------------------------------------------------------
-- 2) Fix INSERT policy to allow inserts when creator_id is NULL (or matches auth.uid()).
--    This prevents RLS from blocking inserts when client omits creator_id.
-- -------------------------------------------------------------------
drop policy if exists "events: authenticated insert" on public.events;

create policy "events: authenticated insert"
on public.events
for insert
to authenticated
with check (
  -- allow inserts even if creator_id is omitted; trigger will set it to auth.uid()
  creator_id is null OR creator_id = auth.uid()
);

-- -------------------------------------------------------------------
-- 3) (Recommended) Prevent creator_id from being changed on UPDATE
--    We do this with a trigger so it’s enforced regardless of client behavior.
--    Admins can still change creator_id by temporarily disabling the trigger if ever needed,
--    but for MVP this is the safest default.
-- -------------------------------------------------------------------
create or replace function public.prevent_event_creator_id_change()
returns trigger
language plpgsql
as $$
begin
  if new.creator_id is distinct from old.creator_id then
    raise exception 'creator_id cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_event_creator_id_change on public.events;

create trigger trg_prevent_event_creator_id_change
before update on public.events
for each row
execute function public.prevent_event_creator_id_change();

commit;
