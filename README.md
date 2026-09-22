# WMS Apps

End-to-end Warehouse Management System baseline using a React Native operator app, a REST backend, and MySQL 8.

## Deliverables

- [System architecture and data flow](docs/architecture.md)
- [REST API specification](docs/api.md)
- [MySQL 8 database schema](database/schema.sql)
- [FIFO/FEFO allocation and putaway SQL examples](examples/inventory-logic.sql)
- [Authentication backend](src/server.ts)
- Product master management is available at `/products.html` after login.

## Quick start

1. Create a MySQL 8 database and run `database/schema.sql`.
2. Run `database/seed-master.sql` for starter UOM/category data.
3. Review the API contract before implementing the backend service.
4. Execute stock mutations in a backend transaction with a unique `Idempotency-Key`.

## API development

Install dependencies with `npm install`, then run `npm run dev`. The login endpoints are available at `/api/v1/auth/login`, `/api/v1/auth/refresh`, and `/api/v1/users/me`. Create an admin password hash using the command documented in [database/seed-admin.sql](database/seed-admin.sql), then run that seed against the `wms` database.

The schema is intentionally backend-neutral. A production implementation should add environment-specific migrations, seed data, authentication configuration, and automated integration tests.