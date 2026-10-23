import os
import json
import re

# 1. Check demo/construction-catalog.json
catalog_path = r"D:\BuildDo\Buildto\demo\construction-catalog.json"
with open(catalog_path, 'r', encoding='utf-8') as f:
    catalog = json.load(f)

print(f"Catalog categories: {len(catalog['categories'])}")
print(f"Catalog suppliers: {len(catalog['suppliers'])}")
print(f"Catalog products: {len(catalog['products'])}")

# 2. Check sample_construction_data.dart
sample_data_path = r"D:\BuildDo\Buildto\apps\customer_app\lib\models\sample_construction_data.dart"
with open(sample_data_path, 'r', encoding='utf-8') as f:
    code = f.read()

# Find all imageUrls
image_refs = re.findall(r"['\"](assets/[^'\"]+)['\"]", code)
print(f"\nTotal image references in sample_construction_data.dart: {len(image_refs)}")

app_root = r"D:\BuildDo\Buildto\apps\customer_app"
missing_images = []
for ref in set(image_refs):
    abs_path = os.path.join(app_root, ref)
    if not os.path.exists(abs_path):
        missing_images.append((ref, abs_path))

print(f"Missing image assets from sample_construction_data: {len(missing_images)}")
for ref, absp in missing_images:
    print(f"  [MISSING ASSET] {ref}")

# 3. Check assets referenced in all 16 screens
screens_dir = r"D:\BuildDo\Buildto\apps\customer_app\lib\screens"
screen_image_refs = set()
for f in os.listdir(screens_dir):
    if not f.endswith('.dart'):
        continue
    with open(os.path.join(screens_dir, f), 'r', encoding='utf-8') as fp:
        c = fp.read()
    refs = re.findall(r"['\"](assets/[^'\"]+)['\"]", c)
    for r in refs:
        screen_image_refs.add((f, r))

missing_screen_assets = []
for screen_file, ref in screen_image_refs:
    abs_path = os.path.join(app_root, ref)
    if not os.path.exists(abs_path):
        missing_screen_assets.append((screen_file, ref))

print(f"\nMissing screen image assets: {len(missing_screen_assets)}")
for sfile, ref in missing_screen_assets:
    print(f"  [MISSING IN {sfile}] {ref}")

# 4. Check category mapping
sample_cats = re.findall(r"id:\s*'(cat-[^']+)'", code)
print(f"\nCategories in sample_construction_data.dart: {len(set(sample_cats))}")

# 5. Check suppliers mapping
sample_stores = re.findall(r"id:\s*'(ven-[^']+)'", code)
print(f"Suppliers in sample_construction_data.dart: {len(set(sample_stores))}")

# 6. Check product IDs
sample_prods = re.findall(r"id:\s*'(prod-[^']+)'", code)
print(f"Products in sample_construction_data.dart: {len(set(sample_prods))}")
