import 'package:flutter/material.dart';

abstract final class IndustrialPalette {
  static const background = Color(0xFF18181A);
  static const surface = Color(0xFF202022);
  static const panel = Color(0xFF262628);
  static const reading = Color(0xFF303033);
  static const border = Color(0xFF3A3A3C);
  static const ink = Color(0xFFF2F1ED);
  static const muted = Color(0xFFA9A8A3);
  static const faint = Color(0xFF777773);
  static const accent = Color(0xFFC6CA4C);
  static const accentInk = Color(0xFF222319);
  static const error = Color(0xFFFF7774);
}

ThemeData industrialTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: IndustrialPalette.accent,
    brightness: Brightness.dark,
    surface: IndustrialPalette.surface,
    onSurface: IndustrialPalette.ink,
    error: IndustrialPalette.error,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'AlibabaPuHuiTi',
    fontFamilyFallback: const ['LiberationSerif'],
    scaffoldBackgroundColor: IndustrialPalette.background,
    colorScheme: scheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: IndustrialPalette.background,
      foregroundColor: IndustrialPalette.ink,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: IndustrialPalette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    cardTheme: CardThemeData(
      color: IndustrialPalette.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: IndustrialPalette.border),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: IndustrialPalette.ink),
      titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: IndustrialPalette.ink),
      bodyMedium:
          TextStyle(fontSize: 14, height: 1.6, color: IndustrialPalette.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: IndustrialPalette.accent,
        foregroundColor: IndustrialPalette.accentInk,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: IndustrialPalette.ink,
        side: const BorderSide(color: IndustrialPalette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: IndustrialPalette.reading,
      labelStyle: const TextStyle(color: IndustrialPalette.muted),
      hintStyle: const TextStyle(color: IndustrialPalette.faint),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: IndustrialPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide:
            const BorderSide(color: IndustrialPalette.accent, width: 1.5),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: IndustrialPalette.accent,
      linearTrackColor: IndustrialPalette.border,
    ),
    dividerColor: IndustrialPalette.border,
  );
}

class IndustrialStatusPill extends StatelessWidget {
  const IndustrialStatusPill({
    super.key,
    required this.label,
    this.icon = Icons.bolt_rounded,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: MediaQuery.maybeOf(context)?.disableAnimations == true
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? IndustrialPalette.reading : IndustrialPalette.panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? IndustrialPalette.accent : IndustrialPalette.border,
          ),
          boxShadow: active
              ? const [BoxShadow(color: Color(0x33C6CA4C), blurRadius: 16)]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: IndustrialPalette.accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: IndustrialPalette.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
          ],
        ),
      );
}
