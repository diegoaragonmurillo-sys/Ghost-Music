import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../features/player/models/lyrics.dart';
import '../features/player/models/track.dart';
import 'download_service.dart';

/// Servicio de letras sincronizadas mediante LRCLIB (`https://lrclib.net/api/search`),
/// Nivel 0 Local-First (archivos `.lrc` descargados) y ajuste inteligente por duración.
class LyricsService {
  LyricsService({
    http.Client? httpClient,
    this._downloadService,
    this._prefs,
  })  : _http = httpClient ?? http.Client();

  final http.Client _http;
  final DownloadService? _downloadService;
  SharedPreferences? _prefs;
  final Map<String, Lyrics?> _cache = {};

  Future<SharedPreferences> get _effectivePrefs async =>
      _prefs ??= await SharedPreferences.getInstance();

  DownloadService get _downloads =>
      _downloadService ?? DownloadService.instance;

  static const _host = 'lrclib.net';
  static const _headers = {
    'User-Agent':
        'GhostMusic/1.0.0 (https://github.com/diegoaragonmurillo-sys/Ghost-Music)',
  };

  /// Clave en [SharedPreferences] para el offset de sincronización por pista.
  static String _offsetPrefKey(String trackId) => 'lyrics_offset_ms_$trackId';

  /// Obtiene el offset manual guardado en milisegundos para una pista específica.
  Future<int> getTrackOffsetMs(String trackId) async {
    final prefs = await _effectivePrefs;
    return prefs.getInt(_offsetPrefKey(trackId)) ?? 0;
  }

  /// Guarda el offset manual en milisegundos para una pista específica.
  Future<void> setTrackOffsetMs(String trackId, int offsetMs) async {
    final prefs = await _effectivePrefs;
    if (offsetMs == 0) {
      await prefs.remove(_offsetPrefKey(trackId));
    } else {
      await prefs.setInt(_offsetPrefKey(trackId), offsetMs);
    }
  }

  /// Expresión regular estricta para capturar minutos, segundos, milisegundos (2 o 3 dígitos) y texto.
  static final RegExp _lrcRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

