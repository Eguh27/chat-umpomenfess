begin;

create extension if not exists pgtap with schema extensions;

create schema test_helpers_guest;
grant usage on schema test_helpers_guest to authenticated;

create function test_helpers_guest.act_as(p_user uuid, p_anonymous boolean default true)
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

grant execute on function test_helpers_guest.act_as(uuid, boolean) to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-4111-8111-111111111111',
    'authenticated', 'authenticated', 'host@example.com',
    extensions.crypt('hostpass', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    now(), now(), false
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'authenticated', 'authenticated', null, null, null,
    '{"provider":"anonymous","providers":[]}'::jsonb, '{}'::jsonb,
    now(), now(), true
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'authenticated', 'authenticated', null, null, null,
    '{"provider":"anonymous","providers":[]}'::jsonb, '{}'::jsonb,
    now(), now(), true
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'authenticated', 'authenticated', null, null, null,
    '{"provider":"anonymous","providers":[]}'::jsonb, '{}'::jsonb,
    now(), now(), true
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'authenticated', 'authenticated', null, null, null,
    '{"provider":"anonymous","providers":[]}'::jsonb, '{}'::jsonb,
    now(), now(), true
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'authenticated', 'authenticated', null, null, null,
    '{"provider":"anonymous","providers":[]}'::jsonb, '{}'::jsonb,
    now(), now(), true
  );

insert into public.rooms (
  slug, host_id, name, password_hash, approval_required, max_guests,
  idle_timeout_minutes, typing_enabled, expires_at, delete_at
)
select
  s.slug,
  '11111111-1111-4111-8111-111111111111',
  s.name,
  extensions.crypt('ABC234', extensions.gen_salt('bf', 10)),
  s.approval_required,
  s.max_guests,
  30,
  true,
  now() + interval '7 days',
  now() + interval '22 days'
from (values
  ('aaaaaaaaaaaaaaaa', 'Room A', false, 2),
  ('bbbbbbbbbbbbbbbb', 'Room B', true, 2),
  ('cccccccccccccccc', 'Room C', false, 2),
  ('dddddddddddddddd', 'Room D', false, 5),
  ('eeeeeeeeeeeeeeee', 'Room E', false, 2),
  ('ffffffffffffffff', 'Room F', false, 2),
  ('iiiiiiiiiiiiiiii', 'Room I', true, 2),
  ('jjjjjjjjjjjjjjjj', 'Room J', false, 2)
) as s(slug, name, approval_required, max_guests);

select plan(62);

select is(
  (
    select status::text
    from public.join_room(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'aaaaaaaaaaaaaaaa', 'abc234', repeat('1', 64)
    )
  ),
  'APPROVED',
  'join_room menerima password case-insensitive'
);

select is(
  (
    select display_name
    from public.room_members m
    join public.rooms r on r.id = m.room_id
    where r.slug = 'aaaaaaaaaaaaaaaa'
      and m.member_no = 1
  ),
  'Guest-01',
  'nomor Guest dimulai dari 01'
);

select throws_ok(
  $$select * from public.join_room(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'aaaaaaaaaaaaaaaa', 'SALAH1', repeat('b', 64)
    )$$,
  'P0001', 'WRONG_PASSWORD',
  'password salah ditolak'
);

select public.record_join_failure('aaaaaaaaaaaaaaaa', repeat('b', 64))
from generate_series(1, 5);

select throws_ok(
  $$select * from public.join_room(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'aaaaaaaaaaaaaaaa', 'ABC234', repeat('b', 64)
    )$$,
  'P0001', 'LOCKED',
  'percobaan ke-6 dari ip_hash yang sama terkunci'
);

