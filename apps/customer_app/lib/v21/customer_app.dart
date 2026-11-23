import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:kraveo_ui/kraveo_ui.dart' show GrozoAuthConfig;

import 'customer_api.dart';
import 'customer_session.dart';
import 'customer_design.dart';
import 'customer_catalog.dart';
import 'customer_reference_home.dart';
import 'customer_checkout.dart';
import 'customer_orders.dart';
import 'customer_workspace.dart';

class SplyzoCustomerApp extends StatefulWidget {
  const SplyzoCustomerApp({super.key, this.session});
  final CustomerSession? session;
  @override
  State<SplyzoCustomerApp> createState() => _SplyzoCustomerAppState();
}

class _SplyzoCustomerAppState extends State<SplyzoCustomerApp>
    with WidgetsBindingObserver {
  CustomerSession? session;
  String? setupError;
  int epoch = 0;
  GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      if (widget.session != null) {
        session = widget.session;
      } else {
        const configured = String.fromEnvironment(
          'BUILDTO_V21_API_BASE_URL',
          defaultValue:
              kReleaseMode ? '' : 'https://buildto-v21-staging.onrender.com',
        );
        final origin = CustomerApi.parseOrigin(configured);
        if (kReleaseMode) {
          const trusted = String.fromEnvironment(
            'BUILDTO_V21_PRODUCTION_API_HOST',
          );
          if (GrozoAuthConfig.mode != 'clerk' ||
              trusted.isEmpty ||
              trusted != origin.host ||
              origin.host.contains('staging') ||
              origin.host == 'localhost' ||
              RegExp(r'^\d+\.').hasMatch(origin.host) ||
              [
                '.test',
                '.local',
                '.invalid',
                '.example',
              ].any(origin.host.endsWith)) {
            throw const CustomerProblem(
              'This build is not configured for production.',
            );
          }
        }
        final auth = NativeCustomerIdentity();
        session = CustomerSession(
          api: CustomerApi(
            origin: origin,
            token: auth.token,
            refreshToken: () => auth.token(forceRefresh: true),
          ),
          auth: auth,
        );
      }
      session!.addListener(changed);
      unawaited(session!.start());
    } catch (_) {
      setupError =
          'Secure customer services are not configured for this build.';
    }
  }

  void changed() {
    if (!mounted) return;
    if (epoch != session!.epoch) {
      setState(() {
        epoch = session!.epoch;
        nav = GlobalKey<NavigatorState>();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && session?.signedIn == true) {
      unawaited(session!.restore());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session?.removeListener(changed);
    if (widget.session == null) session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'Splyzo',
      theme: customerTheme(),
      debugShowCheckedModeBanner: false,
      navigatorKey: nav,
      home: session == null
          ? Scaffold(
              body: SafeArea(
                child: EmptyState(
                  'Let’s get connected',
                  setupError ?? 'Please check the app configuration.',
                ),
              ),
            )
          : CustomerShell(key: ValueKey(epoch)),
    );
    return session == null ? app : CustomerScope(session: session!, child: app);
  }
}

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});
  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int tab = 0;
  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: KeyedSubtree(
            key: ValueKey(tab),
            child: [
              const SplyzoReferenceHome(),
              const CustomerHome(categoriesOnly: true),
              CartPage(embedded: true, onBrowse: () => setState(() => tab = 0)),
              const OrdersPage(),
              const ProfilePage(),
            ][tab],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            height: 67,
            padding: const EdgeInsets.only(top: 7, bottom: 2),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE9EDF5))),
              boxShadow: [
                BoxShadow(
                  color: Color(0x100B214E),
                  blurRadius: 9,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                _referenceTab(
                    0, Icons.home_outlined, Icons.home_rounded, 'Home'),
                _referenceTab(
                  1,
                  Icons.grid_view_outlined,
                  Icons.grid_view_rounded,
                  'Categories',
                ),
                _referenceTab(
                  2,
                  Icons.shopping_cart_outlined,
                  Icons.shopping_cart_rounded,
                  'Cart',
                ),
                _referenceTab(
                  3,
                  Icons.storefront_outlined,
                  Icons.storefront_rounded,
                  'Orders',
                ),
                _referenceTab(
                  4,
                  Icons.person_outline_rounded,
                  Icons.person_rounded,
                  'Profile',
                ),
              ],
            ),
          ),
        ),
      );
  Widget _referenceTab(
    int index,
    IconData idleIcon,
    IconData selectedIcon,
    String label,
  ) {
    final chosen = tab == index;
    final color =
        chosen ? SplyzoReferenceColors.orange : SplyzoReferenceColors.navy;
    return Expanded(
      child: Semantics(
        selected: chosen,
        button: true,
        label: label,
        child: InkWell(
          onTap: () => setState(() => tab = index),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(chosen ? selectedIcon : idleIcon, color: color, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: chosen ? FontWeight.w800 : FontWeight.w500,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                height: 2.5,
                width: 42,
                decoration: BoxDecoration(
                  color: chosen
                      ? SplyzoReferenceColors.orange
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
