/// Modelo inmutable de una pista musical.
///
/// [audioUrl] es `null` hasta que el stream se resuelve justo antes de
/// reproducir: los URLs de YouTube caducan (~6 h) y resolverlos todos al
/// buscar sería lento, así que la resolución es *lazy* (ver SearchService).
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    this.album = '',
    this.fallbackArtworkUrl,
    this.audioUrl,
    this.duration,
  });

  /// ID de vídeo de YouTube.
  final String id;
  final String title;
  final String artist;
  final String album;

  /// Carátula en alta resolución (maxres si existe).
  final String artworkUrl;

  /// Miniatura que siempre existe (hqdefault), usada si [artworkUrl] falla.
  final String? fallbackArtworkUrl;

  /// URL directo del stream audio-only. `null` si aún no se resolvió.
  final String? audioUrl;
  final Duration? duration;

  bool get isResolved => audioUrl != null;

  Track copyWith({String? audioUrl, Duration? duration, String? artworkUrl}) {
    return Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      fallbackArtworkUrl: fallbackArtworkUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
