import 'package:flutter/material.dart';
import '../brand_config.dart';

/// Raw brand palette. Uses the Splyzo navy-blue mark and orange location accent.
/// Screens should NOT use these directly - read semantic roles via `context.k`.
class KraveoPalette {
  KraveoPalette._();

  // Splyzo navy and blue ramp (brand = 800)
  static const g50 = Color(0xFFEFF5FF);
  static const g100 = Color(0xFFDCE9FF);
  static const g200 = Color(0xFFB8D2FF);
  static const g300 = Color(0xFF82B5F9);
  static const g400 = Color(0xFF4A8EDC);
  static const g500 = Color(0xFF216BC2);
  static const g600 = Color(0xFF1555A6);
  static const g700 = Color(0xFF103F83);
  static const g800 = Color(BrandConfig.primary);
  static const g900 = Color(0xFF082451);
  static const g950 = Color(0xFF041633);

  // Accent ramp (brand = 400 is configured from the Splyzo artwork)
  static const y100 = Color(0xFFFFF1E8);
  static const y200 = Color(0xFFFFD7C2);
  static const y300 = Color(0xFFFFB38A);
  static const y400 = Color(BrandConfig.accent);
  static const y500 = Color(0xFFDD4719);
  static const y700 = Color(0xFF9B2E12);

  // Cool neutrals (light)
  static const cream = Color(0xFFF5F8FC);
  static const paper = Color(0xFFFFFFFF);
  static const sand = Color(0xFFEDF2F8);
  static const line = Color(0xFFDCE5F0);
  static const ink = Color(0xFF14243B);
  static const ink2 = Color(0xFF46566F);
  static const ink3 = Color(0xFF64748B);

  // Navy neutrals (dark)
  static const nightBg = Color(0xFF070F1D);
  static const nightSurface = Color(0xFF101C2D);
  static const nightSurface2 = Color(0xFF182841);
  static const nightLine = Color(0xFF263B56);
  static const nightInk = Color(0xFFF3F7FD);
  static const nightInk2 = Color(0xFFB8C5D6);
  static const nightInk3 = Color(0xFF9FB0C5);

  // Semantic
  static const success = g500;
  static const warning = Color(0xFFF15A24);
  static const danger = Color(0xFFE5484D);
  static const info = Color(0xFF3B82F6);
}

/// One status colour language shared by every Splyzo surface (apps + dashboard).
enum KStatus { placed, accepted, preparing, ready, pickedUp, atGate, delivered, cancelled }

extension KStatusX on KStatus {
  Color get color => switch (this) {
        KStatus.placed => const Color(0xFFF5A524),
        KStatus.accepted => const Color(0xFF14B8A6),
        KStatus.preparing => const Color(0xFFF97316),
        KStatus.ready => const Color(0xFF84CC16),
        KStatus.pickedUp => const Color(0xFF3B82F6),
        KStatus.atGate => const Color(0xFF8B5CF6),
        KStatus.delivered => const Color(0xFF16A34A),
        KStatus.cancelled => const Color(0xFFE5484D),
      };

  String get label => switch (this) {
        KStatus.placed => 'Placed',
        KStatus.accepted => 'Accepted',
        KStatus.preparing => 'Preparing',
        KStatus.ready => 'Ready',
        KStatus.pickedUp => 'On the way',
        KStatus.atGate => 'At your door',
        KStatus.delivered => 'Delivered',
        KStatus.cancelled => 'Cancelled',
      };

  /// Tolerant parser for backend strings (PLACED, READY_FOR_PICKUP, ARRIVED_AT_GATE ...).
  static KStatus parse(String raw) {
    final s = raw.toUpperCase().replaceAll(' ', '_');
    if (s.contains('CANCEL')) return KStatus.cancelled;
    if (s.contains('DELIVERED')) return KStatus.delivered;
    if (s.contains('GATE')) return KStatus.atGate;
    if (s.contains('PICKED') || s.contains('TRANSIT') || s.contains('WAY')) return KStatus.pickedUp;
    if (s.contains('READY')) return KStatus.ready;
    if (s.contains('PREPAR')) return KStatus.preparing;
    if (s.contains('ACCEPT') || s.contains('ASSIGN')) return KStatus.accepted;
    return KStatus.placed;
  }
}
