import type { SupabaseClient } from '@supabase/supabase-js';
import { APP_DEFAULTS } from '../config';
import { MessageStore } from './message-store';
import type {
  ChatMessage,
  MemberStatus,
  RealtimeChannelLike,
  RealtimeClientLike,
  RealtimeConnectionStatus,
  RealtimeError,
  RoomMember,
  RoomRealtimeSnapshot,
  SendResult,
} from './types';

const CHANNEL_PREFIX = 'room:';
const INITIAL_PAGE_SIZE = APP_DEFAULTS.historyPageSize;
const BACKFILL_PAGE_SIZE = 100;
/** Batas aman backfill: 50 halaman x 100 pesan = 5000 pesan (kapasitas maksimum room). */
const MAX_BACKFILL_PAGES = 50;

const MEMBER_STATUSES: ReadonlySet<MemberStatus> = new Set([
  'PENDING',
  'APPROVED',
  'REJECTED',
  'KICKED',
  'IDLE',
  'LEFT',
]);

export interface RoomRealtimeOptions {
  client: RealtimeClientLike;
  roomId: string;
  memberId: string | null;
  self: { senderType: 'HOST' | 'GUEST'; senderName: string };
  initialMessages?: ChatMessage[];
  initialMembers?: RoomMember[];
  initialStatus?: MemberStatus | null;
  pageSize?: number;
  createClientMsgId?: () => string;
  now?: () => Date;
}

export type CreateRoomRealtimeOptions = Omit<RoomRealtimeOptions, 'client'> & {
  client: SupabaseClient;
};

/**
 * Satu instance = satu room yang sedang dibuka.
 * - Pesan: Postgres Changes INSERT + backfill `list_messages(p_after_id)` setiap SUBSCRIBED.
 * - Status member: Postgres Changes pada room_members (Guest hanya menerima barisnya sendiri).
 * - Kirim optimistis: id sementara negatif, diganti baris server dengan client_msg_id yang sama.
 */
export class RoomRealtime {
  private readonly client: RealtimeClientLike;
  private readonly roomId: string;
  private readonly memberId: string | null;
  private readonly self: RoomRealtimeOptions['self'];
  private readonly pageSize: number;
  private readonly createClientMsgId: () => string;
  private readonly now: () => Date;
  private readonly store = new MessageStore();
  private readonly members = new Map<string, RoomMember>();
  private readonly listeners = new Set<() => void>();
  private channel: RealtimeChannelLike | null = null;
  private status: RealtimeConnectionStatus = 'idle';
  private selfStatus: MemberStatus | null = null;
  private historyLoaded = false;
  private lastError: RealtimeError | null = null;
  private snapshot: RoomRealtimeSnapshot;
  private backfillPromise: Promise<void> | null = null;
  private stopped = false;

  constructor(options: RoomRealtimeOptions) {
    this.client = options.client;
    this.roomId = options.roomId;
    this.memberId = options.memberId;
    this.self = options.self;
    this.pageSize = Math.min(Math.max(options.pageSize ?? BACKFILL_PAGE_SIZE, 1), 100);
    this.createClientMsgId = options.createClientMsgId ?? (() => crypto.randomUUID());
    this.now = options.now ?? (() => new Date());
    this.store.addServerMany(options.initialMessages ?? []);
    this.historyLoaded = options.initialMessages !== undefined;
    this.selfStatus = options.initialStatus ?? null;
    for (const member of options.initialMembers ?? []) {
      this.members.set(member.id, member);
      if (member.id === this.memberId) this.selfStatus = member.status;
    }
    this.snapshot = this.buildSnapshot();
  }

