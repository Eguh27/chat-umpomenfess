-- Seed development. Jangan dipakai di produksi.
-- Host dev: dev@example.com / devpassword
-- Room dev: slug `devroom000000001`, password `ABC234`.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
)
values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'dev@example.com',
  extensions.crypt('devpassword', extensions.gen_salt('bf')),
  now(),
  '', '', '', '',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now(),
  false
)
on conflict (id) do nothing;

insert into public.rooms (
  slug, host_id, name, password_hash, approval_required, max_guests,
  idle_timeout_minutes, typing_enabled, created_at, expires_at, delete_at
)
select
  'devroom000000001',
  '00000000-0000-4000-8000-000000000001',
  'Room Development',
  extensions.crypt('ABC234', extensions.gen_salt('bf', 10)),
  false,
  10,
  30,
  true,
  now(),
  now() + interval '7 days',
  now() + interval '22 days'
where not exists (
  select 1 from public.rooms where slug = 'devroom000000001'
);

-- Host kedua untuk menguji isolasi antarahost.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
)
values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-4000-8000-000000000002',
  'authenticated',
  'authenticated',
  'dev2@example.com',
  extensions.crypt('devpassword', extensions.gen_salt('bf')),
  now(),
  '', '', '', '',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now(),
  false
)
on conflict (id) do nothing;
