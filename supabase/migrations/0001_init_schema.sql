-- 0001: fondasi database.
-- Ekstensi, enum, semua tabel inti, constraint, index, dan seed konfigurasi.
-- Sumber kontrak: TASK.md bagian 3 dan 4.

create extension if not exists pgcrypto with schema extensions;
-- pg_cron membuat schema `cron` sendiri.
create extension if not exists pg_cron;

do $$
begin
  create type public.member_status as enum
    ('PENDING', 'APPROVED', 'REJECTED', 'KICKED', 'IDLE', 'LEFT');
exception
  when duplicate_object then null;
end
$$;

-- Profil hanya untuk Host (user non-anonim). Guest anonim tidak punya baris.
create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  tier text not null default 'free' check (tier in ('free', 'premium')),
  created_at timestamptz not null default now()
);

create table public.tier_limits (
  tier text primary key check (tier in ('free', 'premium')),
  max_active_rooms int not null check (max_active_rooms > 0),
  max_guests_cap int not null check (max_guests_cap between 2 and 75),
  max_messages_per_room int not null check (max_messages_per_room > 0)
);

-- Nilai dikirim sebagai JSON scalar agar tipe tetap eksplisit saat dibaca.
create table public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null check (slug ~ '^[A-Za-z0-9_-]{16}$'),
  host_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  password_hash text not null check (length(password_hash) > 0),
  password_version int not null default 1 check (password_version > 0),
  approval_required boolean not null,
  max_guests int not null check (max_guests between 2 and 75),
  idle_timeout_minutes int not null default 30 check (idle_timeout_minutes between 10 and 240),
  typing_enabled boolean not null,
  member_counter int not null default 0 check (member_counter >= 0),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at timestamptz,
  delete_at timestamptz not null,
  check (expires_at > created_at),
  check (delete_at > created_at)
);

create index rooms_host_id_idx on public.rooms (host_id);
create index rooms_host_active_idx on public.rooms (host_id, expires_at)
  where closed_at is null;

create table public.room_members (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  member_no int check (member_no > 0),
  display_name text check (display_name is null or char_length(display_name) between 1 and 80),
  status public.member_status not null,
  password_version int not null default 1 check (password_version > 0),
  created_at timestamptz not null default now(),
  status_changed_at timestamptz not null default now(),
  unique (room_id, member_no),
  -- Nomor dan nama diberikan bersamaan, sekali, saat pertama APPROVED.
  check ((member_no is null) = (display_name is null))
);

create index room_members_room_status_idx on public.room_members (room_id, status);
create index room_members_room_created_idx on public.room_members (room_id, created_at);

-- Tabel identitas privat. Tidak punya policy: hanya SECURITY DEFINER yang menyentuh.
create table public.member_identities (
  member_id uuid primary key references public.room_members (id) on delete cascade,
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  unique (room_id, user_id)
);

create index member_identities_user_id_idx on public.member_identities (user_id);
create index member_identities_room_id_idx on public.member_identities (room_id);

-- Tidak masuk publication Realtime.
create table public.member_activity (
  member_id uuid primary key references public.room_members (id) on delete cascade,
  last_active_at timestamptz not null default now()
);

create table public.messages (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms (id) on delete cascade,
  sender_type text not null check (sender_type in ('HOST', 'GUEST')),
  member_id uuid references public.room_members (id) on delete set null,
  sender_name text not null check (char_length(sender_name) between 1 and 80),
  content text not null check (char_length(content) between 1 and 2000),
  client_msg_id uuid not null,
  created_at timestamptz not null default now(),
  unique (room_id, client_msg_id)
);

create index messages_room_id_desc_idx on public.messages (room_id, id desc);
create index messages_member_created_idx on public.messages (member_id, created_at)
  where member_id is not null;

create table public.join_attempts (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms (id) on delete cascade,
  ip_hash text not null check (char_length(ip_hash) >= 32),
  success boolean not null,
  created_at timestamptz not null default now()
);

create index join_attempts_room_ip_created_idx
  on public.join_attempts (room_id, ip_hash, created_at);
create index join_attempts_created_idx on public.join_attempts (created_at);

-- Seed konfigurasi (TASK.md bagian 3). Angka premium masih usulan.
insert into public.tier_limits (tier, max_active_rooms, max_guests_cap, max_messages_per_room)
values
  ('free', 3, 40, 5000),
  ('premium', 10, 75, 20000)
on conflict (tier) do update set
  max_active_rooms = excluded.max_active_rooms,
  max_guests_cap = excluded.max_guests_cap,
  max_messages_per_room = excluded.max_messages_per_room;

insert into public.app_config (key, value)
values
  ('message_max_length', '2000'::jsonb),
  ('messages_per_minute', '20'::jsonb),
  ('max_rooms_per_guest', '5'::jsonb),
  ('password_length', '6'::jsonb),
  ('lockout_fail_threshold', '5'::jsonb),
  ('lockout_window_minutes', '15'::jsonb),
  ('lockout_duration_minutes', '15'::jsonb),
  ('room_failure_cap_per_hour', '200'::jsonb),
  ('room_cooldown_minutes', '10'::jsonb),
  ('room_active_days', '7'::jsonb),
  ('room_grace_days', '15'::jsonb),
  ('pending_ttl_hours', '24'::jsonb),
  ('pending_cap_multiplier', '2'::jsonb),
  ('typing_global_enabled', 'true'::jsonb),
  ('typing_default_on_max_guests', '20'::jsonb)
on conflict (key) do update set
  value = excluded.value,
  updated_at = now();
