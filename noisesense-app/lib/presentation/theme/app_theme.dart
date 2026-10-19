import 'package:flutter/material.dart';

/// The app's single source of visual style.
///
/// Every colour, spacing step and text style used by a screen comes from here.
/// Nothing is styled inline. That is what makes the consistency claim in the
/// report checkable rather than rhetorical: a reviewer can see that there is
/// one definition of "primary action" and one definition of "error", so the
/// same meaning always looks the same (Nielsen, 1994: consistency and
/// standards).
///
/// The palette is taken from the project's hi-fi wireframes
/// (`Wireframes_HiFi.drawio`), which share it with the presentation deck:
/// navy surfaces, teal for normal, amber for approaching the limit and coral
/// for exceeding it. An earlier version of this file described its palette as
/// "the 602 deck's navy" without having been checked against either source;
/// it did not match, and was replaced with the wireframe values.
///
/// Every foreground and background pair below is asserted against WCAG 2.2 by
/// `test/presentation/theme_contrast_test.dart`, and one wireframe colour was
/// changed as a result (see [outlineSubtle]).
class AppTheme {
  const AppTheme._();

  // ------------------------------------------------------------------ palette

  /// Page background. Wireframe `#0B1F3A`.
  static const Color surface = Color(0xFF0B1F3A);

  /// Raised panels: cards, list rows, input fields, the navigation bar.
  /// Wireframe `#122E52`.
  static const Color surfaceContainer = Color(0xFF122E52);

  /// Primary body text and headings.
  static const Color onSurface = Color(0xFFFFFFFF);

  /// Supporting text: units, timestamps, hints. Wireframe `#B8C7D9`, which
  /// clears the 4.5:1 body-text threshold on both surfaces, not merely the
  /// large-text one, because this style is used at normal size.
  static const Color onSurfaceMuted = Color(0xFFB8C7D9);

  /// Teal. The accent for actions and selected state, and the "normal"
  /// exposure tone. Wireframe `#2EC4B6`.
  static const Color primary = Color(0xFF2EC4B6);

  /// Text and icons drawn on [primary], [warning] or [error]: the page navy.
  static const Color onPrimary = Color(0xFF0B1F3A);

  /// Amber: exposure approaching the user's limit. Wireframe `#FFB43B`.
  static const Color warning = Color(0xFFFFB43B);

  /// Coral: exposure above the limit, and errors. Wireframe `#FF6B6B`.
  ///
  /// One colour for both, because both mean "something needs your attention"
  /// and a second red would ask the user to learn a distinction that carries
  /// no meaning.
  static const Color error = Color(0xFFFF6B6B);

  /// Input borders and dividers. Non-text, so judged against SC 1.4.11 at 3:1.
  static const Color outline = Color(0xFF8A9AB0);

  /// Panel borders.
  ///
  /// The one deliberate departure from the wireframes. They draw card edges
  /// in `#1B3D68`, which measures 1.51:1 against the page: under the 3:1 that
  /// SC 1.4.11 requires of a boundary that identifies a component, and the
  /// panel fill alone is no help (see [informationalPairs]). This is the
  /// nearest blue of the same hue that passes on both surfaces.
  static const Color outlineSubtle = Color(0xFF577AA3);

  // ------------------------------------------------------------------ metrics

  /// Minimum side of any tappable target, in logical pixels.
  ///
  /// WCAG 2.2 SC 2.5.8 Target Size (Minimum) sets 24x24 CSS pixels for AA.
  /// This uses 48, the Material Design minimum, because 24 is a floor for
  /// conformance rather than a usable size, and the extra cost is nil. An
  /// app intended to be operated one-handed while walking past traffic should
  /// not be designed to the lowest passing value.
  static const double minTouchTarget = 48;

  /// Spacing scale. A fixed set of steps rather than arbitrary numbers, so
  /// rhythm stays even across screens.
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  static const BorderRadius radius = BorderRadius.all(Radius.circular(12));

  /// Foreground and background pairs that must meet SC 1.4.3, named so the
  /// contrast test enumerates them instead of hardcoding its own list. Adding
  /// a colour pair to the theme without adding it here is therefore visible:
  /// the test cannot silently skip it.
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

  /// Tone colours used as graphics: the gauge ring and the dose bar. Judged
  /// as non-text against both surfaces.
  static const List<Color> toneColours = [primary, warning, error];

  /// Non-text pairs judged against SC 1.4.11 at 3:1.
  ///
  /// These are boundaries that carry meaning: they are what tells the user
  /// where a control begins and ends, so SC 1.4.11 applies to them.
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
  ///
  /// The difference between two background fills is not a boundary that
  /// identifies a component, so SC 1.4.11 does not govern it; the adjacent
  /// `panel border on page` entry is the boundary that does. The figure is
  /// still reported, because it is the measurement that showed fill alone was
  /// insufficient and prompted the border to be added.
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
      // Declared so the OS draws light-on-dark system affordances, such as the
      // text selection handles and the keyboard, to match the app.
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
          // Height, not just padding, so the target stays large enough when
          // the user has scaled text down as well as up.
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
        // Labels stay visible above the field once it has content, rather than
        // disappearing as placeholder text does. A placeholder that vanishes
        // on focus removes the instruction exactly when the user needs it
        // (WCAG 2.2 SC 3.3.2 Labels or Instructions).
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: const TextStyle(color: onSurfaceMuted),
        helperStyle: const TextStyle(color: onSurfaceMuted, fontSize: 13),
        // Two lines of room, so a validation message wraps rather than being
        // truncated at large text sizes (SC 1.4.4 Resize Text).
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
          // The boundary, rather than the fill, is what makes a panel
          // discernible. See [outlineSubtle].
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
        // Labels always shown. Icon-only navigation forces the user to learn
        // what each glyph means (Nielsen, 1994: recognition rather than
        // recall), and gives a screen reader nothing better than the icon's
        // name.
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
