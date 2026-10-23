import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/track_artwork_image.dart';
import '../../../services/palette_service.dart';
import '../models/lyrics.dart';
import '../models/track.dart';
import '../viewmodels/player_view_model.dart';

/// Vista inmersiva de letras reales sincronizadas (LRCLIB) a pantalla completa
/// con motor visual a 60/120FPS, reloj continuo interpolado de alta precisión,
/// física de scroll orgánico estilo Apple Music Sing y compensación de desfases.
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
  static const Duration _tickInterval = Duration(milliseconds: 33);
  static const Duration _lookaheadOffset = Duration(milliseconds: 250);

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  StreamSubscription<int>? _tickSub;
  StreamSubscription<Duration>? _positionSub;

  /// Cronómetro de alta frecuencia para interpolar de manera continua
  /// los intervalos discretos (~200ms) del stream de just_audio sin jitter.
  final Stopwatch _interpolatedWatch = Stopwatch();
  Duration _anchorPosition = Duration.zero;
  Duration _latestStreamPosition = Duration.zero;

  /// Índice de la línea activa actual (-1 si aún está en la intro instrumental).
  int _currentIndex = -1;

  /// Offset manual en milisegundos persistido por canción en SharedPreferences.
  int manualOffsetMs = 0;

  /// Panel de ajuste fino de sincronización visible/oculto.
  bool _showSyncPanel = false;

  /// Detección de scroll táctil del usuario para suspender el auto-scroll
  /// durante 3.5 segundos y evitar tirones.
  bool _isUserScrolling = false;
  Timer? _userScrollTimer;

  String? _currentTrackId;

  PlayerViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _currentTrackId = _vm.currentTrack.id;
    _latestStreamPosition = _vm.currentPosition;
    _anchorPosition = _vm.currentPosition;
    if (_vm.isPlaying) {
      _interpolatedWatch.start();
    }
    _loadPersistedOffset(_vm.currentTrack.id);
    _vm.addListener(_onViewModelChanged);

    // Escucha el stream de audio nativo y resetea el reloj interpolado continuo.
    _positionSub = _vm.positionStream.listen((pos) {
      _latestStreamPosition = pos;
      _anchorPosition = pos;
      _interpolatedWatch.reset();
      if (_vm.isPlaying && !_interpolatedWatch.isRunning) {
        _interpolatedWatch.start();
      }
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
      _anchorPosition = _vm.currentPosition;
      _interpolatedWatch.reset();
      if (_vm.isPlaying) _interpolatedWatch.start();
      _positionSub = _vm.positionStream.listen((pos) {
        _latestStreamPosition = pos;
        _anchorPosition = pos;
        _interpolatedWatch.reset();
        if (_vm.isPlaying && !_interpolatedWatch.isRunning) {
          _interpolatedWatch.start();
        }
      });
      _loadPersistedOffset(_vm.currentTrack.id);
    }
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _tickSub?.cancel();
    _positionSub?.cancel();
    _userScrollTimer?.cancel();
    _interpolatedWatch.stop();
    super.dispose();
  }

  Future<void> _loadPersistedOffset(String trackId) async {
    final saved = await _vm.lyricsService.getTrackOffsetMs(trackId);
    if (!mounted || _currentTrackId != trackId) return;
    setState(() {
      manualOffsetMs = saved != 0
          ? saved
          : (_vm.lyrics?.suggestedOffsetMs ?? 0);
    });
  }

  Future<void> _updateOffset(int newOffsetMs) async {
    setState(() {
      manualOffsetMs = newOffsetMs;
    });
    await _vm.lyricsService.setTrackOffsetMs(_vm.currentTrack.id, newOffsetMs);
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    final trackId = _vm.currentTrack.id;
    if (_currentTrackId != trackId) {
      _currentTrackId = trackId;
      _currentIndex = -1;
      _anchorPosition = _vm.currentPosition;
      _interpolatedWatch.reset();
      _loadPersistedOffset(trackId);
    }

    if (_vm.isPlaying) {
      if (!_interpolatedWatch.isRunning) _interpolatedWatch.start();
    } else {
      if (_interpolatedWatch.isRunning) _interpolatedWatch.stop();
    }

    setState(() {});
  }

  /// Calcula la posición temporal continua sumando el avance del cronómetro
  /// de alta precisión para evitar cualquier salto visual entre actualizaciones de audio.
  Duration _getEffectivePosition() {
    final elapsed = _interpolatedWatch.isRunning
        ? _interpolatedWatch.elapsed
        : Duration.zero;
    final base = _anchorPosition > Duration.zero
        ? _anchorPosition
        : (_latestStreamPosition > Duration.zero
            ? _latestStreamPosition
            : _vm.currentPosition);
    return base + elapsed;
  }

  /// Motor de reloj con interpolación continua, lookahead predictivo (-250ms)
  /// y soporte para el offset persistido.
  void _onTick() {
    if (!mounted) return;
    final lyrics = _vm.lyrics;
    if (lyrics == null || !lyrics.isSynced || lyrics.lines.isEmpty) return;

    final effectivePosition = _getEffectivePosition();
    final positionWithManualOffset =
        effectivePosition + Duration(milliseconds: manualOffsetMs);

    final newIndex = _computeActiveIndex(
      positionWithManualOffset,
      lyrics.lines,
    );

    if (newIndex != _currentIndex) {
      setState(() {
        _currentIndex = newIndex;
      });
      if (!_isUserScrolling && newIndex >= 0) {
        _scrollToActiveIndex(newIndex);
      }
    } else {
      // Si estamos en la intro instrumental, forzar redibujado sutil de la barra
      // de progreso y de los 3 puntos iluminados.
      if (_currentIndex == -1 &&
          lyrics.lines.first.time > const Duration(seconds: 3)) {
        setState(() {});
      }
    }
  }

  /// Búsqueda binaria O(log n) sobre el trigger predictivo de cada línea.
  /// Retorna -1 si aún no comienza la primera línea (estado de intro instrumental).
  int _computeActiveIndex(Duration audioPosition, List<LyricLine> lines) {
    if (lines.isEmpty) return -1;
    final firstTrigger = lines.first.time - _lookaheadOffset;
    if (audioPosition < firstTrigger) return -1;

    var lo = 0;
    var hi = lines.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      final triggerTime = lines[mid].time - _lookaheadOffset;
      if (audioPosition >= triggerTime) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Auto-scroll fluido al tercio superior (alignment: 0.28) estilo Apple Music y Spotify.
  void _scrollToActiveIndex(int index) {
    if (!_itemScrollController.isAttached || index < 0) return;
    _itemScrollController.scrollTo(
      index: index,
      alignment: 0.28,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutQuart,
    );
  }

  void _syncVoiceNow() {
    final lyrics = _vm.lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) return;

    final targetIndex = _currentIndex < 0 ? 0 : _currentIndex;
    final targetTime = lyrics.lines[targetIndex].time;
    final effectivePosition = _getEffectivePosition();

    // Calcula el offset exacto al milisegundo para alinear la voz que se oye
    final newOffsetMs =
        targetTime.inMilliseconds - effectivePosition.inMilliseconds;

    _updateOffset(newOffsetMs);

    final targetLabel = lyrics.lines[targetIndex].text.isNotEmpty
        ? '"${lyrics.lines[targetIndex].text}"'
        : 'Intro';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sincronizado a $targetLabel (${newOffsetMs >= 0 ? '+' : ''}${(newOffsetMs / 1000).toStringAsFixed(1)}s)',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = _vm.currentTrack;
    final palette = _vm.palette;
    final lyrics = _vm.lyrics;

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
                    manualOffsetMs: manualOffsetMs,
                    isSyncOpen: _showSyncPanel,
                    onToggleSync: () {
                      setState(() {
                        _showSyncPanel = !_showSyncPanel;
                      });
                    },
                    onPlayPause: _vm.togglePlayPause,
                    onClose: () => Navigator.of(context).maybePop(),
                  ),
                  if (_showSyncPanel) ...[
                    const SizedBox(height: 10),
                    _SyncAdjustmentPanel(
                      manualOffsetMs: manualOffsetMs,
                      suggestedOffsetMs: lyrics?.suggestedOffsetMs ?? 0,
                      onAdjustOffset: (delta) {
                        _updateOffset(manualOffsetMs + delta);
                      },
                      onResetOffset: () {
                        _updateOffset(0);
                      },
                      onSyncVoiceNow: _syncVoiceNow,
                    ),
                  ],
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
    final effectivePosition =
        _getEffectivePosition() + Duration(milliseconds: manualOffsetMs);

    return LayoutBuilder(
      builder: (context, constraints) {
        final verticalPadding = constraints.maxHeight * 0.40;

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
              stops: [0.0, 0.08, 0.92, 1.0],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (notification.direction != ScrollDirection.idle) {
                _isUserScrolling = true;
                _userScrollTimer?.cancel();
                _userScrollTimer =
                    Timer(const Duration(milliseconds: 3500), () {
                  if (mounted) {
                    setState(() => _isUserScrolling = false);
                    if (_currentIndex >= 0) {
                      _scrollToActiveIndex(_currentIndex);
                    }
                  }
                });
              }
              return false;
            },
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
                final distance = _currentIndex < 0
                    ? index
                    : (index - _currentIndex).abs();
                final isPassed = _currentIndex >= 0 && index < _currentIndex;

                final isFirst = index == 0;
                final showIntroIndicator = isFirst &&
                    lyrics.isSynced &&
                    _currentIndex == -1 &&
                    lines.first.time > const Duration(seconds: 3);

                final itemWidget = _ImmersiveLyricItem(
                  line: line,
                  isActive: isActive,
                  distance: distance,
                  isPassed: isPassed,
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

                if (showIntroIndicator) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InstrumentalIntroIndicator(
                        currentPosition: effectivePosition,
                        firstLineTime: lines.first.time,
                      ),
                      itemWidget,
                    ],
                  );
                }

                return itemWidget;
              },
            ),
          ),
        );
      },
    );
  }
}

