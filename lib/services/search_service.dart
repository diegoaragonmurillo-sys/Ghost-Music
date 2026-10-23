import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../features/player/models/track.dart';

class SearchException implements Exception {
  const SearchException(this.message);
  final String message;

  @override
  String toString() => 'SearchException: $message';
}

/// Motor de búsqueda y resolución de streams (temporal) sobre YouTube.
///
/// Flujo híbrido en dos fases:
/// 1. [search] → metadatos (rápido, una sola petición).
/// 2. [resolveStream] → URL directo audio-only, justo antes de reproducir.
///
/// Si se necesita todo de una vez, `search(query, resolveStreams: true)`
/// devuelve los resultados con el URL del stream ya resuelto.
class SearchService {
  SearchService({YoutubeExplode? youtube, http.Client? httpClient})
      : _yt = youtube ?? YoutubeExplode(),
        _http = httpClient ?? http.Client();

  final YoutubeExplode _yt;
  final http.Client _http;

  /// Descarta directos, intros y mixes/álbumes completos.
  static const _minDuration = Duration(seconds: 45);
  static const _maxDuration = Duration(minutes: 15);

  final Map<String, String> _streamCache = {};

  /// Busca canciones para [query] y las mapea al modelo [Track].
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    bool resolveStreams = false,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final List<Video> videos;
    try {
      final results = await _yt.search.search(q, filter: TypeFilters.video);
      videos = results
          .where((v) =>
              !v.isLive &&
              v.duration != null &&
              v.duration! >= _minDuration &&
              v.duration! <= _maxDuration)
          .take(limit)
          .toList();
    } catch (e) {
      throw SearchException('La búsqueda falló: $e');
    }

    var tracks = await Future.wait(videos.map(_toTrack));
    if (resolveStreams) {
      tracks = await Future.wait(tracks.map(resolveStream));
    }
    return tracks;
  }

  /// Devuelve [track] con su [Track.audioUrl] resuelto.
  Future<Track> resolveStream(Track track) async {
    if (track.isResolved) return track;
    return track.copyWith(audioUrl: await resolveAudioUrl(track.id));
  }

  /// URL directo del stream audio-only de mayor bitrate.
  ///
  /// Se prioriza el contenedor MP4 (AAC) porque es compatible con AVPlayer
  /// (iOS) y ExoPlayer (Android); WebM/Opus no se reproduce en iOS.
  Future<String> resolveAudioUrl(String videoId) async {
    final cached = _streamCache[videoId];
    if (cached != null) return cached;

    try {
      final manifest = await _yt.videos.streams.getManifest(videoId);
      final audio = manifest.audioOnly.toList();
      if (audio.isEmpty) {
        throw const SearchException('El vídeo no tiene stream de audio');
      }
      final mp4 =
          audio.where((s) => s.container == StreamContainer.mp4).toList();
      final pool = mp4.isNotEmpty ? mp4 : audio
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      return _streamCache[videoId] = pool.first.url.toString();
    } on SearchException {
      rethrow;
    } catch (e) {
      throw SearchException('No se pudo obtener el stream: $e');
    }
  }

  Future<Track> _toTrack(Video v) async {
    final meta = parseMetadata(v.title, v.author);
    final hq = v.thumbnails.highResUrl;
    final maxRes = v.thumbnails.maxResUrl;
    return Track(
      id: v.id.value,
      title: meta.title,
      artist: meta.artist,
      artworkUrl: await _exists(maxRes) ? maxRes : hq,
      fallbackArtworkUrl: hq,
      duration: v.duration,
    );
  }

  /// `maxresdefault.jpg` no existe en todos los vídeos (YouTube da 404).
  Future<bool> _exists(String url) async {
    try {
      final res = await _http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static final _artistTitle = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$');
  static final _noise = RegExp(
    r'\s*[\(\[][^\)\]]*(official|video|audio|lyric|letra|visuali[sz]er|'
    r'videoclip|clip|mv|hd|4k|hq|remaster)[^\)\]]*[\)\]]',
    caseSensitive: false,
  );

  /// Limpia títulos de YouTube: "Artista - Canción (Official Video)" →
  /// (title: "Canción", artist: "Artista"). Canales "- Topic" (YouTube Music)
  /// ya traen el título limpio y el artista en el nombre del canal.
  static ({String title, String artist}) parseMetadata(
    String rawTitle,
    String author,
  ) {
    final isTopic = author.endsWith(' - Topic');
    var artist = author
        .replaceAll(RegExp(r'\s*-\s*Topic$'), '')
        .replaceAll(RegExp(r'\s*VEVO$', caseSensitive: false), '')
        .trim();
    var title = rawTitle;

    if (!isTopic) {
      final m = _artistTitle.firstMatch(title);
      if (m != null) {
        artist = m.group(1)!.trim();
        title = m.group(2)!.trim();
      }
    }

    title = title
        .replaceAll(_noise, '')
        .replaceAll(RegExp(r'\s*\|.*$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    return (title: title.isEmpty ? rawTitle : title, artist: artist);
  }

  void dispose() {
    _yt.close();
    _http.close();
  }
}
