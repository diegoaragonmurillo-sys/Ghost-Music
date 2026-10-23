import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_music/features/player/models/lyrics.dart';
import 'package:ghost_music/features/player/models/track.dart';
import 'package:ghost_music/services/lyrics_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _MockHttpClient extends http.BaseClient {
  _MockHttpClient(this.responseJson);
  final String responseJson;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = utf8.encode(responseJson);
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Lyrics Duration-Aware Matching & Sync Engine', () {
    test(
      'selecciona automáticamente el candidato LRC cuya duración coincide con track.duration',
      () async {
        // Simula respuesta de LRCLIB con 2 versiones:
        // 1. Videoclip extendido (240s) con intro hablada
        // 2. Audio oficial de estudio (210s)
        final mockResults = [
          {
            'id': 1,
            'trackName': 'Blinding Lights',
            'artistName': 'The Weeknd',
            'duration': 240.0,
            'syncedLyrics':
                '[00:35.00] I been tryna call (Video Version)\n[00:40.00] I been on my own\n',
          },
          {
            'id': 2,
            'trackName': 'Blinding Lights',
            'artistName': 'The Weeknd',
            'duration': 210.0,
            'syncedLyrics':
                '[00:05.00] I been tryna call (Audio Version)\n[00:10.00] I been on my own\n',
          },
        ];

        final mockClient = _MockHttpClient(jsonEncode(mockResults));
        final service = LyricsService(httpClient: mockClient);

        // Track con duración oficial de 210 segundos (3m 30s)
        const track = Track(
          id: 'yt_blinding_lights',
          title: 'Blinding Lights',
          artist: 'The Weeknd',
          artworkUrl: 'https://example.com/blinding.jpg',
          duration: Duration(seconds: 210),
        );

        final lyrics = await service.fetch(track);

        expect(lyrics, isNotNull);
        expect(lyrics!.isSynced, isTrue);
        // Debe haber seleccionado la versión de 210s (Audio Version)
        expect(lyrics.lines.first.text, 'I been tryna call (Audio Version)');
        expect(lyrics.lines.first.time, const Duration(seconds: 5));
      },
    );

    test(
      'antes de que empiece la primera línea (position < lines.first.time), el índice activo es -1',
      () {
        final lyrics = Lyrics.parse(
          synced:
              '[00:15.50] I said, ooh, I am blinded by the lights\n'
              '[00:22.00] No, I cannot sleep until I feel your touch\n',
        );

        expect(lyrics, isNotNull);
        expect(lyrics!.isSynced, isTrue);

        // A los 0s, 5s o 10s (intro instrumental), debe retornar -1
        expect(lyrics.indexAt(Duration.zero), -1);
        expect(lyrics.indexAt(const Duration(seconds: 5)), -1);
        expect(lyrics.indexAt(const Duration(seconds: 15)), -1);

        // Exactamente al segundo 15.50 y en adelante, se activa la primera línea (índice 0)
        expect(lyrics.indexAt(const Duration(seconds: 15, milliseconds: 500)), 0);
        expect(lyrics.indexAt(const Duration(seconds: 20)), 0);

        // A partir del segundo 22, se activa la segunda línea (índice 1)
        expect(lyrics.indexAt(const Duration(seconds: 22)), 1);
        expect(lyrics.indexAt(const Duration(seconds: 30)), 1);
      },
    );

    test(
      'offset manual por canción persiste en SharedPreferences y desplaza el cálculo activo',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final service = LyricsService(prefs: prefs);

        const trackId = 'yt_test_offset_track';

        // 1. Inicialmente no tiene offset (0)
        expect(await service.getTrackOffsetMs(trackId), 0);

        // 2. Guardar un offset de +3500ms (la voz empezó 3.5s antes de lo esperado en el stream)
        await service.setTrackOffsetMs(trackId, 3500);
        expect(await service.getTrackOffsetMs(trackId), 3500);

        // 3. Verificar persistencia en una nueva instancia del servicio
        final reloadedService = LyricsService(prefs: prefs);
        final persistedOffset = await reloadedService.getTrackOffsetMs(trackId);
        expect(persistedOffset, 3500);

        // 4. Probar que el offset desplaza el cálculo de la línea
        final lyrics = Lyrics.parse(
          synced: '[00:10.00] Primera frase tras intro\n',
        )!;

        const currentStreamTime = Duration(seconds: 7);
        // Sin offset: 7s < 10s -> -1 (intro)
        expect(lyrics.indexAt(currentStreamTime), -1);

        // Con offset de +3500ms: 7s + 3.5s = 10.5s -> la línea 0 ya está activa!
        final adjustedTime = currentStreamTime + Duration(milliseconds: persistedOffset);
        expect(lyrics.indexAt(adjustedTime), 0);

        // 5. Restablecer offset a 0 debe eliminar la clave
        await service.setTrackOffsetMs(trackId, 0);
        expect(await service.getTrackOffsetMs(trackId), 0);
      },
    );

    test(
      'calcula suggestedOffsetMs cuando hay una discrepancia significativa de duración',
      () async {
        final mockResults = [
          {
            'id': 10,
            'trackName': 'Thriller',
            'artistName': 'Michael Jackson',
            'duration': 354.0, // Versión de estudio: 5m 54s
            'syncedLyrics': '[00:20.00] It is close to midnight\n',
          },
        ];

        final mockClient = _MockHttpClient(jsonEncode(mockResults));
        final service = LyricsService(httpClient: mockClient);

        // Video en YouTube que dura 380 segundos (26s más por la intro de cine)
        const videoTrack = Track(
          id: 'yt_thriller_video',
          title: 'Thriller',
          artist: 'Michael Jackson',
          artworkUrl: 'https://example.com/thriller.jpg',
          duration: Duration(seconds: 380),
        );

        final lyrics = await service.fetch(videoTrack);

        expect(lyrics, isNotNull);
        // 354s (LRC) - 380s (Video) = -26s = -26000ms (retrasa las letras 26s)
        expect(lyrics!.suggestedOffsetMs, -26000);

        // Cuando el video va por el segundo 46 (26s intro + 20s canción),
        // al sumar suggestedOffsetMs (-26s) da exactamente 20s, activando [00:20.00].
        const effectivePosition = Duration(seconds: 46);
        final adjustedPosition = effectivePosition +
            Duration(milliseconds: lyrics.suggestedOffsetMs);
        expect(adjustedPosition, const Duration(seconds: 20));
        expect(lyrics.indexAt(adjustedPosition), 0);
      },
    );
  });
}
