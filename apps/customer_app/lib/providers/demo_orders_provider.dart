import 'package:flutter/material.dart';
import '../models/cart_item.dart';

class BuildtoOrderItem {
  final String name;
  final int qty;
  final double price;
  final String imageUrl;
  final String unit;

  const BuildtoOrderItem({
    required this.name,
    required this.qty,
    required this.price,
    required this.imageUrl,
    this.unit = 'units',
  });
}

class BuildtoOrder {
  final String id;
  final String date;
  String status;
  String statusCode; // 'processing', 'delivered', 'cancelled'
  final List<BuildtoOrderItem> items;
  final double total;
  final String supplier;
  final String deliveryAddress;
  final String siteNotes;
  final String paymentMethod;
  final int stage; // 0: Confirmed, 1: Packed, 2: Out for Delivery, 3: Delivered
  final String driverName;
  final String driverVehicle;
  final String driverPhone;
  String? cancelReason;

  BuildtoOrder({
    required this.id,
    required this.date,
    required this.status,
    required this.statusCode,
    required this.items,
    required this.total,
    required this.supplier,
    required this.deliveryAddress,
    this.siteNotes = 'Call site supervisor before unloading',
    this.paymentMethod = 'UPI (Demo)',
    this.stage = 2,
    this.driverName = 'Raju Kumar (Site Driver)',
    this.driverVehicle = 'Tata 407 Heavy Flatbed • DL 1L AA 9081',
    this.driverPhone = '+91 98765 00123',
    this.cancelReason,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'status': status,
      'statusCode': statusCode,
      'items': items.map((i) => {
        'name': i.name,
        'qty': i.qty,
        'price': i.price,
        'image': i.imageUrl,
        'unit': i.unit,
      }).toList(),
      'total': total,
      'supplier': supplier,
      'address': deliveryAddress,
      'paymentMethod': paymentMethod,
    };
  }
}

class DemoOrdersProvider with ChangeNotifier {
  static int _orderCounter = 12457;

  final List<BuildtoOrder> _orders = [
    BuildtoOrder(
      id: '#BT012456',
      date: '24 Oct 2026, 10:30 AM',
      status: 'Out for Delivery',
      statusCode: 'processing',
      stage: 2,
      supplier: 'Shree Shyam Enterprises',
      deliveryAddress: '4891/1C Lal Bihara, Near Metro Pillar 42, New Delhi - 110001',
      siteNotes: 'Call site supervisor before unloading at Gate #2',
      paymentMethod: 'UPI',
      total: 3420.0,
      items: const [
        BuildtoOrderItem(
          name: 'Ultratech Cement 50kg Bag',
          qty: 3,
          price: 1170.0,
          imageUrl: 'assets/products/ultratech_cement.jpg',
          unit: 'bags',
        ),
        BuildtoOrderItem(
          name: 'Tata Tiscon 550D TMT Rebar 12mm',
          qty: 2,
          price: 2250.0,
          imageUrl: 'assets/products/tmt_steel_bars.jpg',
          unit: 'pieces',
        ),
      ],
    ),
    BuildtoOrder(
      id: '#BT011982',
      date: '20 Oct 2026, 03:15 PM',
      status: 'Delivered',
      statusCode: 'delivered',
      stage: 3,
      supplier: 'ABC Traders',
      deliveryAddress: '4891/1C Lal Bihara, Near Metro Pillar 42, New Delhi - 110001',
      paymentMethod: 'Net Banking',
      total: 12700.0,
      items: const [
        BuildtoOrderItem(
          name: 'Kiln Burned Red Clay Bricks (1,000 Pcs)',
          qty: 1,
          price: 7500.0,
          imageUrl: 'assets/products/red_bricks.jpg',
          unit: 'lot',
        ),
        BuildtoOrderItem(
          name: 'Coarse River Sand (100 CFT)',
          qty: 1,
          price: 5200.0,
          imageUrl: 'assets/products/sand_aggregates.jpg',
          unit: 'truckload',
        ),
      ],
    ),
    BuildtoOrder(
      id: '#BT010411',
      date: '14 Oct 2026, 11:00 AM',
      status: 'Delivered',
      statusCode: 'delivered',
      stage: 3,
      supplier: 'R.K. Building Materials',
      deliveryAddress: '4891/1C Lal Bihara, Near Metro Pillar 42, New Delhi - 110001',
      paymentMethod: 'Pay on Unloading (COD)',
      total: 2100.0,
      items: const [
        BuildtoOrderItem(
          name: 'ACC Gold Water Shield Cement 50kg',
          qty: 5,
          price: 2100.0,
          imageUrl: 'assets/products/acc_cement.jpg',
          unit: 'bags',
        ),
      ],
    ),
    BuildtoOrder(
      id: '#BT009832',
      date: '08 Oct 2026, 09:45 AM',
      status: 'Cancelled',
      statusCode: 'cancelled',
      stage: -1,
      supplier: 'Shree Shyam Enterprises',
      deliveryAddress: '4891/1C Lal Bihara, Near Metro Pillar 42, New Delhi - 110001',
      paymentMethod: 'UPI',
      total: 1680.0,
      cancelReason: 'Site construction delayed',
      items: const [
        BuildtoOrderItem(
          name: 'Ambuja Kawach Cement 50kg',
          qty: 4,
          price: 1680.0,
          imageUrl: 'assets/products/ambuja_cement.jpg',
          unit: 'bags',
        ),
      ],
    ),
  ];

