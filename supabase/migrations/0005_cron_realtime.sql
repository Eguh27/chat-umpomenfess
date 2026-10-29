-- 0005: job pemeliharaan + otorisasi Realtime untuk indikator mengetik.
-- Sumber kontrak: TASK.md bagian 5, 8, dan 9.

create or replace function public.expire_pending_members()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ttl_hours int := coalesce(app_private.config_int('pending_ttl_hours'), 24);
begin
  update public.room_members m
  set status = 'LEFT'::public.member_status,
      status_changed_at = now()
  where m.status = 'PENDING'::public.member_status
    and m.status_changed_at < now() - make_interval(hours => v_ttl_hours);
end;
$$;

create or replace function public.purge_join_attempts()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.join_attempts a
  where a.created_at < now() - interval '24 hours';
end;
$$;

create or replace function public.delete_expired_rooms()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.rooms r
  where r.delete_at < now();
end;
$$;

revoke all on function public.expire_pending_members() from public, anon, authenticated;
revoke all on function public.purge_join_attempts() from public, anon, authenticated;
revoke all on function public.delete_expired_rooms() from public, anon, authenticated;

-- Idempotent: cron.schedule dengan nama yang sama akan memperbarui jadwal.
select cron.schedule(
  'release-idle-members',
  '*/5 * * * *',
  $$select public.release_idle_members();$$
);

select cron.schedule(
  'expire-pending-members',
  '0 * * * *',
  $$select public.expire_pending_members();$$
);

select cron.schedule(
  'purge-join-attempts',
  '15 * * * *',
  $$select public.purge_join_attempts();$$
);

select cron.schedule(
  'delete-expired-rooms',
  '0 20 * * *',
  $$select public.delete_expired_rooms();$$
);

-- Topik `typing:<room_id>`; parsing aman untuk topik sembarang.
create or replace function app_private.typing_room_id(p_topic text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_topic is null or left(p_topic, 7) <> 'typing:' then
    return null;
  end if;
  return substring(p_topic from 8)::uuid;
exception
  when others then return null;
end;
$$;

create or replace function app_private.can_use_typing(p_room_id uuid)
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
      and r.typing_enabled
      and coalesce(app_private.config_bool('typing_global_enabled'), false)
      and (
        r.host_id = auth.uid()
        or exists (
          select 1
          from public.member_identities mi
          join public.room_members m on m.id = mi.member_id
          where mi.room_id = r.id
            and mi.user_id = auth.uid()
            and m.status = 'APPROVED'::public.member_status
        )
      )
  );
$$;

revoke all on function app_private.typing_room_id(text) from public, anon, authenticated;
revoke all on function app_private.can_use_typing(uuid) from public, anon, authenticated;
grant execute on function app_private.typing_room_id(text) to authenticated;
grant execute on function app_private.can_use_typing(uuid) to authenticated;

-- Realtime Authorization: private channel `typing:<room_id>`.
-- SELECT = menerima broadcast, INSERT = mengirim broadcast.
do $$
begin
  if to_regclass('realtime.messages') is not null then
    execute 'drop policy if exists typing_broadcast_select on realtime.messages';
    execute $p$
      create policy typing_broadcast_select
        on realtime.messages for select to authenticated
        using (
          realtime.messages.extension = 'broadcast'
          and app_private.can_use_typing(app_private.typing_room_id(realtime.topic()))
        )
    $p$;

    execute 'drop policy if exists typing_broadcast_insert on realtime.messages';
    execute $p$
      create policy typing_broadcast_insert
        on realtime.messages for insert to authenticated
        with check (
          realtime.messages.extension = 'broadcast'
          and app_private.can_use_typing(app_private.typing_room_id(realtime.topic()))
        )
    $p$;
  end if;
end
$$;
