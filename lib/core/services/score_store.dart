import '../models/player_stats.dart';
import '../models/head_to_head.dart';

/// 통산/상대 전적 영구 저장 계층 추상화.
///
/// 게임 코드는 이 인터페이스에만 의존하므로, 구현체(Firebase / Local)를 갈아끼워도
/// 게임 로직은 그대로 동작한다. (RoomService 와 동일한 설계 철학.)
///
/// ---------------------------------------------------------------------------
/// 전적 모델: 통산(profiles) + (페어, 게임)별 승판수(headtohead/{pairKey__gameId})
/// ---------------------------------------------------------------------------
/// - 통산: profiles/{playerId} 는 게임 무관 누적(totalScore/wins/losses/rounds).
/// - 상대 전적: 한 문서가 "두 사람 × 한 게임" 단위다. 같은 페어라도 게임별로
///   wins/scores/rounds/nagari 가 분리된다([recordRound]/[recordNagari] 의 gameId).
///
/// ---------------------------------------------------------------------------
/// 호출 계약 (중복 카운트 방지 — 반드시 지킬 것)
/// ---------------------------------------------------------------------------
/// 게임오버 시 [recordRound] / [recordNagari] 는 **정확히 한 번만** 호출되어야
/// 한다. 온라인 대전에서는 양쪽 클라이언트가 같은 room.state 변경을 동시에 보므로,
/// 가드 없이 호출하면 전적이 두 번 누적된다. 기록은 게임 무관하게
/// GameHostScreen 이 중앙에서 1회 수행한다(개별 게임 위젯은 호출하지 않는다).
///
/// 가드 규약:
///   1) `room.state["recorded"] != true` 인 경우에만 기록한다.
///   2) 기록을 수행하는 "처리 주체"는 다음과 같이 단 하나만 정한다.
///        - 승부:  `myPlayerId == winnerId` 인 클라이언트(승자)만 수행.
///        - 나가리: 승자가 없으므로 hostId 클라이언트가 수행한다.
///   3) 기록 직후 같은 트랜잭션 흐름에서 `room.state["recorded"] = true` 로
///      updateRoom 하여, 이후 어떤 클라이언트도 다시 기록하지 못하게 한다.
///
/// 즉, 전형적 흐름:
/// ```dart
/// if (room.state['recorded'] != true && iAmRecorder) {
///   if (winnerId != null) {
///     await scoreStore.recordRound(
///       winnerId: winnerId, winnerName: winnerName,
///       loserId: loserId, loserName: loserName,
///       score: score, gameId: room.gameId);
///   } else {
///     await scoreStore.recordNagari(
///       idA: aId, nameA: aName, idB: bId, nameB: bName, gameId: room.gameId);
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
  /// - 승자 profile(통산): totalScore += score, wins += 1, rounds += 1, name 갱신
  /// - 패자 profile(통산): losses += 1, rounds += 1, name 갱신
  /// - head-to-head[pairKey__gameId]: wins[winner] += 1, scores[winner] += score,
  ///   rounds += 1 — 즉 그 (페어, [gameId]) 문서에만 승판수가 쌓인다.
  ///
  /// 반드시 위 "호출 계약"의 가드 하에서 1회만 호출할 것.
  Future<void> recordRound({
    required String winnerId,
    required String winnerName,
    required String loserId,
    required String loserName,
    required int score,
    required String gameId,
  });

  /// 나가리(무승부)를 기록한다(원자적).
  ///
  /// - 두 플레이어 profile(통산): nagari += 1, rounds += 1, name 갱신
  /// - head-to-head[pairKey__gameId]: nagari += 1, rounds += 1
  ///
  /// 반드시 위 "호출 계약"의 가드 하에서 1회만 호출할 것.
  Future<void> recordNagari({
    required String idA,
    required String nameA,
    required String idB,
    required String nameB,
    required String gameId,
  });

  /// 특정 플레이어의 현재 통산 전적을 1회 조회한다.
  /// 문서가 없으면 [PlayerStats.empty] 를 반환한다([fallbackName] 사용).
  Future<PlayerStats> statsOf(String playerId, {String? fallbackName});

  /// 특정 플레이어의 통산 전적을 실시간 구독한다.
  /// 문서가 없으면 [PlayerStats.empty] 를 emit 한다.
  Stream<PlayerStats> watchStats(String playerId, {String? fallbackName});

  /// 두 플레이어의 (게임 무관) 상대 전적을 1회 조회한다. 없으면 null.
  ///
  /// 주: 페어×게임 모델 도입 후 표시 핵심은 [headToHeadForGame] 다. 이 메서드는
  /// 게임을 특정하지 않는 레거시/요약 조회용으로 남겨둔다.
  Future<HeadToHead?> headToHead(String idA, String idB);

  /// 두 플레이어의 (게임 무관) 상대 전적을 실시간 구독한다. 없으면 null emit.
  Stream<HeadToHead?> watchHeadToHead(String idA, String idB);

  /// 두 플레이어의 **특정 게임** 상대 전적(승판수)을 1회 조회한다.
  /// 문서가 없으면 0-0 빈 [HeadToHead] 를 반환한다(null 아님 — 새 페어/새 게임 자동 0-0).
  Future<HeadToHead?> headToHeadForGame(String idA, String idB, String gameId);

  /// 두 플레이어의 **특정 게임** 상대 전적을 실시간 구독한다.
  /// 문서가 없으면 0-0 빈 [HeadToHead] 를 emit 한다.
  Stream<HeadToHead?> watchHeadToHeadForGame(
    String idA,
    String idB,
    String gameId,
  );

  /// 두 플레이어의 **특정 게임** 상대 전적을 0-0 으로 초기화한다.
  /// 그 (페어, 게임) 문서만 비운다(다른 게임/다른 페어/통산 profile 은 불변).
  Future<void> resetHeadToHead(String idA, String idB, String gameId);
}
