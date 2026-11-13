import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kraveo_ui/kraveo_ui.dart' show ClerkIdentity;
import 'package:customer_app/v21/customer_api.dart';
import 'package:customer_app/v21/customer_session.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

class FixtureIdentity implements CustomerIdentity {
  @override
  final ValueNotifier<ClerkIdentity> identity = ValueNotifier(
    ClerkIdentity(
      ready: true,
      signedIn: true,
      userId: id(1),
      sessionId: 'session_fixture',
    ),
  );
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> authenticate() async {
    identity.value = ClerkIdentity(
      ready: true,
      signedIn: true,
      userId: id(1),
      sessionId: 'session_fixture',
    );
    return true;
  }

  @override
  Future<String?> token({bool forceRefresh = false}) async =>
      identity.value.signedIn ? 'fixture-token' : null;
  @override
  Future<bool> signOut() async {
    identity.value = const ClerkIdentity(ready: true, signedIn: false);
    return true;
  }
}

class CustomerFixture {
  final requests = <http.Request>[];
  int version = 3;
  List<Data> cartItems = [];
  Data? rfq;
  final auth = FixtureIdentity();
  late final CustomerApi api;
  late final CustomerSession session;
  final products = <Data>[
    {
      'id': id(2),
      'code': 'cement-opc',
      'name': 'UltraTech Cement 50 kg',
      'category': {'id': id(3), 'name': 'Cement & concrete'},
      'fromPrice': '390.00',
      'fromUnit': 'BAG',
      'description': 'OPC 43 grade cement for your next project.',
      'specification': {'grade': 'OPC 43', 'pack': '50 kg'},
      'images': [],
    },
    {
      'id': id(4),
      'name': 'TMT steel bars 12 mm',
      'category': {'id': id(5), 'name': 'Steel & TMT'},
      'fromPrice': '82.00',
      'fromUnit': 'KG',
      'images': [],
    },
  ];
  late final address = <String, dynamic>{
    'id': id(7),
    'cityId': id(8),
    'cityName': 'Hyderabad',
    'stateCode': 'TS',
    'label': 'New home site',
    'recipientName': 'Kabir',
    'phoneE164': '+919876543210',
    'line1': 'Plot 24, Jubilee Hills',
    'locality': 'Jubilee Hills',
    'postalCode': '500033',
    'isDefault': true,
  };
  late final order = <String, dynamic>{
    'id': id(9),
    'publicNumber': 'SP-2026-1042',
    'status': 'PLACED',
    'paymentStatus': 'PENDING',
    'totalPaise': '395000',
    'subtotalPaise': '390000',
    'taxPaise': '0',
    'deliveryPaise': '5000',
    'discountPaise': '0',
    'placedAt': '2026-11-13T10:00:00Z',
    'addressSnapshot': address,
    'suppliers': [
      {
        'id': id(10),
        'supplierId': id(6),
        'status': 'PENDING',
        'totalPaise': '395000',
        'items': [
          {
            'id': id(11),
            'listingId': id(12),
            'name': 'UltraTech Cement 50 kg',
            'unitCode': 'BAG',
            'quantity': '10',
            'unitPrice': '390.00',
            'lineTotalPaise': '390000',
          },
        ],
      },
    ],
  };
  CustomerFixture() {
    api = CustomerApi(
      origin: Uri.parse('https://api.splyzo.test'),
      token: auth.token,
      client: MockClient(handle),
    );
    session = CustomerSession(api: api, auth: auth)
      ..user = {'id': id(1), 'displayName': 'Kabir'};
  }
  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    dynamic data;
    final path = r.url.path;
    final body = r.body.isEmpty
        ? <String, dynamic>{}
        : object(jsonDecode(r.body));
    if (path == '/api/v2/me') {
      data = {'id': id(1), 'displayName': 'Kabir'};
    } else if (path == '/api/v2/catalog/categories') {
      data = [
        {'id': id(3), 'name': 'Cement & concrete'},
        {'id': id(5), 'name': 'Steel & TMT'},
        {'id': id(13), 'name': 'Bricks & blocks'},
      ];
    } else if (path == '/api/v2/catalog/products') {
      data = {'items': products, 'nextCursor': null};
    } else if (path == '/api/v2/catalog/suppliers') {
      data = {
        'items': [
          {'id': id(6), 'displayName': 'Shree Shyam Enterprises'},
          {'id': id(14), 'displayName': 'ABC Building Materials'},
        ],
        'nextCursor': null,
      };
    } else if (path == '/api/v2/catalog/listings') {
      data = [
        {
          'id': id(12),
          'supplierId': id(6),
          'supplierName': 'Shree Shyam Enterprises',
          'productId': id(2),
          'unitCode': 'BAG',
          'unitPrice': '390.00',
          'minOrderQty': '10',
          'stepQty': '5',
          'maxOrderQty': '1000',
          'taxInclusive': true,
          'priceTiers': [],
        },
      ];
    } else if (path == '/api/v2/cart') {
      data = {'version': version, 'items': cartItems};
    } else if (path.startsWith('/api/v2/cart/lines/')) {
      if (body['expectedVersion'] != version) {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'CART_VERSION_CONFLICT',
              'message': 'Refresh cart.',
            },
          }),
          409,
        );
      }
      version++;
      if (r.method == 'DELETE') {
        cartItems.clear();
      } else {
        cartItems = [
          {
            'listingId': id(12),
            'quantity': body['quantity'],
            'displayName': 'UltraTech Cement 50 kg',
            'supplierId': id(6),
            'supplierName': 'Shree Shyam Enterprises',
            'unitCode': 'BAG',
            'unitPrice': '390.00',
            'available': true,
          },
        ];
      }
      data = {'version': version, 'items': cartItems};
    } else if (path == '/api/v2/me/addresses') {
      data = r.method == 'GET' ? [address] : {...address, ...body};
    } else if (path == '/api/v2/delivery/cities') {
      data = [
        {'id': id(8), 'name': 'Hyderabad'},
      ];
    } else if (path == '/api/v2/me/sites' || path == '/api/v2/me/projects') {
      data = {'items': [], 'nextCursor': null};
    } else if (path == '/api/v2/orders') {
      data = [order];
    } else if (path == '/api/v2/orders/${id(9)}') {
      data = order;
    } else if (path == '/api/v2/checkouts') {
      data = {
        'id': id(15),
        'totalPaise': '395000',
        'subtotalPaise': '390000',
        'taxPaise': '0',
        'deliveryPaise': '5000',
        'discountPaise': '0',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .toUtc()
            .toIso8601String(),
      };
    } else if (path == '/api/v2/checkouts/${id(15)}/place') {
      data = order;
    } else if (path == '/api/v2/me/wishlist') {
      data = [];
    } else if (path == '/api/v2/me/notifications') {
      data = {'items': [], 'nextCursor': null};
    } else if (path == '/api/v2/support/cases') {
      data = r.method == 'GET'
          ? []
          : {'id': id(16), 'subject': body['subject']};
    } else if (path == '/api/v2/support/cases/${id(16)}') {
      data = {
        'id': id(16),
        'subject': 'Order delivery question',
        'status': 'OPEN',
        'messages': [
          {'authorId': id(1), 'body': 'Please confirm site delivery.'},
        ],
      };
    } else if (path.endsWith('/messages')) {
      data = {'id': id(17), 'body': body['message']};
    } else if (path == '/api/v2/rfqs') {
      if (r.method == 'POST') {
        rfq = {
          'id': id(18),
          'publicNumber': 'RFQ-104',
          'status': 'DRAFT',
          ...body,
        };
        data = rfq;
      } else {
        data = rfq == null ? [] : [rfq];
      }
    } else if (path == '/api/v2/rfqs/${id(18)}') {
      data = rfq;
    } else if (path.endsWith('/open')) {
      rfq!['status'] = 'OPEN';
      data = {'id': id(18), 'status': 'OPEN'};
    } else if (path.contains('/invitations/')) {
      data = {'alreadyInvited': false};
    } else if (path.endsWith('/quotes') ||
        path.endsWith('/shipments') ||
        path.endsWith('/invoices') ||
        path.endsWith('/returns') ||
        path.endsWith('/payments')) {
      data = [];
    } else {
      return http.Response(
        jsonEncode({
          'error': {
            'code': 'FIXTURE_ROUTE_MISSING',
            'message': 'Missing fixture route: $path',
          },
        }),
        404,
      );
    }
    return http.Response(
      jsonEncode({'data': data, 'requestId': 'fixture'}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  void dispose() {
    session.dispose();
    auth.identity.dispose();
  }
}
