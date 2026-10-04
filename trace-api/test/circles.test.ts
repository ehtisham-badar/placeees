import { describe, expect, it } from 'vitest';
import { inviteCode, normalizeCode } from '../src/circles/routes.js';

describe('invite codes', () => {
  it('are 8 unambiguous characters', () => {
    for (let i = 0; i < 200; i++) expect(inviteCode()).toMatch(/^[2-9A-HJKMNP-Z]{8}$/);
  });

  it('normalize what people type', () => {
    expect(normalizeCode(' h7k2-m9qx ')).toBe('H7K2M9QX');
  });
});
