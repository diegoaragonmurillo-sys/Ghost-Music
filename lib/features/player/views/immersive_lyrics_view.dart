import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/palette_service.dart';
import '../models/lyrics.dart';
import '../models/track.dart';
import '../viewmodels/player_view_model.dart';

/// Vista inmersiva de letras reales sincronizadas (LRCLIB) a pantalla completa.
class ImmersiveLyricsView extends StatefulWidget {
  const ImmersiveLyricsView({
    super.key,
    required this.viewModel,
  });

  final PlayerViewModel viewModel;

  /// Abre [ImmersiveLyricsView] como un Modal Bottom Sheet a pantalla completa.
  static Future<void> show(
    BuildContext context, {
    required PlayerViewModel viewModel,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => ImmersiveLyricsView(viewModel: viewModel),
    );
  }

  @override
  State<ImmersiveLyricsView> createState() => _ImmersiveLyricsViewState();
}

class _ImmersiveLyricsViewState extends State<ImmersiveLyricsView> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listViewKey = GlobalKey();

  StreamSubscription<Duration>? _positionSub;
  List<GlobalKey> _itemKeys = const [];
  String? _currentTrackId;
  int _activeIndex = -1;
  Duration _currentPosition = Duration.zero;
  double _viewportHeight = 0;

  PlayerViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onViewModelChanged);
    _syncItemKeys();
    _positionSub = _vm.positionStream.listen(_onPositionChanged);
  }

  @override
  void didUpdateWidget(covariant ImmersiveLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      _positionSub?.cancel();
      _vm.addListener(_onViewModelChanged);
      _syncItemKeys();
      _positionSub = _vm.positionStream.listen(_onPositionChanged);
    }
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _positionSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    _syncItemKeys();
    setState(() {});
  }

  void _syncItemKeys() {
    final trackId = _vm.currentTrack.id;
    final lines = _vm.lyrics?.lines ?? const <LyricLine>[];

    if (_currentTrackId != trackId || _itemKeys.length != lines.length) {
      _currentTrackId = trackId;
      _itemKeys = List.generate(lines.length, (_) => GlobalKey());
      _activeIndex = -1;
      _updateActiveLine(_currentPosition, forceScroll: true);
    }
  }

  void _onPositionChanged(Duration position) {
    if (!mounted) return;
    _currentPosition = position;
    _updateActiveLine(position);
  }

  void _updateActiveLine(Duration position, {bool forceScroll = false}) {
    final lyrics = _vm.lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) return;

    final newIndex = _findActiveIndex(position, lyrics);
    if (newIndex != _activeIndex || forceScroll) {
      setState(() {
        _activeIndex = newIndex;
      });
      if (newIndex >= 0 && lyrics.isSynced) {
        _scrollToCenter(newIndex);
      }
    }
  }

  int _findActiveIndex(Duration position, Lyrics lyrics) {
    if (!lyrics.isSynced || lyrics.lines.isEmpty) return -1;
    if (position < lyrics.lines.first.time) return 0;

    var active = 0;
    for (var i = 0; i < lyrics.lines.length; i++) {
      if (position >= lyrics.lines[i].time) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  void _scrollToCenter(int index) {
    if (index < 0 || index >= _itemKeys.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final itemContext = _itemKeys[index].currentContext;
      final listContext = _listViewKey.currentContext;

      if (itemContext != null && listContext != null) {
        final itemBox = itemContext.findRenderObject() as RenderBox?;
        final listBox = listContext.findRenderObject() as RenderBox?;
        if (itemBox != null && listBox != null && itemBox.hasSize) {
          final offsetInViewport =
              itemBox.localToGlobal(Offset.zero, ancestor: listBox);
          final itemCenter = offsetInViewport.dy + (itemBox.size.height / 2);
          final viewportCenter = listBox.size.height / 2;
          final delta = itemCenter - viewportCenter;
          final targetOffset = (_scrollController.offset + delta).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          );

          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeOutCubic,
          );
          return;
        }
      }

      // Si el elemento aún está fuera del área renderizada, estimamos su
      // posición media y luego afinamos el centrado cuando entre en pantalla.
      const estimatedItemExtent = 78.0;
      final approxOffset = (index * estimatedItemExtent).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController
          .animateTo(
            approxOffset,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
          )
          .then((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final ctx = _itemKeys[index].currentContext;
        final lCtx = _listViewKey.currentContext;
        if (ctx != null && lCtx != null && ctx.mounted && lCtx.mounted) {
          final iBox = ctx.findRenderObject() as RenderBox?;
          final lBox = lCtx.findRenderObject() as RenderBox?;
          if (iBox != null && lBox != null && iBox.hasSize) {
            final off = iBox.localToGlobal(Offset.zero, ancestor: lBox);
            final delta =
                (off.dy + iBox.size.height / 2) - (lBox.size.height / 2);
            final refined = (_scrollController.offset + delta).clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            );
            _scrollController.animateTo(
              refined,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = _vm.currentTrack;
    final palette = _vm.palette;

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Fondo continuo a pantalla completa sin cortes horizontales.
            _ContinuousGradientBackground(palette: palette),

            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ImmersiveTrackHeader(
                    track: track,
                    isPlaying: _vm.isPlaying,
                    onPlayPause: _vm.togglePlayPause,
                    onClose: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _buildLyricsContent(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricsContent() {
    if (_vm.isLoadingLyrics) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2.5,
        ),
      );
    }

    final lyrics = _vm.lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lyrics_outlined,
                size: 48,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 14),
              Text(
                'Letra sincronizada no disponible para esta canción',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final lines = lyrics.lines;

    return LayoutBuilder(
      builder: (context, constraints) {
        final newHeight = constraints.maxHeight;
        if ((_viewportHeight - newHeight).abs() > 1.0) {
          _viewportHeight = newHeight;
          if (_activeIndex >= 0 && lyrics.isSynced) {
            _scrollToCenter(_activeIndex);
          }
        }
        final symmetricPadding = _viewportHeight * 0.44;

        return ShaderMask(
          shaderCallback: (rect) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.10, 0.90, 1.0],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            key: _listViewKey,
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: 28,
              vertical: symmetricPadding,
            ),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final isActive = !lyrics.isSynced || index == _activeIndex;

              return KeyedSubtree(
                key: _itemKeys[index],
                child: _ImmersiveLyricItem(
                  line: line,
                  isActive: isActive,
                  onTap: lyrics.isSynced ? () => _vm.seek(line.time) : null,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Degradado continuo (`double.infinity` x `double.infinity`) generado con la paleta.
class _ContinuousGradientBackground extends StatelessWidget {
  const _ContinuousGradientBackground({required this.palette});

  final ArtworkPalette palette;

  @override
  Widget build(BuildContext context) {
    final midColor = Color.lerp(palette.primary, palette.secondary, 0.50) ??
        palette.secondary;
    final deepShade =
        Color.lerp(palette.secondary, AppTheme.background, 0.65) ??
            AppTheme.background;

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: AnimatedContainer(
        width: double.infinity,
        height: double.infinity,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.primary,
              midColor,
              palette.secondary,
              deepShade,
              AppTheme.background,
            ],
            stops: const [0.0, 0.28, 0.56, 0.84, 1.0],
          ),
        ),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x22000000),
                Color(0x3D000000),
                Color(0x66000000),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImmersiveTrackHeader extends StatelessWidget {
  const _ImmersiveTrackHeader({
    required this.track,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onClose,
  });

  final Track track;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Image.network(
                track.artworkUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: Colors.white12,
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white70,
                  ),
                ),
              ),
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
                  style: textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isPlaying ? 'Pausar' : 'Reproducir',
            onPressed: onPlayPause,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          IconButton(
            tooltip: 'Cerrar letras',
            onPressed: onClose,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.14),
            ),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }
}

/// Línea de letra con estilo activo (blanco puro, 26px, negrita) e inactivo
/// (50% opacidad y ligeramente atenuado).
class _ImmersiveLyricItem extends StatelessWidget {
  const _ImmersiveLyricItem({
    required this.line,
    required this.isActive,
    this.onTap,
  });

  final LyricLine line;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final targetBlur = isActive ? 0.0 : 1.2;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: targetBlur, end: targetBlur),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (context, sigma, child) {
            return ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
              ),
              child: child,
            );
          },
          child: AnimatedScale(
            scale: isActive ? 1.0 : 0.95,
            alignment: Alignment.centerLeft,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: isActive ? 26 : 21,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                height: 1.28,
                letterSpacing: -0.4,
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.50),
                shadows: isActive
                    ? const [
                        Shadow(
                          color: Color(0x55000000),
                          blurRadius: 14,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : const [],
              ),
              child: Text(line.text),
            ),
          ),
        ),
      ),
    );
  }
}
