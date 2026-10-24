import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';

class BuildtoOrderItem {
  final String? productId;
  final String? vendorId;
  final String name;
  final int qty;
  final double price;
  final String imageUrl;
  final String unit;

  const BuildtoOrderItem({
    this.productId,
    this.vendorId,
    required this.name,
    required this.qty,
    required this.price,
    required this.imageUrl,
    this.unit = 'units',
  });

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'vendorId': vendorId,
        'name': name,
        'qty': qty,
        'price': price,
        'imageUrl': imageUrl,
        'unit': unit,
      };

  factory BuildtoOrderItem.fromMap(Map<String, dynamic> map) => BuildtoOrderItem(
        productId: map['productId'] as String?,
        vendorId: map['vendorId'] as String?,
        name: map['name'] as String? ?? 'Material',
        qty: (map['qty'] as num?)?.toInt() ?? 1,
        price: (map['price'] as num?)?.toDouble() ?? 0.0,
        imageUrl: map['imageUrl'] as String? ??
            (map['image'] as String? ?? 'assets/products/ultratech_cement.jpg'),
        unit: map['unit'] as String? ?? 'units',
      );
}

class BuildtoOrder {
  final String id;
  final String date;
  String status;
  String statusCode; // 'confirmed', 'processing', 'delivered', 'cancelled'
  final List<BuildtoOrderItem> items;
  final double total;
  final String supplier;
  final String deliveryAddress;
  final String siteNotes;
  final String paymentMethod;
  int stage; // 0: Confirmed, 1: Yard Allocation, 2: Dispatched, 3: Delivered, -1: Cancelled
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
    this.stage = 0,
    this.driverName = 'Supplier Fleet Logistics',
    this.driverVehicle = 'Assigned Depot Carrier',
    this.driverPhone = '+91 98765 00123',
    this.cancelReason,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'status': status,
      'statusCode': statusCode,
      'items': items.map((i) => i.toMap()).toList(),
      'total': total,
      'supplier': supplier,
      'address': deliveryAddress,
      'siteNotes': siteNotes,
      'paymentMethod': paymentMethod,
      'stage': stage,
      'driverName': driverName,
      'driverVehicle': driverVehicle,
      'driverPhone': driverPhone,
      'cancelReason': cancelReason,
    };
  }

  factory BuildtoOrder.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? [];
    final parsedItems = rawItems
        .map((i) => BuildtoOrderItem.fromMap(Map<String, dynamic>.from(i as Map)))
        .toList();

    return BuildtoOrder(
      id: map['id'] as String? ?? '#BT000000',
      date: map['date'] as String? ?? '',
      status: map['status'] as String? ?? 'Confirmed',
      statusCode: map['statusCode'] as String? ?? 'confirmed',
      items: parsedItems,
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      supplier: map['supplier'] as String? ?? 'Verified Depot',
      deliveryAddress: map['address'] as String? ??
          (map['deliveryAddress'] as String? ?? ''),
      siteNotes: map['siteNotes'] as String? ??
          'Call site supervisor before unloading',
      paymentMethod: map['paymentMethod'] as String? ?? 'UPI (Demo)',
      stage: (map['stage'] as num?)?.toInt() ?? 0,
      driverName: map['driverName'] as String? ?? 'Supplier Fleet Logistics',
      driverVehicle: map['driverVehicle'] as String? ?? 'Assigned Depot Carrier',
      driverPhone: map['driverPhone'] as String? ?? '+91 98765 00123',
      cancelReason: map['cancelReason'] as String?,
    );
  }
}

class DemoOrdersProvider with ChangeNotifier {
  static const String _prefsKey = 'buildto_demo_orders_v2';
  static int _orderCounter = 12457;

  final List<BuildtoOrder> _orders = [];

  DemoOrdersProvider() {
    _loadFromPrefs();
  }

