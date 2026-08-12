"""
Generates the `categories` table.

Builds a real two-level hierarchy (top-level category -> subcategories)
instead of a flat list, because `categories.parent_category_id` is
self-referencing in the schema and the project wants recursive-CTE rollups
later (e.g. total sales for "Electronics" summed up from its children).

Only leaf (sub-)categories are handed back for products to attach to —
keeping products off the top-level nodes means every product sits at a
consistent depth in the tree, which makes the rollup query simpler.
"""

import pandas as pd

# Top-level category -> list of its subcategories.
CATEGORY_TREE = {
    "Electronics": ["Laptops", "Phones", "Headphones", "Cameras", "Tablets"],
    "Home & Kitchen": ["Cookware", "Small Appliances", "Furniture", "Bedding"],
    "Apparel": ["Men's Clothing", "Women's Clothing", "Shoes", "Accessories"],
    "Sports & Outdoors": ["Fitness Equipment", "Camping Gear", "Cycling"],
    "Toys & Games": ["Board Games", "Action Figures", "Puzzles"],
    "Beauty & Personal Care": ["Skincare", "Haircare", "Fragrance"],
    "Books": ["Fiction", "Non-Fiction", "Children's Books"],
    "Office Supplies": ["Stationery", "Printers & Ink", "Organization"],
}


def generate_categories():
    """
    Returns:
        (categories_df, leaf_category_ids)
        leaf_category_ids is a plain list of ints — everything that is NOT
        a top-level category — for products.py to sample from.
    """
    rows = []
    cat_id = 1
    leaf_ids = []

    for parent_name, children in CATEGORY_TREE.items():
        # Insert the parent first so its id exists before any child row
        # references it via parent_category_id (self-referencing FK).
        parent_id = cat_id
        rows.append({
            "category_id": parent_id,
            "name": parent_name,
            "parent_category_id": None,
        })
        cat_id += 1

        for child_name in children:
            rows.append({
                "category_id": cat_id,
                "name": child_name,
                "parent_category_id": parent_id,
            })
            leaf_ids.append(cat_id)
            cat_id += 1

    return pd.DataFrame(rows), leaf_ids
