import 'package:flutter/material.dart';
import '../models/menu_item.dart';
import '../models/sample_construction_data.dart';

class WishlistProvider with ChangeNotifier {
  final List<MenuItemModel> _items = [];

  WishlistProvider() {
    // Seed initial wishlist items matching Screen 11
    final products = sampleConstructionProducts();
    for (final list in products.values) {
      for (final p in list) {
        if (p.id == 'prod-cem-acc' || p.id == 'prod-stl-tmt-12mm' || p.id == 'prod-brk-clay-piece') {
          if (!_items.any((item) => item.id == p.id)) {
            _items.add(p);
          }
        }
      }
    }
  }

  List<MenuItemModel> get items => List.unmodifiable(_items);
  int get count => _items.length;

  bool contains(String productId) => _items.any((item) => item.id == productId);
  bool isWishlisted(String productId) => contains(productId);

  void toggle(MenuItemModel product) {
    final index = _items.indexWhere((item) => item.id == product.id);
    if (index >= 0) {
      _items.removeAt(index);
    } else {
      _items.add(product);
    }
    notifyListeners();
  }

  void toggleWishlist(MenuItemModel product) => toggle(product);

  void add(MenuItemModel product) {
    if (!contains(product.id)) {
      _items.add(product);
      notifyListeners();
    }
  }

  void remove(String productId) {
    _items.removeWhere((item) => item.id == productId);
    notifyListeners();
  }

  void removeFromWishlist(String productId) => remove(productId);

  void clear() {
    _items.clear();
    notifyListeners();
  }

  void clearWishlist() => clear();
}
