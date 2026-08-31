import 'dart:ui';

import 'package:flutter/material.dart';

/// Taskly glass design system.
/// One visual language is shared by every screen in light and dark mode.
abstract final class TasklyAiThemeV62 {
  static const ink = Color(0xFF070A12);
  static const midnight = Color(0xFF0D1120);
  static const navy = Color(0xFF11182A);
  static const snow = Color(0xFFF5F4FA);
  static const paper = Color(0xFFFFFFFF);
  static const violet = Color(0xFF7657F7);
  static const electricViolet = Color(0xFF9B63FF);
  static const indigo = Color(0xFF536BFF);
  static const cyan = Color(0xFF5BD9F4);
  static const pink = Color(0xFFF18BD2);
  static const mint = Color(0xFF5FE0C3);

  static const aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB06BFF), Color(0xFF7657F7), Color(0xFF536BFF), Color(0xFF5BD9F4)],
    stops: [0, .34, .70, 1],
  );
  static const auroraHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF9B63FF), Color(0xFF7657F7), Color(0xFF536BFF)],
  );
  static const lightWash = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF3F0FF), Color(0xFFEFF8FF)],
  );
  static const darkWash = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF070A12), Color(0xFF10142A), Color(0xFF160F27)],
  );

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: violet,
      brightness: brightness,
      primary: dark ? const Color(0xFFBBA8FF) : const Color(0xFF6849E9),
      secondary: dark ? const Color(0xFF72E4F5) : const Color(0xFF168BA7),
      surface: dark ? midnight : paper,
      error: dark ? const Color(0xFFFF8E9A) : const Color(0xFFD74455),
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
    final muted = on.withValues(alpha: dark ? .64 : .58);
    final border = on.withValues(alpha: dark ? .14 : .12);
    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(fontSize: 38, height: 1.02, fontWeight: FontWeight.w800, letterSpacing: -1.6),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontSize: 30, height: 1.06, fontWeight: FontWeight.w800, letterSpacing: -1.1),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.7),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.45),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.2),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.42),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.38),
      bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.34, color: muted),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
    return base.copyWith(
      textTheme: text,
      dividerColor: border,
      scaffoldBackgroundColor: dark ? ink : snow,
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
        color: dark ? const Color(0xFF151A2A).withValues(alpha: .68) : Colors.white.withValues(alpha: .70),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: BorderSide(color: border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? Colors.white.withValues(alpha: .065) : Colors.white.withValues(alpha: .62),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        iconColor: on.withValues(alpha: .82),
        titleTextStyle: text.bodyLarge?.copyWith(color: on, fontWeight: FontWeight.w700),
        subtitleTextStyle: text.bodySmall,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xFF171B2A) : const Color(0xFFFDFDFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: BorderSide(color: border)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: dark ? .22 : .14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 10.5,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
        )),
      ),
    );
  }
}

extension TasklyV62ThemeX on BuildContext {
  bool get isDarkV62 => Theme.of(this).brightness == Brightness.dark;
  Color get tasklyMutedV62 => Theme.of(this).colorScheme.onSurface.withValues(alpha: isDarkV62 ? .64 : .57);
  Color get tasklyBorderV62 => Theme.of(this).colorScheme.onSurface.withValues(alpha: isDarkV62 ? .14 : .11);
  Color get tasklyGlassV62 => isDarkV62 ? const Color(0xFF151A2A).withValues(alpha: .70) : Colors.white.withValues(alpha: .68);
  LinearGradient get tasklyBackgroundV62 => isDarkV62 ? TasklyAiThemeV62.darkWash : TasklyAiThemeV62.lightWash;
}

class TasklyGlassV62 extends StatelessWidget {
  const TasklyGlassV62({super.key, required this.child, this.padding, this.margin, this.radius = 26, this.gradient});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkV62;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: gradient ?? (dark ? const LinearGradient(colors: [Color(0xCC151A2A), Color(0xB30F1422)]) : const LinearGradient(colors: [Color(0xE6FFFFFF), Color(0xBFF7F3FF)])),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: context.tasklyBorderV62),
        boxShadow: [BoxShadow(blurRadius: 28, spreadRadius: -12, color: Colors.black.withValues(alpha: dark ? .45 : .08), offset: const Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}
