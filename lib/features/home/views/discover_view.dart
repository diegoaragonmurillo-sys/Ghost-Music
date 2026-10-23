import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/track_action_sheet.dart';
import '../../../core/widgets/track_artwork_image.dart';
import '../../../services/audio_player_service.dart';
import '../../../services/discovery_service.dart';
import '../../../services/history_service.dart';
import '../../../services/library_service.dart';
import '../../../services/lyrics_service.dart';
import '../../../services/palette_service.dart';
import '../../../services/recommendation_service.dart';
import '../../player/models/track.dart';
import '../../settings/settings_screen.dart';

/// Vista de Inicio ("Inicio / Para Ti") estilo Apple Music.
///
/// Presenta:
/// - Saludo dinámico según la hora del día.
/// - Carrusel de Éxitos Globales (Top 20 en tiempo real).
/// - Sección "Para Ti" con afinidad dinámica.
/// - Sección "Porque te gusta [Artista]" basada en historial o favoritos.
/// - Carrusel de "Escuchado recientemente".
/// - Mezclas y exploración por género/estado de ánimo.
class DiscoverView extends StatefulWidget {
  const DiscoverView({
    super.key,
    required this.audioService,
    required this.paletteService,
    required this.lyricsService,
    required this.libraryService,
    required this.onPlayTrack,
  });

  final AudioPlayerService audioService;
  final PaletteService paletteService;
  final LyricsService lyricsService;
  final LibraryService libraryService;
  final void Function({required List<Track> queue, required int index})
      onPlayTrack;

  @override
  State<DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<DiscoverView> {
  final DiscoveryService _discovery = DiscoveryService.instance;
  final RecommendationService _recommendations =
      RecommendationService.instance;
  final HistoryService _history = HistoryService.instance;

  List<Track> _topTracks = [];
  List<Track> _forYouTracks = [];
  ({String artist, List<Track> tracks})? _becauseYouLike;
  String _selectedGenre = 'Pop';
  List<Track> _genreTracks = [];

  bool _loading = true;
  bool _loadingGenre = false;

  static const List<String> _genres = [
    'Pop',
    'Rock',
    'Hip-Hop',
    'Reggaeton',
    'Electrónica',
    'R&B',
    'Lo-Fi',
    'Latino',
    'Chill',
  ];

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Buenos días';
    if (hour >= 12 && hour < 20) return 'Buenas tardes';
    return 'Buenas noches';
  }

