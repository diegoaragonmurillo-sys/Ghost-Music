import '../../player/models/track.dart';

/// Modelo inmutable de una lista de reproducción creada por el usuario.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.tracks,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final List<Track> tracks;

  /// Portada derivada de la primera pista de la playlist, si existe.
  String? get coverUrl => tracks.isNotEmpty
      ? (tracks.first.fallbackArtworkUrl ?? tracks.first.artworkUrl)
      : null;

  Playlist copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    List<Track>? tracks,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      tracks: tracks ?? this.tracks,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawTracks = (json['tracks'] as List<dynamic>?) ?? const <dynamic>[];
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tracks: rawTracks
          .whereType<Map<String, dynamic>>()
          .map(Track.fromJson)
          .toList(),
    );
  }
}
