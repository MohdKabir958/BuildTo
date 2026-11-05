import 'package:flutter/material.dart';
import 'buildto_theme.dart';

/// Common design primitives for S01–S13. These have no legacy Grozo imports.
class BuildToBrandMark extends StatelessWidget {
  const BuildToBrandMark({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'BuildTo, Building Made Easy',
    child: ExcludeSemantics(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: compact ? 38 : 48,
          height: compact ? 38 : 48,
          decoration: BoxDecoration(
            color: BuildToPalette.navy,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(alignment: Alignment.center, children: [
            const Icon(Icons.apartment_rounded, color: BuildToPalette.white, size: 27),
            Positioned(right: 6, bottom: 6, child: Container(
              width: 6, height: 21, decoration: BoxDecoration(
                color: BuildToPalette.orange, borderRadius: BorderRadius.circular(2),
              ),
            )),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('BuildTo', style: TextStyle(
            fontSize: compact ? 23 : 28,
            fontWeight: FontWeight.w900,
            color: BuildToPalette.navyDeep,
            letterSpacing: -1.1,
            height: 1.0,
          )),
          const Text('Building Made Easy.', style: TextStyle(
            color: BuildToPalette.navy, fontSize: 10, fontWeight: FontWeight.w700,
          )),
        ]),
      ]),
    ),
  );
}

class BuildToCard extends StatelessWidget {
  const BuildToCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class BuildToPrimaryButton extends StatelessWidget {
  const BuildToPrimaryButton({super.key, required this.label, this.icon, this.onPressed, this.busy = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: busy ? null : onPressed,
    child: busy
      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: BuildToPalette.white))
      : Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Flexible(child: Text(label, maxLines: 2, textAlign: TextAlign.center)),
        ]),
  );
}

enum BuildToStatus { success, pending, warning, danger, neutral }

class BuildToStatusChip extends StatelessWidget {
  const BuildToStatusChip({super.key, required this.label, required this.status});
  final String label;
  final BuildToStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (status) {
      BuildToStatus.success => (BuildToPalette.successTint, BuildToPalette.success, Icons.check_circle_outline),
      BuildToStatus.pending => (BuildToPalette.sky, BuildToPalette.blue, Icons.schedule_rounded),
      BuildToStatus.warning => (BuildToPalette.warningTint, BuildToPalette.warning, Icons.info_outline),
      BuildToStatus.danger => (BuildToPalette.dangerTint, BuildToPalette.danger, Icons.error_outline),
      BuildToStatus.neutral => (BuildToPalette.canvas, BuildToPalette.muted, Icons.remove_circle_outline),
    };
    return Semantics(label: '$label status', child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(50)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: foreground, size: 15),
        const SizedBox(width: 5),
        Flexible(child: Text(label, maxLines: 2, style: TextStyle(
          color: foreground, fontWeight: FontWeight.w700, fontSize: 12,
        ))),
      ]),
    ));
  }
}

class BuildToSectionHeading extends StatelessWidget {
  const BuildToSectionHeading({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Container(height: 20, width: 4, decoration: BoxDecoration(
          color: BuildToPalette.orange, borderRadius: BorderRadius.circular(4),
        )),
        const SizedBox(width: 9),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
      ]),
      if (subtitle != null) ...[
        const SizedBox(height: 5),
        Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ],
  );
}

class BuildToStatePanel extends StatelessWidget {
  const BuildToStatePanel({
    super.key, required this.title, required this.message,
    this.icon = Icons.inventory_2_outlined, this.actionLabel, this.onAction,
  });
  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => BuildToCard(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64, height: 64,
        decoration: const BoxDecoration(color: BuildToPalette.sky, shape: BoxShape.circle),
        child: Icon(icon, size: 30, color: BuildToPalette.navy),
      ),
      const SizedBox(height: 14),
      Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      if (actionLabel != null && onAction != null) ...[
        const SizedBox(height: 16),
        BuildToPrimaryButton(label: actionLabel!, onPressed: onAction),
      ],
    ]),
  ));
}

class BuildToPageWidth extends StatelessWidget {
  const BuildToPageWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: BuildToSpace.maxContentWidth),
      child: child,
    ),
  );
}

/// Read-only skeleton never presents fake order or financial values.
class BuildToSkeleton extends StatefulWidget {
  const BuildToSkeleton({super.key, this.height = 72});
  final double height;
  @override
  State<BuildToSkeleton> createState() => _BuildToSkeletonState();
}

class _BuildToSkeletonState extends State<BuildToSkeleton> {
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: ExcludeSemantics(child: Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: BuildToPalette.outline.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(BuildToSpace.cardRadius),
      ),
    )),
  );
}
