import { describe, expect, it } from 'vitest';
import { MessageStore } from './message-store';
import type { ChatMessage } from './types';

function message(overrides: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: 1,
    room_id: 'room-1',
    sender_type: 'GUEST',
    member_id: 'member-1',
    sender_name: 'Guest-01',
    content: 'halo',
    client_msg_id: 'client-1',
    created_at: '2026-10-29T00:00:00.000Z',
    ...overrides,
  };
}

function optimistic(store: MessageStore, clientMsgId: string, content = 'halo') {
  return store.addOptimistic({
    roomId: 'room-1',
    memberId: 'member-1',
    senderType: 'GUEST',
    senderName: 'Guest-01',
    content,
    clientMsgId,
    createdAt: '2026-10-29T00:00:00.000Z',
  });
}

describe('MessageStore', () => {
  it('mengurutkan pesan server dan membuang duplikat id', () => {
    const store = new MessageStore();
    store.addServerMany([
      message({ id: 2, client_msg_id: 'c2' }),
      message({ id: 1, client_msg_id: 'c1' }),
      message({ id: 2, client_msg_id: 'c2', content: 'duplikat' }),
    ]);

    expect(store.getMessages().map((item) => item.id)).toEqual([1, 2]);
    expect(store.getMessages()[1]?.content).toBe('halo');
    expect(store.getLastServerId()).toBe(2);
  });

  it('membuang duplikat client_msg_id dari server', () => {
    const store = new MessageStore();
    store.addServer(message({ id: 1, client_msg_id: 'same' }));
    store.addServer(message({ id: 2, client_msg_id: 'same' }));

    expect(store.getMessages()).toHaveLength(1);
    expect(store.getMessages()[0]?.id).toBe(1);
  });

  it('mengganti pesan optimistis dengan baris server', () => {
    const store = new MessageStore();
    const pending = optimistic(store, 'client-1');
    expect(pending.optimistic).toBe(true);
    expect(store.getMessages()[0]?.id).toBeLessThan(0);

    store.addServer(message({ id: 10, client_msg_id: 'client-1' }));

    expect(store.getMessages()).toHaveLength(1);
    expect(store.getMessages()[0]?.id).toBe(10);
    expect(store.getMessages()[0]?.optimistic).toBeUndefined();
  });

  it('menjaga urutan pesan optimistis sesuai urutan kirim', () => {
    const store = new MessageStore();
    optimistic(store, 'c1', 'pertama');
    optimistic(store, 'c2', 'kedua');

    expect(store.getMessages().map((item) => item.client_msg_id)).toEqual(['c1', 'c2']);
  });

  it('menandai gagal dan mengembalikan ke status mengirim', () => {
    const store = new MessageStore();
    optimistic(store, 'c1');

    expect(store.markFailed('c1', 'RATE_LIMITED')?.sendStatus).toBe('failed');
    expect(store.getByClientId('c1')?.errorCode).toBe('RATE_LIMITED');

    expect(store.markSending('c1')?.sendStatus).toBe('sending');
    expect(store.getByClientId('c1')?.errorCode).toBeUndefined();
  });

  it('mengabaikan operasi pada pesan yang tidak ada', () => {
    const store = new MessageStore();
    expect(store.markFailed('tidak-ada', 'X')).toBeNull();
    expect(store.markSending('tidak-ada')).toBeNull();
  });
});
