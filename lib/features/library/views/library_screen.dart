import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/audio_player_service.dart';
import '../../../services/download_service.dart';
import '../../../services/library_service.dart';
import '../../../services/lyrics_service.dart';
import '../../../services/palette_service.dart';
import '../../player/models/track.dart';
import '../../player/viewmodels/player_view_model.dart';
import '../../player/views/player_screen.dart';
import '../models/playlist.dart';
import '../widgets/add_to_playlist_sheet.dart';
import 'playlist_detail_screen.dart';

/// Pantalla de Biblioteca Local (Favoritos y Playlists) con estética Apple Music.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.libraryService,
    required this.audioService,
    required this.paletteService,
    required this.lyricsService,
  });

  final LibraryService libraryService;
  final AudioPlayerService audioService;
  final PaletteService paletteService;
  final LyricsService lyricsService;

  void _openPlayer(
    BuildContext context, {
    required List<Track> queue,
    int index = 0,
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

  void _openDetail(
    BuildContext context, {
    String? playlistId,
    bool isFavorites = false,
    bool isDownloads = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailScreen(
          libraryService: libraryService,
          audioService: audioService,
          paletteService: paletteService,
          lyricsService: lyricsService,
          playlistId: playlistId,
          isFavorites: isFavorites,
          isDownloads: isDownloads,
        ),
      ),
    );
  }

  Future<void> _promptCreatePlaylist(BuildContext context) async {
    final name = await PlaylistNameDialog.show(
      context,
      title: 'Nueva Playlist',
      hintText: 'Nombre de la playlist',
      confirmLabel: 'Crear',
    );

    final trimmed = name?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      await libraryService.createPlaylist(trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: Listenable.merge([libraryService, DownloadService.instance]),
      builder: (context, _) {
        final favorites = libraryService.favorites;
        final playlists = libraryService.playlists;
        final downloadedTracks = DownloadService.instance.getDownloadedTracks();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera estilo Apple Music con botón '+' para crear Playlist.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Biblioteca',
                    style: text.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Nueva Playlist',
                    onPressed: () => _promptCreatePlaylist(context),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF1C1C22),
                    ),
                    icon: const Icon(
                      Icons.add_rounded,
                      color: AppTheme.accent,
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  // Tarjeta destacada: "Canciones que te gustan"
                  _FavoritesHeroCard(
                    favoritesCount: favorites.length,
                    onTap: () => _openDetail(context, isFavorites: true),
                    onPlay: favorites.isEmpty
                        ? null
                        : () => _openPlayer(
                              context,
                              queue: favorites,
                              shuffle: false,
                            ),
                    onShuffle: favorites.isEmpty
                        ? null
                        : () => _openPlayer(
                              context,
                              queue: favorites,
                              shuffle: true,
                            ),
                  ),

                  const SizedBox(height: 12),

                  // Tarjeta destacada: "Descargas Offline"
                  _DownloadsHeroCard(
                    downloadsCount: downloadedTracks.length,
                    onTap: () => _openDetail(context, isDownloads: true),
                    onPlay: downloadedTracks.isEmpty
                        ? null
                        : () => _openPlayer(
                              context,
                              queue: downloadedTracks,
                              shuffle: false,
                            ),
                    onShuffle: downloadedTracks.isEmpty
                        ? null
                        : () => _openPlayer(
                              context,
                              queue: downloadedTracks,
                              shuffle: true,
                            ),
                  ),

                  const SizedBox(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Playlists',
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _promptCreatePlaylist(context),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.accent,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text(
                          'Nueva',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (playlists.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 32,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161C),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x16FFFFFF)),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.queue_music_rounded,
                            size: 42,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Aún no has creado playlists',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Toca el botón + para organizar tu música favorita.',
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (var i = 0; i < playlists.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 76,
                          color: Color(0x18FFFFFF),
                        ),
                      _PlaylistRowTile(
                        playlist: playlists[i],
                        onTap: () => _openDetail(
                          context,
                          playlistId: playlists[i].id,
                        ),
                        onDelete: () =>
                            libraryService.deletePlaylist(playlists[i].id),
                      ),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FavoritesHeroCard extends StatelessWidget {
  const _FavoritesHeroCard({
    required this.favoritesCount,
    required this.onTap,
    required this.onPlay,
    required this.onShuffle,
  });

  final int favoritesCount;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFA2D48),
                Color(0xFF9E1946),
                Color(0xFF3E1034),
              ],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40FA2D48),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Canciones que te gustan',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$favoritesCount ${favoritesCount == 1 ? 'pista guardada' : 'pistas guardadas'}',
                      style: text.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Aleatorio',
                onPressed: onShuffle,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                ),
                icon: const Icon(
                  Icons.shuffle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Reproducir favoritos',
                onPressed: onPlay,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                ),
                icon: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppTheme.accent,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadsHeroCard extends StatelessWidget {
  const _DownloadsHeroCard({
    required this.downloadsCount,
    required this.onTap,
    required this.onPlay,
    required this.onShuffle,
  });

  final int downloadsCount;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F766E), // Emerald/Teal oscuro
                Color(0xFF1E3A8A), // Indigo profundo
                Color(0xFF0F172A), // Slate noche
              ],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330D9488),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.arrow_circle_down_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Descargas Offline',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$downloadsCount ${downloadsCount == 1 ? 'pista disponible' : 'pistas disponibles'}',
                      style: text.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Aleatorio',
                onPressed: onShuffle,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                ),
                icon: const Icon(
                  Icons.shuffle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Reproducir descargas',
                onPressed: onPlay,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                ),
                icon: const Icon(
                  Icons.play_arrow_rounded,
                  color: Color(0xFF0F766E),
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistRowTile extends StatelessWidget {
  const _PlaylistRowTile({
    required this.playlist,
    required this.onTap,
    required this.onDelete,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cover = playlist.coverUrl;

    return Dismissible(
      key: ValueKey(playlist.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: cover != null
                    ? Image.network(
                        cover,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _PlaylistBoxIcon(),
                      )
                    : const _PlaylistBoxIcon(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${playlist.tracks.length} ${playlist.tracks.length == 1 ? 'canción' : 'canciones'}',
                      style: text.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistBoxIcon extends StatelessWidget {
  const _PlaylistBoxIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.queue_music_rounded,
        color: AppTheme.textSecondary,
        size: 28,
      ),
    );
  }
}
