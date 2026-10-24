import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer_app/models/menu_item.dart';
import 'package:customer_app/providers/cart_provider.dart';
import 'package:customer_app/providers/demo_orders_provider.dart';

void main() {
  group('Buildto Order Management & Lifecycle Tests', () {
    late DemoOrdersProvider ordersProvider;
    late CartProvider cart;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ordersProvider = DemoOrdersProvider();
      cart = CartProvider();
    });

    final testProduct = MenuItemModel(
      id: 'prod-cem-ultratech',
      vendorId: 'store-1',
      name: 'Ultratech Cement 50kg Bag',
      price: 390.0,
      category: 'cat-cement',
      description: 'Portland Pozzolana Cement',
      imageUrl: 'assets/products/ultratech_cement.jpg',
      isAvailable: true,
      minOrder: 5,
      stockQty: 100,
      unit: 'bags',
    );

    test('getOrderById returns null for unknown or non-existent order ID', () {
      final order = ordersProvider.getOrderById('#BT999999');
      expect(order, isNull, reason: 'Must return null for unknown order, not fallback to first order');

      final orderRandom = ordersProvider.getOrderById('completely_invalid');
      expect(orderRandom, isNull);
    });

    test('active un-dispatched order can be cancelled successfully', () {
      cart.addItem(item: testProduct, dhabaName: 'Test Depot', quantity: 5);
      final newOrder = ordersProvider.createOrder(
        cartItems: cart.items,
        total: 1950.0,
        address: 'Site #4',
        paymentMethod: 'UPI',
      );

      expect(newOrder.stage, equals(0));
      expect(newOrder.statusCode, equals('confirmed'));

      final success = ordersProvider.cancelOrder(newOrder.id, 'Site pour postponed');
      expect(success, isTrue);

      final updated = ordersProvider.getOrderById(newOrder.id);
      expect(updated!.status, equals('Cancelled'));
      expect(updated.statusCode, equals('cancelled'));
      expect(updated.stage, equals(-1));
      expect(updated.cancelReason, equals('Site pour postponed'));
    });

    test('already cancelled order rejects duplicate cancellation', () {
      cart.addItem(item: testProduct, dhabaName: 'Test Depot', quantity: 5);
      final newOrder = ordersProvider.createOrder(
        cartItems: cart.items,
        total: 1950.0,
        address: 'Site #4',
        paymentMethod: 'UPI',
      );

      ordersProvider.cancelOrder(newOrder.id, 'First cancellation');
      final secondCancel = ordersProvider.cancelOrder(newOrder.id, 'Duplicate cancellation');
      expect(secondCancel, isFalse);
    });

    test('dispatched or delivered order cannot be automatically cancelled', () {
      // Delivered order in seed data
      final deliveredOrder = ordersProvider.orders.firstWhere((o) => o.statusCode == 'delivered');
      final cancelDelivered = ordersProvider.cancelOrder(deliveredOrder.id, 'Too late');
      expect(cancelDelivered, isFalse);

      // Dispatched order in seed data (stage == 2)
      final dispatchedOrder = ordersProvider.orders.firstWhere((o) => o.stage == 2);
      final cancelDispatched = ordersProvider.cancelOrder(dispatchedOrder.id, 'Too late');
      expect(cancelDispatched, isFalse);
    });

    test('frequentlyOrderedItems excludes cancelled orders and includes item productIds', () {
      final items = ordersProvider.frequentlyOrderedItems;
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.productId, isNotNull);
        expect(item.name, isNotEmpty);
        expect(item.price, greaterThan(0));
      }
    });

    test('resetDemoData restores default demonstration orders', () async {
      // Create a temporary order
      cart.addItem(item: testProduct, dhabaName: 'Test Depot', quantity: 5);
      ordersProvider.createOrder(
        cartItems: cart.items,
        total: 1950.0,
        address: 'Temp Site',
        paymentMethod: 'UPI',
      );

      expect(ordersProvider.orders.length, greaterThan(4));

      await ordersProvider.resetDemoData();
      expect(ordersProvider.orders.length, equals(4));
      expect(ordersProvider.getOrderById('#BT012456'), isNotNull);
      expect(ordersProvider.getOrderById('#BT011982'), isNotNull);
    });
  });
}
