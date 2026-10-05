import http2 from 'node:http2';
import { SignJWT, importPKCS8 } from 'jose';
import { googleAccessToken } from '../lib/googleAuth.js';
import { config } from '../config.js';
import { sql } from '../db/client.js';

export interface PushMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}

const pem = (s: string) => s.replace(/\\n/g, '\n');

// ---- APNs (token-based auth over HTTP/2) ----

const apnsEnabled = Boolean(config.APNS_KEY_ID && config.APNS_TEAM_ID && config.APNS_PRIVATE_KEY);
let apnsJwt: { token: string; at: number } | null = null;

async function apnsToken(): Promise<string> {
  // Apple rejects tokens older than an hour and throttles refreshing more than every 20 minutes.
  if (apnsJwt && Date.now() - apnsJwt.at < 40 * 60_000) return apnsJwt.token;
  const key = await importPKCS8(pem(config.APNS_PRIVATE_KEY), 'ES256');
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: config.APNS_KEY_ID })
    .setIssuer(config.APNS_TEAM_ID)
    .setIssuedAt()
    .sign(key);
  apnsJwt = { token, at: Date.now() };
  return token;
}

async function sendApns(deviceToken: string, msg: PushMessage): Promise<'ok' | 'gone' | 'error'> {
  const host = config.APNS_PRODUCTION ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';
  const client = http2.connect(host);
  try {
    const token = await apnsToken();
    return await new Promise((resolve) => {
      const req = client.request({
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        authorization: `bearer ${token}`,
        'apns-topic': config.APPLE_BUNDLE_ID,
        'apns-push-type': 'alert',
        'content-type': 'application/json',
      });
      req.on('response', (h) => {
        const status = Number(h[':status']);
        resolve(status === 200 ? 'ok' : status === 410 || status === 400 ? 'gone' : 'error');
      });
      req.on('error', () => resolve('error'));
      req.end(JSON.stringify({ aps: { alert: { title: msg.title, body: msg.body }, sound: 'default' }, ...msg.data }));
      req.setTimeout(10_000, () => {
        req.close();
        resolve('error');
      });
    });
  } finally {
    client.close();
  }
}

// ---- FCM HTTP v1 (service-account OAuth) ----

const fcmEnabled = Boolean(config.FCM_PROJECT_ID && config.FCM_CLIENT_EMAIL && config.FCM_PRIVATE_KEY);
const fcmToken = () =>
  googleAccessToken(
    { clientEmail: config.FCM_CLIENT_EMAIL, privateKey: config.FCM_PRIVATE_KEY },
    'https://www.googleapis.com/auth/firebase.messaging',
  );

async function sendFcm(deviceToken: string, msg: PushMessage): Promise<'ok' | 'gone' | 'error'> {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${config.FCM_PROJECT_ID}/messages:send`, {
    method: 'POST',
    headers: { authorization: `Bearer ${await fcmToken()}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      message: {
        token: deviceToken,
        notification: { title: msg.title, body: msg.body },
        data: msg.data,
        // The app's "Activity" channel (created on first launch); high priority so it shows promptly.
        android: { priority: 'high', notification: { channel_id: 'activity' } },
      },
    }),
  });
  if (res.ok) return 'ok';
  return res.status === 404 ? 'gone' : 'error';
}

/** Which push channels this server can use. */
export const pushStatus = () => ({ apns: apnsEnabled, fcm: fcmEnabled });

/** Sends to every registered device of these users. Dead tokens are pruned. */
export async function pushToUsers(userIds: string[], msg: PushMessage): Promise<number> {
  if (userIds.length === 0 || (!apnsEnabled && !fcmEnabled)) return 0;
  const devices = await sql<{ token: string; platform: 'ios' | 'android' }[]>`
    SELECT token, platform FROM devices WHERE user_id IN ${sql(userIds)}`;

  let sent = 0;
  for (const d of devices) {
    const send = d.platform === 'ios' ? (apnsEnabled ? sendApns : null) : fcmEnabled ? sendFcm : null;
    if (!send) continue;
    const result = await send(d.token, msg).catch(() => 'error' as const);
    if (result === 'ok') sent++;
    if (result === 'gone') await sql`DELETE FROM devices WHERE token = ${d.token}`;
  }
  return sent;
}
