import express from 'express';
import type { RowDataPacket } from 'mysql2';
import path from 'node:path';
import { z } from 'zod';
import { db } from './db.js';
import { signToken, verifyPassword, verifyToken, type AuthUser, type UserRole } from './auth.js';
import { config } from './config.js';
import { requireAuth, requireRole } from './middleware.js';

const app = express();
app.use(express.static(path.resolve(process.cwd(), 'public')));
app.use(express.json({ limit: '32kb' }));

const loginSchema = z.object({
  username: z.string().trim().min(1).max(100),
  password: z.string().min(1).max(200)
});
const refreshSchema = z.object({ refreshToken: z.string().min(1) });
const productSchema = z.object({
  sku: z.string().trim().min(1).max(100),
  name: z.string().trim().min(1).max(255),
  categoryId: z.coerce.number().int().positive(),
  baseUomId: z.coerce.number().int().positive(),
  trackingType: z.enum(['NONE', 'LOT', 'SERIAL']).default('NONE'),
  rotationStrategy: z.enum(['FIFO', 'LIFO', 'FEFO']).default('FIFO'),
  shelfLifeDays: z.coerce.number().int().nonnegative().nullable().optional(),
  unitVolume: z.coerce.number().nonnegative().default(0),
  unitWeight: z.coerce.number().nonnegative().default(0),
  isActive: z.boolean().default(true)
});
const productFilterSchema = z.object({
  search: z.string().trim().max(100).optional(),
  active: z.enum(['true', 'false', 'all']).default('true')
});

type UserRow = RowDataPacket & {
  id: number;
  username: string;
  email: string;
  full_name: string;
  role: UserRole;
  password_hash: string;
};

type ProductRow = RowDataPacket & {
  id: number;
  sku: string;
  name: string;
  category_id: number;
  category_name: string;
  base_uom_id: number;
  uom_code: string;
  tracking_type: 'NONE' | 'LOT' | 'SERIAL';
  rotation_strategy: 'FIFO' | 'LIFO' | 'FEFO';
  shelf_life_days: number | null;
  unit_volume: number;
  unit_weight: number;
  is_active: number;
};

type LookupRow = RowDataPacket & { id: number; code: string; name: string };

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

app.get(`${config.API_PREFIX}/master/products`, requireAuth, async (request, response, next) => {
  try {
    const filters = productFilterSchema.parse(request.query);
    const conditions = ['1 = 1'];
    const params: Record<string, string> = {};
    if (filters.search) {
      conditions.push('(p.sku LIKE :search OR p.name LIKE :search)');
      params.search = `%${filters.search}%`;
    }
    if (filters.active !== 'all') {
      conditions.push('p.is_active = :isActive');
      params.isActive = filters.active === 'true' ? '1' : '0';
    }
    const [rows] = await db.execute<ProductRow[]>(
      `SELECT p.id, p.sku, p.name, p.category_id, c.name AS category_name,
              p.base_uom_id, u.code AS uom_code, p.tracking_type,
              p.rotation_strategy, p.shelf_life_days, p.unit_volume,
              p.unit_weight, p.is_active
       FROM products p
       JOIN categories c ON c.id = p.category_id
       JOIN uoms u ON u.id = p.base_uom_id
       WHERE ${conditions.join(' AND ')}
       ORDER BY p.updated_at DESC, p.id DESC`,
      params
    );
    response.json({ products: rows });
  } catch (error) {
    next(error);
  }
});

app.get(`${config.API_PREFIX}/master/lookups`, requireAuth, async (_request, response, next) => {
  try {
    const [categories] = await db.execute<LookupRow[]>('SELECT id, code, name FROM categories WHERE is_active = TRUE ORDER BY name');
    const [uoms] = await db.execute<LookupRow[]>('SELECT id, code, name FROM uoms ORDER BY code');
    response.json({ categories, uoms });
  } catch (error) {
    next(error);
  }
});

app.post(`${config.API_PREFIX}/master/products`, requireAuth, requireRole('ADMIN', 'SUPERVISOR'), async (request, response, next) => {
  try {
    const input = productSchema.parse(request.body);
    const [result] = await db.execute(
      `INSERT INTO products
        (sku, name, category_id, base_uom_id, tracking_type, rotation_strategy,
         shelf_life_days, unit_volume, unit_weight, is_active)
       VALUES (:sku, :name, :categoryId, :baseUomId, :trackingType, :rotationStrategy,
               :shelfLifeDays, :unitVolume, :unitWeight, :isActive)`,
      { ...input, shelfLifeDays: input.shelfLifeDays ?? null, isActive: input.isActive ? 1 : 0 }
    );
    response.status(201).json({ id: (result as { insertId: number }).insertId, message: 'Product created' });
  } catch (error) {
    next(error);
  }
});

app.patch(`${config.API_PREFIX}/master/products/:id`, requireAuth, requireRole('ADMIN', 'SUPERVISOR'), async (request, response, next) => {
  try {
    const id = z.coerce.number().int().positive().parse(request.params.id);
    const input = productSchema.parse(request.body);
    const [result] = await db.execute(
      `UPDATE products SET sku = :sku, name = :name, category_id = :categoryId,
         base_uom_id = :baseUomId, tracking_type = :trackingType,
         rotation_strategy = :rotationStrategy, shelf_life_days = :shelfLifeDays,
         unit_volume = :unitVolume, unit_weight = :unitWeight, is_active = :isActive
       WHERE id = :id`,
      { ...input, id, shelfLifeDays: input.shelfLifeDays ?? null, isActive: input.isActive ? 1 : 0 }
    );
    if ((result as { affectedRows: number }).affectedRows === 0) {
      response.status(404).json({ error: { code: 'PRODUCT_NOT_FOUND', message: 'Product not found' } });
      return;
    }
    response.json({ message: 'Product updated' });
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