  start(): void {
    if (this.channel || this.stopped) return;
    this.setStatus('connecting');

    const channel = this.client.channel(`${CHANNEL_PREFIX}${this.roomId}`);
    channel.on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'messages',
        filter: `room_id=eq.${this.roomId}`,
      },
      (payload) => this.handleMessage(payload.new),
    );
    channel.on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'room_members',
        filter: `room_id=eq.${this.roomId}`,
      },
      (payload) => this.handleMember(payload.new),
    );
    this.channel = channel;
    channel.subscribe((status) => this.handleSubscribeStatus(status));
  }

  stop(): void {
    if (this.stopped) return;
    this.stopped = true;
    const channel = this.channel;
    this.channel = null;
    this.setStatus('closed');
    if (!channel) return;

    try {
      if (this.client.removeChannel) {
        void Promise.resolve(this.client.removeChannel(channel)).catch(() => undefined);
      } else {
        void Promise.resolve(channel.unsubscribe()).catch(() => undefined);
      }
    } catch {
      // Channel mungkin sudah tertutup; tidak ada yang perlu dilakukan.
    }
  }

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  getSnapshot = (): RoomRealtimeSnapshot => this.snapshot;

  getLastServerId(): number {
    return this.store.getLastServerId();
  }

  /** Backfill manual; juga dipanggil otomatis setiap SUBSCRIBED. */
  refresh(): Promise<void> {
    if (this.backfillPromise) return this.backfillPromise;
    this.backfillPromise = this.runBackfill().finally(() => {
      this.backfillPromise = null;
    });
    return this.backfillPromise;
  }

  async sendMessage(content: string): Promise<SendResult> {
    if (this.stopped) return { ok: false, error: 'REALTIME_CLOSED' };

    const trimmed = content.trim();
    if (trimmed.length === 0) return { ok: false, error: 'INVALID_INPUT' };
    if (trimmed.length > APP_DEFAULTS.messageMaxLength) {
      return { ok: false, error: 'MESSAGE_TOO_LONG' };
    }

    const clientMsgId = this.createClientMsgId();
    const optimistic = this.store.addOptimistic({
      roomId: this.roomId,
      memberId: this.memberId,
      senderType: this.self.senderType,
      senderName: this.self.senderName,
      content: trimmed,
      clientMsgId,
      createdAt: this.now().toISOString(),
    });
    this.emit();
    return this.sendOptimistic(optimistic);
  }

  async retryMessage(clientMsgId: string): Promise<SendResult> {
    if (this.stopped) return { ok: false, error: 'REALTIME_CLOSED' };

    const current = this.store.getByClientId(clientMsgId);
    if (!current?.optimistic) return { ok: false, error: 'NOT_FOUND' };

    const updated = this.store.markSending(clientMsgId);
    this.emit();
    return this.sendOptimistic(updated ?? current);
  }

  private async sendOptimistic(message: ChatMessage): Promise<SendResult> {
    try {
      const { data, error } = await this.client.rpc<ChatMessage[] | ChatMessage>('send_message', {
        p_room_id: this.roomId,
        p_content: message.content,
        p_client_msg_id: message.client_msg_id,
      });

      if (error) {
        // Realtime bisa lebih dulu tiba daripada respons RPC. Kalau baris server
        // sudah masuk lewat Realtime, jangan tandai pesan sebagai gagal.
        const current = this.store.getByClientId(message.client_msg_id);
        if (current && !current.optimistic) {
          this.lastError = null;
          this.emit();
          return { ok: true, message: current };
        }
        this.store.markFailed(message.client_msg_id, error.message);
        this.setError(error.message);
        return { ok: false, error: error.message };
      }

      const row = toArray(data)[0];
      if (!row) {
        const current = this.store.getByClientId(message.client_msg_id);
        if (current && !current.optimistic) {
          this.lastError = null;
          this.emit();
          return { ok: true, message: current };
        }
        this.store.markFailed(message.client_msg_id, 'SERVER_ERROR');
        this.setError('SERVER_ERROR');
        return { ok: false, error: 'SERVER_ERROR' };
      }

      this.store.addServer(row);
      this.lastError = null;
      this.emit();
      return { ok: true, message: row };
    } catch {
      this.store.markFailed(message.client_msg_id, 'SERVER_ERROR');
      this.setError('SERVER_ERROR');
      return { ok: false, error: 'SERVER_ERROR' };
    }
  }

  private handleSubscribeStatus(status: string): void {
    if (this.stopped) return;

    if (status === 'SUBSCRIBED') {
      this.lastError = null;
      this.setStatus('connected');
      void this.refresh();
      return;
    }
    if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
      this.setStatus('error');
      this.setError('REALTIME_ERROR');
      return;
    }
    if (status === 'CLOSED') this.setStatus('closed');
  }

  private async runBackfill(): Promise<void> {
    try {
      if (this.store.getLastServerId() <= 0) {
        // Riwayat awal: 50 pesan terakhir. Pesan yang lebih lama dimuat oleh
        // paginasi riwayat (T-41), bukan oleh backfill realtime.
        const { data, error } = await this.client.rpc<ChatMessage[] | ChatMessage>(
          'list_messages',
          {
            p_room_id: this.roomId,
            p_after_id: null,
            p_limit: INITIAL_PAGE_SIZE,
          },
        );

        if (this.stopped) return;
        if (error) {
          this.setError(error.message);
          return;
        }

        this.store.addServerMany(toArray(data));
        this.historyLoaded = true;
        this.lastError = null;
        this.emit();
        return;
      }

      let cursor = this.store.getLastServerId();
      for (let page = 0; page < MAX_BACKFILL_PAGES; page += 1) {
        const { data, error } = await this.client.rpc<ChatMessage[] | ChatMessage>(
          'list_messages',
          {
            p_room_id: this.roomId,
            p_after_id: cursor,
            p_limit: this.pageSize,
          },
        );

        if (this.stopped) return;
        if (error) {
          this.setError(error.message);
          return;
        }

        const rows = toArray(data);
        if (rows.length === 0) break;
        this.store.addServerMany(rows);

        const next = this.store.getLastServerId();
        if (next <= cursor) break;
        cursor = next;
        if (rows.length < this.pageSize) break;
      }

      this.historyLoaded = true;
      this.lastError = null;
      this.emit();
    } catch {
      this.setError('REALTIME_ERROR');
    }
  }

  private handleMessage(raw: Record<string, unknown>): void {
    if (!isChatMessage(raw) || raw.room_id !== this.roomId) return;
    this.store.addServer(raw);
    this.emit();
  }

  private handleMember(raw: Record<string, unknown>): void {
    if (!isRoomMember(raw)) return;
    if (raw.room_id && raw.room_id !== this.roomId) return;
    this.members.set(raw.id, raw);
    if (raw.id === this.memberId) this.selfStatus = raw.status;
    this.emit();
  }

  private setStatus(status: RealtimeConnectionStatus): void {
    this.status = status;
    this.emit();
  }

  private setError(code: string): void {
    this.lastError = { code, at: this.now().toISOString() };
    this.emit();
  }

  private emit(): void {
    this.snapshot = this.buildSnapshot();
    for (const listener of this.listeners) listener();
  }

  private buildSnapshot(): RoomRealtimeSnapshot {
    return {
      status: this.status,
      messages: this.store.getMessages(),
      members: [...this.members.values()].sort(compareMembers),
      selfStatus: this.selfStatus,
      historyLoaded: this.historyLoaded,
      lastError: this.lastError,
    };
  }
}

