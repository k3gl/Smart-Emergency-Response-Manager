-- ============================================================================
-- Device tokens for push notifications (FCM)
--
-- Each app install has one FCM "device token". We store it against the
-- currently logged-in user so the sender (Edge Function) knows which devices
-- to push to. Because one device can switch accounts, registering a token
-- first removes any previous owner of that token (so it always points at the
-- user logged in right now).
--
-- All writes go through SECURITY DEFINER RPCs; the sender uses the service
-- role (bypasses RLS) to read tokens. No broad client policies are needed.
-- ============================================================================

create table if not exists public.device_tokens (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null,
    token      text not null unique,
    platform   text,
    updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx
    on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;
-- (no client-facing policies: access is via the RPCs below + service role)

-- Claim a token for the current user (replaces any previous owner).
create or replace function public.register_device_token(
    p_token text, p_platform text default 'android')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        return;   -- not authenticated; nothing to register
    end if;
    delete from public.device_tokens where token = p_token;
    insert into public.device_tokens (user_id, token, platform)
    values (auth.uid(), p_token, p_platform);
end
$$;

-- Drop this device's token (called on logout).
create or replace function public.unregister_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    delete from public.device_tokens where token = p_token;
end
$$;