/// Indicador de Intro Instrumental Animado (••• estilo Apple Music)
/// con 3 círculos pulsantes según el progreso y cuenta regresiva sutil.
class _InstrumentalIntroIndicator extends StatelessWidget {
  const _InstrumentalIntroIndicator({
    required this.currentPosition,
    required this.firstLineTime,
  });

  final Duration currentPosition;
  final Duration firstLineTime;

  @override
  Widget build(BuildContext context) {
    final totalMs = firstLineTime.inMilliseconds;
    final progress = totalMs > 0
        ? (currentPosition.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 1.0;
    final remainingSec =
        ((firstLineTime - currentPosition).inMilliseconds / 1000)
            .ceil()
            .clamp(0, 999);

    final dot1 = progress >= 0.20;
    final dot2 = progress >= 0.55;
    final dot3 = progress >= 0.85;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDot(dot1),
              const SizedBox(width: 6),
              _buildDot(dot2),
              const SizedBox(width: 6),
              _buildDot(dot3),
            ],
          ),
          const SizedBox(width: 12),
          Text(
            remainingSec > 0
                ? 'Intro • entra en ${remainingSec}s'
                : 'La voz entra ahora',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      width: active ? 10 : 8,
      height: active ? 10 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.30),
        boxShadow: active
            ? const [
                BoxShadow(
                  color: Colors.white70,
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Panel flotante de ajuste de sincronización con botones rápidos
/// y la opción "La voz empieza AHORA".
class _SyncAdjustmentPanel extends StatelessWidget {
  const _SyncAdjustmentPanel({
    required this.manualOffsetMs,
    required this.suggestedOffsetMs,
    required this.onAdjustOffset,
    required this.onResetOffset,
    required this.onSyncVoiceNow,
  });

  final int manualOffsetMs;
  final int suggestedOffsetMs;
  final ValueChanged<int> onAdjustOffset;
  final VoidCallback onResetOffset;
  final VoidCallback onSyncVoiceNow;

  @override
  Widget build(BuildContext context) {
    final offsetSec = (manualOffsetMs / 1000).toStringAsFixed(1);
    final sign = manualOffsetMs > 0 ? '+' : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xDD1E1E26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.sync_rounded,
                    color: AppTheme.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sincronización: $sign${offsetSec}s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: manualOffsetMs != 0 ? onResetOffset : null,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 28),
                ),
                child: const Text('Restablecer', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStepButton('-0.5s', () => onAdjustOffset(-500)),
              _buildStepButton('-0.1s', () => onAdjustOffset(-100)),
              _buildStepButton('+0.1s', () => onAdjustOffset(100)),
              _buildStepButton('+0.5s', () => onAdjustOffset(500)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onSyncVoiceNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.bolt_rounded, size: 20, color: Colors.amberAccent),
              label: const Text(
                'La voz empieza AHORA',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          if (suggestedOffsetMs != 0 && suggestedOffsetMs != manualOffsetMs) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => onAdjustOffset(suggestedOffsetMs - manualOffsetMs),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_fix_high_rounded,
                      color: Colors.cyanAccent,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Auto-ajuste detectado: ${(suggestedOffsetMs / 1000).toStringAsFixed(1)}s (Toca para aplicar)',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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
    required this.manualOffsetMs,
    required this.isSyncOpen,
    required this.onToggleSync,
    required this.onPlayPause,
    required this.onClose,
  });

  final Track track;
  final bool isPlaying;
  final int manualOffsetMs;
  final bool isSyncOpen;
  final VoidCallback onToggleSync;
  final VoidCallback onPlayPause;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          TrackArtworkImage(
            track: track,
            width: 48,
            height: 48,
            borderRadius: BorderRadius.circular(10),
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
            tooltip: 'Ajustar sincronización',
            onPressed: onToggleSync,
            style: IconButton.styleFrom(
              backgroundColor: isSyncOpen
                  ? AppTheme.accent
                  : (manualOffsetMs != 0
                      ? AppTheme.accent.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.14)),
            ),
            icon: Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 2),
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

/// Línea de letra con jerarquía visual fluida en cascada (distancia al activo),
/// texto en escala armónica (27px / 22px / 20px) sin lag de GPU.
class _ImmersiveLyricItem extends StatelessWidget {
  const _ImmersiveLyricItem({
    required this.line,
    required this.isActive,
    required this.distance,
    required this.isPassed,
    this.onTap,
  });

  final LyricLine line;
  final bool isActive;
  final int distance;
  final bool isPassed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isInstrumentalBreak = line.text.isEmpty;

    // Jerarquía visual en cascada (distancia a la frase activa)
    final double opacity;
    final double scale;
    final double fontSize;
    final FontWeight fontWeight;
    final Color textColor;
    final List<Shadow> shadows;

    if (isActive) {
      opacity = 1.0;
      scale = 1.0;
      fontSize = 27;
      fontWeight = FontWeight.w800;
      textColor = Colors.white;
      shadows = const [
        Shadow(
          color: Color(0x66000000),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ];
    } else if (distance == 1) {
      opacity = 0.48;
      scale = 0.94;
      fontSize = 22;
      fontWeight = FontWeight.w600;
      textColor = Colors.white.withValues(alpha: 0.70);
      shadows = const [];
    } else {
      opacity = isPassed ? 0.22 : 0.32;
      scale = 0.91;
      fontSize = 20;
      fontWeight = FontWeight.w500;
      textColor = Colors.white.withValues(alpha: 0.50);
      shadows = const [];
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: isInstrumentalBreak ? 18 : 14,
        ),
        child: AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: scale,
            alignment: Alignment.centerLeft,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                height: 1.28,
                letterSpacing: -0.4,
                color: textColor,
                shadows: shadows,
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
