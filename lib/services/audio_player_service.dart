import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../core/settings_manager.dart';
import '../features/player/models/track.dart';
import 'audio_handler.dart';
import 'audio_router_service.dart';
import 'search_service.dart';

/// Fachada que consume el ViewModel.
///
/// - **Comandos** → se envían al [GhostAudioHandler] (Background Service), así
///   la UI y la pantalla de bloqueo comparten exactamente el mismo flujo.
/// - **Streams** → se leen del motor `just_audio` y del handler subyacente.
class AudioPlayerService {
  AudioPlayerService(
    this._handler, {
    SearchService? searchService,
    AudioRouterService? audioRouter,
  }) {
    if (searchService != null) {
      _handler.searchService = searchService;
    }
    if (audioRouter != null) {
      _handler.audioRouter = audioRouter;
    } else if (searchService != null) {
      _handler.audioRouter = AudioRouterService(searchService: searchService);
    }
  }

  final GhostAudioHandler _handler;
  AudioQuality? _lastLoadedQuality;
  AudioPlayer get _player => _handler.player;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<PlaybackState> get playbackStateStream => _handler.playbackState;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get bufferedPositionStream =>
      _player.bufferedPositionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Track?> get currentTrackStream => _handler.currentTrackStream;
  Stream<bool> get shuffleModeEnabledStream =>
      _player.shuffleModeEnabledStream;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;

  bool get playing => _player.playing;
  Duration get position => _player.position;
  int get currentIndex => _handler.currentTrackIndex;
  Track? get currentTrack => _handler.currentTrack;
  List<Track> get currentQueue => _handler.currentTracks;
  bool get shuffleEnabled => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;

  /// Carga una cola de pistas y comienza a reproducir en [initialIndex].
  /// Si la misma pista ya está activa y sonando, evita reiniciar el stream.
  Future<void> loadQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) return;
    final target = tracks[initialIndex.clamp(0, tracks.length - 1)];
    final current = _handler.currentTrack;
    final loadedIds = _handler.currentTracks.map((t) => t.id).toList();
    final newIds = tracks.map((t) => t.id).toList();

    final selectedQuality = SettingsManager.instance.audioQuality;
    if (current != null &&
        current.id == target.id &&
        _lastLoadedQuality == selectedQuality &&
        _listEquals(loadedIds, newIds) &&
        _player.processingState != ProcessingState.idle) {
      if (autoPlay && !_player.playing) {
        await _handler.play();
      }
      return;
    }

    _lastLoadedQuality = selectedQuality;
    await _handler.loadTracks(
      tracks,
      initialIndex: initialIndex,
      autoPlay: autoPlay,
    );
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
