import re

# Read MenuItemModel definition
menu_item_path = r"D:\BuildDo\Buildto\apps\customer_app\lib\models\menu_item.dart"
with open(menu_item_path, 'r', encoding='utf-8') as f:
    menu_item_code = f.read()

# Extract fields
fields = re.findall(r"final\s+[\w\<\>\?]+\s+([\w]+);", menu_item_code)
print("MenuItemModel fields:", sorted(fields))

# Read CartProvider definition
cart_provider_path = r"D:\BuildDo\Buildto\apps\customer_app\lib\providers\cart_provider.dart"
with open(cart_provider_path, 'r', encoding='utf-8') as f:
    cart_code = f.read()

# Check methods
methods = [
    'quantityFor', 'addItem', 'decrementItem', 'incrementItem', 'clear', 
    'items', 'subtotal', 'itemCount'
]
print("\nCartProvider method checks:")
for m in methods:
    found = m in cart_code
    print(f"  {m}: {'FOUND' if found else 'MISSING'}")

# Read WishlistProvider definition
wishlist_path = r"D:\BuildDo\Buildto\apps\customer_app\lib\providers\wishlist_provider.dart"
with open(wishlist_path, 'r', encoding='utf-8') as f:
    wishlist_code = f.read()

print("\nWishlistProvider checks:")
for m in ['items', 'isWishlisted', 'toggleWishlist', 'removeFromWishlist', 'clearWishlist']:
    found = m in wishlist_code
    print(f"  {m}: {'FOUND' if found else 'MISSING'}")

# Read NotificationsProvider definition
notifs_path = r"D:\BuildDo\Buildto\apps\customer_app\lib\providers\notifications_provider.dart"
with open(notifs_path, 'r', encoding='utf-8') as f:
    notifs_code = f.read()

print("\nNotificationsProvider checks:")
for m in ['notifications', 'unreadCount', 'markAsRead', 'markAllAsRead']:
    found = m in notifs_code
    print(f"  {m}: {'FOUND' if found else 'MISSING'}")
