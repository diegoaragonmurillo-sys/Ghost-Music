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

  static final RegExp lrcLineRegex =
      RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

  /// Convierte una cadena en formato LRC (`[01:15.22] Texto`) en una lista
  /// ordenada de [LyricLine] con precisión de milisegundos, conservando las
  /// líneas vacías (pausas instrumentales).
  static List<LyricLine> parseLrc(String rawLrc) {
    final lines = <LyricLine>[];
    for (final raw in rawLrc.split('\n')) {
      final match = lrcLineRegex.firstMatch(raw.trim());
      if (match == null) continue;

      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final msGroup = match.group(3)!;
      final milliseconds =
          msGroup.length == 2 ? int.parse(msGroup) * 10 : int.parse(msGroup);
      final text = (match.group(4) ?? '').trim();

      lines.add(
        LyricLine(
          Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text,
        ),
      );
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
          .map((l) => LyricLine(Duration.zero, l.trim()))
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
