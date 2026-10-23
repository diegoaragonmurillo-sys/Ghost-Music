import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/player/models/track.dart';

/// Servicio de historial de reproducción local de Ghost Music.
///
/// Registra las pistas que el usuario escucha (al superar 15 segundos de reproducción)
/// y mantiene un registro de las últimas 50 canciones en [SharedPreferences].
/// También calcula los artistas más escuchados para alimentar el motor de recomendaciones.
class HistoryService extends ChangeNotifier {
  HistoryService({SharedPreferences? prefs}) {
    _prefs = prefs;
  }

  static final HistoryService instance = HistoryService();

  static const String historyPrefKey = 'history_recent_v1';
  static const int maxHistoryLength = 50;

  SharedPreferences? _prefs;
  final List<Track> _recentTracks = [];
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Historial de pistas reproducidas recientemente, de más reciente a más antigua.
  List<Track> get recentTracks => List.unmodifiable(_recentTracks);

  /// Artistas más frecuentes en el historial, ordenados de mayor a menor frecuencia.
  List<String> get topArtists {
    if (_recentTracks.isEmpty) return const [];

    final frequency = <String, int>{};
    for (final track in _recentTracks) {
      final artist = track.artist.trim();
      if (artist.isNotEmpty) {
        frequency[artist] = (frequency[artist] ?? 0) + 1;
      }
    }

    final sortedEntries = frequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedEntries.map((e) => e.key).toList();
  }

  /// Inicializa el servicio leyendo el historial persistido.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _loadFromPrefs();
    _initialized = true;
    notifyListeners();
  }

  void _loadFromPrefs() {
    final prefs = _prefs;
    if (prefs == null) return;

    _recentTracks.clear();
    final raw = prefs.getString(historyPrefKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _recentTracks.add(Track.fromJson(item));
          }
        }
      } catch (_) {
        // Ignora JSON corrupto para salvaguardar la estabilidad.
      }
    }
  }

  /// Registra la reproducción de una pista.
  ///
  /// Si la pista ya figuraba en el historial, se mueve a la primera posición.
  /// Solo conserva hasta [maxHistoryLength] elementos.
  Future<void> recordPlay(Track track) async {
    // Evita duplicados exactos por ID o por título + artista
    _recentTracks.removeWhere(
      (t) => t.id == track.id || (t.title == track.title && t.artist == track.artist),
    );

    _recentTracks.insert(0, track.withoutAudioUrl());

    if (_recentTracks.length > maxHistoryLength) {
      _recentTracks.removeRange(maxHistoryLength, _recentTracks.length);
    }

    await _saveToPrefs();
    notifyListeners();
  }

  /// Limpia todo el historial local.
  Future<void> clearHistory() async {
    _recentTracks.clear();
    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final jsonList = _recentTracks.map((t) => t.toJson()).toList();
    await prefs.setString(historyPrefKey, jsonEncode(jsonList));
  }
}
