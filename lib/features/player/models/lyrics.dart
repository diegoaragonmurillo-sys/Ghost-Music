/// Una línea de letra con su marca de tiempo.
class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}

/// Letra de una canción, sincronizada (LRC) o en texto plano.
class Lyrics {
  const Lyrics({required this.lines, required this.isSynced});

  final List<LyricLine> lines;

  /// `true` si cada línea tiene timestamp real (karaoke estilo Apple Music).
  final bool isSynced;

  static final _timestamp = RegExp(r'\[(\d{1,2}):(\d{1,2}(?:[.:]\d{1,3})?)\]');

  /// Crea una [Lyrics] a partir de LRC sincronizado o, en su defecto, texto.
  static Lyrics? parse({String? synced, String? plain}) {
    if (synced != null && synced.trim().isNotEmpty) {
      final lines = <LyricLine>[];
      for (final raw in synced.split('\n')) {
        final matches = _timestamp.allMatches(raw).toList();
        if (matches.isEmpty) continue;
        final text = raw.substring(matches.last.end).trim();
        for (final m in matches) {
          final minutes = int.parse(m.group(1)!);
          final seconds = double.parse(m.group(2)!.replaceAll(':', '.'));
          lines.add(LyricLine(
            Duration(milliseconds: ((minutes * 60 + seconds) * 1000).round()),
            text,
          ));
        }
      }
      lines.sort((a, b) => a.time.compareTo(b.time));
      if (lines.isNotEmpty) return Lyrics(lines: lines, isSynced: true);
    }
    if (plain != null && plain.trim().isNotEmpty) {
      return Lyrics(
        lines: [
          for (final l in plain.split('\n')) LyricLine(Duration.zero, l.trim()),
        ],
        isSynced: false,
      );
    }
    return null;
  }

  /// Índice de la línea activa para [position] (búsqueda binaria).
  /// Devuelve -1 si aún no empieza la primera línea o no es sincronizada.
  int indexAt(Duration position) {
    if (!isSynced || lines.isEmpty || position < lines.first.time) return -1;
    var lo = 0;
    var hi = lines.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lines[mid].time <= position) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}
