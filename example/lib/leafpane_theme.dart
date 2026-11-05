import 'package:flutter/material.dart';

/// Leafpane **Deep Teal** color system.
///
/// Trustworthy · Calm · Modern
///
/// Keep in sync with `replica/design/tokens.json` and `website/styles.css`.
abstract final class LeafpaneColors {
  static const primary = Color(0xFF087F8C);
  static const primaryPressed = Color(0xFF06646F);
  static const onPrimary = Color(0xFFFFFFFF);

  static const secondary = Color(0xFF55A6A0);
  static const onSecondary = Color(0xFF0F2C2F);

  static const accent = Color(0xFFD5A64A);
  static const onAccent = Color(0xFF1A1408);

  static const surface = Color(0xFFF0F6F6);
  static const surfaceRaised = Color(0xFFE4EEEE);
  static const surfaceCard = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFDCE9E9);

  static const ink = Color(0xFF0F2C2F);
  static const inkMuted = Color(0xFF3A6865);
  static const border = Color(0xFFC5D9D8);

  static const danger = Color(0xFFB42318);
  static const onDanger = Color(0xFFFFFFFF);
}

ThemeData leafpaneTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: LeafpaneColors.primary,
    primary: LeafpaneColors.primary,
    onPrimary: LeafpaneColors.onPrimary,
    secondary: LeafpaneColors.secondary,
    onSecondary: LeafpaneColors.onSecondary,
    tertiary: LeafpaneColors.accent,
    onTertiary: LeafpaneColors.onAccent,
    surface: LeafpaneColors.surface,
    onSurface: LeafpaneColors.ink,
    error: LeafpaneColors.danger,
    onError: LeafpaneColors.onDanger,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: LeafpaneColors.surface,
    dividerColor: LeafpaneColors.border,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: LeafpaneColors.surface,
      foregroundColor: LeafpaneColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return LeafpaneColors.onPrimary;
          }
          return LeafpaneColors.inkMuted;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return LeafpaneColors.primary;
          }
          return LeafpaneColors.surfaceCard;
        }),
      ),
    ),
  );
}
