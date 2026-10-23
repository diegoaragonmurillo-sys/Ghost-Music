import 'package:flutter_test/flutter_test.dart';

import 'package:ghost_music/core/utils/duration_formatter.dart';

void main() {
  test('formatDuration formatea minutos y horas', () {
    expect(formatDuration(const Duration(seconds: 65)), '1:05');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03');
  });
}
