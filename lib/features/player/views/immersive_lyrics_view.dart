import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/palette_service.dart';
import '../models/lyrics.dart';
import '../models/track.dart';
import '../viewmodels/player_view_model.dart';

/// Vista inmersiva de letras reales sincronizadas (LRCLIB) a pantalla completa
/// con motor de reloj a 60FPS (ticks de 50ms), lookahead predictivo de 250ms
/// y `ScrollablePositionedList`.
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
  static const Duration _tickInterval = Duration(milliseconds: 50);
  static const Duration _lookaheadOffset = Duration(milliseconds: 250);

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  StreamSubscription<int>? _tickSub;
  StreamSubscription<Duration>? _positionSub;

  /// Índice de la línea activa actual (deduplicado para evitar scrolls redundantes).
  int _currentIndex = 0;

  /// Offset manual en milisegundos para compensar canciones con intros largos.
  int manualOffsetMs = 0;

  Duration _latestStreamPosition = Duration.zero;
  String? _currentTrackId;

  PlayerViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _currentTrackId = _vm.currentTrack.id;
    _latestStreamPosition = _vm.currentPosition;
    _vm.addListener(_onViewModelChanged);

    // Escucha el stream nativo y lo combina con un reloj de alta frecuencia (50ms).
    _positionSub = _vm.positionStream.listen((pos) {
      _latestStreamPosition = pos;
    });

    _tickSub = Stream<int>.periodic(_tickInterval, (tick) => tick).listen((_) {
      _onTick();
    });
  }

  @override
  void didUpdateWidget(covariant ImmersiveLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      _positionSub?.cancel();
      _vm.addListener(_onViewModelChanged);
      _latestStreamPosition = _vm.currentPosition;
      _positionSub = _vm.positionStream.listen((pos) {
        _latestStreamPosition = pos;
      });
    }
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _tickSub?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    final trackId = _vm.currentTrack.id;
    if (_currentTrackId != trackId) {
      _currentTrackId = trackId;
      _currentIndex = 0;
    }
    setState(() {});
  }

  /// Motor de reloj de 50ms con Lookahead (-250ms sobre el umbral de la línea)
  /// y soporte para [manualOffsetMs].
  void _onTick() {
    if (!mounted) return;
    final lyrics = _vm.lyrics;
    if (lyrics == null || !lyrics.isSynced || lyrics.lines.isEmpty) return;

    // Combina la posición directa del motor de audio con el último valor del stream.
    final livePosition = _vm.currentPosition;
    final basePosition = livePosition > Duration.zero
        ? livePosition
        : _latestStreamPosition;

    // Suma el offset manual global antes de calcular el índice.
    final positionWithManualOffset =
        basePosition + Duration(milliseconds: manualOffsetMs);

    final newIndex = _computeActiveIndex(
      positionWithManualOffset,
      lyrics.lines,
    );

    if (newIndex != _currentIndex) {
      setState(() {
        _currentIndex = newIndex;
      });
      _scrollToActiveIndex(newIndex);
    }
  }

  /// Calcula la línea activa aplicando el lookahead de 250ms para anticipar
  /// la animación visual antes de que el artista cante la frase.
  int _computeActiveIndex(Duration audioPosition, List<LyricLine> lines) {
    if (lines.isEmpty) return 0;

    var candidate = 0;
    for (var i = 0; i < lines.length; i++) {
      // Se resta 250ms al timestamp de la línea para que la animación de UI
      // arranque un instante antes de que se cante.
      final triggerTime = lines[i].time - _lookaheadOffset;
      if (audioPosition >= triggerTime) {
        candidate = i;
      } else {
        break;
      }
    }
    return candidate;
  }

  void _scrollToActiveIndex(int index) {
    if (!_itemScrollController.isAttached) return;
    _itemScrollController.scrollTo(
      index: index,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
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
        final verticalPadding = constraints.maxHeight * 0.45;

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
          child: ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: 28,
              vertical: verticalPadding,
            ),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final isActive = !lyrics.isSynced || index == _currentIndex;

              return _ImmersiveLyricItem(
                line: line,
                isActive: isActive,
                onTap: lyrics.isSynced
                    ? () {
                        setState(() {
                          _currentIndex = index;
                        });
                        _vm.seek(line.time);
                        _scrollToActiveIndex(index);
                      }
                    : null,
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

/// Línea de letra con soporte para pausas instrumentales vacías y estilo
/// activo (blanco puro, 26px, negrita) vs inactivo (50% opacidad, atenuado).
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
    final isInstrumentalBreak = line.text.isEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: isInstrumentalBreak ? 18 : 14,
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: targetBlur, end: targetBlur),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
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
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
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
              child: isInstrumentalBreak
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.more_horiz_rounded,
                          size: isActive ? 32 : 24,
                          color: isActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.40),
                        ),
                      ],
                    )
                  : Text(line.text),
            ),
          ),
        ),
      ),
    );
  }
}
