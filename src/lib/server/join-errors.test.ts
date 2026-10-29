import { describe, expect, it } from 'vitest';
import { mapJoinError, parseRetryAfter } from './join-errors';

describe('parseRetryAfter', () => {
  it('membaca retry_after dari DETAIL JSON', () => {
    expect(parseRetryAfter('{"retry_after":600}')).toBe(600);
  });

  it('membulatkan ke atas', () => {
    expect(parseRetryAfter('{"retry_after":12.2}')).toBe(13);
  });

  it('mengabaikan nilai kosong/tidak valid', () => {
    expect(parseRetryAfter(null)).toBeNull();
    expect(parseRetryAfter('bukan json')).toBeNull();
    expect(parseRetryAfter('{}')).toBeNull();
    expect(parseRetryAfter('{"retry_after":0}')).toBeNull();
    expect(parseRetryAfter('{"retry_after":-5}')).toBeNull();
  });
});

describe('mapJoinError', () => {
  it('password salah -> 401', () => {
    expect(mapJoinError('WRONG_PASSWORD')).toEqual({
      status: 401,
      body: { error: 'WRONG_PASSWORD' },
    });
  });

  it('terkunci -> 429 + Retry-After', () => {
    expect(mapJoinError('LOCKED', '{"retry_after":600}')).toEqual({
      status: 429,
      body: { error: 'LOCKED', retryAfter: 600 },
      headers: { 'retry-after': '600' },
    });
  });

  it('cooldown -> 429 + Retry-After', () => {
    expect(mapJoinError('ROOM_COOLDOWN', '{"retry_after":30}')).toEqual({
      status: 429,
      body: { error: 'ROOM_COOLDOWN', retryAfter: 30 },
      headers: { 'retry-after': '30' },
    });
  });

  it('429 tanpa detail tetap 429', () => {
    expect(mapJoinError('LOCKED', null)).toEqual({
      status: 429,
      body: { error: 'LOCKED' },
      headers: undefined,
    });
  });

  it.each([
    'ROOM_FULL',
    'MAX_ROOMS_PER_GUEST',
    'KICKED',
    'REJECTED',
    'ROOM_CLOSED',
  ])('%s -> 403', (code) => {
    expect(mapJoinError(code)).toEqual({
      status: 403,
      body: { error: code },
    });
  });

  it('room tidak ditemukan -> 404', () => {
    expect(mapJoinError('ROOM_NOT_FOUND')).toEqual({
      status: 404,
      body: { error: 'ROOM_NOT_FOUND' },
    });
  });

  it('input tidak valid -> 400', () => {
    expect(mapJoinError('INVALID_INPUT')).toEqual({
      status: 400,
      body: { error: 'INVALID_INPUT' },
    });
  });

  it('kode tak dikenal tidak membocorkan detail -> 500', () => {
    expect(mapJoinError('SOMETHING_INTERNAL')).toEqual({
      status: 500,
      body: { error: 'SERVER_ERROR' },
    });
  });
});
