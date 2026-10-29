import { describe, expect, it } from 'vitest';
import { RoomRealtime } from './room-realtime';
import { FakeChannel, FakeClient } from './test-doubles';
import type { ChatMessage, RoomMember } from './types';

const ROOM_ID = '11111111-1111-4111-8111-111111111111';
const MEMBER_ID = '22222222-2222-4222-8222-222222222222';
const MEMBER_2_ID = '22222222-2222-4222-8222-222222222223';
const CLIENT_1 = '33333333-3333-4333-8333-333333333333';
const CLIENT_2 = '33333333-3333-4333-8333-333333333334';
const CLIENT_3 = '33333333-3333-4333-8333-333333333335';
const CREATED_AT = '2026-10-29T00:00:00.000Z';

function message(overrides: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: 1,
    room_id: ROOM_ID,
    sender_type: 'GUEST',
    member_id: MEMBER_ID,
    sender_name: 'Guest-01',
    content: 'halo',
    client_msg_id: CLIENT_1,
    created_at: CREATED_AT,
    ...overrides,
  };
}

function member(overrides: Partial<RoomMember> = {}): RoomMember {
  return {
    id: MEMBER_ID,
    room_id: ROOM_ID,
    member_no: 1,
    display_name: 'Guest-01',
    status: 'APPROVED',
    created_at: CREATED_AT,
    ...overrides,
  };
}

