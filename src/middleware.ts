import type { NextFunction, Request, Response } from 'express';
import { verifyToken, type AuthUser, type UserRole } from './auth.js';

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function requireAuth(request: Request, response: Response, next: NextFunction): void {
  const header = request.header('authorization');
  const token = header?.startsWith('Bearer ') ? header.slice(7) : undefined;
  if (!token) {
    response.status(401).json({ error: { code: 'UNAUTHORIZED', message: 'Bearer token is required' } });
    return;
  }

  try {
    request.user = verifyToken(token, 'access');
    next();
  } catch {
    response.status(401).json({ error: { code: 'INVALID_TOKEN', message: 'Access token is invalid or expired' } });
  }
}

export function requireRole(...roles: UserRole[]) {
  return (request: Request, response: Response, next: NextFunction): void => {
    if (!request.user || !roles.includes(request.user.role)) {
      response.status(403).json({ error: { code: 'FORBIDDEN', message: 'Insufficient permissions' } });
      return;
    }
    next();
  };
}
