import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/audio_player_service.dart';
import '../viewmodels/player_view_model.dart';
import '../widgets/album_artwork.dart';
import '../widgets/blurred_background.dart';
import '../widgets/playback_controls.dart';
import '../widgets/playback_progress_bar.dart';

/// Pantalla "Now Playing" (Vista en MVVM). Solo renderiza estado del
/// [PlayerViewModel] y le delega las acciones del usuario.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.audioService, this.viewModel});

  /// Servicio de audio compartido (conectado al Background Service).
  final AudioPlayerService audioService;

  /// Inyectable para tests; si es null se crea uno por defecto.
  final PlayerViewModel? viewModel;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final PlayerViewModel _vm =
      widget.viewModel ?? PlayerViewModel(audioService: widget.audioService);

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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          final track = _vm.currentTrack;
          return Stack(
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
                      _Header(album: track.album),
                      const Spacer(),
                      AlbumArtwork(
                        url: track.artworkUrl,
                        isPlaying: _vm.isPlaying,
                        glowColor: _vm.palette.primary,
                      ),
                      const Spacer(),
                      // Título + artista (jerarquía tipográfica Apple Music).
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
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.favorite_border_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      PlaybackProgressBar(
                        progressStream: _vm.progressStream,
                        onSeek: _vm.seek,
                      ),
                      const SizedBox(height: 16),
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
                      if (_vm.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _vm.error!,
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(color: Colors.redAccent),
                          ),
                        ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.album});

  final String album;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'REPRODUCIENDO DESDE EL ÁLBUM',
                  style: text.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
    );
  }
}