  Future<void> _loadFeed({bool forceRefresh = false}) async {
    setState(() => _loading = true);

    try {
      final results = await Future.wait([
        _discovery.getTopTracks(forceRefresh: forceRefresh),
        _recommendations.getForYou(),
        _recommendations.getBecauseYouLike(),
        _discovery.getGenreTracks(_selectedGenre),
      ]);

      if (!mounted) return;

      setState(() {
        _topTracks = results[0] as List<Track>;
        _forYouTracks = results[1] as List<Track>;
        _becauseYouLike =
            results[2] as ({String artist, List<Track> tracks})?;
        _genreTracks = results[3] as List<Track>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _onSelectGenre(String genre) async {
    if (_selectedGenre == genre && _genreTracks.isNotEmpty) return;
    setState(() {
      _selectedGenre = genre;
      _loadingGenre = true;
    });

    final tracks = await _discovery.getGenreTracks(genre);
    if (!mounted) return;
    setState(() {
      _genreTracks = tracks;
      _loadingGenre = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return RefreshIndicator(
      color: AppTheme.accent,
      backgroundColor: AppTheme.surfaceElevated,
      onRefresh: () => _loadFeed(forceRefresh: true),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Cabecera superior con saludo y botón de Ajustes
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greeting,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Ghost Music • Para Ti',
                              style: text.bodySmall?.copyWith(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
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
                    padding: const EdgeInsets.all(12),
                  ),
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
            )
          else ...[
            // 1. Escuchado recientemente (si hay historial)
            ListenableBuilder(
              listenable: _history,
              builder: (context, _) {
                final recents = _history.recentTracks;
                if (recents.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: 'Escuchado recientemente',
                      subtitle: 'Retoma tus canciones favoritas',
                    ),
                    SizedBox(
                      height: 190,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        itemCount: recents.take(15).length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 14),
                        itemBuilder: (context, idx) {
                          final track = recents[idx];
                          return _SmallMediaCard(
                            track: track,
                            audioService: widget.audioService,
                            libraryService: widget.libraryService,
                            onTap: () => widget.onPlayTrack(
                              queue: recents,
                              index: idx,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),

            // 2. Carrusel Hero: Top 20 Global
            if (_topTracks.isNotEmpty) ...[
              _SectionHeader(
                title: 'Éxitos Globales',
                subtitle: 'Las 20 canciones más escuchadas del momento',
              ),
              SizedBox(
                height: 230,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: _topTracks.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 16),
                  itemBuilder: (context, idx) {
                    final track = _topTracks[idx];
                    return _TopChartHeroCard(
                      rank: idx + 1,
                      track: track,
                      audioService: widget.audioService,
                      libraryService: widget.libraryService,
                      onTap: () => widget.onPlayTrack(
                        queue: _topTracks,
                        index: idx,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 3. Sección "Para Ti"
            if (_forYouTracks.isNotEmpty) ...[
              _SectionHeader(
                title: 'Para Ti',
                subtitle: 'Recomendaciones personalizadas para tus gustos',
              ),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: _forYouTracks.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 14),
                  itemBuilder: (context, idx) {
                    final track = _forYouTracks[idx];
                    return _SmallMediaCard(
                      track: track,
                      audioService: widget.audioService,
                      libraryService: widget.libraryService,
                      onTap: () => widget.onPlayTrack(
                        queue: _forYouTracks,
                        index: idx,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 4. Sección "Porque te gusta [Artista]"
            if (_becauseYouLike != null &&
                _becauseYouLike!.tracks.isNotEmpty) ...[
              _SectionHeader(
                title: 'Porque te gusta ${_becauseYouLike!.artist}',
                subtitle: 'Canciones y colaboraciones afines',
              ),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: _becauseYouLike!.tracks.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 14),
                  itemBuilder: (context, idx) {
                    final track = _becauseYouLike!.tracks[idx];
                    return _SmallMediaCard(
                      track: track,
                      audioService: widget.audioService,
                      libraryService: widget.libraryService,
                      onTap: () => widget.onPlayTrack(
                        queue: _becauseYouLike!.tracks,
                        index: idx,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 5. Explorar por Género / Estado de ánimo
            _SectionHeader(
              title: 'Explorar por Género',
              subtitle: 'Selecciona una vibración o estilo sonoro',
            ),
            SizedBox(
              height: 38,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: _genres.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final genre = _genres[idx];
                  final isSelected = genre == _selectedGenre;
                  return ChoiceChip(
                    label: Text(genre),
                    selected: isSelected,
                    onSelected: (_) => _onSelectGenre(genre),
                    selectedColor: AppTheme.accent,
                    backgroundColor: const Color(0xFF1C1C24),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            if (_loadingGenre)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.accent,
                    strokeWidth: 2.5,
                  ),
                ),
              )
            else if (_genreTracks.isNotEmpty)
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _genreTracks.take(8).length,
                itemBuilder: (context, idx) {
                  final track = _genreTracks[idx];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: TrackArtworkImage(
                        track: track,
                        width: 48,
                        height: 48,
                      ),
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => TrackActionSheet.show(
                        context,
                        track: track,
                        audioService: widget.audioService,
                        libraryService: widget.libraryService,
                      ),
                    ),
                    onTap: () => widget.onPlayTrack(
                      queue: _genreTracks,
                      index: idx,
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              fontSize: 19,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: text.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta de gran formato para el Top 20 Global con insignia de ranking.
class _TopChartHeroCard extends StatelessWidget {
  const _TopChartHeroCard({
    required this.rank,
    required this.track,
    required this.audioService,
    required this.libraryService,
    required this.onTap,
  });

  final int rank;
  final Track track;
  final AudioPlayerService audioService;
  final LibraryService libraryService;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 156,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: TrackArtworkImage(
                    track: track,
                    width: 156,
                    height: 156,
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: rank <= 3 ? AppTheme.accent : Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: rank <= 3 ? AppTheme.accent : Colors.white,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => TrackActionSheet.show(
                        context,
                        track: track,
                        audioService: audioService,
                        libraryService: libraryService,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta para carruseles de tamaño medio ("Para Ti", "Escuchado recientemente").
class _SmallMediaCard extends StatelessWidget {
  const _SmallMediaCard({
    required this.track,
    required this.audioService,
    required this.libraryService,
    required this.onTap,
  });

  final Track track;
  final AudioPlayerService audioService;
  final LibraryService libraryService;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: TrackArtworkImage(
                    track: track,
                    width: 124,
                    height: 124,
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => TrackActionSheet.show(
                        context,
                        track: track,
                        audioService: audioService,
                        libraryService: libraryService,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