delete from public.join_attempts
where room_id = (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'));

set local role authenticated;
select test_helpers_guest.act_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

select is(
  (select status from public.get_room_public('aaaaaaaaaaaaaaaa')),
  'ACTIVE',
  'get_room_public mengembalikan ACTIVE'
);

select is(
  (select typing_effective from public.get_room_public('aaaaaaaaaaaaaaaa')),
  true,
  'typing_effective true bila room dan global aktif'
);

select throws_ok(
  $$select * from public.get_room_public('tidakada')$$,
  'P0001', 'NOT_FOUND',
  'get_room_public slug tidak ada'
);

select is(
  (select count(*)::int from public.my_rooms()),
  1,
  'my_rooms menampilkan satu keanggotaan'
);

select is(
  (select display_name from public.my_rooms()),
  'Guest-01',
  'my_rooms membawa display_name'
);

select is(
  (
    select sender_type
    from public.send_message(
      (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')),
      'Halo room', 'aaaaaaaa-0000-4000-8000-000000000001'
    )
  ),
  'GUEST',
  'send_message Guest memakai sender_type GUEST'
);

select is(
  (
    select sender_name
    from public.send_message(
      (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')),
      'Halo room', 'aaaaaaaa-0000-4000-8000-000000000001'
    )
  ),
  'Guest-01',
  'sender_name Guest dari database'
);

select is(
  (
    select id
    from public.send_message(
      (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')),
      'Halo room', 'aaaaaaaa-0000-4000-8000-000000000001'
    )
  ),
  (
    select max(id)
    from public.messages
    where room_id = (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))
  ),
  'send_message idempotent pada client_msg_id'
);

select is(
  (
    select count(*)::int
    from public.messages
    where room_id = (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))
  ),
  1,
  'retry tidak menggandakan pesan'
);

reset role;
set local role authenticated;
select test_helpers_guest.act_as('11111111-1111-4111-8111-111111111111', false);

select is(
  (
    select sender_type
    from public.send_message(
      (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')),
      'Pesan Host', 'aaaaaaaa-0000-4000-8000-000000000002'
    )
  ),
  'HOST',
  'Host bisa membalas di room tanpa menjadi member'
);

select is(
  (
    select sender_name
    from public.messages
    where client_msg_id = 'aaaaaaaa-0000-4000-8000-000000000002'
  ),
  'Host',
  'sender_name Host = Host'
);

reset role;
set local role authenticated;
select test_helpers_guest.act_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

select is(
  (select count(*)::int from public.list_messages(
    (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))
  )),
  2,
  'list_messages memuat riwayat'
);

select public.send_message(
  (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')),
  'Pesan ketiga', 'aaaaaaaa-0000-4000-8000-000000000003'
);

select is(
  (select max(id) from public.list_messages(
    (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')),
    null, null, 2
  )),
  (select max(id) from public.messages
    where room_id = (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))),
  'muat awal mengambil pesan terakhir'
);

select is(
  (select id from public.list_messages(
    (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')),
    (select min(id) from public.messages
      where room_id = (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))) + 1,
    null, 1
  )),
  (select min(id) from public.messages
    where room_id = (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))),
  'paginasi ke atas memakai p_before_id'
);

select is(
  (select count(*)::int from public.list_messages(
    (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')),
    null,
    (select min(id) from public.messages
      where room_id = (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))),
    100
  )),
  2,
  'backfill memakai p_after_id'
);

select is(
  (select touch_activity((select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')))::text),
  'APPROVED',
  'touch_activity mengembalikan status APPROVED'
);

reset role;

select is(
  (
    select status::text
    from public.join_room(
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'dddddddddddddddd', 'ABC234', repeat('3', 64)
    )
  ),
  'APPROVED',
  'Guest kelima masuk room idle'
);

reset role;

update public.member_activity a
set last_active_at = now() - interval '31 minutes'
where a.member_id = (
  select m.id
  from public.room_members m
  join public.member_identities mi on mi.member_id = m.id
  join public.rooms r on r.id = m.room_id
  where r.slug = 'dddddddddddddddd'
    and mi.user_id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
);

select public.release_idle_members(
  (select room_id from public.get_room_public('dddddddddddddddd'))
);

select is(
  (
    select m.status::text
    from public.room_members m
    join public.rooms r on r.id = m.room_id
    where r.slug = 'dddddddddddddddd' and m.member_no = 1
  ),
  'IDLE',
  'release_idle_members melepas kursi idle'
);

set local role authenticated;
select test_helpers_guest.act_as('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');

select is(
  (select rejoin_room((select room_id from public.get_room_public('dddddddddddddddd')))::text),
  'APPROVED',
  'rejoin_room tanpa password mengembalikan APPROVED'
);

reset role;

update public.rooms
set password_version = password_version + 1
where slug = 'dddddddddddddddd';

update public.room_members m
set status = 'IDLE'::public.member_status
where m.id = (
  select m2.id
  from public.room_members m2
  join public.rooms r on r.id = m2.room_id
  where r.slug = 'dddddddddddddddd' and m2.member_no = 1
);

set local role authenticated;
select test_helpers_guest.act_as('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');

select throws_ok(
  $$select public.rejoin_room((select room_id from public.get_room_public('dddddddddddddddd')))$$,
  'P0001', 'PASSWORD_CHANGED',
  'rejoin_room menolak bila password_version berubah'
);

reset role;

select is(
  (
    select status::text
    from public.join_room(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'bbbbbbbbbbbbbbbb', 'ABC234', repeat('4', 64)
    )
  ),
  'PENDING',
  'room approval menghasilkan PENDING'
);

set local role authenticated;
select test_helpers_guest.act_as('11111111-1111-4111-8111-111111111111', false);

select is(
  (
    select status::text
    from public.decide_member(
      (
        select m.id
        from public.room_members m
        join public.rooms r on r.id = m.room_id
        where r.slug = 'bbbbbbbbbbbbbbbb'
          and m.status = 'PENDING'::public.member_status
        limit 1
      ),
      'APPROVE'
    )
  ),
  'APPROVED',
  'Host menyetujui member PENDING'
);

reset role;
select is(
  (
    select status::text
    from public.join_room(
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'bbbbbbbbbbbbbbbb', 'ABC234', repeat('5', 64)
    )
  ),
  'PENDING',
  'member kedua menunggu persetujuan'
);

set local role authenticated;
select test_helpers_guest.act_as('11111111-1111-4111-8111-111111111111', false);

select is(
  (
    select status::text
    from public.decide_member(
      (
        select m.id
        from public.room_members m
        join public.rooms r on r.id = m.room_id
        where r.slug = 'bbbbbbbbbbbbbbbb'
          and m.status = 'PENDING'::public.member_status
        limit 1
      ),
      'REJECT'
    )
  ),
  'REJECTED',
  'Host menolak member PENDING'
);

reset role;
select throws_ok(
  $$select * from public.join_room(
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'bbbbbbbbbbbbbbbb', 'ABC234', repeat('5', 64)
    )$$,
  'P0001', 'REJECTED',
  'member REJECTED tidak bisa mencoba lagi'
);

set local role authenticated;
select test_helpers_guest.act_as('11111111-1111-4111-8111-111111111111', false);

select lives_ok(
  $$select public.kick_member(
      (
        select m.id
        from public.room_members m
        join public.rooms r on r.id = m.room_id
        where r.slug = 'bbbbbbbbbbbbbbbb'
          and m.status = 'APPROVED'::public.member_status
        order by m.member_no
        limit 1
      )
    )$$,
  'Host bisa kick member'
);

select test_helpers_guest.act_as('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

select throws_ok(
  $$select * from public.send_message(
      (select room_id from public.get_room_public('bbbbbbbbbbbbbbbb')),
      'masih bisa?', 'bbbbbbbb-0000-4000-8000-000000000001'
    )$$,
  'P0001', 'NOT_MEMBER',
  'member KICKED tidak bisa mengirim pesan'
);

select throws_ok(
  $$select public.rejoin_room((select room_id from public.get_room_public('bbbbbbbbbbbbbbbb')))$$,
  'P0001', 'KICKED',
  'rejoin_room menolak KICKED'
);

reset role;
select throws_ok(
  $$select * from public.join_room(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'bbbbbbbbbbbbbbbb', 'ABC234', repeat('6', 64)
    )$$,
  'P0001', 'KICKED',
  'join_room menolak KICKED'
);

select is(
  (
    select status::text
    from public.join_room(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'cccccccccccccccc', 'ABC234', repeat('7', 64)
    )
  ),
  'APPROVED',
  'Guest yang di-kick boleh masuk room lain'
);

select is(
  (
    select status::text
    from public.join_room(
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'cccccccccccccccc', 'ABC234', repeat('8', 64)
    )
  ),
  'APPROVED',
  'kursi kedua room C terisi'
);

select throws_ok(
  $$select * from public.join_room(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'cccccccccccccccc', 'ABC234', repeat('9', 64)
    )$$,
  'P0001', 'ROOM_FULL',
  'kursi penuh menolak Guest berikutnya'
);

update public.app_config set value = '1'::jsonb where key = 'max_rooms_per_guest';

select is(
  (
    select status::text
    from public.join_room(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'eeeeeeeeeeeeeeee', 'ABC234', repeat('a', 64)
    )
  ),
  'APPROVED',
  'Guest keempat masuk room E'
);

select throws_ok(
  $$select * from public.join_room(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'ffffffffffffffff', 'ABC234', repeat('b', 64)
    )$$,
  'P0001', 'MAX_ROOMS_PER_GUEST',
  'batas keanggotaan aktif per Guest ditegakkan'
);

set local role authenticated;
select test_helpers_guest.act_as('11111111-1111-4111-8111-111111111111', false);

select lives_ok(
  $$select public.close_room((select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')))$$,
  'Host menutup room'
);

select test_helpers_guest.act_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

select throws_ok(
  $$select * from public.send_message(
      (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa')),
      'setelah tutup', 'aaaaaaaa-0000-4000-8000-000000000004'
    )$$,
  'P0001', 'ROOM_CLOSED',
  'pesan setelah room ditutup ditolak'
);

select is(
  (
    select count(*)::int
    from public.messages
    where room_id = (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))
  ),
  0,
  'Guest tidak bisa membaca pesan room CLOSED lewat RLS'
);

select test_helpers_guest.act_as('11111111-1111-4111-8111-111111111111', false);

select ok(
  (
    select count(*)::int
    from public.messages
    where room_id = (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))
  ) > 0,
  'Host masih bisa membaca pesan room CLOSED'
);

reset role;

select throws_ok(
  $$select * from public.join_room(
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'aaaaaaaaaaaaaaaa', 'ABC234', repeat('c', 64)
    )$$,
  'P0001', 'ROOM_CLOSED',
  'join_room menolak room CLOSED'
);

set local role authenticated;
select test_helpers_guest.act_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

select throws_ok(
  $$select * from public.list_messages(
      (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))
    )$$,
  'P0001', 'ROOM_CLOSED',
  'list_messages menolak room CLOSED untuk Guest'
);

select throws_ok(
  $$select * from public.member_identities$$,
  '42501', null,
  'member_identities tidak bisa dibaca langsung'
);

select is(
  (
    select count(*)::int
    from public.messages
    where room_id = (select room_id from public.get_room_public('bbbbbbbbbbbbbbbb'))
  ),
  0,
  'Guest room A tidak bisa membaca pesan room B (RLS)'
);

select is(
  (
    select count(*)::int
    from public.room_members
    where room_id = (select room_id from public.get_room_public('aaaaaaaaaaaaaaaa'))
  ),
  1,
  'Guest hanya melihat baris member miliknya'
);

select throws_ok(
  $$select * from public.join_room(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'aaaaaaaaaaaaaaaa', 'ABC234', repeat('d', 64)
    )$$,
  '42501', null,
  'authenticated tidak punya grant join_room'
);

set local role anon;
select throws_ok(
  $$select * from public.get_room_public('aaaaaaaaaaaaaaaa')$$,
  '42501', null,
  'role anon tidak bisa memanggil RPC Guest'
);

reset role;

-- Siapkan dua APPROVED + satu PENDING untuk menguji ROOM_FULL saat approve.
insert into public.room_members (
  room_id, member_no, display_name, status, password_version
)
select r.id, n, format('Guest-%s', lpad(n::text, 2, '0')),
       'APPROVED'::public.member_status, r.password_version
from public.rooms r
cross join generate_series(21, 22) as n
where r.slug = 'bbbbbbbbbbbbbbbb';

update public.rooms
set member_counter = 22
where slug = 'bbbbbbbbbbbbbbbb';

insert into public.room_members (
  room_id, member_no, display_name, status, password_version
)
select r.id, null, null, 'PENDING'::public.member_status, r.password_version
from public.rooms r
where r.slug = 'bbbbbbbbbbbbbbbb';

set local role authenticated;
select test_helpers_guest.act_as('11111111-1111-4111-8111-111111111111', false);

select throws_ok(
  $$select * from public.decide_member(
      (
        select m.id
        from public.room_members m
        join public.rooms r on r.id = m.room_id
        where r.slug = 'bbbbbbbbbbbbbbbb'
          and m.status = 'PENDING'::public.member_status
        limit 1
      ),
      'APPROVE'
    )$$,
  'P0001', 'ROOM_FULL',
  'approve ditolak saat kursi sudah penuh'
);

reset role;
update public.app_config set value = '5'::jsonb where key = 'max_rooms_per_guest';
update public.app_config set value = '1'::jsonb where key = 'pending_cap_multiplier';

select is(
  (
    select status::text
    from public.join_room(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'iiiiiiiiiiiiiiii', 'ABC234', repeat('e', 64)
    )
  ),
  'PENDING',
  'Guest pertama masuk antrean room I'
);

select is(
  (
    select status::text
    from public.join_room(
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'iiiiiiiiiiiiiiii', 'ABC234', repeat('f', 64)
    )
  ),
  'PENDING',
  'Guest kedua masuk antrean room I'
);

select throws_ok(
  $$select * from public.join_room(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'iiiiiiiiiiiiiiii', 'ABC234', repeat('0', 64)
    )$$,
  'P0001', 'ROOM_FULL',
  'pending cap dihitung dari max_guests x multiplier'
);

update public.tier_limits set max_messages_per_room = 3 where tier = 'free';

set local role authenticated;
select test_helpers_guest.act_as('dddddddd-dddd-4ddd-8ddd-dddddddddddd');

select public.send_message(
  (select room_id from public.get_room_public('eeeeeeeeeeeeeeee')),
  'satu', 'dddddddd-0000-4000-8000-000000000001'
);
select public.send_message(
  (select room_id from public.get_room_public('eeeeeeeeeeeeeeee')),
  'dua', 'dddddddd-0000-4000-8000-000000000002'
);
select public.send_message(
  (select room_id from public.get_room_public('eeeeeeeeeeeeeeee')),
  'tiga', 'dddddddd-0000-4000-8000-000000000003'
);

select throws_ok(
  $$select * from public.send_message(
      (select room_id from public.get_room_public('eeeeeeeeeeeeeeee')),
      'empat', 'dddddddd-0000-4000-8000-000000000004'
    )$$,
  'P0001', 'ROOM_MESSAGE_LIMIT',
  'batas pesan per room ditegakkan'
);

select throws_ok(
  $$select * from public.send_message(
      (select room_id from public.get_room_public('eeeeeeeeeeeeeeee')),
      repeat('x', 2001), 'dddddddd-0000-4000-8000-000000000005'
    )$$,
  'P0001', 'MESSAGE_TOO_LONG',
  'pesan melebihi batas ditolak'
);

reset role;
update public.app_config set value = '1'::jsonb where key = 'messages_per_minute';

select is(
  (
    select status::text
    from public.join_room(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'jjjjjjjjjjjjjjjj', 'ABC234', repeat('2', 64)
    )
  ),
  'APPROVED',
  'Guest masuk room J untuk uji rate limit'
);

set local role authenticated;
select test_helpers_guest.act_as('dddddddd-dddd-4ddd-8ddd-dddddddddddd');

select public.send_message(
  (select room_id from public.get_room_public('jjjjjjjjjjjjjjjj')),
  'pertama', 'dddddddd-0000-4000-8000-000000000006'
);

select throws_ok(
  $$select * from public.send_message(
      (select room_id from public.get_room_public('jjjjjjjjjjjjjjjj')),
      'kedua', 'dddddddd-0000-4000-8000-000000000007'
    )$$,
  'P0001', 'RATE_LIMITED',
  'rate limit per member ditegakkan'
);

select lives_ok(
  $$select public.leave_room(
      (select room_id from public.get_room_public('eeeeeeeeeeeeeeee'))
    )$$,
  'leave_room berhasil untuk member APPROVED'
);

reset role;

select is(
  (
    select m.status::text
    from public.room_members m
    join public.member_identities mi on mi.member_id = m.id
    join public.rooms r on r.id = m.room_id
    where r.slug = 'eeeeeeeeeeeeeeee'
      and mi.user_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  ),
  'LEFT',
  'leave_room mengubah status menjadi LEFT'
);

set local role authenticated;
select test_helpers_guest.act_as('dddddddd-dddd-4ddd-8ddd-dddddddddddd');

select is(
  (select public.touch_activity(
      (select room_id from public.get_room_public('eeeeeeeeeeeeeeee'))
    )::text),
  'LEFT',
  'touch_activity mengembalikan status LEFT setelah keluar'
);

select throws_ok(
  $$select public.rejoin_room(
      (select room_id from public.get_room_public('eeeeeeeeeeeeeeee'))
    )$$,
  'P0001', 'NOT_MEMBER',
  'rejoin_room menolak status LEFT'
);

select is(
  (select status from public.get_room_public('aaaaaaaaaaaaaaaa')),
  'CLOSED',
  'get_room_public mengembalikan CLOSED'
);

reset role;

select * from finish();
rollback;
