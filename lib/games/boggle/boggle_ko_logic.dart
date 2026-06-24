import 'dart:math';

import 'boggle_logic.dart';
import 'boggle_words_ko.dart';

/// 한글 보글 로직. 각 칸은 '음절 타일'(한글 1글자)이다.
///
/// 경로 검증/인접 판정은 [BoggleLogic]을 그대로 재사용한다(NxN 격자, 한 칸 한 글자).
/// 무작위 음절판은 실제 단어가 거의 안 나오므로, 사전에서 뽑은 단어를 인접 경로에
/// '심어서(plant)' 찾을 수 있는 단어를 보장한다.
///
/// 격자 크기(4·5·6)는 인자로 받는다. 판이 클수록 더 많은 단어를 심는다.
abstract class KoBoggleLogic {
  static const int defaultSize = BoggleLogic.defaultSize; // 4
  static const int minWordLength = 2; // 한글은 2음절부터 인정

  static int cellCount(int size) => BoggleLogic.cellCount(size);

  /// 격자 크기별 제한시간(초). 영어판과 동일하게 스케일.
  static int durationFor(int size) => BoggleLogic.durationFor(size);

  /// (하위 호환) 기본 크기의 제한시간.
  static int get durationSeconds => durationFor(defaultSize);

  /// 글자판에 심을 단어 풀(2~3음절). 최초 1회만 만든다.
  static List<String>? _plantPool;
  static List<String> get plantPool =>
      _plantPool ??= koBoggleWords.where((w) => w.length <= 3).toList();

  /// 글자판 생성: 단어 몇 개를 인접 경로에 심고, 남은 칸은 빈도 높은 음절로 채운다.
  static String randomBoard(int size, Random rng) {
    final pool = plantPool;
    final cells = cellCount(size);
    final grid = List<String?>.filled(cells, null);

    // 칸 수에 비례해 심을 단어 수를 정한다. (16→4~6, 25→6~8, 36→9~11)
    final target = (cells / 4).round() + rng.nextInt(3);
    final maxAttempts = cells * 40;
    var planted = 0;
    var attempts = 0;
    while (planted < target && attempts < maxAttempts) {
      attempts++;
      final word = pool[rng.nextInt(pool.length)];
      final path = _tryPlacePath(size, grid, word.length, rng);
      if (path == null) continue;
      for (var i = 0; i < word.length; i++) {
        grid[path[i]] = word[i];
      }
      planted++;
    }

    // 남은 칸은 빈도 높은 음절로 채운다.
    for (var i = 0; i < cells; i++) {
      grid[i] ??= koFillSyllables[rng.nextInt(koFillSyllables.length)];
    }
    return grid.map((c) => c!).join();
  }

  /// 빈 칸들로만 이어지는 자기회피 인접 경로(길이 [len])를 찾는다. 실패 시 null.
  static List<int>? _tryPlacePath(
    int size,
    List<String?> grid,
    int len,
    Random rng,
  ) {
    final cells = cellCount(size);
    final empties = <int>[
      for (var i = 0; i < cells; i++)
        if (grid[i] == null) i,
    ];
    if (empties.length < len) return null;

    for (var tries = 0; tries < 60; tries++) {
      final start = empties[rng.nextInt(empties.length)];
      final path = <int>[start];
      final used = <int>{start};
      var ok = true;
      for (var s = 1; s < len; s++) {
        final last = path.last;
        final nbrs = <int>[
          for (var n = 0; n < cells; n++)
            if (grid[n] == null &&
                !used.contains(n) &&
                BoggleLogic.adjacent(size, last, n))
              n,
        ];
        if (nbrs.isEmpty) {
          ok = false;
          break;
        }
        final nx = nbrs[rng.nextInt(nbrs.length)];
        path.add(nx);
        used.add(nx);
      }
      if (ok && path.length == len) return path;
    }
    return null;
  }

  /// 화면 표기: 음절 그대로.
  static String displayAt(String grid, int index) => grid[index];

  /// 경로 → 단어(음절 이어붙임).
  static String wordFromPath(String grid, List<int> path) {
    final buf = StringBuffer();
    for (final idx in path) {
      buf.write(grid[idx]);
    }
    return buf.toString();
  }

  /// 사전 등재 여부.
  static bool inDictionary(String word) => koBoggleWords.contains(word.trim());

  /// 한글 점수표(음절 수 기준): 2=1, 3=2, 4=3, 5+=5.
  static int scoreFor(String word) {
    final n = word.length;
    if (n < 2) return 0;
    if (n == 2) return 1;
    if (n == 3) return 2;
    if (n == 4) return 3;
    return 5;
  }

  /// 보드에서 단어를 인접 경로로 만들 수 있는가(같은 칸 재사용 금지).
  /// 각 칸이 한 글자이므로 [BoggleLogic.canFormWord]를 그대로 재사용한다.
  static bool canFormWord(int size, String grid, String word) =>
      BoggleLogic.canFormWord(size, grid, word);

  /// 제출 검증. 한글은 2음절 이상.
  static WordCheck check(
    int size,
    String grid,
    String word,
    Set<String> alreadyFound,
  ) {
    final w = word.trim();
    if (w.length < minWordLength) return WordCheck.tooShort;
    if (alreadyFound.contains(w)) return WordCheck.duplicate;
    if (!inDictionary(w)) return WordCheck.notInDictionary;
    if (!canFormWord(size, grid, w)) return WordCheck.notOnBoard;
    return WordCheck.valid;
  }
}
