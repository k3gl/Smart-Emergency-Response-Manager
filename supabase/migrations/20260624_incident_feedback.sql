-- ============================================================================
-- Incident feedback (citizen satisfaction rating)
--
-- After an incident the citizen reported is Resolved, they may rate the
-- experience 1–5 and optionally leave a comment. One rating per incident.
--
-- RLS:
--   * A citizen may read and create feedback ONLY for incidents they reported.
--   * Admins may read all feedback (for aggregation / quality review).
-- ============================================================================

create table if not exists public.incident_feedback (
    id          uuid primary key default gen_random_uuid(),
    incident_id uuid not null references public.incidents (id) on delete cascade,
    reporter_id uuid not null,                       -- the citizen (auth.uid())
    rating      int  not null check (rating between 1 and 5),
    comment     text,
    created_at  timestamptz not null default now(),
    unique (incident_id)                             -- one rating per incident
);

create index if not exists incident_feedback_reporter_idx
    on public.incident_feedback (reporter_id);

alter table public.incident_feedback enable row level security;

-- Citizen: read own feedback.
drop policy if exists "feedback_owner_read" on public.incident_feedback;
create policy "feedback_owner_read" on public.incident_feedback
    for select to authenticated
    using (reporter_id = auth.uid());

-- Citizen: create feedback only for an incident they actually reported.
drop policy if exists "feedback_owner_insert" on public.incident_feedback;
create policy "feedback_owner_insert" on public.incident_feedback
    for insert to authenticated
    with check (
        reporter_id = auth.uid()
        and exists (
            select 1 from public.incidents i
            where i.id = incident_feedback.incident_id
              and i.reporter_id = auth.uid()
        )
    );

-- Admin: full read access (quality review / dashboards).
drop policy if exists "feedback_admin_all" on public.incident_feedback;
create policy "feedback_admin_all" on public.incident_feedback
    for all to authenticated
    using (
        exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'Admin')
    )
    with check (
        exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'Admin')
    );
