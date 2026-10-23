import '../features/player/models/track.dart';
import 'discovery_service.dart';
import 'history_service.dart';
import 'library_service.dart';

/// Motor de recomendaciones dinámicas para la sección "Inicio / Para Ti".
///
/// Combina las señales locales de favoritos ([LibraryService]) y del historial
/// de reproducciones ([HistoryService]) para consultar canciones y artistas afines
/// en [DiscoveryService]. Si el usuario es nuevo, ofrece un "Starter Pack"
/// con el Top Global.
class RecommendationService {
  RecommendationService({
    LibraryService? libraryService,
    HistoryService? historyService,
    DiscoveryService? discoveryService,
  })  : _library = libraryService ?? LibraryService.instance,
        _history = historyService ?? HistoryService.instance,
        _discovery = discoveryService ?? DiscoveryService.instance;

  static final RecommendationService instance = RecommendationService();

  final LibraryService _library;
  final HistoryService _history;
  final DiscoveryService _discovery;

  /// Determina si el usuario tiene suficiente actividad local para personalización.
  bool get hasUserSignals =>
      _history.recentTracks.isNotEmpty || _library.favorites.isNotEmpty;

  /// Obtiene la lista de pistas para la sección "Para Ti".
  ///
  /// Si hay historial o favoritos, mezcla canciones de artistas afines.
  /// En caso contrario, provee el Top Global como starter pack.
  Future<List<Track>> getForYou() async {
    final candidateArtists = <String>[];

    // 1. Agregar artistas más escuchados
    for (final artist in _history.topArtists) {
      if (!candidateArtists.contains(artist)) {
        candidateArtists.add(artist);
      }
    }

    // 2. Agregar artistas de canciones favoritas
    for (final fav in _library.favorites) {
      final artist = fav.artist.trim();
      if (artist.isNotEmpty && !candidateArtists.contains(artist)) {
        candidateArtists.add(artist);
      }
    }

    if (candidateArtists.isEmpty) {
      // Usuario nuevo: retornar el Top Global
      return _discovery.getTopTracks();
    }

    final recommended = <Track>[];
    final recentIds = _history.recentTracks.map((t) => t.id).toSet();

    // Consultar artistas afines de hasta los primeros 2 artistas
    for (final artist in candidateArtists.take(2)) {
      final related = await _discovery.fetchRelatedTracks(artist);
      for (final t in related) {
        if (!recentIds.contains(t.id) &&
            !recommended.any((existing) => existing.title == t.title)) {
          recommended.add(t);
        }
      }
    }

    if (recommended.isEmpty) {
      return _discovery.getTopTracks();
    }

    return recommended;
  }

  /// Retorna un artista relevante del usuario y una selección de canciones afines
  /// para la sección "Porque te gusta [Artista]".
  /// Retorna `null` si no hay señales o no se encuentran temas afines.
  Future<({String artist, List<Track> tracks})?> getBecauseYouLike() async {
    String? targetArtist;

    // Priorizar el artista más escuchado en el historial
    if (_history.topArtists.isNotEmpty) {
      targetArtist = _history.topArtists.first;
    } else if (_library.favorites.isNotEmpty) {
      targetArtist = _library.favorites.first.artist;
    }

    if (targetArtist == null || targetArtist.trim().isEmpty) {
      return null;
    }

    final tracks = await _discovery.fetchRelatedTracks(targetArtist);
    if (tracks.isEmpty) {
      return null;
    }

    return (artist: targetArtist, tracks: tracks);
  }
}
