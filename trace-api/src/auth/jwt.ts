import { SignJWT, jwtVerify } from 'jose';
import { config } from '../config.js';
import { AppError } from '../lib/errors.js';

const secret = new TextEncoder().encode(config.JWT_SECRET);
const ISSUER = 'trace-api';

export async function issueToken(userId: string): Promise<string> {
  return new SignJWT({})
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setIssuer(ISSUER)
    .setIssuedAt()
    .setExpirationTime('30d')
    .sign(secret);
}

export async function verifyToken(token: string): Promise<string> {
  try {
    const { payload } = await jwtVerify(token, secret, { issuer: ISSUER });
    if (!payload.sub) throw new Error('no sub');
    return payload.sub;
  } catch {
    throw new AppError('unauthorized', 401);
  }
}
