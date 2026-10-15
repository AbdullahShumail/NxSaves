import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

abstract final class NxColors {
  static const violet = Color(0xFF7B61FF);
  static const pink = Color(0xFFFF4F9A);
  static const teal = Color(0xFF2DD4BF);
  static const amber = Color(0xFFFFB547);
  static const red = Color(0xFFFF5D6C);

  static const brand = LinearGradient(
    colors: [violet, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Extra colors the Material scheme doesn't cover.
class NxPalette extends ThemeExtension<NxPalette> {
  const NxPalette({required this.card, required this.border, required this.muted, required this.field});

  final Color card;
  final Color border;
  final Color muted;
  final Color field;

  static const dark = NxPalette(
    card: Color(0xFF15151F),
    border: Color(0x14FFFFFF),
    muted: Color(0xFF9A9AB0),
    field: Color(0xFF1C1C28),
  );

  static const light = NxPalette(
    card: Colors.white,
    border: Color(0x14000000),
    muted: Color(0xFF6B6B80),
    field: Color(0xFFF1F1F7),
  );

  @override
  NxPalette copyWith({Color? card, Color? border, Color? muted, Color? field}) => NxPalette(
        card: card ?? this.card,
        border: border ?? this.border,
        muted: muted ?? this.muted,
        field: field ?? this.field,
      );

  @override
  NxPalette lerp(NxPalette? other, double t) {
    if (other == null) return this;
    return NxPalette(
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      field: Color.lerp(field, other.field, t)!,
    );
  }
}

extension NxThemeContext on BuildContext {
  NxPalette get nx => Theme.of(this).extension<NxPalette>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? NxPalette.dark : NxPalette.light;
  final background = dark ? const Color(0xFF0A0A10) : const Color(0xFFF5F5FA);
  final scheme = ColorScheme.fromSeed(seedColor: NxColors.violet, brightness: brightness).copyWith(
    primary: dark ? const Color(0xFFA493FF) : NxColors.violet,
    onPrimary: Colors.white,
    secondary: NxColors.pink,
    tertiary: NxColors.teal,
    error: NxColors.red,
    surface: background,
    onSurfaceVariant: palette.muted,
  );

  final base = ThemeData(colorScheme: scheme, brightness: brightness, useMaterial3: true);
  final text = base.textTheme.copyWith(
    displaySmall: base.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );

  return base.copyWith(
    scaffoldBackgroundColor: background,
    textTheme: text,
    extensions: [palette],
    splashFactory: InkSparkle.splashFactory,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF101017) : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: NxColors.violet.withValues(alpha: dark ? 0.28 : 0.14),
      height: 70,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? scheme.onSurface : palette.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? scheme.primary : palette.muted,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: palette.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF26263A) : const Color(0xFF1E1E2C),
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      actionTextColor: const Color(0xFFC6BBFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.standard,
        side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? NxColors.violet.withValues(alpha: dark ? 0.3 : 0.14)
              : palette.field,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? NxColors.violet : palette.field,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : palette.muted,
      ),
      trackOutlineColor: WidgetStatePropertyAll(palette.border),
    ),
    dividerTheme: DividerThemeData(color: palette.border, space: 1),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
