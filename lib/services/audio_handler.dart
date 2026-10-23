import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../features/player/models/track.dart';

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

    // Metadatos de la pista actual → pantalla de bloqueo.
    player.currentIndexStream.listen((index) {
      final items = queue.value;
      if (index != null && index < items.length) mediaItem.add(items[index]);
    });

    // Cuando se conoce la duración real, se actualiza el MediaItem para que
    // la barra de progreso del lock screen sea precisa.
    player.durationStream.listen((duration) {
      final index = player.currentIndex;
      final items = [...queue.value];
      if (duration == null || index == null || index >= items.length) return;
      final updated = items[index].copyWith(duration: duration);
      items[index] = updated;
      queue.add(items);
      mediaItem.add(updated);
    });
  }

  // ---------------------------------------------------------------------------
  // Carga de cola
  // ---------------------------------------------------------------------------

  Future<void> loadTracks(List<Track> tracks, {int initialIndex = 0}) async {
    final items = tracks.map(_toMediaItem).toList();
    queue.add(items);
    mediaItem.add(items[initialIndex]);
    await player.setAudioSources(
      [
        for (final item in items)
          AudioSource.uri(Uri.parse(item.extras!['url'] as String), tag: item),
      ],
      initialIndex: initialIndex,
    );
  }

  static MediaItem _toMediaItem(Track t) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
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
    if (player.hasNext) await player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.position > _restartThreshold || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    final effective =
        player.shuffleModeEnabled ? player.shuffleIndices[index] : index;
    await player.seek(Duration.zero, index: effective);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    if (enable) await player.shuffle();
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

  void _broadcastState() {
    final playing = player.playing;
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
        processingState: switch (player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: player.currentIndex,
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
