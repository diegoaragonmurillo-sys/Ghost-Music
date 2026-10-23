import 'package:material_ui/material_ui.dart';

import '../../features/library/widgets/add_to_playlist_sheet.dart';
import '../../features/player/models/track.dart';
import '../../services/audio_player_service.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../theme/app_theme.dart';
import 'track_artwork_image.dart';

/// Hoja de acciones contextuales para una pista musical.
///
/// Permite:
/// - Reproducir a continuación (`audioService.insertNext`).
/// - Añadir al final de la cola (`audioService.appendToQueue`).
/// - Añadir a favoritos / Quitar de favoritos.
/// - Añadir a una playlist.
/// - Descargar para escuchar offline.
class TrackActionSheet extends StatelessWidget {
  const TrackActionSheet({
    super.key,
    required this.track,
    this.audioService,
    this.libraryService,
  });

  final Track track;
  final AudioPlayerService? audioService;
  final LibraryService? libraryService;

  static Future<void> show(
    BuildContext context, {
    required Track track,
    AudioPlayerService? audioService,
    LibraryService? libraryService,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => TrackActionSheet(
        track: track,
        audioService: audioService,
        libraryService: libraryService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lib = libraryService ?? LibraryService.instance;
    final text = Theme.of(context).textTheme;
    final isFav = lib.isFavorite(track.id);

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Info de la canción
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TrackArtworkImage(
                  track: track,
                  width: 52,
                  height: 52,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10),
          if (audioService != null) ...[
            ListTile(
              leading: const Icon(
                Icons.playlist_play_rounded,
                color: Colors.white,
                size: 22,
              ),
              title: const Text('Reproducir a continuación'),
              onTap: () {
                audioService!.insertNext(track);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Se reproducirá a continuación'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.queue_music_rounded,
                color: Colors.white,
                size: 22,
              ),
              title: const Text('Agregar al final de la cola'),
              onTap: () {
                audioService!.appendToQueue(track);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Agregado al final de la cola'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
          ListTile(
            leading: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFav ? AppTheme.accent : Colors.white,
              size: 22,
            ),
            title: Text(isFav ? 'Quitar de favoritos' : 'Añadir a favoritos'),
            onTap: () {
              lib.toggleFavorite(track);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.playlist_add_rounded,
              color: Colors.white,
              size: 22,
            ),
            title: const Text('Añadir a una playlist'),
            onTap: () {
              Navigator.of(context).pop();
              AddToPlaylistSheet.show(
                context,
                libraryService: lib,
                track: track,
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.download_rounded,
              color: Colors.white,
              size: 22,
            ),
            title: const Text('Descargar para escuchar offline'),
            onTap: () {
              Navigator.of(context).pop();
              DownloadService.instance.downloadTrack(track);
            },
          ),
        ],
      ),
    );
  }
}
