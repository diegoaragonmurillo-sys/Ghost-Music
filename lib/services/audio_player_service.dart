import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../core/settings_manager.dart';
import '../features/player/models/track.dart';
import 'audio_handler.dart';
import 'audio_router_service.dart';
import 'search_service.dart';

/// Fachada que consume el ViewModel y las vistas de Ghost Music.
///
/// - **Comandos** → se envían al [GhostAudioHandler] (Background Service), así
///   la UI y la pantalla de bloqueo comparten exactamente el mismo flujo.
/// - **Streams** → se leen del motor `just_audio` y del handler subyacente.
/// - **Sleep Timer** → temporizador de apagado suave con fade-out lineal de volumen en los últimos 20s.
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
  Stream<List<Track>> get queueStream => _handler.queueStream;
  Stream<bool> get shuffleModeEnabledStream =>
      _player.shuffleModeEnabledStream;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;
  Stream<bool> get autoplayStream => _handler.autoplayStream;

  bool get playing => _player.playing;
  Duration get position => _player.position;
  int get currentIndex => _handler.currentTrackIndex;
  Track? get currentTrack => _handler.currentTrack;
  List<Track> get currentQueue => _handler.currentTracks;
  bool get shuffleEnabled => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;
  bool get autoplayEnabled => _handler.autoplayEnabled;
  set autoplayEnabled(bool value) => _handler.autoplayEnabled = value;

  // ---------------------------------------------------------------------------
  // Mutaciones de la cola interactiva ("A continuación")
  // ---------------------------------------------------------------------------

  void insertNext(Track track) => _handler.insertNext(track);
  void appendToQueue(Track track) => _handler.appendToQueue(track);
  void reorderQueue(int oldIndex, int newIndex) =>
      _handler.reorderQueue(oldIndex, newIndex);
  void removeAt(int index) => _handler.removeAt(index);
  Future<void> skipToQueueItem(int index) => _handler.skipToQueueItem(index);

  // ---------------------------------------------------------------------------
  // Temporizador de Apagado (Sleep Timer) con Fade-out suave
  // ---------------------------------------------------------------------------

  Timer? _sleepTimer;
  Duration? _sleepTimerRemaining;
  bool _sleepTimerEndOfTrack = false;
  StreamSubscription<ProcessingState>? _endOfTrackSub;
  StreamSubscription<Duration>? _endOfTrackFadeSub;

  final StreamController<Duration?> _sleepTimerController =
      StreamController<Duration?>.broadcast();

  Duration? get sleepTimerRemaining => _sleepTimerRemaining;
  bool get isSleepTimerActive =>
      _sleepTimer != null || _sleepTimerEndOfTrack;
  bool get isSleepTimerEndOfTrack => _sleepTimerEndOfTrack;
  Stream<Duration?> get sleepTimerStream => _sleepTimerController.stream;

  /// Inicia el Sleep Timer para apagarse tras [duration].
  /// En los últimos 20 segundos reduce gradualmente el volumen antes de pausar.
  void startSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepTimerRemaining = duration;
    _sleepTimerEndOfTrack = false;
    _sleepTimerController.add(_sleepTimerRemaining);

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_sleepTimerRemaining == null) {
        timer.cancel();
        return;
      }

      final updated = _sleepTimerRemaining! - const Duration(seconds: 1);
      if (updated <= Duration.zero) {
        timer.cancel();
        _sleepTimerRemaining = null;
        _sleepTimer = null;
        _sleepTimerController.add(null);
        await pause();
        await _player.setVolume(1.0);
        return;
      }

      _sleepTimerRemaining = updated;
      _sleepTimerController.add(updated);

      // Fade-out lineal en los últimos 20 segundos
      if (updated.inSeconds <= 20) {
        final volume = (updated.inSeconds / 20.0).clamp(0.0, 1.0);
        unawaited(_player.setVolume(volume));
      }
    });
  }

  /// Configura el temporizador para pausar la reproducción cuando termine la pista actual.
  void setSleepTimerEndOfTrack() {
    cancelSleepTimer();
    _sleepTimerEndOfTrack = true;
    _sleepTimerRemaining = null;
    _sleepTimerController.add(null);

    _endOfTrackFadeSub = _player.positionStream.listen((pos) {
      final total = _player.duration;
      if (total != null && total > Duration.zero) {
        final remaining = total - pos;
        if (remaining <= const Duration(seconds: 20) && remaining > Duration.zero) {
          final volume = (remaining.inMilliseconds / 20000.0).clamp(0.0, 1.0);
          unawaited(_player.setVolume(volume));
        }
      }
    });

    _endOfTrackSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        pause();
        cancelSleepTimer();
      }
    });
  }

  /// Cancela el temporizador activo y restaura el volumen normal a 1.0.
  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerRemaining = null;
    _sleepTimerEndOfTrack = false;
    _endOfTrackSub?.cancel();
    _endOfTrackSub = null;
    _endOfTrackFadeSub?.cancel();
    _endOfTrackFadeSub = null;
    unawaited(_player.setVolume(1.0));
    _sleepTimerController.add(null);
  }

  // ---------------------------------------------------------------------------
  // Control de reproducción
  // ---------------------------------------------------------------------------

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
