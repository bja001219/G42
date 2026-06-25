import 'dart:async';

import 'room_service.dart';

/// 상대 연결 상태 감지기(순수 로직, **단조 시계** 기반 — 벽시계 점프에 안전).
///
/// 절대 시각(DateTime)을 쓰지 않는다. 대신 단조 증가하는 경과 시간([Stopwatch])만
/// 본다: "상대 heartbeat 값이 마지막으로 바뀐 것을 관측한 경과 시각"으로부터
/// [staleAfter] 넘게 값이 그대로면 끊긴 것으로 본다. 단조 시계라 기기 시간 변경(NTP
/// 보정, 사용자 수동 변경, DST)으로 갑자기 stale 로 튀지 않는다.
///
/// **보수적 설계**: 상대 heartbeat 를 한 번이라도 관측하기 전에는 절대 stale 로
/// 판정하지 않는다(arm 되지 않음). 정상 플레이 중 잠깐의 지연으로 멀쩡한 게임을
/// 끊지 않는다 — 진짜로 [staleAfter] 동안 완전히 침묵할 때만 신호한다.
class OpponentPresence {
  /// 이만큼 상대 heartbeat 가 안 바뀌면 끊긴 것으로 간주.
  final Duration staleAfter;

  /// 단조 경과 시간 소스(테스트에서 주입 가능). 기본은 내부 Stopwatch.
  final Duration Function() _now;

  int? _lastBeat;
  Duration? _lastChange;

  OpponentPresence({
    this.staleAfter = const Duration(seconds: 45),
    Duration Function()? clock,
  }) : _now = clock ?? _stopwatchClock();

  static Duration Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  /// 한 번이라도 상대가 살아있음을 관측했는가(이전엔 stale 판정 불가).
  bool get isArmed => _lastChange != null;

  /// 방 스냅샷에서 본 상대 heartbeat 값 [beat] 으로 갱신한다.
  ///
  /// 값이 새로 바뀌었으면(=상대 살아있음) `true` 를 반환한다(호출자는 이 신호로
  /// "끊김" 안내를 자동으로 닫을 수 있다).
  bool observe(int? beat) {
    if (beat == null) return false;
    if (_lastBeat == null || beat != _lastBeat) {
      _lastBeat = beat;
      _lastChange = _now();
      return true;
    }
    return false;
  }

  /// 상대가 [staleAfter] 이상 침묵했는가(arm 된 이후에만 true 가능).
  bool isStale() {
    final last = _lastChange;
    if (last == null) return false;
    return _now() - last >= staleAfter;
  }

  /// "계속 기다리기" 선택 후: 기준 시각을 지금으로 미뤄 다음 임계까지 다시 기다린다.
  void snooze() {
    if (_lastChange != null) _lastChange = _now();
  }

  /// 무장 해제. 앱이 백그라운드로 갈 때 호출해, 복귀 후 **새 heartbeat 를 다시
  /// 관측하기 전까지는** stale 판정을 하지 않게 한다(백그라운드 동안 스냅샷이 끊겨
  /// 멀쩡한 상대를 끊겼다고 오판하는 것을 방지).
  void disarm() {
    _lastBeat = null;
    _lastChange = null;
  }
}

/// 자기 heartbeat 를 주기적으로 전송한다([RoomService.heartbeat] 호출).
///
/// 방에 들어가 있는 동안(대기실+인게임) 계속 돌아 상대가 나를 관측할 수 있게 한다.
/// 쓰기 실패는 서비스 단에서 무시되며 다음 주기에 자연히 재시도된다.
class HeartbeatSender {
  final RoomService service;
  final String code;
  final String playerId;
  final Duration interval;

  Timer? _timer;

  HeartbeatSender({
    required this.service,
    required this.code,
    required this.playerId,
    this.interval = const Duration(seconds: 9),
  });

  void start() {
    if (_timer != null) return;
    _send(); // 즉시 1회(입장 직후 상대가 빨리 인지하도록).
    _timer = Timer.periodic(interval, (_) => _send());
  }

  void _send() {
    // fire-and-forget. 실패는 무시(서비스가 삼킨다).
    service.heartbeat(code, playerId);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
