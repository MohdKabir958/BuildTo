import os
import re

lib_dir = r"D:\BuildDo\Buildto\apps\customer_app\lib"
dart_files = []
for root, dirs, files in os.walk(lib_dir):
    for f in files:
        if f.endswith('.dart'):
            dart_files.append(os.path.join(root, f))

print(f"Total Dart files found: {len(dart_files)}")

# 1. Check relative imports
import_errors = []
for file_path in dart_files:
    file_dir = os.path.dirname(file_path)
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    for line_num, line in enumerate(lines, 1):
        line = line.strip()
        if line.startswith("import ") and not (line.startswith("import 'package:") or line.startswith('import "package:') or line.startswith("import 'dart:") or line.startswith('import "dart:')):
            m = re.search(r"import\s+['\"]([^'\"]+)['\"]", line)
            if m:
                target_rel = m.group(1)
                target_abs = os.path.normpath(os.path.join(file_dir, target_rel))
                if not os.path.exists(target_abs):
                    import_errors.append((file_path, line_num, target_rel, target_abs))

print(f"Broken relative imports: {len(import_errors)}")
for src, lnum, rel, absp in import_errors:
    print(f"  [BROKEN IMPORT] {os.path.relpath(src, lib_dir)}:{lnum} -> '{rel}'")

# 2. Check 16 screens exist and can be instantiated
screens = {
    "01_Home": "screens/home_screen.dart",
    "02_BrowseCategory": "screens/browse_category_screen.dart",
    "03_ProductDetail": "screens/product_detail_screen.dart",
    "04_ViewCart": "screens/view_cart_screen.dart",
    "05_Checkout": "screens/checkout_screen.dart",
    "06_OrderPlaced": "screens/order_placed_screen.dart",
    "07_TrackOrder": "screens/track_order_screen.dart",
    "08_MyOrders": "screens/my_orders_screen.dart",
    "09_CancelOrder": "screens/cancel_order_screen.dart",
    "10_OrderCancelled": "screens/order_cancelled_screen.dart",
    "11_Wishlist": "screens/wishlist_screen.dart",
    "12_Notifications": "screens/notifications_screen.dart",
    "13_ProfileSettings": "screens/profile_settings_screen.dart",
    "14_SupportHelp": "screens/support_help_screen.dart",
    "15_PaymentSuccessAlt": "screens/payment_success_alt_screen.dart",
    "16_RepeatOrder": "screens/repeat_order_screen.dart",
}

print("\n--- 16 Screens Existence Check ---")
for screen_id, rel_path in sorted(screens.items()):
    full_path = os.path.join(lib_dir, rel_path)
    exists = os.path.exists(full_path)
    size = os.path.getsize(full_path) if exists else 0
    print(f"  [{'PASS' if exists else 'FAIL'}] {screen_id}: {rel_path} ({size} bytes)")

