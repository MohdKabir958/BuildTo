import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kraveo_ui/kraveo_ui.dart' show GrozoAuthConfig;
import '../api/supplier_v21_api.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import '../screens/supplier_shell.dart';
import 'supplier_auth_controller.dart';
import 'supplier_clerk_port.dart';
import 'supplier_release_policy.dart';
import '../onboarding/supplier_onboarding_flow.dart';

/// Opt-in staging experience. Android's official native Clerk UI authenticates,
/// but only /me and /suppliers/:id/access can unlock a supplier workspace.
class BuildToSupplierV21App extends StatefulWidget {
  const BuildToSupplierV21App({super.key, this.controller});
  final SupplierAuthController? controller;

  @override
  State<BuildToSupplierV21App> createState() => _BuildToSupplierV21AppState();
}

class _BuildToSupplierV21AppState extends State<BuildToSupplierV21App>
    with WidgetsBindingObserver {
  SupplierAuthController? _controller;
  String? _setupFailure;
  bool _ownsController = false;
  bool _applicationsOpen = false;
  bool _returnHomeOnApproval = false;
  bool _approvalDepartureStarted = false;

  bool _departAfterApproval() {
    final controller = _controller;
    if (!_returnHomeOnApproval ||
        _approvalDepartureStarted ||
        controller == null) {
      return false;
    }
    _approvalDepartureStarted = true;
    unawaited(controller.refresh());
    return true;
  }

  void _initController() {
    if (widget.controller != null) {
      _controller = widget.controller;
    } else {
      try {
        if (!GrozoAuthConfig.usesClerk) {
          throw StateError('Native Clerk mode must be enabled.');
        }
        SupplierReleasePolicy.validate(authMode: GrozoAuthConfig.mode);
        final clerk = NativeSupplierClerkPort();
        final api = SupplierV21Api(
          origin: SupplierV21Config.origin,
          token: () => clerk.token(),
        );
        _controller = SupplierAuthController(clerk: clerk, api: api);
        _ownsController = true;
      } catch (_) {
        _setupFailure = 'Secure supplier sign-in is not configured. '
            'Check the Splyzo API origin and Android Clerk settings.';
      }
    }
    if (_controller != null) unawaited(_controller!.start());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final controller = _controller;
      if (controller != null &&
          controller.stage != SupplierAccessStage.signedOut &&
          controller.stage != SupplierAccessStage.starting &&
          controller.stage != SupplierAccessStage.misconfigured) {
        // Re-evaluate membership and suspension whenever the user returns.
        unawaited(controller.refresh());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Splyzo Supplier',
        debugShowCheckedModeBanner: false,
        theme: BuildToTheme.light(),
        home: _setupFailure == null
            ? AnimatedBuilder(
                animation: _controller!,
                builder: (context, _) {
                  final controller = _controller!;
                  final canView = controller.sessionKey != null &&
                      (controller.stage == SupplierAccessStage.authorized ||
                          controller.stage == SupplierAccessStage.noSupplier);
                  final homeReady =
                      controller.stage == SupplierAccessStage.authorized &&
                          controller.activeSupplier != null;
                  if (_applicationsOpen &&
                      _returnHomeOnApproval &&
                      homeReady) {
                    _applicationsOpen = false;
                    _returnHomeOnApproval = false;
                  }
                  if (_applicationsOpen && canView) {
                    return SupplierOnboardingFlow(
                      key: ValueKey(controller.sessionKey),
                      controller: controller,
                      api: controller.applications,
                      leaveWhenApproved: _returnHomeOnApproval,
                      onApproved: _departAfterApproval,
                      onClose: () => setState(() {
                        _applicationsOpen = false;
                        _returnHomeOnApproval = false;
                        _approvalDepartureStarted = false;
                      }),
                    );
                  }
                  return _SupplierAccessView(
                    controller: controller,
                    openApplications: () => setState(() {
                      _returnHomeOnApproval = controller.stage !=
                          SupplierAccessStage.authorized;
                      _approvalDepartureStarted = false;
                      _applicationsOpen = true;
                    }),
                  );
                },
              )
            : _AccessScaffold(
                title: 'Secure setup required',
                subtitle: _setupFailure!,
                icon: Icons.admin_panel_settings_outlined,
                actions: [
                  _AccessAction(
                    'Retry setup',
                    Icons.refresh_rounded,
                    () => setState(() {
                      _setupFailure = null;
                      _initController();
                    }),
                  ),
                ],
              ),
      );
}

class _SupplierAccessView extends StatelessWidget {
  const _SupplierAccessView({
    required this.controller,
    required this.openApplications,
  });
  final SupplierAuthController controller;
  final VoidCallback openApplications;

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    final membership = controller.activeSupplier;
    if (stage == SupplierAccessStage.authorized && membership != null) {
      return BuildToSupplierShell(
        key: ValueKey(
          '${controller.sessionKey}|${membership.supplierId}|${membership.role.name}',
        ),
        verifiedSupplier: membership,
        dashboardRepository: controller.dashboardRepository,
        catalogRepository: controller.catalogRepository,
        inventoryRepository: controller.inventoryRepository,
        deliveryRepository: controller.deliveryRepository,
        rfqRepository: controller.rfqRepository,
        ordersRepository: controller.ordersRepository,
        shipmentsRepository: controller.shipmentsRepository,
        careRepository: controller.careRepository,
        financeRepository: controller.financeRepository,
        displayName: controller.account?.displayName,
        onSwitchSupplier: controller.showSupplierChooser,
        onSignOut: controller.signOut,
        onRefresh: controller.refresh,
        onOpenApplications: openApplications,
        canSwitchSupplier: (controller.account?.suppliers.length ?? 0) > 1,
      );
    }
    if (stage == SupplierAccessStage.chooseSupplier &&
        controller.account != null) {
      return _SupplierPicker(controller: controller);
    }
    if (stage == SupplierAccessStage.checking) {
      return _AccessScaffold(
        title: 'Verifying your supplier account',
        subtitle: 'Checking your Clerk session and current Splyzo permissions.',
        icon: Icons.shield_outlined,
        loading: true,
        actions: [
          _AccessAction(
            'Cancel and return to welcome',
            Icons.arrow_back_rounded,
            controller.signOut,
            outlined: true,
          ),
        ],
        busy: controller.busy,
      );
    }

    final (title, description, icon) = switch (stage) {
      SupplierAccessStage.signedOut || SupplierAccessStage.starting => (
          'Welcome to Splyzo Supplier',
          'Already have an account? Sign in. New supplier? Create an '
              'account to register your business and track approval.',
          Icons.storefront_outlined,
        ),
      SupplierAccessStage.noSupplier => (
          'Your account is in review',
          'Your registration is awaiting admin approval. Once accepted by Splyzo administration, your supplier workspace will activate immediately.',
          Icons.domain_verification_outlined,
        ),
      SupplierAccessStage.accessDenied => (
          'Supplier access unavailable',
          'The backend denied or changed your supplier membership. '
              'No protected business data is shown.',
          Icons.lock_person_outlined,
        ),
      SupplierAccessStage.sessionExpired => (
          'Session expired',
          'Please sign in again to continue securely.',
          Icons.lock_clock_outlined,
        ),
      SupplierAccessStage.unavailable => (
          'Cannot verify your access',
          'The connection or identity provider is unavailable. '
              'We will not use cached roles while offline.',
          Icons.wifi_off_outlined,
        ),
      SupplierAccessStage.misconfigured => (
          'Connection setup needs attention',
          'Your supplier account is protected. Retry the connection '
              'or return to sign in; no business data has been unlocked.',
          Icons.settings_suggest_outlined,
        ),
      _ => (
          'Access unavailable',
          'Your supplier membership needs verification.',
          Icons.shield_outlined,
        ),
    };

    return _AccessScaffold(
      title: title,
      subtitle: description,
      icon: icon,
      message: controller.notice,
      email: controller.signedInEmail,
      actions: switch (stage) {
        SupplierAccessStage.signedOut ||
        SupplierAccessStage.starting ||
        SupplierAccessStage.sessionExpired =>
          [
            _AccessAction(
              'Sign in to my account',
              Icons.login_rounded,
              () => controller.authenticate(mode: 'signIn'),
            ),
            _AccessAction(
              'Create a new account',
              Icons.person_add_alt_1_outlined,
              () => controller.authenticate(mode: 'signUp'),
              outlined: true,
            ),
            if (controller.notice != null)
              _AccessAction(
                'Retry Clerk connection',
                Icons.refresh_rounded,
                controller.retryClerkInitialization,
                outlined: true,
              ),
          ],
        SupplierAccessStage.noSupplier => [
            _AccessAction(
              'Open supplier applications',
              Icons.add_business_rounded,
              openApplications,
            ),
            _AccessAction(
              'Recheck admin approval',
              Icons.refresh_rounded,
              controller.refresh,
            ),
            _AccessAction(
              'Sign out / change account',
              Icons.logout_rounded,
              controller.signOut,
              outlined: true,
            ),
          ],
        SupplierAccessStage.accessDenied ||
        SupplierAccessStage.unavailable ||
        SupplierAccessStage.misconfigured =>
          [
            _AccessAction(
              'Retry secure verification',
              Icons.refresh_rounded,
              controller.refresh,
            ),
            _AccessAction(
              'Sign out / Back to welcome',
              Icons.arrow_back_rounded,
              controller.signOut,
              outlined: true,
            ),
          ],
        _ => [],
      },
      busy: controller.busy,
    );
  }
}

