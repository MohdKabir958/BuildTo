import os
import re

screens_dir = r"D:\BuildDo\Buildto\apps\customer_app\lib\screens"

# Regex patterns for calls
cart_calls = set()
wishlist_calls = set()
session_calls = set()
notif_calls = set()

for f in os.listdir(screens_dir):
    if not f.endswith('.dart'):
        continue
    path = os.path.join(screens_dir, f)
    with open(path, 'r', encoding='utf-8') as fp:
        code = fp.read()
    
    # cart calls
    for m in re.finditer(r"cart\.(\w+)", code):
        cart_calls.add(m.group(1))
    # wishlist calls
    for m in re.finditer(r"wishlist\.(\w+)", code):
        wishlist_calls.add(m.group(1))
    # session calls
    for m in re.finditer(r"session\.(\w+)", code):
        session_calls.add(m.group(1))
    # notif calls
    for m in re.finditer(r"(?:notif|notifs|notifProvider)\.(\w+)", code):
        notif_calls.add(m.group(1))

print("Cart calls in screens:", sorted(cart_calls))
print("\nWishlist calls in screens:", sorted(wishlist_calls))
print("\nSession calls in screens:", sorted(session_calls))
print("\nNotification calls in screens:", sorted(notif_calls))
