/**
 * Nilai default yang DICERMINKAN dari database (tabel tier_limits & app_config).
 * Sumber kebenaran = database. File ini hanya untuk teks UI / validasi sisi client.
 * Jika angka berubah, ubah di database dulu (lihat TASK.md bagian 4).
 */
export const TIER_DEFAULTS = {
  free: { maxActiveRooms: 3, maxGuestsCap: 40, maxMessagesPerRoom: 5000 },
  premium: { maxActiveRooms: 10, maxGuestsCap: 75, maxMessagesPerRoom: 20000 },
} as const;

export const APP_DEFAULTS = {
  roomActiveDays: 7,
  roomGraceDays: 15,
  messageMaxLength: 2000,
  messagesPerMinutePerGuest: 20,
  maxRoomsPerGuest: 5,
  passwordLength: 6,
  historyPageSize: 50,
  idleTimeoutMinutesDefault: 30,
  idleTimeoutMinutesMin: 10,
  idleTimeoutMinutesMax: 240,
  heartbeatSeconds: 120,
  typingThrottleSeconds: 5,
  typingExpireSeconds: 6,
} as const;

export type Tier = keyof typeof TIER_DEFAULTS;
