import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Dedicated V2.1 origin. Never piggyback on Grozo's legacy /api transport.
/// Supply --dart-define=BUILDTO_V21_API_BASE_URL=https://your-api-origin.
/// S01 has NO implicit auth fallback; S02 provides the verified Clerk token.
abstract final class SupplierV21Config {
  static const String configuredOrigin =
      String.fromEnvironment('BUILDTO_V21_API_BASE_URL');

  static Uri parseOrigin(String input, {bool release = kReleaseMode}) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.path != '' && uri.path != '/') {
      throw StateError('Configure a plain HTTPS BuildTo V2.1 API origin.');
    }
    final localDebug = !release &&
        uri.scheme == 'http' &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '10.0.2.2');
    if (uri.scheme != 'https' && !localDebug) {
      throw StateError(
          'BuildTo V2.1 requires HTTPS except the local debug emulator.');
    }
    return uri.replace(path: '', query: null, fragment: null);
  }

  static Uri get origin => parseOrigin(configuredOrigin);
}

typedef SupplierAccessToken = Future<String?> Function();

enum SupplierV21Problem {
  configuration,
  authentication,
  forbidden,
  notFound,
  conflict,
  precondition,
  rateLimited,
  network,
  server,
  invalidResponse,
  validation,
}

class SupplierV21Exception implements Exception {
  const SupplierV21Exception(this.problem,
      {this.code, this.requestId, this.statusCode, this.retryAfter});
  final SupplierV21Problem problem;
  final String? code;
  final String? requestId;
  final int? statusCode;
  final Duration? retryAfter;

  @override
  String toString() =>
      'SupplierV21Exception($problem, $code, status=$statusCode, requestId=$requestId)';
}

class SupplierV21Response {
  const SupplierV21Response({required this.data, this.requestId});
  final Object? data;
  final String? requestId;

  Map<String, Object?> requireObject() {
    if (data is! Map<String, dynamic>) {
      throw SupplierV21Exception(SupplierV21Problem.invalidResponse,
          requestId: requestId);
    }
    return Map<String, Object?>.from(data as Map<String, dynamic>);
  }
}

/// HTTP boundary only. Never computes money or supplier authorization in Dart.
/// Caller must choose endpoints from S00 contract map and pass the exact
/// supplier ID obtained via an authenticated /api/v2/me response in S02.
class SupplierV21Api {
  SupplierV21Api({
    required Uri origin,
    required SupplierAccessToken token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  })  : _origin = SupplierV21Config.parseOrigin(origin.toString()),
        _token = token,
        _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final Uri _origin;
  final SupplierAccessToken _token;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  bool _closed = false;

  void close() {
    _closed = true;
    if (_ownsClient) _client.close();
  }

  Future<SupplierV21Response> get(String path,
          {bool requiresAuth = true, Map<String, String>? query}) =>
      request('GET', path, requiresAuth: requiresAuth, query: query);

  Future<SupplierV21Response> request(
    String method,
    String path, {
    bool requiresAuth = true,
    Map<String, String>? query,
    Map<String, Object?>? body,
    String? idempotencyKey,
    String? ifMatch,
  }) async {
    if (_closed) {
      throw const SupplierV21Exception(SupplierV21Problem.configuration,
          code: 'CLIENT_CLOSED');
    }
    if (!{'GET', 'POST', 'PATCH', 'PUT', 'DELETE'}.contains(method)) {
      throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }
    // Only canonical V2.1 relative paths; disallow absolute origins and fragments.
    final endpoint = Uri.tryParse(path);
    if (endpoint == null ||
        !path.startsWith('/api/v2/') ||
        endpoint.hasScheme ||
        endpoint.hasAuthority ||
        endpoint.fragment.isNotEmpty ||
        endpoint.query.isNotEmpty ||
        path.contains('..') ||
        path.contains('//')) {
      throw ArgumentError.value(
          path, 'path', 'Use a canonical V2.1 path without query');
    }
    if (body != null && method == 'GET') {
      throw ArgumentError('GET cannot send a business mutation payload');
    }
    if (query != null && (method != 'GET' || query.length > 8 ||
        query.entries.any((entry) =>
            !RegExp(r'^[a-zA-Z][a-zA-Z0-9]{0,39}
    if (idempotencyKey != null &&
        (idempotencyKey.isEmpty ||
            idempotencyKey.length > 128 ||
            RegExp(r'[\r\n]').hasMatch(idempotencyKey))) {
      throw ArgumentError.value(
          idempotencyKey, 'idempotencyKey', 'Invalid idempotency key');
    }

    final token = requiresAuth ? await _token() : null;
    if (requiresAuth && (token == null || token.trim().isEmpty)) {
      throw const SupplierV21Exception(SupplierV21Problem.authentication,
          code: 'NO_SESSION');
    }
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (requiresAuth) headers['Authorization'] = 'Bearer ${token!.trim()}';
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    if (ifMatch != null) headers['If-Match'] = ifMatch;

    try {
      final uri = _origin.resolve(path);
      final resource = query == null || query.isEmpty
          ? uri
          : uri.replace(queryParameters: query);
      final response = await _client
          .send(http.Request(method, resource)
            ..headers.addAll(headers)
            ..body = body == null ? '' : jsonEncode(body))
          .timeout(timeout);
      final payload = await http.Response.fromStream(response).timeout(timeout);
      Object? decoded;
      try {
        decoded = jsonDecode(payload.body);
      } on FormatException {
        throw SupplierV21Exception(
          SupplierV21Problem.invalidResponse,
          statusCode: payload.statusCode,
          requestId: payload.headers['x-request-id'],
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw SupplierV21Exception(SupplierV21Problem.invalidResponse,
            statusCode: payload.statusCode);
      }
      final requestId = decoded['requestId'] is String
          ? decoded['requestId'] as String
          : payload.headers['x-request-id'];
      if (payload.statusCode >= 200 && payload.statusCode < 300) {
        if (!decoded.containsKey('data')) {
          throw SupplierV21Exception(SupplierV21Problem.invalidResponse,
              requestId: requestId);
        }
        return SupplierV21Response(data: decoded['data'], requestId: requestId);
      }
      final err = decoded['error'];
      final code = err is Map<String, dynamic> && err['code'] is String
          ? err['code'] as String
          : null;
      final problem = switch (payload.statusCode) {
        400 || 422 => SupplierV21Problem.validation,
        401 => SupplierV21Problem.authentication,
        403 => SupplierV21Problem.forbidden,
        404 => SupplierV21Problem.notFound,
        409 => SupplierV21Problem.conflict,
        428 => SupplierV21Problem.precondition,
        429 => SupplierV21Problem.rateLimited,
        >= 500 => SupplierV21Problem.server,
        _ => SupplierV21Problem.invalidResponse,
      };
      final seconds = int.tryParse(payload.headers['retry-after'] ?? '');
      throw SupplierV21Exception(
        problem,
        code: code,
        statusCode: payload.statusCode,
        requestId: requestId,
        retryAfter:
            seconds == null || seconds < 0 ? null : Duration(seconds: seconds),
      );
    } on TimeoutException {
      // A timed-out mutation MAY have committed. UI must re-read and retry
      // with the same intent/idempotency key, never show success or failure blindly.
      throw const SupplierV21Exception(SupplierV21Problem.network,
          code: 'TIMEOUT_UNKNOWN_OUTCOME');
    } on http.ClientException {
      throw const SupplierV21Exception(SupplierV21Problem.network,
          code: 'NETWORK_UNAVAILABLE');
    }
  }
}
).hasMatch(entry.key) ||
            entry.value.isEmpty || entry.value.length > 240 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(entry.value)))) {
      throw ArgumentError.value(query, 'query', 'Invalid V2.1 GET filters');
    }
    if (idempotencyKey != null &&
        (idempotencyKey.isEmpty ||
            idempotencyKey.length > 128 ||
            RegExp(r'[\r\n]').hasMatch(idempotencyKey))) {
      throw ArgumentError.value(
          idempotencyKey, 'idempotencyKey', 'Invalid idempotency key');
    }

