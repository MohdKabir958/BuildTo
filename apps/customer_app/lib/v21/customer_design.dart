import 'package:flutter/material.dart';
import 'customer_api.dart';
import 'customer_session.dart';

const ink = Color(0xFF152A3A),
    accent = Color(0xFFF17436),
    paper = Color(0xFFF7F7F2),
    muted = Color(0xFF64747C),
    line = Color(0xFFE4E9E5),
    green = Color(0xFF23745D);
ThemeData customerTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ink,
    primary: ink,
    secondary: accent,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    fontFamily: 'packages/kraveo_ui/Jakarta',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'packages/kraveo_ui/Bricolage',
        fontSize: 34,
        fontWeight: FontWeight.w700,
        height: 1.13,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'packages/kraveo_ui/Bricolage',
        fontSize: 25,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            fontFamily: 'packages/kraveo_ui/Jakarta'),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: accent.withValues(alpha: .13),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
        selectedColor: accent.withValues(alpha: .13),
        backgroundColor: Colors.white,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(
            fontFamily: 'packages/kraveo_ui/Jakarta', color: ink)),
    dividerColor: line,
  );
}

class CustomerScope extends InheritedNotifier<CustomerSession> {
  const CustomerScope({
    super.key,
    required CustomerSession session,
    required super.child,
  }) : super(notifier: session);
  static CustomerSession of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<CustomerScope>()!.notifier!;
}

void push(BuildContext c, Widget page) =>
    Navigator.of(c).push(MaterialPageRoute(builder: (_) => page));
void notice(BuildContext c, String message) =>
    ScaffoldMessenger.of(c).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );

class ActionButton extends StatefulWidget {
  const ActionButton(
    this.text,
    this.action, {
    super.key,
    this.icon,
    this.tonal = false,
  });
  final String text;
  final Future<void> Function()? action;
  final IconData? icon;
  final bool tonal;
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 18),
        if (busy || widget.icon != null) const SizedBox(width: 10),
        Flexible(child: Text(busy ? 'Please wait…' : widget.text)),
      ],
    );
    Future<void> act() async {
      setState(() => busy = true);
      try {
        await widget.action!();
      } catch (e) {
        if (context.mounted) {
          notice(
            context,
            e is CustomerProblem
                ? e.message
                : e is FormatException
                    ? e.message
                    : 'Unable to complete this action. Please retry.',
          );
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    return widget.tonal
        ? OutlinedButton(
            onPressed: busy || widget.action == null ? null : act,
            child: child,
          )
        : FilledButton(
            onPressed: busy || widget.action == null ? null : act,
            child: child,
          );
  }
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = 20,
  });
  final Widget child;
  final Color color;
  final double padding;
  @override
  Widget build(BuildContext context) => Material(
        color: color,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: line)),
        child: Padding(padding: EdgeInsets.all(padding), child: child),
      );
}

class Section extends StatelessWidget {
  const Section(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (action != null)
              TextButton(onPressed: onTap, child: Text(action!)),
          ],
        ),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;
  Color get tone => ['CANCELLED', 'REJECTED', 'FAILED'].contains(status)
      ? const Color(0xFFAB382C)
      : [
          'APPROVED',
          'DELIVERED',
          'FULFILLED',
          'ACTIVE',
          'DEFAULT',
          'CAPTURED',
          'COD_VERIFIED',
          'PROCESSED',
          'ACCEPTED'
        ].contains(status)
          ? green
          : const Color(0xFF8A5B14);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label(status),
          style: TextStyle(
            color: tone,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.title,
    this.message, {
    super.key,
    this.icon = Icons.inventory_2_outlined,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: accent.withValues(alpha: .1),
              child: Icon(icon, size: 30, color: accent),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, height: 1.6),
            ),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      );
}

class RemotePage<T> extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.load,
    required this.builder,
    this.title,
  });
  final Future<T> Function() load;
  final Widget Function(T, VoidCallback) builder;
  final String? title;
  @override
  State<RemotePage<T>> createState() => _RemotePageState<T>();
}

class _RemotePageState<T> extends State<RemotePage<T>> {
  late Future<T> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  void reload() => setState(() => future = widget.load());
  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<T>(
      future: future,
      builder: (c, s) {
        if (s.hasError) {
          return ListView(
            children: [
              EmptyState(
                'Let’s try that again',
                s.error is CustomerProblem
                    ? (s.error as CustomerProblem).message
                    : 'We couldn’t load this page.',
                icon: Icons.wifi_off_rounded,
                action: ActionButton('Retry', () async => reload()),
              ),
            ],
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return RefreshIndicator(
          onRefresh: () async {
            reload();
            try {
              await future;
            } catch (_) {}
          },
          child: widget.builder(s.data as T, reload),
        );
      },
    );
    return widget.title == null
        ? content
        : Scaffold(
            appBar: AppBar(
              title: Text(widget.title!),
              actions: [
                IconButton(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: content,
                ),
              ),
            ),
          );
  }
}

class SignedIn extends StatelessWidget {
  const SignedIn({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final s = CustomerScope.of(context);
    return s.signedIn
        ? child
        : ListView(
            children: [
              EmptyState(
                'Your next project starts here',
                'Sign in to manage your cart, orders and delivery sites.',
                icon: Icons.person_outline_rounded,
                action: ActionButton(
                  'Sign in securely',
                  s.signIn,
                  icon: Icons.arrow_forward,
                ),
              ),
              if (s.authNotice != null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(s.authNotice!, textAlign: TextAlign.center),
                ),
            ],
          );
  }
}

class AmountRow extends StatelessWidget {
  const AmountRow(this.title, this.amount, {super.key, this.total = false});
  final String title;
  final Object? amount;
  final bool total;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: total ? ink : muted,
                  fontWeight: total ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
            ),
            Text(
              money(amount),
              style: TextStyle(
                fontSize: total ? 22 : 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

Widget totals(Data d) => Column(
      children: [
        AmountRow('Materials', d['subtotalPaise']),
        if ('${d['discountPaise'] ?? 0}' != '0')
          AmountRow('Discount', d['discountPaise']),
        AmountRow('Tax', d['taxPaise']),
        AmountRow('Delivery', d['deliveryPaise']),
        const Divider(),
        AmountRow('Total', d['totalPaise'], total: true),
      ],
    );
