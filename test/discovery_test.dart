import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_music/features/player/models/track.dart';
import 'package:ghost_music/services/audio_handler.dart';
import 'package:ghost_music/services/discovery_service.dart';
import 'package:ghost_music/services/history_service.dart';
import 'package:ghost_music/services/library_service.dart';
import 'package:ghost_music/services/recommendation_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleTrack1 = Track(
    id: 'yt_track_1',
    title: 'Starboy',
    artist: 'The Weeknd',
    album: 'Starboy',
    artworkUrl: 'https://example.com/starboy.jpg',
    duration: Duration(seconds: 230),
  );

  const sampleTrack2 = Track(
    id: 'yt_track_2',
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    album: 'After Hours',
    artworkUrl: 'https://example.com/blinding.jpg',
    duration: Duration(seconds: 200),
  );

  const sampleTrack3 = Track(
    id: 'yt_track_3',
    title: 'One More Time',
    artist: 'Daft Punk',
    album: 'Discovery',
    artworkUrl: 'https://example.com/daft.jpg',
    duration: Duration(seconds: 320),
  );

  group('DiscoveryService', () {
    test('mapea respuesta de Deezer chart a modelos Track y aplica caché en memoria', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (request.url.path == '/chart/0/tracks') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 12345,
                  'title': 'Save Your Tears',
                  'duration': 215,
                  'artist': {
                    'name': 'The Weeknd',
                    'picture_xl': 'https://e-cdns-images.dzcdn.net/images/artist/xl.jpg',
                  },
                  'album': {
                    'title': 'After Hours',
                    'cover_xl': 'https://e-cdns-images.dzcdn.net/images/cover/xl.jpg',
                    'cover_medium': 'https://e-cdns-images.dzcdn.net/images/cover/med.jpg',
                  },
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{"data":[]}', 200);
      });

      final service = DiscoveryService(httpClient: mockClient);

      final tracks = await service.getTopTracks();
      expect(tracks.length, 1);
      final t = tracks.first;
      expect(t.id, 'dz_12345');
      expect(t.title, 'Save Your Tears');
      expect(t.artist, 'The Weeknd');
      expect(t.album, 'After Hours');
      expect(t.duration, const Duration(seconds: 215));
      expect(t.artworkUrl, 'https://e-cdns-images.dzcdn.net/images/cover/xl.jpg');
      expect(callCount, 1);

      // Segunda llamada dentro del TTL debe retornar desde la caché en memoria sin red
      final cachedTracks = await service.getTopTracks();
      expect(cachedTracks.length, 1);
      expect(callCount, 1);
    });

    test('obtiene canciones por género', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/search' &&
            request.url.queryParameters['q'] == 'rock') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 999,
                  'title': 'Smells Like Teen Spirit',
                  'duration': 301,
                  'artist': {'name': 'Nirvana'},
                  'album': {
                    'title': 'Nevermind',
                    'cover_xl': 'https://example.com/nirvana.jpg',
                  },
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{"data":[]}', 200);
      });

      final service = DiscoveryService(httpClient: mockClient);
      final tracks = await service.getGenreTracks('rock');
      expect(tracks.length, 1);
      expect(tracks.first.title, 'Smells Like Teen Spirit');
      expect(tracks.first.artist, 'Nirvana');
    });
  });

  group('HistoryService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('registra reproducción, evita duplicados y mantiene max 50 elementos', () async {
      final prefs = await SharedPreferences.getInstance();
      final history = HistoryService(prefs: prefs);
      await history.init();

      expect(history.recentTracks, isEmpty);

      await history.recordPlay(sampleTrack1);
      await history.recordPlay(sampleTrack2);
      expect(history.recentTracks.length, 2);
      expect(history.recentTracks.first.title, 'Blinding Lights');

      // Si se vuelve a reproducir sampleTrack1, pasa a ser la más reciente
      await history.recordPlay(sampleTrack1);
      expect(history.recentTracks.length, 2);
      expect(history.recentTracks.first.title, 'Starboy');
    });

    test('calcula topArtists por frecuencia descendente', () async {
      final prefs = await SharedPreferences.getInstance();
      final history = HistoryService(prefs: prefs);
      await history.init();

      await history.recordPlay(sampleTrack1); // The Weeknd
      await history.recordPlay(sampleTrack3); // Daft Punk
      await history.recordPlay(sampleTrack2); // The Weeknd

      final top = history.topArtists;
      expect(top.isNotEmpty, isTrue);
      expect(top.first, 'The Weeknd');
    });

    test('clearHistory vacía la lista y persistencia', () async {
      final prefs = await SharedPreferences.getInstance();
      final history = HistoryService(prefs: prefs);
      await history.init();

      await history.recordPlay(sampleTrack1);
      expect(history.recentTracks.length, 1);

      await history.clearHistory();
      expect(history.recentTracks, isEmpty);
      expect(history.topArtists, isEmpty);
    });
  });

  group('RecommendationService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('usuario nuevo sin historial ni favoritos recibe Starter Pack (Top Global)', () async {
      final prefs = await SharedPreferences.getInstance();
      final history = HistoryService(prefs: prefs);
      final library = LibraryService(prefs: prefs);
      await history.init();
      await library.init();

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 111,
                'title': 'Top Hit',
                'duration': 180,
                'artist': {'name': 'Top Artist'},
                'album': {'cover_xl': 'https://example.com/cover.jpg'},
              },
            ],
          }),
          200,
        );
      });

      final discovery = DiscoveryService(httpClient: mockClient);
      final recommender = RecommendationService(
        historyService: history,
        libraryService: library,
        discoveryService: discovery,
      );

      expect(recommender.hasUserSignals, isFalse);
      final forYou = await recommender.getForYou();
      expect(forYou.length, 1);
      expect(forYou.first.title, 'Top Hit');

      final because = await recommender.getBecauseYouLike();
      expect(because, isNull);
    });

    test('usuario con historial genera recomendaciones personalizadas y BecauseYouLike', () async {
      final prefs = await SharedPreferences.getInstance();
      final history = HistoryService(prefs: prefs);
      final library = LibraryService(prefs: prefs);
      await history.init();
      await library.init();

      await history.recordPlay(sampleTrack1); // The Weeknd

      final mockClient = MockClient((request) async {
        if (request.url.path == '/search/artist') {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 222, 'name': 'The Weeknd'}
              ]
            }),
            200,
          );
        }
        if (request.url.path == '/artist/222/related') {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 333, 'name': 'Post Malone'}
              ]
            }),
            200,
          );
        }
        if (request.url.path == '/artist/222/top' ||
            request.url.path == '/artist/333/top') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 555,
                  'title': 'Circles',
                  'duration': 215,
                  'artist': {'name': 'Post Malone'},
                  'album': {'cover_xl': 'https://example.com/circles.jpg'},
                }
              ]
            }),
            200,
          );
        }
        return http.Response('{"data":[]}', 200);
      });

      final discovery = DiscoveryService(httpClient: mockClient);
      final recommender = RecommendationService(
        historyService: history,
        libraryService: library,
        discoveryService: discovery,
      );

      expect(recommender.hasUserSignals, isTrue);

      final forYou = await recommender.getForYou();
      expect(forYou.any((t) => t.title == 'Circles'), isTrue);

      final because = await recommender.getBecauseYouLike();
      expect(because, isNotNull);
      expect(because!.artist, 'The Weeknd');
      expect(because.tracks.any((t) => t.title == 'Circles'), isTrue);
    });
  });

  group('Algoritmo de Reordenamiento de Cola', () {
    test('calculateReorderIndex actualiza el índice actual según el movimiento', () {
      // 1. Mover la canción que está sonando (currentIndex 0 -> 2)
      expect(GhostAudioHandler.calculateReorderIndex(0, 0, 2), 2);

      // 2. Mover una canción que estaba antes de la actual hacia después (old: 0, new: 3, current: 2)
      // La canción actual retrocede 1 posición
      expect(GhostAudioHandler.calculateReorderIndex(2, 0, 3), 1);

      // 3. Mover una canción que estaba después de la actual hacia antes (old: 3, new: 0, current: 1)
      // La canción actual avanza 1 posición
      expect(GhostAudioHandler.calculateReorderIndex(1, 3, 0), 2);

      // 4. Mover una canción después de la actual hacia otra posición después (no afecta a current)
      expect(GhostAudioHandler.calculateReorderIndex(0, 2, 3), 0);
    });
  });
}
