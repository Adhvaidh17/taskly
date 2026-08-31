import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class TasklyTheme extends ThemeExtension<TasklyTheme> {
  const TasklyTheme({
    required this.canvas,
    required this.panel,
    required this.panelStrong,
    required this.panelSoft,
    required this.border,
    required this.textMuted,
    required this.textFaint,
    required this.chatMine,
    required this.chatOther,
    required this.chatMineText,
    required this.chatOtherText,
    required this.senderName,
    required this.replyBackground,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  final Color canvas;
  final Color panel;
  final Color panelStrong;
  final Color panelSoft;
  final Color border;
  final Color textMuted;
  final Color textFaint;
  final Color chatMine;
  final Color chatOther;
  final Color chatMineText;
  final Color chatOtherText;
  final Color senderName;
  final Color replyBackground;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  @override
  TasklyTheme copyWith({
    Color? canvas,
    Color? panel,
    Color? panelStrong,
    Color? panelSoft,
    Color? border,
    Color? textMuted,
    Color? textFaint,
    Color? chatMine,
    Color? chatOther,
    Color? chatMineText,
    Color? chatOtherText,
    Color? senderName,
    Color? replyBackground,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
  }) {
    return TasklyTheme(
      canvas: canvas ?? this.canvas,
      panel: panel ?? this.panel,
      panelStrong: panelStrong ?? this.panelStrong,
      panelSoft: panelSoft ?? this.panelSoft,
      border: border ?? this.border,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      chatMine: chatMine ?? this.chatMine,
      chatOther: chatOther ?? this.chatOther,
      chatMineText: chatMineText ?? this.chatMineText,
      chatOtherText: chatOtherText ?? this.chatOtherText,
      senderName: senderName ?? this.senderName,
      replyBackground: replyBackground ?? this.replyBackground,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
    );
  }

  @override
  TasklyTheme lerp(covariant TasklyTheme? other, double t) {
    if (other == null) return this;
    return TasklyTheme(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelStrong: Color.lerp(panelStrong, other.panelStrong, t)!,
      panelSoft: Color.lerp(panelSoft, other.panelSoft, t)!,
      border: Color.lerp(border, other.border, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      chatMine: Color.lerp(chatMine, other.chatMine, t)!,
      chatOther: Color.lerp(chatOther, other.chatOther, t)!,
      chatMineText: Color.lerp(chatMineText, other.chatMineText, t)!,
      chatOtherText: Color.lerp(chatOtherText, other.chatOtherText, t)!,
      senderName: Color.lerp(senderName, other.senderName, t)!,
      replyBackground: Color.lerp(replyBackground, other.replyBackground, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

extension TasklyThemeContext on BuildContext {
  TasklyTheme get taskly => Theme.of(this).extension<TasklyTheme>()!;
}

class AppTheme {
  static const accent = Color(0xFF6D5CE7);
  static const danger = Color(0xFFE05252);
  static const warning = Color(0xFFE59A23);
  static const success = Color(0xFF169B72);
  static const info = Color(0xFF3B82F6);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;

    // Light is intentionally warm/airy and surface-led. Dark is intentionally
    // deep/navy and panel-led; neither mode reuses the other's black/white UI.
    final canvas = dark ? const Color(0xFF080A11) : const Color(0xFFF5F7FC);
    final panel = dark ? const Color(0xFF151923) : const Color(0xFFFFFFFF);
    final panelStrong = dark ? const Color(0xFF202532) : const Color(0xFFE9ECF4);
    final panelSoft = dark ? const Color(0xFF1B202B) : const Color(0xFFEEF1F7);
    final border = dark ? const Color(0xFF343B4B) : const Color(0xFFD6DCE8);
    final primary = dark ? const Color(0xFFB5A7FF) : const Color(0xFF6552D9);

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: panel,
      error: danger,
    ).copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF17112F) : Colors.white,
      secondary: dark ? const Color(0xFF79D7F4) : const Color(0xFF3478D7),
      surface: panel,
      surfaceContainerLowest: canvas,
      surfaceContainerLow: panelSoft,
      surfaceContainer: panel,
      surfaceContainerHigh: panelStrong,
      surfaceTint: Colors.transparent,
      outline: dark ? const Color(0xFF646D80) : const Color(0xFF737C8E),
      outlineVariant: border,
    );

    final tokens = TasklyTheme(
      canvas: canvas,
      panel: panel,
      panelStrong: panelStrong,
      panelSoft: panelSoft,
      border: border,
      textMuted: dark ? const Color(0xFFB6BDCB) : const Color(0xFF566071),
      textFaint: dark ? const Color(0xFF858EA0) : const Color(0xFF7B8494),
      chatMine: dark ? const Color(0xFF5D4CC5) : const Color(0xFFE5DFFF),
      chatOther: dark ? const Color(0xFF1C212C) : Colors.white,
      chatMineText: dark ? Colors.white : const Color(0xFF211A4D),
      chatOtherText: dark ? const Color(0xFFF2F4F8) : const Color(0xFF171A22),
      senderName: dark ? const Color(0xFFD0C7FF) : const Color(0xFF5542C2),
      replyBackground: dark ? const Color(0x66000000) : const Color(0x14000000),
      success: dark ? const Color(0xFF54D7AD) : success,
      warning: dark ? const Color(0xFFF4BC55) : warning,
      danger: dark ? const Color(0xFFFF827A) : danger,
      info: dark ? const Color(0xFF7CB8FF) : info,
    );

    final typography = Typography.material2021(
      platform: defaultTargetPlatform,
      colorScheme: scheme,
    );
    final baseTextTheme = dark ? typography.white : typography.black;
    final textTheme = baseTextTheme.copyWith(
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.25,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: baseTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );

    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarContrastEnforced: false,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      cardColor: tokens.panel,
      dividerColor: tokens.border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      extensions: [tokens],
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 19),
        iconTheme: IconThemeData(color: scheme.onSurface),
        systemOverlayStyle: overlay,
      ),
      cardTheme: CardThemeData(
        color: tokens.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: tokens.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.panelSoft,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        hintStyle: TextStyle(color: tokens.textFaint),
        labelStyle: TextStyle(color: tokens.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.panel,
        surfaceTintColor: Colors.transparent,
        indicatorColor: dark ? const Color(0xFF4E3D99) : const Color(0xFFE0D9FF),
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? (dark ? Colors.white : const Color(0xFF3E2E9D))
                : tokens.textMuted,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : tokens.textMuted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.panel,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: tokens.textMuted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: tokens.panel,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.textMuted,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.panelSoft,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : tokens.panel;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : tokens.textMuted;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: tokens.border)),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 46),
          side: BorderSide(color: tokens.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.textMuted,
          highlightColor: scheme.primary.withValues(alpha: 0.10),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFF303441) : const Color(0xFF20232B),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: tokens.panelStrong,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: tokens.danger,
        textColor: dark ? const Color(0xFF2B0505) : Colors.white,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : tokens.textFaint;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : tokens.panelStrong;
        }),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF343946) : const Color(0xFF20232B),
          borderRadius: BorderRadius.circular(9),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
