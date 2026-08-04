# Retail Database Schema

## Overview

| Table           | Purpose                                                  |
| --------------- | -------------------------------------------------------- |
| `categories`  | Product categories, with self-referencing sub-categories |
| `stores`      | Physical store locations                                 |
| `customers`   | Customer accounts                                        |
| `products`    | Product catalog, priced per unit                         |
| `employees`   | Store staff, with a manager hierarchy                    |
| `orders`      | Customer orders, placed online or in-store               |
| `order_items` | Line items belonging to an order                         |
| `inventory`   | Stock levels per product, per store                      |
| `payments`    | Payments made against an order                           |

## Entity Relationships

```
categories ─┐ (self-reference: parent_category_id)
            │
            └──< products >──< order_items >──── orders
                    │                              │  │
stores ──< employees┘                          customers│
  │           │  (self-ref: manager_id)              │
  ├──< orders ┘                                       │
  └──< inventory >──── products                  payments
```

- A **category** can have a parent category (unlimited nesting).
- A **product** belongs to exactly one category.
- A **store** employs many **employees**; an employee optionally reports to
  another employee (manager hierarchy).
- A **customer** places many **orders**; each order belongs to one store and
  is optionally handled by one employee (nullable — e.g. online orders).
- An **order** contains many **order_items**, each pointing to one product.
- **Inventory** tracks quantity per product, per store.
- A **payment** belongs to exactly one order.

## Key Constraints

**Composite uniqueness**

- `order_items`: `(order_id, product_id)` — a product appears at most once
  per order.
- `inventory`: `(store_id, product_id)` — one stock row per product per
  store.

**Value checks**

- `products.unit_price >= 0`, `products.cost >= 0`
- `employees.salary > 0`
- `orders.total_amount >= 0`
- `orders.channel IN ('online', 'in-store')`
- `orders.status IN ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled')`
- `order_items.quantity > 0`, `order_items.unit_price >= 0`, `order_items.discount >= 0`
- `inventory.quantity >= 0`
- `payments.amount > 0`
- `payments.method IN ('cash', 'card', 'wallet', 'bank_transfer')`

**Nullable foreign keys** (everything else marked FK is required)

- `orders.employee_id` — an order isn't always tied to a staff member.
- `employees.manager_id` — the top-level manager has no manager.

> DBML's `note:` field is used to record CHECK constraints and other details
> that DBML doesn't express natively — these need to be added by hand when
> generating actual `CREATE TABLE` SQL.

## Files

- `retail_schema.dbml` — the schema definition, importable at
  [dbdiagram.io](https://dbdiagram.io) (paste directly into the editor).

## Build Order

If generating SQL from this schema, create tables in this order so that
foreign keys always reference an existing table:

1. `categories`, `stores`, `customers`
2. `products`, `employees`
3. `orders`
4. `order_items`, `inventory`, `payments`

Drop tables in reverse order.
