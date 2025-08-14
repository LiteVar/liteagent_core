import 'dart:async';

class Timeout {
  final int timeoutSeconds;
  Timer? _timer;
  Timeout(this.timeoutSeconds);

  Duration get timeoutDuration => Duration(seconds: timeoutSeconds);

  void start(void Function() func) {
    _timer = Timer(timeoutDuration, () {
      func();
    });
  }

  void clear() {
    _timer?.cancel();
  }
}