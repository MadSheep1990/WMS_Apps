-- MySQL 8 examples. Execute each transaction from the backend using a pooled connection.

-- 1) FEFO allocation. Replace :... with bound parameters. FIFO can use
-- received_at ASC; LIFO can use received_at DESC.
START TRANSACTION;

SELECT id, quantity_on_hand, quantity_reserved, expiry_date, received_at
FROM inventory
WHERE warehouse_id = :warehouse_id
  AND product_id = :product_id
  AND quantity_on_hand - quantity_reserved > 0
  AND (expiry_date IS NULL OR expiry_date >= CURRENT_DATE)
ORDER BY
  CASE WHEN :strategy = 'FEFO' THEN COALESCE(expiry_date, '9999-12-31') END ASC,
  CASE WHEN :strategy IN ('FIFO', 'FEFO') THEN received_at END ASC,
  CASE WHEN :strategy = 'LIFO' THEN received_at END DESC,
  id ASC
FOR UPDATE;

-- The service loops through the locked rows, taking the remaining quantity.
-- For each selected row:
UPDATE inventory
SET quantity_reserved = quantity_reserved + :take_quantity,
    updated_at = CURRENT_TIMESTAMP
WHERE id = :inventory_id
  AND quantity_on_hand - quantity_reserved >= :take_quantity;

INSERT INTO stock_movements
  (warehouse_id, product_id, location_id, inventory_id, movement_type,
   quantity, reference_type, reference_id, idempotency_key, performed_by)
VALUES
  (:warehouse_id, :product_id, :location_id, :inventory_id, 'RESERVATION',
   :take_quantity, 'OUTBOUND_ORDER', :outbound_order_id, :idempotency_key, :user_id);

COMMIT;

-- 2) Putaway candidate ranking. The application applies the product's
-- category/temperature/hazard filters before presenting the top candidate.
SELECT l.id AS location_id,
       l.code,
       l.capacity_units - l.occupied_units AS free_units,
       CASE WHEN l.preferred_category_id = :category_id THEN 0 ELSE 1 END AS category_penalty,
       CASE WHEN l.location_type = 'BIN' THEN 0 ELSE 1 END AS type_penalty
FROM locations l
WHERE l.warehouse_id = :warehouse_id
  AND l.is_active = 1
  AND l.location_type = 'BIN'
  AND l.capacity_units - l.occupied_units >= :quantity
  AND (l.preferred_category_id IS NULL OR l.preferred_category_id = :category_id)
  AND NOT EXISTS (
    SELECT 1
    FROM inventory i
    WHERE i.location_id = l.id
      AND i.product_id <> :product_id
      AND i.quantity_on_hand > 0
      AND :allow_mixed_products = 0
  )
ORDER BY category_penalty, type_penalty, l.occupied_units ASC, l.code
LIMIT 10;

-- 3) Atomic receipt into a known bin. The backend first resolves barcode ->
-- product, then inserts or updates the exact product/lot/expiry balance.
START TRANSACTION;

INSERT INTO inventory
  (warehouse_id, location_id, product_id, lot_number, expiry_date,
   quantity_on_hand, quantity_reserved, received_at)
VALUES
  (:warehouse_id, :location_id, :product_id, :lot_number, :expiry_date,
   :quantity, 0, CURRENT_TIMESTAMP)
ON DUPLICATE KEY UPDATE
  quantity_on_hand = quantity_on_hand + VALUES(quantity_on_hand),
  updated_at = CURRENT_TIMESTAMP;

UPDATE locations
SET occupied_units = occupied_units + :quantity,
    updated_at = CURRENT_TIMESTAMP
WHERE id = :location_id
  AND occupied_units + :quantity <= capacity_units;

INSERT INTO stock_movements
  (warehouse_id, product_id, location_id, movement_type, quantity,
   lot_number, expiry_date, reference_type, reference_id,
   idempotency_key, performed_by)
VALUES
  (:warehouse_id, :product_id, :location_id, 'RECEIPT', :quantity,
   :lot_number, :expiry_date, 'INBOUND_ORDER', :inbound_order_id,
   :idempotency_key, :user_id);

COMMIT;
