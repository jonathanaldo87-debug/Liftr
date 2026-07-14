import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Brand Colors ──────────────────────────────────────────────
class LiftrColors {
  // Accent — lime green (same in both modes)
  static const accent = Color(0xFFC8F075);
  static const accentDark = Color(0xFF80E850);
  static const accentText = Color(0xFF0F1A04); // text ON accent bg

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
    Color? surface, Color? card, Color? border, Color? borderSubtle,
    Color? textPrimary, Color? textSecondary, Color? textMuted, Color? textDim,
    Color? accentBg, Color? accentBorder, Color? accentMid, Color? accentTextColor,
  }) => LiftrTheme(
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
    );
  }
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
        error: const Color(0xFFE24B4A),
        onError: Colors.white,
        surface: isDark ? LiftrColors.darkSurface : LiftrColors.lightSurface,
        onSurface: text,
      ),
      fontFamily: 'DMSans',
      textTheme: TextTheme(
        displayLarge: TextStyle(fontFamily: 'DMSerifDisplay', color: text, fontSize: 32, fontWeight: FontWeight.w400),
        displayMedium: TextStyle(fontFamily: 'DMSerifDisplay', color: text, fontSize: 26, fontWeight: FontWeight.w400),
        displaySmall: TextStyle(fontFamily: 'DMSerifDisplay', color: text, fontSize: 22, fontWeight: FontWeight.w400),
        headlineMedium: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: -0.3),
        titleLarge: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w500),
        titleMedium: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(
          color: isDark ? LiftrColors.darkTextMuted : LiftrColors.lightTextMuted,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: TextStyle(
          color: isDark ? LiftrColors.darkTextMuted : LiftrColors.lightTextMuted,
          fontSize: 11,
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
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bg,
        selectedItemColor: LiftrColors.accent,
        unselectedItemColor: isDark ? LiftrColors.darkTextDim : LiftrColors.lightTextDim,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? LiftrColors.darkCard : LiftrColors.lightCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? LiftrColors.darkBorder : LiftrColors.lightBorder,
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? LiftrColors.darkBorder : LiftrColors.lightBorder,
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LiftrColors.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(
          color: isDark ? LiftrColors.darkTextDim : LiftrColors.lightTextDim,
          fontSize: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LiftrColors.accent,
          foregroundColor: LiftrColors.accentText,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.01,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? LiftrColors.darkBorderSubtle : LiftrColors.lightBorderSubtle,
        thickness: 0.5,
        space: 0,
      ),
      cardTheme: CardThemeData(
        color: isDark ? LiftrColors.darkSurface : LiftrColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark ? LiftrColors.darkBorderSubtle : LiftrColors.lightBorderSubtle,
            width: 0.5,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }
}
