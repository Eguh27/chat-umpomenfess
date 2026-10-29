import { describe, expect, it } from 'vitest';
import { hashIp, normalizeIp } from './ip';

describe('normalizeIp', () => {
  it('keeps ipv4', () => expect(normalizeIp('203.0.113.7')).toBe('203.0.113.7'));
  it('unwraps ipv4-mapped ipv6', () => expect(normalizeIp('::ffff:203.0.113.7')).toBe('203.0.113.7'));
  it('reduces ipv6 to /64', () => {
    expect(normalizeIp('2001:db8:1:2:aaaa:bbbb:cccc:dddd')).toBe('2001:0db8:0001:0002::/64');
    expect(normalizeIp('2001:db8:1:2::1')).toBe('2001:0db8:0001:0002::/64');
    expect(normalizeIp('2001:db8::1')).toBe('2001:0db8:0000:0000::/64');
  });
  it('same /64 gives same hash', () => {
    const salt = 'x'.repeat(32);
    expect(hashIp('2001:db8:1:2::1', salt)).toBe(hashIp('2001:db8:1:2:ffff::9', salt));
    expect(hashIp('2001:db8:1:3::1', salt)).not.toBe(hashIp('2001:db8:1:2::1', salt));
  });
  it('rejects weak salt and garbage', () => {
    expect(() => hashIp('1.2.3.4', 'short')).toThrow();
    expect(() => normalizeIp('not-an-ip')).toThrow();
  });
});
