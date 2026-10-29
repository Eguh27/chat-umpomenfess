/* Data tiruan untuk kerangka UI statis (T-31).
   Kontrak nyata menyusul di T-50..T-54; jangan di-import dari modul server.
   Semua identitas di sini fiktif: nama Guest tanpa user_id (S-09). */

export interface Quota {
  used: number;
  max: number;
  tier: 'free' | 'premium';
}

export interface HostRoom {
  id: string;
  slug: string;
  name: string;
  status: 'ACTIVE' | 'CLOSED';
  approvedCount: number;
  pendingCount: number;
  maxGuests: number;
  endsIn: string;
  typingOn: boolean;
}

export interface ChatMessage {
  id: number;
  sender: 'HOST' | 'GUEST';
  name: string;
  time: string;
  text: string;
}

export interface PendingMember {
  id: string;
  requestedAt: string;
}

export interface ApprovedMember {
  no: string;
  lastActive: string;
}

export interface MyRoom {
  name: string;
  slug: string;
  displayName: string;
  status: 'APPROVED' | 'PENDING';
  unread: number;
  endsIn: string;
}

export const quota: Quota = { used: 2, max: 3, tier: 'free' };

export const hostRooms: HostRoom[] = [
  {
    id: 'demo-room-1',
    slug: 'k3tK9mQp2weR7uds',
    name: 'Rapat & Koordinasi KKN',
    status: 'ACTIVE',
    approvedCount: 12,
    pendingCount: 2,
    maxGuests: 40,
    endsIn: 'berakhir 6 hari',
    typingOn: true,
  },
  {
    id: 'demo-room-2',
    slug: 'xD8pWnQ3sJmT2vhL',
    name: 'Curhat Sesama Mahasiswa',
    status: 'ACTIVE',
    approvedCount: 23,
    pendingCount: 0,
    maxGuests: 40,
    endsIn: 'berakhir 2 hari',
    typingOn: true,
  },
  {
    id: 'demo-room-3',
    slug: 'pN4rFzK7bWqM8jcD',
    name: 'Musyawarah Persewaan',
    status: 'CLOSED',
    approvedCount: 18,
    pendingCount: 0,
    maxGuests: 25,
    endsIn: 'arsip 14 hari lagi',
    typingOn: false,
  },
];

/** Password tampil sekali — hanya contoh render (Space Mono, tanpa lega). */
export const newRoomPassword = 'K3TX9M';

export const guestRoomName = 'Ngobrol Santai (demo)';

export const chat: ChatMessage[] = [
  { id: 1, sender: 'HOST', name: 'Host', time: '14:00', text: 'Selamat datang semua. Jadi geladi besok jam 07.00 di gerbang kampus ya.' },
  { id: 2, sender: 'GUEST', name: 'Guest-01', time: '14:01', text: 'Siap. Yang bawa alat ramping-an, inget bareng-bareng ya.' },
  { id: 3, sender: 'GUEST', name: 'Guest-03', time: '14:03', text: 'Aku bawa satu alat, nanti bisa dipinjem kalau ada yang lupa.' },
  { id: 4, sender: 'GUEST', name: 'Guest-02', time: '14:04', text: 'Kalau gerbang ternyata ditutup, titik kumpul lanjutannya di mana?' },
  { id: 5, sender: 'HOST', name: 'Host', time: '14:05', text: 'Masjid kampus. Info lanjut menyusul di sini juga.' },
];

export const pendingMembers: PendingMember[] = [
  { id: 'pm-1', requestedAt: '3 menit lalu' },
  { id: 'pm-2', requestedAt: '11 menit lalu' },
];

export const approvedMembers: ApprovedMember[] = [
  { no: '01', lastActive: 'aktif baru saja' },
  { no: '02', lastActive: 'aktif 2 menit lalu' },
  { no: '03', lastActive: 'aktif 4 menit lalu' },
  { no: '04', lastActive: 'aktif 5 menit lalu' },
  { no: '07', lastActive: 'aktif 20 menit lalu' },
];

export const myRooms: MyRoom[] = [
  {
    name: 'Rapat & Koordinasi KKN',
    slug: 'k3tK9mQp2weR7uds',
    displayName: 'Guest-02',
    status: 'APPROVED',
    unread: 3,
    endsIn: 'berakhir 6 hari',
  },
  {
    name: 'Curhat Sesama Mahasiswa',
    slug: 'xD8pWnQ3sJmT2vhL',
    displayName: 'Guest-05',
    status: 'PENDING',
    unread: 0,
    endsIn: 'berakhir 2 hari',
  },
];

/** Keadaan Guest untuk pratinjau statis lewat ?state= (verifikasi bagian 11). */
export const guestStates: Array<{ key: string; label: string }> = [
  { key: 'disclaimer', label: 'disclaimer' },
  { key: 'password', label: 'form password' },
  { key: 'salah', label: 'password salah' },
  { key: 'kunci', label: 'terkunci' },
  { key: 'penuh', label: 'kursi penuh' },
  { key: 'pending', label: 'menunggu persetujuan' },
  { key: 'ditolak', label: 'ditolak' },
  { key: 'keluar', label: 'dikeluarkan' },
  { key: 'idle', label: 'keluar otomatis (idle)' },
  { key: 'tutup', label: 'room ditutup' },
  { key: 'maks', label: 'batas 5 room' },
  { key: 'chat', label: 'obrolan' },
];
