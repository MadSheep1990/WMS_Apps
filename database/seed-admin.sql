-- Local development seed. Password: Admin@12345
-- Change this password immediately after the first login.
INSERT INTO users (username, email, password_hash, full_name, role)
VALUES ('admin', 'admin@example.com', '$2a$12$BDXCOmzNsLIcxfLQkFQDe.Z20t.D9V536exeN4K5G89d0FLpbRZEy', 'WMS Administrator', 'ADMIN');
