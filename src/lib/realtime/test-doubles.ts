import type {
  PostgresChangeFilter,
  RealtimeChannelLike,
  RealtimeClientLike,
  RpcResult,
} from './types';

type RowCallback = (payload: { new: Record<string, unknown> }) => void;

/** Channel tiruan: merekam listener dan bisa memicu event secara manual. */
export class FakeChannel implements RealtimeChannelLike {
  readonly handlers: Array<{ filter: PostgresChangeFilter; callback: RowCallback }> = [];
  statusCallback: ((status: string, error?: Error) => void) | null = null;
  unsubscribed = false;

  on(
    _event: 'postgres_changes',
    filter: PostgresChangeFilter,
    callback: RowCallback,
  ): RealtimeChannelLike {
    this.handlers.push({ filter, callback });
    return this;
  }

  subscribe(callback: (status: string, error?: Error) => void): RealtimeChannelLike {
    this.statusCallback = callback;
    return this;
  }

  unsubscribe(): Promise<unknown> {
    this.unsubscribed = true;
    return Promise.resolve('ok');
  }

  emitRow(table: string, row: Record<string, unknown>): void {
    for (const handler of this.handlers) {
      if (handler.filter.table === table) handler.callback({ new: row });
    }
  }

  emitStatus(status: string): void {
    this.statusCallback?.(status);
  }
}

export type RpcHandler = (name: string, args: Record<string, unknown>) => RpcResult<unknown>;

/** Client tiruan: tidak ada jaringan; RPC dijawab oleh rpcHandler. */
export class FakeClient implements RealtimeClientLike {
  readonly channelNames: string[] = [];
  readonly channels: FakeChannel[] = [];
  readonly rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  readonly removedChannels: FakeChannel[] = [];
  rpcHandler: RpcHandler = () => ({ data: null, error: null });

  channel(name: string): RealtimeChannelLike {
    this.channelNames.push(name);
    const channel = new FakeChannel();
    this.channels.push(channel);
    return channel;
  }

  rpc<T = unknown>(name: string, args: Record<string, unknown>): Promise<RpcResult<T>> {
    this.rpcCalls.push({ name, args });
    return Promise.resolve(this.rpcHandler(name, args) as RpcResult<T>);
  }

  removeChannel(channel: RealtimeChannelLike): Promise<unknown> {
    this.removedChannels.push(channel as FakeChannel);
    return Promise.resolve('ok');
  }
}