/** Boundary aman: SupabaseClient asli dipetakan ke subset struktural yang dites. */
export function createRoomRealtime(options: CreateRoomRealtimeOptions): RoomRealtime {
  return new RoomRealtime({
    ...options,
    client: options.client as unknown as RealtimeClientLike,
  });
}

function toArray<T>(data: T[] | T | null): T[] {
  if (data === null) return [];
  return Array.isArray(data) ? data : [data];
}

function compareMembers(a: RoomMember, b: RoomMember): number {
  const aNo = a.member_no ?? Number.MAX_SAFE_INTEGER;
  const bNo = b.member_no ?? Number.MAX_SAFE_INTEGER;
  if (aNo !== bNo) return aNo - bNo;
  return a.id.localeCompare(b.id);
}

function isChatMessage(value: unknown): value is ChatMessage {
  if (!value || typeof value !== 'object') return false;
  const row = value as Record<string, unknown>;
  return (
    typeof row.id === 'number' &&
    typeof row.room_id === 'string' &&
    (row.sender_type === 'HOST' || row.sender_type === 'GUEST') &&
    (row.member_id === null || typeof row.member_id === 'string') &&
    typeof row.sender_name === 'string' &&
    typeof row.content === 'string' &&
    typeof row.client_msg_id === 'string' &&
    typeof row.created_at === 'string'
  );
}

function isRoomMember(value: unknown): value is RoomMember {
  if (!value || typeof value !== 'object') return false;
  const row = value as Record<string, unknown>;
  return (
    typeof row.id === 'string' &&
    typeof row.status === 'string' &&
    MEMBER_STATUSES.has(row.status as MemberStatus) &&
    (row.display_name === null || typeof row.display_name === 'string') &&
    (row.room_id === undefined || typeof row.room_id === 'string')
  );
}
