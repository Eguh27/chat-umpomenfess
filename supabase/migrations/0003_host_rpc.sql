-- 0003: RPC Host + helper internal.
-- Semua identitas diturunkan dari auth.uid(); JWT anonim ditolak NOT_HOST.
-- Sumber kontrak: TASK.md bagian 6.

create or replace function app_private.raise_error(p_code text, p_detail text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_detail is null then
    raise exception using
      errcode = 'P0001',
      message = p_code;
  else
    raise exception using
      errcode = 'P0001',
      message = p_code,
      detail = p_detail;
  end if;
end;
$$;

create or replace function app_private.generate_room_password()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bytes bytea;
  v_len int;
  v_out text := '';
  i int;
begin
  v_len := coalesce(app_private.config_int('password_length'), 6);
  v_bytes := extensions.gen_random_bytes(v_len);
  for i in 0 .. v_len - 1 loop
    v_out := v_out || substr(
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
      (get_byte(v_bytes, i) % 32) + 1,
      1
    );
  end loop;
  return v_out;
end;
$$;

create or replace function app_private.generate_slug()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slug text;
begin
  loop
    -- 12 byte base64 = 16 karakter tanpa padding; +/ dipetakan ke -_.
    v_slug := translate(
      encode(extensions.gen_random_bytes(12), 'base64'),
      '+/',
      '-_'
    );
    exit when not exists (select 1 from public.rooms r where r.slug = v_slug);
  end loop;
  return v_slug;
end;
$$;

create or replace function app_private.next_guest_number(p_room_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_no int;
begin
  update public.rooms r
  set member_counter = r.member_counter + 1
  where r.id = p_room_id
  returning r.member_counter into v_no;

  if v_no is null then
    perform app_private.raise_error('NOT_FOUND');
  end if;
  return v_no;
end;
$$;

create or replace function app_private.guest_display_name(p_no int)
returns text
language sql
immutable
set search_path = ''
as $$
  select format('Guest-%s', lpad(p_no::text, 2, '0'));
$$;

-- Internal/cron, juga dipanggil lazy oleh RPC lain. Tidak ada grant ke client.
create or replace function public.release_idle_members(p_room_id uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.room_members m
  set status = 'IDLE'::public.member_status,
      status_changed_at = now()
  from public.rooms r, public.member_activity a
  where m.room_id = r.id
    and a.member_id = m.id
    and (p_room_id is null or r.id = p_room_id)
    and r.closed_at is null
    and now() < r.expires_at
    and m.status = 'APPROVED'::public.member_status
    and a.last_active_at < now() - make_interval(mins => r.idle_timeout_minutes);
end;
$$;

create or replace function public.create_room(
  p_name text,
  p_max_guests int,
  p_approval_required boolean,
  p_idle_timeout_minutes int,
  p_typing_enabled boolean
)
returns table (room_id uuid, slug text, password text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_name text;
  v_tier text;
  v_max_rooms int;
  v_guests_cap int;
  v_active int;
  v_slug text;
  v_password text;
  v_expires timestamptz;
  v_delete timestamptz;
  v_id uuid;
begin
  if v_uid is null or app_private.is_anonymous() then
    perform app_private.raise_error('NOT_HOST');
  end if;

  v_name := btrim(coalesce(p_name, ''));
  if char_length(v_name) not between 1 and 80
     or p_max_guests is null
     or p_max_guests < 2
     or p_max_guests > 75
     or p_approval_required is null
     or p_idle_timeout_minutes is null
     or p_idle_timeout_minutes < 10
     or p_idle_timeout_minutes > 240
     or p_typing_enabled is null then
    perform app_private.raise_error('INVALID_INPUT');
  end if;

  -- Kunci baris profil: dua tab Host tidak boleh lolos kuota bersamaan.
  select p.tier into v_tier
  from public.profiles p
  where p.user_id = v_uid
  for update;

  if v_tier is null then
    insert into public.profiles (user_id) values (v_uid)
    on conflict (user_id) do nothing;

    select p.tier into v_tier
    from public.profiles p
    where p.user_id = v_uid
    for update;
  end if;

  select t.max_active_rooms, t.max_guests_cap
  into v_max_rooms, v_guests_cap
  from public.tier_limits t
  where t.tier = v_tier;

  if v_guests_cap is null then
    perform app_private.raise_error('INVALID_INPUT');
  end if;

  if p_max_guests > v_guests_cap then
    perform app_private.raise_error('CAPACITY_EXCEEDS_TIER');
  end if;

  select count(*)::int into v_active
  from public.rooms r
  where r.host_id = v_uid
    and r.closed_at is null
    and now() < r.expires_at;

  if v_active >= v_max_rooms then
    perform app_private.raise_error('QUOTA_REACHED');
  end if;

  v_slug := app_private.generate_slug();
  v_password := app_private.generate_room_password();
  v_expires := now() + make_interval(days => app_private.config_int('room_active_days'));
  v_delete := v_expires + make_interval(days => app_private.config_int('room_grace_days'));

  insert into public.rooms (
    slug, host_id, name, password_hash, approval_required, max_guests,
    idle_timeout_minutes, typing_enabled, expires_at, delete_at
  )
  values (
    v_slug, v_uid, v_name,
    extensions.crypt(v_password, extensions.gen_salt('bf', 10)),
    p_approval_required, p_max_guests, p_idle_timeout_minutes,
    p_typing_enabled, v_expires, v_delete
  )
  returning id, rooms.expires_at into v_id, v_expires;

  return query select v_id, v_slug, v_password, v_expires;
end;
$$;

create or replace function public.regenerate_password(p_room_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_password text;
begin
  if v_uid is null or app_private.is_anonymous() then
    perform app_private.raise_error('NOT_HOST');
  end if;

  select r.* into v_room
  from public.rooms r
  where r.id = p_room_id and r.host_id = v_uid
  for update;

  if not found then
    perform app_private.raise_error('NOT_FOUND');
  end if;

  if v_room.closed_at is not null or now() >= v_room.expires_at then
    perform app_private.raise_error('ROOM_CLOSED');
  end if;

  v_password := app_private.generate_room_password();

  update public.rooms r
  set password_hash = extensions.crypt(v_password, extensions.gen_salt('bf', 10)),
      password_version = r.password_version + 1
  where r.id = v_room.id;

  return v_password;
end;
$$;

create or replace function public.update_room_settings(
  p_room_id uuid,
  p_approval_required boolean default null,
  p_max_guests int default null,
  p_idle_timeout_minutes int default null,
  p_typing_enabled boolean default null
)
returns table (
  id uuid, slug text, name text, approval_required boolean, max_guests int,
  idle_timeout_minutes int, typing_enabled boolean, created_at timestamptz,
  expires_at timestamptz, closed_at timestamptz, delete_at timestamptz,
  password_version int, member_counter int
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_tier text;
  v_cap int;
  v_approved int;
begin
  if v_uid is null or app_private.is_anonymous() then
    perform app_private.raise_error('NOT_HOST');
  end if;

  select r.* into v_room
  from public.rooms r
  where r.id = p_room_id and r.host_id = v_uid
  for update;

  if not found then
    perform app_private.raise_error('NOT_FOUND');
  end if;

  if v_room.closed_at is not null or now() >= v_room.expires_at then
    perform app_private.raise_error('ROOM_CLOSED');
  end if;

  if p_idle_timeout_minutes is not null
     and (p_idle_timeout_minutes < 10 or p_idle_timeout_minutes > 240) then
    perform app_private.raise_error('INVALID_INPUT');
  end if;

  if p_max_guests is not null then
    select p.tier into v_tier
    from public.profiles p
    where p.user_id = v_uid;

    select t.max_guests_cap into v_cap
    from public.tier_limits t
    where t.tier = coalesce(v_tier, 'free');

    if p_max_guests < 2 or p_max_guests > 75 or p_max_guests > v_cap then
      perform app_private.raise_error('CAPACITY_EXCEEDS_TIER');
    end if;

    select count(*)::int into v_approved
    from public.room_members m
    where m.room_id = v_room.id
      and m.status = 'APPROVED'::public.member_status;

    if p_max_guests < v_approved then
      perform app_private.raise_error('CAPACITY_BELOW_MEMBERS');
    end if;
  end if;

  update public.rooms r
  set approval_required = coalesce(p_approval_required, r.approval_required),
      max_guests = coalesce(p_max_guests, r.max_guests),
      idle_timeout_minutes = coalesce(p_idle_timeout_minutes, r.idle_timeout_minutes),
      typing_enabled = coalesce(p_typing_enabled, r.typing_enabled)
  where r.id = v_room.id
  returning * into v_room;

  return query select
    v_room.id, v_room.slug, v_room.name, v_room.approval_required, v_room.max_guests,
    v_room.idle_timeout_minutes, v_room.typing_enabled, v_room.created_at,
    v_room.expires_at, v_room.closed_at, v_room.delete_at,
    v_room.password_version, v_room.member_counter;
end;
$$;

create or replace function public.close_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_grace_days int;
begin
  if v_uid is null or app_private.is_anonymous() then
    perform app_private.raise_error('NOT_HOST');
  end if;

  select r.* into v_room
  from public.rooms r
  where r.id = p_room_id and r.host_id = v_uid
  for update;

  if not found then
    perform app_private.raise_error('NOT_FOUND');
  end if;

  if v_room.closed_at is null then
    v_grace_days := coalesce(app_private.config_int('room_grace_days'), 15);

    update public.rooms r
    set closed_at = now(),
        delete_at = now() + make_interval(days => v_grace_days)
    where r.id = v_room.id;
  end if;
end;
$$;

create or replace function public.decide_member(
  p_member_id uuid,
  p_decision text
)
returns table (id uuid, display_name text, status public.member_status)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_member public.room_members%rowtype;
  v_room public.rooms%rowtype;
  v_room_id uuid;
  v_approved int;
  v_no int;
  v_display text;
begin
  if v_uid is null or app_private.is_anonymous() then
    perform app_private.raise_error('NOT_HOST');
  end if;

  -- Baca room_id tanpa lock, kunci room lebih dulu (urutan lock sama dengan join_room),
  -- lalu kunci baris member.
  select m.room_id into v_room_id
  from public.room_members m
  where m.id = p_member_id;

  if not found then
    perform app_private.raise_error('NOT_FOUND');
  end if;

  select r.* into v_room
  from public.rooms r
  where r.id = v_room_id and r.host_id = v_uid
  for update;

  if not found then
    perform app_private.raise_error('NOT_FOUND');
  end if;

  select m.* into v_member
  from public.room_members m
  where m.id = p_member_id
  for update;

  if v_room.closed_at is not null or now() >= v_room.expires_at then
    perform app_private.raise_error('ROOM_CLOSED');
  end if;

  if p_decision is null or p_decision not in ('APPROVE', 'REJECT') then
    perform app_private.raise_error('INVALID_INPUT');
  end if;

  if v_member.status <> 'PENDING'::public.member_status then
    perform app_private.raise_error('NOT_PENDING');
  end if;

  if p_decision = 'APPROVE' then
    perform public.release_idle_members(v_room.id);

    select count(*)::int into v_approved
    from public.room_members m
    where m.room_id = v_room.id
      and m.status = 'APPROVED'::public.member_status;

    if v_approved >= v_room.max_guests then
      perform app_private.raise_error('ROOM_FULL');
    end if;

    if v_member.member_no is null then
      v_no := app_private.next_guest_number(v_room.id);
      v_display := app_private.guest_display_name(v_no);
    else
      v_no := v_member.member_no;
      v_display := v_member.display_name;
    end if;

    update public.room_members m
    set status = 'APPROVED'::public.member_status,
        member_no = v_no,
        display_name = v_display,
        status_changed_at = now()
    where m.id = v_member.id;

    insert into public.member_activity (member_id, last_active_at)
    values (v_member.id, now())
    on conflict (member_id) do update set last_active_at = excluded.last_active_at;
  else
    update public.room_members m
    set status = 'REJECTED'::public.member_status,
        status_changed_at = now()
    where m.id = v_member.id;
    v_display := v_member.display_name;
  end if;

  return query select
    v_member.id,
    v_display,
    case when p_decision = 'APPROVE'
      then 'APPROVED'::public.member_status
      else 'REJECTED'::public.member_status
    end;
end;
$$;

create or replace function public.kick_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_member public.room_members%rowtype;
begin
  if v_uid is null or app_private.is_anonymous() then
    perform app_private.raise_error('NOT_HOST');
  end if;

  select m.* into v_member
  from public.room_members m
  join public.rooms r on r.id = m.room_id
  where m.id = p_member_id and r.host_id = v_uid
  for update of m;

  if not found then
    perform app_private.raise_error('NOT_FOUND');
  end if;

  if v_member.status <> 'KICKED'::public.member_status then
    update public.room_members m
    set status = 'KICKED'::public.member_status,
        status_changed_at = now()
    where m.id = v_member.id;

    delete from public.member_activity a where a.member_id = v_member.id;
  end if;
end;
$$;

create or replace function public.list_members(p_room_id uuid)
returns table (id uuid, display_name text, status public.member_status, created_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or app_private.is_anonymous() then
    perform app_private.raise_error('NOT_HOST');
  end if;

  if not exists (
    select 1 from public.rooms r where r.id = p_room_id and r.host_id = v_uid
  ) then
    perform app_private.raise_error('NOT_FOUND');
  end if;

  return query
  select m.id, m.display_name, m.status, m.created_at
  from public.room_members m
  where m.room_id = p_room_id
  order by m.member_no nulls last, m.created_at;
end;
$$;

create or replace function public.list_hosted_rooms()
returns table (
  id uuid, slug text, name text, status text, approval_required boolean,
  max_guests int, idle_timeout_minutes int, typing_enabled boolean,
  typing_effective boolean, created_at timestamptz, expires_at timestamptz,
  closed_at timestamptz, delete_at timestamptz,
  approved_count int, pending_count int, quota jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_tier text;
  v_max_rooms int;
  v_used int;
  v_typing_global boolean;
begin
  if v_uid is null or app_private.is_anonymous() then
    perform app_private.raise_error('NOT_HOST');
  end if;

  select p.tier into v_tier
  from public.profiles p
  where p.user_id = v_uid;

  select t.max_active_rooms into v_max_rooms
  from public.tier_limits t
  where t.tier = coalesce(v_tier, 'free');

  select count(*)::int into v_used
  from public.rooms r
  where r.host_id = v_uid
    and r.closed_at is null
    and now() < r.expires_at;

  v_typing_global := coalesce(app_private.config_bool('typing_global_enabled'), false);

  return query
  select
    r.id,
    r.slug,
    r.name,
    case when r.closed_at is null and now() < r.expires_at then 'ACTIVE' else 'CLOSED' end,
    r.approval_required,
    r.max_guests,
    r.idle_timeout_minutes,
    r.typing_enabled,
    (r.typing_enabled and v_typing_global
      and r.closed_at is null and now() < r.expires_at),
    r.created_at,
    r.expires_at,
    r.closed_at,
    r.delete_at,
    (select count(*)::int from public.room_members m
      where m.room_id = r.id and m.status = 'APPROVED'::public.member_status),
    (select count(*)::int from public.room_members m
      where m.room_id = r.id and m.status = 'PENDING'::public.member_status),
    jsonb_build_object('used', v_used, 'max', coalesce(v_max_rooms, 0))
  from public.rooms r
  where r.host_id = v_uid
    and now() < r.delete_at
  order by r.created_at desc;
end;
$$;

create or replace function public.export_messages(
  p_room_id uuid,
  p_after_id bigint default 0,
  p_limit int default 1000
)
returns setof public.messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_after bigint := coalesce(p_after_id, 0);
  v_limit int := least(greatest(coalesce(p_limit, 1000), 1), 1000);
begin
  if v_uid is null or app_private.is_anonymous() then
    perform app_private.raise_error('NOT_HOST');
  end if;

  select r.* into v_room
  from public.rooms r
  where r.id = p_room_id and r.host_id = v_uid;

  if not found or now() >= v_room.delete_at then
    perform app_private.raise_error('NOT_FOUND');
  end if;

  return query
  select m.*
  from public.messages m
  where m.room_id = v_room.id
    and m.id > v_after
  order by m.id
  limit v_limit;
end;
$$;

-- Privilege: helper internal tanpa grant; RPC Host untuk authenticated (anon ditolak di dalam).
revoke all on function app_private.raise_error(text, text) from public, anon, authenticated;
revoke all on function app_private.generate_room_password() from public, anon, authenticated;
revoke all on function app_private.generate_slug() from public, anon, authenticated;
revoke all on function app_private.next_guest_number(uuid) from public, anon, authenticated;
revoke all on function app_private.guest_display_name(int) from public, anon, authenticated;
revoke all on function public.release_idle_members(uuid) from public, anon, authenticated;

revoke all on function public.create_room(text, int, boolean, int, boolean) from public, anon, authenticated;
revoke all on function public.regenerate_password(uuid) from public, anon, authenticated;
revoke all on function public.update_room_settings(uuid, boolean, int, int, boolean) from public, anon, authenticated;
revoke all on function public.close_room(uuid) from public, anon, authenticated;
revoke all on function public.decide_member(uuid, text) from public, anon, authenticated;
revoke all on function public.kick_member(uuid) from public, anon, authenticated;
revoke all on function public.list_members(uuid) from public, anon, authenticated;
revoke all on function public.list_hosted_rooms() from public, anon, authenticated;
revoke all on function public.export_messages(uuid, bigint, int) from public, anon, authenticated;

grant execute on function public.create_room(text, int, boolean, int, boolean) to authenticated;
grant execute on function public.regenerate_password(uuid) to authenticated;
grant execute on function public.update_room_settings(uuid, boolean, int, int, boolean) to authenticated;
grant execute on function public.close_room(uuid) to authenticated;
grant execute on function public.decide_member(uuid, text) to authenticated;
grant execute on function public.kick_member(uuid) to authenticated;
grant execute on function public.list_members(uuid) to authenticated;
grant execute on function public.list_hosted_rooms() to authenticated;
grant execute on function public.export_messages(uuid, bigint, int) to authenticated;
