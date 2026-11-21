import 'dart:async';

class PollingHelper {
  PollingHelper({this.interval = const Duration(milliseconds: 120)});

  final Duration interval;
  Timer? _timer;
  bool _running = false;

  void start(Future<void> Function() pollOnce) {
    stop();
    _timer = Timer.periodic(interval, (_) {
      if (_running) {
        return;
      }
      _running = true;
      unawaited(_run(pollOnce));
    });
  }

  Future<void> _run(Future<void> Function() pollOnce) async {
    try {
      await pollOnce();
    } catch (_) {
      stop();
      return;
    } finally {
      _running = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  void dispose() {
    stop();
  }
}
