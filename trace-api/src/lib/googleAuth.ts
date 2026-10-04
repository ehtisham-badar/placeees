import { importPKCS8, SignJWT } from 'jose';

const cache = new Map<string, { token: string; expires: number }>();

export interface ServiceAccount {
  clientEmail: string;
  privateKey: string;
}

/** OAuth access token for a Google service account (JWT bearer grant), cached until near expiry. */
export async function googleAccessToken(sa: ServiceAccount, scope: string): Promise<string> {
  const key = `${sa.clientEmail}|${scope}`;
  const hit = cache.get(key);
  if (hit && Date.now() < hit.expires - 60_000) return hit.token;

  const pk = await importPKCS8(sa.privateKey.replace(/\\n/g, '\n'), 'RS256');
  const assertion = await new SignJWT({ scope })
    .setProtectedHeader({ alg: 'RS256' })
    .setIssuer(sa.clientEmail)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(pk);
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  if (!res.ok) throw new Error(`google oauth ${res.status}`);
  const body = (await res.json()) as { access_token: string; expires_in: number };
  cache.set(key, { token: body.access_token, expires: Date.now() + body.expires_in * 1000 });
  return body.access_token;
}
