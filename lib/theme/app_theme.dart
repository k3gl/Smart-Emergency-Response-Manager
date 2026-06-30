import 'package:flutter/material.dart';

/// Centralized app theme — a modern semi-dark look. Defining styling once here
/// gives every screen a consistent appearance. Purely presentational.
class AppTheme {
  // Core palette (semi-dark, not pure black).
  static const Color bg = Color(0xFF13151A); // app background
  static const Color surface = Color(0xFF1C1F27); // cards / inputs
  static const Color surfaceHi = Color(0xFF232733); // raised surfaces
  static const Color stroke = Color(0xFF2A2E38); // subtle borders
  static const Color primary = Color(0xFF5B8DEF); // vibrant blue accent
  static const Color accent = Color(0xFFFF5C61); // emergency red
  static const Color textHi = Color(0xFFE7E9EE); // primary text
  static const Color textLo = Color(0xFF9BA1AD); // muted text

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      primary: primary,
      error: accent,
      surface: surface,
    );

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardColor: surface,

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceHi,
        modalBackgroundColor: surfaceHi,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceHi,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      listTileTheme: const ListTileThemeData(iconColor: textLo),

      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textHi,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textHi,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: textLo),
        labelStyle: const TextStyle(color: textLo),
        prefixIconColor: textLo,
        border: border(stroke),
        enabledBorder: border(stroke),
        focusedBorder: border(primary, 1.6),
        errorBorder: border(accent, 1.2),
        focusedErrorBorder: border(accent, 1.6),
        floatingLabelStyle: const TextStyle(color: primary),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textHi,
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: const BorderSide(color: stroke),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHi,
        contentTextStyle: const TextStyle(color: textHi),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      dividerTheme: const DividerThemeData(color: stroke, thickness: 1),

      iconTheme: const IconThemeData(color: textHi),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeSlideTransitionsBuilder(),
          TargetPlatform.iOS: _FadeSlideTransitionsBuilder(),
          TargetPlatform.windows: _FadeSlideTransitionsBuilder(),
          TargetPlatform.macOS: _FadeSlideTransitionsBuilder(),
          TargetPlatform.linux: _FadeSlideTransitionsBuilder(),
        },
      ),
    );
  }
}

/// A smooth fade + slight slide-up used for every page navigation.
class _FadeSlideTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeSlideTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
