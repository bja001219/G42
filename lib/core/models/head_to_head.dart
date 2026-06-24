/// 한 (두 사람 쌍, 게임) 단위의 상대 전적(head-to-head).
///
/// Firestore `headtohead/{pairKey__gameId}` 문서 1개 = HeadToHead 1개.
/// [pairKey]는 두 id를 정렬해 합친 안정적 키이므로 A↔B 순서와 무관하게 같고,
/// 거기에 [gameId]를 붙여 "그 두 사람이 이 게임에서 거둔 승판수"만 따로 집계한다.
/// 즉 같은 페어라도 게임별로 전적이 분리된다.
///
/// 주의: Firestore는 중첩 배열을 허용하지 않지만 `Map<String,int>`는 허용된다.
/// 그래서 승수/점수를 플레이어id → 값 형태의 맵으로 저장한다.
class HeadToHead {
  /// 정렬된 두 id로 만든 안정적 쌍 키 (keyFor 참고).
  final String pairKey;

  /// 이 전적이 속한 게임 id (예: 'gostop', 'chess'). 페어×게임 단위 분리의 핵심.
  final String gameId;

  /// 플레이어id → 그 플레이어가 이 (페어, 게임) 매치업에서 거둔 승판수.
  final Map<String, int> wins;

  /// 플레이어id → 그 플레이어가 이 매치업에서 획득한 누적 점수.
  final Map<String, int> scores;

  /// 두 사람이 이 게임에서 함께 치른 라운드 수.
  final int rounds;

  /// 두 사람 사이의 나가리(무승부) 횟수.
  final int nagari;

  const HeadToHead({
    required this.pairKey,
    this.gameId = '',
    this.wins = const {},
    this.scores = const {},
    this.rounds = 0,
    this.nagari = 0,
  });

  /// 두 플레이어 id로 순서에 무관한 안정적 키 생성.
  /// 예) keyFor("b","a") == keyFor("a","b") == "a__b".
  static String keyFor(String a, String b) => ([a, b]..sort()).join('__');

  /// (페어, 게임) 문서 키. 예) docKeyFor("b","a","gostop") == "a__b__gostop".
  /// pairKey 와 gameId 사이 구분자는 keyFor 와 동일한 '__' 를 쓴다(키 안정성).
  static String docKeyFor(String a, String b, String gameId) =>
      '${keyFor(a, b)}__$gameId';

  /// 특정 플레이어의 이 매치업 승수.
  int winsOf(String id) => wins[id] ?? 0;

  /// 특정 플레이어의 이 매치업 누적 점수.
  int scoreOf(String id) => scores[id] ?? 0;

  factory HeadToHead.fromMap(Map<String, dynamic> m) => HeadToHead(
    pairKey: (m['pairKey'] ?? '') as String,
    gameId: (m['gameId'] ?? '') as String,
    wins: m['wins'] == null
        ? <String, int>{}
        : Map<String, int>.from(
            (m['wins'] as Map).map(
              (k, v) => MapEntry(k as String, (v ?? 0) as int),
            ),
          ),
    scores: m['scores'] == null
        ? <String, int>{}
        : Map<String, int>.from(
            (m['scores'] as Map).map(
              (k, v) => MapEntry(k as String, (v ?? 0) as int),
            ),
          ),
    rounds: (m['rounds'] ?? 0) as int,
    nagari: (m['nagari'] ?? 0) as int,
  );

  Map<String, dynamic> toMap() => {
    'pairKey': pairKey,
    'gameId': gameId,
    'wins': wins,
    'scores': scores,
    'rounds': rounds,
    'nagari': nagari,
  };
}
