import '../core/settings_manager.dart';
import '../features/player/models/track.dart';
import 'search_service.dart';

/// Motor de enrutamiento de audio inteligente con tolerancia a fallos
/// ("Graceful Degradation" / Fallback en cascada).
///
/// Enruta la resolución del stream según la preferencia del usuario en
/// [SettingsManager]:
/// - `lossless`  → Deezer (FLAC) → JioSaavn (320kbps) → YouTube (128kbps)
/// - `high`      → JioSaavn (320kbps) → YouTube (128kbps)
/// - `data_saver`→ YouTube (128kbps)
class AudioRouterService {
  AudioRouterService({
    required this.searchService,
    SettingsManager? settingsManager,
  }) : _settings = settingsManager ?? SettingsManager.instance;

  final SearchService searchService;
  final SettingsManager _settings;

  /// Expone la búsqueda de metadatos delegando en [SearchService].
  Future<List<Track>> search(String query, {int limit = 20}) {
    return searchService.search(query, limit: limit);
  }

  /// Resuelve y devuelve una copia de [track] con el `audioUrl` obtenido
  /// mediante la cascada de proveedores según la calidad configurada.
  Future<Track> resolveStream(Track track) async {
    final url = await resolveAudioUrl(track);
    return track.copyWith(audioUrl: url);
  }

  /// Flujo principal de resolución con tolerancia a fallos en cascada.
  Future<String> resolveAudioUrl(Track track) async {
    final quality = await _settings.getSavedAudioQuality();
    // ignore: avoid_print
    print(
      '[AudioRouter] Resolviendo "${track.title}" con preferencia: ${quality.key}',
    );

    switch (quality) {
      case AudioQuality.lossless:
        try {
          return await _fetchFromDeezer(track);
        } catch (deezerError) {
          // ignore: avoid_print
          print(
            '[AudioRouter] Deezer (lossless) falló ($deezerError) -> Fallback a JioSaavn (high)...',
          );
          try {
            return await _fetchFromJioSaavn(track);
          } catch (saavnError) {
            // ignore: avoid_print
            print(
              '[AudioRouter] JioSaavn (high) falló ($saavnError) -> Fallback a YouTube (data_saver)...',
            );
            return await _fetchFromYouTube(track);
          }
        }

      case AudioQuality.high:
        try {
          return await _fetchFromJioSaavn(track);
        } catch (saavnError) {
          // ignore: avoid_print
          print(
            '[AudioRouter] JioSaavn (high) falló ($saavnError) -> Fallback a YouTube (data_saver)...',
          );
          return await _fetchFromYouTube(track);
        }

      case AudioQuality.dataSaver:
        return await _fetchFromYouTube(track);
    }
  }

  /// Proveedor Lossless (Deezer FLAC).
  Future<String> _fetchFromDeezer(Track track) async {
    throw Exception('API no implementada aún');
  }

  /// Proveedor High Quality (JioSaavn 320kbps).
  Future<String> _fetchFromJioSaavn(Track track) async {
    throw Exception('API no implementada aún');
  }

  /// Proveedor Data Saver (YouTube 128kbps).
  Future<String> _fetchFromYouTube(Track track) async {
    return searchService.resolveAudioUrl(track.id);
  }
}
