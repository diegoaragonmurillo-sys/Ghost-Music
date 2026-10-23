import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../features/player/models/track.dart';
import 'audio_handler.dart';

/// Fachada que consume el ViewModel.
///
/// - **Comandos** → se envían al [GhostAudioHandler] (Background Service), así
///   la UI y la pantalla de bloqueo comparten exactamente el mismo flujo.
/// - **Streams** → se leen del motor `just_audio` subyacente, que ofrece
///   posición y buffer con mayor granularidad para la UI.
class AudioPlayerService {
  AudioPlayerService(this._handler);

  final GhostAudioHandler _handler;
  AudioPlayer get _player => _handler.player;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get bufferedPositionStream =>
      _player.bufferedPositionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  Stream<bool> get shuffleModeEnabledStream =>
      _player.shuffleModeEnabledStream;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;

  bool get playing => _player.playing;
  int? get currentIndex => _player.currentIndex;
  bool get shuffleEnabled => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;

  /// Evita recargar (y cortar la música) si la cola ya está cargada, por
  /// ejemplo al volver a abrir la pantalla mientras suena en background.
  Future<void> loadQueue(List<Track> tracks, {int initialIndex = 0}) async {
    final loadedIds = _handler.queue.value.map((m) => m.id).toList();
    final newIds = tracks.map((t) => t.id).toList();
    if (_listEquals(loadedIds, newIds)) return;
    await _handler.loadTracks(tracks, initialIndex: initialIndex);
  }

  Future<void> play() => _handler.play();
  Future<void> pause() => _handler.pause();
  Future<void> seek(Duration position) => _handler.seek(position);
  Future<void> skipToNext() => _handler.skipToNext();
  Future<void> skipToPrevious() => _handler.skipToPrevious();

  Future<void> setShuffle(bool enabled) => _handler.setShuffleMode(
        enabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      );

  Future<void> setLoopMode(LoopMode mode) => _handler.setRepeatMode(
        switch (mode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
