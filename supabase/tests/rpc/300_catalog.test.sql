begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

select is(
  (
    select count(*)::int
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and not c.relrowsecurity
  ),
  0,
  'semua tabel public mengaktifkan RLS'
);

select is(
  (
    select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app_private')
      and p.prosecdef
      and not exists (
        select 1
        from unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
        where cfg like 'search_path=%'
      )
  ),
  0,
  'semua fungsi SECURITY DEFINER memasang search_path'
);

select is(
  (
    select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app_private')
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  0,
  'role anon tidak punya EXECUTE pada fungsi aplikasi'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.join_room(uuid,text,text,text)'::regprocedure,
    'EXECUTE'
  ),
  'join_room hanya untuk service_role'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.join_room(uuid,text,text,text)'::regprocedure,
    'EXECUTE'
  ),
  'service_role bisa memanggil join_room'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.release_idle_members(uuid)'::regprocedure,
    'EXECUTE'
  ),
  'release_idle_members tidak bisa dipanggil client'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_join_failure(text,text)'::regprocedure,
    'EXECUTE'
  ),
  'record_join_failure hanya untuk service_role'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.record_join_failure(text,text)'::regprocedure,
    'EXECUTE'
  ),
  'service_role bisa mencatat kegagalan join'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'app_private.config_int(text)'::regprocedure,
    'EXECUTE'
  ),
  'helper konfigurasi tetap privat'
);

select is(
  (
    select count(*)::int
    from pg_policies
    where schemaname = 'public'
      and tablename in ('member_identities', 'member_activity', 'join_attempts')
  ),
  0,
  'tabel identitas/aktivitas/attempts tidak punya policy'
);

select is(
  (
    select count(*)::int
    from pg_policies
    where schemaname = 'public'
      and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
  ),
  0,
  'tidak ada policy tulis untuk client di schema public'
);

select set_eq(
  $$select tablename from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'$$,
  $$values ('messages'), ('room_members')$$,
  'publication Realtime hanya messages dan room_members'
);

select is(
  (
    select relreplident::text
    from pg_class
    where oid = 'public.room_members'::regclass
  ),
  'f',
  'room_members memakai replica identity full'
);

select set_eq(
  $$select jobname from cron.job$$,
  $$values
      ('release-idle-members'),
      ('expire-pending-members'),
      ('purge-join-attempts'),
      ('delete-expired-rooms')$$,
  'empat job cron terdaftar'
);

select ok(
  not has_column_privilege(
    'authenticated', 'public.rooms', 'password_hash', 'SELECT'
  ),
  'kolom password_hash tidak diberikan ke authenticated'
);

select ok(
  has_column_privilege(
    'authenticated', 'public.rooms', 'id', 'SELECT'
  ),
  'kolom publik rooms tetap bisa dibaca Host'
);

select ok(
  not has_table_privilege('anon', 'public.messages', 'SELECT'),
  'anon tidak punya SELECT messages'
);

select is(
  (
    select count(*)::int
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'room_members'
      and column_name = 'user_id'
  ),
  0,
  'room_members tidak memiliki kolom user_id'
);

select is(
  (
    select count(*)::int
    from pg_policies
    where schemaname = 'public'
      and policyname in (
        'profiles_select_self',
        'tier_limits_select_all',
        'app_config_select_all',
        'rooms_select_host',
        'room_members_select',
        'messages_select'
      )
  ),
  6,
  'enam policy SELECT terpasang'
);

select is(
  (
    select count(*)::int
    from pg_trigger
    where tgname = 'on_auth_user_created'
      and not tgisinternal
  ),
  1,
  'trigger profil auth.users terpasang'
);

select is(
  (
    select count(*)::int
    from pg_policies
    where schemaname = 'realtime'
      and tablename = 'messages'
      and policyname in ('typing_broadcast_select', 'typing_broadcast_insert')
  ),
  2,
  'policy Realtime untuk typing terpasang'
);

select is(
  (
    select count(*)::int
    from public.app_config
    where key in (
      'message_max_length', 'messages_per_minute', 'max_rooms_per_guest',
      'password_length', 'lockout_fail_threshold', 'lockout_window_minutes',
      'lockout_duration_minutes', 'room_failure_cap_per_hour',
      'room_cooldown_minutes', 'room_active_days', 'room_grace_days',
      'pending_ttl_hours', 'pending_cap_multiplier',
      'typing_global_enabled', 'typing_default_on_max_guests'
    )
  ),
  15,
  'semua kunci app_config ter-seed'
);

select is(
  (select count(*)::int from public.tier_limits),
  2,
  'tier_limits berisi free dan premium'
);

select is(
  (
    select count(*)::int
    from public.room_members m
    join public.member_identities mi on mi.member_id = m.id
    where mi.user_id is null
  ),
  0,
  'member_identities tidak boleh tanpa user_id'
);

select * from finish();
rollback;
