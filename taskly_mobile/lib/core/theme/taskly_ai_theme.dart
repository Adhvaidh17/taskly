import 'package:flutter/material.dart';

class TasklyAiColors {
  static const violet = Color(0xFF7C3CFF);
  static const electric = Color(0xFF4C6FFF);
  static const magenta = Color(0xFFD64EFF);

  static const lightCanvas = Color(0xFFF7F7FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightInk = Color(0xFF11131A);

  static const darkCanvas = Color(0xFF080A12);
  static const darkSurface = Color(0xFF111521);
  static const darkSurface2 = Color(0xFF171B29);
  static const darkInk = Color(0xFFF7F7FB);

  static const aiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, magenta, electric],
  );
}

class TasklyAiTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: TasklyAiColors.violet,
      brightness: Brightness.light,
      surface: TasklyAiColors.lightSurface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme.copyWith(
        primary: TasklyAiColors.violet,
        secondary: TasklyAiColors.electric,
        surface: TasklyAiColors.lightSurface,
      ),
      scaffoldBackgroundColor: TasklyAiColors.lightCanvas,
      textTheme: _textTheme(Brightness.light),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white.withValues(alpha: 0.86),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.88),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: TasklyAiColors.violet,
            width: 1.4,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: TasklyAiColors.lightSurface,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: TasklyAiColors.violet,
      brightness: Brightness.dark,
      surface: TasklyAiColors.darkSurface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme.copyWith(
        primary: const Color(0xFFA777FF),
        secondary: const Color(0xFF7A8DFF),
        surface: TasklyAiColors.darkSurface,
      ),
      scaffoldBackgroundColor: TasklyAiColors.darkCanvas,
      textTheme: _textTheme(Brightness.dark),
      cardTheme: CardThemeData(
        elevation: 0,
        color: TasklyAiColors.darkSurface.withValues(alpha: 0.82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TasklyAiColors.darkSurface2.withValues(alpha: 0.9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.07),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFFA777FF),
            width: 1.4,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: TasklyAiColors.darkSurface,
      ),
    );
  }

  static TextTheme _textTheme(Brightness brightness) {
    final ink = brightness == Brightness.dark
        ? TasklyAiColors.darkInk
        : TasklyAiColors.lightInk;
    return TextTheme(
      displaySmall: TextStyle(
        color: ink,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineMedium: TextStyle(
        color: ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
      ),
      titleLarge: TextStyle(
        color: ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      bodyLarge: TextStyle(
        color: ink.withValues(alpha: 0.88),
        height: 1.42,
      ),
      bodyMedium: TextStyle(
        color: ink.withValues(alpha: 0.72),
        height: 1.42,
      ),
    );
  }
}
