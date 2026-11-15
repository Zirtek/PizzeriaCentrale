import 'package:flutter/material.dart';

class AppTheme {
  // Sfondo nero e superfici scure
  static const Color backgroundBlack = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF141414);
  static const Color surfaceElevated = Color(0xFF1F1F1F);
  static const Color cardBorder = Color(0xFF2E2E2E);

  // Testi su sfondo scuro
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFFB0B0B0);

  // Colori semantici richiesti
  static const Color moneyGreen = Color(0xFF00E676); // Conti soldi & Completati
  static const Color completedGreen = Color(0xFF00E676);
  static const Color toCompleteYellow = Color(0xFFFFD60A); // Da completare / In corso / Da incassare
  static const Color toStartRed = Color(0xFFE53935); // Da iniziare / Nuovo ordine / Ritardo

  // Tinte scure per box informativi
  static const Color darkGreenTint = Color(0xFF0A2918);
  static const Color darkYellowTint = Color(0xFF292205);
  static const Color darkRedTint = Color(0xFF2E0D0D);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundBlack,
      colorScheme: const ColorScheme.dark(
        primary: moneyGreen,
        onPrimary: Colors.black,
        secondary: toCompleteYellow,
        onSecondary: Colors.black,
        surface: surfaceDark,
        onSurface: textWhite,
        error: toStartRed,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceDark,
        foregroundColor: textWhite,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: cardBorder, width: 1.2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceDark,
        titleTextStyle: const TextStyle(
          color: textWhite,
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(color: textWhite, fontSize: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: cardBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: moneyGreen,
          foregroundColor: Colors.black,
          minimumSize: const Size(48, 50),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textWhite,
          side: const BorderSide(color: cardBorder, width: 1.5),
          minimumSize: const Size(48, 46),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return toCompleteYellow;
            }
            return surfaceDark;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.black;
            }
            return textWhite;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: cardBorder)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceDark,
        selectedColor: toCompleteYellow,
        side: const BorderSide(color: cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(
          color: textWhite,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: cardBorder,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: textMuted),
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
          borderSide: const BorderSide(color: toCompleteYellow, width: 2),
        ),
      ),
    );
  }
}