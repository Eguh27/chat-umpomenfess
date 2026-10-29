-- 0004: RPC Guest + join_room khusus service_role.
-- Identitas Guest selalu diturunkan dari auth.uid() (kecuali join_room yang
-- menerima user_id hasil verifikasi token oleh Agent B).
-- Sumber kontrak: TASK.md bagian 6 dan 8.

create or replace function public.get_room_public(p_slug text)
returns table (room_id uuid, name text, status text, typing_effective boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_room public.rooms%rowtype;
  v_typing_global boolean;
begin
  select r.* into v_room
  from public.rooms r
  where r.slug = p_slug;

  if not found then
    perform app_private.raise_error('NOT_FOUND');
  end if;

  v_typing_global := coalesce(app_private.config_bool('typing_global_enabled'), false);

  return query select
    v_room.id,
    v_room.name,
    case when v_room.closed_at is null and now() < v_room.expires_at then 'ACTIVE' else 'CLOSED' end,
    (v_room.typing_enabled and v_typing_global
      and v_room.closed_at is null and now() < v_room.expires_at);
end;
$$;

create or replace function public.rejoin_room(p_room_id uuid)
returns public.member_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_member public.room_members%rowtype;
  v_approved int;
begin
  if v_uid is null then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  -- Urutan lock: rooms lalu room_members (konsisten dengan join_room).
  select r.* into v_room
  from public.rooms r
  where r.id = p_room_id
  for update;

  if not found then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  select m.* into v_member
  from public.member_identities mi
  join public.room_members m on m.id = mi.member_id
  where mi.room_id = v_room.id and mi.user_id = v_uid
  for update of m;

  if not found then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  if v_member.status = 'KICKED'::public.member_status then
    perform app_private.raise_error('KICKED');
  end if;

  if v_member.status in ('REJECTED'::public.member_status, 'LEFT'::public.member_status) then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  if v_room.closed_at is not null or now() >= v_room.expires_at then
    perform app_private.raise_error('ROOM_CLOSED');
  end if;

  if v_member.status in ('PENDING'::public.member_status, 'APPROVED'::public.member_status) then
    return v_member.status;
  end if;

  if v_member.password_version <> v_room.password_version then
    perform app_private.raise_error('PASSWORD_CHANGED');
  end if;

  perform public.release_idle_members(v_room.id);

  select count(*)::int into v_approved
  from public.room_members m
  where m.room_id = v_room.id
    and m.status = 'APPROVED'::public.member_status;

  if v_approved >= v_room.max_guests then
    perform app_private.raise_error('ROOM_FULL');
  end if;

  update public.room_members m
  set status = 'APPROVED'::public.member_status,
      status_changed_at = now()
  where m.id = v_member.id;

  insert into public.member_activity (member_id, last_active_at)
  values (v_member.id, now())
  on conflict (member_id) do update set last_active_at = excluded.last_active_at;

  return 'APPROVED'::public.member_status;
end;
$$;

create or replace function public.my_rooms()
returns table (
  room_id uuid, slug text, name text, room_status text,
  my_status public.member_status, display_name text, expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return;
  end if;

  return query
  select
    r.id,
    r.slug,
    r.name,
    case when r.closed_at is null and now() < r.expires_at then 'ACTIVE' else 'CLOSED' end,
    m.status,
    m.display_name,
    r.expires_at
  from public.member_identities mi
  join public.room_members m on m.id = mi.member_id
  join public.rooms r on r.id = mi.room_id
  where mi.user_id = v_uid
    and m.status in (
      'PENDING'::public.member_status,
      'APPROVED'::public.member_status,
      'IDLE'::public.member_status
    )
    and r.closed_at is null
    and now() < r.expires_at
  order by r.created_at desc;
end;
$$;

create or replace function public.list_messages(
  p_room_id uuid,
  p_before_id bigint default null,
  p_after_id bigint default null,
  p_limit int default 50
)
returns setof public.messages
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_is_host boolean;
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  if v_uid is null then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  select r.* into v_room
  from public.rooms r
  where r.id = p_room_id;

  if not found then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  v_is_host := v_room.host_id = v_uid;

  if v_is_host then
    if now() >= v_room.delete_at then
      perform app_private.raise_error('ROOM_CLOSED');
    end if;
  else
    if not app_private.is_approved_member(v_room.id) then
      perform app_private.raise_error('NOT_MEMBER');
    end if;

    if v_room.closed_at is not null or now() >= v_room.expires_at then
      perform app_private.raise_error('ROOM_CLOSED');
    end if;
  end if;

  if p_before_id is not null then
    -- Halaman lebih lama: ambil v_limit terakhir sebelum id tersebut.
    return query
    select m.*
    from (
      select msg.*
      from public.messages msg
      where msg.room_id = v_room.id
        and msg.id < p_before_id
      order by msg.id desc
      limit v_limit
    ) m
    order by m.id;
  elsif coalesce(p_after_id, 0) > 0 then
    -- Menambal pesan yang terlewat setelah reconnect.
    return query
    select msg.*
    from public.messages msg
    where msg.room_id = v_room.id
      and msg.id > p_after_id
    order by msg.id
    limit v_limit;
  else
    -- Muat awal: v_limit pesan TERAKHIR, tetap urut naik.
    return query
    select m.*
    from (
      select msg.*
      from public.messages msg
      where msg.room_id = v_room.id
      order by msg.id desc
      limit v_limit
    ) m
    order by m.id;
  end if;
end;
$$;

create or replace function public.send_message(
  p_room_id uuid,
  p_content text,
  p_client_msg_id uuid
)
returns public.messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_member public.room_members%rowtype;
  v_existing public.messages%rowtype;
  v_msg public.messages%rowtype;
  v_is_host boolean;
  v_content text;
  v_max_len int;
  v_recent int;
  v_total bigint;
  v_room_limit int;
  v_sender_type text;
  v_sender_name text;
  v_member_id uuid;
begin
  if v_uid is null then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  if p_client_msg_id is null then
    perform app_private.raise_error('INVALID_INPUT');
  end if;

  v_max_len := coalesce(app_private.config_int('message_max_length'), 2000);
  v_content := btrim(coalesce(p_content, ''));

  if char_length(v_content) = 0 then
    perform app_private.raise_error('INVALID_INPUT');
  end if;

  if char_length(v_content) > v_max_len then
    perform app_private.raise_error('MESSAGE_TOO_LONG');
  end if;

  select r.* into v_room
  from public.rooms r
  where r.id = p_room_id;

  if not found then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  v_is_host := v_room.host_id = v_uid;

  if v_is_host then
    v_member_id := null;
    v_sender_type := 'HOST';
    v_sender_name := 'Host';
  else
    select m.* into v_member
    from public.member_identities mi
    join public.room_members m on m.id = mi.member_id
    where mi.room_id = v_room.id and mi.user_id = v_uid
    for update of m;

    if not found or v_member.status <> 'APPROVED'::public.member_status then
      perform app_private.raise_error('NOT_MEMBER');
    end if;

    v_member_id := v_member.id;
    v_sender_type := 'GUEST';
    v_sender_name := v_member.display_name;
  end if;

  -- Idempotensi: retry dengan client_msg_id yang sama mengembalikan baris lama.
  select m.* into v_existing
  from public.messages m
  where m.room_id = v_room.id
    and m.client_msg_id = p_client_msg_id;

  if found then
    if (v_is_host and v_existing.sender_type = 'HOST')
       or (not v_is_host and v_existing.member_id = v_member_id) then
      return v_existing;
    end if;
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  if v_room.closed_at is not null or now() >= v_room.expires_at then
    perform app_private.raise_error('ROOM_CLOSED');
  end if;

  select count(*)::int into v_recent
  from public.messages m
  where m.room_id = v_room.id
    and m.created_at > now() - interval '1 minute'
    and (
      (v_is_host and m.sender_type = 'HOST')
      or (not v_is_host and m.member_id = v_member_id)
    );

  if v_recent >= coalesce(app_private.config_int('messages_per_minute'), 20) then
    perform app_private.raise_error('RATE_LIMITED');
  end if;

  select t.max_messages_per_room into v_room_limit
  from public.profiles p
  join public.tier_limits t on t.tier = p.tier
  where p.user_id = v_room.host_id;

  if v_room_limit is null then
    select t.max_messages_per_room into v_room_limit
    from public.tier_limits t
    where t.tier = 'free';
  end if;

  select count(*)::bigint into v_total
  from public.messages m
  where m.room_id = v_room.id;

  if v_total >= v_room_limit then
    perform app_private.raise_error('ROOM_MESSAGE_LIMIT');
  end if;

  begin
    insert into public.messages (
      room_id, sender_type, member_id, sender_name, content, client_msg_id
    )
    values (
      v_room.id, v_sender_type, v_member_id, v_sender_name, v_content, p_client_msg_id
    )
    returning * into v_msg;
  exception
    when unique_violation then
      select m.* into v_msg
      from public.messages m
      where m.room_id = v_room.id
        and m.client_msg_id = p_client_msg_id;

      if not found
         or not (
           (v_is_host and v_msg.sender_type = 'HOST')
           or (not v_is_host and v_msg.member_id = v_member_id)
         ) then
        perform app_private.raise_error('NOT_MEMBER');
      end if;
  end;

  if not v_is_host then
    insert into public.member_activity (member_id, last_active_at)
    values (v_member_id, now())
    on conflict (member_id) do update set last_active_at = excluded.last_active_at;
  end if;

  return v_msg;
end;
$$;

create or replace function public.touch_activity(p_room_id uuid)
returns public.member_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_member public.room_members%rowtype;
  v_active boolean;
begin
  if v_uid is null then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  select m.* into v_member
  from public.member_identities mi
  join public.room_members m on m.id = mi.member_id
  where mi.room_id = p_room_id and mi.user_id = v_uid;

  if not found then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  if v_member.status = 'APPROVED'::public.member_status then
    select app_private.room_is_active(p_room_id) into v_active;

    if v_active then
      insert into public.member_activity (member_id, last_active_at)
      values (v_member.id, now())
      on conflict (member_id) do update set last_active_at = excluded.last_active_at;
    end if;
  end if;

  return v_member.status;
end;
$$;

create or replace function public.leave_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_member public.room_members%rowtype;
begin
  if v_uid is null then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  select m.* into v_member
  from public.member_identities mi
  join public.room_members m on m.id = mi.member_id
  where mi.room_id = p_room_id and mi.user_id = v_uid
  for update of m;

  if not found then
    perform app_private.raise_error('NOT_MEMBER');
  end if;

  if v_member.status in (
    'PENDING'::public.member_status,
    'APPROVED'::public.member_status,
    'IDLE'::public.member_status
  ) then
    update public.room_members m
    set status = 'LEFT'::public.member_status,
        status_changed_at = now()
    where m.id = v_member.id;

    delete from public.member_activity a where a.member_id = v_member.id;
  end if;
end;
$$;

-- Khusus service_role. Client authenticated/anon TIDAK boleh memanggil ini.
create or replace function public.join_room(
  p_user_id uuid,
  p_slug text,
  p_password text,
  p_ip_hash text
)
returns table (status public.member_status, room_id uuid, member_id uuid, display_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_room public.rooms%rowtype;
  v_member public.room_members%rowtype;
  v_status public.member_status;
  v_member_no int;
  v_display text;
  v_approved int;
  v_pending int;
  v_attempts int;
  v_last_fail timestamptz;
  v_retry int;
  v_active_rooms int;
  v_max_rooms int;
  v_threshold int;
  v_window int;
  v_duration int;
  v_cooldown int;
  v_failure_cap int;
  v_pending_mult int;
begin
  if p_user_id is null
     or p_ip_hash is null
     or char_length(p_ip_hash) < 32 then
    perform app_private.raise_error('INVALID_INPUT');
  end if;

  -- Kunci room sejak awal: serialisasi percobaan password, kursi, dan penomoran.
  select r.* into v_room
  from public.rooms r
  where r.slug = p_slug
  for update;

  if not found then
    perform app_private.raise_error('ROOM_NOT_FOUND');
  end if;

  if v_room.closed_at is not null or now() >= v_room.expires_at then
    perform app_private.raise_error('ROOM_CLOSED');
  end if;

  v_threshold := coalesce(app_private.config_int('lockout_fail_threshold'), 5);
  v_window := coalesce(app_private.config_int('lockout_window_minutes'), 15);
  v_duration := coalesce(app_private.config_int('lockout_duration_minutes'), 15);
  v_cooldown := coalesce(app_private.config_int('room_cooldown_minutes'), 10);
  v_failure_cap := coalesce(app_private.config_int('room_failure_cap_per_hour'), 200);

  -- Cooldown seluruh room.
  select count(*)::int, max(a.created_at)
  into v_attempts, v_last_fail
  from public.join_attempts a
  where a.room_id = v_room.id
    and a.success = false
    and a.created_at > now() - interval '1 hour';

  if v_attempts >= v_failure_cap then
    v_retry := ceil(
      extract(epoch from (v_last_fail + make_interval(mins => v_cooldown) - now()))
    )::int;

    if v_retry > 0 then
      perform app_private.raise_error(
        'ROOM_COOLDOWN',
        jsonb_build_object('retry_after', v_retry)::text
      );
    end if;
  end if;

  -- Lockout per (room, ip_hash).
  select count(*)::int, max(a.created_at)
  into v_attempts, v_last_fail
  from public.join_attempts a
  where a.room_id = v_room.id
    and a.ip_hash = p_ip_hash
    and a.success = false
    and a.created_at > now() - make_interval(mins => v_window);

  if v_attempts >= v_threshold then
    v_retry := ceil(
      extract(epoch from (v_last_fail + make_interval(mins => v_duration) - now()))
    )::int;

    if v_retry > 0 then
      perform app_private.raise_error(
        'LOCKED',
        jsonb_build_object('retry_after', v_retry)::text
      );
    end if;
  end if;

  -- Sudah pernah menjadi member: status tertentu tidak boleh mencoba password lagi.
  select m.* into v_member
  from public.member_identities mi
  join public.room_members m on m.id = mi.member_id
  where mi.room_id = v_room.id
    and mi.user_id = p_user_id
  for update of m;

  if found then
    if v_member.status = 'KICKED'::public.member_status then
      perform app_private.raise_error('KICKED');
    end if;

    if v_member.status = 'REJECTED'::public.member_status then
      perform app_private.raise_error('REJECTED');
    end if;

    if v_member.status in (
      'PENDING'::public.member_status,
      'APPROVED'::public.member_status
    ) then
      return query select v_member.status, v_room.id, v_member.id, v_member.display_name;
      return;
    end if;
  end if;

  -- Password room case-insensitive: selalu hash versi UPPERCASE.
  -- Catatan: percobaan GAGAL tidak bisa dicatat di sini karena exception akan
  -- me-rollback seluruh statement. Agent B mencatatnya lewat record_join_failure().
  if extensions.crypt(upper(p_password), v_room.password_hash)
     is distinct from v_room.password_hash then
    perform app_private.raise_error('WRONG_PASSWORD');
  end if;

  v_max_rooms := coalesce(app_private.config_int('max_rooms_per_guest'), 5);

  select count(*)::int into v_active_rooms
  from public.member_identities mi
  join public.room_members m on m.id = mi.member_id
  join public.rooms r on r.id = mi.room_id
  where mi.user_id = p_user_id
    and mi.room_id <> v_room.id
    and m.status in (
      'PENDING'::public.member_status,
      'APPROVED'::public.member_status
    )
    and r.closed_at is null
    and now() < r.expires_at;

  if v_active_rooms >= v_max_rooms then
    perform app_private.raise_error('MAX_ROOMS_PER_GUEST');
  end if;

  -- Lepas kursi idle secara lazy sebelum menghitung kapasitas.
  perform public.release_idle_members(v_room.id);

  if v_room.approval_required then
    select count(*)::int into v_pending
    from public.room_members m
    where m.room_id = v_room.id
      and m.status = 'PENDING'::public.member_status;

    v_pending_mult := coalesce(app_private.config_int('pending_cap_multiplier'), 2);

    if v_pending >= v_room.max_guests * v_pending_mult then
      perform app_private.raise_error('ROOM_FULL');
    end if;

    v_status := 'PENDING'::public.member_status;
    v_member_no := v_member.member_no;
    v_display := v_member.display_name;
  else
    select count(*)::int into v_approved
    from public.room_members m
    where m.room_id = v_room.id
      and m.status = 'APPROVED'::public.member_status;

    if v_approved >= v_room.max_guests then
      perform app_private.raise_error('ROOM_FULL');
    end if;

    v_status := 'APPROVED'::public.member_status;

    if v_member.id is null or v_member.member_no is null then
      v_member_no := app_private.next_guest_number(v_room.id);
      v_display := app_private.guest_display_name(v_member_no);
    else
      v_member_no := v_member.member_no;
      v_display := v_member.display_name;
    end if;
  end if;

  if v_member.id is null then
    insert into public.room_members (
      room_id, member_no, display_name, status, password_version, status_changed_at
    )
    values (
      v_room.id, v_member_no, v_display, v_status, v_room.password_version, now()
    )
    returning * into v_member;

    insert into public.member_identities (member_id, room_id, user_id)
    values (v_member.id, v_room.id, p_user_id);
  else
    update public.room_members m
    set status = v_status,
        member_no = v_member_no,
        display_name = v_display,
        password_version = v_room.password_version,
        status_changed_at = now()
    where m.id = v_member.id
    returning * into v_member;
  end if;

  -- `member_id` adalah nama kolom OUT pada fungsi ini, jadi pakai nama constraint.
  insert into public.member_activity (member_id, last_active_at)
  values (v_member.id, now())
  on conflict on constraint member_activity_pkey
  do update set last_active_at = excluded.last_active_at;

  -- Hanya tercatat bila seluruh proses join berhasil (transaksi commit).
  insert into public.join_attempts (room_id, ip_hash, success)
  values (v_room.id, p_ip_hash, true);

  return query select v_member.status, v_room.id, v_member.id, v_member.display_name;
end;
$$;

-- Service-only: dipanggil Agent B setelah join_room mengembalikan WRONG_PASSWORD.
-- Exception pada join_room me-rollback tulisannya sendiri, jadi pencatatan
-- kegagalan harus berada di statement terpisah.
create or replace function public.record_join_failure(
  p_slug text,
  p_ip_hash text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_ip_hash is null or char_length(p_ip_hash) < 32 then
    perform app_private.raise_error('INVALID_INPUT');
  end if;

  insert into public.join_attempts (room_id, ip_hash, success)
  select r.id, p_ip_hash, false
  from public.rooms r
  where r.slug = p_slug;
end;
$$;

revoke all on function public.get_room_public(text) from public, anon, authenticated;
revoke all on function public.rejoin_room(uuid) from public, anon, authenticated;
revoke all on function public.my_rooms() from public, anon, authenticated;
revoke all on function public.list_messages(uuid, bigint, bigint, int) from public, anon, authenticated;
revoke all on function public.send_message(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.touch_activity(uuid) from public, anon, authenticated;
revoke all on function public.leave_room(uuid) from public, anon, authenticated;
revoke all on function public.join_room(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.record_join_failure(text, text) from public, anon, authenticated;

grant execute on function public.get_room_public(text) to authenticated;
grant execute on function public.rejoin_room(uuid) to authenticated;
grant execute on function public.my_rooms() to authenticated;
grant execute on function public.list_messages(uuid, bigint, bigint, int) to authenticated;
grant execute on function public.send_message(uuid, text, uuid) to authenticated;
grant execute on function public.touch_activity(uuid) to authenticated;
grant execute on function public.leave_room(uuid) to authenticated;
grant execute on function public.join_room(uuid, text, text, text) to service_role;
grant execute on function public.record_join_failure(text, text) to service_role;
