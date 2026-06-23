import 'dart:math';

import 'boggle_ko_logic.dart';
import 'boggle_logic.dart';

/// 보글 언어/규칙 추상화. 같은 [BoggleView]로 영어/한글을 모두 구동한다.
///
/// 경로·인접 판정은 격자 크기(4x4)에만 의존하므로 [BoggleLogic]의 static을
/// 공유하고, 언어별로 다른 부분(글자판 생성/표기/사전/점수)만 이 인터페이스로 분리한다.
abstract class BoggleRules {
  const BoggleRules();

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
}

/// 영어 보글(기존 동작 위임).
class EnglishBoggleRules extends BoggleRules {
  const EnglishBoggleRules();

  @override
  String get id => 'en';
  @override
  int get durationSeconds => BoggleLogic.durationSeconds;
  @override
  int get minWordLength => 3;

  @override
  String randomBoard(Random rng) => BoggleLogic.randomBoard(rng);
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
      BoggleLogic.check(grid, word, alreadyFound);
  @override
  String displayWord(String word) => word.toUpperCase();
}

/// 한글 보글.
class KoreanBoggleRules extends BoggleRules {
  const KoreanBoggleRules();

  @override
  String get id => 'ko';
  @override
  int get durationSeconds => KoBoggleLogic.durationSeconds;
  @override
  int get minWordLength => KoBoggleLogic.minWordLength;

  @override
  String randomBoard(Random rng) => KoBoggleLogic.randomBoard(rng);
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
      KoBoggleLogic.check(grid, word, alreadyFound);
  @override
  String displayWord(String word) => word; // 한글은 대소문자 없음
}
