import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../core/settings_manager.dart';
import '../features/downloads/models/offline_package.dart';
import '../features/player/models/track.dart';
import 'audio_router_service.dart';
import 'lyrics_service.dart';

/// Motor y Gestor de Descargas Offline (Nivel 0 Local-First).
///
/// Empaqueta en disco Audio + Carátula + Letras LRC y registra los paquetes
/// en Hive para reproducción instantánea con latencia cero sin conexión.
class DownloadService extends ChangeNotifier {
  DownloadService({
    this._dio,
    this._box,
    this._baseDirPath,
    this._audioRouter,
    this._lyricsService,
  });

  static final DownloadService instance = DownloadService();

  static const String boxName = 'offline_packages_v1';

  Dio? _dio;
  Box<Map<dynamic, dynamic>>? _box;
  String? _baseDirPath;
  AudioRouterService? _audioRouter;
  LyricsService? _lyricsService;

  final Map<String, OfflinePackage> _packages = {};
  final Map<String, DownloadProgress> _progressMap = {};
  final Map<String, CancelToken> _cancelTokens = {};

  bool _initialized = false;

  bool get isInitialized => _initialized;

  Dio get _effectiveDio =>
      _dio ??= Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));

  void attachDependencies({
    AudioRouterService? audioRouter,
    LyricsService? lyricsService,
  }) {
    if (audioRouter != null) _audioRouter = audioRouter;
    if (lyricsService != null) _lyricsService = lyricsService;
  }

  /// Inicializa Hive, la caja de paquetes y carga los archivos existentes.
  Future<void> init({String? customStoragePath}) async {
    if (_initialized && _box != null) return;

    if (_box == null) {
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.initFlutter(customStoragePath);
        _box = await Hive.openBox<Map<dynamic, dynamic>>(boxName);
      } else {
        _box = Hive.box<Map<dynamic, dynamic>>(boxName);
      }
    }

    if (_baseDirPath == null) {
      if (customStoragePath != null) {
        _baseDirPath = '$customStoragePath/ghost_offline';
      } else {
        final docs = await getApplicationDocumentsDirectory();
        _baseDirPath = '${docs.path}/ghost_offline';
      }
    }

    final baseDir = Directory(_baseDirPath!);
    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }

    _packages.clear();
    final box = _box!;
    final keysToDelete = <dynamic>[];

    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw != null) {
        try {
          final pkg = OfflinePackage.fromMap(raw);
          final audioFile = File(pkg.localAudioPath);
          if (audioFile.existsSync()) {
            _packages[pkg.track.id] = pkg;
            _progressMap[pkg.track.id] = DownloadProgress.downloaded;
          } else {
            keysToDelete.add(key);
          }
        } catch (_) {
          keysToDelete.add(key);
        }
      }
    }

    for (final k in keysToDelete) {
      await box.delete(k);
    }

    _initialized = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Consultas Nivel 0 (Síncronas y O(1))
  // ---------------------------------------------------------------------------

  bool isDownloaded(String trackId) => _packages.containsKey(trackId);

  OfflinePackage? getPackage(String trackId) => _packages[trackId];

  DownloadProgress getProgress(String trackId) {
    final current = _progressMap[trackId];
    if (current != null) return current;
    if (isDownloaded(trackId)) return DownloadProgress.downloaded;
    return DownloadProgress.idle;
  }

  List<OfflinePackage> get downloadedPackages {
    final list = _packages.values.toList();
    list.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return list;
  }

  List<Track> get downloadedTracks {
    return downloadedPackages
        .map((p) => p.track.copyWith(audioUrl: p.localAudioPath))
        .toList();
  }

  /// Alias de conveniencia para [downloadedTracks].
  List<Track> getDownloadedTracks() => downloadedTracks;

  int get totalStorageBytes {
    var sum = 0;
    for (final p in _packages.values) {
      sum += p.fileSizeBytes;
    }
    return sum;
  }

  // ---------------------------------------------------------------------------
  // Flujo de Descarga
  // ---------------------------------------------------------------------------

  Future<void> downloadTrack(Track track) async {
    if (isDownloaded(track.id)) return;
    if (_progressMap[track.id]?.status == DownloadTaskStatus.downloading) {
      return;
    }

    _progressMap[track.id] = const DownloadProgress(
      status: DownloadTaskStatus.downloading,
      progress: 0.02,
    );
    notifyListeners();

    final cancelToken = CancelToken();
    _cancelTokens[track.id] = cancelToken;

    final sanitizedId = track.id.replaceAll(RegExp(r'[^\w\-]'), '_');
    final trackDir = Directory('$_baseDirPath/$sanitizedId');
    if (!trackDir.existsSync()) {
      trackDir.createSync(recursive: true);
    }

    final localAudioPath = '${trackDir.path}/audio.m4a';
    final localArtworkPath = '${trackDir.path}/artwork.jpg';
    final localLrcPath = '${trackDir.path}/lyrics.lrc';

    try {
      final quality =
          await SettingsManager.instance.getSavedDownloadQuality();

      final router = _audioRouter;
      if (router == null) {
        throw StateError('AudioRouterService no configurado en DownloadService');
      }

      // 1) Resolver URL remota ignorando local para descargar
      final remoteAudioUrl = await router.resolveAudioUrl(
        track,
        qualityOverride: quality,
        bypassLocal: true,
      );

      // Descarga de audio
      await _effectiveDio.download(
        remoteAudioUrl,
        localAudioPath,
        cancelToken: cancelToken,
        options: Options(
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
          },
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final p = 0.05 + (received / total) * 0.75;
            _progressMap[track.id] = DownloadProgress(
              status: DownloadTaskStatus.downloading,
              progress: p.clamp(0.05, 0.80),
            );
            notifyListeners();
          }
        },
      );

      // 2) Descarga de carátula
      String? savedArtworkPath;
      final artUrl = track.artworkUrl.isNotEmpty
          ? track.artworkUrl
          : track.fallbackArtworkUrl;
      if (artUrl != null &&
          (artUrl.startsWith('http://') || artUrl.startsWith('https://'))) {
        try {
          await _effectiveDio.download(
            artUrl,
            localArtworkPath,
            cancelToken: cancelToken,
          );
          if (File(localArtworkPath).existsSync()) {
            savedArtworkPath = localArtworkPath;
          }
        } catch (_) {
          // Si falla la carátula, continuamos sin abortar
        }
      }

      _progressMap[track.id] = const DownloadProgress(
        status: DownloadTaskStatus.downloading,
        progress: 0.90,
      );
      notifyListeners();

      // 3) Letras LRC
      String? savedLrcPath;
      final lyricsSvc = _lyricsService;
      if (lyricsSvc != null) {
        try {
          final lrcText = await lyricsSvc.fetchRawLrcForOffline(track);
          if (lrcText != null && lrcText.trim().isNotEmpty) {
            final lrcFile = File(localLrcPath);
            await lrcFile.writeAsString(lrcText);
            savedLrcPath = localLrcPath;
          }
        } catch (_) {
          // Letras no disponibles offline
        }
      }

      // Calcular tamaño total
      var fileBytes = 0;
      final audioFile = File(localAudioPath);
      if (audioFile.existsSync()) fileBytes += audioFile.lengthSync();
      if (savedArtworkPath != null) {
        final artFile = File(savedArtworkPath);
        if (artFile.existsSync()) fileBytes += artFile.lengthSync();
      }
      if (savedLrcPath != null) {
        final lFile = File(savedLrcPath);
        if (lFile.existsSync()) fileBytes += lFile.lengthSync();
      }

      final package = OfflinePackage(
        track: track.withoutAudioUrl(),
        localAudioPath: localAudioPath,
        localArtworkPath: savedArtworkPath,
        localLrcPath: savedLrcPath,
        quality: quality,
        fileSizeBytes: fileBytes,
        downloadedAt: DateTime.now(),
      );

      await _box?.put(track.id, package.toMap());
      _packages[track.id] = package;
      _progressMap[track.id] = DownloadProgress.downloaded;
      notifyListeners();
    } catch (e) {
      if (cancelToken.isCancelled) {
        _progressMap[track.id] = DownloadProgress.idle;
      } else {
        _progressMap[track.id] = DownloadProgress(
          status: DownloadTaskStatus.error,
          error: e.toString(),
        );
      }
      // Limpiar archivos parciales si falló la descarga de audio
      if (trackDir.existsSync() && !isDownloaded(track.id)) {
        try {
          trackDir.deleteSync(recursive: true);
        } catch (_) {}
      }
      notifyListeners();
    } finally {
      _cancelTokens.remove(track.id);
    }
  }

  // ---------------------------------------------------------------------------
  // Limpieza y cancelación
  // ---------------------------------------------------------------------------

  Future<void> cancelDownload(String trackId) async {
    final token = _cancelTokens[trackId];
    if (token != null && !token.isCancelled) {
      token.cancel('Cancelado por el usuario');
    }
    _cancelTokens.remove(trackId);
    _progressMap[trackId] = DownloadProgress.idle;
    notifyListeners();
  }

  Future<void> deleteDownload(String trackId) async {
    await cancelDownload(trackId);

    _packages.remove(trackId);
    _progressMap.remove(trackId);
    await _box?.delete(trackId);

    final sanitizedId = trackId.replaceAll(RegExp(r'[^\w\-]'), '_');
    if (_baseDirPath != null) {
      final trackDir = Directory('$_baseDirPath/$sanitizedId');
      if (trackDir.existsSync()) {
        try {
          trackDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> deleteAllDownloads() async {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) token.cancel();
    }
    _cancelTokens.clear();
    _packages.clear();
    _progressMap.clear();

    await _box?.clear();

    if (_baseDirPath != null) {
      final baseDir = Directory(_baseDirPath!);
      if (baseDir.existsSync()) {
        try {
          baseDir.deleteSync(recursive: true);
          baseDir.createSync(recursive: true);
        } catch (_) {}
      }
    }
    notifyListeners();
  }
}
