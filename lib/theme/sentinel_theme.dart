import 'package:flutter/material.dart';

/// Brand surfaces are independent of the user's chosen accent color.
@immutable
class SentinelColors extends ThemeExtension<SentinelColors> {
  const SentinelColors({
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.glow,
    required this.success,
    required this.warning,
  });

  final Color backgroundTop;
  final Color backgroundBottom;
  final Color glow;
  final Color success;
  final Color warning;

  static SentinelColors of(BuildContext context) =>
      Theme.of(context).extension<SentinelColors>() ??
      forBrightness(Theme.of(context).brightness);

  static SentinelColors forBrightness(
    Brightness brightness, {
    bool pureBlack = false,
  }) {
    final dark = brightness == Brightness.dark;
    return SentinelColors(
      backgroundTop: pureBlack
          ? Colors.black
          : Color(dark ? 0xFF311F52 : 0xFFF7F5FC),
      backgroundBottom: pureBlack
          ? Colors.black
          : Color(dark ? 0xFF1B0B50 : 0xFFEEEAFA),
      glow: const Color(0xFFD071F9),
      success: Color(dark ? 0xFF72E0BB : 0xFF18795C),
      warning: Color(dark ? 0xFFFFCE83 : 0xFF8B5400),
    );
  }

  @override
  SentinelColors copyWith({
    Color? backgroundTop,
    Color? backgroundBottom,
    Color? glow,
    Color? success,
    Color? warning,
  }) => SentinelColors(
    backgroundTop: backgroundTop ?? this.backgroundTop,
    backgroundBottom: backgroundBottom ?? this.backgroundBottom,
    glow: glow ?? this.glow,
    success: success ?? this.success,
    warning: warning ?? this.warning,
  );

  @override
  SentinelColors lerp(SentinelColors? other, double t) => other == null
      ? this
      : SentinelColors(
          backgroundTop: Color.lerp(backgroundTop, other.backgroundTop, t)!,
          backgroundBottom: Color.lerp(
            backgroundBottom,
            other.backgroundBottom,
            t,
          )!,
          glow: Color.lerp(glow, other.glow, t)!,
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}

abstract final class SentinelTheme {
  static const primary = Color(0xFF8B72F8);
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF6551C9), Color(0xFF8E46B9)],
  );
  static const legacyPrimary = 0xFFD8C0C3;

  static ThemeData build({
    required Brightness brightness,
    ColorScheme? colorScheme,
    String? fontFamily,
    bool pureBlack = false,
    PageTransitionsTheme? pageTransitionsTheme,
  }) {
    final dark = brightness == Brightness.dark;
    final brand = SentinelColors.forBrightness(
      brightness,
      pureBlack: dark && pureBlack,
    );
    final source =
        colorScheme ??
        ColorScheme.fromSeed(seedColor: primary, brightness: brightness);
    final scheme = source.copyWith(
      surface: Color(dark ? 0xFF271943 : 0xFFFCFAFF),
      surfaceContainerLowest: Color(dark ? 0xFF201238 : 0xFFFFFFFF),
      surfaceContainerLow: Color(dark ? 0xFF2E204A : 0xFFF7F3FE),
      surfaceContainer: Color(dark ? 0xFF352650 : 0xFFFFFFFF),
      surfaceContainerHigh: Color(dark ? 0xFF40305E : 0xFFF0EAF9),
      surfaceContainerHighest: Color(dark ? 0xFF4B3B69 : 0xFFE9E1F4),
      onSurface: Color(dark ? 0xFFF6F2FF : 0xFF251B39),
      onSurfaceVariant: Color(dark ? 0xFFC5BBD9 : 0xFF695E7B),
      outline: Color(dark ? 0xFF817297 : 0xFF91849F),
      outlineVariant: Color(dark ? 0xFF514064 : 0xFFE3DCEC),
    );
    final effectiveScheme = dark && pureBlack
        ? scheme.copyWith(
            surface: Colors.black,
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: const Color(0xFF111111),
            surfaceContainer: const Color(0xFF181818),
            surfaceContainerHigh: const Color(0xFF222222),
            surfaceContainerHighest: const Color(0xFF2C2C2C),
          )
        : scheme;
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: effectiveScheme,
      extensions: [brand],
      pageTransitionsTheme: pageTransitionsTheme,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: effectiveScheme.outlineVariant),
    );
    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: brand.backgroundTop,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontSize: 20,
        ),
      ),
      cardTheme: CardThemeData(
        color: effectiveScheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape.copyWith(
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .65)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: effectiveScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: effectiveScheme.surfaceContainerLow,
        modalBackgroundColor: effectiveScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: effectiveScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 48),
          elevation: 0,
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: effectiveScheme.surfaceContainerLow,
        elevation: 0,
        indicatorColor: scheme.primary.withValues(alpha: .18),
        labelTextStyle: WidgetStatePropertyAll(
          base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: .18),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: effectiveScheme.surfaceContainerHigh,
        shape: shape,
        elevation: 4,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .6),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shape,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: effectiveScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    );
  }
}
