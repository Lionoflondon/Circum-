import 'dart:async';

/// One terminal result for browser recorder events, cancellation and timeout.
class GiftVoiceCompletion<T> {
  GiftVoiceCompletion({required Duration timeout, required this.onSettled}) {
    _timer = Timer(
        timeout, () => fail(TimeoutException('Recording took too long.')));
  }

  final void Function() onSettled;
  final Completer<T> _result = Completer<T>();
  Timer? _timer;
  Future<T> get future => _result.future;
  bool get isCompleted => _result.isCompleted;

  void complete(T value) {
    if (isCompleted) return;
    _timer?.cancel();
    _result.complete(value);
    onSettled();
  }

  void fail(Object error) {
    if (isCompleted) return;
    _timer?.cancel();
    _result.completeError(error);
    onSettled();
  }
}
