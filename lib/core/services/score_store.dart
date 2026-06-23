import '../models/player_stats.dart';
import '../models/head_to_head.dart';

/// 통산/상대 전적 영구 저장 계층 추상화.
///
/// 게임 코드는 이 인터페이스에만 의존하므로, 구현체(Firebase / Local)를 갈아끼워도
/// 게임 로직은 그대로 동작한다. (RoomService 와 동일한 설계 철학.)
///
/// ---------------------------------------------------------------------------
/// Phase 2 호출 계약 (중복 카운트 방지 — 반드시 지킬 것)
/// ---------------------------------------------------------------------------
/// 고스톱 게임오버 시 [recordRound] / [recordNagari] 는 **정확히 한 번만** 호출되어야
/// 한다. 온라인 대전에서는 양쪽 클라이언트가 같은 room.state 변경을 동시에 보므로,
/// 가드 없이 호출하면 전적이 두 번 누적된다.
///
/// 가드 규약:
///   1) `room.state["recorded"] != true` 인 경우에만 기록한다.
///   2) 기록을 수행하는 "처리 주체"는 다음과 같이 단 하나만 정한다.
///        - 온라인:  `myPlayerId == winnerId` 인 클라이언트(승자)만 수행.
///                    (나가리는 승자가 없으므로 hostId 클라이언트가 수행한다.)
///        - 핫시트:  화면을 들고 있는 처리 주체(단일 디바이스)가 1회 수행.
///   3) 기록 직후 같은 트랜잭션 흐름에서 `room.state["recorded"] = true` 로
///      updateRoom/submit 하여, 이후 어떤 클라이언트도 다시 기록하지 못하게 한다.
///
/// 즉, 전형적 흐름:
/// ```dart
/// if (room.state['recorded'] != true && iAmRecorder) {
///   if (winnerId != null) {
///     await scoreStore.recordRound(
///       winnerId: winnerId, winnerName: winnerName,
///       loserId: loserId, loserName: loserName, score: score);
///   } else {
///     await scoreStore.recordNagari(
///       idA: aId, nameA: aName, idB: bId, nameB: bName);
///   }
///   await roomService.updateRoom(code, {'state': {...room.state, 'recorded': true}});
/// }
/// ```
/// ---------------------------------------------------------------------------
abstract class ScoreStore {
  /// UI에 표시할 저장 모드 이름.
  String get label;

  /// 한 라운드의 승패 결과를 기록한다(원자적).
  ///
  /// - 승자 profile: totalScore += score, wins += 1, rounds += 1, name 갱신
  /// - 패자 profile: losses += 1, rounds += 1, name 갱신
  /// - head-to-head: wins[winner] += 1, scores[winner] += score, rounds += 1
  ///
  /// 반드시 위 "호출 계약"의 가드 하에서 1회만 호출할 것.
  Future<void> recordRound({
    required String winnerId,
    required String winnerName,
    required String loserId,
    required String loserName,
    required int score,
  });

  /// 나가리(무승부)를 기록한다(원자적).
  ///
  /// - 두 플레이어 profile: nagari += 1, rounds += 1, name 갱신
  /// - head-to-head: nagari += 1, rounds += 1
  ///
  /// 반드시 위 "호출 계약"의 가드 하에서 1회만 호출할 것.
  Future<void> recordNagari({
    required String idA,
    required String nameA,
    required String idB,
    required String nameB,
  });

  /// 특정 플레이어의 현재 통산 전적을 1회 조회한다.
  /// 문서가 없으면 [PlayerStats.empty] 를 반환한다([fallbackName] 사용).
  Future<PlayerStats> statsOf(String playerId, {String? fallbackName});

  /// 특정 플레이어의 통산 전적을 실시간 구독한다.
  /// 문서가 없으면 [PlayerStats.empty] 를 emit 한다.
  Stream<PlayerStats> watchStats(String playerId, {String? fallbackName});

  /// 두 플레이어의 상대 전적을 1회 조회한다. 없으면 null.
  Future<HeadToHead?> headToHead(String idA, String idB);

  /// 두 플레이어의 상대 전적을 실시간 구독한다. 없으면 null emit.
  Stream<HeadToHead?> watchHeadToHead(String idA, String idB);
}
