import 'package:flutter/material.dart';

import 'design/buildto_theme.dart';
import 'ui/supplier_shell.dart';

/// Opt-in S01 UI shell. No claims of authenticated supplier access until S02.
/// Production legacy vendor flows remain unchanged by default.
class SupplierFoundationApp extends StatelessWidget {
  const SupplierFoundationApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Buildto Supplier',
    debugShowCheckedModeBanner: false,
    theme: BuildtoSupplierTheme.light,
    home: const SupplierShell(),
  );
}
