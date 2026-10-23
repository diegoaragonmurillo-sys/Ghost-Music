import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/library/models/playlist.dart';
import '../features/player/models/track.dart';

/// Servicio persistente de Biblioteca Local (Favoritos y Playlists).
///
/// Sigue la arquitectura MVVM mediante [ChangeNotifier] y almacena solo
/// metadatos (sin `audioUrl` efímero) en [SharedPreferences].
class LibraryService extends ChangeNotifier {
  LibraryService({SharedPreferences? prefs}) {
    _prefs = prefs;
  }

  static final LibraryService instance = LibraryService();

  static const String favoritesPrefKey = 'library_favorites_v1';
  static const String playlistsPrefKey = 'library_playlists_v1';

  SharedPreferences? _prefs;
  final List<Track> _favorites = [];
  final List<Playlist> _playlists = [];
  bool _initialized = false;
  int _idCounter = 0;

  /// Canciones favoritas ordenadas de más reciente a más antigua.
  List<Track> get favorites => List.unmodifiable(_favorites);

  /// Playlists creadas por el usuario.
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  /// Inicializa el servicio leyendo los datos persistidos en [SharedPreferences].
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _loadFromPrefs();
    _initialized = true;
    notifyListeners();
  }

  void _loadFromPrefs() {
    final prefs = _prefs;
    if (prefs == null) return;

    _favorites.clear();
    final rawFavs = prefs.getString(favoritesPrefKey);
    if (rawFavs != null && rawFavs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFavs) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _favorites.add(Track.fromJson(item));
          }
        }
      } catch (_) {
        // Ignora JSON corrupto para no bloquear el inicio de la app.
      }
    }

    _playlists.clear();
    final rawPlaylists = prefs.getString(playlistsPrefKey);
    if (rawPlaylists != null && rawPlaylists.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPlaylists) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _playlists.add(Playlist.fromJson(item));
          }
        }
      } catch (_) {
        // Ignora JSON corrupto.
      }
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized || _prefs == null) {
      await init();
    }
  }

  Future<void> _persistFavorites() async {
    await _ensureInitialized();
    final encoded = jsonEncode(_favorites.map((t) => t.toJson()).toList());
    await _prefs?.setString(favoritesPrefKey, encoded);
  }

  Future<void> _persistPlaylists() async {
    await _ensureInitialized();
    final encoded = jsonEncode(_playlists.map((p) => p.toJson()).toList());
    await _prefs?.setString(playlistsPrefKey, encoded);
  }

  /// Devuelve `true` si la pista con [trackId] está en Favoritos.
  bool isFavorite(String trackId) {
    return _favorites.any((t) => t.id == trackId);
  }

  /// Obtiene una playlist actualizada por su [playlistId].
  Playlist? getPlaylistById(String playlistId) {
    for (final p in _playlists) {
      if (p.id == playlistId) return p;
    }
    return null;
  }

  /// Alterna el estado de favorito de [track]. Si se añade, se limpia
  /// `audioUrl` para evitar guardar URLs temporales que caducan.
  Future<void> toggleFavorite(Track track) async {
    await _ensureInitialized();
    final existingIdx = _favorites.indexWhere((t) => t.id == track.id);
    if (existingIdx >= 0) {
      _favorites.removeAt(existingIdx);
    } else {
      _favorites.insert(0, track.withoutAudioUrl());
    }
    notifyListeners();
    await _persistFavorites();
  }

  /// Crea una nueva [Playlist] con [name] y opcionalmente una pista inicial.
  Future<Playlist> createPlaylist(String name, {Track? initialTrack}) async {
    await _ensureInitialized();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('El nombre de la playlist no puede estar vacío');
    }

    final now = DateTime.now();
    final id = 'pl_${now.microsecondsSinceEpoch}_${++_idCounter}';
    final playlist = Playlist(
      id: id,
      name: trimmed,
      createdAt: now,
      tracks: initialTrack != null
          ? <Track>[initialTrack.withoutAudioUrl()]
          : const <Track>[],
    );

    _playlists.insert(0, playlist);
    notifyListeners();
    await _persistPlaylists();
    return playlist;
  }

  /// Elimina la playlist con [playlistId].
  Future<void> deletePlaylist(String playlistId) async {
    await _ensureInitialized();
    _playlists.removeWhere((p) => p.id == playlistId);
    notifyListeners();
    await _persistPlaylists();
  }

  /// Renombra una playlist existente.
  Future<void> renamePlaylist(String playlistId, String newName) async {
    await _ensureInitialized();
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;

    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;

    _playlists[idx] = _playlists[idx].copyWith(name: trimmed);
    notifyListeners();
    await _persistPlaylists();
  }

  /// Añade [track] a la playlist [playlistId] evitando duplicados por `id`
  /// y limpiando `audioUrl`.
  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    await _ensureInitialized();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;

    final current = _playlists[idx];
    if (current.tracks.any((t) => t.id == track.id)) {
      return;
    }

    final updatedTracks = <Track>[
      ...current.tracks,
      track.withoutAudioUrl(),
    ];
    _playlists[idx] = current.copyWith(tracks: updatedTracks);
    notifyListeners();
    await _persistPlaylists();
  }

  /// Elimina una pista de la playlist [playlistId].
  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    await _ensureInitialized();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;

    final current = _playlists[idx];
    final updatedTracks =
        current.tracks.where((t) => t.id != trackId).toList();
    _playlists[idx] = current.copyWith(tracks: updatedTracks);
    notifyListeners();
    await _persistPlaylists();
  }
}
