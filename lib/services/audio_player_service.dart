import 'package:just_audio/just_audio.dart';

import '../features/player/models/track.dart';

/// Capa de servicio que encapsula `just_audio`.
///
/// La UI nunca habla con el reproductor directamente: lo hace a través del
/// ViewModel, que consume este servicio. Más adelante aquí se integrará
/// `audio_service` para reproducción en segundo plano y controles del sistema.
class AudioPlayerService {
  AudioPlayerService() : _player = AudioPlayer();

  final AudioPlayer _player;

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
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get hasNext => _player.hasNext;
  bool get hasPrevious => _player.hasPrevious;

  Future<void> loadQueue(List<Track> tracks, {int initialIndex = 0}) {
    return _player.setAudioSources(
      tracks.map((t) => AudioSource.uri(Uri.parse(t.audioUrl), tag: t)).toList(),
      initialIndex: initialIndex,
    );
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> seekToNext() => _player.seekToNext();
  Future<void> seekToPrevious() => _player.seekToPrevious();
  Future<void> setShuffle(bool enabled) =>
      _player.setShuffleModeEnabled(enabled);
  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);

  Future<void> dispose() => _player.dispose();
}
