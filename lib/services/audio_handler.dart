import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../features/player/models/track.dart';
import 'audio_router_service.dart';
import 'discovery_service.dart';
import 'download_service.dart';
import 'history_service.dart';
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
    player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        // ignore: avoid_print
        print('Error nativo del stream: $e');
      },
    );
    _init();
  }

  /// Umbral tipo Spotify/Apple Music: "anterior" reinicia la pista si ya
  /// se reprodujeron más de 3 s.
  static const _restartThreshold = Duration(seconds: 3);

  final AudioPlayer player = AudioPlayer();
  final math.Random _random = math.Random();
  SearchService? searchService;
  AudioRouterService? audioRouter;

  /// Selecciona un índice aleatorio distinto de [currentIndex] cuando hay
  /// al menos 2 pistas en la cola.
  static int pickNextShuffleIndex(
    int currentIndex,
    int length, [
    math.Random? random,
  ]) {
    if (length <= 1) return 0;
    final rng = random ?? math.Random();
    final raw = rng.nextInt(length - 1);
    return raw >= currentIndex ? raw + 1 : raw;
  }

  AudioRouterService? get _effectiveRouter {
    if (audioRouter != null) return audioRouter;
    final search = searchService;
    if (search != null) {
      return audioRouter = AudioRouterService(searchService: search);
    }
    return null;
  }

  List<Track> _tracks = [];
  int _currentIndex = 0;
  int _loadToken = 0;
  bool _recordedForCurrentTrack = false;
  bool _autoplayEnabled = true;
  bool _fetchingAutoplay = false;

  bool get autoplayEnabled => _autoplayEnabled;
  set autoplayEnabled(bool value) {
    if (_autoplayEnabled != value) {
      _autoplayEnabled = value;
      _autoplayController.add(value);
    }
  }

  final StreamController<bool> _autoplayController =
      StreamController<bool>.broadcast();
  Stream<bool> get autoplayStream => _autoplayController.stream;

  final StreamController<List<Track>> _queueController =
      StreamController<List<Track>>.broadcast();
  Stream<List<Track>> get queueStream => _queueController.stream;

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

    // Al superar 15 segundos de reproducción continua de la pista actual,
    // se registra automáticamente en el historial local.
    player.positionStream.listen((pos) {
      if (!_recordedForCurrentTrack && pos >= const Duration(seconds: 15)) {
        final track = currentTrack;
        if (track != null) {
          _recordedForCurrentTrack = true;
          unawaited(HistoryService.instance.recordPlay(track));
        }
      }
    });

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
    if (player.shuffleModeEnabled && _tracks.length > 1) {
      final randomIndex = pickNextShuffleIndex(
        _currentIndex,
        _tracks.length,
        _random,
      );
      await _playIndex(randomIndex, autoPlay: true);
      return;
    }
    if (_currentIndex + 1 < _tracks.length) {
      await _playIndex(_currentIndex + 1, autoPlay: true);
    } else if (player.loopMode == LoopMode.all) {
      await _playIndex(0, autoPlay: true);
    } else if (_autoplayEnabled) {
      await _triggerAutoplay();
    } else if (_autoplayEnabled) {
      await _triggerAutoplay();
    } else {
      await player.pause();
      await player.seek(Duration.zero);
    }
  }

  /// Radio infinita / Autoplay: busca temas afines para seguir reproduciendo
  /// sin interrupción cuando la cola se agota.
  Future<void> _triggerAutoplay() async {
    if (_fetchingAutoplay) return;
    _fetchingAutoplay = true;

    try {
      final track = currentTrack;
      List<Track> candidates = const [];
      if (track != null && track.artist.trim().isNotEmpty) {
        candidates =
            await DiscoveryService.instance.fetchRelatedTracks(track.artist);
      }
      if (candidates.isEmpty) {
        candidates = await DiscoveryService.instance.getTopTracks();
      }

      final existingIds = _tracks.map((t) => t.id).toSet();
      final newTracks = candidates
          .where((t) => !existingIds.contains(t.id))
          .take(5)
          .toList();

      if (newTracks.isNotEmpty) {
        _tracks.addAll(newTracks);
        final items = _tracks.map(_toMediaItem).toList();
        queue.add(items);
        _queueController.add(List.unmodifiable(_tracks));
        await _playIndex(_currentIndex + 1, autoPlay: true);
        return;
      }
    } catch (_) {
      // Ignora errores de conexión y finaliza limpiamente
    } finally {
      _fetchingAutoplay = false;
    }

    await player.pause();
    await player.seek(Duration.zero);
  }

  // ---------------------------------------------------------------------------
  // Mutaciones de la cola interactiva ("A continuación")
  // ---------------------------------------------------------------------------

  /// Inserta una pista para ser reproducida justo a continuación de la actual.
  void insertNext(Track track) {
    if (_tracks.isEmpty) {
      loadTracks([track], initialIndex: 0, autoPlay: true);
      return;
    }
    final insertPos = (_currentIndex + 1).clamp(0, _tracks.length);
    _tracks.insert(insertPos, track);
    final items = _tracks.map(_toMediaItem).toList();
    queue.add(items);
    _queueController.add(List.unmodifiable(_tracks));
    _broadcastState();
  }

  /// Añade una pista al final de la cola de reproducción actual.
  void appendToQueue(Track track) {
    if (_tracks.isEmpty) {
      loadTracks([track], initialIndex: 0, autoPlay: true);
      return;
    }
    _tracks.add(track);
    final items = _tracks.map(_toMediaItem).toList();
    queue.add(items);
    _queueController.add(List.unmodifiable(_tracks));
    _broadcastState();
  }

  /// Calcula el nuevo [currentIndex] tras reordenar un elemento de [oldIndex] a [targetIndex].
  static int calculateReorderIndex(
    int currentIndex,
    int oldIndex,
    int targetIndex,
  ) {
    if (currentIndex == oldIndex) {
      return targetIndex;
    } else if (oldIndex < currentIndex && targetIndex >= currentIndex) {
      return currentIndex - 1;
    } else if (oldIndex > currentIndex && targetIndex <= currentIndex) {
      return currentIndex + 1;
    }
    return currentIndex;
  }

  /// Reordena un elemento en la cola (drag & drop).
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _tracks.length) return;
    final targetIndex = newIndex.clamp(0, _tracks.length - 1);
    if (oldIndex == targetIndex) return;

    final item = _tracks.removeAt(oldIndex);
    _tracks.insert(targetIndex, item);

    _currentIndex =
        calculateReorderIndex(_currentIndex, oldIndex, targetIndex);

    final items = _tracks.map(_toMediaItem).toList();
    queue.add(items);
    _queueController.add(List.unmodifiable(_tracks));
    _broadcastState();
  }

  /// Elimina una pista de la cola en el índice especificado.
  void removeAt(int index) {
    if (index < 0 || index >= _tracks.length) return;

    if (_tracks.length == 1) {
      _tracks.clear();
      queue.add([]);
      _queueController.add([]);
      _currentIndex = 0;
      unawaited(player.stop());
      _broadcastState();
      return;
    }

    final isCurrent = index == _currentIndex;
    _tracks.removeAt(index);

    if (index < _currentIndex) {
      _currentIndex -= 1;
    } else if (isCurrent) {
      if (_currentIndex >= _tracks.length) {
        _currentIndex = _tracks.length - 1;
      }
      _playIndex(_currentIndex, autoPlay: player.playing);
    }

    final items = _tracks.map(_toMediaItem).toList();
    queue.add(items);
    _queueController.add(List.unmodifiable(_tracks));
    _broadcastState();
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
    _queueController.add(List.unmodifiable(_tracks));
    await _playIndex(_currentIndex, autoPlay: autoPlay);
  }

  Future<void> _playIndex(int index, {required bool autoPlay}) async {
    if (index < 0 || index >= _tracks.length) return;
    final token = ++_loadToken;
    _currentIndex = index;
    _recordedForCurrentTrack = false;

    var track = _tracks[index];
    final items = [...queue.value];
    if (index < items.length) {
      mediaItem.add(items[index]);
    }
    _currentTrackController.add(track);
    _broadcastState(forceLoading: true);

    try {
      // Resuelve el stream a través del AudioRouterService aplicando
      // la preferencia de calidad actual y el fallback en cascada.
      final router = _effectiveRouter;
      if (router == null && !track.isResolved) {
        throw StateError(
          'AudioRouterService no configurado en GhostAudioHandler',
        );
      }
      if (router != null) {
        track = await router.resolveStream(track);
        if (token != _loadToken) return;
        _tracks[index] = track;
        if (index < items.length) {
          items[index] = _toMediaItem(track);
          queue.add(items);
          mediaItem.add(items[index]);
        }
        _currentTrackController.add(track);
      }

      final streamUrl = track.audioUrl;
      if (streamUrl == null || streamUrl.isEmpty) {
        throw StateError('No se pudo resolver el URL de audio');
      }

      final isLocalFile = !streamUrl.startsWith('http://') &&
          !streamUrl.startsWith('https://');

      try {
        final AudioSource source;
        final mediaTag = index < items.length ? items[index] : null;
        if (isLocalFile) {
          final cleanPath = streamUrl.startsWith('file://')
              ? Uri.parse(streamUrl).toFilePath()
              : streamUrl;
          source = AudioSource.file(
            cleanPath,
            tag: mediaTag,
          );
        } else {
          source = AudioSource.uri(
            Uri.parse(streamUrl),
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
            },
            tag: mediaTag,
          );
        }
        await player.setAudioSource(source);
      } catch (e) {
        // ignore: avoid_print
        print('Error al asignar setAudioSource: $e');
        rethrow;
      }
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
    final router = _effectiveRouter;
    if (router == null || nextIndex < 0 || nextIndex >= _tracks.length) {
      return;
    }
    final next = _tracks[nextIndex];
    if (next.isResolved) return;
    unawaited(
      router.resolveStream(next).then((resolved) {
        if (nextIndex < _tracks.length && _tracks[nextIndex].id == resolved.id) {
          _tracks[nextIndex] = resolved;
        }
      }).catchError((_) {}),
    );
  }

  static MediaItem _toMediaItem(Track t) {
    Uri artUri;
    final pkg = DownloadService.instance.getPackage(t.id);
    if (pkg?.localArtworkPath != null &&
        File(pkg!.localArtworkPath!).existsSync()) {
      artUri = Uri.file(pkg.localArtworkPath!);
    } else {
      artUri = Uri.parse(t.artworkUrl);
    }

    return MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album.isEmpty ? 'YouTube Music' : t.album,
      duration: t.duration,
      artUri: artUri,
      extras: {'url': t.audioUrl},
    );
  }

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
    if (player.shuffleModeEnabled && _tracks.length > 1) {
      final randomIndex = pickNextShuffleIndex(
        _currentIndex,
        _tracks.length,
        _random,
      );
      await _playIndex(randomIndex, autoPlay: true);
      return;
    }
    if (_currentIndex + 1 < _tracks.length) {
      await _playIndex(_currentIndex + 1, autoPlay: true);
    } else if (player.loopMode == LoopMode.all) {
      await _playIndex(0, autoPlay: true);
    } else if (_autoplayEnabled) {
      await _triggerAutoplay();
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
