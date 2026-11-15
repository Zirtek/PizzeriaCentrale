import 'package:flutter/material.dart';

class AppTheme {
  // Palette invariata: Bianco + Terracotta / Mattone + Accenti funzionali
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color warmSurface = Color(0xFFFBF6F3);
  static const Color cardBorder = Color(0xFFEBD8CE);

  static const Color terracottaPrimary = Color(0xFFB84221);
  static const Color brickBrownDark = Color(0xFF7D2912);
  static const Color ovenOrangeAccent = Color(0xFFE05A2B);
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
          minimumSize: const Size(48, 50),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brickBrownDark,
          side: const BorderSide(color: terracottaPrimary, width: 1.5),
          minimumSize: const Size(48, 46),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: warmSurface,
        selectedColor: terracottaPrimary,
        side: const BorderSide(color: cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(
          color: textDarkBrown,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: cardBorder,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: warmSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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