function flush(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function setup(options: {
  initialMessages?: ChatMessage[];
  initialMembers?: RoomMember[];
  memberId?: string | null;
  senderType?: 'HOST' | 'GUEST';
} = {}) {
  const client = new FakeClient();
  const rt = new RoomRealtime({
    client,
    roomId: ROOM_ID,
    memberId: options.memberId ?? MEMBER_ID,
    self: {
      senderType: options.senderType ?? 'GUEST',
      senderName: 'Guest-01',
    },
    initialMessages: options.initialMessages,
    initialMembers: options.initialMembers,
    createClientMsgId: () => CLIENT_1,
    now: () => new Date(CREATED_AT),
  });
  return { client, rt };
}

async function start(rt: RoomRealtime, client: FakeClient): Promise<FakeChannel> {
  rt.start();
  const channel = client.channels[0];
  if (!channel) throw new Error('channel belum dibuat');
  channel.emitStatus('SUBSCRIBED');
  await flush();
  return channel;
}

describe('RoomRealtime', () => {
  it('subscribe ke pesan + status dan memuat 50 riwayat awal', async () => {
    const { client, rt } = setup();
    client.rpcHandler = (name) => {
      if (name === 'list_messages') {
        return {
          data: [
            message({ id: 1, client_msg_id: CLIENT_1 }),
            message({ id: 2, client_msg_id: CLIENT_2, content: 'kedua' }),
          ],
          error: null,
        };
      }
      return { data: null, error: null };
    };

    const channel = await start(rt, client);
    expect(client.channelNames).toEqual([`room:${ROOM_ID}`]);
    expect(channel.handlers.map((handler) => [handler.filter.table, handler.filter.event])).toEqual([
      ['messages', 'INSERT'],
      ['room_members', '*'],
    ]);
    expect(rt.getSnapshot()).toMatchObject({
      status: 'connected',
      historyLoaded: true,
      messages: [{ id: 1 }, { id: 2 }],
    });
    expect(client.rpcCalls[0]).toMatchObject({
      name: 'list_messages',
      args: {
        p_room_id: ROOM_ID,
        p_after_id: null,
        p_limit: 50,
      },
    });
  });

  it('menggabungkan pesan realtime tanpa duplikat', async () => {
    const { client, rt } = setup({ initialMessages: [] });
    const channel = await start(rt, client);

    channel.emitRow('messages', message({ id: 1, client_msg_id: CLIENT_1 }));
    channel.emitRow('messages', message({ id: 1, client_msg_id: CLIENT_1 }));

    expect(rt.getSnapshot().messages).toHaveLength(1);
    expect(rt.getSnapshot().messages[0]?.content).toBe('halo');
  });

  it('mengirim optimistis lalu mengganti dengan baris server', async () => {
    const { client, rt } = setup({ initialMessages: [] });
    const channel = await start(rt, client);
    client.rpcHandler = (name) => {
      if (name === 'send_message') {
        return { data: message({ id: 7, client_msg_id: CLIENT_1 }), error: null };
      }
      return { data: null, error: null };
    };

    const pending = rt.sendMessage('  halo  ');
    expect(rt.getSnapshot().messages[0]).toMatchObject({
      id: -1,
      content: 'halo',
      optimistic: true,
      sendStatus: 'sending',
    });

    const result = await pending;
    expect(result).toMatchObject({ ok: true, message: { id: 7 } });
    expect(rt.getSnapshot().messages).toHaveLength(1);
    expect(rt.getSnapshot().messages[0]).toMatchObject({
      id: 7,
      content: 'halo',
      optimistic: undefined,
    });

    channel.emitRow('messages', message({ id: 7, client_msg_id: CLIENT_1 }));
    expect(rt.getSnapshot().messages).toHaveLength(1);
  });

  it('menandai gagal lalu bisa retry dengan client_msg_id yang sama', async () => {
    const { client, rt } = setup({ initialMessages: [] });
    await start(rt, client);
    client.rpcHandler = () => ({
      data: null,
      error: { message: 'RATE_LIMITED' },
    });

    const first = await rt.sendMessage('halo');
    expect(first).toEqual({ ok: false, error: 'RATE_LIMITED' });
    expect(rt.getSnapshot().messages[0]).toMatchObject({
      optimistic: true,
      sendStatus: 'failed',
      errorCode: 'RATE_LIMITED',
    });
    expect(rt.getSnapshot().lastError?.code).toBe('RATE_LIMITED');

    client.rpcHandler = () => ({
      data: message({ id: 8, client_msg_id: CLIENT_1 }),
      error: null,
    });
    const retried = await rt.retryMessage(CLIENT_1);
    expect(retried).toMatchObject({ ok: true, message: { id: 8 } });
    expect(rt.getSnapshot().messages[0]).toMatchObject({
      id: 8,
      optimistic: undefined,
    });
  });

  it('backfill lagi setelah reconnect memakai id terakhir', async () => {
    const { client, rt } = setup({
      initialMessages: [
        message({ id: 1, client_msg_id: CLIENT_1 }),
        message({ id: 2, client_msg_id: CLIENT_2 }),
      ],
    });
    const channel = await start(rt, client);
    expect(rt.getSnapshot().messages.map((item) => item.id)).toEqual([1, 2]);

    channel.emitStatus('CHANNEL_ERROR');
    await flush();
    expect(rt.getSnapshot()).toMatchObject({
      status: 'error',
      lastError: { code: 'REALTIME_ERROR' },
    });

    client.rpcHandler = (name) => {
      if (name === 'list_messages') {
        return {
          data: [message({ id: 3, client_msg_id: CLIENT_3 })],
          error: null,
        };
      }
      return { data: null, error: null };
    };
    channel.emitStatus('SUBSCRIBED');
    await flush();

    expect(rt.getSnapshot().status).toBe('connected');
    expect(rt.getSnapshot().messages.map((item) => item.id)).toEqual([1, 2, 3]);
    expect(client.rpcCalls.at(-1)).toMatchObject({
      name: 'list_messages',
      args: { p_after_id: 2, p_limit: 100 },
    });
  });

  it('memperbarui status member dan status diri sendiri', async () => {
    const { client, rt } = setup({
      initialMembers: [member()],
      initialStatus: 'APPROVED',
    });
    const channel = await start(rt, client);
    expect(rt.getSnapshot().selfStatus).toBe('APPROVED');

    channel.emitRow(
      'room_members',
      member({
        id: MEMBER_2_ID,
        member_no: 2,
        display_name: 'Guest-02',
        status: 'PENDING',
      }),
    );
    expect(rt.getSnapshot().members.map((item) => item.display_name)).toEqual([
      'Guest-01',
      'Guest-02',
    ]);

    channel.emitRow('room_members', member({ status: 'IDLE' }));
    expect(rt.getSnapshot().selfStatus).toBe('IDLE');
  });

  it('menutup channel saat stop dan menolak kirim setelahnya', async () => {
    const { client, rt } = setup({ initialMessages: [] });
    const channel = await start(rt, client);

    rt.stop();
    expect(rt.getSnapshot().status).toBe('closed');
    expect(client.removedChannels).toContain(channel);
    await expect(rt.sendMessage('halo')).resolves.toEqual({
      ok: false,
      error: 'REALTIME_CLOSED',
    });
  });
});
