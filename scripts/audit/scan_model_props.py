import os
import re

screens_dir = r"D:\BuildDo\Buildto\apps\customer_app\lib\screens"

product_props = set()
category_props = set()
supplier_props = set()

for f in os.listdir(screens_dir):
    if not f.endswith('.dart'):
        continue
    path = os.path.join(screens_dir, f)
    with open(path, 'r', encoding='utf-8') as fp:
        code = fp.read()
    
    for m in re.finditer(r"product\.(\w+)", code):
        product_props.add(m.group(1))
    for m in re.finditer(r"category\.(\w+)", code):
        category_props.add(m.group(1))
    for m in re.finditer(r"supplier\.(\w+)", code):
        supplier_props.add(m.group(1))

print("product properties accessed:", sorted(product_props))
print("\ncategory properties accessed:", sorted(category_props))
print("\nsupplier properties accessed:", sorted(supplier_props))
