import 'package:flutter_test/flutter_test.dart';

import 'package:ghost_music/core/utils/duration_formatter.dart';
import 'package:ghost_music/features/player/models/lyrics.dart';
import 'package:ghost_music/services/search_service.dart';

void main() {
  test('formatDuration formatea minutos y horas', () {
    expect(formatDuration(const Duration(seconds: 65)), '1:05');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  test('SearchService.parseMetadata limpia títulos de YouTube', () {
    final parsed = SearchService.parseMetadata(
      'Daft Punk - Get Lucky (Official Audio) ft. Pharrell Williams',
      'DaftPunkVEVO',
    );
    expect(parsed.artist, 'Daft Punk');
    expect(parsed.title, 'Get Lucky ft. Pharrell Williams');

    final topic = SearchService.parseMetadata(
      'Blinding Lights',
      'The Weeknd - Topic',
    );
    expect(topic.artist, 'The Weeknd');
    expect(topic.title, 'Blinding Lights');
  });

  test('Lyrics.parse interpreta formato LRC sincronizado', () {
    final lyrics = Lyrics.parse(
      synced: '[00:10.00] First line\n[00:20.50] Second line',
    );
    expect(lyrics, isNotNull);
    expect(lyrics!.isSynced, isTrue);
    expect(lyrics.lines.length, 2);
    expect(lyrics.indexAt(const Duration(seconds: 5)), -1);
    expect(lyrics.indexAt(const Duration(seconds: 12)), 0);
    expect(lyrics.indexAt(const Duration(seconds: 25)), 1);
  });
}
