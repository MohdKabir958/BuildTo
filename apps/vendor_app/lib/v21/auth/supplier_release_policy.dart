import 'package:flutter/foundation.dart';
import '../api/supplier_v21_api.dart';

/// Prevent an accidentally staged, test-authenticated supplier APK/AAB from
/// being launched as a release. This complements but does NOT replace server
/// authorization, owned signing, independent security review or real UAT.
abstract final class SupplierReleasePolicy {
  static const configuredProductionHost =
      String.fromEnvironment('BUILDTO_V21_PRODUCTION_API_HOST');

  static void validate({
    bool release = kReleaseMode,
    String authMode =
        const String.fromEnvironment('AUTH_MODE', defaultValue: 'legacy'),
    String apiOrigin = SupplierV21Config.configuredOrigin,
    String productionHost = configuredProductionHost,
  }) {
    if (!release) return;
    if (authMode != 'clerk') {
      throw StateError('Release requires native production Clerk mode.');
    }
    final origin = SupplierV21Config.parseOrigin(apiOrigin, release: true);
    final expected = productionHost.trim().toLowerCase();
    if (expected.isEmpty ||
        !RegExp(r'^[a-z0-9](?:[a-z0-9.-]{1,251}[a-z0-9])?$')
            .hasMatch(expected) ||
        !expected.contains('.') ||
        expected.contains('..') ||
        origin.host.toLowerCase() != expected ||
        origin.scheme != 'https' ||
        origin.hasPort && origin.port != 443) {
      throw StateError('Release requires an explicit trusted HTTPS API host.');
    }
    final forbidden = expected == 'localhost' ||
        expected == '10.0.2.2' ||
        expected == '127.0.0.1' ||
        RegExp(r'^[0-9]+(?:\.[0-9]+){3}$').hasMatch(expected) ||
        expected.contains('staging') ||
        expected.contains('clerk.accounts.dev') ||
        expected.endsWith('.test') ||
        expected.endsWith('.invalid') ||
        expected.endsWith('.local') ||
        expected.endsWith('.example') ||
        expected.endsWith('.example.com');
    if (forbidden) {
      throw StateError('Test, staging and sample origins cannot ship.');
    }
  }
}
