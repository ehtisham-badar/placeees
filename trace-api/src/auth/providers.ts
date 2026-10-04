import { createRemoteJWKSet, jwtVerify } from 'jose';
import { config } from '../config.js';
import { AppError } from '../lib/errors.js';

const appleKeys = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
const googleKeys = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));

/** Verifies a Sign in with Apple identity token and returns the stable Apple user id. */
export async function verifyAppleIdentity(identityToken: string): Promise<string> {
  try {
    const { payload } = await jwtVerify(identityToken, appleKeys, {
      issuer: 'https://appleid.apple.com',
      audience: config.APPLE_BUNDLE_ID,
    });
    if (!payload.sub) throw new Error('no sub');
    return payload.sub;
  } catch {
    throw new AppError('invalid_identity_token', 401);
  }
}

/** Verifies a Google ID token and returns the stable Google user id. */
export async function verifyGoogleIdentity(idToken: string): Promise<string> {
  if (config.GOOGLE_CLIENT_IDS.length === 0) throw new AppError('google_not_configured', 503);
  try {
    const { payload } = await jwtVerify(idToken, googleKeys, {
      issuer: ['https://accounts.google.com', 'accounts.google.com'],
      audience: config.GOOGLE_CLIENT_IDS,
    });
    if (!payload.sub) throw new Error('no sub');
    return payload.sub;
  } catch {
    throw new AppError('invalid_identity_token', 401);
  }
}
