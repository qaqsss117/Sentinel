import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'sentinel_assets.dart';
import 'sentinel_theme.dart';

class SentinelBackground extends StatelessWidget {
  const SentinelBackground({
    super.key,
    required this.child,
    this.decorated = false,
  });
  final Widget child;
  final bool decorated;

  @override
  Widget build(BuildContext context) {
    final colors = SentinelColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.backgroundTop, colors.backgroundBottom],
        ),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (decorated)
            Positioned(
              top: 48,
              right: -12,
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: .22,
                    child: Image.asset(
                      SentinelAssets.planet,
                      width: 150,
                      height: 150,
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Constrains content using the available pane width, not the display size.
class SentinelPage extends StatelessWidget {
  const SentinelPage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class SentinelPanel extends StatelessWidget {
  const SentinelPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class SentinelAnimation extends StatelessWidget {
  const SentinelAnimation({
    super.key,
    required this.asset,
    this.size = 160,
    this.animate = true,
    this.fallback = Icons.shield_outlined,
    this.repeat = true,
  });
  final String asset;
  final double size;
  final bool animate;
  final bool repeat;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final enabled =
        animate &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: enabled
            ? Lottie.asset(
                asset,
                animate: true,
                repeat: repeat,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  fallback,
                  size: size * .35,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : Icon(
                fallback,
                size: size * .35,
                color: Theme.of(context).colorScheme.primary,
              ),
      ),
    );
  }
}

class SentinelPageHeading extends StatelessWidget {
  const SentinelPageHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}
