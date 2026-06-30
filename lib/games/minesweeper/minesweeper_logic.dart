import 'dart:math';

/// 지뢰찾기 핵심 로직 (순수 함수 모음).
///
/// 보드는 행 우선(row-major) 1차원으로 다룬다. 셀 인덱스 = r * cols + c.
/// 위젯/동기화에서 분리된 순수 계산만 담아 단위 테스트가 쉽다.
class MinesweeperLogic {
  final int rows;
  final int cols;

  const MinesweeperLogic({required this.rows, required this.cols});

  int get total => rows * cols;

  int index(int r, int c) => r * cols + c;
  int rowOf(int i) => i ~/ cols;
  int colOf(int i) => i % cols;

  bool inBounds(int r, int c) => r >= 0 && r < rows && c >= 0 && c < cols;

  /// i의 8방향 이웃 인덱스(보드 안쪽만).
  List<int> neighbors(int i) {
    final r = rowOf(i), c = colOf(i);
    final out = <int>[];
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr, nc = c + dc;
        if (inBounds(nr, nc)) out.add(index(nr, nc));
      }
    }
    return out;
  }

  /// [safeIndex](첫 클릭 칸)를 피해 지뢰를 배치한다. 칸이 충분히 남으면 그 이웃까지
  /// 안전지대로 둬서 첫 클릭이 항상 넓게 열리도록(클래식 지뢰찾기의 "첫 클릭 안전").
  List<int> placeMines(int mineCount, int safeIndex, Random rng) {
    final m = mineCount.clamp(0, total - 1);
    final forbidden = <int>{safeIndex};
    // 이웃까지 빼도 지뢰가 들어갈 자리가 남으면 이웃도 안전지대로.
    final withNeighbors = <int>{safeIndex, ...neighbors(safeIndex)};
    if (total - withNeighbors.length >= m) {
      forbidden.addAll(withNeighbors);
    }
    final candidates = <int>[];
    for (var i = 0; i < total; i++) {
      if (!forbidden.contains(i)) candidates.add(i);
    }
    candidates.shuffle(rng);
    final mines = candidates.take(m).toList()..sort();
    return mines;
  }

  /// [i] 칸의 인접 지뢰 수(0~8).
  int adjacentMines(int i, Set<int> mineSet) {
    var n = 0;
    for (final nb in neighbors(i)) {
      if (mineSet.contains(nb)) n++;
    }
    return n;
  }

  /// [start]에서 flood-fill로 열어야 할 칸 인덱스 집합을 반환한다.
  /// 인접 지뢰가 0인 칸은 이웃까지 펼쳐 열고, 0이 아닌 칸은 자기 자신만 연다.
  /// 깃발/이미 열린/지뢰 칸은 펼치지 않는다([start]는 지뢰가 아니라고 가정).
  Set<int> revealFrom(
    int start,
    Set<int> mineSet,
    List<int> revealed,
    List<int> flags,
  ) {
    final out = <int>{};
    final stack = <int>[start];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      if (out.contains(i)) continue;
      if (revealed[i] == 1) continue;
      if (flags[i] == 1) continue;
      if (mineSet.contains(i)) continue;
      out.add(i);
      if (adjacentMines(i, mineSet) == 0) {
        for (final nb in neighbors(i)) {
          if (!out.contains(nb) &&
              revealed[nb] == 0 &&
              flags[nb] == 0 &&
              !mineSet.contains(nb)) {
            stack.add(nb);
          }
        }
      }
    }
    return out;
  }

  /// 안전 칸(지뢰 아님)이 모두 열렸는가 = 클리어(승리).
  bool isCleared(List<int> revealed, Set<int> mineSet) {
    for (var i = 0; i < total; i++) {
      if (mineSet.contains(i)) continue;
      if (revealed[i] != 1) return false;
    }
    return true;
  }
}

/// 방 동기화 맵(`room.state`)으로 오가는 지뢰찾기 상태를 다루는 헬퍼.
///
/// 두 플레이어가 **같은 보드**를 실시간으로 공유한다(협동). 상태는 Firestore 친화적인
/// 평탄한 정수 리스트로 저장한다:
///   - revealed[i] == 1 : 열린 칸
///   - flags[i]    == 1 : 깃발 칸
///   - mines            : 지뢰 셀 인덱스 목록(첫 클릭 전에는 비어 있고 generated=false)
///   - phase            : 'playing' | 'won' | 'lost'
///   - hit              : 밟은 지뢰 칸(없으면 -1)
class MinesweeperState {
  /// 새 보드(아직 지뢰 미배치). [config]에는 난이도 식별용 값을 그대로 실어둔다.
  static Map<String, dynamic> fresh({
    required int rows,
    required int cols,
    required int mines,
    Map<String, dynamic>? config,
  }) {
    final total = rows * cols;
    final safeMines = mines.clamp(1, total - 1);
    return <String, dynamic>{
      'rows': rows,
      'cols': cols,
      'mineCount': safeMines,
      'generated': false,
      'mines': <int>[],
      'revealed': List<int>.filled(total, 0),
      'flags': List<int>.filled(total, 0),
      'phase': 'playing',
      'hit': -1,
      'config': ?config,
    };
  }

