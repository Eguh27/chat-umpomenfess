import { useEffect, useMemo, useSyncExternalStore } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createRoomRealtime } from './room-realtime';
import type {
  ChatMessage,
  MemberStatus,
  RoomMember,
  RoomRealtimeSnapshot,
  SendResult,
  SenderType,
} from './types';

export interface UseRoomRealtimeOptions {
  client: SupabaseClient;
  roomId: string;
  memberId: string | null;
  senderType: SenderType;
  senderName: string;
  initialMessages?: ChatMessage[];
  initialMembers?: RoomMember[];
  initialStatus?: MemberStatus | null;
  createClientMsgId?: () => string;
}

export interface UseRoomRealtimeResult {
  snapshot: RoomRealtimeSnapshot;
  sendMessage: (content: string) => Promise<SendResult>;
  retryMessage: (clientMsgId: string) => Promise<SendResult>;
}

/** Hook tipis untuk React island; logika ada di RoomRealtime (framework-agnostic). */
export function useRoomRealtime(options: UseRoomRealtimeOptions): UseRoomRealtimeResult {
  const {
    client,
    roomId,
    memberId,
    senderType,
    senderName,
    initialMessages,
    initialMembers,
    initialStatus,
    createClientMsgId,
  } = options;

  const realtime = useMemo(
    () =>
      createRoomRealtime({
        client,
        roomId,
        memberId,
        self: { senderType, senderName },
        initialMessages,
        initialMembers,
        initialStatus,
        createClientMsgId,
      }),
    // Data awal bersifat snapshot saat room dibuka; perubahan berikutnya datang dari Realtime.
    [client, roomId, memberId, senderType, senderName, initialStatus],
  );

  useEffect(() => {
    realtime.start();
    return () => realtime.stop();
  }, [realtime]);

  const snapshot = useSyncExternalStore(
    realtime.subscribe,
    realtime.getSnapshot,
    realtime.getSnapshot,
  );

  return {
    snapshot,
    sendMessage: (content) => realtime.sendMessage(content),
    retryMessage: (clientMsgId) => realtime.retryMessage(clientMsgId),
  };
}
