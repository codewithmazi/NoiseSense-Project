import 'package:flutter/material.dart';

/// The app's single source of visual style.
class AppTheme {
  const AppTheme._();

  // ------------------------------------------------------------------ palette

  /// Page background. Wireframe `#0B1F3A`.
  static const Color surface = Color(0xFF0B1F3A);

  /// Raised panels: cards, list rows, input fields, the navigation bar.
  static const Color surfaceContainer = Color(0xFF122E52);

  /// Primary body text and headings.
  static const Color onSurface = Color(0xFFFFFFFF);

  /// Supporting text: units, timestamps, hints.
  static const Color onSurfaceMuted = Color(0xFFB8C7D9);

  /// Teal: accent colour and the normal-exposure tone.
  static const Color primary = Color(0xFF2EC4B6);

  /// Text and icons drawn on [primary], [warning] or [error]: the page navy.
  static const Color onPrimary = Color(0xFF0B1F3A);

  /// Amber: exposure approaching the user's limit. Wireframe `#FFB43B`.
  static const Color warning = Color(0xFFFFB43B);

  /// Coral: exposure above the limit, and errors.
  static const Color error = Color(0xFFFF6B6B);

  /// Input borders and dividers. Non-text, so judged against SC 1.4.11 at 3:1.
  static const Color outline = Color(0xFF8A9AB0);

  /// Panel borders.
  static const Color outlineSubtle = Color(0xFF577AA3);

  // ------------------------------------------------------------------ metrics

  /// Minimum side of any tappable target, in logical pixels.
  static const double minTouchTarget = 48;

  /// Spacing scale.
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  static const BorderRadius radius = BorderRadius.all(Radius.circular(12));

  /// Text/background pairs that must meet SC 1.4.3; read by the contrast test.
  static const Map<String, (Color foreground, Color background)> textPairs = {
    'body text on page': (onSurface, surface),
    'body text on panel': (onSurface, surfaceContainer),
    'muted text on page': (onSurfaceMuted, surface),
    'muted text on panel': (onSurfaceMuted, surfaceContainer),
    'accent text on page': (primary, surface),
    'accent text on panel': (primary, surfaceContainer),
    'error text on page': (error, surface),
    'error text on panel': (error, surfaceContainer),
    'warning text on page': (warning, surface),
    'warning text on panel': (warning, surfaceContainer),
    'label on primary button': (onPrimary, primary),
    'label on warning chip': (onPrimary, warning),
    'label on error chip': (onPrimary, error),
  };

  /// Tone colours used as graphics: the gauge ring and the dose bar.
  static const List<Color> toneColours = [primary, warning, error];

  /// Non-text pairs judged against SC 1.4.11 at 3:1.
  static const Map<String, (Color foreground, Color background)> nonTextPairs =
      {
        'field border on page': (outline, surface),
        'field border on panel': (outline, surfaceContainer),
        'panel border on page': (outlineSubtle, surface),
        'panel border on panel': (outlineSubtle, surfaceContainer),
        'gauge teal on page': (primary, surface),
        'gauge amber on page': (warning, surface),
        'gauge coral on page': (error, surface),
        'dose bar teal on track': (primary, surfaceContainer),
        'dose bar amber on track': (warning, surfaceContainer),
        'dose bar coral on track': (error, surfaceContainer),
      };

  /// Pairs measured for the record but not held to a threshold.
  static const Map<String, (Color foreground, Color background)>
  informationalPairs = {'panel fill against page': (surfaceContainer, surface)};

  // -------------------------------------------------------------------- theme

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceContainer,
      error: error,
      onError: onPrimary,
      outline: outline,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      // Dark brightness, so system widgets draw light-on-dark.
      brightness: Brightness.dark,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          // Fixed height keeps the tap target large at any text size.
          minimumSize: const Size.fromHeight(minTouchTarget),
          // Pill-shaped, as in the wireframes.
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainer,
        // Floating labels stay visible once the field has content.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: const TextStyle(color: onSurfaceMuted),
        helperStyle: const TextStyle(color: onSurfaceMuted, fontSize: 13),
        // Two lines for errors, so they wrap at large text sizes.
        helperMaxLines: 2,
        errorMaxLines: 3,
        errorStyle: const TextStyle(color: error, fontSize: 13),
        border: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: error),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: error, width: 2),
        ),
      ),
      cardTheme: const CardThemeData(
        color: surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          // The boundary, rather than the fill, is what makes a panel discernible.
          side: BorderSide(color: outlineSubtle),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: outlineSubtle,
        thickness: 0.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceContainer,
        indicatorColor: primary,
        // Labels always shown.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 13,
            color: onSurfaceMuted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? onPrimary
                : onSurfaceMuted,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? onPrimary : outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : surfaceContainer,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(outline),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          side: const BorderSide(color: primary),
          minimumSize: const Size.fromHeight(minTouchTarget),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceContainer,
        contentTextStyle: TextStyle(color: onSurface),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
