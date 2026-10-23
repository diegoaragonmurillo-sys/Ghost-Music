import 'package:material_ui/material_ui.dart';

/// Carátula del álbum con sombra teñida y efecto "respiración":
/// se contrae ligeramente al pausar y crece al reproducir (como Apple Music).
class AlbumArtwork extends StatelessWidget {
  const AlbumArtwork({
    super.key,
    required this.url,
    required this.isPlaying,
    required this.glowColor,
  });

  final String url;
  final bool isPlaying;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedScale(
        scale: isPlaying ? 1.0 : 0.82,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: isPlaying ? 0.55 : 0.25),
                blurRadius: isPlaying ? 50 : 24,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Image.network(
                url,
                key: ValueKey(url),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const ColoredBox(
                        color: Color(0x22FFFFFF),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0x22FFFFFF),
                  child: Center(child: Icon(Icons.music_note_rounded, size: 64)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
