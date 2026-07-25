CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    product_id VARCHAR(50) NOT NULL,
    quantity INTEGER NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS products_cache (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(200),
    price DECIMAL(10,2),
    last_synced TIMESTAMP
);

-- Sample orders
INSERT INTO orders (product_id, quantity, status) VALUES
    ('PROD-001', 2, 'completed'),
    ('PROD-005', 1, 'completed'),
    ('PROD-009', 5, 'completed'),
    ('PROD-012', 3, 'pending'),
    ('PROD-003', 1, 'completed'),
    ('PROD-015', 10, 'completed'),
    ('PROD-007', 2, 'failed'),
    ('PROD-020', 1, 'completed'),
    ('PROD-011', 4, 'completed'),
    ('PROD-002', 3, 'pending');
