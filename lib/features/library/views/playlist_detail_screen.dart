import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/widgets/track_artwork_image.dart';
import '../../../services/audio_player_service.dart';
import '../../../services/download_service.dart';
import '../../../services/library_service.dart';
import '../../../services/lyrics_service.dart';
import '../../../services/palette_service.dart';
import '../../downloads/widgets/download_button.dart';
import '../../player/models/track.dart';
import '../../player/viewmodels/player_view_model.dart';
import '../../player/views/player_screen.dart';
import '../widgets/add_to_playlist_sheet.dart';

/// Vista de detalle para "Canciones que te gustan" (Favoritos),
/// "Descargas Offline" o una [Playlist] específica.
class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.libraryService,
    required this.audioService,
    required this.paletteService,
    required this.lyricsService,
    this.playlistId,
    this.isFavorites = false,
    this.isDownloads = false,
  });

  final LibraryService libraryService;
  final AudioPlayerService audioService;
  final PaletteService paletteService;
  final LyricsService lyricsService;
  final String? playlistId;
  final bool isFavorites;
  final bool isDownloads;

  void _openPlayer(
    BuildContext context, {
    required List<Track> queue,
    required int index,
    bool shuffle = false,
  }) {
    if (queue.isEmpty) return;
    audioService.setShuffle(shuffle);
    final startIndex =
        shuffle ? math.Random().nextInt(queue.length) : index;

    final vm = PlayerViewModel(
      audioService: audioService,
      paletteService: paletteService,
      lyricsService: lyricsService,
      libraryService: libraryService,
      queue: queue,
      initialIndex: startIndex,
    );

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            PlayerScreen(viewModel: vm),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _promptRenamePlaylist(
    BuildContext context,
    String id,
    String currentName,
  ) async {
    final newName = await PlaylistNameDialog.show(
      context,
      title: 'Renombrar Playlist',
      hintText: 'Nuevo nombre',
      confirmLabel: 'Guardar',
      initialValue: currentName,
    );

    final trimmed = newName?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      await libraryService.renamePlaylist(id, trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: Listenable.merge([libraryService, DownloadService.instance]),
      builder: (context, _) {
        final playlist =
            playlistId != null ? libraryService.getPlaylistById(playlistId!) : null;

        if (!isFavorites && !isDownloads && playlist == null) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(backgroundColor: AppTheme.background),
            body: const Center(child: Text('Esta playlist ya no existe.')),
          );
        }

        final String title;
        final List<Track> tracks;
        if (isFavorites) {
          title = 'Canciones que te gustan';
          tracks = libraryService.favorites;
        } else if (isDownloads) {
          title = 'Descargas Offline';
          tracks = DownloadService.instance.downloadedTracks;
        } else {
          title = playlist!.name;
          tracks = playlist.tracks;
        }

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            ),
            actions: [
              if (!isFavorites && !isDownloads && playlist != null)
                PopupMenuButton<String>(
                  color: const Color(0xFF1C1C22),
                  onSelected: (action) async {
                    if (action == 'rename') {
                      await _promptRenamePlaylist(
                        context,
                        playlist.id,
                        playlist.name,
                      );
                    } else if (action == 'delete') {
                      final nav = Navigator.of(context);
                      await libraryService.deletePlaylist(playlist.id);
                      if (nav.mounted) nav.pop();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Renombrar'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppTheme.accent,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Eliminar playlist',
                            style: TextStyle(color: AppTheme.accent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    children: [
                      // Portada destacada estilo Apple Music.
                      Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 28,
                              offset: Offset(0, 12),
                            ),
                          ],
                          gradient: isFavorites
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFFA2D48),
                                    Color(0xFF8C144E),
                                  ],
                                )
                              : (isDownloads
                                  ? const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF007A6E),
                                        Color(0xFF132F3D),
                                      ],
                                    )
                                  : const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF2B2B36),
                                        Color(0xFF17171D),
                                      ],
                                    )),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: isFavorites
                              ? const Center(
                                  child: Icon(
                                    Icons.favorite_rounded,
                                    size: 84,
                                    color: Colors.white,
                                  ),
                                )
                              : (isDownloads
                                  ? const Center(
                                      child: Icon(
                                        Icons.download_done_rounded,
                                        size: 84,
                                        color: Colors.white,
                                      ),
                                    )
                                  : (tracks.isNotEmpty
                                      ? TrackArtworkImage(
                                          track: tracks.first,
                                          fit: BoxFit.cover,
                                          errorWidget: const Center(
                                            child: Icon(
                                              Icons.queue_music_rounded,
                                              size: 72,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        )
                                      : const Center(
                                          child: Icon(
                                            Icons.queue_music_rounded,
                                            size: 72,
                                            color: Colors.white70,
                                          ),
                                        ))),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tracks.length} ${tracks.length == 1 ? 'canción' : 'canciones'}',
                        style: text.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Botones de acción rápida: Reproducir y Aleatorio (Shuffle).
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: tracks.isEmpty
                                  ? null
                                  : () => _openPlayer(
                                        context,
                                        queue: tracks,
                                        index: 0,
                                        shuffle: false,
                                      ),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    const Color(0xFF1C1C22),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text(
                                'Reproducir',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: tracks.isEmpty
                                  ? null
                                  : () => _openPlayer(
                                        context,
                                        queue: tracks,
                                        index: 0,
                                        shuffle: true,
                                      ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1C1C22),
                                foregroundColor: AppTheme.accent,
                                disabledBackgroundColor:
                                    const Color(0xFF141418),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.shuffle_rounded),
                              label: const Text(
                                'Aleatorio',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (tracks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Text(
                        isFavorites
                            ? 'Marca canciones con el corazón para verlas aquí.'
                            : (isDownloads
                                ? 'No tienes canciones descargadas.\nToca el botón de descarga en cualquier pista para escucharla sin conexión.'
                                : 'Esta playlist está vacía. Añade canciones desde el buscador o el reproductor.'),
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
                  sliver: SliverList.separated(
                    itemCount: tracks.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      indent: 70,
                      color: Color(0x18FFFFFF),
                    ),
                    itemBuilder: (context, index) {
                      final track = tracks[index];

                      return Dismissible(
                        key: ValueKey('${title}_${track.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                        onDismissed: (_) {
                          if (isFavorites) {
                            libraryService.toggleFavorite(track);
                          } else if (isDownloads) {
                            DownloadService.instance.deleteDownload(track.id);
                          } else if (playlist != null) {
                            libraryService.removeTrackFromPlaylist(
                              playlist.id,
                              track.id,
                            );
                          }
                        },
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 4),
                          onTap: () => _openPlayer(
                            context,
                            queue: tracks,
                            index: index,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: TrackArtworkImage(
                              track: track,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                            ),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            [
                              track.artist,
                              if (track.duration != null)
                                formatDuration(track.duration!),
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DownloadButton(track: track),
                              if (!isFavorites && !isDownloads)
                                IconButton(
                                  tooltip: 'Añadir a otra playlist',
                                  onPressed: () => AddToPlaylistSheet.show(
                                    context,
                                    libraryService: libraryService,
                                    track: track,
                                  ),
                                  icon: const Icon(
                                    Icons.playlist_add_rounded,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              IconButton(
                                tooltip: isFavorites
                                    ? 'Quitar de favoritos'
                                    : (isDownloads
                                        ? 'Eliminar descarga'
                                        : 'Quitar de la playlist'),
                                onPressed: () {
                                  if (isFavorites) {
                                    libraryService.toggleFavorite(track);
                                  } else if (isDownloads) {
                                    DownloadService.instance
                                        .deleteDownload(track.id);
                                  } else if (playlist != null) {
                                    libraryService.removeTrackFromPlaylist(
                                      playlist.id,
                                      track.id,
                                    );
                                  }
                                },
                                icon: Icon(
                                  isFavorites
                                      ? Icons.favorite_rounded
                                      : Icons.remove_circle_outline_rounded,
                                  color: isFavorites
                                      ? AppTheme.accent
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
