import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Brand Colors ──────────────────────────────────────────────
class LiftrColors {
  // Accent — lime green (same in both modes)
  static const accent = Color(0xFFC8F075);
  static const accentDark = Color(0xFF80E850);
  static const accentText = Color(0xFF0F1A04); // text ON accent bg

  // Destructive actions — delete, sign-out warnings, form errors. Same in both
  // modes. Was copy-pasted as a raw 0xFFE24B4A in ~20 places; use this, or
  // `context.lt.danger` where a theme is in hand.
  static const danger = Color(0xFFE24B4A);

  // Drop shadow beneath popovers (the exercise dropdown). Deliberately soft.
  static const shadow = Color(0x33000000);

  // Dark mode palette
  static const darkBg = Color(0xFF0F0F10);
  static const darkSurface = Color(0xFF15151A);
  static const darkCard = Color(0xFF1A1A1E);
  static const darkBorder = Color(0xFF2E2E34);
  static const darkBorderSubtle = Color(0xFF2A2A32);
  static const darkText = Color(0xFFE2E2E6);
  static const darkTextSecondary = Color(0xFF9A9AA4);
  static const darkTextMuted = Color(0xFF5A5A62);
  static const darkTextDim = Color(0xFF3A3A42);

  // Dark mode accent tints
  static const darkAccentBg = Color(0xFF1A2208);
  static const darkAccentBorder = Color(0xFF3A5010);
  static const darkAccentMid = Color(0xFF80A840);
  static const darkAccentText = Color(0xFFA0D050);

  // Light mode palette
  static const lightBg = Color(0xFFF5F5F0);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFF0F0EA);
  static const lightBorder = Color(0xFFDDDDD5);
  static const lightBorderSubtle = Color(0xFFE5E5DE);
  static const lightText = Color(0xFF1A1A1E);
  static const lightTextSecondary = Color(0xFF5A5A62);
  static const lightTextMuted = Color(0xFF8A8A94);
  static const lightTextDim = Color(0xFFB0B0B8);

  // Light mode accent tints
  static const lightAccentBg = Color(0xFFEEFAD8);
  static const lightAccentBorder = Color(0xFF9AC840);
  static const lightAccentMid = Color(0xFF4A8010);
  static const lightAccentText = Color(0xFF3A6008);
}

// ── Theme Extension (custom tokens) ───────────────────────────
class LiftrTheme extends ThemeExtension<LiftrTheme> {
  final Color surface;
  final Color card;
  final Color border;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDim;
  final Color accentBg;
  final Color accentBorder;
  final Color accentMid;
  final Color accentTextColor;
  final Color danger;

  const LiftrTheme({
    required this.surface,
    required this.card,
    required this.border,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDim,
    required this.accentBg,
    required this.accentBorder,
    required this.accentMid,
    required this.accentTextColor,
    this.danger = LiftrColors.danger,
  });

  static const dark = LiftrTheme(
    surface: LiftrColors.darkSurface,
    card: LiftrColors.darkCard,
    border: LiftrColors.darkBorder,
    borderSubtle: LiftrColors.darkBorderSubtle,
    textPrimary: LiftrColors.darkText,
    textSecondary: LiftrColors.darkTextSecondary,
    textMuted: LiftrColors.darkTextMuted,
    textDim: LiftrColors.darkTextDim,
    accentBg: LiftrColors.darkAccentBg,
    accentBorder: LiftrColors.darkAccentBorder,
    accentMid: LiftrColors.darkAccentMid,
    accentTextColor: LiftrColors.darkAccentText,
  );

  static const light = LiftrTheme(
    surface: LiftrColors.lightSurface,
    card: LiftrColors.lightCard,
    border: LiftrColors.lightBorder,
    borderSubtle: LiftrColors.lightBorderSubtle,
    textPrimary: LiftrColors.lightText,
    textSecondary: LiftrColors.lightTextSecondary,
    textMuted: LiftrColors.lightTextMuted,
    textDim: LiftrColors.lightTextDim,
    accentBg: LiftrColors.lightAccentBg,
    accentBorder: LiftrColors.lightAccentBorder,
    accentMid: LiftrColors.lightAccentMid,
    accentTextColor: LiftrColors.lightAccentText,
  );

