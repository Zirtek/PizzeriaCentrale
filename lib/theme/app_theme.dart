import 'package:flutter/material.dart';

class AppTheme {
  // Palette: Bianco + Arancione mischiato al rosso tendente al marrone (Terracotta / Mattone)
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color warmSurface = Color(0xFFFBF6F3);
  static const Color cardBorder = Color(0xFFEBD8CE);

  static const Color terracottaPrimary = Color(0xFFB84221); // Arancione-rosso-marrone
  static const Color brickBrownDark = Color(0xFF7D2912);    // Marrone-rosso caldo
  static const Color ovenOrangeAccent = Color(0xFFE05A2B);  // Arancione vivo
  static const Color textDarkBrown = Color(0xFF2B1914);
  static const Color textMutedBrown = Color(0xFF6E534B);

  static const Color delayAlertRed = Color(0xFFC62828);
  static const Color paidGreen = Color(0xFF2E7D32);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundWhite,
      colorScheme: ColorScheme.fromSeed(
        seedColor: terracottaPrimary,
        primary: terracottaPrimary,
        secondary: ovenOrangeAccent,
        surface: backgroundWhite,
        onSurface: textDarkBrown,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: terracottaPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: warmSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: cardBorder, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: terracottaPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brickBrownDark,
          side: const BorderSide(color: terracottaPrimary, width: 1.5),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: warmSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: terracottaPrimary, width: 2),
        ),
      ),
    );
  }
}