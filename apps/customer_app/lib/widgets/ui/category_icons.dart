import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Icons for construction material category keys.
const Map<String, IconData> kCategoryIconKeys = {
  'all': LucideIcons.layoutGrid,
  'cement': LucideIcons.package,
  'steel': LucideIcons.shieldCheck,
  'tmt': LucideIcons.shieldCheck,
  'tmt_bars': LucideIcons.shieldCheck,
  'bricks': LucideIcons.store,
  'blocks': LucideIcons.store,
  'sand': LucideIcons.landmark,
  'aggregates': LucideIcons.landmark,
  'plumbing': LucideIcons.lightbulb,
  'pipes': LucideIcons.lightbulb,
  'electrical': LucideIcons.zap,
  'electricals': LucideIcons.zap,
  'wiring': LucideIcons.zap,
  'paint': LucideIcons.sprayCan,
  'paints': LucideIcons.sprayCan,
  'finishes': LucideIcons.sprayCan,
  'hardware': LucideIcons.settings,
  'tools': LucideIcons.settings,
  'roofing': LucideIcons.house,
  'tiles': LucideIcons.house,
  'wood': LucideIcons.sparkles,
  'timber': LucideIcons.sparkles,
  'store': LucideIcons.store,
  'materials': LucideIcons.package,
};

/// The keyword fallback used for category chips and tabs.
IconData categoryIconForLabel(String label) {
  final l = label.toLowerCase();
  if (l == 'all') return LucideIcons.layoutGrid;
  if (l.contains('cement')) return LucideIcons.package;
  if (l.contains('steel') || l.contains('tmt')) return LucideIcons.shieldCheck;
  if (l.contains('brick') || l.contains('block')) return LucideIcons.store;
  if (l.contains('sand') || l.contains('aggregate')) return LucideIcons.landmark;
  if (l.contains('plumb') || l.contains('pipe')) return LucideIcons.lightbulb;
  if (l.contains('electric') || l.contains('wire')) return LucideIcons.zap;
  if (l.contains('paint') || l.contains('finish')) return LucideIcons.sprayCan;
  if (l.contains('hard') || l.contains('tool')) return LucideIcons.settings;
  if (l.contains('roof') || l.contains('tile')) return LucideIcons.house;
  if (l.contains('wood') || l.contains('timber')) return LucideIcons.sparkles;
  return LucideIcons.package;
}

/// Server icon [key] -> icon; an unknown or missing key falls back to the keyword table on [label],
/// which ends in the construction package icon.
IconData categoryIcon({String? key, required String label}) {
  final icon = key == null ? null : kCategoryIconKeys[key.trim().toLowerCase()];
  return icon ?? categoryIconForLabel(label);
}
