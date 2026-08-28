import 'package:flutter/material.dart';

/// Taskly v6.1 visual system: AI-first, luminous, clean and usable in both modes.
abstract final class TasklyAiThemeV61 {
  static const violet = Color(0xFF7157FF);
  static const indigo = Color(0xFF4667FF);
  static const cyan = Color(0xFF21C7D9);
  static const magenta = Color(0xFFD54CFF);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final darkMode = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: violet,
      brightness: brightness,
      primary: darkMode ? const Color(0xFFA99BFF) : const Color(0xFF6248F2),
      secondary: darkMode ? const Color(0xFF6EE8F3) : const Color(0xFF087F92),
      surface: darkMode ? const Color(0xFF11131C) : const Color(0xFFF9F9FE),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          darkMode ? const Color(0xFF080A10) : const Color(0xFFF6F7FC),
      visualDensity: VisualDensity.standard,
    );

    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.25,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
    );

    final outline = darkMode
        ? Colors.white.withValues(alpha: 0.09)
        : const Color(0xFF15172A).withValues(alpha: 0.08);

    return base.copyWith(
      textTheme: text,
      dividerColor: outline,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: darkMode
            ? const Color(0xFF171925).withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.92),
        shadowColor: Colors.black.withValues(alpha: darkMode ? 0.28 : 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: outline),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: darkMode
            ? const Color(0xFF10121B).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.96),
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkMode
            ? Colors.white.withValues(alpha: 0.055)
            : Colors.white.withValues(alpha: 0.9),
        hintStyle: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.42),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          side: BorderSide(color: outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        side: BorderSide(color: outline),
      ),
    );
  }
}

class TasklyAiGradient {
  static LinearGradient hero(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? const [Color(0xFF3A2A8A), Color(0xFF163769), Color(0xFF0D535B)]
          : const [Color(0xFFECE7FF), Color(0xFFE8F0FF), Color(0xFFDFFBFA)],
    );
  }

  static const action = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF6B4EFF), Color(0xFF4A72FF), Color(0xFF16B9C7)],
  );
}
