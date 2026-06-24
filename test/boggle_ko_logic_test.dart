import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/boggle/boggle_ko_logic.dart';
import 'package:g42/games/boggle/boggle_logic.dart';
import 'package:g42/games/boggle/boggle_words_ko.dart';

void main() {
  // 4x4 = 16칸. 윗줄(0~3)에 '사람나무', 나머지는 '가'로 채운 통제용 보드.
  const grid =
      '사람나무'
      '가가가가'
      '가가가가'
      '가가가가';
  const size = 4;

  test('사전 로드: 충분한 한글 단어 + 알려진 단어 포함', () {
    expect(koBoggleWords.length, greaterThan(10000));
    expect(koBoggleWords.contains('사람'), true);
    expect(koBoggleWords.contains('바다'), true);
    expect(koBoggleWords.contains('나무'), true);
  });

  test('scoreFor: 음절 수 기준 (2=1,3=2,4=3,5+=5)', () {
    expect(KoBoggleLogic.scoreFor('가'), 0); // 1음절
    expect(KoBoggleLogic.scoreFor('사람'), 1); // 2
    expect(KoBoggleLogic.scoreFor('무지개'), 2); // 3
    expect(KoBoggleLogic.scoreFor('가나다라'), 3); // 4
    expect(KoBoggleLogic.scoreFor('가나다라마'), 5); // 5+
  });

  test('canFormWord: 인접 경로로 만들 수 있는 단어만 (BoggleLogic 재사용)', () {
    expect(KoBoggleLogic.canFormWord(size, grid, '사람'), true); // 0→1 인접
    expect(KoBoggleLogic.canFormWord(size, grid, '나무'), true); // 2→3 인접
    expect(KoBoggleLogic.canFormWord(size, grid, '하늘'), false); // 글자 없음
  });

  test('check: 유효/짧음/중복/사전없음/보드밖', () {
    expect(KoBoggleLogic.check(size, grid, '사람', {}), WordCheck.valid);
    expect(KoBoggleLogic.check(size, grid, '가', {}), WordCheck.tooShort);
    expect(KoBoggleLogic.check(size, grid, '사람', {'사람'}), WordCheck.duplicate);
    expect(
      KoBoggleLogic.check(size, grid, '람나', {}),
      WordCheck.notInDictionary,
    );
    // '바다'는 사전엔 있으나 이 보드에선 만들 수 없음.
    expect(KoBoggleLogic.check(size, grid, '바다', {}), WordCheck.notOnBoard);
  });

  test('durationFor: 크기별 스케일 (영어판과 동일)', () {
    expect(KoBoggleLogic.durationFor(4), 90);
    expect(KoBoggleLogic.durationFor(5), 120);
    expect(KoBoggleLogic.durationFor(6), 150);
  });

  test('randomBoard 4x4: 16개 한글 음절 + 심은 단어가 실제로 찾아짐', () {
    for (final seed in [1, 7, 42, 123]) {
      final b = KoBoggleLogic.randomBoard(size, Random(seed));
      expect(b.length, 16, reason: 'seed=$seed');
      expect(
        b.runes.every((r) => r >= 0xAC00 && r <= 0xD7A3),
        true,
        reason: '모든 칸이 한글 음절이어야 함 (seed=$seed): $b',
      );
      // 단어 심기 덕분에 사전 단어가 최소 1개는 보드에서 만들어져야 한다.
      final hasWord = koBoggleWords.any(
        (w) => KoBoggleLogic.canFormWord(size, b, w),
      );
      expect(hasWord, true, reason: '심은 단어가 찾아져야 함 (seed=$seed): $b');
    }
  });

  test('randomBoard 5x5/6x6: 칸 수 일치 + 전부 한글 + 단어 심김', () {
    for (final sz in const [5, 6]) {
      final cells = sz * sz;
      for (final seed in [1, 7, 42]) {
        final b = KoBoggleLogic.randomBoard(sz, Random(seed));
        expect(b.length, cells, reason: 'size=$sz seed=$seed');
        expect(
          b.runes.every((r) => r >= 0xAC00 && r <= 0xD7A3),
          true,
          reason: '모든 칸이 한글이어야 함 (size=$sz seed=$seed): $b',
        );
        final hasWord = koBoggleWords.any(
          (w) => KoBoggleLogic.canFormWord(sz, b, w),
        );
        expect(hasWord, true, reason: '심은 단어가 찾아져야 함 (size=$sz seed=$seed)');
      }
    }
  });

  test('randomBoard 10x10: 100칸 전부 한글 + 단어 여러 개 심김', () {
    for (final seed in [1, 7]) {
      final b = KoBoggleLogic.randomBoard(10, Random(seed));
      expect(b.length, 100, reason: 'seed=$seed');
      expect(
        b.runes.every((r) => r >= 0xAC00 && r <= 0xD7A3),
        true,
        reason: '모든 칸이 한글이어야 함 (seed=$seed)',
      );
      // 큰 판은 단어를 많이 심으므로(약 cells/4 ≈ 25개) 최소 1개는 반드시 찾아져야 한다.
      final hasWord = koBoggleWords.any(
        (w) => KoBoggleLogic.canFormWord(10, b, w),
      );
      expect(hasWord, true, reason: '심은 단어가 찾아져야 함 (seed=$seed)');
    }
  });
}
