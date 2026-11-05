import 'package:flutter/material.dart';

import 'buildto_tokens.dart';

/// Vector brand emblem: a compact building/letter-B motif in BuildTo navy and
/// amber. The source PDF has low-resolution logo artwork; replace the emblem
/// with the approved vector asset when it is supplied, without changing callers.
class BuildtoBrandMark extends StatelessWidget {
  const BuildtoBrandMark({super.key, this.size = 46});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Buildto brand mark',
        image: true,
        child: ExcludeSemantics(
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(painter: _BuildtoMarkPainter()),
          ),
        ),
      );
}

class _BuildtoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * .21)),
      Paint()..color = BuildtoPalette.navy,
    );
    final stroke = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * .20, s * .14, s * .13, s * .72),
        Radius.circular(s * .04),
      ),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * .36, s * .21, s * .16, s * .58),
        Radius.circular(s * .04),
      ),
      stroke,
    );
    final amber = Paint()..color = BuildtoPalette.amber;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * .57, s * .14, s * .19, s * .72),
        Radius.circular(s * .06),
      ),
      amber,
    );
    canvas.drawRect(
      Rect.fromLTWH(s * .76, s * .34, s * .075, s * .32),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _BuildtoMarkPainter oldDelegate) => false;
}

class BuildtoWordmark extends StatelessWidget {
  const BuildtoWordmark({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BuildtoBrandMark(size: compact ? 38 : 45),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Buildto', style: TextStyle(
              fontSize: compact ? 23 : 27,
              height: 1, fontWeight: FontWeight.w900,
              letterSpacing: -0.9, color: BuildtoPalette.navy)),
            const SizedBox(height: 3),
            const Text('Building Made Easy.', style: TextStyle(
              fontSize: 10, height: 1.1, fontWeight: FontWeight.w700,
              color: BuildtoPalette.navy)),
          ],
        ),
      ],
    );
  }
}

/// Constrains content for larger Android devices/tablets and always respects
/// the outer horizontal gutters. Children control their own vertical padding.
class BuildtoContent extends StatelessWidget {
  const BuildtoContent({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: BuildtoSpace.contentMaxWidth),
      child: child,
    ),
  );
}

class BuildtoPanel extends StatelessWidget {
  const BuildtoPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.background = BuildtoPalette.white,
    this.border = BuildtoPalette.border,
    this.radius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color background;
  final Color border;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
      boxShadow: [
        BoxShadow(
          color: BuildtoPalette.navyDeep.withValues(alpha: .035),
          blurRadius: 16, offset: const Offset(0, 4),
        ),
      ],
    ),
    padding: padding,
    child: child,
  );
}

class BuildtoSectionHeading extends StatelessWidget {
  const BuildtoSectionHeading({
    super.key, required this.title, this.subtitle, this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 4, height: 22, decoration: BoxDecoration(
          color: BuildtoPalette.amber,
          borderRadius: BorderRadius.circular(4),
        )),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: theme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class BuildtoStatusPill extends StatelessWidget {
  const BuildtoStatusPill({
    super.key, required this.label,
    this.tone = BuildtoTone.neutral, this.icon,
  });
  final String label;
  final BuildtoTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: const BorderRadius.all(BuildtoCorners.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, color: tone.foreground, size: 14),
            const SizedBox(width: 5),
          ],
          Text(label, style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w800,
            color: tone.foreground)),
        ]),
      ),
    ),
  );
}

class BuildtoPrimaryButton extends StatelessWidget {
  const BuildtoPrimaryButton({
    super.key, required this.label, required this.onPressed,
    this.icon, this.busy = false, this.expanded = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: busy ? null : onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy) ...[
            const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: BuildtoPalette.white)),
            const SizedBox(width: 10),
          ] else if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 9),
          ],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// Consistent interactive overview card for desktop/tablet/mobile. The action
/// must navigate or display genuine information; no inert decorative buttons.
class BuildtoActionTile extends StatelessWidget {
  const BuildtoActionTile({
    super.key, required this.icon, required this.title,
    required this.subtitle, required this.onTap, this.accent,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final highlight = accent ?? BuildtoPalette.navy;
    return Material(
      color: BuildtoPalette.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey('action-' + title),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: BuildtoPalette.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 44, width: 44,
                  decoration: BoxDecoration(
                    color: highlight.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: highlight),
                ),
                const SizedBox(height: 12),
                Text(title,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(subtitle,
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 11),
                const Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(Icons.arrow_forward_rounded,
                    size: 19, color: BuildtoPalette.navy),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BuildtoStatePanel extends StatelessWidget {
  const BuildtoStatePanel({
    super.key,
    required this.icon, required this.title, required this.message,
    this.actionLabel, this.onAction,
    this.tone = BuildtoTone.information,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final BuildtoTone tone;

  @override
  Widget build(BuildContext context) {
    return BuildtoPanel(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: tone.background,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 30, color: tone.foreground),
          ),
          const SizedBox(height: 17),
          Text(title, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 7),
          Text(message, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: BuildtoPalette.muted)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 19),
            BuildtoPrimaryButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

class BuildtoLoadingPanel extends StatelessWidget {
  const BuildtoLoadingPanel({super.key, this.label = 'Loading your workspace'});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true, label: label,
    child: BuildtoPanel(
      child: Row(children: [
        const SizedBox(width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    ),
  );
}

/// A compact wizard/tracking step indicator, based on reference PDF pp. 5/7.
/// Deliberately neutral: a step is not marked successful until business state
/// has been verified independently by its feature module.
class BuildtoStepIndicator extends StatelessWidget {
  const BuildtoStepIndicator({
    super.key, required this.labels, required this.currentStep,
  }) : assert(labels.length > 0), assert(currentStep >= 0);
  final List<String> labels;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) Expanded(child: Container(
            height: 2, color: i <= currentStep
              ? BuildtoPalette.navy : BuildtoPalette.border,
          )),
          Flexible(
            flex: 2,
            child: Column(children: [
              Container(
                width: 30, height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i <= currentStep ? BuildtoPalette.navy
                    : BuildtoPalette.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: BuildtoPalette.navy, width: 1.5),
                ),
                child: Text((i + 1).toString(), style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 12,
                  color: i <= currentStep ? Colors.white
                    : BuildtoPalette.navy)),
              ),
              const SizedBox(height: 6),
              Text(labels[i], maxLines: 2, textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: i <= currentStep ? BuildtoPalette.navy
                    : BuildtoPalette.muted)),
            ]),
          ),
        ],
      ],
    );
  }
}
