import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:kraveo_ui/kraveo_ui.dart' show GrozoAuthConfig;
import 'customer_api.dart';
import 'customer_session.dart';
import 'customer_design.dart';
import 'customer_catalog.dart';
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
          api: CustomerApi(origin: origin, token: auth.token),
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
              const CustomerHome(),
              const CustomerHome(categoriesOnly: true),
              const CartPage(embedded: true),
              const OrdersPage(),
              const ProfilePage(),
            ][tab],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Categories',
            ),
            NavigationDestination(
              icon: Icon(Icons.shopping_bag_outlined),
              selectedIcon: Icon(Icons.shopping_bag),
              label: 'Cart',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      );
}
