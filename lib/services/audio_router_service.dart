import 'dart:io';

import '../core/settings_manager.dart';
import '../features/player/models/track.dart';
import 'download_service.dart';
import 'search_service.dart';

/// Motor de enrutamiento de audio inteligente con tolerancia a fallos
/// ("Graceful Degradation" / Fallback en cascada) y Nivel 0 Local-First.
///
/// Enruta la resolución del stream según la preferencia del usuario en
/// [SettingsManager]:
/// - `Nivel 0`   → Archivo local descargado en disco (Cero llamadas de red)
/// - `lossless`  → Deezer (FLAC) → JioSaavn (320kbps) → YouTube (128kbps)
/// - `high`      → JioSaavn (320kbps) → YouTube (128kbps)
/// - `data_saver`→ YouTube (128kbps)
class AudioRouterService {
  AudioRouterService({
    required this.searchService,
    SettingsManager? settingsManager,
    DownloadService? downloadService,
  })  : _settings = settingsManager ?? SettingsManager.instance,
        _downloadService = downloadService;

  final SearchService searchService;
  final SettingsManager _settings;
  final DownloadService? _downloadService;

  DownloadService get _downloads =>
      _downloadService ?? DownloadService.instance;

  /// Expone la búsqueda de metadatos delegando en [SearchService].
  Future<List<Track>> search(String query, {int limit = 20}) {
    return searchService.search(query, limit: limit);
  }

  /// Resuelve y devuelve una copia de [track] con el `audioUrl` obtenido
  /// mediante Nivel 0 o la cascada de proveedores según la calidad configurada.
  Future<Track> resolveStream(
    Track track, {
    AudioQuality? qualityOverride,
    bool bypassLocal = false,
  }) async {
    final url = await resolveAudioUrl(
      track,
      qualityOverride: qualityOverride,
      bypassLocal: bypassLocal,
    );
    return track.copyWith(audioUrl: url);
  }

  /// Flujo principal de resolución con Nivel 0 Local y tolerancia a fallos en cascada.
  Future<String> resolveAudioUrl(
    Track track, {
    AudioQuality? qualityOverride,
    bool bypassLocal = false,
  }) async {
    // -------------------------------------------------------------------------
    // NIVEL 0: Local First (Cero llamadas de red)
    // -------------------------------------------------------------------------
    if (!bypassLocal) {
      final pkg = _downloads.getPackage(track.id);
      if (pkg != null && File(pkg.localAudioPath).existsSync()) {
        // ignore: avoid_print
        print(
          '[AudioRouter] Nivel 0 Local Hit -> Reproduciendo desde disco: ${pkg.localAudioPath}',
        );
        return pkg.localAudioPath;
      }
    }

    final quality = qualityOverride ?? await _settings.getSavedAudioQuality();
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
