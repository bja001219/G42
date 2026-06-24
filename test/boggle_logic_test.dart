import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/boggle/boggle_logic.dart';

void main() {
  // 명시적으로 구성한 16자 보드(행 우선, 4x4):
  //  index: 0  1  2  3
  //         4  5  6  7
  //         8  9  10 11
  //         12 13 14 15
  //  c a t s
  //  o a r e
  //  d o g t
  //  e n s w
  const grid = 'catsoaredogtensw';
  const size = 4;

  group('점수표 (표준 보글)', () {
    test('3~4자=1, 5자=2, 6자=3, 7자=5, 8자+=11', () {
      expect(BoggleLogic.scoreFor('cat'), 1);
      expect(BoggleLogic.scoreFor('cats'), 1);
      expect(BoggleLogic.scoreFor('soare'), 2);
      expect(BoggleLogic.scoreFor('orange'), 3);
      expect(BoggleLogic.scoreFor('amazing'), 5);
      expect(BoggleLogic.scoreFor('elephant'), 11);
      expect(BoggleLogic.scoreFor('extraordinary'), 11);
    });

    test('2자 이하는 0점', () {
      expect(BoggleLogic.scoreFor('ab'), 0);
      expect(BoggleLogic.scoreFor('a'), 0);
    });

    test('totalScore는 합산', () {
      expect(BoggleLogic.totalScore(['cat', 'soare', 'orange']), 1 + 2 + 3);
    });
  });

  group('인접 판정', () {
    test('상하좌우/대각선은 인접', () {
      expect(BoggleLogic.adjacent(size, 0, 1), true); // 우
      expect(BoggleLogic.adjacent(size, 0, 4), true); // 하
      expect(BoggleLogic.adjacent(size, 0, 5), true); // 대각
      expect(BoggleLogic.adjacent(size, 5, 0), true);
    });

    test('자기 자신/두 칸 이상 떨어지면 비인접', () {
      expect(BoggleLogic.adjacent(size, 0, 0), false);
      expect(BoggleLogic.adjacent(size, 0, 2), false);
      expect(BoggleLogic.adjacent(size, 0, 8), false);
      expect(BoggleLogic.adjacent(size, 3, 4), false); // 줄바꿈 모서리(다른 행)
    });
  });

  group('경로 유효성', () {
    test('연속 인접 + 중복 없음이면 유효', () {
      // c(0) a(1) t(2): 가로 연속.
      expect(BoggleLogic.isValidPath(size, [0, 1, 2]), true);
    });

    test('중복 칸 재사용은 무효', () {
      expect(BoggleLogic.isValidPath(size, [0, 1, 0]), false);
    });

    test('비인접 점프는 무효', () {
      expect(BoggleLogic.isValidPath(size, [0, 2]), false);
    });

    test('빈 경로는 무효', () {
      expect(BoggleLogic.isValidPath(size, []), false);
    });
  });

  group('보드에서 단어 만들기 (canFormWord)', () {
    test('인접 경로로 가능한 단어', () {
      // grid: c a t s / o a r e / d o g t / e n s w
      expect(BoggleLogic.canFormWord(size, grid, 'cat'), true); // 0-1-2
      expect(BoggleLogic.canFormWord(size, grid, 'cats'), true); // 0-1-2-3
      expect(BoggleLogic.canFormWord(size, grid, 'dog'), true); // 8-9-10
      expect(BoggleLogic.canFormWord(size, grid, 'rat'), true); // r(6) a(5) t(2)
    });

    test('칸 재사용이 필요한 단어는 불가', () {
      // 같은 칸을 두 번 써야 하는 단어는 만들 수 없다.
      expect(BoggleLogic.canFormWord(size, grid, 'catt'), false);
    });

    test('보드에 없는 글자가 들어간 단어는 불가', () {
      expect(BoggleLogic.canFormWord(size, grid, 'zebra'), false);
    });

    test('비인접 글자 조합은 불가', () {
      // c(0) s(3): 인접하지 않음.
      expect(BoggleLogic.canFormWord(size, grid, 'cs'), false);
    });
  });

  group('q는 qu로 확장', () {
    // q a u .  → 'qu'(0) i(?) ... 'q' 한 칸이 'qu' 두 글자.
    //  q i z .
    //  . . . .
    //  . . . .
    //  . . . .
    const qgrid = 'qiz.............';
    test('q 칸 하나가 qu를 소비', () {
      // 'quiz': q(0)=qu, i(1), z(2) → 0-1-2 인접.
      expect(BoggleLogic.canFormWord(size, qgrid, 'quiz'), true);
      expect(BoggleLogic.displayAt(qgrid, 0), 'Qu');
      expect(BoggleLogic.letterAt(qgrid, 0), 'qu');
    });
  });

  group('사전 조회', () {
    test('흔한 단어는 사전에 있다', () {
      expect(BoggleLogic.inDictionary('cat'), true);
      expect(BoggleLogic.inDictionary('dog'), true);
      expect(BoggleLogic.inDictionary('quiz'), true);
      expect(BoggleLogic.inDictionary('CAT'), true); // 대소문자 무관
    });

    test('없는 단어/비단어는 사전에 없다', () {
      expect(BoggleLogic.inDictionary('zzxq'), false);
      expect(BoggleLogic.inDictionary(''), false);
    });
  });

  group('통합 검증 (check)', () {
    test('정상 단어는 valid', () {
      expect(BoggleLogic.check(size, grid, 'cat', {}), WordCheck.valid);
    });

    test('3자 미만은 tooShort', () {
      expect(BoggleLogic.check(size, grid, 'ca', {}), WordCheck.tooShort);
    });

    test('이미 찾은 단어는 duplicate', () {
      expect(
        BoggleLogic.check(size, grid, 'cat', {'cat'}),
        WordCheck.duplicate,
      );
    });

    test('사전에 없으면 notInDictionary', () {
      expect(
        BoggleLogic.check(size, grid, 'qzx', {}),
        anyOf(WordCheck.notInDictionary, WordCheck.notOnBoard),
      );
    });

    test('사전엔 있지만 보드로 못 만들면 notOnBoard', () {
      // 'zebra'는 사전엔 있으나 이 보드엔 만들 수 없다.
      expect(BoggleLogic.check(size, grid, 'zebra', {}), WordCheck.notOnBoard);
    });
  });

  group('보드 생성 (4x4)', () {
    test('randomBoard는 16자 소문자', () {
      final rng = Random(42);
      final gen = BoggleLogic.randomBoard(size, rng);
      expect(gen.length, 16);
      expect(RegExp(r'^[a-z]{16}$').hasMatch(gen), true);
    });

    test('같은 시드는 같은 보드(온라인 동일판 보장 가능)', () {
      expect(
        BoggleLogic.randomBoard(size, Random(7)),
        BoggleLogic.randomBoard(size, Random(7)),
      );
    });
  });

  group('큰 보드 (5x5 / 6x6)', () {
    test('cellCount / durationFor 스케일', () {
      expect(BoggleLogic.cellCount(4), 16);
      expect(BoggleLogic.cellCount(5), 25);
      expect(BoggleLogic.cellCount(6), 36);
      expect(BoggleLogic.durationFor(4), 90);
      expect(BoggleLogic.durationFor(5), 120);
      expect(BoggleLogic.durationFor(6), 150);
    });

    test('5x5는 25자, 6x6는 36자 소문자', () {
      for (final sz in const [5, 6]) {
        final cells = sz * sz;
        final gen = BoggleLogic.randomBoard(sz, Random(3));
        expect(gen.length, cells, reason: 'size=$sz');
        expect(
          RegExp('^[a-z]{$cells}\$').hasMatch(gen),
          true,
          reason: 'size=$sz: $gen',
        );
      }
    });

    test('같은 시드는 같은 보드 (5x5/6x6)', () {
      expect(
        BoggleLogic.randomBoard(5, Random(7)),
        BoggleLogic.randomBoard(5, Random(7)),
      );
      expect(
        BoggleLogic.randomBoard(6, Random(7)),
        BoggleLogic.randomBoard(6, Random(7)),
      );
    });

    test('5x5 인접은 행 경계를 넘지 않는다', () {
      // index 4(행0 끝)와 5(행1 시작)는 다른 행 → 비인접.
      expect(BoggleLogic.adjacent(5, 4, 5), false);
      expect(BoggleLogic.adjacent(5, 0, 1), true); // 같은 행 우측
      expect(BoggleLogic.adjacent(5, 0, 5), true); // 바로 아래
      expect(BoggleLogic.adjacent(5, 0, 6), true); // 대각
    });

    test('canFormWord는 큰 보드에서도 동작', () {
      // 5x5 상단 행에 'hello' 배치, 나머지는 채움 문자.
      const g = 'hello'
          'xxxxx'
          'xxxxx'
          'xxxxx'
          'xxxxx';
      expect(BoggleLogic.canFormWord(5, g, 'hello'), true); // 0-1-2-3-4
      expect(BoggleLogic.canFormWord(5, g, 'help'), false); // 'p' 없음
    });
  });

  group('10x10 큰 판 (주사위 없는 크기 → 빈도 채움)', () {
    test('100자 소문자', () {
      final gen = BoggleLogic.randomBoard(10, Random(5));
      expect(gen.length, 100);
      expect(RegExp(r'^[a-z]{100}$').hasMatch(gen), true);
    });

    test('같은 시드는 같은 보드(동일판 보장)', () {
      expect(
        BoggleLogic.randomBoard(10, Random(99)),
        BoggleLogic.randomBoard(10, Random(99)),
      );
    });

    test('durationFor(10) = 210초', () {
      expect(BoggleLogic.cellCount(10), 100);
      expect(BoggleLogic.durationFor(10), 210);
    });

    test('10x10 인접은 행 경계를 넘지 않는다', () {
      // index 9(행0 끝)와 10(행1 시작)은 다른 행 → 비인접.
      expect(BoggleLogic.adjacent(10, 9, 10), false);
      expect(BoggleLogic.adjacent(10, 0, 1), true); // 같은 행
      expect(BoggleLogic.adjacent(10, 0, 10), true); // 바로 아래
      expect(BoggleLogic.adjacent(10, 0, 11), true); // 대각
    });

    test('빈도 채움 보드에서도 인접 단어를 만들 수 있다', () {
      // 첫 행에 'water'를 깔고 나머지는 'x'로 채운 10x10.
      final g = 'water${'x' * 95}';
      expect(g.length, 100);
      expect(BoggleLogic.canFormWord(10, g, 'water'), true); // 0-1-2-3-4
    });
  });
}
