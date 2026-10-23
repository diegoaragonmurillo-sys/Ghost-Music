import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/palette_service.dart';

/// Fondo inmersivo estilo Apple Music:
/// Degradado continuo a pantalla completa (`double.infinity` en ancho y alto)
/// generado dinámicamente con la paleta de la carátula, sin cortes horizontales.
class BlurredBackground extends StatelessWidget {
  const BlurredBackground({
    super.key,
    required this.artworkUrl,
    required this.palette,
  });

  final String artworkUrl;
  final ArtworkPalette palette;

  static const _duration = Duration(milliseconds: 900);

  @override
  Widget build(BuildContext context) {
    final midColor = Color.lerp(palette.primary, palette.secondary, 0.55) ??
        palette.secondary;
    final deepColor = Color.lerp(palette.secondary, AppTheme.background, 0.72) ??
        AppTheme.background;

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: AnimatedContainer(
        width: double.infinity,
        height: double.infinity,
        duration: _duration,
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.primary,
              midColor,
              palette.secondary,
              deepColor,
              AppTheme.background,
            ],
            stops: const [0.0, 0.28, 0.56, 0.82, 1.0],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -0.35),
              radius: 1.25,
              colors: [
                palette.primary.withValues(alpha: 0.38),
                palette.secondary.withValues(alpha: 0.18),
                const Color(0x99000000),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
