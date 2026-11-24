import 'dart:async';

import 'package:flutter/widgets.dart';

/// Shows the startup artwork while the app mounts and initializes underneath.
class SplyzoStartup extends StatefulWidget {
  const SplyzoStartup({super.key, required this.child});

  final Widget child;

  @override
  State<SplyzoStartup> createState() => _SplyzoStartupState();
}

class _SplyzoStartupState extends State<SplyzoStartup> {
  Timer? _minimum;
  bool _showSplash = true;

  void _onImageReady() {
    // Start the minimum after the image has been painted. Fast session checks
    // can finish before the artwork decodes on the first launch.
    if (!mounted) return;
    _minimum ??= Timer(const Duration(milliseconds: 300), () {
      setState(() => _showSplash = false);
    });
  }

  @override
  void dispose() {
    _minimum?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            excluding: _showSplash,
            child: IgnorePointer(
              ignoring: _showSplash,
              child: widget.child,
            ),
          ),
          if (_showSplash) SplyzoSplashScreen(onImageReady: _onImageReady),
        ],
      );
}

class SplyzoSplashScreen extends StatelessWidget {
  const SplyzoSplashScreen({super.key, this.onImageReady});

  final VoidCallback? onImageReady;

  void _afterPaint() {
    final callback = onImageReady;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Image.asset(
            'assets/brand/startup-splash.png',
            package: 'kraveo_ui',
            fit: BoxFit.contain,
            semanticLabel: 'Splyzo. Your Building Needs, Just Nearby.',
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame != null) _afterPaint();
              return child;
            },
            errorBuilder: (context, error, stackTrace) {
              // A missing asset should never trap the app on the splash.
              _afterPaint();
              return const SizedBox.expand();
            },
          ),
        ),
      );
}
