import 'dart:math';

import 'boggle_ko_logic.dart';
import 'boggle_logic.dart';

/// 보글 언어/규칙 추상화. 같은 [BoggleView]로 영어/한글을 모두 구동한다.
///
/// 경로·인접 판정은 격자 크기(NxN)에만 의존하므로 [BoggleLogic]의 static을
/// 공유하고, 언어별로 다른 부분(글자판 생성/표기/사전/점수)만 이 인터페이스로 분리한다.
///
/// 격자 크기 [size]는 모드마다 다르다(4·5·6). 인접/경로 검증 헬퍼는 이 크기를
/// 자동으로 반영한다.
abstract class BoggleRules {
  const BoggleRules({required this.size});

  /// 격자 한 변(4·5·6).
  final int size;

  /// 보드 전체 칸 수.
  int get cellCount => size * size;

  String get id; // 'en' | 'ko'
  int get durationSeconds;
  int get minWordLength;

  String randomBoard(Random rng);
  String displayAt(String grid, int index);
  String wordFromPath(String grid, List<int> path);
  int scoreFor(String word);
  WordCheck check(String grid, String word, Set<String> alreadyFound);

  /// 입력/표시용 단어 변환(영어=대문자, 한글=그대로).
  String displayWord(String word);

  // ---- 크기 의존 기하(영어/한글 공통) ----------------------------------------

  /// 두 칸이 인접한가(현재 격자 크기 기준).
  bool adjacent(int a, int b) => BoggleLogic.adjacent(size, a, b);

  /// 경로가 유효한가(현재 격자 크기 기준).
  bool isValidPath(List<int> path) => BoggleLogic.isValidPath(size, path);
}

/// 영어 보글(기존 동작 위임).
class EnglishBoggleRules extends BoggleRules {
  const EnglishBoggleRules({super.size = BoggleLogic.defaultSize});

  @override
  String get id => 'en';
  @override
  int get durationSeconds => BoggleLogic.durationFor(size);
  @override
  int get minWordLength => 3;

  @override
  String randomBoard(Random rng) => BoggleLogic.randomBoard(size, rng);
  @override
  String displayAt(String grid, int index) =>
      BoggleLogic.displayAt(grid, index);
  @override
  String wordFromPath(String grid, List<int> path) =>
      BoggleLogic.wordFromPath(grid, path);
  @override
  int scoreFor(String word) => BoggleLogic.scoreFor(word);
  @override
  WordCheck check(String grid, String word, Set<String> alreadyFound) =>
      BoggleLogic.check(size, grid, word, alreadyFound);
  @override
  String displayWord(String word) => word.toUpperCase();
}

/// 한글 보글.
class KoreanBoggleRules extends BoggleRules {
  const KoreanBoggleRules({super.size = KoBoggleLogic.defaultSize});

  @override
  String get id => 'ko';
  @override
  int get durationSeconds => KoBoggleLogic.durationFor(size);
  @override
  int get minWordLength => KoBoggleLogic.minWordLength;

  @override
  String randomBoard(Random rng) => KoBoggleLogic.randomBoard(size, rng);
  @override
  String displayAt(String grid, int index) =>
      KoBoggleLogic.displayAt(grid, index);
  @override
  String wordFromPath(String grid, List<int> path) =>
      KoBoggleLogic.wordFromPath(grid, path);
  @override
  int scoreFor(String word) => KoBoggleLogic.scoreFor(word);
  @override
  WordCheck check(String grid, String word, Set<String> alreadyFound) =>
      KoBoggleLogic.check(size, grid, word, alreadyFound);
  @override
  String displayWord(String word) => word; // 한글은 대소문자 없음
}
