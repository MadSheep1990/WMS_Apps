import express from 'express';
import type { RowDataPacket } from 'mysql2';
import path from 'node:path';
import { z } from 'zod';
import { db } from './db.js';
import { signToken, verifyPassword, verifyToken, type AuthUser, type UserRole } from './auth.js';
import { config } from './config.js';
import { requireAuth } from './middleware.js';

const app = express();
app.use(express.static(path.resolve(process.cwd(), 'public')));
app.use(express.json({ limit: '32kb' }));

const loginSchema = z.object({
  username: z.string().trim().min(1).max(100),
  password: z.string().min(1).max(200)
});
const refreshSchema = z.object({ refreshToken: z.string().min(1) });

type UserRow = RowDataPacket & {
  id: number;
  username: string;
  email: string;
  full_name: string;
  role: UserRole;
  password_hash: string;
};

function toAuthUser(row: UserRow): AuthUser {
  return { id: row.id, username: row.username, email: row.email, fullName: row.full_name, role: row.role };
}

app.post(`${config.API_PREFIX}/auth/login`, async (request, response, next) => {
  try {
    const input = loginSchema.parse(request.body);
    const [rows] = await db.execute<UserRow[]>(
      `SELECT id, username, email, full_name, role, password_hash
       FROM users WHERE username = :username AND is_active = TRUE LIMIT 1`,
      { username: input.username }
    );
    const user = rows[0];
    if (!user || !(await verifyPassword(input.password, user.password_hash))) {
      response.status(401).json({ error: { code: 'INVALID_CREDENTIALS', message: 'Username or password is incorrect' } });
      return;
    }

    const authUser = toAuthUser(user);
    response.json({
      user: authUser,
      accessToken: signToken(authUser, 'access'),
      refreshToken: signToken(authUser, 'refresh')
    });
  } catch (error) {
    next(error);
  }
});

app.post(`${config.API_PREFIX}/auth/refresh`, (request, response) => {
  const parsed = refreshSchema.safeParse(request.body);
  if (!parsed.success) {
    response.status(400).json({ error: { code: 'VALIDATION_ERROR', message: 'refreshToken is required' } });
    return;
  }

  try {
    const tokenUser = verifyToken(parsed.data.refreshToken, 'refresh');
    response.json({ accessToken: signToken(tokenUser, 'access') });
  } catch {
    response.status(401).json({ error: { code: 'INVALID_REFRESH_TOKEN', message: 'Refresh token is invalid or expired' } });
  }
});

app.get(`${config.API_PREFIX}/users/me`, requireAuth, async (request, response, next) => {
  try {
    const [rows] = await db.execute<UserRow[]>(
      `SELECT id, username, email, full_name, role, password_hash
       FROM users WHERE id = :id AND is_active = TRUE LIMIT 1`,
      { id: request.user!.id }
    );
    const user = rows[0];
    if (!user) {
      response.status(401).json({ error: { code: 'USER_INACTIVE', message: 'User is not active' } });
      return;
    }
    response.json({ user: toAuthUser(user) });
  } catch (error) {
    next(error);
  }
});

app.use((error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
  if (error instanceof z.ZodError) {
    response.status(422).json({ error: { code: 'VALIDATION_ERROR', message: error.issues[0]?.message ?? 'Invalid request' } });
    return;
  }
  console.error(error);
  response.status(500).json({ error: { code: 'INTERNAL_ERROR', message: 'Internal server error' } });
});

if (process.env.NODE_ENV !== 'test') {
  app.listen(config.PORT, () => console.log(`WMS API listening on port ${config.PORT}`));
}

export { app };
