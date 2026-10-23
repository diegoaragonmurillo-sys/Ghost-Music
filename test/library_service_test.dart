import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_music/features/player/models/track.dart';
import 'package:ghost_music/services/audio_handler.dart';
import 'package:ghost_music/services/library_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sampleTrack1 = Track(
    id: 'yt_blinding_lights',
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    album: 'After Hours',
    artworkUrl: 'https://example.com/maxres.jpg',
    fallbackArtworkUrl: 'https://example.com/hq.jpg',
    audioUrl: 'https://ephemeral-stream.youtube.com/audio.mp4',
    duration: Duration(minutes: 3, seconds: 20),
  );

  const sampleTrack2 = Track(
    id: 'yt_get_lucky',
    title: 'Get Lucky',
    artist: 'Daft Punk',
    album: 'Random Access Memories',
    artworkUrl: 'https://example.com/daft_max.jpg',
    fallbackArtworkUrl: 'https://example.com/daft_hq.jpg',
    audioUrl: 'https://ephemeral-stream.youtube.com/daft.mp4',
    duration: Duration(minutes: 4, seconds: 8),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'toggleFavorite añade, persiste sin audioUrl efímero y elimina al alternar',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final service = LibraryService(prefs: prefs);
      await service.init();

      expect(service.isFavorite(sampleTrack1.id), isFalse);

      // 1. Añadir a favoritos.
      await service.toggleFavorite(sampleTrack1);
      expect(service.isFavorite(sampleTrack1.id), isTrue);
      expect(service.favorites.length, 1);
      expect(service.favorites.first.audioUrl, isNull);

      // 2. Recargar desde una nueva instancia para verificar persistencia real.
      final reloadedService = LibraryService(prefs: prefs);
      await reloadedService.init();
      expect(reloadedService.isFavorite(sampleTrack1.id), isTrue);
      expect(reloadedService.favorites.first.id, sampleTrack1.id);
      expect(reloadedService.favorites.first.title, sampleTrack1.title);
      expect(reloadedService.favorites.first.duration, sampleTrack1.duration);
      expect(reloadedService.favorites.first.audioUrl, isNull);

      // 3. Quitar de favoritos al volver a llamar toggleFavorite.
      await reloadedService.toggleFavorite(sampleTrack1);
      expect(reloadedService.isFavorite(sampleTrack1.id), isFalse);
      expect(reloadedService.favorites, isEmpty);
    },
  );

  test(
    'crea playlists, evita duplicados, elimina pistas individuales y borra la playlist',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final service = LibraryService(prefs: prefs);
      await service.init();

      // 1. Crear playlist con pista inicial.
      final playlist = await service.createPlaylist(
        'Synthwave & Pop',
        initialTrack: sampleTrack1,
      );
      expect(service.playlists.length, 1);
      expect(service.playlists.first.name, 'Synthwave & Pop');
      expect(service.playlists.first.tracks.length, 1);
      expect(service.playlists.first.tracks.first.audioUrl, isNull);

      // 2. Añadir la misma pista dos veces no debe duplicarla.
      await service.addTrackToPlaylist(playlist.id, sampleTrack1);
      await service.addTrackToPlaylist(playlist.id, sampleTrack1);
      expect(service.playlists.first.tracks.length, 1);

      // 3. Añadir una segunda pista distinta.
      await service.addTrackToPlaylist(playlist.id, sampleTrack2);
      expect(service.playlists.first.tracks.length, 2);
      expect(service.playlists.first.tracks.last.id, sampleTrack2.id);
      expect(service.playlists.first.tracks.last.audioUrl, isNull);

      // 4. Renombrar playlist y verificar persistencia en nueva instancia.
      await service.renamePlaylist(playlist.id, 'Favoritas Nocturnas');
      final reloaded = LibraryService(prefs: prefs);
      await reloaded.init();
      expect(reloaded.playlists.first.name, 'Favoritas Nocturnas');
      expect(reloaded.playlists.first.tracks.length, 2);

      // 5. Eliminar una pista individual de la playlist.
      await reloaded.removeTrackFromPlaylist(playlist.id, sampleTrack1.id);
      expect(reloaded.playlists.first.tracks.length, 1);
      expect(reloaded.playlists.first.tracks.first.id, sampleTrack2.id);

      // 6. Borrar la playlist completa.
      await reloaded.deletePlaylist(playlist.id);
      expect(reloaded.playlists, isEmpty);
    },
  );

  test(
    'GhostAudioHandler.pickNextShuffleIndex elige índices aleatorios distintos de currentIndex',
    () {
      expect(GhostAudioHandler.pickNextShuffleIndex(0, 1), 0);

      final rng = math.Random(42);
      const length = 5;
      for (var current = 0; current < length; current++) {
        final seen = <int>{};
        for (var i = 0; i < 40; i++) {
          final next =
              GhostAudioHandler.pickNextShuffleIndex(current, length, rng);
          expect(next, inInclusiveRange(0, length - 1));
          expect(next, isNot(equals(current)));
          seen.add(next);
        }
        // Con 40 muestras sobre 4 opciones posibles, debe cubrir varios índices distintos.
        expect(seen.length, greaterThan(1));
      }
    },
  );
}