  @override
  LiftrTheme copyWith({
    Color? surface,
    Color? card,
    Color? border,
    Color? borderSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textDim,
    Color? accentBg,
    Color? accentBorder,
    Color? accentMid,
    Color? accentTextColor,
    Color? danger,
  }) =>
      LiftrTheme(
        surface: surface ?? this.surface,
        card: card ?? this.card,
        border: border ?? this.border,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        textDim: textDim ?? this.textDim,
        accentBg: accentBg ?? this.accentBg,
        accentBorder: accentBorder ?? this.accentBorder,
        accentMid: accentMid ?? this.accentMid,
        accentTextColor: accentTextColor ?? this.accentTextColor,
        danger: danger ?? this.danger,
      );

  @override
  LiftrTheme lerp(LiftrTheme? other, double t) {
    if (other == null) return this;
    return LiftrTheme(
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      accentBg: Color.lerp(accentBg, other.accentBg, t)!,
      accentBorder: Color.lerp(accentBorder, other.accentBorder, t)!,
      accentMid: Color.lerp(accentMid, other.accentMid, t)!,
      accentTextColor: Color.lerp(accentTextColor, other.accentTextColor, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

// ── Shape tokens ──────────────────────────────────────────────
// Corner radii and border widths don't change between light and dark, so they
// live here as plain constants rather than in the theme extension. One entry
// per value the design already uses — these preserve the exact numbers that
// were scattered as literals, so adopting them is a rename, not a restyle.

/// Corner radii, smallest to largest.
class LiftrRadii {
  static const pip = 2.0; // progress dots
  static const inset = 7.0; // inner accent icon square
  static const tile = 8.0; // emoji tiles, calendar day cells
  static const control = 10.0; // icon buttons, set rows, inner input fields
  static const field = 12.0; // text fields and most small cards
  static const button = 14.0; // primary / cancel buttons
  static const card = 16.0; // standard cards and list rows
  static const cardLarge = 18.0; // chart card, profile identity block
  static const panel = 20.0; // chips, toggles, section containers
  static const sheet = 24.0; // workout card, bottom-sheet top

  /// `BorderRadius.circular(field)` in one call.
  static BorderRadius all(double r) => BorderRadius.circular(r);
}

/// Border stroke widths.
class LiftrBorders {
  static const hairline = 0.5; // the default divider/card outline
  static const thin = 1.0; // selected / emphasised
  static const medium = 1.5; // focused input, chart line
}

/// Layout spacing — gaps between widgets and padding inside them.
///
/// The suffix is the pixel value, so this is a rename that preserves every
/// existing gap exactly; nothing shifts. Named `xN` rather than sm/md/lg because
/// the design uses 16 distinct steps, more than a t-shirt scale can hold
/// cleanly. Applied to SizedBox spacers and EdgeInsets.all/symmetric; positional
/// fromLTRB paddings keep their literals, since they're layout-specific rather
/// than part of this rhythm.
class LiftrSpacing {
  static const x2 = 2.0;
  static const x3 = 3.0;
  static const x4 = 4.0;
  static const x5 = 5.0;
  static const x6 = 6.0;
  static const x8 = 8.0;
  static const x10 = 10.0;
  static const x12 = 12.0;
  static const x14 = 14.0;
  static const x16 = 16.0;
  static const x18 = 18.0;
  static const x20 = 20.0;
  static const x24 = 24.0;
  static const x28 = 28.0;
  static const x32 = 32.0;
  static const x36 = 36.0;
}

/// Font sizes.
///
/// Same convention as [LiftrSpacing]: the suffix is the pixel value, so
/// adopting these is a rename that preserves every existing size exactly.
/// Named `xN` rather than by role because the design uses 15 distinct steps —
/// and because the same size does different jobs in different places (13 is
/// both a set row and a button label), so a role name would be a lie at half
/// the call sites.
///
/// These are the raw scale. Where a piece of text fits one of the roles in
/// `AppTheme`'s `textTheme` — screen titles, section headers, body copy — reach
/// for `Theme.of(context).textTheme` instead; it carries colour and weight too.
/// This class is for the rest: the one-off labels, hints and chips that make up
/// most of the app's text.
class LiftrType {
  static const x9 = 9.0; // chart axis labels
  static const x10 = 10.0; // input hints, badge text
  static const x11 = 11.0; // section headers, chip labels, metadata
  static const x12 = 12.0; // secondary labels, card captions
  static const x13 = 13.0; // body text, set rows, button labels
  static const x14 = 14.0; // emphasised body, list titles
  static const x15 = 15.0; // primary buttons, field text
  static const x16 = 16.0; // card titles, stat values
  static const x18 = 18.0; // section titles
  static const x20 = 20.0; // the weight input
  static const x22 = 22.0; // screen titles (serif)
  static const x26 = 26.0; // large display (serif)
  static const x28 = 28.0; // stat headline
  static const x30 = 30.0; // onboarding emoji
  static const x32 = 32.0; // hero display (serif)
}

// ── Helper extension on BuildContext ──────────────────────────
extension LiftrThemeX on BuildContext {
  LiftrTheme get lt => Theme.of(this).extension<LiftrTheme>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get bgColor => isDark ? LiftrColors.darkBg : LiftrColors.lightBg;
}

// ── ThemeData builders ─────────────────────────────────────────
class AppTheme {
  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? LiftrColors.darkBg : LiftrColors.lightBg;
    final text = isDark ? LiftrColors.darkText : LiftrColors.lightText;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: LiftrColors.accent,
        onPrimary: LiftrColors.accentText,
        secondary: LiftrColors.accentDark,
        onSecondary: LiftrColors.accentText,
        error: LiftrColors.danger,
        onError: Colors.white,
        surface: isDark ? LiftrColors.darkSurface : LiftrColors.lightSurface,
        onSurface: text,
      ),
      fontFamily: 'DMSans',
      textTheme: TextTheme(
        displayLarge: TextStyle(
            fontFamily: 'DMSerifDisplay',
            color: text,
            fontSize: LiftrType.x32,
            fontWeight: FontWeight.w400),
        displayMedium: TextStyle(
            fontFamily: 'DMSerifDisplay',
            color: text,
            fontSize: LiftrType.x26,
            fontWeight: FontWeight.w400),
        displaySmall: TextStyle(
            fontFamily: 'DMSerifDisplay',
            color: text,
            fontSize: LiftrType.x22,
            fontWeight: FontWeight.w400),
        headlineMedium: TextStyle(
            color: text,
            fontSize: LiftrType.x18,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3),
        titleLarge: TextStyle(
            color: text, fontSize: LiftrType.x16, fontWeight: FontWeight.w500),
        titleMedium: TextStyle(
            color: text, fontSize: LiftrType.x14, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(
            color: text, fontSize: LiftrType.x15, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(
            color: text, fontSize: LiftrType.x13, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(
          color:
              isDark ? LiftrColors.darkTextMuted : LiftrColors.lightTextMuted,
          fontSize: LiftrType.x12,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: TextStyle(
          color:
              isDark ? LiftrColors.darkTextMuted : LiftrColors.lightTextMuted,
          fontSize: LiftrType.x11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.08,
        ),
      ),
      extensions: [isDark ? LiftrTheme.dark : LiftrTheme.light],
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: text),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
                .copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark
                .copyWith(statusBarColor: Colors.transparent),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bg,
        selectedItemColor: LiftrColors.accent,
        unselectedItemColor:
            isDark ? LiftrColors.darkTextDim : LiftrColors.lightTextDim,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? LiftrColors.darkCard : LiftrColors.lightCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LiftrRadii.field),
          borderSide: BorderSide(
            color: isDark ? LiftrColors.darkBorder : LiftrColors.lightBorder,
            width: LiftrBorders.hairline,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LiftrRadii.field),
          borderSide: BorderSide(
            color: isDark ? LiftrColors.darkBorder : LiftrColors.lightBorder,
            width: LiftrBorders.hairline,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LiftrRadii.field),
          borderSide: const BorderSide(
              color: LiftrColors.accent, width: LiftrBorders.medium),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x16, vertical: LiftrSpacing.x14),
        hintStyle: TextStyle(
          color: isDark ? LiftrColors.darkTextDim : LiftrColors.lightTextDim,
          fontSize: LiftrType.x14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LiftrColors.accent,
          foregroundColor: LiftrColors.accentText,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LiftrRadii.button)),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: LiftrType.x15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.01,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark
            ? LiftrColors.darkBorderSubtle
            : LiftrColors.lightBorderSubtle,
        thickness: 0.5,
        space: 0,
      ),
      cardTheme: CardThemeData(
        color: isDark ? LiftrColors.darkSurface : LiftrColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LiftrRadii.panel),
          side: BorderSide(
            color: isDark
                ? LiftrColors.darkBorderSubtle
                : LiftrColors.lightBorderSubtle,
            width: LiftrBorders.hairline,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }
}
