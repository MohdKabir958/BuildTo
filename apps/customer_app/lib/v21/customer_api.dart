import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef Data = Map<String, dynamic>;
Data object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Data> rows(Object? value) => value is List
    ? value.map(object).toList()
    : value is Map && value['items'] is List
        ? rows(value['items'])
        : <Data>[];
String field(Data value, String key, [String fallback = '']) =>
    value[key]?.toString() ?? fallback;
String label(Object? value) => (value ?? '')
    .toString()
    .toLowerCase()
    .split('_')
    .map((s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}')
    .join(' ');
String requestKey() =>
    'customer_${DateTime.now().microsecondsSinceEpoch}_${List.generate(12, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}';

/// Money and quantities stay exact; doubles never enter order mutations.
BigInt scaled(String value, int places) {
  if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value)) {
    throw const FormatException('Enter a positive number.');
  }
  final parts = value.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > places) {
    throw FormatException('Use up to $places decimal places.');
  }
  return BigInt.parse(parts[0]) * BigInt.from(10).pow(places) +
      BigInt.parse(
        fraction.padRight(places, '0').isEmpty
            ? '0'
            : fraction.padRight(places, '0'),
      );
}

String decimal(BigInt value, int places) {
  final base = BigInt.from(10).pow(places);
  final tail = (value % base)
      .toString()
      .padLeft(places, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${value ~/ base}${tail.isEmpty ? '' : '.$tail'}';
}

String money(Object? paise) {
  final n = BigInt.tryParse('${paise ?? 0}') ?? BigInt.zero;
  final digits = (n.abs() ~/ BigInt.from(100)).toString();
  final chunks = <String>[];
  var rest = digits;
  if (rest.length > 3) {
    chunks.insert(0, rest.substring(rest.length - 3));
    rest = rest.substring(0, rest.length - 3);
    while (rest.length > 2) {
      chunks.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
  }
  chunks.insert(0, rest);
  final cents = (n.abs() % BigInt.from(100)).toString().padLeft(2, '0');
  return '${n.isNegative ? '-' : ''}₹${chunks.join(',')}${cents == '00' ? '' : '.$cents'}';
}

String price(Object? rupees) {
  try {
    return money(scaled('$rupees', 2));
  } catch (_) {
    return 'Price unavailable';
  }
}

String quantityStep(
  String current,
  String minimum,
  String step,
  String? maximum,
  int direction,
) {
  final min = scaled(minimum, 3), delta = scaled(step, 3);
  var next = scaled(current, 3) + delta * BigInt.from(direction);
  if (next < min) next = min;
  if (maximum != null && next > scaled(maximum, 3)) return current;
  return decimal(next, 3);
}

class CustomerProblem implements Exception {
  const CustomerProblem(this.message, {this.status, this.code});
  final String message;
  final int? status;
  final String? code;
  @override
  String toString() => message;
}

class CustomerApi {
  CustomerApi({required this.origin, required this.token, http.Client? client})
      : client = client ?? http.Client() {
    parseOrigin(origin.toString());
  }
  final Uri origin;
  final Future<String?> Function() token;
  final http.Client client;
  VoidCallback? onUnauthorized;
  int _scope = 0;
  void invalidate() => _scope++;
  static Uri parseOrigin(String raw, {bool release = kReleaseMode}) {
    final u = Uri.tryParse(raw.trim());
    if (u == null ||
        u.host.isEmpty ||
        u.userInfo.isNotEmpty ||
        u.hasQuery ||
        u.hasFragment ||
        (u.path != '' && u.path != '/') ||
        (u.scheme != 'https' &&
            (release ||
                u.scheme != 'http' ||
                !['localhost', '127.0.0.1', '10.0.2.2'].contains(u.host)))) {
      throw const CustomerProblem('Configure a trusted HTTPS API origin.');
    }
    return u.replace(path: '');
  }

  Uri? imageUri(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = origin.resolve(value);
    return uri.origin == origin.origin &&
            uri.path.startsWith('/api/v2/catalog/images/') &&
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment
        ? uri
        : null;
  }

  Future<dynamic> call(
    String path, {
    String method = 'GET',
    Data? body,
    Map<String, String>? query,
    bool authenticated = true,
    String? key,
  }) async {
    if (!path.startsWith('/api/v2/') ||
        path.contains('..') ||
        path.contains('?') ||
        path.contains('#')) {
      throw const CustomerProblem('Invalid request.');
    }
    final scope = _scope;
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (authenticated) {
      final t = await token();
      if (t == null || t.isEmpty) {
        throw const CustomerProblem('Sign in to continue.', status: 401);
      }
      headers['Authorization'] = 'Bearer $t';
    }
    if (scope != _scope) {
      throw const CustomerProblem('Your account changed. Please try again.');
    }
    if (key != null) headers['Idempotency-Key'] = key;
    try {
      final req = http.Request(
        method,
        origin.resolve(path).replace(queryParameters: query),
      );
      req.headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final res = await http.Response.fromStream(
        await client.send(req),
      ).timeout(const Duration(seconds: 25));
      if (scope != _scope) {
        throw const CustomerProblem('Your account changed. Please try again.');
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        throw const CustomerProblem(
          'The service returned an unreadable response. Please retry.',
        );
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final error = object(object(decoded)['error']);
        if (res.statusCode == 401) {
          invalidate();
          onUnauthorized?.call();
        }
        final code = field(error, 'code');
        const messages = {
          'CART_VERSION_CONFLICT':
              'Your cart changed on another device. Refresh and review it.',
          'QUOTE_EXPIRED':
              'This price quote expired. Review the latest prices.',
          'MEDIA_STORAGE_UNAVAILABLE':
              'Document upload is temporarily unavailable.',
          'PROFILE_NOT_PROVISIONED':
              'Your account is being prepared. Please retry in a moment.',
          'INVALID_SEARCH':
              'Use letters, numbers, spaces or a hyphen to search.',
        };
        throw CustomerProblem(
          messages[code] ??
              (res.statusCode == 401
                  ? 'Your session expired. Sign in again.'
                  : res.statusCode == 403
                      ? 'This action is not available for your account.'
                      : res.statusCode == 404
                          ? 'This item or service is unavailable.'
                          : res.statusCode == 429
                              ? 'Too many requests. Please wait and retry.'
                              : res.statusCode >= 500
                                  ? 'The service is temporarily unavailable. Please retry.'
                                  : field(
                                      error,
                                      'message',
                                      'Please check the details and try again.',
                                    )),
          status: res.statusCode,
          code: code,
        );
      }
      if (decoded is! Map || !decoded.containsKey('data')) {
        throw const CustomerProblem(
          'Unexpected service response. Please retry.',
        );
      }
      return decoded['data'];
    } on TimeoutException {
      throw const CustomerProblem(
        'The connection is taking too long. Please retry.',
      );
    } on http.ClientException {
      throw const CustomerProblem(
        'Unable to connect. Check your internet and retry.',
      );
    }
  }

  Future<Data> me() async => object(await call('/api/v2/me'));
  Future<List<Data>> categories() async =>
      rows(await call('/api/v2/catalog/categories', authenticated: false));
  Future<Data> products({
    String? category,
    String? search,
    String? cursor,
    String? supplier,
  }) async =>
      object(
        await call(
          '/api/v2/catalog/products',
          authenticated: false,
          query: {
            if (category != null) 'categoryId': category,
            if (supplier != null) 'supplierId': supplier,
            if (search != null && search.isNotEmpty) 'search': search,
            if (cursor != null) 'cursor': cursor,
          },
        ),
      );
  Future<List<Data>> offers(String id) async => rows(
        await call(
          '/api/v2/catalog/listings',
          authenticated: false,
          query: {'productId': id},
        ),
      );
  Future<Data> cart() async => object(await call('/api/v2/cart'));
  Future<Data> setLine(String id, String quantity, int version) async => object(
        await call(
          '/api/v2/cart/lines/$id',
          method: 'PUT',
          body: {'quantity': quantity, 'expectedVersion': version},
        ),
      );
  Future<void> removeLine(String id, int version) async {
    await call(
      '/api/v2/cart/lines/$id',
      method: 'DELETE',
      body: {'expectedVersion': version},
    );
  }

  Future<List<Data>> addresses() async =>
      rows(await call('/api/v2/me/addresses'));
  Future<List<Data>> orders() async => rows(await call('/api/v2/orders'));
  Future<Data> order(String id) async =>
      object(await call('/api/v2/orders/$id'));
  Future<Data> preview(
    String address,
    int version,
    String key, {
    String? site,
    String? promotion,
  }) async =>
      object(
        await call(
          '/api/v2/checkouts',
          method: 'POST',
          key: key,
          body: {
            'addressId': address,
            'expectedCartVersion': version,
            if (site != null) 'siteId': site,
            if (promotion != null && promotion.isNotEmpty)
              'promotionCode': promotion,
          },
        ),
      );
  Future<Data> place(String quote, String key) async => object(
        await call(
          '/api/v2/checkouts/$quote/place',
          method: 'POST',
          key: key,
          body: {'clientRequestId': key},
        ),
      );
  void close() => client.close();
}

BigInt estimatedLinePaise(Data line) {
  return (scaled(field(line, 'unitPrice', '0'), 2) *
              scaled(field(line, 'quantity', '0'), 3) +
          BigInt.from(500)) ~/
      BigInt.from(1000);
}
