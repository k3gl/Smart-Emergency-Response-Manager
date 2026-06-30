-- ============================================================================
-- Centralized dispatch queue
--
-- Introduces ONE global queue shared by all stations for incidents that
-- cannot be assigned immediately, plus the dispatch engine that decides
-- which unit serves which incident.
--
-- Separation of concerns (mirrors the design spec):
--   * dispatch_queue (table + priority index)   -> "which incident first?"
--       ordered by severity (highest first) then age (oldest first).
--   * dispatch_available_unit() / request_dispatch() (engine functions)
--                                                -> "which unit serves which?"
--       nearest candidate; ties broken by oldest.
--   * _perform_dispatch()  -> the commit step (writes the dispatch rows and
--                             flips the statuses).
--   * units_dispatch_after_available (trigger) -> the event wiring:
--       the instant a unit becomes Available, the engine runs automatically.
--
-- The queue stores DEMANDS (incident x required unit type), not bare
-- incidents: an incident may need POLICE *and* FIRE; one can be filled while
-- the other waits.  This is required because a unit can only serve incidents
-- matching its type, and keeps the model correct as more stations/units are
-- added.
--
-- All engine functions are SECURITY DEFINER: the "unit became Available"
-- trigger fires while a Unit is updating its OWN row, but the engine must be
-- able to write incident_dispatches and update OTHER units, which a Unit's
-- RLS forbids.  Running as the function owner bypasses that safely because
-- the logic itself is fixed.
-- ============================================================================

-- 1. Priority helper: a single source of truth for "how urgent is this?" -----
--    The AI emits exactly three levels (LOW / URGENT / CRITICAL); higher rank
--    = served first.  FAKE / unknown rank 0 and never gets queued.
create or replace function public.severity_rank(sev text)
returns int
language sql
immutable
as $$
  select case upper(coalesce(sev, ''))
    when 'CRITICAL' then 3
    when 'URGENT'   then 2
    when 'LOW'      then 1
    else 0                   -- unknown / FAKE never gets queued (rank 0)
  end
$$;

-- 2. Great-circle distance, in SQL, so the engine can rank candidates --------
--    without round-tripping to the app.  Matches the app/worker constants
--    (ROAD_FACTOR 1.3, AVG_CITY_SPEED 30km/h are applied at commit time).
create or replace function public.haversine_km(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision)
returns double precision
language sql
immutable
as $$
  select 2 * 6371.0 * asin(sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2) +
      cos(radians(lat1)) * cos(radians(lat2)) *
      power(sin(radians(lng2 - lng1) / 2), 2)
  ))
$$;

-- 3. The global queue --------------------------------------------------------
create table if not exists public.dispatch_queue (
    id                 uuid primary key default gen_random_uuid(),
    incident_id        uuid not null references public.incidents (id) on delete cascade,
    required_unit_type text not null check (required_unit_type in ('POLICE','AMBULANCE','FIRE')),
    severity_rank      int  not null,            -- denormalized at enqueue time for fast ordering
    enqueued_at        timestamptz not null default now(),
    -- An incident never needs two units of the same type from the queue at
    -- once; this also makes enqueue idempotent.
    unique (incident_id, required_unit_type)
);

-- The priority index: highest severity first, then oldest first.  Scoped by
-- type because the engine only ever scans one type at a time.
create index if not exists dispatch_queue_priority_idx
    on public.dispatch_queue (required_unit_type, severity_rank desc, enqueued_at asc);

