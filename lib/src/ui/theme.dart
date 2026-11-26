import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class NxColors {
  static const lime = Color(0xFFD4FF3A);
  static const ink = Color(0xFF111115);
  static const red = Color(0xFFFF5A5F);
  static const amber = Color(0xFFFFB547);
  static const green = Color(0xFF34D399);
}

/// The app's colors. Dark mode uses lime as the accent; light mode uses ink with lime on top,
/// because lime text or lines on white are hard to see.
class NxPalette extends ThemeExtension<NxPalette> {
  const NxPalette({
    required this.background,
    required this.card,
    required this.field,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
  });

  final Color background;
  final Color card;
  final Color field;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;

  static const dark = NxPalette(
    background: Color(0xFF0B0B0E),
    card: Color(0xFF16161B),
    field: Color(0xFF202027),
    border: Color(0x12FFFFFF),
    text: Color(0xFFF5F5F7),
    muted: Color(0xFF8E8E9A),
    accent: NxColors.lime,
    onAccent: Color(0xFF0B0B0E),
  );

  static const light = NxPalette(
    background: Color(0xFFF4F4F1),
    card: Colors.white,
    field: Color(0xFFEBEBE6),
    border: Color(0x14000000),
    text: NxColors.ink,
    muted: Color(0xFF6E6E78),
    accent: NxColors.ink,
    onAccent: NxColors.lime,
  );

  @override
  NxPalette copyWith({
    Color? background,
    Color? card,
    Color? field,
    Color? border,
    Color? text,
    Color? muted,
    Color? accent,
    Color? onAccent,
  }) =>
      NxPalette(
        background: background ?? this.background,
        card: card ?? this.card,
        field: field ?? this.field,
        border: border ?? this.border,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
      );

  @override
  NxPalette lerp(NxPalette? other, double t) {
    if (other == null) return this;
    return NxPalette(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      field: Color.lerp(field, other.field, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

extension NxThemeContext on BuildContext {
  NxPalette get nx => Theme.of(this).extension<NxPalette>()!;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final p = dark ? NxPalette.dark : NxPalette.light;
  final scheme = ColorScheme.fromSeed(seedColor: NxColors.lime, brightness: brightness).copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    error: NxColors.red,
    surface: p.background,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    outline: p.border,
  );

  final base = ThemeData(colorScheme: scheme, brightness: brightness, useMaterial3: true);
  final t = base.textTheme.apply(bodyColor: p.text, displayColor: p.text);
  final text = t.copyWith(
    headlineLarge: t.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2),
    headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
    headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );

  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    textTheme: text,
    extensions: [p],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
      hintStyle: TextStyle(color: p.muted),
      labelStyle: TextStyle(color: p.muted),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: dark ? NxColors.lime : NxColors.ink,
      selectionColor: NxColors.lime.withValues(alpha: 0.35),
      selectionHandleColor: dark ? NxColors.lime : NxColors.ink,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF26262E) : NxColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      actionTextColor: NxColors.lime,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.muted.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.text,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    dividerTheme: DividerThemeData(color: p.border, space: 1, thickness: 1),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
