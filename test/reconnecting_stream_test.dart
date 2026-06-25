import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:g42/core/services/reconnecting_stream.dart';

/// reconnectingStream 회귀 테스트.
///
/// 목적: "둘이 게임 잘 하다 아무도 안 나갔는데 갑자기 끊김"의 핵심 원인 —
/// 실시간 리스너가 일시적 단절로 에러를 내고 죽어버려 게임 화면이 영구히 얼어붙는
/// 것 — 을 막는다. 이 래퍼는 소스 에러/종료를 소비자에게 전파하지 않고 흡수한 뒤
/// 자동으로 다시 구독해야 한다.
void main() {
  test('정상 이벤트는 그대로 전달된다', () async {
    final ctrl = StreamController<int>();
    final out = reconnectingStream<int>(
      () => ctrl.stream,
      delay: (_) async {},
    );
    final received = <int>[];
    final sub = out.listen(received.add);

    ctrl.add(1);
    ctrl.add(2);
    await pumpEventQueue();

    expect(received, [1, 2]);
    await sub.cancel();
  });

  test('소스가 에러로 죽으면 에러를 전파하지 않고 자동 재구독한다', () async {
    final sources = <StreamController<int>>[];
    var subscribeCount = 0;
    final out = reconnectingStream<int>(
      () {
        subscribeCount++;
        final c = StreamController<int>();
        sources.add(c);
        return c.stream;
      },
      delay: (_) async {}, // 즉시 재연결.
    );

    final received = <int>[];
    Object? sawError;
    final sub = out.listen(received.add, onError: (Object e) => sawError = e);
    await pumpEventQueue();
    expect(subscribeCount, 1);

    // 첫 소스로 정상 이벤트.
    sources[0].add(10);
    await pumpEventQueue();
    expect(received, [10]);

    // 첫 소스가 에러로 종료 → 소비자엔 에러가 보이지 않고, 재구독이 일어난다.
    sources[0].addError(Exception('네트워크 단절'));
    await pumpEventQueue();
    expect(sawError, isNull, reason: '에러는 소비자에게 전파되지 않아야 한다');
    expect(subscribeCount, 2, reason: '자동으로 다시 구독해야 한다');

    // 재연결된 새 소스로 이벤트가 계속 흐른다(=게임이 복구됨).
    sources[1].add(20);
    await pumpEventQueue();
    expect(received, [10, 20]);

    await sub.cancel();
  });

  test('소스가 예기치 않게 완료되어도 재구독한다', () async {
    final sources = <StreamController<int>>[];
    var subscribeCount = 0;
    final out = reconnectingStream<int>(
      () {
        subscribeCount++;
        final c = StreamController<int>();
        sources.add(c);
        return c.stream;
      },
      delay: (_) async {},
    );

    final received = <int>[];
    final sub = out.listen(received.add);
    await pumpEventQueue();
    expect(subscribeCount, 1);

    // 소스가 그냥 닫힘(done) → 재구독.
    await sources[0].close();
    await pumpEventQueue();
    expect(subscribeCount, 2);

    sources[1].add(99);
    await pumpEventQueue();
    expect(received, [99]);

    await sub.cancel();
  });

  test('백오프 대기 중 소비자가 취소하면 재구독하지 않는다', () async {
    final sources = <StreamController<int>>[];
    final delays = <Completer<void>>[];
    var subscribeCount = 0;
    final out = reconnectingStream<int>(
      () {
        subscribeCount++;
        final c = StreamController<int>();
        sources.add(c);
        return c.stream;
      },
      delay: (_) {
        final c = Completer<void>();
        delays.add(c);
        return c.future;
      },
    );

    final sub = out.listen((_) {});
    await pumpEventQueue();
    expect(subscribeCount, 1);

    // 에러 → 재연결 백오프 시작(대기 중).
    sources[0].addError(Exception('x'));
    await pumpEventQueue();
    expect(delays.length, 1, reason: '재연결 백오프 대기에 들어가야 한다');

    // 대기 도중 소비자가 취소.
    await sub.cancel();
    // 대기가 끝나도 재구독은 일어나지 않아야 한다.
    delays[0].complete();
    await pumpEventQueue();
    expect(subscribeCount, 1, reason: '취소 후엔 재구독하지 않는다');
  });

  test('연속 실패 시 백오프가 증가하고, 정상 이벤트가 오면 리셋된다', () async {
    final sources = <StreamController<int>>[];
    final waited = <Duration>[];
    final out = reconnectingStream<int>(
      () {
        final c = StreamController<int>();
        sources.add(c);
        return c.stream;
      },
      initialBackoff: const Duration(milliseconds: 100),
      maxBackoff: const Duration(seconds: 1),
      delay: (d) async {
        waited.add(d);
      },
    );

    final received = <int>[];
    final sub = out.listen(received.add);
    await pumpEventQueue();

    // 1차 실패(이벤트 없이 바로 에러) → 100ms.
    sources[0].addError(Exception('a'));
    await pumpEventQueue();
    // 2차 실패 → 200ms(2배).
    sources[1].addError(Exception('b'));
    await pumpEventQueue();
    expect(waited, [
      const Duration(milliseconds: 100),
      const Duration(milliseconds: 200),
    ]);

    // 정상 이벤트가 한 번 흐르면 백오프 리셋.
    sources[2].add(7);
    await pumpEventQueue();
    expect(received, [7]);

    // 이후 실패는 다시 100ms부터 시작.
    sources[2].addError(Exception('c'));
    await pumpEventQueue();
    expect(waited.last, const Duration(milliseconds: 100));

    await sub.cancel();
  });

  test('백오프는 maxBackoff 를 넘지 않는다', () async {
    final sources = <StreamController<int>>[];
    final waited = <Duration>[];
    final out = reconnectingStream<int>(
      () {
        final c = StreamController<int>();
        sources.add(c);
        return c.stream;
      },
      initialBackoff: const Duration(milliseconds: 100),
      maxBackoff: const Duration(milliseconds: 300),
      delay: (d) async {
        waited.add(d);
      },
    );

    final sub = out.listen((_) {});
    await pumpEventQueue();

    // 100 → 200 → 300(상한) → 300 ...
    for (var i = 0; i < 4; i++) {
      sources[i].addError(Exception('e$i'));
      await pumpEventQueue();
    }
    expect(waited, [
      const Duration(milliseconds: 100),
      const Duration(milliseconds: 200),
      const Duration(milliseconds: 300),
      const Duration(milliseconds: 300),
    ]);

    await sub.cancel();
  });
}
