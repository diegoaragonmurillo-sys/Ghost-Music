import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/palette_service.dart';
import '../models/lyrics.dart';
import '../models/track.dart';
import '../viewmodels/player_view_model.dart';

/// Vista inmersiva de letras sincronizadas a pantalla completa (estilo Apple Music).
class ImmersiveLyricsView extends StatefulWidget {
  const ImmersiveLyricsView({
    super.key,
    required this.viewModel,
    this.lines,
  });

  final PlayerViewModel viewModel;

  /// Líneas opcionales. Por defecto utiliza las 5 líneas de prueba de [Lyrics.demoLines].
  final List<LyricLine>? lines;

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

  /// Lista hardcodeada con 5 líneas de prueba y sus tiempos para simular una canción.
  static const List<LyricLine> _hardcodedTestLines = Lyrics.demoLines;

  late List<GlobalKey> _itemKeys;
  int _lastActiveIndex = -1;

  List<LyricLine> get _activeLines => widget.lines ?? _hardcodedTestLines;

  @override
  void initState() {
    super.initState();
    _itemKeys = List.generate(_activeLines.length, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(covariant ImmersiveLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_itemKeys.length != _activeLines.length) {
      _itemKeys = List.generate(_activeLines.length, (_) => GlobalKey());
      _lastActiveIndex = -1;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _resolveActiveIndex(Duration position, List<LyricLine> lines) {
    if (lines.isEmpty || position < lines.first.time) return 0;
    var active = 0;
    for (var i = 0; i < lines.length; i++) {
      if (position >= lines[i].time) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  void _scrollToActiveLine(int index, double viewportHeight) {
    if (!_scrollController.hasClients) return;
    if (index < 0 || index >= _itemKeys.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final itemContext = _itemKeys[index].currentContext;
      final listContext = _listViewKey.currentContext;

      if (itemContext != null && listContext != null) {
        final itemBox = itemContext.findRenderObject() as RenderBox?;
        final listBox = listContext.findRenderObject() as RenderBox?;
        if (itemBox != null && listBox != null && itemBox.hasSize) {
          final itemOffsetInList =
              itemBox.localToGlobal(Offset.zero, ancestor: listBox);
          final itemCenterY = itemOffsetInList.dy + (itemBox.size.height / 2);
          final viewportCenterY = listBox.size.height / 2;
          final delta = itemCenterY - viewportCenterY;
          final targetOffset = (_scrollController.offset + delta).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          );

          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
          );
          return;
        }
      }

      // Fallback estimando el alto de cada ítem si aún no se ha renderizado.
      const estimatedItemHeight = 96.0;
      final targetOffset = (index * estimatedItemHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final lines = _activeLines;
    final screenSize = MediaQuery.sizeOf(context);

    return SizedBox(
      height: screenSize.height,
      width: screenSize.width,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: vm,
          builder: (context, _) {
            final track = vm.currentTrack;
            final palette = vm.palette;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Fondo dinámico a pantalla completa generado con los colores de la carátula.
                _DynamicArtworkGradientBackground(
                  palette: palette,
                  artworkUrl: track.artworkUrl,
                ),

                SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      // Indicador superior de arrastre (Modal Bottom Sheet handle).
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
                        isPlaying: vm.isPlaying,
                        onPlayPause: vm.togglePlayPause,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final viewportHeight = constraints.maxHeight;
                            final symmetricPadding = viewportHeight * 0.42;

                            return StreamBuilder<Duration>(
                              stream: vm.positionStream,
                              initialData: Duration.zero,
                              builder: (context, snapshot) {
                                final position = snapshot.data ?? Duration.zero;
                                final activeIndex =
                                    _resolveActiveIndex(position, lines);

                                if (activeIndex != _lastActiveIndex) {
                                  _lastActiveIndex = activeIndex;
                                  _scrollToActiveLine(
                                    activeIndex,
                                    viewportHeight,
                                  );
                                }

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
                                      stops: [0.0, 0.12, 0.88, 1.0],
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
                                      final isActive = index == activeIndex;

                                      return KeyedSubtree(
                                        key: _itemKeys[index],
                                        child: _ImmersiveLyricItem(
                                          line: line,
                                          isActive: isActive,
                                          onTap: () => vm.seek(line.time),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Fondo de gradiente dinámico a pantalla completa a partir de [ArtworkPalette].
class _DynamicArtworkGradientBackground extends StatelessWidget {
  const _DynamicArtworkGradientBackground({
    required this.palette,
    required this.artworkUrl,
  });

  final ArtworkPalette palette;
  final String artworkUrl;

  @override
  Widget build(BuildContext context) {
    final deepShade = Color.lerp(palette.secondary, AppTheme.background, 0.55) ??
        AppTheme.background;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.primary,
                palette.secondary,
                deepShade,
              ],
              stops: const [0.0, 0.52, 1.0],
            ),
          ),
        ),
        // Halo atmosférico difuminado de la carátula para riqueza cromática tipo Apple Music.
        IgnorePointer(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 85,
              sigmaY: 85,
              tileMode: TileMode.mirror,
            ),
            child: Opacity(
              opacity: 0.35,
              child: Image.network(
                artworkUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        // Velo sutil para garantizar contraste óptimo con la tipografía blanca.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x26000000),
                Color(0x40000000),
                Color(0x66000000),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Cabecera compacta con mini-carátula, título, artista y controles rápidos.
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
                  child: const Icon(Icons.music_note_rounded, color: Colors.white70),
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

/// Línea individual de letra con transición animada de escala, opacidad y blur.
class _ImmersiveLyricItem extends StatelessWidget {
  const _ImmersiveLyricItem({
    required this.line,
    required this.isActive,
    required this.onTap,
  });

  final LyricLine line;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final targetBlur = isActive ? 0.0 : 1.8;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: targetBlur, end: targetBlur),
          duration: const Duration(milliseconds: 350),
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
            scale: isActive ? 1.0 : 0.94,
            alignment: Alignment.centerLeft,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontSize: isActive ? 30 : 23,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                height: 1.25,
                letterSpacing: -0.5,
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.5),
                shadows: isActive
                    ? const [
                        Shadow(
                          color: Color(0x55000000),
                          blurRadius: 16,
                          offset: Offset(0, 4),
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
