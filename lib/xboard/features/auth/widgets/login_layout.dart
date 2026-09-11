import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';

/// Arranges the same brand and form widgets for the available window size.
class LoginLayout extends StatelessWidget {
  const LoginLayout({
    super.key,
    required this.title,
    required this.website,
    required this.child,
  });

  final String title;
  final String website;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, viewport) {
          final isWide = viewport.maxWidth >= 760;
          final padding = viewport.maxWidth >= 1100 ? 40.0 : 24.0;
          final verticalPadding = viewport.maxHeight < 600 ? 16.0 : 32.0;
          final brandHeight = (viewport.maxHeight - verticalPadding * 2).clamp(
            360.0,
            560.0,
          );

          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: padding,
                vertical: verticalPadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 1080 : 420),
                child: LayoutBuilder(
                  builder: (context, content) {
                    final gap = isWide ? 40.0 : 32.0;
                    final brandWidth = (content.maxWidth - gap) * 0.46;

                    // Keep the widget tree stable when changing direction so
                    // focus, validation and editing state survive resizing.
                    return Flex(
                      direction: isWide ? Axis.horizontal : Axis.vertical,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: isWide ? brandWidth : content.maxWidth,
                          child: _LoginBrand(
                            key: const ValueKey('login-brand'),
                            title: title,
                            website: website,
                            isWide: isWide,
                            minHeight: isWide ? brandHeight : 0,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? gap : 0,
                          height: isWide ? 0 : gap,
                        ),
                        SizedBox(
                          width: isWide
                              ? content.maxWidth - brandWidth - gap
                              : content.maxWidth,
                          child: Align(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand({
    super.key,
    required this.title,
    required this.website,
    required this.isWide,
    required this.minHeight,
  });

  final String title;
  final String website;
  final bool isWide;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = isWide ? colors.onPrimaryContainer : colors.onSurface;

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: isWide ? const EdgeInsets.all(32) : EdgeInsets.zero,
      decoration: isWide
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primaryContainer, colors.surfaceContainerLow],
              ),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.4),
              ),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: isWide
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/icon.png',
            width: isWide ? 80 : 56,
            height: isWide ? 80 : 56,
            excludeFromSemantics: true,
          ),
          SizedBox(height: isWide ? 40 : 16),
          Text(
            title,
            textAlign: isWide ? TextAlign.start : TextAlign.center,
            style: textTheme.headlineLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isWide) ...[
            const SizedBox(height: 16),
            Text(
              appLocalizations.xboardEnjoyFastNetworkExperience,
              style: textTheme.titleMedium?.copyWith(color: foreground),
            ),
          ],
          SizedBox(height: isWide ? 40 : 8),
          Text(
            website,
            textAlign: isWide ? TextAlign.start : TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