  static List<BuildtoOrder> _initialSeedOrders() {
    return [
      BuildtoOrder(
        id: '#BT012456',
        date: '24 Oct 2026, 10:30 AM',
        status: 'Dispatched',
        statusCode: 'processing',
        stage: 2,
        supplier: 'Shree Shyam Enterprises',
        deliveryAddress:
            '4891/1C Lal Bihara, Near Metro Pillar 42, New Delhi - 110001',
        siteNotes: 'Call site supervisor before unloading at Gate #2',
        paymentMethod: 'UPI',
        total: 3420.0,
        driverName: 'Depot Fleet Logistics',
        driverVehicle: 'Tata 407 Flatbed Carrier',
        driverPhone: '+91 98765 00123',
        items: const [
          BuildtoOrderItem(
            productId: 'prod-cem-ultratech',
            vendorId: 'store-1',
            name: 'Ultratech Cement 50kg Bag',
            qty: 3,
            price: 1170.0,
            imageUrl: 'assets/products/ultratech_cement.jpg',
            unit: 'bags',
          ),
          BuildtoOrderItem(
            productId: 'prod-stl-tata-12',
            vendorId: 'store-2',
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
        deliveryAddress:
            '4891/1C Lal Bihara, Near Metro Pillar 42, New Delhi - 110001',
        paymentMethod: 'Net Banking',
        total: 12700.0,
        driverName: 'ABC Logistics Fleet',
        driverVehicle: 'Heavy Tipper Truck',
        driverPhone: '+91 98765 00123',
        items: const [
          BuildtoOrderItem(
            productId: 'prod-brk-red-clay',
            vendorId: 'store-3',
            name: 'Kiln Burned Red Clay Bricks (1,000 Pcs)',
            qty: 1,
            price: 7500.0,
            imageUrl: 'assets/products/red_bricks.jpg',
            unit: 'lot',
          ),
          BuildtoOrderItem(
            productId: 'prod-snd-river-100',
            vendorId: 'store-3',
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
        deliveryAddress:
            '4891/1C Lal Bihara, Near Metro Pillar 42, New Delhi - 110001',
        paymentMethod: 'Pay on Unloading (COD)',
        total: 2100.0,
        driverName: 'R.K. Logistics Fleet',
        driverVehicle: 'Medium Commercial Carrier',
        driverPhone: '+91 98765 00123',
        items: const [
          BuildtoOrderItem(
            productId: 'prod-cem-acc-gold',
            vendorId: 'store-4',
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
        deliveryAddress:
            '4891/1C Lal Bihara, Near Metro Pillar 42, New Delhi - 110001',
        paymentMethod: 'UPI',
        total: 1680.0,
        cancelReason: 'Site construction delayed',
        items: const [
          BuildtoOrderItem(
            productId: 'prod-cem-ambuja-kw',
            vendorId: 'store-1',
            name: 'Ambuja Kawach Cement 50kg',
            qty: 4,
            price: 1680.0,
            imageUrl: 'assets/products/ambuja_cement.jpg',
            unit: 'bags',
          ),
        ],
      ),
    ];
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr) as List<dynamic>;
        _orders.clear();
        for (final item in decoded) {
          _orders.add(BuildtoOrder.fromMap(Map<String, dynamic>.from(item as Map)));
        }
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('Error loading demo orders from prefs: $e');
    }

    // Default seed fallback
    _orders.clear();
    _orders.addAll(_initialSeedOrders());
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listMap = _orders.map((o) => o.toMap()).toList();
      await prefs.setString(_prefsKey, jsonEncode(listMap));
    } catch (e) {
      debugPrint('Error saving demo orders to prefs: $e');
    }
  }

  List<BuildtoOrder> get orders => List.unmodifiable(_orders);

  List<BuildtoOrder> ordersByStatus(String statusFilter) {
    if (statusFilter == 'all') return orders;
    return _orders.where((o) => o.statusCode == statusFilter).toList();
  }

  BuildtoOrder? getOrderById(String id) {
    final cleanTarget = id.replaceAll('#', '').trim().toLowerCase();
    for (final o in _orders) {
      if (o.id.replaceAll('#', '').trim().toLowerCase() == cleanTarget) {
        return o;
      }
    }
    // Return null when order is genuinely not found.
    return null;
  }

  BuildtoOrder createOrder({
    required List<CartItem> cartItems,
    required double total,
    required String address,
    required String paymentMethod,
    String siteNotes = 'Call site supervisor before unloading at Gate #2',
  }) {
    final now = DateTime.now();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = now.minute.toString().padLeft(2, '0');
    final dateStr =
        '${now.day} ${months[now.month - 1]} ${now.year}, $hour:$minuteStr $ampm';

    final orderId = '#BT0${_orderCounter++}';

    final orderItems = cartItems.map((ci) {
      return BuildtoOrderItem(
        productId: ci.item.id,
        vendorId: ci.dhabaId.isNotEmpty ? ci.dhabaId : ci.item.vendorId,
        name: ci.name,
        qty: ci.quantity,
        price: ci.totalPrice,
        imageUrl: ci.imageUrl ?? 'assets/products/ultratech_cement.jpg',
        unit: ci.unit,
      );
    }).toList();

    final supplier = cartItems.isNotEmpty && cartItems.first.dhabaName.isNotEmpty
        ? cartItems.first.dhabaName
        : 'Verified Depot';

    final newOrder = BuildtoOrder(
      id: orderId,
      date: dateStr,
      status: 'Confirmed',
      statusCode: 'confirmed',
      stage: 0,
      supplier: supplier,
      deliveryAddress: address,
      siteNotes: siteNotes,
      paymentMethod: paymentMethod,
      total: total,
      items: orderItems,
      driverName: '$supplier Logistics Dispatch',
      driverVehicle: 'Depot Flatbed Truck',
      driverPhone: '+91 98765 00123',
    );

    _orders.insert(0, newOrder);
    _saveToPrefs();
    notifyListeners();
    return newOrder;
  }

  bool cancelOrder(String orderId, String reason) {
    final order = getOrderById(orderId);
    if (order == null) return false;
    if (order.statusCode == 'cancelled') return false;
    if (order.statusCode == 'delivered' || order.stage > 1) {
      // Dispatched or delivered orders cannot be cancelled automatically
      return false;
    }

    order.status = 'Cancelled';
    order.statusCode = 'cancelled';
    order.stage = -1;
    order.cancelReason = reason;
    _saveToPrefs();
    notifyListeners();
    return true;
  }

  Future<void> resetDemoData() async {
    _orders.clear();
    _orders.addAll(_initialSeedOrders());
    await _saveToPrefs();
    notifyListeners();
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
