class DebugPerfLogger {
  DebugPerfLogger._();

  static Stopwatch start(String scope, String message) {
    final watch = Stopwatch()..start();
    _log(scope, 'START $message');
    return watch;
  }

  static void end(
    String scope,
    Stopwatch watch,
    String message, {
    Map<String, Object?>? data,
  }) {
    watch.stop();
    final extras = <String>[
      'durationMs=${watch.elapsedMilliseconds}',
      ..._serialize(data),
    ];
    _log(scope, 'END $message ${extras.join(' ')}');
  }

  static void info(String scope, String message, {Map<String, Object?>? data}) {
    final extras = _serialize(data);
    _log(scope, extras.isEmpty ? message : '$message ${extras.join(' ')}');
  }

  static void error(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? data,
  }) {
    final extras = <String>[
      ..._serialize(data),
      if (error != null) 'error=$error',
    ];
    _log(
      scope,
      extras.isEmpty ? 'ERROR $message' : 'ERROR $message ${extras.join(' ')}',
    );
  }

  static List<String> _serialize(Map<String, Object?>? data) {
    if (data == null || data.isEmpty) {
      return const <String>[];
    }
    return data.entries.map((entry) => '${entry.key}=${entry.value}').toList();
  }

  static void _log(String scope, String message) {
    return;
  }
}