-- 4. Commit step: actually dispatch p_unit to p_incident ---------------------
--    Writes the junction row, marks the unit Assigned, and promotes the
--    incident.  Idempotent on the dispatch row.
create or replace function public._perform_dispatch(p_unit_id uuid, p_incident_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_ilat double precision; v_ilng double precision;
    v_ulat double precision; v_ulng double precision;
    v_dist numeric;          -- approx road km
    v_eta  int;              -- approx minutes
begin
    select latitude, longitude into v_ilat, v_ilng
      from public.incidents where id = p_incident_id;

    -- Prefer the unit's live GPS; fall back to its station coordinates.
    select coalesce(u.current_latitude,  s.latitude),
           coalesce(u.current_longitude, s.longitude)
      into v_ulat, v_ulng
      from public.units u
      left join public.stations s on s.id = u.station_id
     where u.id = p_unit_id;

    v_dist := round((public.haversine_km(v_ulat, v_ulng, v_ilat, v_ilng) * 1.3)::numeric, 2);
    v_eta  := round((v_dist / 30.0) * 60.0);

    insert into public.incident_dispatches (incident_id, unit_id, distance_km, eta_minutes)
    values (p_incident_id, p_unit_id, v_dist, v_eta)
    on conflict do nothing;

    update public.units
       set status = 'Assigned', current_incident_id = p_incident_id
     where id = p_unit_id;

    -- Promote the incident.  Keep the first (primary) unit's ETA/distance.
    update public.incidents
       set status           = 'Assigned',
           assigned_unit_id = coalesce(assigned_unit_id, p_unit_id),
           eta_minutes      = coalesce(eta_minutes, v_eta),
           distance_km      = coalesce(distance_km, v_dist),
           assigned_at      = coalesce(assigned_at, now())
     where id = p_incident_id;
end
$$;

-- 5. INCIDENT-driven entry: "a new incident needs a unit of type T" ----------
--    Find the nearest available unit of that type, regardless of station.
--    If one exists -> dispatch immediately (NOT queued).
--    Otherwise     -> add the demand to the global queue (waiting).
--    Returns true if dispatched, false if queued.
create or replace function public.request_dispatch(p_incident_id uuid, p_unit_type text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_ilat double precision; v_ilng double precision;
    v_unit uuid;
begin
    select latitude, longitude into v_ilat, v_ilng
      from public.incidents where id = p_incident_id;

    -- Nearest Available, active unit of the required type, across ALL stations.
    select u.id into v_unit
      from public.units u
      left join public.stations s on s.id = u.station_id
     where u.status = 'Available'
       and u.is_active
       and u.unit_type = p_unit_type
     order by public.haversine_km(
                coalesce(u.current_latitude,  s.latitude),
                coalesce(u.current_longitude, s.longitude),
                v_ilat, v_ilng) asc
     limit 1
     for update of u skip locked;   -- don't grab a unit another dispatch is taking

    if v_unit is not null then
        perform public._perform_dispatch(v_unit, p_incident_id);
        return true;
    end if;

    -- Nothing free: enqueue the unmet demand and mark the incident Queued.
    insert into public.dispatch_queue (incident_id, required_unit_type, severity_rank)
    select p_incident_id, p_unit_type,
           public.severity_rank((select severity from public.incidents where id = p_incident_id))
    on conflict (incident_id, required_unit_type) do nothing;

    update public.incidents
       set status = 'Queued'
     where id = p_incident_id
       and status not in ('Assigned','Resolved');

    return false;
end
$$;

-- 6. UNIT-driven entry: "this unit just became Available, give it work" -------
--    Implements the spec's Unit Availability Flow, steps 1-7:
--      1. look at the global queue
--      2. find the highest severity currently waiting for THIS unit's type
--      3. take only the incidents at that severity
--      4-5. nearest one to this unit
--      6. ties (very similar distance) -> oldest
--      7. dispatch + remove from queue
--    Returns true if it picked up an incident.
create or replace function public.dispatch_available_unit(p_unit_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_type     text;
    v_ulat     double precision; v_ulng double precision;
    v_top_rank int;
    v_incident uuid;
begin
    select u.unit_type,
           coalesce(u.current_latitude,  s.latitude),
           coalesce(u.current_longitude, s.longitude)
      into v_type, v_ulat, v_ulng
      from public.units u
      left join public.stations s on s.id = u.station_id
     where u.id = p_unit_id
       and u.status = 'Available'
       and u.is_active;

    if not found then
        return false;   -- unit isn't actually dispatchable
    end if;

    -- Step 2: highest severity waiting for this type (ignore everything below).
    select max(severity_rank) into v_top_rank
      from public.dispatch_queue
     where required_unit_type = v_type;

    if v_top_rank is null then
        return false;   -- queue empty for this type
    end if;

    -- Steps 3-6: among that top severity only, pick the nearest incident;
    -- break near-ties (within ~0.1 km, tunable) by oldest enqueued.
    select q.incident_id into v_incident
      from public.dispatch_queue q
      join public.incidents i on i.id = q.incident_id
     where q.required_unit_type = v_type
       and q.severity_rank      = v_top_rank
     order by round(public.haversine_km(v_ulat, v_ulng, i.latitude, i.longitude)::numeric, 1) asc,
              q.enqueued_at asc
     limit 1
     for update of q skip locked;   -- two freeing units won't grab the same incident

    if v_incident is null then
        return false;
    end if;

    -- Step 7: dispatch and remove the satisfied demand from the queue.
    perform public._perform_dispatch(p_unit_id, v_incident);

    delete from public.dispatch_queue
     where incident_id = v_incident
       and required_unit_type = v_type;

    return true;
end
$$;

-- 7. Event wiring: run the engine when a unit becomes Available --------------
--    Fires AFTER the existing `units_auto_resolve` BEFORE-trigger has flipped
--    a resolving unit back to 'Available'.  Guarded so it only runs on a real
--    transition INTO Available, which also prevents recursion (the dispatch
--    sets the unit to 'Assigned', never back to 'Available').
create or replace function public.units_dispatch_on_available()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status = 'Available' and new.is_active
       and (tg_op = 'INSERT' or old.status is distinct from 'Available') then
        perform public.dispatch_available_unit(new.id);
    end if;
    return null;   -- AFTER trigger: return value ignored
end
$$;

drop trigger if exists units_dispatch_after_available on public.units;
create trigger units_dispatch_after_available
    after insert or update of status on public.units
    for each row execute function public.units_dispatch_on_available();

-- 8. RLS for the queue -------------------------------------------------------
--    Admins read/manage the waiting list in the app; the worker uses the
--    service_role key and bypasses RLS; the engine functions are SECURITY
--    DEFINER so the trigger path works without granting Units any access.
alter table public.dispatch_queue enable row level security;

drop policy if exists "queue_admin_all" on public.dispatch_queue;
create policy "queue_admin_all" on public.dispatch_queue
    for all to authenticated
    using (
        exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'Admin')
    )
    with check (
        exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'Admin')
    );
