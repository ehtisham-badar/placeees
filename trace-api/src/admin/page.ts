/** The moderation console (spec F-05). Static: it holds no secrets and asks for the admin token. */
export const ADMIN_PAGE = String.raw`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Trace Admin</title><meta name="robots" content="noindex">
<style>
  :root{--ink:#0a0c11;--surface:#13161e;--high:#1c202b;--line:rgba(255,255,255,.12);--text:#f4f1ea;--muted:#9097a6;
    --ember:#ff7a4d;--mint:#5fe3c3;--rose:#ff5c7a;--amber:#ffc857}
  *{box-sizing:border-box}body{margin:0;background:var(--ink);color:var(--text);font:14px/1.45 system-ui,-apple-system,Segoe UI,sans-serif}
  header{display:flex;align-items:center;gap:16px;padding:16px 24px;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--ink);z-index:1}
  header b{font:italic 600 20px Georgia,serif}
  nav{display:flex;gap:4px;flex-wrap:wrap}nav button{background:none;color:var(--muted);border:0;padding:8px 14px;border-radius:99px;font-weight:700;cursor:pointer}
  nav button.on{background:var(--high);color:var(--text)}
  main{max-width:1100px;margin:0 auto;padding:24px}
  .card{background:var(--surface);border:1px solid var(--line);border-radius:16px;padding:16px;margin-bottom:12px;display:flex;gap:16px}
  .card img{width:120px;height:150px;object-fit:cover;border-radius:10px;flex:none;background:var(--high)}
  .grow{flex:1;min-width:0}.meta{color:var(--muted);font-size:12px}.serif{font:18px/1.35 Georgia,serif;margin:6px 0;word-wrap:break-word}
  .row{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
  button.act{border:1px solid var(--line);background:var(--high);color:var(--text);padding:7px 12px;border-radius:10px;font-weight:700;cursor:pointer}
  button.ok{color:var(--mint)}button.bad{color:var(--rose)}button.warn{color:var(--amber)}
  .pill{display:inline-block;padding:2px 9px;border-radius:99px;background:rgba(255,122,77,.15);color:var(--ember);font-weight:700;font-size:12px}
  input{background:var(--high);color:var(--text);border:1px solid var(--line);border-radius:10px;padding:9px 12px;font:inherit}
  .empty{color:var(--muted);padding:40px;text-align:center}h2{font:500 22px Georgia,serif;margin:24px 0 12px}
  #login{max-width:360px;margin:15vh auto;text-align:center}#login input{width:100%;margin:16px 0}
  #toast{position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:var(--high);padding:10px 16px;border-radius:12px;display:none}
  @media(max-width:600px){.card{flex-direction:column}.card img{width:100%;height:220px}}
</style></head>
<body>
<div id="login"><b style="font:italic 600 28px Georgia,serif">trace admin</b>
  <form id="lf"><input id="tok" type="password" placeholder="Admin token" autocomplete="current-password" required>
  <button class="act" style="width:100%">Sign in</button></form></div>
<div id="app" hidden>
  <header><b>trace</b><nav id="tabs"></nav><span style="flex:1"></span><button class="act" id="out">Sign out</button></header>
  <main id="view"></main>
</div>
<div id="toast"></div>
<script>
const $ = (s) => document.querySelector(s);
const h = (tag, attrs = {}, ...kids) => {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) k.startsWith('on') ? el.addEventListener(k.slice(2), v) : el.setAttribute(k, v);
  for (const k of kids.flat()) if (k != null && k !== false) el.append(k instanceof Node ? k : document.createTextNode(String(k)));
  return el;
};
const ago = (t) => { const s = (Date.now() - new Date(t)) / 1000; return s < 3600 ? Math.round(s / 60) + ' min ago' : s < 86400 ? Math.round(s / 3600) + ' h ago' : Math.round(s / 86400) + ' d ago'; };
const toast = (m) => { const t = $('#toast'); t.textContent = m; t.style.display = 'block'; setTimeout(() => (t.style.display = 'none'), 2200); };
let token = '';
try { token = sessionStorage.getItem('trace-admin') || ''; } catch {}

async function api(path, body) {
  const res = await fetch('/v1/admin' + path, {
    method: body ? 'POST' : 'GET',
    headers: { 'x-admin-token': token, ...(body ? { 'content-type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 401) { signOut(); throw new Error('Wrong token'); }
  if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || res.status);
  return res.json();
}
const act = (label, cls, fn) => h('button', { class: 'act ' + cls, onclick: async (e) => {
  e.target.disabled = true; try { await fn(); toast(label + ' ✓'); render(); } catch (err) { toast(err.message); e.target.disabled = false; }
} }, label);
const moderation = (kind, id) => [
  act('Approve', 'ok', () => api('/' + kind + '/' + id, { action: 'approve' })),
  act('Reject', 'warn', () => api('/' + kind + '/' + id, { action: 'reject' })),
  act('Remove', 'bad', () => api('/' + kind + '/' + id, { action: 'remove' })),
];
const ban = (userId, handle) => act('Ban @' + (handle || 'user'), 'bad', () => {
  if (!confirm('Ban @' + handle + '? They will be signed out everywhere.')) throw new Error('Cancelled');
  return api('/users/' + userId + '/ban', { banned: true });
});

const LABELS = {
  firstSessionUnlockRate: ['First-session unlock rate', 'pct'], d1Retention: ['D1 retention', 'pct'],
  d7Retention: ['D7 retention', 'pct'], dropsPerWau: ['Drops per weekly user', 'num'],
  medianUnlocksPerDrop: ['Unlocks per drop (median)', 'num'], relayHopsPerRelay: ['Relay hops per relay', 'num'],
  trailCompletionRate: ['Trail completion', 'pct'], moderationFalseNegativeRate: ['Moderation misses', 'pct'],
};
const fmt = (v, kind) => v == null ? '–' : kind === 'pct' ? Math.round(v * 1000) / 10 + '%' : String(Math.round(v * 100) / 100);

const tabs = {
  async Metrics(v) {
    const r = await api('/metrics?days=7');
    v.append(h('h2', {}, 'Pilot targets · last 7 days'));
    const grid = h('div', { style: 'display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px' });
    for (const [key, [label, kind]] of Object.entries(LABELS)) {
      const value = r.metrics[key], target = r.targets[key];
      const lowerIsBetter = key === 'moderationFalseNegativeRate';
      const ok = value != null && (lowerIsBetter ? value <= target : value >= target);
      grid.append(h('div', { class: 'card', style: 'flex-direction:column;gap:4px' },
        h('div', { class: 'meta' }, label),
        h('div', { style: 'font:600 30px Georgia,serif;color:' + (value == null ? 'var(--muted)' : ok ? 'var(--mint)' : 'var(--amber)') }, fmt(value, kind)),
        h('div', { class: 'meta' }, 'target ' + (lowerIsBetter ? '< ' : '≥ ') + fmt(target, kind))));
    }
    v.append(grid, h('div', { class: 'meta', style: 'margin-top:8px' },
      (r.metrics.newUsers ?? 0) + ' new users · ' + (r.metrics.wau ?? 0) + ' weekly actives'));
    v.append(h('h2', {}, 'Why unlocks fail'));
    v.append(r.unlockFailures.length ? h('div', { class: 'row' }, r.unlockFailures.map((f) => h('span', { class: 'pill' }, f.reason + ': ' + f.count))) : h('div', { class: 'meta' }, 'No failed attempts yet.'));
  },
  async Queue(v) {
    const q = await api('/queue');
    v.append(h('h2', {}, 'Drops awaiting review (' + q.drops.length + ')'));
    if (!q.drops.length) v.append(h('div', { class: 'empty' }, 'Nothing waiting.'));
    for (const d of q.drops) v.append(h('div', { class: 'card' }, d.mediaUrl && h('img', { src: d.mediaUrl, alt: '' }),
      h('div', { class: 'grow' },
        h('div', { class: 'meta' }, d.type + ' · @' + (d.handle || '?') + ' · ' + ago(d.createdAt) + (d.moderationNote ? ' · ' + d.moderationNote : '')),
        d.openReports ? h('span', { class: 'pill' }, d.openReports + ' reports') : null,
        d.teaser && h('div', { class: 'serif' }, d.teaser), d.body && h('div', {}, d.body),
        h('div', { class: 'row' }, moderation('drops', d.id), ban(d.creatorId, d.handle)))));
    v.append(h('h2', {}, 'Echoes (' + q.echoes.length + ')'));
    for (const e of q.echoes) v.append(h('div', { class: 'card' }, h('div', { class: 'grow' },
      h('div', { class: 'meta' }, '@' + e.handle + ' · ' + ago(e.createdAt)), h('div', { class: 'serif' }, e.body),
      h('div', { class: 'row' }, moderation('echoes', e.id), ban(e.userId, e.handle)))));
    v.append(h('h2', {}, 'Now photos (' + q.nowPhotos.length + ')'));
    for (const n of q.nowPhotos) v.append(h('div', { class: 'card' }, h('img', { src: n.mediaUrl || '', alt: '' }), h('div', { class: 'grow' },
      h('div', { class: 'meta' }, '@' + n.handle + ' · ' + ago(n.createdAt)), h('div', { class: 'row' }, moderation('now-photos', n.id), ban(n.userId, n.handle)))));
  },
  async Reports(v) {
    const { reports } = await api('/reports');
    if (!reports.length) return v.append(h('div', { class: 'empty' }, 'No open reports.'));
    for (const r of reports) v.append(h('div', { class: 'card' }, h('div', { class: 'grow' },
      h('div', { class: 'meta' }, r.targetType + ' · ' + r.reporters + ' people · last ' + ago(r.lastAt)),
      h('div', { class: 'serif' }, r.preview || '(deleted)'), r.reasons && h('div', { class: 'meta' }, 'Reasons: ' + r.reasons.join(', ')),
      h('div', { class: 'row' },
        r.targetType === 'drop' ? act('Remove drop', 'bad', () => api('/drops/' + r.targetId, { action: 'remove' })) : null,
        r.targetType === 'echo' ? act('Remove echo', 'bad', () => api('/echoes/' + r.targetId, { action: 'remove' })) : null,
        r.targetType === 'user' ? act('Ban user', 'bad', () => api('/users/' + r.targetId + '/ban', { banned: true })) : null,
        act('Dismiss', '', () => api('/reports/dismiss', { targetType: r.targetType, targetId: r.targetId }))))));
  },
  async Integrity(v) {
    const { events, summary } = await api('/integrity');
    v.append(h('h2', {}, 'Last 24 hours'), h('div', { class: 'row' }, summary.length ? summary.map((s) => h('span', { class: 'pill' }, s.kind + ': ' + s.count)) : 'Quiet.'));
    v.append(h('h2', {}, 'Recent events'));
    for (const e of events) v.append(h('div', { class: 'card' }, h('div', { class: 'grow' },
      h('div', {}, h('b', {}, e.kind), ' · @' + (e.handle || '?') + ' · ' + ago(e.createdAt)),
      e.detail && h('div', { class: 'meta' }, JSON.stringify(e.detail)),
      e.userId && h('div', { class: 'row' }, ban(e.userId, e.handle)))));
  },
  async Venues(v) {
    const form = h('form', { class: 'row', onsubmit: async (ev) => {
      ev.preventDefault(); const f = new FormData(ev.target);
      try { const r = await api('/venues', { dropId: f.get('dropId'), name: f.get('name') }); toast('Created ' + r.code); render(); } catch (err) { toast(err.message); }
    } }, h('input', { name: 'name', placeholder: 'Venue name', required: '' }), h('input', { name: 'dropId', placeholder: 'Drop id (public, approved)', required: '', size: '38' }), h('button', { class: 'act ok' }, 'Create code'));
    v.append(h('h2', {}, 'New venue code'), form, h('h2', {}, 'Venues'));
    const { venues } = await api('/venues');
    for (const x of venues) v.append(h('div', { class: 'card' }, h('div', { class: 'grow' },
      h('div', {}, h('b', {}, x.name), ' · ', h('code', {}, x.code)), h('div', { class: 'meta' }, x.teaser || ''),
      h('div', { class: 'row' }, h('a', { href: x.url, target: '_blank', style: 'color:var(--ember)' }, x.url)))));
  },
};
let current = 'Metrics';
async function render() {
  $('#tabs').replaceChildren(...Object.keys(tabs).map((t) => h('button', { class: t === current ? 'on' : '', onclick: () => { current = t; render(); } }, t)));
  const v = h('div'); $('#view').replaceChildren(v);
  try { await tabs[current](v); } catch (err) { v.append(h('div', { class: 'empty' }, err.message)); }
}
function signOut() { token = ''; try { sessionStorage.removeItem('trace-admin'); } catch {} $('#app').hidden = true; $('#login').hidden = false; }
function signIn() { $('#login').hidden = true; $('#app').hidden = false; render(); }
$('#lf').addEventListener('submit', (e) => { e.preventDefault(); token = $('#tok').value; try { sessionStorage.setItem('trace-admin', token); } catch {} signIn(); });
$('#out').addEventListener('click', signOut);
if (token) signIn();
</script></body></html>`;
