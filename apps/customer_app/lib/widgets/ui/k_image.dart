import 'package:flutter/material.dart';
import 'package:kraveo_ui/kraveo_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Network or asset image with a calm placeholder, fade-in and a branded fallback.
/// Fills whatever box it is given.
class KImage extends StatelessWidget {
  const KImage(this.url,
      {super.key,
      this.fit = BoxFit.cover,
      this.grayscale = false,
      this.fallbackIcon = LucideIcons.package});

  final String url;
  final BoxFit fit;
  final bool grayscale;
  final IconData fallbackIcon;

  static const int maxDecodePixels = 1200;

  static int decodeSize(
      double logicalWidth, double logicalHeight, double devicePixelRatio) {
    final longest = [logicalWidth, logicalHeight]
        .where((v) => v.isFinite && v > 0)
        .fold<double>(0, (a, b) => b > a ? b : a);
    final px = longest *
        (devicePixelRatio.isFinite && devicePixelRatio > 0
            ? devicePixelRatio
            : 1);
    if (px <= 0) return maxDecodePixels;
    return ((px / 100).ceil() * 100).clamp(100, maxDecodePixels);
  }

  static const _grayMatrix = <double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    Widget fallback() => ColoredBox(
          color: k.brandSoft,
          child: Center(
              child: Icon(fallbackIcon,
                  size: 30, color: k.brand.withValues(alpha: 0.4))),
        );

    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      return fallback();
    }

    final bool isAsset = cleanUrl.startsWith('assets/') || cleanUrl.startsWith('packages/');
    final ImageProvider rawProvider = isAsset
        ? AssetImage(cleanUrl)
        : NetworkImage(cleanUrl) as ImageProvider;

    Widget body = LayoutBuilder(builder: (context, constraints) {
      final screen = MediaQuery.sizeOf(context);
      final size = decodeSize(
        constraints.hasBoundedWidth ? constraints.maxWidth : screen.width,
        constraints.hasBoundedHeight ? constraints.maxHeight : screen.width,
        MediaQuery.devicePixelRatioOf(context),
      );
      return Stack(fit: StackFit.expand, children: [
        ColoredBox(color: k.surfaceAlt),
        Image(
          image: ResizeImage(rawProvider,
              width: size, height: size, policy: ResizeImagePolicy.fit),
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          frameBuilder: (context, child, frame, sync) {
            if (sync) return child;
            return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : KMotion.slow,
                curve: KMotion.emphasized,
                child: child);
          },
          errorBuilder: (context, error, stack) => fallback(),
        ),
      ]);
    });

    if (grayscale) {
      body = ColorFiltered(
          colorFilter: const ColorFilter.matrix(_grayMatrix), child: body);
    }
    return body;
  }
}
