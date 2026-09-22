# WMS REST API Specification

Base URL: `/api/v1`  
Authentication: `Authorization: Bearer <access-token>`  
All mutation endpoints accept `Idempotency-Key`.

## Authentication and users

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/auth/login` | Issue access/refresh tokens |
| POST | `/auth/refresh` | Rotate access token |
| GET | `/users/me` | Return current user and permissions |
| GET/POST/PATCH | `/users`, `/users/{id}` | Manage users (admin) |

## Master data

| Method | Endpoint | Purpose |
|---|---|---|
| GET/POST/PATCH | `/categories`, `/categories/{id}` | Product categories |
| GET/POST/PATCH | `/uoms`, `/uoms/{id}` | Units of measure |
| GET/POST/PATCH | `/products`, `/products/{id}` | SKU/product master |
| POST | `/products/{id}/barcodes` | Add a barcode |
| GET | `/products/resolve-barcode?value=...` | Resolve barcode to SKU/UOM |
| GET/POST/PATCH | `/warehouses`, `/warehouses/{id}` | Warehouse master |
| GET/POST/PATCH | `/locations`, `/locations/{id}` | Zone/aisle/rack/shelf/bin locations |
| GET/POST/PATCH | `/putaway-rules`, `/putaway-rules/{id}` | Putaway ranking rules |

## Inbound

| Method | Endpoint | Purpose |
|---|---|---|
| GET/POST | `/inbound-orders` | Search/create GRN or PO receipt |
| GET/PATCH | `/inbound-orders/{id}` | Read/update receipt status |
| POST | `/inbound-orders/{id}/receive` | Scan and receive quantities |
| POST | `/inbound-orders/{id}/putaway` | Confirm suggested bin and quantity |
| GET | `/inbound-orders/{id}/putaway-suggestions` | Rank eligible locations |

`POST /inbound-orders/{id}/receive` body:

```json
{
  "lines": [{
    "barcode": "8850000000012",
    "quantity": 12,
    "lotNumber": "LOT-2026-09",
    "expiryDate": "2027-09-30"
  }]
}
```

## Inventory

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/inventory?warehouseId=&productId=&locationId=` | Current balances |
| GET | `/inventory/availability?productId=&quantity=` | Allocatable stock |
| GET | `/stock-movements` | Ledger search |
| POST | `/stock-adjustments` | Create an adjustment request |
| POST | `/stock-adjustments/{id}/approve` | Approve and post adjustment |
| GET/POST | `/cycle-counts`, `/cycle-counts/{id}/lines` | Count plan and capture |
| POST | `/cycle-counts/{id}/complete` | Reconcile approved count |

## Outbound

| Method | Endpoint | Purpose |
|---|---|---|
| GET/POST | `/outbound-orders` | Search/create sales orders |
| GET/PATCH | `/outbound-orders/{id}` | Read/update order |
| POST | `/outbound-orders/{id}/allocate` | Allocate FIFO/LIFO/FEFO |
| GET/POST | `/waves`, `/waves/{id}/release` | Create/release a wave |
| GET | `/pick-tasks?waveId=` | Route-ordered pick tasks |
| POST | `/pick-tasks/{id}/pick` | Scan and confirm a pick |
| POST | `/outbound-orders/{id}/pack/validate` | Validate scanned carton contents |
| POST | `/outbound-orders/{id}/ship` | Confirm shipment |
| POST | `/documents/delivery-notes` | Generate delivery note |
| POST | `/documents/shipping-labels` | Generate shipping label |
| GET | `/documents/{id}` | Download document metadata/file URL |

## Dashboard

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/dashboard/summary` | Space utilization, fulfillment rate, open exceptions |
| GET | `/dashboard/top-moving-skus` | Top moving SKUs for a date range |
| GET | `/dashboard/stock-aging` | Aging buckets by SKU/location |

## Error contract

```json
{
  "error": {
    "code": "INSUFFICIENT_STOCK",
    "message": "Not enough allocatable stock for SKU-001",
    "details": { "productId": 1, "requested": 10, "available": 6 },
    "requestId": "req_01J..."
  }
}
```

Use `409` for inventory conflicts/idempotency conflicts, `422` for validation errors, `404` for missing resources, and `403` for insufficient role permissions.
