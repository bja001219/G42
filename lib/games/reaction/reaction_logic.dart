/// 반응속도 대결 순수 로직 (UI / Firestore 의존 없음).
abstract class ReactionLogic {
  /// 부정출발(초록 전에 탭) 표식.
  static const int falseStart = -1;

  /// 아직 기록되지 않음.
  static const int notRecorded = 0;

  /// 라운드 승자 판정.
  ///
  /// [msA], [msB]: 각 플레이어의 반응시간(ms). [falseStart](-1)는 부정출발(자동 패).
  /// 반환: 0 = A 승, 1 = B 승, -1 = 무승부(둘 다 부정출발 또는 동일 ms).
  static int roundWinner(int msA, int msB) {
    final foulA = msA == falseStart;
    final foulB = msB == falseStart;
    if (foulA && foulB) return -1;
    if (foulA) return 1;
    if (foulB) return 0;
    if (msA < msB) return 0;
    if (msB < msA) return 1;
    return -1; // 동일 ms → 무승부
  }

  /// 양쪽 반응이 모두 기록되었는가(부정출발 포함).
  static bool bothRecorded(int msA, int msB) =>
      msA != notRecorded && msB != notRecorded;

  /// [wins] 중 [target] 선취한 플레이어가 있으면 그 인덱스, 없으면 null.
  static int? matchWinnerIndex(List<int> wins, int target) {
    for (var i = 0; i < wins.length; i++) {
      if (wins[i] >= target) return i;
    }
    return null;
  }
}
