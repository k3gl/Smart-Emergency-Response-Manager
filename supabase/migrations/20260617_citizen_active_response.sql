-- ============================================================================
-- Let a Citizen see the Unit responding to their own incident.
--
-- A Citizen is the user whose auth.uid() equals incidents.reporter_id.
-- They get SELECT access on:
--   * the units row referenced by incidents.assigned_unit_id, and
--   * the incident_dispatches rows belonging to their incidents.
-- ============================================================================

drop policy if exists "units_reporter_read"    on public.units;
drop policy if exists "dispatch_reporter_read" on public.incident_dispatches;

create policy "units_reporter_read" on public.units
    for select to authenticated
    using (
        exists (
            select 1 from public.incidents i
            where i.assigned_unit_id = units.id
              and i.reporter_id      = auth.uid()
        )
        or exists (
            select 1 from public.incident_dispatches d
            join   public.incidents i on i.id = d.incident_id
            where  d.unit_id     = units.id
              and  i.reporter_id = auth.uid()
        )
    );

create policy "dispatch_reporter_read" on public.incident_dispatches
    for select to authenticated
    using (
        exists (
            select 1 from public.incidents i
            where i.id          = incident_dispatches.incident_id
              and i.reporter_id = auth.uid()
        )
    );