  List<BuildtoOrder> get orders => List.unmodifiable(_orders);

  List<BuildtoOrder> ordersByStatus(String statusFilter) {
    if (statusFilter == 'all') return orders;
    return _orders.where((o) => o.statusCode == statusFilter).toList();
  }

  BuildtoOrder? getOrderById(String id) {
    for (final o in _orders) {
      if (o.id == id || o.id.replaceAll('#', '') == id.replaceAll('#', '')) {
        return o;
      }
    }
    return _orders.isNotEmpty ? _orders.first : null;
  }

  BuildtoOrder createOrder({
    required List<CartItem> cartItems,
    required double total,
    required String address,
    required String paymentMethod,
    String siteNotes = 'Call site supervisor before unloading at Gate #2',
  }) {
    final now = DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = now.minute.toString().padLeft(2, '0');
    final dateStr = '${now.day} ${months[now.month - 1]} ${now.year}, $hour:$minuteStr $ampm';

    final orderId = '#BT0${_orderCounter++}';

    final orderItems = cartItems.map((ci) {
      return BuildtoOrderItem(
        name: ci.name,
        qty: ci.quantity,
        price: ci.totalPrice,
        imageUrl: ci.imageUrl ?? 'assets/products/ultratech_cement.jpg',
        unit: ci.unit,
      );
    }).toList();

    final supplier = cartItems.isNotEmpty && cartItems.first.dhabaName.isNotEmpty
        ? cartItems.first.dhabaName
        : 'Shree Shyam Enterprises';

    final newOrder = BuildtoOrder(
      id: orderId,
      date: dateStr,
      status: 'Out for Delivery',
      statusCode: 'processing',
      stage: 2,
      supplier: supplier,
      deliveryAddress: address,
      siteNotes: siteNotes,
      paymentMethod: paymentMethod,
      total: total,
      items: orderItems,
    );

    _orders.insert(0, newOrder);
    notifyListeners();
    return newOrder;
  }

  bool cancelOrder(String orderId, String reason) {
    final order = getOrderById(orderId);
    if (order != null) {
      order.status = 'Cancelled';
      order.statusCode = 'cancelled';
      order.cancelReason = reason;
      notifyListeners();
      return true;
    }
    return false;
  }

  List<BuildtoOrderItem> get frequentlyOrderedItems {
    final map = <String, BuildtoOrderItem>{};
    for (final o in _orders) {
      if (o.statusCode != 'cancelled') {
        for (final item in o.items) {
          map.putIfAbsent(item.name, () => item);
        }
      }
    }
    return map.values.toList();
  }
}
