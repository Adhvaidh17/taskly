import 'package:flutter/material.dart';

/// Taskly v6.2 visual language.
///
/// Direction distilled from the supplied references:
/// - calm, whitespace-led chat hierarchy in light mode;
/// - deep navy/black glass surfaces in dark mode;
/// - violet/indigo/cyan aurora as the AI signal;
/// - rounded, tactile surfaces instead of heavy borders;
/// - a single luminous AI accent, not gradients on every component.
abstract final class TasklyAiThemeV62 {
  static const ink = Color(0xFF070A12);
  static const midnight = Color(0xFF0C1020);
  static const navy = Color(0xFF111729);
  static const snow = Color(0xFFF7F8FC);
  static const paper = Color(0xFFFFFFFF);

  static const violet = Color(0xFF7254FF);
  static const electricViolet = Color(0xFF9B4DFF);
  static const indigo = Color(0xFF445CFF);
  static const cyan = Color(0xFF49D5F2);
  static const pink = Color(0xFFF06CC8);
  static const mint = Color(0xFF5CE1C4);

  static const aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF9D4DFF),
      Color(0xFF6B50FF),
      Color(0xFF445CFF),
      Color(0xFF49D5F2),
    ],
    stops: [0.0, .34, .68, 1.0],
  );

  static const auroraHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF9D4DFF),
      Color(0xFF6B50FF),
      Color(0xFF445CFF),
    ],
  );

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: violet,
      brightness: brightness,
      primary: dark ? const Color(0xFFB7A8FF) : const Color(0xFF6447F4),
      secondary: dark ? const Color(0xFF7CE8F7) : const Color(0xFF167E97),
      surface: dark ? navy : paper,
      error: dark ? const Color(0xFFFF9EAA) : const Color(0xFFB42335),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? ink : snow,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    final on = scheme.onSurface;
    final muted = on.withValues(alpha: dark ? .63 : .58);
    final border = on.withValues(alpha: dark ? .09 : .075);

    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontSize: 38,
        height: 1.03,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 30,
        height: 1.08,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.7,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.45,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.2,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.42),
      bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.38, color: muted),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );

    return base.copyWith(
      textTheme: text,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: on,
        titleTextStyle: text.titleLarge?.copyWith(color: on),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: dark
            ? const Color(0xFF111827).withValues(alpha: .88)
            : Colors.white.withValues(alpha: .94),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? Colors.white.withValues(alpha: .055)
            : const Color(0xFFF1F3F9),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        iconColor: on.withValues(alpha: .80),
        titleTextStyle: text.bodyLarge?.copyWith(
          color: on,
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: text.bodySmall,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF111522) : Colors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: dark ? const Color(0xFF111522) : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xFF111522) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: .13),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 10.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

extension TasklyV62ThemeX on BuildContext {
  bool get isDarkV62 => Theme.of(this).brightness == Brightness.dark;

  Color get tasklyMutedV62 =>
      Theme.of(this).colorScheme.onSurface.withValues(alpha: isDarkV62 ? .62 : .57);

  Color get tasklyBorderV62 =>
      Theme.of(this).colorScheme.onSurface.withValues(alpha: isDarkV62 ? .10 : .075);

  Color get tasklyGlassV62 => isDarkV62
      ? const Color(0xFF111827).withValues(alpha: .79)
      : Colors.white.withValues(alpha: .82);
}
