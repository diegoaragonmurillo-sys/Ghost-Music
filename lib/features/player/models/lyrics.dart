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

  /// Convierte una cadena en formato LRC (`[01:15.22] Texto`) en una lista
  /// ordenada de [LyricLine] con precisión de milisegundos.
  static List<LyricLine> parseLrc(String rawLrc) {
    final lines = <LyricLine>[];
    for (final raw in rawLrc.split('\n')) {
      final matches = _timestamp.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.substring(matches.last.end).trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final minutes = int.parse(m.group(1)!);
        final seconds = double.parse(m.group(2)!.replaceAll(':', '.'));
        lines.add(
          LyricLine(
            Duration(milliseconds: ((minutes * 60 + seconds) * 1000).round()),
            text,
          ),
        );
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// Crea una [Lyrics] a partir de LRC sincronizado o, en su defecto, texto.
  static Lyrics? parse({String? synced, String? plain}) {
    if (synced != null && synced.trim().isNotEmpty) {
      final lines = parseLrc(synced);
      if (lines.isNotEmpty) return Lyrics(lines: lines, isSynced: true);
    }
    if (plain != null && plain.trim().isNotEmpty) {
      final plainLines = plain
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => LyricLine(Duration.zero, l))
          .toList();
      if (plainLines.isNotEmpty) {
        return Lyrics(lines: plainLines, isSynced: false);
      }
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
