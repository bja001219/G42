import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/onecard/onecard_logic.dart';

void main() {
  group('카드 파싱', () {
    test('무늬/랭크 추출', () {
      expect(OneCardLogic.suitOf('H7'), 'H');
      expect(OneCardLogic.rankOf('H7'), '7');
      expect(OneCardLogic.suitOf('D10'), 'D');
      expect(OneCardLogic.rankOf('D10'), '10');
      expect(OneCardLogic.rankOf('SA'), 'A');
    });

    test('조커 판정', () {
      expect(OneCardLogic.isJoker('JR'), true);
      expect(OneCardLogic.isJoker('JB'), true);
      expect(OneCardLogic.isJoker('H7'), false);
      expect(OneCardLogic.suitOf('JR'), isNull);
      expect(OneCardLogic.rankOf('JB'), isNull);
    });
  });

  group('덱 생성', () {
    test('조커 없이 52장', () {
      final deck = OneCardLogic.freshDeck(rng: Random(1));
      expect(deck.length, 52);
      expect(deck.toSet().length, 52); // 중복 없음.
    });

    test('조커 포함 54장', () {
      final deck = OneCardLogic.freshDeck(jokers: true, rng: Random(1));
      expect(deck.length, 54);
      expect(deck.contains('JR'), true);
      expect(deck.contains('JB'), true);
    });
  });

  group('합법수 판정', () {
    test('무늬 일치', () {
      expect(OneCardLogic.canPlay('H3', topCard: 'H7', activeSuit: 'H'), true);
    });

    test('랭크 일치', () {
      expect(OneCardLogic.canPlay('S7', topCard: 'H7', activeSuit: 'H'), true);
    });

    test('무늬·랭크 모두 불일치면 불가', () {
      expect(OneCardLogic.canPlay('S3', topCard: 'H7', activeSuit: 'H'), false);
    });

    test('7로 바뀐 activeSuit를 따른다', () {
      // top은 H7이지만 7로 무늬가 C로 변경된 상황.
      expect(OneCardLogic.canPlay('C3', topCard: 'H7', activeSuit: 'C'), true);
      expect(OneCardLogic.canPlay('H3', topCard: 'H7', activeSuit: 'C'), false);
    });

    test('playableCards / hasPlayable', () {
      final hand = ['H3', 'S9', 'C7'];
      final playable = OneCardLogic.playableCards(
        hand,
        topCard: 'H7',
        activeSuit: 'H',
      );
      expect(playable.contains('H3'), true); // 무늬.
      expect(playable.contains('C7'), true); // 랭크.
      expect(playable.contains('S9'), false);
      expect(
        OneCardLogic.hasPlayable(hand, topCard: 'H7', activeSuit: 'H'),
        true,
      );
      expect(
        OneCardLogic.hasPlayable(['S9'], topCard: 'H7', activeSuit: 'H'),
        false,
      );
    });
  });

  group('2 누적 공격', () {
    test('attackValue / attackKind', () {
      expect(OneCardLogic.attackValue('H2'), 2);
      expect(OneCardLogic.attackKindOf('H2'), 'two');
      expect(OneCardLogic.attackValue('JR'), 5);
      expect(OneCardLogic.attackKindOf('JR'), 'joker');
      expect(OneCardLogic.attackValue('H9'), 0);
      expect(OneCardLogic.attackKindOf('H9'), '');
    });

    test('공격 중에는 2로만 방어 가능', () {
      // pending>0, attackKind='two' → 2만 낼 수 있다.
      expect(
        OneCardLogic.canPlay(
          'S2',
          topCard: 'H2',
          activeSuit: 'H',
          pending: 2,
          attackKind: 'two',
        ),
        true,
      );
      // 무늬가 같아도 2가 아니면 막을 수 없다.
      expect(
        OneCardLogic.canPlay(
          'H9',
          topCard: 'H2',
          activeSuit: 'H',
          pending: 2,
          attackKind: 'two',
        ),
        false,
      );
    });

    test('2 공격은 조커로 막을 수 없다(혼합 금지)', () {
      expect(
        OneCardLogic.canPlay(
          'JR',
          topCard: 'H2',
          activeSuit: 'H',
          pending: 2,
          attackKind: 'two',
        ),
        false,
      );
    });

    test('조커 공격은 조커로만 막는다', () {
      expect(
        OneCardLogic.canPlay(
          'JB',
          topCard: 'JR',
          activeSuit: 'H',
          pending: 5,
          attackKind: 'joker',
        ),
        true,
      );
      expect(
        OneCardLogic.canPlay(
          'H2',
          topCard: 'JR',
          activeSuit: 'H',
          pending: 5,
          attackKind: 'joker',
        ),
        false,
      );
    });

    test('누적 합산: 2+2 = 4', () {
      final first = OneCardLogic.attackValue('H2');
      final second = OneCardLogic.attackValue('S2');
      expect(first + second, 4);
    });
  });

  group('7 무늬 변경 / A 스킵', () {
    test('isWildSuit / isSkip', () {
      expect(OneCardLogic.isWildSuit('H7'), true);
      expect(OneCardLogic.isWildSuit('H8'), false);
      expect(OneCardLogic.isSkip('SA'), true);
      expect(OneCardLogic.isSkip('S2'), false);
    });
  });

  group('드로우 / 재활용', () {
    test('충분한 덱에서 정상 뽑기', () {
      final deck = ['C3', 'D4', 'S5', 'H6'];
      final res = OneCardLogic.draw(deck, ['SA'], 2, rng: Random(1));
      expect(res.drawn.length, 2);
      expect(res.deck.length, 2);
      // 원본 불변.
      expect(deck.length, 4);
    });

    test('덱 소진 시 버린 더미(맨 위 제외) 재활용', () {
      final deck = <String>['C3']; // 1장뿐.
      // 버린 더미: 맨 위 H7은 남기고 나머지를 섞어 재활용.
      final discard = ['S5', 'D8', 'H7'];
      final res = OneCardLogic.draw(
        deck,
        discard,
        3,
        rng: Random(1),
        keepTop: 'H7',
      );
      // 덱1 + 재활용2(S5,D8) = 3장 뽑기 가능.
      expect(res.drawn.length, 3);
      expect(res.drawn.contains('H7'), false); // 맨 위는 재활용 안 됨.
    });

    test('보충할 카드가 없으면 가능한 만큼만', () {
      final deck = <String>['C3'];
      final res = OneCardLogic.draw(
        deck,
        ['H7'],
        4,
        rng: Random(1),
        keepTop: 'H7',
      );
      // 덱1장만, 재활용 가능 카드 없음 → 1장만.
      expect(res.drawn.length, 1);
    });
  });

  group('승리', () {
    test('손패 0이면 승리', () {
      expect(OneCardLogic.isWinner([]), true);
      expect(OneCardLogic.isWinner(['H3']), false);
    });
  });

  group('조커 (와일드 +5) — 정식 활성화', () {
    test('덱에 빨강/검정 조커 2장이 포함된다', () {
      final deck = OneCardLogic.freshDeck(jokers: true, rng: Random(7));
      expect(deck.where(OneCardLogic.isJoker).length, 2);
    });

    test('조커는 평시(공격 없음) 어떤 더미 위에도 낼 수 있다', () {
      expect(OneCardLogic.canPlay('JR', topCard: 'H7', activeSuit: 'H'), true);
      expect(OneCardLogic.canPlay('JB', topCard: 'S10', activeSuit: 'S'), true);
    });

    test('조커 공격값은 +5, 종류는 joker', () {
      expect(OneCardLogic.attackValue('JR'), 5);
      expect(OneCardLogic.attackValue('JB'), 5);
      expect(OneCardLogic.attackKindOf('JR'), 'joker');
    });

    test('조커 공격은 조커로만 방어 — 2/일반 카드는 불가', () {
      expect(
        OneCardLogic.canPlay(
          'JB',
          topCard: 'JR',
          activeSuit: 'S',
          pending: 5,
          attackKind: 'joker',
        ),
        true,
      );
      expect(
        OneCardLogic.canPlay(
          'S2',
          topCard: 'JR',
          activeSuit: 'S',
          pending: 5,
          attackKind: 'joker',
        ),
        false,
      );
      expect(
        OneCardLogic.canPlay(
          'S9',
          topCard: 'JR',
          activeSuit: 'S',
          pending: 5,
          attackKind: 'joker',
        ),
        false,
      );
    });

    test('조커끼리 누적: 5 + 5 = 10', () {
      expect(
        OneCardLogic.attackValue('JR') + OneCardLogic.attackValue('JB'),
        10,
      );
    });

    test('일반 공격(2)은 조커로 막을 수 없다(혼합 금지)', () {
      expect(
        OneCardLogic.canPlay(
          'JR',
          topCard: 'H2',
          activeSuit: 'H',
          pending: 2,
          attackKind: 'two',
        ),
        false,
      );
    });

    test('와일드 무늬지정 후: 더미가 조커여도 지정 무늬로 이어간다', () {
      // 조커가 버려지고 활성 무늬가 C(클로버)로 지정된 상황.
      // top이 조커라 랭크 일치는 불가능 → 지정 무늬로만 이어진다.
      expect(
        OneCardLogic.canPlay('C5', topCard: 'JR', activeSuit: 'C'),
        true, // 지정 무늬 일치.
      );
      expect(
        OneCardLogic.canPlay('H5', topCard: 'JR', activeSuit: 'C'),
        false, // 다른 무늬 + 조커 더미라 랭크 일치 불가.
      );
      expect(
        OneCardLogic.canPlay('JB', topCard: 'JR', activeSuit: 'C'),
        true, // 조커는 언제든 가능.
      );
    });

    test('playableCards: 조커 공격 방어 상황에선 손패의 조커만 낼 수 있다', () {
      final hand = ['H9', 'S2', 'JB', 'C7'];
      final playable = OneCardLogic.playableCards(
        hand,
        topCard: 'JR',
        activeSuit: 'S',
        pending: 5,
        attackKind: 'joker',
      );
      expect(playable, ['JB']);
    });
  });

  group('표시', () {
    test('label', () {
      expect(OneCardLogic.label('H7'), '♥7');
      expect(OneCardLogic.label('S10'), '♠10');
      expect(OneCardLogic.label('JR'), '조커(빨강)');
    });
  });
}
