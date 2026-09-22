import bcrypt from 'bcryptjs';
import jwt, { type SignOptions } from 'jsonwebtoken';
import { config } from './config.js';

export type UserRole = 'ADMIN' | 'SUPERVISOR' | 'RECEIVER' | 'PICKER' | 'PACKER' | 'AUDITOR';

export interface AuthUser {
  id: number;
  username: string;
  email: string;
  fullName: string;
  role: UserRole;
}

type TokenKind = 'access' | 'refresh';

export async function verifyPassword(password: string, passwordHash: string): Promise<boolean> {
  return bcrypt.compare(password, passwordHash);
}

export function signToken(user: AuthUser, kind: TokenKind): string {
  const options: SignOptions = {
    expiresIn: (kind === 'access' ? config.JWT_EXPIRES_IN : config.JWT_REFRESH_EXPIRES_IN) as SignOptions['expiresIn'],
    subject: String(user.id),
    issuer: 'wms-api'
  };

  return jwt.sign({ username: user.username, role: user.role, kind }, config.JWT_SECRET, options);
}

export function verifyToken(token: string, expectedKind: TokenKind): AuthUser {
  const payload = jwt.verify(token, config.JWT_SECRET, { issuer: 'wms-api' });
  if (typeof payload === 'string' || payload.kind !== expectedKind || !payload.sub) {
    throw new Error('INVALID_TOKEN');
  }

  return {
    id: Number(payload.sub),
    username: String(payload.username),
    email: '',
    fullName: '',
    role: payload.role as UserRole
  };
}
