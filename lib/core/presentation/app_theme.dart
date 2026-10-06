import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF0F766E);
  static const canvas = Color(0xFFF2F6F7);
  static const surface = Colors.white;
  static const text = Color(0xFF172B3A);
  static const secondary = Color(0xFF526474);
  static const border = Color(0xFFDCE4EA);
  static const success = Color(0xFF166534);
  static const warning = Color(0xFF92400E);
  static const danger = Color(0xFFB91C1C);
}

abstract final class Space {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0, xxl = 32.0;
  static const contentWidth = 720.0;
}

ThemeData appTheme() {
  final colors = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.secondary,
    outlineVariant: AppColors.border,
    error: AppColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: AppColors.canvas,
    fontFamily: 'Vazirmatn',
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      headlineSmall: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: AppColors.text),
      bodyMedium: TextStyle(fontSize: 16, color: AppColors.text),
      bodySmall: TextStyle(fontSize: 14, color: AppColors.secondary),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shadowColor: const Color(0x18172B3A),
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      errorMaxLines: 4,
      helperMaxLines: 4,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.secondary),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      minVerticalPadding: 12,
      iconColor: AppColors.secondary,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 24),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFDCEFEA),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      titleTextStyle: const TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.text,
      actionTextColor: Colors.white,
      contentTextStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 16,
        color: Colors.white,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: MotionPageTransitions(
          ZoomPageTransitionsBuilder(),
        ),
        TargetPlatform.iOS: MotionPageTransitions(
          CupertinoPageTransitionsBuilder(),
        ),
        TargetPlatform.macOS: MotionPageTransitions(
          CupertinoPageTransitionsBuilder(),
        ),
        TargetPlatform.windows: MotionPageTransitions(
          ZoomPageTransitionsBuilder(),
        ),
        TargetPlatform.linux: MotionPageTransitions(
          ZoomPageTransitionsBuilder(),
        ),
      },
    ),
  );
}

bool reduceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.accessibleNavigationOf(context);

/// Keep native route gestures, while honoring the device's motion preference.
class MotionPageTransitions extends PageTransitionsBuilder {
  const MotionPageTransitions(this.delegate);
  final PageTransitionsBuilder delegate;
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => reduceMotion(context)
      ? child
      : delegate.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}
