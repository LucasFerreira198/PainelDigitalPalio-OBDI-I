import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../settings/app_settings.dart';

class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF070709);
  static const Color surface = Color(0xFF141419);
  static const Color surfaceElevated = Color(0xFF1C1C24);
  static const Color cardBorder = Color(0x1FFFFFFF);
  static const Color accent = Color(0xFFFF6A00); // Padrão Fiat Sport
  static const Color danger = Color(0xFFFF3B30);
  static const Color warning = Color(0xFFFFCC00);
  static const Color success = Color(0xFF34C759);
  
  static const Color gaugeIdle = Color(0xFF2C2C35);
  static const Color gaugeNormal = Color(0xFF2ECC71);
  static const Color gaugeWarning = Color(0xFFF1C40F);
  static const Color gaugeDanger = Color(0xFFE53935);

  static ThemeData themeFor(ClusterTheme clusterTheme) {
    final base = ThemeData.dark(useMaterial3: true);
    final primaryColor = clusterTheme.accent;

    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: base.colorScheme.copyWith(
        primary: primaryColor,
        surface: surface,
        error: danger,
      ),
      cardTheme: CardTheme(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
      ),
      textTheme: GoogleFonts.rajdhaniTextTheme(base.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }

  static ThemeData get dark => themeFor(ClusterTheme.fiatOrange);

  static TextStyle digitalDisplay({
    double fontSize = 48,
    Color? color,
    FontWeight fontWeight = FontWeight.bold,
  }) =>
      GoogleFonts.orbitron(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? Colors.white,
        letterSpacing: 1.5,
      );

  static BoxDecoration cockpitCardDecoration({
    Color? borderColor,
    bool glowing = false,
    Color? glowColor,
  }) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: borderColor ?? cardBorder,
        width: glowing ? 1.5 : 1.0,
      ),
      boxShadow: glowing && glowColor != null
          ? [
              BoxShadow(
                color: glowColor.withOpacity(0.25),
                blurRadius: 10,
                spreadRadius: 1,
              )
            ]
          : null,
    );
  }
}
