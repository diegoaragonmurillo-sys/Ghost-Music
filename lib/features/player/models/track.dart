/// Modelo inmutable de una pista musical.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.audioUrl,
    required this.artworkUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String audioUrl;
  final String artworkUrl;
}

/// Cola de prueba (audio libre de SoundHelix + carátulas placeholder).
const List<Track> demoQueue = [
  Track(
    id: '1',
    title: 'Midnight Echoes',
    artist: 'Ghost Ensemble',
    album: 'Phantom Frequencies',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    artworkUrl: 'https://picsum.photos/seed/ghostmusic1/800/800',
  ),
  Track(
    id: '2',
    title: 'Neon Haze',
    artist: 'Spectral Waves',
    album: 'After Hours',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    artworkUrl: 'https://picsum.photos/seed/ghostmusic2/800/800',
  ),
  Track(
    id: '3',
    title: 'Velvet Static',
    artist: 'The Apparitions',
    album: 'Lowlight',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    artworkUrl: 'https://picsum.photos/seed/ghostmusic3/800/800',
  ),
];
