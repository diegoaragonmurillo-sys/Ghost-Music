import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/duration_formatter.dart';
import '../../services/audio_player_service.dart';
import '../../services/lyrics_service.dart';
import '../../services/palette_service.dart';
import '../../services/search_service.dart';
import '../player/models/track.dart';
import '../player/viewmodels/player_view_model.dart';
import '../player/views/player_screen.dart';
import '../settings/settings_screen.dart';

/// Pantalla principal de búsqueda y exploración musical (estilo Apple Music).
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.audioService,
    required this.searchService,
    required this.paletteService,
    required this.lyricsService,
  });

  final AudioPlayerService audioService;
  final SearchService searchService;
  final PaletteService paletteService;
  final LyricsService lyricsService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  List<Track> _results = const [];
  bool _isSearching = false;
  String? _error;
  int _searchGeneration = 0;

  static const List<String> _quickSuggestions = [
    'The Weeknd Blinding Lights',
    'Daft Punk Get Lucky',
    'Dua Lipa Levitating',
    'Arctic Monkeys Do I Wanna Know',
    'Tame Impala The Less I Know The Better',
    'Coldplay Yellow',
  ];

  @override
  void initState() {
    super.initState();
    // Carga inicial de sugerencias reales para que la pantalla nunca arranque vacía.
    unawaited(_performSearch('The Weeknd'));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 420),
      () => _performSearch(trimmed),
    );
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final gen = ++_searchGeneration;
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await widget.searchService.search(trimmed);
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _error = 'No se pudo completar la búsqueda. Verifica tu conexión.';
        _isSearching = false;
      });
    }
  }

  void _openPlayer({required List<Track> queue, required int index}) {
    FocusScope.of(context).unfocus();
    final vm = PlayerViewModel(
      audioService: widget.audioService,
      paletteService: widget.paletteService,
      lyricsService: widget.lyricsService,
      queue: queue,
      initialIndex: index,
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera con tipografía grande e impactante estilo Apple Music + botón de Ajustes.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Buscar',
                    style: text.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ajustes de Calidad de Audio',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF1C1C22),
                    ),
                    icon: const Icon(
                      Icons.settings_rounded,
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ),
            ),

            // Barra de búsqueda minimalista.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SearchField(
                controller: _controller,
                onChanged: _onQueryChanged,
                onSubmitted: _performSearch,
                onClear: () {
                  _controller.clear();
                  setState(() => _error = null);
                },
              ),
            ),

            // Chips rápidos de exploración.
            SizedBox(
              height: 46,
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                scrollDirection: Axis.horizontal,
                itemCount: _quickSuggestions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final label = _quickSuggestions[i];
                  return ActionChip(
                    label: Text(label),
                    backgroundColor: const Color(0xFF1A1A1F),
                    side: const BorderSide(color: Color(0x22FFFFFF)),
                    labelStyle: text.labelMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onPressed: () {
                      _controller.text = label;
                      _performSearch(label);
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 4),

            // Lista de resultados.
            Expanded(
              child: _buildBody(text),
            ),

            // Mini-reproductor inferior si ya hay una pista activa en el handler.
            _MiniPlayerBar(
              audioService: widget.audioService,
              onTap: () {
                final queue = widget.audioService.currentQueue;
                if (queue.isEmpty) return;
                _openPlayer(
                  queue: queue,
                  index: widget.audioService.currentIndex,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(TextTheme text) {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppTheme.accent,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          'Escribe el nombre de una canción o artista',
          style: text.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        indent: 72,
        color: Color(0x18FFFFFF),
      ),
      itemBuilder: (context, index) {
        final track = _results[index];
        return _TrackTile(
          track: track,
          onTap: () => _openPlayer(queue: _results, index: index),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'Artistas, canciones o letras',
        hintStyle: const TextStyle(color: Color(0x80FFFFFF)),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0x99FFFFFF),
        ),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                onPressed: onClear,
                icon: const Icon(
                  Icons.cancel_rounded,
                  size: 20,
                  color: Color(0x99FFFFFF),
                ),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF1C1C22),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final thumbUrl = track.fallbackArtworkUrl ?? track.artworkUrl;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                thumbUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFF1C1C22),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(Icons.music_note_rounded),
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
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
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
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.play_circle_fill_rounded,
              color: AppTheme.accent,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayerBar extends StatelessWidget {
  const _MiniPlayerBar({required this.audioService, required this.onTap});

  final AudioPlayerService audioService;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return StreamBuilder<Track?>(
      stream: audioService.currentTrackStream,
      initialData: audioService.currentTrack,
      builder: (context, snapshot) {
        final track = snapshot.data ?? audioService.currentTrack;
        if (track == null) return const SizedBox.shrink();

        final thumbUrl = track.fallbackArtworkUrl ?? track.artworkUrl;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Material(
                color: const Color(0xCC1E1E26),
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            thumbUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(Icons.music_note_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        StreamBuilder(
                          stream: audioService.playerStateStream,
                          builder: (context, _) {
                            final playing = audioService.playing;
                            return IconButton(
                              onPressed: () => playing
                                  ? audioService.pause()
                                  : audioService.play(),
                              icon: Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 30,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          onPressed: audioService.skipToNext,
                          icon: const Icon(Icons.skip_next_rounded, size: 28),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
