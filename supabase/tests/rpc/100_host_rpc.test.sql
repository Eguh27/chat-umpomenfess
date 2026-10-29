begin;

create extension if not exists pgtap with schema extensions;

create schema test_helpers_host;
grant usage on schema test_helpers_host to authenticated;

create function test_helpers_host.act_as(p_user uuid, p_anonymous boolean default false)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user,
      'role', 'authenticated',
      'is_anonymous', p_anonymous
    )::text,
    true
  );
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end;
$$;

grant execute on function test_helpers_host.act_as(uuid, boolean) to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-4111-8111-111111111111',
    'authenticated', 'authenticated', 'host1@example.com',
    extensions.crypt('hostpass', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    now(), now(), false
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '22222222-2222-4222-8222-222222222222',
    'authenticated', 'authenticated', 'host2@example.com',
    extensions.crypt('hostpass', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    now(), now(), false
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '33333333-3333-4333-8333-333333333333',
    'authenticated', 'authenticated', null, null, null,
    '{"provider":"anonymous","providers":[]}'::jsonb, '{}'::jsonb,
    now(), now(), true
  );

select plan(37);

select is(
  (select count(*)::int from public.profiles where user_id = '11111111-1111-4111-8111-111111111111'),
  1,
  'trigger membuat profil untuk Host'
);

select is(
  (select count(*)::int from public.profiles where user_id = '33333333-3333-4333-8333-333333333333'),
  0,
  'user anonim tidak mendapat profil'
);

set local role authenticated;

select test_helpers_host.act_as('33333333-3333-4333-8333-333333333333', true);
select throws_ok(
  $$select * from public.create_room('Anon', 2, false, 30, true)$$,
  'P0001', 'NOT_HOST',
  'JWT anonim ditolak create_room'
);

select test_helpers_host.act_as('11111111-1111-4111-8111-111111111111', false);

select is(
  (select length(password) from public.create_room('Room Satu', 5, false, 30, true)),
  6,
  'create_room mengembalikan password 6 karakter'
);

select is(
  (select slug ~ '^[A-Za-z0-9_-]{16}$' from public.create_room('Room Dua', 5, false, 30, true)),
  true,
  'slug 16 karakter aman'
);

select is(
  (
    select expires_at > now() + interval '6 days'
       and expires_at < now() + interval '8 days'
    from public.create_room('Room Tiga', 5, false, 60, false)
  ),
  true,
  'expires_at memakai room_active_days'
);

select throws_ok(
  $$select * from public.create_room('Room Empat', 5, false, 30, true)$$,
  'P0001', 'QUOTA_REACHED',
  'kuota room aktif free = 3'
);

select throws_ok(
  $$select * from public.create_room('Kapasitas', 41, false, 30, true)$$,
  'P0001', 'CAPACITY_EXCEEDS_TIER',
  'kapasitas di atas cap tier ditolak'
);

select throws_ok(
  $$select * from public.create_room('', 2, false, 30, true)$$,
  'P0001', 'INVALID_INPUT',
  'nama kosong ditolak'
);

select throws_ok(
  $$select * from public.create_room('Idle', 2, false, 5, true)$$,
  'P0001', 'INVALID_INPUT',
  'idle timeout di luar 10..240 ditolak'
);

select is(
  (
    select max_guests
    from public.update_room_settings(
      (select id from public.rooms where name = 'Room Satu'),
      null, 6, 60, null
    )
  ),
  6,
  'update_room_settings mengubah max_guests'
);

select throws_ok(
  $$select * from public.update_room_settings(
      (select id from public.rooms where name = 'Room Satu'),
      null, null, 9, null
    )$$,
  'P0001', 'INVALID_INPUT',
  'update_room_settings menolak idle timeout tidak valid'
);

reset role;

-- Setup member langsung untuk menguji batas kapasitas dan moderasi.
insert into public.room_members (
  room_id, member_no, display_name, status, password_version
)
select r.id, n, format('Guest-%s', lpad(n::text, 2, '0')),
       'APPROVED'::public.member_status, r.password_version
from public.rooms r
cross join generate_series(1, 3) as n
where r.name = 'Room Dua';

update public.rooms
set member_counter = 3
where name = 'Room Dua';

insert into public.room_members (
  room_id, member_no, display_name, status, password_version
)
select r.id, null, null, 'PENDING'::public.member_status, r.password_version
from public.rooms r
where r.name = 'Room Dua';

set local role authenticated;
select test_helpers_host.act_as('11111111-1111-4111-8111-111111111111', false);

select throws_ok(
  $$select * from public.update_room_settings(
      (select id from public.rooms where name = 'Room Dua'),
      null, 2, null, null
    )$$,
  'P0001', 'CAPACITY_BELOW_MEMBERS',
  'kapasitas tidak boleh di bawah jumlah APPROVED'
);

select is(
  (select count(*)::int from public.list_members(
    (select id from public.rooms where name = 'Room Dua')
  )),
  4,
  'list_members mengembalikan semua member'
);

select ok(
  not exists (
    select 1
    from pg_proc p
    cross join lateral unnest(p.proargnames, p.proargmodes) as a(name, mode)
    where p.oid = 'public.list_members(uuid)'::regprocedure
      and a.mode = 't'
      and a.name = 'user_id'
  ),
  'list_members tidak mengembalikan user_id'
);

select is(
  (
    select status::text
    from public.decide_member(
      (
        select m.id from public.room_members m
        join public.rooms r on r.id = m.room_id
        where r.name = 'Room Dua'
          and m.status = 'PENDING'::public.member_status
        limit 1
      ),
      'APPROVE'
    )
  ),
  'APPROVED',
  'decide_member APPROVE memberi status APPROVED'
);

select throws_ok(
  $$select * from public.decide_member(
      (
        select m.id from public.room_members m
        join public.rooms r on r.id = m.room_id
        where r.name = 'Room Dua'
          and m.status = 'APPROVED'::public.member_status
        limit 1
      ),
      'APPROVE'
    )$$,
  'P0001', 'NOT_PENDING',
  'decide_member menolak member yang bukan PENDING'
);

select lives_ok(
  $$select public.kick_member(
      (
        select m.id from public.room_members m
        join public.rooms r on r.id = m.room_id
        where r.name = 'Room Dua'
          and m.member_no = 1
      )
    )$$,
  'kick_member mengubah status menjadi KICKED'
);

select is(
  (
    select status::text from public.room_members m
    join public.rooms r on r.id = m.room_id
    where r.name = 'Room Dua' and m.member_no = 1
  ),
  'KICKED',
  'status member ter-kick tersimpan'
);

select throws_ok(
  $$select public.kick_member('ffffffff-ffff-4fff-8fff-ffffffffffff')$$,
  'P0001', 'NOT_FOUND',
  'kick_member menolak member yang tidak ada'
);

select is(
  (select count(*)::int from public.list_hosted_rooms()),
  3,
  'list_hosted_rooms menampilkan 3 room'
);

select is(
  (select distinct quota ->> 'used' from public.list_hosted_rooms()),
  '3',
  'kuota used = 3'
);

select is(
  (select distinct quota ->> 'max' from public.list_hosted_rooms()),
  '3',
  'kuota max = 3'
);

select is(
  (select status from public.list_hosted_rooms() where name = 'Room Satu'),
  'ACTIVE',
  'status turunan ACTIVE'
);

select lives_ok(
  $$select public.close_room((select id from public.rooms where name = 'Room Satu'))$$,
  'close_room berhasil'
);

select is(
  (select status from public.list_hosted_rooms() where name = 'Room Satu'),
  'CLOSED',
  'status turunan CLOSED setelah ditutup'
);

select throws_ok(
  $$select public.regenerate_password((select id from public.rooms where name = 'Room Satu'))$$,
  'P0001', 'ROOM_CLOSED',
  'regenerate_password menolak room CLOSED'
);

select is(
  (select length(public.regenerate_password(
    (select id from public.rooms where name = 'Room Dua')
  ))),
  6,
  'regenerate_password mengembalikan password baru'
);

select is(
  (select password_version from public.rooms where name = 'Room Dua'),
  2,
  'regenerate_password menaikkan password_version'
);

select lives_ok(
  $$select * from public.create_room('Room Setelah Tutup', 5, false, 30, true)$$,
  'close_room membebaskan kuota room aktif'
);

select lives_ok(
  $$select * from public.export_messages(
    (select id from public.rooms where name = 'Room Satu')
  )$$,
  'Host bisa mengekspor room CLOSED selama masa tenggang'
);

reset role;
update public.rooms
set created_at = now() - interval '1 day',
    delete_at = now() - interval '1 second'
where name = 'Room Satu';

set local role authenticated;
select test_helpers_host.act_as('11111111-1111-4111-8111-111111111111', false);

select throws_ok(
  $$select * from public.export_messages(
    (select id from public.rooms where name = 'Room Satu')
  )$$,
  'P0001', 'NOT_FOUND',
  'room setelah delete_at tidak bisa diekspor'
);

select test_helpers_host.act_as('22222222-2222-4222-8222-222222222222', false);

select throws_ok(
  $$select public.regenerate_password((select id from public.rooms where name = 'Room Dua'))$$,
  'P0001', 'NOT_FOUND',
  'Host lain tidak bisa mengubah room'
);

select test_helpers_host.act_as('11111111-1111-4111-8111-111111111111', false);

select throws_ok(
  $$select password_hash from public.rooms limit 1$$,
  '42501', null,
  'Host tidak punya grant kolom password_hash'
);

select throws_ok(
  $$insert into public.rooms (slug, host_id, name, password_hash, approval_required, max_guests, typing_enabled, expires_at, delete_at)
    values ('zzzzzzzzzzzzzzzz', '11111111-1111-4111-8111-111111111111', 'Paksa', 'x', false, 2, false, now() + interval '1 day', now() + interval '2 days')$$,
  '42501', null,
  'Host tidak bisa INSERT rooms langsung'
);

select throws_ok(
  $$update public.profiles set tier = 'premium' where user_id = '11111111-1111-4111-8111-111111111111'$$,
  '42501', null,
  'Host tidak bisa mengubah tier sendiri'
);

select throws_ok(
  $$select * from public.join_room(
    '11111111-1111-4111-8111-111111111111', 'x', 'x', repeat('a', 64)
  )$$,
  '42501', null,
  'authenticated tidak bisa memanggil join_room'
);

reset role;

select * from finish();
rollback;