  /// Convierte un texto LRC (`[01:15.22] Texto`) en una lista de [LyricLine]
  /// con precisión de milisegundos, conservando pausas instrumentales vacías.
  List<LyricLine> parseLrc(String syncedLyrics) {
    final lines = <LyricLine>[];
    for (final rawLine in syncedLyrics.split('\n')) {
      final match = _lrcRegex.firstMatch(rawLine.trim());
      if (match == null) continue;

      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final msStr = match.group(3)!;
      final milliseconds =
          msStr.length == 2 ? int.parse(msStr) * 10 : int.parse(msStr);
      final text = (match.group(4) ?? '').trim();

      lines.add(
        LyricLine(
          Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text,
        ),
      );
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// Convierte un objeto [Lyrics] a formato LRC estándar para almacenamiento offline.
  String serializeToLrc(Lyrics lyrics) {
    final buffer = StringBuffer();
    for (final line in lyrics.lines) {
      final totalSeconds = line.time.inSeconds;
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;
      final centiseconds = (line.time.inMilliseconds % 1000) ~/ 10;
      final mm = minutes.toString().padLeft(2, '0');
      final ss = seconds.toString().padLeft(2, '0');
      final xx = centiseconds.toString().padLeft(2, '0');
      buffer.writeln('[$mm:$ss.$xx] ${line.text}');
    }
    return buffer.toString().trim();
  }

  /// Obtiene texto LRC crudo para guardar offline.
  Future<String?> fetchRawLrcForOffline(Track track) async {
    final pkg = _downloads.getPackage(track.id);
    if (pkg?.localLrcPath != null) {
      final file = File(pkg!.localLrcPath!);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    }

    final lyrics = await fetch(track);
    if (lyrics == null || lyrics.lines.isEmpty) return null;
    return serializeToLrc(lyrics);
  }

  /// Obtiene y parsea las letras sincronizadas (LRC) para [trackName] y [artistName],
  /// con soporte opcional para [targetDuration].
  Future<List<LyricLine>> fetchSyncedLyrics({
    required String trackName,
    required String artistName,
    Duration? targetDuration,
  }) async {
    final cleanTrack = _cleanForLookup(trackName);
    final cleanArtist = _cleanArtist(artistName);

    final lyrics = await _search(
          {
            'track_name': cleanTrack,
            'artist_name': cleanArtist,
          },
          targetDuration: targetDuration,
        ) ??
        await _search(
          {'q': '$cleanTrack $cleanArtist'},
          targetDuration: targetDuration,
        );

    if (lyrics == null) return const [];
    return lyrics.lines;
  }

  /// Obtiene el objeto [Lyrics] para un [Track] con Nivel 0 y caché en memoria.
  Future<Lyrics?> fetch(Track track) async {
    // -------------------------------------------------------------------------
    // NIVEL 0: Local First (Lectura directa desde archivo .lrc en disco)
    // -------------------------------------------------------------------------
    final pkg = _downloads.getPackage(track.id);
    if (pkg?.localLrcPath != null) {
      final localFile = File(pkg!.localLrcPath!);
      if (localFile.existsSync()) {
        try {
          final content = localFile.readAsStringSync();
          final parsed = Lyrics.parse(synced: content, plain: content);
          if (parsed != null && parsed.lines.isNotEmpty) {
            return _cache[track.id] = parsed;
          }
        } catch (_) {}
      }
    }

    if (_cache.containsKey(track.id)) return _cache[track.id];

    final title = _cleanForLookup(track.title);
    final artist = _cleanArtist(track.artist);
    Lyrics? lyrics;
    try {
      // 1. Petición GET a https://lrclib.net/api/search pasando track_name, artist_name y targetDuration.
      lyrics = await _search(
        {
          'track_name': title,
          'artist_name': artist,
        },
        targetDuration: track.duration,
      );
      // 2. Fallback por consulta general si los metadatos de YouTube varían.
      lyrics ??= await _search(
        {'q': '$title $artist'},
        targetDuration: track.duration,
      );
    } catch (_) {
      lyrics = null;
    }
    return _cache[track.id] = lyrics;
  }

  Future<Lyrics?> _search(
    Map<String, String> params, {
    Duration? targetDuration,
  }) async {
    final uri = Uri.https(_host, '/api/search', params);
    final res = await _http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;

    final decoded = jsonDecode(res.body);
    if (decoded is! List || decoded.isEmpty) return null;

    final list = decoded.cast<Map<String, dynamic>>();

    // 1. Filtra primero los candidatos con syncedLyrics válido
    final syncedCandidates = <Map<String, dynamic>>[];
    for (final item in list) {
      final synced = item['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) {
        final parsed = parseLrc(synced);
        if (parsed.isNotEmpty) {
          syncedCandidates.add(item);
        }
      }
    }

    if (syncedCandidates.isNotEmpty) {
      Map<String, dynamic> chosenItem = syncedCandidates.first;

      if (targetDuration != null) {
        // Ordena según la menor diferencia absoluta de duración con respecto al audio
        syncedCandidates.sort((a, b) {
          final durA = (a['duration'] as num?)?.toDouble() ?? 0.0;
          final durB = (b['duration'] as num?)?.toDouble() ?? 0.0;
          final diffA = (durA - targetDuration.inSeconds).abs();
          final diffB = (durB - targetDuration.inSeconds).abs();
          return diffA.compareTo(diffB);
        });

        // Intentar preferir match cuya diferencia sea <= 4 segundos
        chosenItem = syncedCandidates.firstWhere(
          (item) {
            final dur = (item['duration'] as num?)?.toDouble();
            if (dur == null) return false;
            return (dur - targetDuration.inSeconds).abs() <= 4.0;
          },
          orElse: () => syncedCandidates.first,
        );
      }

      final parsedLines = parseLrc(chosenItem['syncedLyrics'] as String);
      final lrcDurationSec = (chosenItem['duration'] as num?)?.toDouble();
      var suggestedOffsetMs = 0;

      // Compensación inteligente: si hay una diferencia notable de duración
      // (ej. videoclip con intro hablada de 26s respecto a la versión de estudio,
      // deltaMs será negativo (-26000ms) para retrasar el disparo de las letras).
      if (targetDuration != null &&
          lrcDurationSec != null &&
          lrcDurationSec > 0) {
        final deltaMs =
            (lrcDurationSec * 1000).round() - targetDuration.inMilliseconds;
        if (deltaMs.abs() >= 3000 && deltaMs.abs() <= 60000) {
          suggestedOffsetMs = deltaMs;
        }
      }

      return Lyrics(
        lines: parsedLines,
        isSynced: true,
        suggestedOffsetMs: suggestedOffsetMs,
      );
    }

    // Fallback a letra plana si ninguna entrada tiene tiempos LRC.
    final first = list.first;
    return Lyrics.parse(
      synced: first['syncedLyrics'] as String?,
      plain: first['plainLyrics'] as String?,
    );
  }

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
