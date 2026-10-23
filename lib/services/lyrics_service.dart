import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/player/models/lyrics.dart';
import '../features/player/models/track.dart';

/// Letras sincronizadas desde LRCLIB (https://lrclib.net), API abierta y
/// gratuita sin API key.
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

  Future<Lyrics?> fetch(Track track) async {
    if (_cache.containsKey(track.id)) return _cache[track.id];

    final title = _cleanForLookup(track.title);
    Lyrics? lyrics;
    try {
      // 1. Coincidencia exacta (con duración para elegir la versión correcta).
      lyrics = await _get(title, track.artist, track.duration);
      // 2. Búsqueda flexible por título + artista.
      lyrics ??= await _search({'track_name': title, 'artist_name': track.artist});
      // 3. Búsqueda libre.
      lyrics ??= await _search({'q': '$title ${track.artist}'});
    } catch (_) {
      lyrics = null;
    }
    return _cache[track.id] = lyrics;
  }

  Future<Lyrics?> _get(String title, String artist, Duration? duration) async {
    final res = await _http
        .get(
          Uri.https(_host, '/api/get', {
            'track_name': title,
            'artist_name': artist,
            if (duration != null) 'duration': '${duration.inSeconds}',
          }),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return Lyrics.parse(
      synced: json['syncedLyrics'] as String?,
      plain: json['plainLyrics'] as String?,
    );
  }

  Future<Lyrics?> _search(Map<String, String> params) async {
    final res = await _http
        .get(Uri.https(_host, '/api/search', params), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    // Preferir resultados con letra sincronizada.
    final best = list.firstWhere(
      (e) => (e['syncedLyrics'] as String?)?.isNotEmpty ?? false,
      orElse: () => list.first,
    );
    return Lyrics.parse(
      synced: best['syncedLyrics'] as String?,
      plain: best['plainLyrics'] as String?,
    );
  }

  /// Quita "ft./feat." y paréntesis residuales que confunden la búsqueda.
  static String _cleanForLookup(String title) => title
      .replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]'), '')
      .replaceAll(RegExp(r'\s+(ft\.?|feat\.?|featuring)\s+.*$', caseSensitive: false), '')
      .trim();

  void dispose() => _http.close();
}
