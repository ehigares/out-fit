-- 003_events_creator_id_autoset.sql
-- Ensures events.creator_id is always set to the authenticated user
-- and cannot be spoofed or changed after insert.

begin;

-- 1) Function to set creator_id on insert
create or replace function public.set_event_creator_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Always set creator_id to the authenticated user
  new.creator_id := auth.uid();
  return new;
end;
$$;

-- 2) Trigger: BEFORE INSERT sets creator_id
drop trigger if exists trg_set_event_creator_id on public.events;
create trigger trg_set_event_creator_id
before insert on public.events
for each row
execute function public.set_event_creator_id();

-- 3) Function to prevent creator_id changes
create or replace function public.prevent_event_creator_id_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.creator_id is distinct from old.creator_id then
    raise exception 'creator_id cannot be changed';
  end if;
  return new;
end;
$$;

-- 4) Trigger: BEFORE UPDATE blocks creator_id changes
drop trigger if exists trg_prevent_event_creator_id_change on public.events;
create trigger trg_prevent_event_creator_id_change
before update on public.events
for each row
execute function public.prevent_event_creator_id_change();

commit;