    final token = requiresAuth ? await _token() : null;
    if (requiresAuth && (token == null || token.trim().isEmpty)) {
      throw const SupplierV21Exception(SupplierV21Problem.authentication,
          code: 'NO_SESSION');
    }
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (requiresAuth) headers['Authorization'] = 'Bearer ${token!.trim()}';
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    if (ifMatch != null) headers['If-Match'] = ifMatch;

    try {
      final response = await _client
          .send(http.Request(method, _origin.resolve(path))
            ..headers.addAll(headers)
            ..body = body == null ? '' : jsonEncode(body))
          .timeout(timeout);
      final payload = await http.Response.fromStream(response).timeout(timeout);
      Object? decoded;
      try {
        decoded = jsonDecode(payload.body);
      } on FormatException {
        throw SupplierV21Exception(
          SupplierV21Problem.invalidResponse,
          statusCode: payload.statusCode,
          requestId: payload.headers['x-request-id'],
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw SupplierV21Exception(SupplierV21Problem.invalidResponse,
            statusCode: payload.statusCode);
      }
      final requestId = decoded['requestId'] is String
          ? decoded['requestId'] as String
          : payload.headers['x-request-id'];
      if (payload.statusCode >= 200 && payload.statusCode < 300) {
        if (!decoded.containsKey('data')) {
          throw SupplierV21Exception(SupplierV21Problem.invalidResponse,
              requestId: requestId);
        }
        return SupplierV21Response(data: decoded['data'], requestId: requestId);
      }
      final err = decoded['error'];
      final code = err is Map<String, dynamic> && err['code'] is String
          ? err['code'] as String
          : null;
      final problem = switch (payload.statusCode) {
        400 || 422 => SupplierV21Problem.validation,
        401 => SupplierV21Problem.authentication,
        403 => SupplierV21Problem.forbidden,
        404 => SupplierV21Problem.notFound,
        409 => SupplierV21Problem.conflict,
        428 => SupplierV21Problem.precondition,
        429 => SupplierV21Problem.rateLimited,
        >= 500 => SupplierV21Problem.server,
        _ => SupplierV21Problem.invalidResponse,
      };
      final seconds = int.tryParse(payload.headers['retry-after'] ?? '');
      throw SupplierV21Exception(
        problem,
        code: code,
        statusCode: payload.statusCode,
        requestId: requestId,
        retryAfter:
            seconds == null || seconds < 0 ? null : Duration(seconds: seconds),
      );
    } on TimeoutException {
      // A timed-out mutation MAY have committed. UI must re-read and retry
      // with the same intent/idempotency key, never show success or failure blindly.
      throw const SupplierV21Exception(SupplierV21Problem.network,
          code: 'TIMEOUT_UNKNOWN_OUTCOME');
    } on http.ClientException {
      throw const SupplierV21Exception(SupplierV21Problem.network,
          code: 'NETWORK_UNAVAILABLE');
    }
  }
}
