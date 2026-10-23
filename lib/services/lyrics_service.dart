import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/player/models/lyrics.dart';
import '../features/player/models/track.dart';

/// Servicio de letras sincronizadas mediante LRCLIB (`https://lrclib.net/api/search`).
class LyricsService {
  LyricsService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Map<String, Lyrics?> _cache = {};

  static const _host = 'lrclib.net';
  static const _headers = {
    'User-Agent':
        'GhostMusic/1.0.0 (https://github.com/diegoaragonmurillo-sys/Ghost-Music)',
  };

  /// Obtiene y parsea las letras sincronizadas (LRC) para [trackName] y [artistName].
  Future<List<LyricLine>> fetchSyncedLyrics({
    required String trackName,
    required String artistName,
  }) async {
    final cleanTrack = _cleanForLookup(trackName);
    final cleanArtist = _cleanArtist(artistName);

    final lyrics = await _search({
          'track_name': cleanTrack,
          'artist_name': cleanArtist,
        }) ??
        await _search({'q': '$cleanTrack $cleanArtist'});

    if (lyrics == null) return const [];
    return lyrics.lines;
  }

  /// Obtiene el objeto [Lyrics] para un [Track] con caché en memoria.
  Future<Lyrics?> fetch(Track track) async {
    if (_cache.containsKey(track.id)) return _cache[track.id];

    final title = _cleanForLookup(track.title);
    final artist = _cleanArtist(track.artist);
    Lyrics? lyrics;
    try {
      // 1. Petición GET a https://lrclib.net/api/search pasando track_name y artist_name.
      lyrics = await _search({
        'track_name': title,
        'artist_name': artist,
      });
      // 2. Fallback por consulta general si los metadatos de YouTube varían.
      lyrics ??= await _search({'q': '$title $artist'});
    } catch (_) {
      lyrics = null;
    }
    return _cache[track.id] = lyrics;
  }

  Future<Lyrics?> _search(Map<String, String> params) async {
    final uri = Uri.https(_host, '/api/search', params);
    final res = await _http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;

    final decoded = jsonDecode(res.body);
    if (decoded is! List || decoded.isEmpty) return null;

    final list = decoded.cast<Map<String, dynamic>>();

    // Prioriza resultados que contengan el campo syncedLyrics en formato LRC.
    for (final item in list) {
      final synced = item['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) {
        final parsed = Lyrics.parse(synced: synced);
        if (parsed != null && parsed.lines.isNotEmpty) {
          return parsed;
        }
      }
    }

    // Fallback a letra plana si ninguna entrada tiene tiempos LRC.
    final first = list.first;
    return Lyrics.parse(
      synced: first['syncedLyrics'] as String?,
      plain: first['plainLyrics'] as String?,
    );
  }

  /// Convierte un texto LRC (`[01:15.22] Texto`) directamente en `List<LyricLine>`.
  List<LyricLine> parseLrc(String syncedLyrics) => Lyrics.parseLrc(syncedLyrics);

  static String _cleanForLookup(String title) => title
      .replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]'), '')
      .replaceAll(
        RegExp(r'\s+(ft\.?|feat\.?|featuring)\s+.*$', caseSensitive: false),
        '',
      )
      .trim();

  static String _cleanArtist(String artist) => artist
      .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*VEVO$', caseSensitive: false), '')
      .trim();

  void dispose() => _http.close();
}
