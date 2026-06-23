/// 한 플레이어의 통산 전적.
///
/// Firestore `profiles/{playerId}` 문서 1개 = PlayerStats 1개.
/// 모든 카운터는 음수가 될 수 없으며, 누적(increment)으로만 갱신된다.
class PlayerStats {
  /// 플레이어 식별자 (IdentityService.playerId 와 동일).
  final String playerId;

  /// 마지막으로 기록된 표시 이름(닉네임). 라운드 기록 시 최신값으로 갱신.
  final String name;

  /// 통산 누적 점수(승리 시 획득한 점수의 합).
  final int totalScore;

  /// 승리 횟수.
  final int wins;

  /// 패배 횟수.
  final int losses;

  /// 치른 라운드 수(승/패 모두 +1, 나가리도 +1).
  final int rounds;

  /// 나가리(무승부) 횟수.
  final int nagari;

  const PlayerStats({
    required this.playerId,
    required this.name,
    this.totalScore = 0,
    this.wins = 0,
    this.losses = 0,
    this.rounds = 0,
    this.nagari = 0,
  });

  /// 아직 전적이 없는 플레이어용 빈 통계.
  factory PlayerStats.empty(String id, String name) =>
      PlayerStats(playerId: id, name: name);

  /// 승률(0.0 ~ 1.0). 라운드가 없으면 0.
  double get winRate => rounds == 0 ? 0 : wins / rounds;

  factory PlayerStats.fromMap(Map<String, dynamic> m) => PlayerStats(
    playerId: (m['playerId'] ?? '') as String,
    name: (m['name'] ?? '플레이어') as String,
    totalScore: (m['totalScore'] ?? 0) as int,
    wins: (m['wins'] ?? 0) as int,
    losses: (m['losses'] ?? 0) as int,
    rounds: (m['rounds'] ?? 0) as int,
    nagari: (m['nagari'] ?? 0) as int,
  );

  Map<String, dynamic> toMap() => {
    'playerId': playerId,
    'name': name,
    'totalScore': totalScore,
    'wins': wins,
    'losses': losses,
    'rounds': rounds,
    'nagari': nagari,
  };

  PlayerStats copyWith({
    String? name,
    int? totalScore,
    int? wins,
    int? losses,
    int? rounds,
    int? nagari,
  }) => PlayerStats(
    playerId: playerId,
    name: name ?? this.name,
    totalScore: totalScore ?? this.totalScore,
    wins: wins ?? this.wins,
    losses: losses ?? this.losses,
    rounds: rounds ?? this.rounds,
    nagari: nagari ?? this.nagari,
  );
}
