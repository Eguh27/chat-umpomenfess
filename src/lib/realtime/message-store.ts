import type { ChatMessage, SenderType } from './types';

export interface OptimisticInput {
  roomId: string;
  memberId: string | null;
  senderType: SenderType;
  senderName: string;
  content: string;
  clientMsgId: string;
  createdAt: string;
}

/**
 * Menyimpan pesan server + optimistis.
 * Dedupe memakai `id` (server) dan `client_msg_id` (idempotensi RPC).
 */
export class MessageStore {
  private readonly byId = new Map<number, ChatMessage>();
  private readonly byClientId = new Map<string, ChatMessage>();
  private nextTempId = -1;

  addServer(message: ChatMessage): void {
    if (this.byId.has(message.id)) return;

    const existingByClient = this.byClientId.get(message.client_msg_id);
    if (existingByClient && !existingByClient.optimistic) return;
    if (existingByClient) {
      this.byId.delete(existingByClient.id);
      this.byClientId.delete(existingByClient.client_msg_id);
    }

    this.byId.set(message.id, message);
    this.byClientId.set(message.client_msg_id, message);
  }

  addServerMany(messages: ChatMessage[]): void {
    for (const message of messages) this.addServer(message);
  }

  addOptimistic(input: OptimisticInput): ChatMessage {
    const tempId = this.nextTempId--;
    const message: ChatMessage = {
      id: tempId,
      room_id: input.roomId,
      sender_type: input.senderType,
      member_id: input.memberId,
      sender_name: input.senderName,
      content: input.content,
      client_msg_id: input.clientMsgId,
      created_at: input.createdAt,
      optimistic: true,
      sendStatus: 'sending',
    };
    this.byId.set(tempId, message);
    this.byClientId.set(input.clientMsgId, message);
    return message;
  }

  markFailed(clientMsgId: string, errorCode: string): ChatMessage | null {
    return this.updateOptimistic(clientMsgId, { sendStatus: 'failed', errorCode });
  }

  markSending(clientMsgId: string): ChatMessage | null {
    return this.updateOptimistic(clientMsgId, { sendStatus: 'sending', errorCode: undefined });
  }

  getByClientId(clientMsgId: string): ChatMessage | undefined {
    return this.byClientId.get(clientMsgId);
  }

  getMessages(): ChatMessage[] {
    const server: ChatMessage[] = [];
    const optimistic: ChatMessage[] = [];
    for (const message of this.byId.values()) {
      if (message.optimistic) optimistic.push(message);
      else server.push(message);
    }
    server.sort((a, b) => a.id - b.id);
    optimistic.sort((a, b) => b.id - a.id);
    return [...server, ...optimistic];
  }

  getLastServerId(): number {
    let last = 0;
    for (const message of this.byId.values()) {
      if (!message.optimistic && message.id > last) last = message.id;
    }
    return last;
  }

  clear(): void {
    this.byId.clear();
    this.byClientId.clear();
    this.nextTempId = -1;
  }

  private updateOptimistic(
    clientMsgId: string,
    patch: Pick<ChatMessage, 'sendStatus' | 'errorCode'>,
  ): ChatMessage | null {
    const current = this.byClientId.get(clientMsgId);
    if (!current?.optimistic) return null;
    const updated: ChatMessage = { ...current, ...patch };
    this.byId.set(updated.id, updated);
    this.byClientId.set(clientMsgId, updated);
    return updated;
  }
}
