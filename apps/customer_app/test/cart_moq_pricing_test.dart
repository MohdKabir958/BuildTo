import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/models/menu_item.dart';
import 'package:customer_app/providers/cart_provider.dart';

void main() {
  group('Buildto Cart, MOQ and Pricing Tests', () {
    late CartProvider cart;

    setUp(() {
      cart = CartProvider();
    });

    final inStockItemWithMoq = MenuItemModel(
      id: 'test-item-moq',
      vendorId: 'depot-1',
      name: 'Ultratech Super Cement 50kg',
      price: 400.0,
      category: 'cat-cement',
      description: 'Portland Pozzolana Cement',
      imageUrl: 'assets/products/ultratech_cement.jpg',
      isAvailable: true,
      minOrder: 10,
      stockQty: 50,
      unit: 'bags',
    );

    final outOfStockItem = MenuItemModel(
      id: 'test-item-oos',
      vendorId: 'depot-1',
      name: 'Discontinued Rebar',
      price: 500.0,
      category: 'cat-steel',
      description: 'Out of stock item',
      imageUrl: 'assets/products/tmt_steel_bars.jpg',
      isAvailable: false,
      stockQty: 0,
      unit: 'pieces',
    );

    test('adding out-of-stock item is rejected and cart remains empty', () {
      final success = cart.addItem(
        item: outOfStockItem,
        dhabaName: 'Test Depot',
        quantity: 1,
      );
      expect(success, isFalse);
      expect(cart.items, isEmpty);
      expect(cart.itemCount, equals(0));
    });

    test('initial add enforces Minimum Order Quantity (MOQ)', () {
      // Requested qty 1, but minOrder is 10
      final success = cart.addItem(
        item: inStockItemWithMoq,
        dhabaName: 'Test Depot',
        quantity: 1,
      );
      expect(success, isTrue);
      expect(cart.items.length, equals(1));
      expect(cart.items.first.quantity, equals(10));
      expect(cart.subtotal, equals(4000.0));
    });

    test('increment is capped at availableStock', () {
      final limitedItem = MenuItemModel(
        id: 'test-item-limited',
        vendorId: 'depot-1',
        name: 'Special Binding Wire',
        price: 100.0,
        category: 'cat-hardware',
        description: 'Limited roll',
        imageUrl: 'assets/products/hardware.jpg',
        isAvailable: true,
        minOrder: 1,
        stockQty: 3,
        unit: 'rolls',
      );

      cart.addItem(item: limitedItem, dhabaName: 'Test Depot', quantity: 2);
      final lineItemId = cart.items.first.cartItemId;

      // 2 -> 3 (at stock limit)
      final inc1 = cart.incrementItem(lineItemId);
      expect(inc1, isTrue);
      expect(cart.items.first.quantity, equals(3));

      // 3 -> 4 (exceeds stock limit of 3)
      final inc2 = cart.incrementItem(lineItemId);
      expect(inc2, isFalse);
      expect(cart.items.first.quantity, equals(3));
    });

    test('decrementing below minOrder removes item from cart cleanly', () {
      cart.addItem(item: inStockItemWithMoq, dhabaName: 'Test Depot', quantity: 10);
      final lineItemId = cart.items.first.cartItemId;
      expect(cart.items.first.quantity, equals(10));

      // Decrementing below MOQ (10) should cleanly remove the line item
      cart.decrementItem(lineItemId);
      expect(cart.items, isEmpty);
      expect(cart.itemCount, equals(0));
    });

    test('pricing quote calculates standard delivery and free delivery over threshold', () {
      // Subtotal < 25,000 -> standard delivery fee ₹150
      cart.addItem(item: inStockItemWithMoq, dhabaName: 'Test Depot', quantity: 10);
      // 10 * 400 = 4,000
      var quote = cart.quote;
      expect(quote.subtotal, equals(4000.0));
      expect(quote.deliveryFee, equals(150.0));
      expect(quote.grandTotal, equals(4150.0));

      // Add more items so subtotal >= 25,000 -> delivery fee FREE
      final expensiveItem = MenuItemModel(
        id: 'test-item-bulk',
        vendorId: 'depot-1',
        name: 'Structural Steel Bundle',
        price: 25000.0,
        category: 'cat-steel',
        description: 'Bulk bundle',
        imageUrl: 'assets/products/tmt_steel_bars.jpg',
        isAvailable: true,
        minOrder: 1,
        stockQty: 10,
        unit: 'ton',
      );
      cart.addItem(item: expensiveItem, dhabaName: 'Test Depot', quantity: 1);

      // Subtotal = 4,000 + 25,000 = 29,000 >= 25,000
      quote = cart.quote;
      expect(quote.subtotal, equals(29000.0));
      expect(quote.deliveryFee, equals(0.0));
      expect(quote.grandTotal, equals(29000.0));
    });

    test('clear resets cart items and totals', () {
      cart.addItem(item: inStockItemWithMoq, dhabaName: 'Test Depot', quantity: 10);
      expect(cart.items, isNotEmpty);
      cart.clear();
      expect(cart.items, isEmpty);
      expect(cart.subtotal, equals(0.0));
      expect(cart.quote.grandTotal, equals(0.0));
    });
  });
}
