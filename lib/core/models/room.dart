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

/// heartbeats 맵을 방어적으로 파싱한다. null/문자열/중첩맵 등 숫자가 아닌 값은
/// 조용히 건너뛴다 — 손상된 문서 한 건이 fromMap 을 throw 시켜 reconnectingStream
/// 의 무한 재시도(poison loop)를 유발하지 않도록.
Map<String, int> _beatsFrom(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, int>{};
  raw.forEach((k, v) {
    if (k is String && v is num) out[k] = v.toInt();
  });
  return out;
}

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

  /// 플레이어별 heartbeat 카운터(playerId → 단조 증가 값). 각 클라이언트가 자기
  /// 값을 주기적으로 올려 "살아있음"을 알린다. 상대 값이 한동안 안 바뀌면(=새로고침/
  /// 강제종료) 연결이 끊긴 것으로 간주한다. `state` 와 분리된 top-level 필드라
  /// 게임 상태를 건드리지 않는다.
  final Map<String, int> heartbeats;

  const Room({
    required this.code,
    required this.gameId,
    required this.status,
    required this.players,
    required this.hostId,
    this.turn,
    this.winner,
    this.state = const {},
    this.heartbeats = const {},
  });

  List<String> get playerIds => players.map((p) => p.id).toList();

  bool get isFull => players.length >= 2;

  /// [id] 플레이어의 최신 heartbeat 값(없으면 null).
  int? heartbeatOf(String id) => heartbeats[id];

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
    heartbeats: _beatsFrom(m['heartbeats']),
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
    'heartbeats': heartbeats,
  };

  Room copyWith({
    RoomStatus? status,
    List<RoomPlayer>? players,
    String? turn,
    String? winner,
    Map<String, dynamic>? state,
    Map<String, int>? heartbeats,
  }) => Room(
    code: code,
    gameId: gameId,
    hostId: hostId,
    status: status ?? this.status,
    players: players ?? this.players,
    turn: turn ?? this.turn,
    winner: winner ?? this.winner,
    state: state ?? this.state,
    heartbeats: heartbeats ?? this.heartbeats,
  );

  /// Firestore의 `update(patch)`와 동일한 의미로 top-level 필드를 덮어쓴다.
  /// (LocalRoomService에서 사용)
  ///
  /// dotted field path("state.s0" 처럼 '.'이 든 키)도 Firestore 와 동일하게
  /// 해석한다: `state` 맵 안쪽으로 깊게 머지하여 형제 키(다른 좌석 등)는 보존한다.
  /// 실시간 게임(예: 테트리스)에서 두 플레이어가 각자 자기 좌석 칸만 동시에 써도
  /// 서로 덮어쓰지 않게 하기 위함이다.
  Room applyPatch(Map<String, dynamic> patch) {
    // 1) state 베이스: 'state' 전체 교체가 있으면 그걸, 없으면 기존 state 복제.
    final newState = patch.containsKey('state')
        ? Map<String, dynamic>.from(patch['state'] as Map)
        : Map<String, dynamic>.from(state);

    // 2) dotted 'state.*' 키들을 newState 안쪽으로 깊게 머지.
    patch.forEach((key, value) {
      if (!key.contains('.')) return;
      final parts = key.split('.');
      if (parts.first != 'state' || parts.length < 2) return;
      var cursor = newState;
      for (var i = 1; i < parts.length - 1; i++) {
        final seg = parts[i];
        final next = cursor[seg];
        final child = next is Map
            ? Map<String, dynamic>.from(next)
            : <String, dynamic>{};
        cursor[seg] = child;
        cursor = child;
      }
      cursor[parts.last] = value;
    });

    // 3) heartbeats: 'heartbeats' 전체 교체 또는 dotted 'heartbeats.<id>' 갱신.
    final newBeats = patch.containsKey('heartbeats')
        ? _beatsFrom(patch['heartbeats'])
        : Map<String, int>.from(heartbeats);
    patch.forEach((key, value) {
      if (!key.startsWith('heartbeats.')) return;
      final id = key.substring('heartbeats.'.length);
      if (id.isNotEmpty && value is num) newBeats[id] = value.toInt();
    });

    return Room(
      code: code,
      gameId: patch.containsKey('gameId')
          ? (patch['gameId'] ?? '') as String
          : gameId,
      hostId: hostId,
      status: patch.containsKey('status')
          ? _statusFrom(patch['status'])
          : status,
      players: patch.containsKey('players')
          ? (patch['players'] as List)
                .map(
                  (e) =>
                      RoomPlayer.fromMap(Map<String, dynamic>.from(e as Map)),
                )
                .toList()
          : players,
      turn: patch.containsKey('turn') ? patch['turn'] as String? : turn,
      winner: patch.containsKey('winner') ? patch['winner'] as String? : winner,
      state: newState,
      heartbeats: newBeats,
    );
  }
}
