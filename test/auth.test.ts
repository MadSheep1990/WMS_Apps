import assert from 'node:assert/strict';
import test from 'node:test';
import { signToken, verifyToken } from '../src/auth.js';

test('refresh token cannot be used as an access token', () => {
  const user = { id: 1, username: 'admin', email: 'admin@example.com', fullName: 'Admin', role: 'ADMIN' as const };
  const refreshToken = signToken(user, 'refresh');
  assert.throws(() => verifyToken(refreshToken, 'access'));
});

test('access token preserves user identity and role', () => {
  const user = { id: 1, username: 'admin', email: 'admin@example.com', fullName: 'Admin', role: 'ADMIN' as const };
  const accessToken = signToken(user, 'access');
  assert.deepEqual(verifyToken(accessToken, 'access'), {
    id: 1,
    username: 'admin',
    email: '',
    fullName: '',
    role: 'ADMIN'
  });
});
