import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_music/core/settings_manager.dart';
import 'package:ghost_music/features/downloads/models/offline_package.dart';
import 'package:ghost_music/features/player/models/track.dart';
import 'package:ghost_music/services/audio_router_service.dart';
import 'package:ghost_music/services/download_service.dart';
import 'package:ghost_music/services/lyrics_service.dart';
import 'package:ghost_music/services/search_service.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingSearchService extends SearchService {
  @override
  Future<String?> getStreamUrl(Track track) {
    throw StateError('Nivel 0 falló: se invocó SearchService en lugar de disco');
  }

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    bool resolveStreams = false,
  }) {
    throw StateError('No se esperaba llamada de red a SearchService');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<Map<dynamic, dynamic>> hiveBox;

  const testTrack = Track(
    id: 'yt_test_offline_123',
    title: 'Starboy',
    artist: 'The Weeknd',
    album: 'Starboy',
    artworkUrl: 'https://example.com/starboy.jpg',
    duration: Duration(minutes: 3, seconds: 50),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('ghost_offline_test_');
    Hive.init(tempDir.path);
    hiveBox = await Hive.openBox<Map<dynamic, dynamic>>('offline_packages_test_box');
  });

  tearDown(() async {
    await hiveBox.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SettingsManager - Calidad de Descarga Offline', () {
    test('downloadQuality por defecto es high y se guarda independientemente de streaming', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsManager(prefs: prefs);
      await settings.init();

      // Valores por defecto
      expect(settings.audioQuality, AudioQuality.dataSaver);
      expect(settings.downloadQuality, AudioQuality.high);

      // Cambiar calidad de descarga
      await settings.setDownloadQuality(AudioQuality.lossless);
      expect(settings.downloadQuality, AudioQuality.lossless);
      // Streaming debe mantenerse inalterado
      expect(settings.audioQuality, AudioQuality.dataSaver);

      // Cambiar calidad de streaming
      await settings.setAudioQuality(AudioQuality.high);
      expect(settings.audioQuality, AudioQuality.high);
      expect(settings.downloadQuality, AudioQuality.lossless);

      // Comprobar persistencia recargando desde SharedPreferences
      final reloaded = SettingsManager(prefs: prefs);
      await reloaded.init();
      expect(reloaded.audioQuality, AudioQuality.high);
      expect(reloaded.downloadQuality, AudioQuality.lossless);
    });
  });

  group('Nivel 0 Local-First: DownloadService, AudioRouter & LyricsService', () {
    test('empaqueta en disco y verifica Nivel 0 en AudioRouterService sin red', () async {
      // 1. Crear archivos locales simulados en tempDir
      final trackDir = Directory('${tempDir.path}/yt_test_offline_123');
      trackDir.createSync(recursive: true);

      final audioFile = File('${trackDir.path}/audio.m4a');
      audioFile.writeAsStringSync('fake_audio_stream_bytes');

      final artworkFile = File('${trackDir.path}/artwork.jpg');
      artworkFile.writeAsStringSync('fake_artwork_bytes');

      final lrcFile = File('${trackDir.path}/lyrics.lrc');
      lrcFile.writeAsStringSync(
        '[00:10.50] I am trying to put you in the worst mood, ah\n'
        '[00:15.00] P1 cleaner than your church shoes, ah\n',
      );

      final pkg = OfflinePackage(
        track: testTrack,
        localAudioPath: audioFile.path,
        localArtworkPath: artworkFile.path,
        localLrcPath: lrcFile.path,
        downloadedAt: DateTime.now(),
        fileSizeBytes: audioFile.lengthSync(),
        quality: AudioQuality.high,
      );

      // 2. Guardar en Box de Hive
      await hiveBox.put(testTrack.id, pkg.toMap());

      // 3. Inicializar DownloadService con el Box y directorio
      final downloadService = DownloadService(
        box: hiveBox,
        baseDirPath: tempDir.path,
      );
      await downloadService.init(customStoragePath: tempDir.path);

      expect(downloadService.isDownloaded(testTrack.id), isTrue);
      expect(downloadService.getDownloadedTracks().length, 1);
      expect(downloadService.getDownloadedTracks().first.id, testTrack.id);
      // El paquete en Hive almacena el track sin URL efímera de red
      expect(downloadService.getPackage(testTrack.id)?.track.audioUrl, isNull);
      // Pero para la reproducción offline, expone la ruta local del archivo
      expect(
        downloadService.getDownloadedTracks().first.audioUrl,
        audioFile.path,
      );

      // 4. Test AudioRouterService Nivel 0
      final failingSearch = _FailingSearchService();
      final audioRouter = AudioRouterService(
        searchService: failingSearch,
        downloadService: downloadService,
      );

      final resolvedPath = await audioRouter.resolveAudioUrl(testTrack);
      expect(resolvedPath, audioFile.path);

      // 5. Test LyricsService Nivel 0
      final lyricsService = LyricsService(
        downloadService: downloadService,
      );

      final lyrics = await lyricsService.fetch(testTrack);
      expect(lyrics, isNotNull);
      expect(lyrics!.lines.length, 2);
      expect(lyrics.lines[0].text, 'I am trying to put you in the worst mood, ah');
      expect(lyrics.lines[0].time, const Duration(seconds: 10, milliseconds: 500));
      expect(lyrics.lines[1].text, 'P1 cleaner than your church shoes, ah');
      expect(lyrics.lines[1].time, const Duration(seconds: 15));

      // 6. Eliminar paquete offline
      await downloadService.deleteDownload(testTrack.id);
      expect(downloadService.isDownloaded(testTrack.id), isFalse);
      expect(downloadService.getDownloadedTracks(), isEmpty);
      expect(audioFile.existsSync(), isFalse);
      expect(artworkFile.existsSync(), isFalse);
      expect(lrcFile.existsSync(), isFalse);
    });
  });
}
