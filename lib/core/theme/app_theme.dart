import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tema oscuro global de Ghost Music.
///
/// Tipografía Inter (similar a SF Pro de Apple Music) con pesos altos para
/// títulos y alto contraste sobre fondos difuminados.
abstract final class AppTheme {
  static const Color background = Color(0xFF0A0A0C);
  static const Color accent = Color(0xFFFA2D48); // rojo estilo Apple Music
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xB3FFFFFF); // 70 %

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: background,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        activeTrackColor: textPrimary,
        inactiveTrackColor: Color(0x33FFFFFF),
        thumbColor: textPrimary,
        overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
      ),
      iconTheme: const IconThemeData(color: textPrimary),
    );
  }
}
