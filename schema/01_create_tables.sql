-- Active: 1782466035020@@127.0.0.1@5432@retail_warehouse_db
CREATE TABLE categories (
    category_id         SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    parent_category_id  INT,
    CONSTRAINT fk_categories_parent
        FOREIGN KEY (parent_category_id) REFERENCES categories(category_id)
);

CREATE TABLE stores (
    store_id       SERIAL PRIMARY KEY,
    name           VARCHAR(150) NOT NULL,
    phone          VARCHAR(20) NOT NULL,
    city           VARCHAR(100) NOT NULL,
    opened_date    DATE NOT NULL,
    manager        VARCHAR(150) NOT NULL
);

CREATE TABLE customers (
    customer_id    SERIAL PRIMARY KEY,
    first_name     VARCHAR(100) NOT NULL,
    last_name      VARCHAR(100) NOT NULL,
    email          VARCHAR(150) NOT NULL UNIQUE,
    phone          VARCHAR(20) NOT NULL,
    address        VARCHAR(200) NOT NULL,
    city           VARCHAR(100) NOT NULL,
    state          VARCHAR(50) NOT NULL,
    signup_date    DATE NOT NULL,
    age            INT NOT NULL,
    sex            VARCHAR(10) NOT NULL
);

CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    category_id INT NOT NULL,
    name VARCHAR(150) NOT NULL,
    brand VARCHAR(100) NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    cost     DECIMAL(10,2) NOT NULL CHECK (cost >= 0),
    CONSTRAINT fk_products_category
        FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL,
    hire_date DATE NOT NULL,
    manager_id INT,
    store_id INT NOT NULL,
    CONSTRAINT fk_employees_store
        FOREIGN KEY (store_id) REFERENCES stores(store_id),
    CONSTRAINT fk_employees_manager
        FOREIGN KEY (manager_id) REFERENCES employees(employee_id)    
);

CREATE TABLE orders (
    order_id       SERIAL PRIMARY KEY,
    customer_id    INT NOT NULL,
    store_id       INT NOT NULL,
    employee_id    INT,
    order_date     DATE NOT NULL,
    channel        VARCHAR(50) NOT NULL DEFAULT 'in-store'
                   CHECK (channel IN ('online', 'in-store')) ,
    status         VARCHAR(50) NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'completed', 'cancelled','shipped','delivered')),
    total_amount   DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (total_amount >0),

    CONSTRAINT fk_orders_customer
         FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_orders_store
        FOREIGN KEY (store_id) REFERENCES stores(store_id),
    CONSTRAINT fk_orders_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);

CREATE TABLE order_items (
    order_item_id  SERIAL PRIMARY KEY,
    order_id       INT NOT NULL,
    product_id     INT NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    unit_price     DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    discount       DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
    CONSTRAINT fk_orderitems_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_orderitems_product
        FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT uq_order_product
        UNIQUE (order_id, product_id)
);

CREATE TABLE inventory (
    inventory_id       SERIAL PRIMARY KEY,
    store_id           INT NOT NULL,
    product_id         INT NOT NULL,
    quantity           INT NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    last_restock_date  DATE,
    CONSTRAINT fk_inventory_store
        FOREIGN KEY (store_id) REFERENCES stores(store_id),
    CONSTRAINT fk_inventory_product
        FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT uq_store_product
        UNIQUE (store_id, product_id)
);

CREATE TABLE payments (
    payment_id     SERIAL PRIMARY KEY,
    order_id       INT NOT NULL,
    method         VARCHAR(20) NOT NULL
                   CHECK (method IN ('cash', 'card', 'wallet', 'bank_transfer')),
    amount         DECIMAL(10,2) NOT NULL CHECK (amount > 0),
    paid_at        TIMESTAMP NOT NULL,
    CONSTRAINT fk_payments_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);