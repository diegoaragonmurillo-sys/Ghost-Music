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

  /// Lista hardcodeada con 5 líneas de prueba y sus tiempos para simular
  /// una canción en la vista inmersiva de letras.
  static const List<LyricLine> demoLines = [
    LyricLine(Duration(seconds: 0), 'Luces de neón brillando en la ciudad'),
    LyricLine(Duration(seconds: 4), 'El eco de tu voz vuelve a resonar'),
    LyricLine(Duration(seconds: 8), 'Cada pulso marca el ritmo del corazón'),
    LyricLine(Duration(seconds: 12), 'Flotando sin gravedad en esta canción'),
    LyricLine(Duration(seconds: 16), 'Hasta que el silencio nos vuelva a encontrar'),
  ];

  static const Lyrics demo = Lyrics(lines: demoLines, isSynced: true);

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
