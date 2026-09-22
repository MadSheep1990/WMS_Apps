-- Minimal master data for local development.
INSERT INTO uoms (code, name, decimal_scale)
VALUES
  ('PCS', 'ชิ้น', 0),
  ('BOX', 'กล่อง', 0),
  ('KG', 'กิโลกรัม', 3)
ON DUPLICATE KEY UPDATE name = VALUES(name), decimal_scale = VALUES(decimal_scale);

INSERT INTO categories (code, name)
VALUES ('GENERAL', 'สินค้าทั่วไป')
ON DUPLICATE KEY UPDATE name = VALUES(name), is_active = TRUE;
