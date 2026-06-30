-- ============================================================================
-- Anonymous reporting flag
--
-- A citizen may choose to mark a report as anonymous. This is purely a record
-- of the reporter's preference — it does not change dispatch, AI, or any other
-- behaviour; the incident still carries reporter_id for system use.
-- ============================================================================

alter table public.incidents
    add column if not exists is_anonymous boolean not null default false;
