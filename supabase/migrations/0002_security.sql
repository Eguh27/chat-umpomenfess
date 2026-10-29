-- 0002: boundary keamanan.
-- Schema privat + helper, pencabutan privilege default, RLS + policy,
-- grant kolom rooms, publication Realtime, dan trigger profil Host.
-- Sumber kontrak: TASK.md bagian 5.

create schema if not exists app_private;
revoke all on schema app_private from public;
grant usage on schema app_private to authenticated;

-- Default privileges harus dipasang sebelum fungsi/tabel baru dibuat.
alter default privileges in schema public revoke all on tables from public, anon, authenticated;
alter default privileges in schema public revoke all on sequences from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema app_private revoke execute on functions from public, anon, authenticated;

-- Semua helper SECURITY DEFINER agar policy tidak rekursi ke RLS tabel sumber.
create or replace function app_private.is_anonymous()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
$$;

create or replace function app_private.config_int(p_key text)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select (c.value #>> '{}')::int
  from public.app_config c
  where c.key = p_key;
$$;

create or replace function app_private.config_bool(p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (c.value #>> '{}')::boolean
  from public.app_config c
  where c.key = p_key;
$$;

create or replace function app_private.is_room_host(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.rooms r
    where r.id = p_room_id
      and r.host_id = auth.uid()
  );
$$;

create or replace function app_private.is_approved_member(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.member_identities mi
    join public.room_members m on m.id = mi.member_id
    where mi.room_id = p_room_id
      and mi.user_id = auth.uid()
      and m.status = 'APPROVED'::public.member_status
  );
$$;

create or replace function app_private.is_self_member(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.member_identities mi
    where mi.member_id = p_member_id
      and mi.user_id = auth.uid()
  );
$$;

create or replace function app_private.room_is_active(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.rooms r
    where r.id = p_room_id
      and r.closed_at is null
      and now() < r.expires_at
  );
$$;

create or replace function app_private.room_is_readable_by_host(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.rooms r
    where r.id = p_room_id
      and r.host_id = auth.uid()
      and now() < r.delete_at
  );
$$;

-- Hanya helper yang dipakai langsung oleh policy yang perlu EXECUTE untuk client.
revoke all on function app_private.is_room_host(uuid) from public, anon, authenticated;
revoke all on function app_private.is_approved_member(uuid) from public, anon, authenticated;
revoke all on function app_private.is_self_member(uuid) from public, anon, authenticated;
revoke all on function app_private.room_is_active(uuid) from public, anon, authenticated;
revoke all on function app_private.room_is_readable_by_host(uuid) from public, anon, authenticated;
grant execute on function app_private.is_room_host(uuid) to authenticated;
grant execute on function app_private.is_approved_member(uuid) to authenticated;
grant execute on function app_private.is_self_member(uuid) to authenticated;
grant execute on function app_private.room_is_active(uuid) to authenticated;
grant execute on function app_private.room_is_readable_by_host(uuid) to authenticated;

revoke all on function app_private.is_anonymous() from public, anon, authenticated;
revoke all on function app_private.config_int(text) from public, anon, authenticated;
revoke all on function app_private.config_bool(text) from public, anon, authenticated;

-- RLS aktif di semua tabel public.
alter table public.profiles enable row level security;
alter table public.tier_limits enable row level security;
alter table public.app_config enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.member_identities enable row level security;
alter table public.member_activity enable row level security;
alter table public.messages enable row level security;
alter table public.join_attempts enable row level security;

-- Cabut semua privilege tabel/sequence, lalu beri grant eksplisit.
revoke all on all tables in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;

grant select on public.profiles to authenticated;
grant select on public.tier_limits to authenticated;
grant select on public.app_config to authenticated;
grant select on public.room_members to authenticated;
grant select on public.messages to authenticated;
grant select (
  id, slug, name, approval_required, max_guests, idle_timeout_minutes,
  typing_enabled, created_at, expires_at, closed_at, delete_at, password_version
) on public.rooms to authenticated;

-- Policy: hanya SELECT. Tidak ada INSERT/UPDATE/DELETE untuk client.
create policy profiles_select_self
  on public.profiles for select to authenticated
  using (user_id = auth.uid());

create policy tier_limits_select_all
  on public.tier_limits for select to authenticated
  using (true);

create policy app_config_select_all
  on public.app_config for select to authenticated
  using (true);

create policy rooms_select_host
  on public.rooms for select to authenticated
  using (app_private.is_room_host(id));

create policy room_members_select
  on public.room_members for select to authenticated
  using (
    app_private.is_room_host(room_id)
    or app_private.is_self_member(id)
  );

create policy messages_select
  on public.messages for select to authenticated
  using (
    (app_private.is_room_host(room_id) and app_private.room_is_readable_by_host(room_id))
    or (app_private.is_approved_member(room_id) and app_private.room_is_active(room_id))
  );

-- member_identities, member_activity, join_attempts: RLS aktif tanpa policy.

-- Publication Realtime: hanya messages dan room_members.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'create publication supabase_realtime';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'
  ) then
    execute 'alter publication supabase_realtime add table public.messages';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_members'
  ) then
    execute 'alter publication supabase_realtime add table public.room_members';
  end if;
end
$$;

-- UPDATE status member harus membawa seluruh kolom agar RLS Realtime bisa dievaluasi.
alter table public.room_members replica identity full;

-- Profil Host dibuat otomatis; user anonim tidak mendapat profil.
create or replace function app_private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.is_anonymous, false) is false then
    insert into public.profiles (user_id)
    values (new.id)
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;

revoke all on function app_private.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app_private.handle_new_user();
