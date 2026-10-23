import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../services/audio_player_service.dart';
import '../../../services/library_service.dart';
import '../../../services/lyrics_service.dart';
import '../../../services/palette_service.dart';
import '../models/lyrics.dart';
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

  static const zero = ProgressState(
    position: Duration.zero,
    buffered: Duration.zero,
    total: Duration.zero,
  );
}

/// ViewModel del reproductor (MVVM).
///
/// - Estado "lento" (pista actual, play/pause, shuffle, paleta, letras) se
///   notifica vía [ChangeNotifier].
/// - Estado "rápido" (posición) se expone como [Stream] para que solo la
///   barra de progreso o las letras se reconstruyan con alta frecuencia.
class PlayerViewModel extends ChangeNotifier {
  PlayerViewModel({
    required AudioPlayerService audioService,
    PaletteService? paletteService,
    LyricsService? lyricsService,
    LibraryService? libraryService,
    required List<Track> queue,
    int initialIndex = 0,
  })  : _audio = audioService,
        _palettes = paletteService ?? PaletteService(),
        _lyricsService = lyricsService ?? LyricsService(),
        _libraryService = libraryService ?? LibraryService.instance,
        _queue = List<Track>.from(queue),
        _currentIndex =
            queue.isEmpty ? 0 : initialIndex.clamp(0, queue.length - 1);

  final AudioPlayerService _audio;
  final PaletteService _palettes;
  final LyricsService _lyricsService;
  final LibraryService _libraryService;
  final List<Track> _queue;
  final List<StreamSubscription<dynamic>> _subs = [];

  int _currentIndex;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  ArtworkPalette _palette = ArtworkPalette.fallback;
  Lyrics? _lyrics;
  bool _isLoadingLyrics = false;
  String? _error;

  // ---- Getters expuestos a la vista ----
  Track get currentTrack => _queue[_currentIndex];
  List<Track> get queue => List.unmodifiable(_queue);
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get shuffle => _shuffle;
  LoopMode get loopMode => _loopMode;
  ArtworkPalette get palette => _palette;
  Lyrics? get lyrics => _lyrics;
  bool get isLoadingLyrics => _isLoadingLyrics;
  String? get error => _error;
  LibraryService get libraryService => _libraryService;
  bool get isCurrentTrackFavorite =>
      _libraryService.isFavorite(currentTrack.id);

  Duration get currentPosition => _audio.position;
  Stream<Duration> get positionStream => _audio.positionStream;

  Stream<ProgressState> get progressStream {
    late StreamController<ProgressState> controller;
    var position = Duration.zero;
    var buffered = Duration.zero;
    var total = currentTrack.duration ?? Duration.zero;
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
            total = d ?? currentTrack.duration ?? Duration.zero;
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
    _isPlaying = _audio.playing;
    _shuffle = _audio.shuffleEnabled;
    _loopMode = _audio.loopMode;

    _libraryService.addListener(_onLibraryChanged);

    _subs
      ..add(_audio.playbackStateStream.listen((state) {
        final loading =
            state.processingState == AudioProcessingState.loading ||
            state.processingState == AudioProcessingState.buffering;
        if (_isPlaying != state.playing || _isLoading != loading) {
          _isPlaying = state.playing;
          _isLoading = loading;
          notifyListeners();
        }
      }))
      ..add(_audio.currentTrackStream.listen((track) {
        if (track == null) return;
        final idx = _queue.indexWhere((t) => t.id == track.id);
        if (idx != -1) {
          final changed = idx != _currentIndex;
          _queue[idx] = track;
          _currentIndex = idx;
          notifyListeners();
          if (changed) {
            _updatePalette();
            _updateLyrics();
          }
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

    unawaited(_updatePalette());
    unawaited(_updateLyrics());

    try {
      await _audio.loadQueue(_queue, initialIndex: _currentIndex);
    } catch (e) {
      _error = 'No se pudo reproducir el stream: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _updatePalette() async {
    final track = currentTrack;
    final palette = await _palettes.fromTrack(track);
    if (track.id == currentTrack.id) {
      _palette = palette;
      notifyListeners();
    }
  }

  Future<void> _updateLyrics() async {
    final track = currentTrack;
    _isLoadingLyrics = true;
    _lyrics = null;
    notifyListeners();

    final result = await _lyricsService.fetch(track);
    if (track.id == currentTrack.id) {
      _lyrics = result;
      _isLoadingLyrics = false;
      notifyListeners();
    }
  }

  void _onLibraryChanged() {
    notifyListeners();
  }

  // ---- Acciones (intents de la vista) ----
  Future<void> toggleCurrentTrackFavorite() =>
      _libraryService.toggleFavorite(currentTrack);

  void togglePlayPause() => _isPlaying ? _audio.pause() : _audio.play();

  void seek(Duration position) => _audio.seek(position);

  void next() => _audio.skipToNext();

  void previous() => _audio.skipToPrevious();

  void toggleShuffle() => _audio.setShuffle(!_shuffle);

  void cycleLoopMode() {
    const order = [LoopMode.off, LoopMode.all, LoopMode.one];
    _audio.setLoopMode(order[(order.indexOf(_loopMode) + 1) % order.length]);
  }

  @override
  void dispose() {
    _libraryService.removeListener(_onLibraryChanged);
    for (final s in _subs) {
      s.cancel();
    }
    // El reproductor NO se libera aquí: pertenece al Background Service y
    // debe seguir sonando aunque la vista se destruya.
    super.dispose();
  }
}