  static int rowsOf(Map<String, dynamic> s) =>
      (s['rows'] as num?)?.toInt() ?? 0;
  static int colsOf(Map<String, dynamic> s) =>
      (s['cols'] as num?)?.toInt() ?? 0;
  static int mineCountOf(Map<String, dynamic> s) =>
      (s['mineCount'] as num?)?.toInt() ?? 0;
  static String phaseOf(Map<String, dynamic> s) =>
      (s['phase'] as String?) ?? 'playing';
  static int hitOf(Map<String, dynamic> s) => (s['hit'] as num?)?.toInt() ?? -1;
  static bool generatedOf(Map<String, dynamic> s) => s['generated'] == true;

  /// 길이 [len]의 0/1 정수 리스트로 방어적 파싱(Firestore는 `List<dynamic>`로 돌려준다).
  static List<int> intList(Object? raw, int len) {
    final out = List<int>.filled(len, 0);
    if (raw is List) {
      for (var i = 0; i < raw.length && i < len; i++) {
        final v = raw[i];
        out[i] = v is num ? v.toInt() : 0;
      }
    }
    return out;
  }

  /// 지뢰 인덱스 목록을 방어적으로 파싱.
  static List<int> mineList(Object? raw) {
    if (raw is List) {
      return <int>[for (final v in raw) if (v is num) v.toInt()];
    }
    return <int>[];
  }

  static List<int> revealedOf(Map<String, dynamic> s) =>
      intList(s['revealed'], rowsOf(s) * colsOf(s));
  static List<int> flagsOf(Map<String, dynamic> s) =>
      intList(s['flags'], rowsOf(s) * colsOf(s));
  static List<int> minesOf(Map<String, dynamic> s) => mineList(s['mines']);

  /// 꽂힌 깃발 수.
  static int flagCount(Map<String, dynamic> s) =>
      flagsOf(s).where((v) => v == 1).length;

  /// [i] 칸을 연다. 진행 중이 아니거나 이미 열린/깃발 칸이면 그대로 둔다.
  /// 첫 클릭이면 [rng]로 지뢰를 (그 칸을 피해) 배치한다. 지뢰를 밟으면 'lost',
  /// 마지막 안전 칸을 열면 'won'.
  static Map<String, dynamic> applyReveal(
    Map<String, dynamic> state,
    int i,
    Random rng,
  ) {
    if (phaseOf(state) != 'playing') return state;
    final rows = rowsOf(state), cols = colsOf(state);
    final total = rows * cols;
    if (i < 0 || i >= total) return state;

    final revealed = revealedOf(state);
    final flags = flagsOf(state);
    if (revealed[i] == 1 || flags[i] == 1) return state;

    final logic = MinesweeperLogic(rows: rows, cols: cols);
    var mines = minesOf(state);
    var generated = generatedOf(state);
    if (!generated) {
      mines = logic.placeMines(mineCountOf(state), i, rng);
      generated = true;
    }
    final mineSet = mines.toSet();

    final next = Map<String, dynamic>.from(state);
    next['mines'] = mines;
    next['generated'] = generated;

    if (mineSet.contains(i)) {
      next['phase'] = 'lost';
      next['hit'] = i;
      return next;
    }

    final toOpen = logic.revealFrom(i, mineSet, revealed, flags);
    for (final c in toOpen) {
      revealed[c] = 1;
    }
    next['revealed'] = revealed;
    if (logic.isCleared(revealed, mineSet)) {
      next['phase'] = 'won';
    }
    return next;
  }

  /// [i] 칸의 깃발을 토글한다. 진행 중이 아니거나 이미 열린 칸이면 그대로 둔다.
  static Map<String, dynamic> applyFlag(Map<String, dynamic> state, int i) {
    if (phaseOf(state) != 'playing') return state;
    final rows = rowsOf(state), cols = colsOf(state);
    final total = rows * cols;
    if (i < 0 || i >= total) return state;

    final revealed = revealedOf(state);
    if (revealed[i] == 1) return state;

    final flags = flagsOf(state);
    flags[i] = flags[i] == 1 ? 0 : 1;

    final next = Map<String, dynamic>.from(state);
    next['flags'] = flags;
    return next;
  }
}
