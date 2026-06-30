-- ============================================================================
-- Return idle units to their station
--
-- After a unit becomes Available, if no new incident is assigned within
-- IDLE_RETURN_MINUTES (5), snap its stored location back to its station — so
-- a unit that finished a job (and whose app may have stopped reporting GPS)
-- doesn't keep being measured from the last incident's coordinates forever.
--
-- Pieces:
--   * units.available_since  -> "idle since" clock, maintained by a trigger.
--   * return_idle_units_to_station()  -> the reset, run by pg_cron every minute.
-- ============================================================================

-- 1. Idle clock --------------------------------------------------------------
alter table public.units
    add column if not exists available_since timestamptz;

-- Maintain it on every status change:
--   * entering Available  -> stamp now()  (start the idle clock)
--   * leaving  Available  -> clear it     (it's working again)
-- Fires alphabetically AFTER units_auto_resolve, so on a resolve the status
-- has already been flipped to 'Available' by the time we read new.status.
create or replace function public.units_track_available_since()
returns trigger
language plpgsql
as $$
begin
    if new.status = 'Available'
       and (tg_op = 'INSERT' or old.status is distinct from 'Available') then
        new.available_since := now();
    elsif new.status <> 'Available' then
        new.available_since := null;
    end if;
    return new;
end
$$;

drop trigger if exists units_track_available_since on public.units;
create trigger units_track_available_since
    before insert or update of status on public.units
    for each row execute function public.units_track_available_since();

-- Backfill existing idle units so they're eligible right away.
update public.units set available_since = now()
 where status = 'Available' and available_since is null;

-- 2. The reset ---------------------------------------------------------------
-- Move only units that are genuinely idle and not already at their station.
-- Returns how many were moved (handy for logging / manual runs).
create or replace function public.return_idle_units_to_station()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
    v_moved int;
begin
    with moved as (
        update public.units u
           set current_latitude  = s.latitude,
               current_longitude = s.longitude,
               last_location_at  = now()
          from public.stations s
         where s.id = u.station_id
           and u.status = 'Available'
           and u.is_active
           and u.current_incident_id is null
           and u.available_since is not null
           and u.available_since < now() - interval '5 minutes'   -- IDLE_RETURN_MINUTES
           and (u.current_latitude  is distinct from s.latitude
             or u.current_longitude is distinct from s.longitude)
        returning u.id
    )
    select count(*) into v_moved from moved;
    return v_moved;
end
$$;

-- 3. Schedule it every minute via pg_cron ------------------------------------
-- pg_cron is available on Supabase (Database > Extensions, or this CREATE).
create extension if not exists pg_cron;

-- Replace any previous schedule with the same name, then (re)create it.
do $$
begin
    perform cron.unschedule('return-idle-units');
exception when others then
    null;   -- not scheduled yet
end
$$;

select cron.schedule(
    'return-idle-units',
    '* * * * *',                                   -- every minute
    $$ select public.return_idle_units_to_station(); $$
);
