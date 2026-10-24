import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer_app/models/menu_item.dart';
import 'package:customer_app/providers/cart_provider.dart';
import 'package:customer_app/providers/demo_orders_provider.dart';

void main() {
  group('Buildto Checkout & Order Creation Tests', () {
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

    test('simulated checkout creates order with unique ID starting with #BT0', () {
      cart.addItem(item: testProduct, dhabaName: 'Shree Shyam Enterprises', quantity: 5);

      final order1 = ordersProvider.createOrder(
        cartItems: cart.items,
        total: cart.quote.grandTotal,
        address: '4891/1C Lal Bihara, New Delhi',
        paymentMethod: 'UPI',
        siteNotes: 'Gate #2 unloading',
      );

      expect(order1.id, startsWith('#BT0'));
      expect(order1.status, equals('Confirmed'));
      expect(order1.statusCode, equals('confirmed'));
      expect(order1.stage, equals(0));
      expect(order1.total, equals(cart.quote.grandTotal));
      expect(order1.supplier, equals('Shree Shyam Enterprises'));
      expect(order1.items.length, equals(1));
      expect(order1.items.first.productId, equals('prod-cem-ultratech'));
      expect(order1.items.first.qty, equals(5));

      final order2 = ordersProvider.createOrder(
        cartItems: cart.items,
        total: cart.quote.grandTotal,
        address: 'Sector 62, Noida Site',
        paymentMethod: 'COD',
      );

      expect(order2.id, startsWith('#BT0'));
      expect(order2.id, isNot(equals(order1.id)));
    });

    test('created orders appear immediately at the top of orders list', () {
      final initialCount = ordersProvider.orders.length;
      cart.addItem(item: testProduct, dhabaName: 'Depot A', quantity: 5);

      final created = ordersProvider.createOrder(
        cartItems: cart.items,
        total: 1950.0,
        address: 'Site A',
        paymentMethod: 'UPI',
      );

      expect(ordersProvider.orders.length, equals(initialCount + 1));
      expect(ordersProvider.orders.first.id, equals(created.id));
    });

    test('order lookup finds created order by ID without prefix sensitivity', () {
      cart.addItem(item: testProduct, dhabaName: 'Depot A', quantity: 5);
      final created = ordersProvider.createOrder(
        cartItems: cart.items,
        total: 1950.0,
        address: 'Site A',
        paymentMethod: 'UPI',
      );

      // Lookup with exact ID
      final found1 = ordersProvider.getOrderById(created.id);
      expect(found1, isNotNull);
      expect(found1!.id, equals(created.id));

      // Lookup without '#'
      final cleanId = created.id.replaceAll('#', '');
      final found2 = ordersProvider.getOrderById(cleanId);
      expect(found2, isNotNull);
      expect(found2!.id, equals(created.id));
    });
  });
}
