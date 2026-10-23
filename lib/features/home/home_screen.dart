import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/duration_formatter.dart';
import '../../core/widgets/track_action_sheet.dart';
import '../../core/widgets/track_artwork_image.dart';
import '../../services/audio_player_service.dart';
import '../../services/library_service.dart';
import '../../services/lyrics_service.dart';
import '../../services/palette_service.dart';
import '../../services/search_service.dart';
import '../downloads/widgets/download_button.dart';
import '../library/views/library_screen.dart';
import '../library/widgets/add_to_playlist_sheet.dart';
import '../player/models/track.dart';
import '../player/viewmodels/player_view_model.dart';
import '../player/views/player_screen.dart';
import '../settings/settings_screen.dart';
import 'views/discover_view.dart';

/// Pantalla raíz con navegación entre Buscar y Biblioteca Local (estilo Apple Music),
/// manteniendo el MiniPlayer flotando sobre la barra inferior.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.audioService,
    required this.searchService,
    required this.paletteService,
    required this.lyricsService,
    this.libraryService,
  });

  final AudioPlayerService audioService;
  final SearchService searchService;
  final PaletteService paletteService;
  final LyricsService lyricsService;
  final LibraryService? libraryService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  int _selectedTabIndex = 0;
  List<Track> _results = const [];
  bool _isSearching = false;
  String? _error;
  int _searchGeneration = 0;

  LibraryService get _library =>
      widget.libraryService ?? LibraryService.instance;

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
      libraryService: _library,
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
          children: [
            Expanded(
              child: IndexedStack(
                index: _selectedTabIndex,
                children: [
                  DiscoverView(
                    audioService: widget.audioService,
                    paletteService: widget.paletteService,
                    lyricsService: widget.lyricsService,
                    libraryService: _library,
                    onPlayTrack: _openPlayer,
                  ),
                  _buildSearchTab(text),
                  LibraryScreen(
                    libraryService: _library,
                    audioService: widget.audioService,
                    paletteService: widget.paletteService,
                    lyricsService: widget.lyricsService,
                  ),
                ],
              ),
            ),

            // Mini-reproductor inferior siempre visible sobre la barra de navegación.
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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x18FFFFFF))),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedTabIndex,
          onTap: (idx) {
            FocusScope.of(context).unfocus();
            setState(() => _selectedTabIndex = idx);
          },
          backgroundColor: const Color(0xF2121216),
          selectedItemColor: AppTheme.accent,
          unselectedItemColor: AppTheme.textSecondary,
          selectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              label: 'Inicio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search_rounded),
              label: 'Buscar',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.library_music_rounded),
              label: 'Biblioteca',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab(TextTheme text) {
    return Column(
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
          child: _buildSearchBody(text),
        ),
      ],
    );
  }

  Widget _buildSearchBody(TextTheme text) {
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

    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
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
            final isFav = _library.isFavorite(track.id);
            return _TrackTile(
              track: track,
              isFavorite: isFav,
              audioService: widget.audioService,
              libraryService: _library,
              onTap: () => _openPlayer(queue: _results, index: index),
              onToggleFavorite: () => _library.toggleFavorite(track),
              onAddToPlaylist: () => AddToPlaylistSheet.show(
                context,
                libraryService: _library,
                track: track,
              ),
            );
          },
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
  const _TrackTile({
    required this.track,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onAddToPlaylist,
    this.audioService,
    this.libraryService,
  });

  final Track track;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onAddToPlaylist;
  final AudioPlayerService? audioService;
  final LibraryService? libraryService;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            TrackArtworkImage(
              track: track,
              width: 56,
              height: 56,
              borderRadius: BorderRadius.circular(8),
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
            DownloadButton(track: track, size: 20),
            IconButton(
              tooltip:
                  isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
              onPressed: onToggleFavorite,
              icon: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: isFavorite ? AppTheme.accent : AppTheme.textSecondary,
                size: 22,
              ),
            ),
            IconButton(
              tooltip: 'Añadir a una playlist',
              onPressed: onAddToPlaylist,
              icon: const Icon(
                Icons.playlist_add_rounded,
                color: AppTheme.textSecondary,
                size: 24,
              ),
            ),
            IconButton(
              tooltip: 'Más opciones',
              onPressed: () => TrackActionSheet.show(
                context,
                track: track,
                audioService: audioService,
                libraryService: libraryService,
              ),
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AppTheme.textSecondary,
                size: 20,
              ),
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
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
                        TrackArtworkImage(
                          track: track,
                          width: 44,
                          height: 44,
                          borderRadius: BorderRadius.circular(8),
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
