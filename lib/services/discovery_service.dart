import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/player/models/track.dart';

/// Servicio de descubrimiento musical y tendencias globales utilizando la API de Deezer.
///
/// Ofrece:
/// - Top 20/30 Éxitos Globales en tiempo real.
/// - Canciones de artistas afines/similares.
/// - Mezclas por género o estado de ánimo.
/// - Caché en memoria con TTL de 2 horas para optimizar el rendimiento y datos.
class DiscoveryService {
  DiscoveryService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  static final DiscoveryService instance = DiscoveryService();

  final http.Client _http;

  static const _host = 'api.deezer.com';
  static const _cacheTtl = Duration(hours: 2);

  List<Track>? _topChartCache;
  DateTime? _topChartCachedAt;

  final Map<String, List<Track>> _relatedCache = {};
  final Map<String, DateTime> _relatedCachedAt = {};

  final Map<String, List<Track>> _genreCache = {};
  final Map<String, DateTime> _genreCachedAt = {};

  /// Obtiene el Top 20 Global de canciones más escuchadas del momento.
  Future<List<Track>> getTopTracks({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _topChartCache != null &&
        _topChartCachedAt != null &&
        now.difference(_topChartCachedAt!) < _cacheTtl) {
      return _topChartCache!;
    }

    try {
      final uri = Uri.https(_host, '/chart/0/tracks', {'limit': '30'});
      final res = await _http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return _topChartCache ?? const [];

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return _topChartCache ?? const [];

      final data = decoded['data'];
      if (data is! List) return _topChartCache ?? const [];

      final tracks = <Track>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final track = _mapDeezerItemToTrack(item);
          if (track != null) tracks.add(track);
        }
      }

      if (tracks.isNotEmpty) {
        _topChartCache = tracks;
        _topChartCachedAt = now;
      }
      return tracks;
    } catch (_) {
      return _topChartCache ?? const [];
    }
  }

  /// Busca artistas similares a [artistName] y retorna sus temas más populares.
  Future<List<Track>> fetchRelatedTracks(String artistName) async {
    final clean = artistName.trim().toLowerCase();
    if (clean.isEmpty) return const [];

    final now = DateTime.now();
    final cached = _relatedCache[clean];
    final cachedAt = _relatedCachedAt[clean];
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _cacheTtl) {
      return cached;
    }

    try {
      // 1. Obtener ID del artista en Deezer
      final searchUri =
          Uri.https(_host, '/search/artist', {'q': clean, 'limit': '1'});
      final searchRes =
          await _http.get(searchUri).timeout(const Duration(seconds: 6));
      if (searchRes.statusCode != 200) return const [];

      final searchJson = jsonDecode(searchRes.body);
      final artists = searchJson['data'] as List?;
      if (artists == null || artists.isEmpty) return const [];

      final artistId = artists.first['id']?.toString();
      if (artistId == null) return const [];

      // 2. Obtener hasta 3 artistas relacionados
      final relatedUri =
          Uri.https(_host, '/artist/$artistId/related', {'limit': '3'});
      final relatedRes =
          await _http.get(relatedUri).timeout(const Duration(seconds: 6));
      final relatedJson =
          relatedRes.statusCode == 200 ? jsonDecode(relatedRes.body) : null;
      final relatedArtists = (relatedJson?['data'] as List?) ?? [];

      final combinedTracks = <Track>[];
      final targetArtistIds = <String>[
        artistId,
        ...relatedArtists.take(2).map((a) => a['id'].toString()),
      ];

      // 3. Extraer los mejores temas de cada artista
      for (final id in targetArtistIds) {
        final topUri = Uri.https(_host, '/artist/$id/top', {'limit': '6'});
        final topRes =
            await _http.get(topUri).timeout(const Duration(seconds: 5));
        if (topRes.statusCode == 200) {
          final topJson = jsonDecode(topRes.body);
          final items = topJson['data'] as List?;
          if (items != null) {
            for (final item in items) {
              if (item is Map<String, dynamic>) {
                final track = _mapDeezerItemToTrack(item);
                if (track != null &&
                    !combinedTracks.any((t) => t.title == track.title)) {
                  combinedTracks.add(track);
                }
              }
            }
          }
        }
      }

      if (combinedTracks.isNotEmpty) {
        _relatedCache[clean] = combinedTracks;
        _relatedCachedAt[clean] = now;
      }
      return combinedTracks;
    } catch (_) {
      return const [];
    }
  }

  /// Obtiene canciones populares filtradas por género o estado de ánimo.
  Future<List<Track>> getGenreTracks(String genre) async {
    final clean = genre.trim().toLowerCase();
    final now = DateTime.now();
    final cached = _genreCache[clean];
    final cachedAt = _genreCachedAt[clean];
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _cacheTtl) {
      return cached;
    }

    try {
      final uri = Uri.https(_host, '/search', {'q': genre, 'limit': '25'});
      final res = await _http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];

      final decoded = jsonDecode(res.body);
      final data = decoded['data'] as List?;
      if (data == null) return const [];

      final tracks = <Track>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final track = _mapDeezerItemToTrack(item);
          if (track != null) tracks.add(track);
        }
      }

      if (tracks.isNotEmpty) {
        _genreCache[clean] = tracks;
        _genreCachedAt[clean] = now;
      }
      return tracks;
    } catch (_) {
      return const [];
    }
  }

  /// Mapea un objeto track de la API de Deezer al modelo [Track] de la app.
  Track? _mapDeezerItemToTrack(Map<String, dynamic> item) {
    try {
      final id = item['id']?.toString();
      final title = item['title'] as String?;
      final artistObj = item['artist'] as Map<String, dynamic>?;
      final albumObj = item['album'] as Map<String, dynamic>?;
      final artistName = artistObj?['name'] as String? ?? 'Artista';
      final albumTitle = albumObj?['title'] as String? ?? '';
      final durationSec = (item['duration'] as num?)?.toInt() ?? 0;

      final coverXl = albumObj?['cover_xl'] as String?;
      final coverBig = albumObj?['cover_big'] as String?;
      final coverMed = albumObj?['cover_medium'] as String?;
      final artistPic = artistObj?['picture_xl'] as String? ??
          artistObj?['picture_big'] as String?;

      final artworkUrl = coverXl ?? coverBig ?? coverMed ?? artistPic;
      if (id == null || title == null || artworkUrl == null) return null;

      return Track(
        id: 'dz_$id',
        title: title,
        artist: artistName,
        album: albumTitle,
        artworkUrl: artworkUrl,
        fallbackArtworkUrl: coverMed ?? coverBig,
        duration: durationSec > 0 ? Duration(seconds: durationSec) : null,
      );
    } catch (_) {
      return null;
    }
  }

  void clearCache() {
    _topChartCache = null;
    _topChartCachedAt = null;
    _relatedCache.clear();
    _relatedCachedAt.clear();
    _genreCache.clear();
    _genreCachedAt.clear();
  }
}
