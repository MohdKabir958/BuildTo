import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'supplier_models.dart';

typedef SupplierTokenProvider = Future<String?> Function();

/// Release URLs must be explicit owned HTTPS origins. Local emulator HTTP is
/// permitted in debug only. No environment default silently routes a V2.1
/// client to the old /api, Grozo or an unintended production backend.
class SupplierApiConfig {
  const SupplierApiConfig._(this.origin);
  final Uri origin;

  factory SupplierApiConfig.fromOrigin(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Set a valid V2.1 API origin');
    }
    final local = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' || uri.host == '10.0.2.2';
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' && local && !kReleaseMode)) {
      throw const FormatException('V2.1 API requires HTTPS');
    }
    return SupplierApiConfig._(uri.replace(path: '/', query: null, fragment: null));
  }

  factory SupplierApiConfig.fromEnvironment() {
    const origin = String.fromEnvironment('BUILDTO_V21_API_ORIGIN');
    return SupplierApiConfig.fromOrigin(origin);
  }
}

class SupplierApiResponse<T> {
  const SupplierApiResponse({required this.data, required this.requestId});
  final T data;
  final String requestId;
}

sealed class SupplierApiFailure implements Exception {
  const SupplierApiFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class SupplierSessionMissing extends SupplierApiFailure {
  const SupplierSessionMissing()
      : super('Sign in to your authorized supplier account');
}

class SupplierServerFailure extends SupplierApiFailure {
  const SupplierServerFailure({
    required this.status,
    required this.code,
    required super.message,
    required this.requestId,
  });
  final int status;
  final String code;
  final String? requestId;
}

class SupplierConnectionFailure extends SupplierApiFailure {
  const SupplierConnectionFailure()
      : super('Cannot reach the BuildTo API. Check your connection and retry.');
}

class SupplierProtocolFailure extends SupplierApiFailure {
  const SupplierProtocolFailure()
      : super('The BuildTo API returned an unexpected response.');
}

/// Read-only S01 transport. No privileged mutation endpoints are included
/// before the relevant module PR validates idempotency, money and RBAC.
class SupplierApiClient {
  SupplierApiClient({
    required SupplierApiConfig config,
    http.Client? client,
    SupplierTokenProvider? tokenProvider,
    this.timeout = const Duration(seconds: 12),
  }) : _config = config,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _tokenProvider = tokenProvider;

  final SupplierApiConfig _config;
  final http.Client _client;
  final bool _ownsClient;
  final SupplierTokenProvider? _tokenProvider;
  final Duration timeout;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<SupplierApiResponse<SupplierSystemInfo>> system() =>
      _get('/api/v2/system', SupplierSystemInfo.fromJson);

  Future<SupplierApiResponse<List<MaterialCategory>>> categories() =>
      _get('/api/v2/catalog/categories', (value) {
        if (value is! List) throw const FormatException('Expected category list');
        return List.unmodifiable(value.map(MaterialCategory.fromJson));
      });

  Future<SupplierApiResponse<SupplierIdentity>> identity() =>
      _get('/api/v2/me', SupplierIdentity.fromJson, authenticated: true);

  Future<SupplierApiResponse<SupplierAccess>> access(String supplierId) {
    if (!RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
        .hasMatch(supplierId)) {
      throw const FormatException('Invalid supplier UUID');
    }
    return _get('/api/v2/suppliers/' + supplierId + '/access',
        SupplierAccess.fromJson, authenticated: true);
  }

  Future<SupplierApiResponse<T>> _get<T>(
    String path,
    T Function(Object?) decode, {
    bool authenticated = false,
  }) async {
    if (!path.startsWith('/api/v2/') || path.contains('..') || path.contains('?')) {
      throw ArgumentError.value(path, 'path', 'Only exact V2.1 routes allowed');
    }
    final headers = <String, String>{'Accept': 'application/json'};
    if (authenticated) {
      final token = await _tokenProvider?.call();
      if (token == null || token.trim().isEmpty) {
        throw const SupplierSessionMissing();
      }
      headers['Authorization'] = 'Bearer ' + token;
    }

    late final http.Response response;
    try {
      response = await _client.get(_config.origin.resolve(path), headers: headers)
          .timeout(timeout);
    } on TimeoutException {
      throw const SupplierConnectionFailure();
    } on http.ClientException {
      throw const SupplierConnectionFailure();
    }

    Map<String, dynamic> body;
    try {
      final raw = jsonDecode(response.body);
      if (raw is! Map<String, dynamic>) throw const FormatException();
      body = raw;
    } on FormatException {
      throw const SupplierProtocolFailure();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'];
      if (error is! Map<String, dynamic> ||
          error['code'] is! String || error['message'] is! String) {
        throw const SupplierProtocolFailure();
      }
      throw SupplierServerFailure(
        status: response.statusCode,
        code: error['code'] as String,
        message: error['message'] as String,
        requestId: body['requestId'] is String
            ? body['requestId'] as String : null,
      );
    }

    try {
      if (body['requestId'] is! String || !body.containsKey('data')) {
        throw const FormatException();
      }
      return SupplierApiResponse<T>(
        data: decode(body['data']),
        requestId: body['requestId'] as String,
      );
    } on FormatException {
      throw const SupplierProtocolFailure();
    } on TypeError {
      throw const SupplierProtocolFailure();
    }
  }
}
