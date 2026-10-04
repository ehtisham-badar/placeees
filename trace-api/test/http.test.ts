import { describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { hit } from '../src/lib/rateLimit.js';

describe('http', () => {
  it('rejects unauthenticated requests', async () => {
    const app = buildApp();
    const res = await app.inject({ method: 'GET', url: '/v1/me' });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: 'unauthorized' });
  });

  it('rate-limits sign-in per IP', async () => {
    const app = buildApp();
    const codes: number[] = [];
    for (let i = 0; i < 11; i++) {
      const res = await app.inject({ method: 'POST', url: '/v1/auth/google', payload: { idToken: 'x' } });
      codes.push(res.statusCode);
    }
    expect(codes.slice(0, 10).every((c) => c !== 429)).toBe(true);
    expect(codes[10]).toBe(429);
  });

  it('validates bodies', async () => {
    const app = buildApp();
    const res = await app.inject({ method: 'POST', url: '/v1/auth/google', payload: {} });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('invalid_request');
  });
});

describe('per-user action windows', () => {
  it('allows up to max per window, then refuses until it slides', () => {
    const t0 = 1_000_000;
    for (let i = 0; i < 3; i++) expect(hit('k', 3, 60_000, t0 + i)).toBe(true);
    expect(hit('k', 3, 60_000, t0 + 10)).toBe(false);
    expect(hit('k', 3, 60_000, t0 + 60_001)).toBe(true);
  });
});

describe('surfaces', () => {
  it('hides the admin API when no token is configured', async () => {
    const res = await buildApp().inject({ method: 'GET', url: '/v1/admin/queue' });
    expect(res.statusCode).toBe(404);
  });

  it('serves app-link verification files', async () => {
    const app = buildApp();
    const aasa = await app.inject({ method: 'GET', url: '/.well-known/apple-app-site-association' });
    expect(aasa.json().applinks.details[0].components).toEqual([{ '/': '/v/*' }]);
    const assetlinks = await app.inject({ method: 'GET', url: '/.well-known/assetlinks.json' });
    expect(assetlinks.json()[0].target.package_name).toBe('app.trace.mobile');
  });
});
