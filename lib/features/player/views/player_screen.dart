import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../models/lyrics.dart';
import '../models/track.dart';
import '../viewmodels/player_view_model.dart';
import '../widgets/album_artwork.dart';
import '../widgets/blurred_background.dart';
import '../widgets/playback_controls.dart';
import '../widgets/playback_progress_bar.dart';

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
  bool _showLyrics = false;

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
                      _Header(
                        track: track,
                        showLyrics: _showLyrics,
                        onToggleLyrics: () =>
                            setState(() => _showLyrics = !_showLyrics),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          child: _showLyrics
                              ? _LyricsPanel(
                                  key: const ValueKey('lyrics'),
                                  lyrics: _vm.lyrics,
                                  isLoading: _vm.isLoadingLyrics,
                                  positionStream: _vm.positionStream,
                                  onSeek: _vm.seek,
                                )
                              : Center(
                                  key: const ValueKey('artwork'),
                                  child: AlbumArtwork(
                                    url: track.artworkUrl,
                                    isPlaying: _vm.isPlaying,
                                    glowColor: _vm.palette.primary,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                            tooltip: 'Letras',
                            onPressed: () =>
                                setState(() => _showLyrics = !_showLyrics),
                            icon: Icon(
                              Icons.lyrics_rounded,
                              color: _showLyrics
                                  ? _vm.palette.primary
                                  : AppTheme.textSecondary,
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
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.track,
    required this.showLyrics,
    required this.onToggleLyrics,
  });

  final Track track;
  final bool showLyrics;
  final VoidCallback onToggleLyrics;

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
          IconButton(
            onPressed: onToggleLyrics,
            icon: Icon(
              showLyrics ? Icons.album_rounded : Icons.format_quote_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel de letras sincronizadas estilo Apple Music.
class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel({
    super.key,
    required this.lyrics,
    required this.isLoading,
    required this.positionStream,
    required this.onSeek,
  });

  final Lyrics? lyrics;
  final bool isLoading;
  final Stream<Duration> positionStream;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final data = lyrics;
    if (data == null || data.lines.isEmpty) {
      return Center(
        child: Text(
          'Letra no disponible para esta canción',
          textAlign: TextAlign.center,
          style: text.titleMedium?.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0x26000000),
            borderRadius: BorderRadius.circular(18),
          ),
          child: StreamBuilder<Duration>(
            stream: positionStream,
            initialData: Duration.zero,
            builder: (context, snapshot) {
              final pos = snapshot.data ?? Duration.zero;
              final activeIndex = data.indexAt(pos);

              return ListView.builder(
                itemCount: data.lines.length,
                itemBuilder: (context, i) {
                  final line = data.lines[i];
                  final isActive = !data.isSynced || i == activeIndex;
                  return GestureDetector(
                    onTap: data.isSynced ? () => onSeek(line.time) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: (text.titleLarge ?? const TextStyle()).copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: isActive
                              ? Colors.white
                              : const Color(0x55FFFFFF),
                        ),
                        child: Text(
                          line.text.isEmpty ? '•••' : line.text,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
