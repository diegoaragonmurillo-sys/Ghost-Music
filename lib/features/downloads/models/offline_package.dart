import '../../../core/settings_manager.dart';
import '../../player/models/track.dart';

enum DownloadTaskStatus {
  idle,
  downloading,
  downloaded,
  error,
}

class DownloadProgress {
  const DownloadProgress({
    required this.status,
    this.progress = 0.0,
    this.error,
  });

  final DownloadTaskStatus status;
  final double progress;
  final String? error;

  static const idle = DownloadProgress(status: DownloadTaskStatus.idle);
  static const downloaded = DownloadProgress(
    status: DownloadTaskStatus.downloaded,
    progress: 1.0,
  );
}

/// Paquete completo descargado en disco (Audio + Carátula + Letras LRC).
class OfflinePackage {
  const OfflinePackage({
    required this.track,
    required this.localAudioPath,
    this.localArtworkPath,
    this.localLrcPath,
    required this.quality,
    required this.fileSizeBytes,
    required this.downloadedAt,
  });

  final Track track;
  final String localAudioPath;
  final String? localArtworkPath;
  final String? localLrcPath;
  final AudioQuality quality;
  final int fileSizeBytes;
  final DateTime downloadedAt;

  OfflinePackage copyWith({
    Track? track,
    String? localAudioPath,
    String? localArtworkPath,
    String? localLrcPath,
    AudioQuality? quality,
    int? fileSizeBytes,
    DateTime? downloadedAt,
  }) {
    return OfflinePackage(
      track: track ?? this.track,
      localAudioPath: localAudioPath ?? this.localAudioPath,
      localArtworkPath: localArtworkPath ?? this.localArtworkPath,
      localLrcPath: localLrcPath ?? this.localLrcPath,
      quality: quality ?? this.quality,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      downloadedAt: downloadedAt ?? this.downloadedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'track': track.withoutAudioUrl().toJson(),
      'localAudioPath': localAudioPath,
      'localArtworkPath': localArtworkPath,
      'localLrcPath': localLrcPath,
      'quality': quality.key,
      'fileSizeBytes': fileSizeBytes,
      'downloadedAt': downloadedAt.toIso8601String(),
    };
  }

  factory OfflinePackage.fromMap(Map<dynamic, dynamic> map) {
    final rawTrack = map['track'] as Map<dynamic, dynamic>;
    final trackMap = Map<String, dynamic>.from(rawTrack);

    final rawDownloadedAt = map['downloadedAt'] as String?;
    final downloadedAt = rawDownloadedAt != null
        ? DateTime.tryParse(rawDownloadedAt) ?? DateTime.now()
        : DateTime.now();

    return OfflinePackage(
      track: Track.fromJson(trackMap),
      localAudioPath: map['localAudioPath'] as String,
      localArtworkPath: map['localArtworkPath'] as String?,
      localLrcPath: map['localLrcPath'] as String?,
      quality: AudioQuality.fromKey(map['quality'] as String?),
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
      downloadedAt: downloadedAt,
    );
  }
}
