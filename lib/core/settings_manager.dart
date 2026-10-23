import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Niveles de calidad de audio soportados por el enrutador inteligente.
enum AudioQuality {
  /// YouTube 128kbps (valor por defecto).
  dataSaver(
    key: 'data_saver',
    title: 'Ahorro de datos',
    subtitle: 'YouTube • 128 kbps AAC',
    badge: '128 kbps',
  ),

  /// JioSaavn 320kbps.
  high(
    key: 'high',
    title: 'Alta calidad',
    subtitle: 'JioSaavn • 320 kbps AAC',
    badge: '320 kbps',
  ),

  /// Deezer FLAC sin pérdida.
  lossless(
    key: 'lossless',
    title: 'Lossless (Sin pérdida)',
    subtitle: 'Deezer • FLAC hasta 1411 kbps',
    badge: 'FLAC',
  );

  const AudioQuality({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.badge,
  });

  final String key;
  final String title;
  final String subtitle;
  final String badge;

  static AudioQuality fromKey(String? raw) {
    for (final q in AudioQuality.values) {
      if (q.key == raw) return q;
    }
    return AudioQuality.dataSaver;
  }
}

/// Gestor persistente de preferencias del usuario (Singleton + ChangeNotifier).
class SettingsManager extends ChangeNotifier {
  SettingsManager({SharedPreferences? prefs}) {
    _prefs = prefs;
  }

  static final SettingsManager instance = SettingsManager();

  static const String _audioQualityPrefKey = 'audio_quality';
  static const String _downloadQualityPrefKey = 'download_quality';

  SharedPreferences? _prefs;
  AudioQuality _audioQuality = AudioQuality.dataSaver;
  AudioQuality _downloadQuality = AudioQuality.high;
  bool _initialized = false;

  /// Preferencia actual de calidad de streaming (por defecto [AudioQuality.dataSaver]).
  AudioQuality get audioQuality => _audioQuality;

  /// Preferencia actual de calidad de descarga (por defecto [AudioQuality.high]).
  AudioQuality get downloadQuality => _downloadQuality;

  /// Clave en texto plano (`data_saver`, `high`, `lossless`).
  String get audioQualityKey => _audioQuality.key;

  /// Inicializa [SharedPreferences] y carga la preferencia guardada.
  Future<void> init() async {
    if (_initialized && _prefs != null) return;
    _prefs ??= await SharedPreferences.getInstance();
    final savedAudio = _prefs?.getString(_audioQualityPrefKey);
    final savedDownload = _prefs?.getString(_downloadQualityPrefKey);
    _audioQuality = AudioQuality.fromKey(savedAudio);
    _downloadQuality = savedDownload != null
        ? AudioQuality.fromKey(savedDownload)
        : AudioQuality.high;
    _initialized = true;
    notifyListeners();
  }

  /// Lee la calidad actual asegurándose de haber cargado `SharedPreferences`.
  Future<AudioQuality> getSavedAudioQuality() async {
    if (!_initialized) {
      await init();
    }
    return _audioQuality;
  }

  /// Lee la calidad de descarga asegurándose de haber cargado `SharedPreferences`.
  Future<AudioQuality> getSavedDownloadQuality() async {
    if (!_initialized) {
      await init();
    }
    return _downloadQuality;
  }

  /// Guarda la nueva preferencia de calidad de audio localmente.
  Future<void> setAudioQuality(AudioQuality quality) async {
    _audioQuality = quality;
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setString(_audioQualityPrefKey, quality.key);
  }

  /// Guarda la preferencia usando su clave (`data_saver`, `high`, `lossless`).
  Future<void> setAudioQualityByKey(String key) {
    return setAudioQuality(AudioQuality.fromKey(key));
  }

  /// Guarda la nueva preferencia de calidad de descarga localmente.
  Future<void> setDownloadQuality(AudioQuality quality) async {
    _downloadQuality = quality;
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setString(_downloadQualityPrefKey, quality.key);
  }

  /// Guarda la preferencia de descarga usando su clave (`data_saver`, `high`, `lossless`).
  Future<void> setDownloadQualityByKey(String key) {
    return setDownloadQuality(AudioQuality.fromKey(key));
  }
}
