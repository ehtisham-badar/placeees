import { describe, expect, it } from 'vitest';
import { verifyLocal } from '../src/media/local.js';

// Signing uses JWT_SECRET; build URLs by hand with the same helper the server uses.
const { createHmac } = await import('node:crypto');
const { config } = await import('../src/config.js');
const sig = (op: string, key: string, exp: number) =>
  createHmac('sha256', config.JWT_SECRET).update(`trace-media|${op}|${key}|${exp}`).digest('base64url');

const KEY = 'drops/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222.m4a';
const NOW = Date.parse('2026-10-05T12:00:00Z');
const EXP = NOW / 1000 + 300;

describe('local media URLs', () => {
  it('accept a valid, unexpired signature for the same operation', () => {
    expect(verifyLocal('get', KEY, EXP, sig('get', KEY, EXP), NOW)).toBe(true);
  });

  it('reject expired, tampered, cross-operation and path-escaping requests', () => {
    expect(verifyLocal('get', KEY, EXP, sig('get', KEY, EXP), (EXP + 1) * 1000)).toBe(false);
    expect(verifyLocal('get', KEY, EXP + 60, sig('get', KEY, EXP), NOW)).toBe(false);
    expect(verifyLocal('put', KEY, EXP, sig('get', KEY, EXP), NOW)).toBe(false);
    const evil = 'drops/../../etc/passwd';
    expect(verifyLocal('get', evil, EXP, sig('get', evil, EXP), NOW)).toBe(false);
  });
});
