import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../services/audio_player_service.dart';
import '../../../services/palette_service.dart';
import '../models/track.dart';

/// Estado de progreso agrupado para la barra de reproducción.
class ProgressState {
  const ProgressState({
    required this.position,
    required this.buffered,
    required this.total,
  });

  final Duration position;
  final Duration buffered;
  final Duration total;

  static const zero =
      ProgressState(position: Duration.zero, buffered: Duration.zero, total: Duration.zero);
}

/// ViewModel del reproductor (MVVM).
///
/// - Estado "lento" (pista actual, play/pause, shuffle, paleta) se notifica
///   vía [ChangeNotifier].
/// - Estado "rápido" (posición) se expone como [Stream] para que solo la
///   barra de progreso se reconstruya ~60 veces/seg, no toda la pantalla.
class PlayerViewModel extends ChangeNotifier {
  PlayerViewModel({
    AudioPlayerService? audioService,
    PaletteService? paletteService,
    this._queue = demoQueue,
  })  : _audio = audioService ?? AudioPlayerService(),
        _palettes = paletteService ?? PaletteService();

  final AudioPlayerService _audio;
  final PaletteService _palettes;
  final List<Track> _queue;
  final List<StreamSubscription<dynamic>> _subs = [];

  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  ArtworkPalette _palette = ArtworkPalette.fallback;
  String? _error;

  // ---- Getters expuestos a la vista ----
  Track get currentTrack => _queue[_currentIndex];
  List<Track> get queue => List.unmodifiable(_queue);
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get shuffle => _shuffle;
  LoopMode get loopMode => _loopMode;
  ArtworkPalette get palette => _palette;
  String? get error => _error;

  Stream<ProgressState> get progressStream {
    // Combina posición + buffer + duración en un único stream.
    late StreamController<ProgressState> controller;
    var position = Duration.zero;
    var buffered = Duration.zero;
    var total = Duration.zero;
    final subs = <StreamSubscription<dynamic>>[];

    void emit() => controller.add(
          ProgressState(position: position, buffered: buffered, total: total),
        );

    controller = StreamController<ProgressState>(
      onListen: () {
        subs
          ..add(_audio.positionStream.listen((p) {
            position = p;
            emit();
          }))
          ..add(_audio.bufferedPositionStream.listen((b) {
            buffered = b;
            emit();
          }))
          ..add(_audio.durationStream.listen((d) {
            total = d ?? Duration.zero;
            emit();
          }));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  // ---- Ciclo de vida ----
  Future<void> init() async {
    _subs
      ..add(_audio.playerStateStream.listen((state) {
        final loading = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        if (_isPlaying != state.playing || _isLoading != loading) {
          _isPlaying = state.playing;
          _isLoading = loading;
          notifyListeners();
        }
      }))
      ..add(_audio.currentIndexStream.listen((index) {
        if (index != null && index != _currentIndex) {
          _currentIndex = index;
          notifyListeners();
          _updatePalette();
        }
      }))
      ..add(_audio.shuffleModeEnabledStream.listen((s) {
        _shuffle = s;
        notifyListeners();
      }))
      ..add(_audio.loopModeStream.listen((m) {
        _loopMode = m;
        notifyListeners();
      }));

    _updatePalette();

    try {
      await _audio.loadQueue(_queue);
      _isLoading = false;
    } catch (e) {
      _error = 'No se pudo cargar el audio: $e';
      _isLoading = false;
    }
    notifyListeners();
  }

  Future<void> _updatePalette() async {
    final url = currentTrack.artworkUrl;
    final palette = await _palettes.fromUrl(url);
    // Evita aplicar una paleta obsoleta si el usuario cambió de pista.
    if (url == currentTrack.artworkUrl) {
      _palette = palette;
      notifyListeners();
    }
  }

  // ---- Acciones (intents de la vista) ----
  void togglePlayPause() => _isPlaying ? _audio.pause() : _audio.play();

  void seek(Duration position) => _audio.seek(position);

  void next() {
    if (_audio.hasNext) _audio.seekToNext();
  }

  /// Comportamiento Spotify/Apple: si han pasado >3 s, reinicia la pista;
  /// si no, salta a la anterior.
  void previous() {
    if (_audio.position > const Duration(seconds: 3) || !_audio.hasPrevious) {
      _audio.seek(Duration.zero);
    } else {
      _audio.seekToPrevious();
    }
  }

  void toggleShuffle() => _audio.setShuffle(!_shuffle);

  void cycleLoopMode() {
    const order = [LoopMode.off, LoopMode.all, LoopMode.one];
    _audio.setLoopMode(order[(order.indexOf(_loopMode) + 1) % order.length]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _audio.dispose();
    super.dispose();
  }
}
