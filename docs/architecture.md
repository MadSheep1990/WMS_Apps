# WMS End-to-End Architecture

## 1. Scope

This baseline uses React Native for the operator application and a REST API service for the backend. React Native is the client layer; it is not used as the server runtime. The backend should run as a Node.js service (TypeScript recommended) and use MySQL 8 as the system of record.

## 2. Logical architecture

```mermaid
flowchart LR
  RN[React Native mobile app] --> API[Node.js REST API]
  Web[Supervisor web client] --> API
  API --> Auth[JWT + RBAC]
  API --> WMS[WMS domain services]
  WMS --> DB[(MySQL 8]
  WMS --> Queue[Job queue]
  Queue --> Print[Label / delivery-note worker]
  Queue --> Analytics[Reporting aggregation]
  RN --> Scan[Camera / handheld scanner]
  WMS --> Audit[Audit log]
```

The API is stateless. Authentication tokens carry the user identity and role, while authorization is checked again at the service boundary. Stock mutations are performed inside MySQL transactions and are represented by immutable `stock_movements` records plus the current `inventory` balance.

## 3. Main data flow

### Inbound

1. Create an inbound order and its lines from a purchase order or ASN.
2. The operator scans a barcode; the API resolves it to a product.
3. The receiving transaction locks the target inventory row, validates quantity and expiry, increments stock, and writes a `RECEIPT` movement.
4. Putaway rules rank eligible bins by zone, capacity, product category, and hazard/temperature constraints.
5. The operator confirms the suggested location; the API posts a `PUTAWAY` movement if receiving and putaway are separate steps.

### Inventory

`inventory` stores one balance per product, bin, lot, and expiry date. `stock_movements` is the audit-friendly ledger. Available quantity is reserved for open outbound lines before it can be picked. All changes use row locks (`SELECT ... FOR UPDATE`) and an idempotency key on the API request.

### Outbound

1. Import or create a sales order and lines.
2. Allocate stock by FIFO, LIFO, or FEFO according to the warehouse/product policy.
3. Build a wave and pick list ordered by warehouse route sequence.
4. Scan source bin and product at picking; post `PICK` movements and reservations.
5. Scan each item again at packing; reject a mismatch before shipment confirmation.
6. Generate a delivery note and shipping label asynchronously; post `SHIPMENT` only after pack validation succeeds.

### Analytics

Operational KPIs query indexed transactional tables. For larger installations, a scheduled worker copies daily facts into reporting tables or a read replica. Dashboard requests must never hold locks on the write path.

## 4. React Native application areas

- Receiving: barcode scan, quantity/lot/expiry capture, putaway confirmation.
- Inventory: location lookup, stock inquiry, cycle count, adjustment approval.
- Picking: wave queue, route-ordered tasks, scan validation, short-pick workflow.
- Packing: order verification, carton contents, delivery-note/label print request.
- Supervisor: KPI dashboard, master data, exception queue, audit trail.

Use offline-safe scan queues only for capture. Before committing a stock mutation, the client must send the server-side idempotency key and refresh the authoritative result.

## 5. Deployment baseline

- React Native app distributed to Android/iOS handhelds.
- Node.js API behind a reverse proxy with TLS.
- MySQL 8 with foreign keys, backups, point-in-time recovery, and a read replica when reporting load grows.
- Redis or a managed queue for print/report jobs.
- Object storage for generated documents, with only document metadata stored in MySQL.
