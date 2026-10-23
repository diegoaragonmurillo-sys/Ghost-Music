import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../features/player/models/track.dart';
import 'search_service.dart';

/// Inicializa el Background Service de audio. Debe llamarse una sola vez
/// en `main()` antes de `runApp`.
///
/// - Android: levanta un Foreground Service `mediaPlayback` con notificación
///   multimedia y MediaSession (pantalla de bloqueo, auriculares, Wear, Auto).
/// - iOS: registra MPNowPlayingInfoCenter + MPRemoteCommandCenter
///   (pantalla de bloqueo, Centro de Control, AirPods).
Future<GhostAudioHandler> initAudioService() {
  return AudioService.init(
    builder: GhostAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.miempresa.ghost_music.channel.audio',
      androidNotificationChannelName: 'Reproducción de música',
      androidNotificationChannelDescription:
          'Controles de reproducción de Ghost Music',
      // Mantiene el servicio en primer plano durante la pausa: evita
      // ForegroundServiceStartNotAllowedException (Android 12+) al reanudar
      // desde la pantalla de bloqueo.
      androidStopForegroundOnPause: false,
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );
}

/// Puente entre `just_audio` (motor) y `audio_service` (SO).
///
/// Es la ÚNICA fuente de verdad de la reproducción: tanto la UI como los
/// controles del sistema (lock screen, notificación, auriculares) envían
/// sus comandos aquí, por lo que el estado siempre es coherente.
class GhostAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  GhostAudioHandler() {
    _init();
  }

  /// Umbral tipo Spotify/Apple Music: "anterior" reinicia la pista si ya
  /// se reprodujeron más de 3 s.
  static const _restartThreshold = Duration(seconds: 3);

  final AudioPlayer player = AudioPlayer();
  SearchService? searchService;

  List<Track> _tracks = const [];
  int _currentIndex = 0;
  int _loadToken = 0;

  List<Track> get currentTracks => List.unmodifiable(_tracks);
  int get currentTrackIndex => _currentIndex;
  Track? get currentTrack =>
      (_tracks.isNotEmpty && _currentIndex >= 0 && _currentIndex < _tracks.length)
          ? _tracks[_currentIndex]
          : null;

  final StreamController<Track?> _currentTrackController =
      StreamController<Track?>.broadcast();
  Stream<Track?> get currentTrackStream => _currentTrackController.stream;

  Future<void> _init() async {
    // Sesión de audio "música": gestiona interrupciones (llamadas, Siri),
    // ducking y pausa al desconectar auriculares.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.becomingNoisyEventStream.listen((_) => pause());

    // Cualquier cambio del motor se refleja en el SO.
    player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object e, StackTrace st) => _broadcastState(),
    );
    player.playingStream.listen((_) => _broadcastState());
    player.shuffleModeEnabledStream.listen((_) => _broadcastState());
    player.loopModeStream.listen((_) => _broadcastState());

    // Al terminar una pista, avanza o repite según el modo actual.
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _onTrackCompleted();
      }
    });

    // Cuando se conoce la duración real, se actualiza el MediaItem para que
    // la barra de progreso del lock screen sea precisa.
    player.durationStream.listen((duration) {
      final index = _currentIndex;
      final items = [...queue.value];
      if (duration == null || index < 0 || index >= items.length) return;
      final updated = items[index].copyWith(duration: duration);
      items[index] = updated;
      queue.add(items);
      mediaItem.add(updated);
      if (index < _tracks.length) {
        _tracks[index] = _tracks[index].copyWith(duration: duration);
      }
    });
  }

  Future<void> _onTrackCompleted() async {
    if (_tracks.isEmpty) return;
    if (player.loopMode == LoopMode.one) {
      await player.seek(Duration.zero);
      await player.play();
      return;
    }
    if (_currentIndex + 1 < _tracks.length) {
      await _playIndex(_currentIndex + 1, autoPlay: true);
    } else if (player.loopMode == LoopMode.all) {
      await _playIndex(0, autoPlay: true);
    } else {
      await player.pause();
      await player.seek(Duration.zero);
    }
  }

  // ---------------------------------------------------------------------------
  // Carga de cola y resolución de streams bajo demanda
  // ---------------------------------------------------------------------------

  Future<void> loadTracks(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) return;
    _tracks = List<Track>.from(tracks);
    _currentIndex = initialIndex.clamp(0, _tracks.length - 1);

    final items = _tracks.map(_toMediaItem).toList();
    queue.add(items);
    await _playIndex(_currentIndex, autoPlay: autoPlay);
  }

  Future<void> _playIndex(int index, {required bool autoPlay}) async {
    if (index < 0 || index >= _tracks.length) return;
    final token = ++_loadToken;
    _currentIndex = index;

    var track = _tracks[index];
    final items = [...queue.value];
    if (index < items.length) {
      mediaItem.add(items[index]);
    }
    _currentTrackController.add(track);
    _broadcastState(forceLoading: true);

    try {
      // Si el track aún no tiene el URL directo del stream, lo resolvemos con
      // SearchService obteniendo el manifiesto audioOnly de YouTube.
      if (!track.isResolved) {
        final resolver = searchService;
        if (resolver == null) {
          throw StateError('SearchService no configurado en GhostAudioHandler');
        }
        track = await resolver.resolveStream(track);
        if (token != _loadToken) return;
        _tracks[index] = track;
        if (index < items.length) {
          items[index] = _toMediaItem(track);
          queue.add(items);
          mediaItem.add(items[index]);
        }
        _currentTrackController.add(track);
      }

      final url = track.audioUrl;
      if (url == null || url.isEmpty) {
        throw StateError('No se pudo resolver el URL de audio');
      }

      await player.setAudioSource(
        AudioSource.uri(Uri.parse(url), tag: items[index]),
      );
      if (token != _loadToken) return;

      if (autoPlay) {
        unawaited(player.play());
      }
      // Pre-resuelve la siguiente pista en segundo plano para cambio instantáneo.
      _prefetchNext(index + 1);
    } catch (e) {
      _broadcastState();
      rethrow;
    }
  }

  void _prefetchNext(int nextIndex) {
    final resolver = searchService;
    if (resolver == null || nextIndex < 0 || nextIndex >= _tracks.length) {
      return;
    }
    final next = _tracks[nextIndex];
    if (next.isResolved) return;
    unawaited(
      resolver.resolveStream(next).then((resolved) {
        if (nextIndex < _tracks.length && _tracks[nextIndex].id == resolved.id) {
          _tracks[nextIndex] = resolved;
        }
      }).catchError((_) {}),
    );
  }

  static MediaItem _toMediaItem(Track t) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album.isEmpty ? 'YouTube Music' : t.album,
        duration: t.duration,
        artUri: Uri.parse(t.artworkUrl),
        extras: {'url': t.audioUrl},
      );

  // ---------------------------------------------------------------------------
  // Comandos (UI + sistema operativo)
  // ---------------------------------------------------------------------------

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_tracks.isEmpty) return;
    if (_currentIndex + 1 < _tracks.length) {
      await _playIndex(_currentIndex + 1, autoPlay: true);
    } else if (player.loopMode == LoopMode.all) {
      await _playIndex(0, autoPlay: true);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_tracks.isEmpty) return;
    if (player.position > _restartThreshold || _currentIndex <= 0) {
      await player.seek(Duration.zero);
    } else {
      await _playIndex(_currentIndex - 1, autoPlay: true);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    await _playIndex(index, autoPlay: true);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    await player.setShuffleModeEnabled(enable);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) {
    return player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => LoopMode.all,
    });
  }

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  /// Android: el usuario descartó la app de recientes → liberar recursos.
  @override
  Future<void> onTaskRemoved() => stop();

  // ---------------------------------------------------------------------------
  // Estado → sistema operativo
  // ---------------------------------------------------------------------------

  void _broadcastState({bool forceLoading = false}) {
    final playing = player.playing;
    final procState = forceLoading
        ? AudioProcessingState.loading
        : switch (player.processingState) {
            ProcessingState.idle => AudioProcessingState.idle,
            ProcessingState.loading => AudioProcessingState.loading,
            ProcessingState.buffering => AudioProcessingState.buffering,
            ProcessingState.ready => AudioProcessingState.ready,
            ProcessingState.completed => AudioProcessingState.completed,
          };

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToQueueItem,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        // Botones visibles en la notificación compacta de Android.
        androidCompactActionIndices: const [0, 1, 2],
        processingState: procState,
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: _currentIndex,
        shuffleMode: player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
      ),
    );
  }
}
