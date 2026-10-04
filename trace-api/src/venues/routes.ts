import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { normalizeCode } from '../circles/routes.js';
import { config } from '../config.js';
import { sql } from '../db/client.js';
import { fuzzyCircle } from '../drops/fuzz.js';
import { notFound } from '../lib/errors.js';

interface VenueRow {
  code: string;
  name: string;
  dropId: string;
  type: string;
  teaser: string | null;
  lat: number;
  lng: number;
}

async function findVenue(raw: string): Promise<VenueRow | undefined> {
  const [v] = await sql<VenueRow[]>`
    SELECT v.code, v.name, v.drop_id, d.type, d.teaser, ST_Y(d.geo::geometry) AS lat, ST_X(d.geo::geometry) AS lng
    FROM venues v JOIN drops d ON d.id = v.drop_id
    WHERE v.code = ${normalizeCode(raw)} AND d.status = 'approved' AND d.visibility = 'public'`;
  return v;
}

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

/** What someone without the app sees after scanning a venue QR code or tapping an NFC tag (spec F-16). */
export function venueLandingHtml(v: { code: string; name: string; teaser: string | null } | null): string {
  const title = v ? `Something is waiting at ${esc(v.name)}` : 'This Trace has moved on';
  const store = [
    config.APP_STORE_URL && `<a class="btn" href="${esc(config.APP_STORE_URL)}">Download for iPhone</a>`,
    config.PLAY_STORE_URL && `<a class="btn" href="${esc(config.PLAY_STORE_URL)}">Get it on Android</a>`,
  ]
    .filter(Boolean)
    .join('');
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} · Trace</title>
<meta name="description" content="Some things, you have to be there for.">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,500;1,9..144,500&family=Manrope:wght@500;700;800&display=swap" rel="stylesheet">
<style>
  :root{--ink:#0a0c11;--text:#f4f1ea;--muted:#9097a6;--ember:#ff7a4d;--sun:#ffb648}
  *{box-sizing:border-box}html,body{margin:0;height:100%}
  body{background:radial-gradient(120% 70% at 50% -10%,rgba(255,122,77,.22),var(--ink) 60%);background-color:var(--ink);color:var(--text);
    font-family:Manrope,system-ui,sans-serif;display:flex;align-items:center;justify-content:center;padding:24px}
  main{max-width:420px;width:100%}
  .rings{width:180px;height:180px;margin:0 auto 32px;position:relative}
  .rings span{position:absolute;inset:0;border:1.5px solid var(--ember);border-radius:50%;animation:pulse 3.2s ease-out infinite;opacity:0}
  .rings span:nth-child(2){animation-delay:1.06s}.rings span:nth-child(3){animation-delay:2.13s}
  .rings i{position:absolute;left:50%;top:50%;width:20px;height:20px;margin:-10px;border-radius:50%;
    background:radial-gradient(#ffc0a8,var(--ember));box-shadow:0 0 24px var(--ember)}
  @keyframes pulse{0%{transform:scale(.15);opacity:.9}100%{transform:scale(1);opacity:0}}
  @media (prefers-reduced-motion:reduce){.rings span{animation:none;opacity:.4}}
  .brand{font-family:Fraunces,serif;font-style:italic;font-size:22px;margin-bottom:28px}
  h1{font-family:Fraunces,serif;font-weight:500;font-size:34px;line-height:1.08;margin:0 0 12px}
  .teaser{font-family:Fraunces,serif;font-style:italic;font-size:20px;color:var(--sun);margin:0 0 16px}
  p{color:var(--muted);line-height:1.5;margin:0 0 28px}
  .btn{display:block;text-align:center;text-decoration:none;font-weight:800;padding:17px;border-radius:18px;margin-bottom:12px;
    background:linear-gradient(135deg,var(--ember),var(--sun));color:var(--ink)}
  .btn.ghost{background:#1c202b;color:var(--text);border:1px solid rgba(255,255,255,.12)}
</style></head>
<body><main>
  <div class="brand">trace</div>
  <div class="rings" aria-hidden="true"><span></span><span></span><span></span><i></i></div>
  <h1>${title}</h1>
  ${v?.teaser ? `<p class="teaser">“${esc(v.teaser)}”</p>` : ''}
  <p>${v ? 'It only opens for people standing right here. Get Trace, then unlock it before you leave.' : 'Look around: there may be other drops nearby.'}</p>
  ${v ? `<a class="btn ghost" href="trace://v/${esc(v.code)}">Open in Trace</a>` : ''}
  ${store}
</main></body></html>`;
}

export async function venueRoutes(app: FastifyInstance) {
  // In-app: resolve a scanned code to its drop. Still needs an on-site unlock to open.
  app.get('/v1/venues/:code', { preHandler: requireAuth }, async (req) => {
    const { code } = z.object({ code: z.string().max(20) }).parse(req.params);
    const v = await findVenue(code);
    if (!v) throw notFound();
    return {
      code: v.code,
      name: v.name,
      drop: { id: v.dropId, type: v.type, teaser: v.teaser, ...fuzzyCircle(v.dropId, { lat: v.lat, lng: v.lng }) },
    };
  });

  // Web: the QR/NFC target. Universal links open the app instead when it's installed.
  app.get('/v/:code', async (req, reply) => {
    const { code } = z.object({ code: z.string().max(20) }).parse(req.params);
    const v = await findVenue(code).catch(() => undefined);
    return reply
      .code(v ? 200 : 404)
      .header('content-type', 'text/html; charset=utf-8')
      .header('cache-control', 'public, max-age=300')
      .send(venueLandingHtml(v ? { code: v.code, name: v.name, teaser: v.teaser } : null));
  });

  // Universal links (iOS) and App Links (Android) for /v/*.
  app.get('/.well-known/apple-app-site-association', async (_req, reply) =>
    reply.header('content-type', 'application/json').send({
      applinks: { details: [{ appIDs: [`${config.APPLE_TEAM_ID}.${config.APPLE_BUNDLE_ID}`], components: [{ '/': '/v/*' }] }] },
      appclips: { apps: [`${config.APPLE_TEAM_ID}.${config.APPLE_BUNDLE_ID}.Clip`] },
    }),
  );

  app.get('/.well-known/assetlinks.json', async () => [
    {
      relation: ['delegate_permission/common.handle_all_urls'],
      target: {
        namespace: 'android_app',
        package_name: config.ANDROID_PACKAGE,
        sha256_cert_fingerprints: config.ANDROID_CERT_SHA256,
      },
    },
  ]);
}