class _AccessAction {
  const _AccessAction(
    this.label,
    this.icon,
    this.callback, {
    this.outlined = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback callback;
  final bool outlined;
}

class _AccessScaffold extends StatelessWidget {
  const _AccessScaffold({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.message,
    this.email,
    this.actions = const [],
    this.loading = false,
    this.busy = false,
  });
  final String title, subtitle;
  final IconData icon;
  final String? message, email;
  final List<_AccessAction> actions;
  final bool loading, busy;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: BuildToPageWidth(
            child: Center(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: BuildToBrandMark(),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: 80,
                    height: 80,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BuildToPalette.sky,
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: Icon(icon, color: BuildToPalette.navy, size: 42),
                  ),
                  const SizedBox(height: 24),
                  Text(title,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  if (email != null && email!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Clerk account: ${email!}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (message != null && message!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    BuildToCard(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: BuildToPalette.warning,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(message!)),
                        ],
                      ),
                    ),
                  ],
                  if (loading) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 18),
                    const BuildToSkeleton(height: 72),
                  ],
                  if (busy && !loading) ...[
                    const SizedBox(height: 18),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(
                      'Connecting securely. You can retry if this fails.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    for (final action in actions) ...[
                      SizedBox(
                        width: double.infinity,
                        child: action.outlined
                            ? OutlinedButton.icon(
                                onPressed: busy ? null : action.callback,
                                icon: Icon(action.icon),
                                label: Text(action.label),
                              )
                            : BuildToPrimaryButton(
                                label: action.label,
                                icon: action.icon,
                                busy: busy,
                                onPressed: action.callback,
                              ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Splyzo • Secure supplier workspace',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SupplierPicker extends StatelessWidget {
  const _SupplierPicker({required this.controller});
  final SupplierAuthController controller;

  @override
  Widget build(BuildContext context) {
    final suppliers = controller.account!.suppliers;
    return Scaffold(
      body: SafeArea(
        child: BuildToPageWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              const BuildToBrandMark(compact: true),
              const SizedBox(height: 26),
              const BuildToSectionHeading(
                title: 'Choose your supplier',
                subtitle: 'Select a business for this session. '
                    'Every selection is verified with the backend.',
              ),
              const SizedBox(height: 18),
              for (final member in suppliers) ...[
                BuildToCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    minVerticalPadding: 8,
                    leading: const CircleAvatar(
                      backgroundColor: BuildToPalette.sky,
                      foregroundColor: BuildToPalette.navy,
                      child: Icon(Icons.factory_outlined),
                    ),
                    title: Text(
                      'Supplier • ${member.supplierId.substring(member.supplierId.length - 8)}',
                    ),
                    subtitle: Text('Role: ${member.role.name.toUpperCase()}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: controller.busy
                        ? null
                        : () => controller.selectSupplier(member.supplierId),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Supplier business names are not included in the /me response. '
                'IDs are shown instead of invented names.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 26),
              OutlinedButton.icon(
                onPressed: controller.signOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out / change Clerk account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
