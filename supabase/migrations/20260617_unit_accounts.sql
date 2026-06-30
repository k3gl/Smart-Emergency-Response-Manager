-- ============================================================================
-- Unit accounts refactor
--
--   * Units become first-class account-backed entities (name, email,
--     auth_user_id, live location, is_active).
--   * Status set is expanded to: Available, Assigned, Enroute, OnScene,
--     Resolved, Offline.  The system only ever sets a unit to "Assigned" on
--     dispatch — every later transition is driven by the Unit itself.
--   * profiles.unit_id is removed: Admins/Citizens never appear as Units.
--   * RLS enforces:  Unit -> own row + own dispatches/incidents;
--                    Admin -> everything;  Citizen -> nothing on units.
-- ============================================================================

-- 1. Units table additions ---------------------------------------------------

alter table public.units
    add column if not exists auth_user_id     uuid references auth.users (id) on delete set null,
    add column if not exists name             text,
    add column if not exists email            text,
    add column if not exists current_latitude  double precision,
    add column if not exists current_longitude double precision,
    add column if not exists last_location_at  timestamptz,
    add column if not exists is_active        boolean not null default true;

-- Email is the login identifier.  Allow nullable rows already in the table
-- but require uniqueness once present.
create unique index if not exists units_email_key       on public.units (lower(email)) where email is not null;
create unique index if not exists units_auth_user_key   on public.units (auth_user_id) where auth_user_id is not null;

-- Backfill `name` for legacy rows so the new model never sees NULL.
update public.units set name = coalesce(name, unit_code);

-- 2. Status enum widening ----------------------------------------------------
-- Original CHECK was Available/Dispatched/Returning/Offline.  Replace.

alter table public.units drop constraint if exists units_status_check;

-- Map any legacy "Dispatched"/"Returning" rows to the new vocabulary first.
update public.units set status = 'Assigned' where status = 'Dispatched';
update public.units set status = 'Enroute'  where status = 'Returning';

alter table public.units
    add constraint units_status_check
    check (status in ('Available','Assigned','Enroute','OnScene','Resolved','Offline'));

-- 3. profiles.unit_id is removed --------------------------------------------
-- A Unit identity comes from units.auth_user_id, not from a profile flag.

alter table public.profiles
    drop column if exists unit_id;

-- 4. Trigger: when a Unit marks itself Resolved, auto-close incident and
--    bounce the unit back to Available.
-- ----------------------------------------------------------------------------

create or replace function public.unit_status_after_resolve() returns trigger
language plpgsql
as $$
declare
    incident_id_to_close uuid;
begin
    -- Only act on transitions INTO a terminal state.
    if new.status in ('Resolved','Completed','Closed') then
        incident_id_to_close := new.current_incident_id;

        -- Free the unit.
        new.status              := 'Available';
        new.current_incident_id := null;

        if incident_id_to_close is not null then
            update public.incidents
            set    status      = 'Resolved',
                   resolved_at = coalesce(resolved_at, now())
            where  id = incident_id_to_close
              and  status <> 'Resolved';

            -- Free any sibling dispatched units on the same incident.
            update public.units u
            set    status              = 'Available',
                   current_incident_id = null
            from   public.incident_dispatches d
            where  d.incident_id = incident_id_to_close
              and  d.unit_id     = u.id
              and  u.id <> new.id;
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists units_auto_resolve on public.units;
create trigger units_auto_resolve
    before update of status on public.units
    for each row execute function public.unit_status_after_resolve();

-- 5. RLS policies ------------------------------------------------------------

alter table public.units enable row level security;

drop policy if exists "units_admin_all"        on public.units;
drop policy if exists "units_self_read"        on public.units;
drop policy if exists "units_self_update"      on public.units;
drop policy if exists "units_dispatcher_read"  on public.units;

-- Admins manage everything.
create policy "units_admin_all" on public.units
    for all to authenticated
    using (
        exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'Admin')
    )
    with check (
        exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'Admin')
    );

-- A Unit may read its own row.
create policy "units_self_read" on public.units
    for select to authenticated
    using (auth_user_id = auth.uid());

-- A Unit may update only its own row, and only the columns it owns
-- (the trigger above still enforces the auto-resolve invariant).
create policy "units_self_update" on public.units
    for update to authenticated
    using (auth_user_id = auth.uid())
    with check (auth_user_id = auth.uid());

-- Dispatcher worker uses the service_role key and bypasses RLS.

-- 6. RLS for incident_dispatches (Unit sees only its own) -------------------

alter table public.incident_dispatches enable row level security;

drop policy if exists "dispatch_admin_all"   on public.incident_dispatches;
drop policy if exists "dispatch_self_read"   on public.incident_dispatches;

create policy "dispatch_admin_all" on public.incident_dispatches
    for all to authenticated
    using (
        exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'Admin')
    )
    with check (
        exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'Admin')
    );

create policy "dispatch_self_read" on public.incident_dispatches
    for select to authenticated
    using (
        exists (select 1 from public.units u
                where u.id = incident_dispatches.unit_id
                  and u.auth_user_id = auth.uid())
    );

-- 7. Incidents: Unit may read incidents dispatched to it --------------------

alter table public.incidents enable row level security;

drop policy if exists "incidents_admin_all" on public.incidents;
drop policy if exists "incidents_self_read" on public.incidents;
drop policy if exists "incidents_owner_read" on public.incidents;

create policy "incidents_admin_all" on public.incidents
    for all to authenticated
    using (
        exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'Admin')
    )
    with check (
        exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'Admin')
    );

-- A Unit can see any incident it is dispatched to.
create policy "incidents_self_read" on public.incidents
    for select to authenticated
    using (
        exists (
            select 1 from public.incident_dispatches d
            join   public.units u on u.id = d.unit_id
            where  d.incident_id = incidents.id
              and  u.auth_user_id = auth.uid()
        )
    );

-- A Citizen can read their own reported incidents (existing behaviour).
create policy "incidents_owner_read" on public.incidents
    for select to authenticated
    using (reporter_id = auth.uid());
