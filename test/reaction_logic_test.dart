import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/reaction/reaction_logic.dart';

void main() {
  group('roundWinner', () {
    test('A가 더 빠름 → A 승(0)', () {
      expect(ReactionLogic.roundWinner(220, 310), 0);
    });

    test('B가 더 빠름 → B 승(1)', () {
      expect(ReactionLogic.roundWinner(400, 250), 1);
    });

    test('동일 ms → 무승부(-1)', () {
      expect(ReactionLogic.roundWinner(300, 300), -1);
    });

    test('A 부정출발 → B 승(1)', () {
      expect(ReactionLogic.roundWinner(ReactionLogic.falseStart, 500), 1);
    });

    test('B 부정출발 → A 승(0)', () {
      expect(ReactionLogic.roundWinner(500, ReactionLogic.falseStart), 0);
    });

    test('둘 다 부정출발 → 무승부(-1)', () {
      expect(
        ReactionLogic.roundWinner(
          ReactionLogic.falseStart,
          ReactionLogic.falseStart,
        ),
        -1,
      );
    });

    test('부정출발은 아무리 빠른 정상 반응에도 진다', () {
      // A 부정출발(-1), B 느린 반응(900ms) → B 승.
      expect(ReactionLogic.roundWinner(ReactionLogic.falseStart, 900), 1);
    });
  });

  group('bothRecorded', () {
    test('둘 다 기록됨', () {
      expect(ReactionLogic.bothRecorded(200, 300), isTrue);
    });
    test('부정출발도 기록으로 간주', () {
      expect(ReactionLogic.bothRecorded(ReactionLogic.falseStart, 300), isTrue);
    });
    test('한쪽 미기록(0)', () {
      expect(
        ReactionLogic.bothRecorded(ReactionLogic.notRecorded, 300),
        isFalse,
      );
    });
  });

  group('matchWinnerIndex', () {
    test('목표 도달자 인덱스', () {
      expect(ReactionLogic.matchWinnerIndex([3, 1], 3), 0);
      expect(ReactionLogic.matchWinnerIndex([1, 3], 3), 1);
    });
    test('아무도 도달 못함 → null', () {
      expect(ReactionLogic.matchWinnerIndex([2, 1], 3), isNull);
    });
  });
}
