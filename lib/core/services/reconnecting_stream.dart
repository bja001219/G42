import 'dart:async';

/// 내부 소스 스트림이 **에러로 죽거나 예기치 않게 완료되어도** 자동으로 다시
/// 구독(reconnect)하는 스트림을 만든다.
///
/// 왜 필요한가: Firestore `snapshots()` 리스너는 일시적인 네트워크/웹채널 단절,
/// 토큰 만료, 모바일 브라우저 백그라운드 스로틀링 등으로 **에러를 한 번 내고 스트림이
/// 종료**될 수 있다. 그대로 두면 게임 화면(StreamBuilder)이 마지막 상태로 영구히
/// 얼어붙어 "둘이 잘 하다 아무도 안 나갔는데 갑자기 끊김"처럼 보인다.
///
/// 이 래퍼는 그런 종료를 **소비자에게 전파하지 않고** 흡수한 뒤, 지수 백오프로
/// 소스를 다시 구독한다. 재연결되면 Firestore가 현재 문서 스냅샷을 즉시 다시
/// 흘려보내므로 게임은 자연스럽게 최신 상태로 복구된다.
///
/// 동작 요약:
///  - [subscribe]: 매 (재)연결마다 **새 소스 스트림**을 만드는 팩토리.
///  - 연속 실패 시 [initialBackoff] → 2배씩 → [maxBackoff] 상한으로 대기.
///  - 이벤트가 1건이라도 정상적으로 흐르면 백오프를 [initialBackoff]로 리셋한다.
///  - 반환 스트림의 구독을 취소하면 내부 구독/대기 타이머도 모두 정리한다.
///
/// [delay] 는 테스트에서 시간을 제어하기 위해 주입 가능하게 열어 두었다(기본은 실제
/// [Future.delayed]).
Stream<T> reconnectingStream<T>(
  Stream<T> Function() subscribe, {
  Duration initialBackoff = const Duration(milliseconds: 400),
  Duration maxBackoff = const Duration(seconds: 8),
  Future<void> Function(Duration) delay = _wait,
}) {
  return _Reconnector<T>(
    subscribe: subscribe,
    initialBackoff: initialBackoff,
    maxBackoff: maxBackoff,
    delay: delay,
  ).stream;
}

Future<void> _wait(Duration d) => Future<void>.delayed(d);

class _Reconnector<T> {
  final Stream<T> Function() subscribe;
  final Duration initialBackoff;
  final Duration maxBackoff;
  final Future<void> Function(Duration) delay;

  late final StreamController<T> _controller;
  StreamSubscription<T>? _sub;
  late Duration _backoff;

  /// 소비자가 구독을 취소했는지(취소 후엔 재연결하지 않는다).
  bool _closed = false;

  /// 재연결 세대 카운터. 취소/재연결이 겹칠 때 옛 콜백이 새 구독을 망가뜨리지
  /// 않도록 가드한다.
  int _generation = 0;

  _Reconnector({
    required this.subscribe,
    required this.initialBackoff,
    required this.maxBackoff,
    required this.delay,
  }) {
    _backoff = initialBackoff;
    _controller = StreamController<T>(onListen: _connect, onCancel: _dispose);
  }

  Stream<T> get stream => _controller.stream;

  void _connect() {
    if (_closed) return;
    final gen = _generation;
    Stream<T> source;
    try {
      source = subscribe();
    } catch (_) {
      // 팩토리 자체가 실패 → 백오프 후 재시도.
      _scheduleReconnect(gen);
      return;
    }
    _sub = source.listen(
      (event) {
        _backoff = initialBackoff; // 정상 이벤트 → 백오프 리셋.
        if (!_controller.isClosed) _controller.add(event);
      },
      onError: (Object _, StackTrace _) {
        // 에러를 소비자에게 전파하지 않고 흡수한 뒤 재연결.
        // (cancelOnError:true 라 이 구독은 이미 취소된 상태다.)
        _sub = null;
        _scheduleReconnect(gen);
      },
      onDone: () {
        // 소스가 예기치 않게 끝남 → 재연결(소비자 스트림은 살려 둔다).
        _sub = null;
        _scheduleReconnect(gen);
      },
      cancelOnError: true,
    );
  }

  Future<void> _scheduleReconnect(int gen) async {
    if (_closed || gen != _generation) return;
    final wait = _backoff;
    _backoff = _nextBackoff(_backoff);
    await delay(wait);
    if (_closed || gen != _generation) return;
    // 이 재연결 시도를 새 세대로 승격(이후 옛 콜백 무력화).
    _generation++;
    _connect();
  }

  Duration _nextBackoff(Duration current) {
    final next = current * 2;
    return next > maxBackoff ? maxBackoff : next;
  }

  Future<void> _dispose() async {
    _closed = true;
    _generation++;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
  }
}
