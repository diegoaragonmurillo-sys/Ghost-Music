import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/palette_service.dart';

/// Fondo inmersivo estilo Apple Music:
/// carátula escalada + desenfoque gaussiano fuerte + gradiente teñido con la
/// paleta extraída. Las transiciones entre pistas se animan suavemente.
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
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Gradiente base con la paleta (anima el cambio de color).
        AnimatedContainer(
          duration: _duration,
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.primary, palette.secondary, AppTheme.background],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),

        // 2. Carátula difuminada (cross-fade entre pistas).
        AnimatedSwitcher(
          duration: _duration,
          child: ImageFiltered(
            key: ValueKey(artworkUrl),
            imageFilter: ImageFilter.blur(
              sigmaX: 70,
              sigmaY: 70,
              tileMode: TileMode.mirror,
            ),
            child: Transform.scale(
              scale: 1.6,
              child: Opacity(
                opacity: 0.55,
                child: Image.network(
                  artworkUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),

        // 3. Viñeta oscura inferior para legibilidad de controles.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x99000000), Color(0xE6000000)],
              stops: [0.0, 0.6, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}
