-- WMS MySQL 8.0 schema
-- Use InnoDB and UTC timestamps. Run in a dedicated database.
CREATE DATABASE IF NOT EXISTS wms CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE wms;

CREATE TABLE users (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(100) NOT NULL UNIQUE,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  full_name VARCHAR(200) NOT NULL,
  role ENUM('ADMIN','SUPERVISOR','RECEIVER','PICKER','PACKER','AUDITOR') NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE warehouses (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(200) NOT NULL,
  address_line1 VARCHAR(255), address_line2 VARCHAR(255),
  city VARCHAR(100), country VARCHAR(100), timezone VARCHAR(64) NOT NULL DEFAULT 'UTC',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE categories (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  parent_id BIGINT UNSIGNED NULL,
  code VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(150) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_categories_parent FOREIGN KEY (parent_id) REFERENCES categories(id)
) ENGINE=InnoDB;

CREATE TABLE uoms (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(30) NOT NULL UNIQUE,
  name VARCHAR(80) NOT NULL,
  decimal_scale TINYINT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB;

CREATE TABLE products (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  sku VARCHAR(100) NOT NULL UNIQUE,
  name VARCHAR(255) NOT NULL,
  category_id BIGINT UNSIGNED NOT NULL,
  base_uom_id BIGINT UNSIGNED NOT NULL,
  tracking_type ENUM('NONE','LOT','SERIAL') NOT NULL DEFAULT 'NONE',
  rotation_strategy ENUM('FIFO','LIFO','FEFO') NOT NULL DEFAULT 'FIFO',
  shelf_life_days INT UNSIGNED NULL,
  unit_volume DECIMAL(14,4) NOT NULL DEFAULT 0,
  unit_weight DECIMAL(14,4) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES categories(id),
  CONSTRAINT fk_products_uom FOREIGN KEY (base_uom_id) REFERENCES uoms(id),
  INDEX idx_products_category_active (category_id, is_active)
) ENGINE=InnoDB;

CREATE TABLE product_barcodes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  product_id BIGINT UNSIGNED NOT NULL,
  uom_id BIGINT UNSIGNED NOT NULL,
  barcode VARCHAR(100) NOT NULL UNIQUE,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_barcodes_product FOREIGN KEY (product_id) REFERENCES products(id),
  CONSTRAINT fk_barcodes_uom FOREIGN KEY (uom_id) REFERENCES uoms(id),
  INDEX idx_barcodes_product (product_id),
  INDEX idx_barcodes_lookup (barcode, product_id)
) ENGINE=InnoDB;

CREATE TABLE locations (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  warehouse_id BIGINT UNSIGNED NOT NULL,
  parent_id BIGINT UNSIGNED NULL,
  code VARCHAR(100) NOT NULL,
  location_type ENUM('ZONE','AISLE','RACK','SHELF','BIN') NOT NULL,
  route_sequence INT UNSIGNED NOT NULL DEFAULT 0,
  capacity_units DECIMAL(14,3) NOT NULL DEFAULT 0,
  occupied_units DECIMAL(14,3) NOT NULL DEFAULT 0,
  preferred_category_id BIGINT UNSIGNED NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT uq_locations_code UNIQUE (warehouse_id, code),
  CONSTRAINT fk_locations_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
  CONSTRAINT fk_locations_parent FOREIGN KEY (parent_id) REFERENCES locations(id),
  CONSTRAINT fk_locations_category FOREIGN KEY (preferred_category_id) REFERENCES categories(id),
  INDEX idx_locations_lookup (warehouse_id, location_type, is_active, route_sequence),
  INDEX idx_locations_parent (parent_id)
) ENGINE=InnoDB;

CREATE TABLE putaway_rules (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  warehouse_id BIGINT UNSIGNED NOT NULL,
  category_id BIGINT UNSIGNED NULL,
  priority INT NOT NULL DEFAULT 100,
  allow_mixed_products BOOLEAN NOT NULL DEFAULT FALSE,
  min_free_units DECIMAL(14,3) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_putaway_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
  CONSTRAINT fk_putaway_category FOREIGN KEY (category_id) REFERENCES categories(id),
  INDEX idx_putaway_match (warehouse_id, category_id, is_active, priority)
) ENGINE=InnoDB;

CREATE TABLE inbound_orders (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  warehouse_id BIGINT UNSIGNED NOT NULL,
  order_number VARCHAR(80) NOT NULL UNIQUE,
  supplier_code VARCHAR(100),
  purchase_order_number VARCHAR(100),
  status ENUM('DRAFT','EXPECTED','RECEIVING','RECEIVED','PUTAWAY','COMPLETED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  expected_at DATETIME NULL,
  received_at DATETIME NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_inbound_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
  CONSTRAINT fk_inbound_user FOREIGN KEY (created_by) REFERENCES users(id),
  INDEX idx_inbound_status (warehouse_id, status, expected_at)
) ENGINE=InnoDB;

CREATE TABLE inbound_items (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  inbound_order_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  expected_quantity DECIMAL(14,3) NOT NULL,
  received_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  uom_id BIGINT UNSIGNED NOT NULL,
  CONSTRAINT fk_inbound_items_order FOREIGN KEY (inbound_order_id) REFERENCES inbound_orders(id),
  CONSTRAINT fk_inbound_items_product FOREIGN KEY (product_id) REFERENCES products(id),
  CONSTRAINT fk_inbound_items_uom FOREIGN KEY (uom_id) REFERENCES uoms(id),
  INDEX idx_inbound_items_product (product_id, inbound_order_id)
) ENGINE=InnoDB;

CREATE TABLE inventory (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  warehouse_id BIGINT UNSIGNED NOT NULL,
  location_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  lot_number VARCHAR(100) NULL,
  serial_number VARCHAR(150) NULL,
  expiry_date DATE NULL,
  received_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  quantity_on_hand DECIMAL(14,3) NOT NULL DEFAULT 0,
  quantity_reserved DECIMAL(14,3) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  lot_number_key VARCHAR(100) GENERATED ALWAYS AS (COALESCE(lot_number, '')) STORED,
  serial_number_key VARCHAR(150) GENERATED ALWAYS AS (COALESCE(serial_number, '')) STORED,
  expiry_date_key DATE GENERATED ALWAYS AS (COALESCE(expiry_date, '9999-12-31')) STORED,
  CONSTRAINT uq_inventory_balance UNIQUE (location_id, product_id, lot_number_key, serial_number_key, expiry_date_key),
  CONSTRAINT fk_inventory_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
  CONSTRAINT fk_inventory_location FOREIGN KEY (location_id) REFERENCES locations(id),
  CONSTRAINT fk_inventory_product FOREIGN KEY (product_id) REFERENCES products(id),
  CONSTRAINT ck_inventory_available CHECK (quantity_on_hand >= quantity_reserved AND quantity_reserved >= 0),
  INDEX idx_inventory_allocation (warehouse_id, product_id, expiry_date, received_at),
  INDEX idx_inventory_location (location_id, product_id),
  INDEX idx_inventory_lot (product_id, lot_number, expiry_date)
) ENGINE=InnoDB;

CREATE TABLE outbound_orders (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  warehouse_id BIGINT UNSIGNED NOT NULL,
  order_number VARCHAR(80) NOT NULL UNIQUE,
  customer_code VARCHAR(100),
  status ENUM('DRAFT','RELEASED','ALLOCATED','PICKING','PACKING','SHIPPED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  priority TINYINT UNSIGNED NOT NULL DEFAULT 5,
  requested_ship_at DATETIME NULL,
  shipped_at DATETIME NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_outbound_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
  CONSTRAINT fk_outbound_user FOREIGN KEY (created_by) REFERENCES users(id),
  INDEX idx_outbound_queue (warehouse_id, status, priority, requested_ship_at)
) ENGINE=InnoDB;

CREATE TABLE outbound_items (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  outbound_order_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  ordered_quantity DECIMAL(14,3) NOT NULL,
  allocated_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  picked_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  uom_id BIGINT UNSIGNED NOT NULL,
  CONSTRAINT fk_outbound_items_order FOREIGN KEY (outbound_order_id) REFERENCES outbound_orders(id),
  CONSTRAINT fk_outbound_items_product FOREIGN KEY (product_id) REFERENCES products(id),
  CONSTRAINT fk_outbound_items_uom FOREIGN KEY (uom_id) REFERENCES uoms(id),
  INDEX idx_outbound_items_product (product_id, outbound_order_id)
) ENGINE=InnoDB;

CREATE TABLE waves (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  warehouse_id BIGINT UNSIGNED NOT NULL,
  wave_number VARCHAR(80) NOT NULL UNIQUE,
  status ENUM('DRAFT','RELEASED','IN_PROGRESS','COMPLETED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  released_at DATETIME NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  CONSTRAINT fk_waves_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
  CONSTRAINT fk_waves_user FOREIGN KEY (created_by) REFERENCES users(id),
  INDEX idx_waves_status (warehouse_id, status)
) ENGINE=InnoDB;

CREATE TABLE pick_tasks (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  wave_id BIGINT UNSIGNED NOT NULL,
  outbound_order_id BIGINT UNSIGNED NOT NULL,
  outbound_item_id BIGINT UNSIGNED NOT NULL,
  inventory_id BIGINT UNSIGNED NOT NULL,
  source_location_id BIGINT UNSIGNED NOT NULL,
  assigned_to BIGINT UNSIGNED NULL,
  quantity DECIMAL(14,3) NOT NULL,
  picked_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  status ENUM('OPEN','ASSIGNED','PICKED','SHORT','CANCELLED') NOT NULL DEFAULT 'OPEN',
  route_sequence INT UNSIGNED NOT NULL DEFAULT 0,
  CONSTRAINT fk_pick_wave FOREIGN KEY (wave_id) REFERENCES waves(id),
  CONSTRAINT fk_pick_order FOREIGN KEY (outbound_order_id) REFERENCES outbound_orders(id),
  CONSTRAINT fk_pick_item FOREIGN KEY (outbound_item_id) REFERENCES outbound_items(id),
  CONSTRAINT fk_pick_inventory FOREIGN KEY (inventory_id) REFERENCES inventory(id),
  CONSTRAINT fk_pick_location FOREIGN KEY (source_location_id) REFERENCES locations(id),
  CONSTRAINT fk_pick_user FOREIGN KEY (assigned_to) REFERENCES users(id),
  INDEX idx_pick_queue (wave_id, status, route_sequence),
  INDEX idx_pick_assignee (assigned_to, status)
) ENGINE=InnoDB;

CREATE TABLE cycle_counts (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  warehouse_id BIGINT UNSIGNED NOT NULL,
  count_number VARCHAR(80) NOT NULL UNIQUE,
  status ENUM('DRAFT','OPEN','COUNTING','REVIEW','COMPLETED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  scheduled_at DATETIME NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  CONSTRAINT fk_counts_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
  CONSTRAINT fk_counts_user FOREIGN KEY (created_by) REFERENCES users(id),
  INDEX idx_counts_queue (warehouse_id, status, scheduled_at)
) ENGINE=InnoDB;

CREATE TABLE cycle_count_items (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  cycle_count_id BIGINT UNSIGNED NOT NULL,
  inventory_id BIGINT UNSIGNED NOT NULL,
  expected_quantity DECIMAL(14,3) NOT NULL,
  counted_quantity DECIMAL(14,3) NULL,
  counted_by BIGINT UNSIGNED NULL,
  counted_at DATETIME NULL,
  CONSTRAINT fk_count_items_count FOREIGN KEY (cycle_count_id) REFERENCES cycle_counts(id),
  CONSTRAINT fk_count_items_inventory FOREIGN KEY (inventory_id) REFERENCES inventory(id),
  CONSTRAINT fk_count_items_user FOREIGN KEY (counted_by) REFERENCES users(id),
  UNIQUE KEY uq_count_inventory (cycle_count_id, inventory_id)
) ENGINE=InnoDB;

CREATE TABLE stock_movements (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  warehouse_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  location_id BIGINT UNSIGNED NULL,
  inventory_id BIGINT UNSIGNED NULL,
  movement_type ENUM('RECEIPT','PUTAWAY','RESERVATION','PICK','PACK','SHIPMENT','ADJUSTMENT','COUNT') NOT NULL,
  quantity DECIMAL(14,3) NOT NULL,
  lot_number VARCHAR(100) NULL,
  expiry_date DATE NULL,
  reference_type VARCHAR(50) NULL,
  reference_id BIGINT UNSIGNED NULL,
  idempotency_key VARCHAR(150) NOT NULL,
  performed_by BIGINT UNSIGNED NOT NULL,
  performed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_movement_idempotency UNIQUE (idempotency_key),
  CONSTRAINT fk_movements_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
  CONSTRAINT fk_movements_product FOREIGN KEY (product_id) REFERENCES products(id),
  CONSTRAINT fk_movements_location FOREIGN KEY (location_id) REFERENCES locations(id),
  CONSTRAINT fk_movements_inventory FOREIGN KEY (inventory_id) REFERENCES inventory(id),
  CONSTRAINT fk_movements_user FOREIGN KEY (performed_by) REFERENCES users(id),
  INDEX idx_movements_product_time (product_id, performed_at),
  INDEX idx_movements_reference (reference_type, reference_id),
  INDEX idx_movements_location_time (location_id, performed_at)
) ENGINE=InnoDB;

CREATE TABLE audit_logs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  action VARCHAR(80) NOT NULL,
  entity_type VARCHAR(80) NOT NULL,
  entity_id BIGINT UNSIGNED NULL,
  request_id VARCHAR(100) NULL,
  before_json JSON NULL,
  after_json JSON NULL,
  ip_address VARCHAR(45) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id),
  INDEX idx_audit_entity (entity_type, entity_id, created_at),
  INDEX idx_audit_user_time (user_id, created_at),
  INDEX idx_audit_request (request_id)
) ENGINE=InnoDB;
