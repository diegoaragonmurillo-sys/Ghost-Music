import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../library/widgets/add_to_playlist_sheet.dart';
import '../models/track.dart';
import '../viewmodels/player_view_model.dart';
import '../widgets/album_artwork.dart';
import '../widgets/blurred_background.dart';
import '../widgets/playback_controls.dart';
import '../widgets/playback_progress_bar.dart';
import 'immersive_lyrics_view.dart';

/// Pantalla "Now Playing" (Vista en MVVM). Solo renderiza estado del
/// [PlayerViewModel] y le delega las acciones del usuario.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.viewModel,
  });

  final PlayerViewModel viewModel;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  PlayerViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.init();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  void _openImmersiveLyrics() {
    ImmersiveLyricsView.show(context, viewModel: _vm);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          final track = _vm.currentTrack;
          return SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                BlurredBackground(
                  artworkUrl: track.artworkUrl,
                  palette: _vm.palette,
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        _Header(track: track),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Center(
                            child: AlbumArtwork(
                              url: track.artworkUrl,
                              isPlaying: _vm.isPlaying,
                              glowColor: _vm.palette.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Título + artista + acciones de Favorito y Añadir a Playlist.
                        Row(
                          children: [
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Column(
                                  key: ValueKey(track.id),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.titleMedium?.copyWith(
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: _vm.isCurrentTrackFavorite
                                  ? 'Quitar de favoritos'
                                  : 'Añadir a favoritos',
                              onPressed: _vm.toggleCurrentTrackFavorite,
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(scale: anim, child: child),
                                child: Icon(
                                  _vm.isCurrentTrackFavorite
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  key: ValueKey(_vm.isCurrentTrackFavorite),
                                  color: _vm.isCurrentTrackFavorite
                                      ? AppTheme.accent
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Añadir a una playlist',
                              onPressed: () => AddToPlaylistSheet.show(
                                context,
                                libraryService: _vm.libraryService,
                                track: track,
                              ),
                              icon: const Icon(
                                Icons.playlist_add_rounded,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        PlaybackProgressBar(
                          progressStream: _vm.progressStream,
                          onSeek: _vm.seek,
                        ),
                        const SizedBox(height: 14),
                        PlaybackControls(
                          isPlaying: _vm.isPlaying,
                          isLoading: _vm.isLoading,
                          shuffle: _vm.shuffle,
                          loopMode: _vm.loopMode,
                          accentColor: _vm.palette.primary,
                          onPlayPause: _vm.togglePlayPause,
                          onNext: _vm.next,
                          onPrevious: _vm.previous,
                          onShuffle: _vm.toggleShuffle,
                          onRepeat: _vm.cycleLoopMode,
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _openImmersiveLyrics,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            shape: const StadiumBorder(),
                          ),
                          icon: const Icon(Icons.lyrics_rounded, size: 18),
                          label: const Text(
                            'Letras sincronizadas',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (_vm.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _vm.error!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: text.bodySmall
                                  ?.copyWith(color: Colors.redAccent),
                            ),
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'REPRODUCIENDO AHORA',
                  style: text.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
