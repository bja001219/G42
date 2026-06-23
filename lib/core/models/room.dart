/// 방에 참가한 플레이어.
class RoomPlayer {
  final String id;
  final String name;

  const RoomPlayer({required this.id, required this.name});

  factory RoomPlayer.fromMap(Map<String, dynamic> m) => RoomPlayer(
    id: (m['id'] ?? '') as String,
    name: (m['name'] ?? '플레이어') as String,
  );

  Map<String, dynamic> toMap() => {'id': id, 'name': name};
}

enum RoomStatus { waiting, playing, finished }

RoomStatus _statusFrom(Object? v) => RoomStatus.values.firstWhere(
  (s) => s.name == v,
  orElse: () => RoomStatus.waiting,
);

/// 하나의 게임 방. Firestore 문서 1개 = Room 1개.
///
/// [state]는 게임별 자유 형식 맵으로, 동기화의 핵심이다.
/// 게임은 항상 [state] 전체를 통째로 갱신한다(부분 패치 X).
class Room {
  final String code;
  final String gameId;
  final RoomStatus status;
  final List<RoomPlayer> players;
  final String hostId;

  /// 현재 차례인 플레이어 id (턴제 게임용). null이면 차례 개념 없음.
  final String? turn;

  /// 승자 playerId, 무승부는 'draw', 진행 중이면 null.
  final String? winner;

  /// 게임별 동기화 상태.
  final Map<String, dynamic> state;

  const Room({
    required this.code,
    required this.gameId,
    required this.status,
    required this.players,
    required this.hostId,
    this.turn,
    this.winner,
    this.state = const {},
  });

  List<String> get playerIds => players.map((p) => p.id).toList();

  bool get isFull => players.length >= 2;

  RoomPlayer? playerById(String id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  RoomPlayer? opponentOf(String myId) {
    for (final p in players) {
      if (p.id != myId) return p;
    }
    return null;
  }

  factory Room.fromMap(Map<String, dynamic> m) => Room(
    code: (m['code'] ?? '') as String,
    gameId: (m['gameId'] ?? '') as String,
    status: _statusFrom(m['status']),
    players: ((m['players'] as List?) ?? const [])
        .map((e) => RoomPlayer.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    hostId: (m['hostId'] ?? '') as String,
    turn: m['turn'] as String?,
    winner: m['winner'] as String?,
    state: m['state'] == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(m['state'] as Map),
  );

  Map<String, dynamic> toMap() => {
    'code': code,
    'gameId': gameId,
    'status': status.name,
    'players': players.map((p) => p.toMap()).toList(),
    'hostId': hostId,
    'turn': turn,
    'winner': winner,
    'state': state,
  };

  Room copyWith({
    RoomStatus? status,
    List<RoomPlayer>? players,
    String? turn,
    String? winner,
    Map<String, dynamic>? state,
  }) => Room(
    code: code,
    gameId: gameId,
    hostId: hostId,
    status: status ?? this.status,
    players: players ?? this.players,
    turn: turn ?? this.turn,
    winner: winner ?? this.winner,
    state: state ?? this.state,
  );

  /// Firestore의 `update(patch)`와 동일한 의미로 top-level 필드를 덮어쓴다.
  /// (LocalRoomService에서 사용)
  Room applyPatch(Map<String, dynamic> patch) => Room(
    code: code,
    gameId: gameId,
    hostId: hostId,
    status: patch.containsKey('status') ? _statusFrom(patch['status']) : status,
    players: patch.containsKey('players')
        ? (patch['players'] as List)
              .map(
                (e) => RoomPlayer.fromMap(Map<String, dynamic>.from(e as Map)),
              )
              .toList()
        : players,
    turn: patch.containsKey('turn') ? patch['turn'] as String? : turn,
    winner: patch.containsKey('winner') ? patch['winner'] as String? : winner,
    state: patch.containsKey('state')
        ? Map<String, dynamic>.from(patch['state'] as Map)
        : state,
  );
}
