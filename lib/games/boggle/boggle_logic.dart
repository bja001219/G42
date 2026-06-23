import 'dart:math';

import 'boggle_words.dart';

/// 보글(글자판 단어찾기) 순수 로직.
///
/// 보드는 4x4 = 16칸을 한 줄로 평탄화한 16자 소문자 String으로 표현한다.
/// (Firestore 중첩 배열 금지 → 단일 String으로 인코딩.)
abstract class BoggleLogic {
  /// 보드 한 변의 길이.
  static const int size = 4;

  /// 보드 전체 칸 수 (16).
  static const int cellCount = size * size;

  /// 기본 제한시간(초).
  static const int durationSeconds = 90;

  /// 표준 보글 16-주사위. 각 주사위는 6면(글자).
  /// (영문 보글 클래식 분포 — 'q'는 'qu'로 취급.)
  static const List<String> _dice = <String>[
    'aaeegn',
    'abbjoo',
    'achops',
    'affkps',
    'aoottw',
    'cimotu',
    'deilrx',
    'delrvy',
    'distty',
    'eeghnw',
    'eeinsu',
    'ehrtvw',
    'eiosst',
    'elrtty',
    'himnqu',
    'hlnnrz',
  ];

  /// 표준 16-주사위를 섞어 보드 문자열(16자)을 만든다.
  ///
  /// 'q' 면은 'qu'를 의미하지만, 단일 칸 인코딩을 위해 'q' 한 글자로 저장하고
  /// 단어 매칭 시 'qu'로 확장한다(아래 [letterAt] 참고).
  static String randomBoard(Random rng) {
    final dice = List<String>.from(_dice);
    dice.shuffle(rng);
    final buf = StringBuffer();
    for (final d in dice) {
      buf.write(d[rng.nextInt(d.length)]);
    }
    return buf.toString();
  }

  /// 행/열 → 평탄화 인덱스.
  static int indexOf(int row, int col) => row * size + col;

  /// 인덱스 → 행.
  static int rowOf(int index) => index ~/ size;

  /// 인덱스 → 열.
  static int colOf(int index) => index % size;

  /// 한 칸의 화면 표기 글자열. 'q'는 'Qu'로 표기한다.
  static String displayAt(String board, int index) {
    final c = board[index];
    return c == 'q' ? 'Qu' : c.toUpperCase();
  }

  /// 단어 매칭용 칸 글자열('q' → 'qu').
  static String letterAt(String board, int index) {
    final c = board[index];
    return c == 'q' ? 'qu' : c;
  }

  /// 두 칸이 인접(상하좌우+대각 8방향)한가.
  static bool adjacent(int a, int b) {
    if (a == b) return false;
    final dr = (rowOf(a) - rowOf(b)).abs();
    final dc = (colOf(a) - colOf(b)).abs();
    return dr <= 1 && dc <= 1;
  }

  /// 주어진 경로(인덱스 목록)가 유효한가:
  /// (1) 비어있지 않고, (2) 같은 칸 재사용 없음, (3) 연속 칸이 모두 인접.
  static bool isValidPath(List<int> path) {
    if (path.isEmpty) return false;
    final seen = <int>{};
    for (var i = 0; i < path.length; i++) {
      final idx = path[i];
      if (idx < 0 || idx >= cellCount) return false;
      if (!seen.add(idx)) return false; // 중복 칸 재사용
      if (i > 0 && !adjacent(path[i - 1], idx)) return false;
    }
    return true;
  }

  /// 경로가 만들어내는 단어(소문자, 'q'→'qu' 확장).
  static String wordFromPath(String board, List<int> path) {
    final buf = StringBuffer();
    for (final idx in path) {
      buf.write(letterAt(board, idx));
    }
    return buf.toString();
  }

  /// 보드에서 [word]를 인접 경로(같은 칸 재사용 금지)로 만들 수 있는가.
  ///
  /// 'q' 칸은 'qu' 두 글자를 소비한다.
  static bool canFormWord(String board, String word) {
    final w = word.toLowerCase();
    if (w.isEmpty) return false;
    final used = List<bool>.filled(cellCount, false);
    for (var start = 0; start < cellCount; start++) {
      if (_dfs(board, w, 0, start, used)) return true;
    }
    return false;
  }

  static bool _dfs(
    String board,
    String word,
    int pos,
    int cell,
    List<bool> used,
  ) {
    if (used[cell]) return false;
    final letters = letterAt(board, cell); // 'q'면 'qu'
    final end = pos + letters.length;
    if (end > word.length) return false;
    if (word.substring(pos, end) != letters) return false;

    if (end == word.length) return true;

    used[cell] = true;
    for (var n = 0; n < cellCount; n++) {
      if (adjacent(cell, n) && _dfs(board, word, end, n, used)) {
        used[cell] = false;
        return true;
      }
    }
    used[cell] = false;
    return false;
  }

  /// 단어가 사전에 있는가.
  static bool inDictionary(String word) =>
      boggleWords.contains(word.toLowerCase());

  /// 표준 보글 점수: 3~4=1, 5=2, 6=3, 7=5, 8+=11.
  static int scoreFor(String word) {
    final n = word.length;
    if (n < 3) return 0;
    if (n <= 4) return 1;
    if (n == 5) return 2;
    if (n == 6) return 3;
    if (n == 7) return 5;
    return 11; // 8자 이상
  }

  /// 단어 제출 검증 결과.
  static WordCheck check(String board, String word, Set<String> alreadyFound) {
    final w = word.toLowerCase().trim();
    if (w.length < 3) return WordCheck.tooShort;
    if (alreadyFound.contains(w)) return WordCheck.duplicate;
    if (!inDictionary(w)) return WordCheck.notInDictionary;
    if (!canFormWord(board, w)) return WordCheck.notOnBoard;
    return WordCheck.valid;
  }

  /// 단어 목록의 총점.
  static int totalScore(Iterable<String> words) {
    var sum = 0;
    for (final w in words) {
      sum += scoreFor(w);
    }
    return sum;
  }
}

/// 단어 제출 검증 결과.
enum WordCheck {
  valid,
  tooShort,
  duplicate,
  notInDictionary,
  notOnBoard;

  /// 사용자에게 보여줄 한국어 메시지.
  String get message {
    switch (this) {
      case WordCheck.valid:
        return '정답!';
      case WordCheck.tooShort:
        return '너무 짧은 단어입니다';
      case WordCheck.duplicate:
        return '이미 찾은 단어입니다';
      case WordCheck.notInDictionary:
        return '사전에 없는 단어입니다';
      case WordCheck.notOnBoard:
        return '보드에서 만들 수 없는 경로입니다';
    }
  }
}
