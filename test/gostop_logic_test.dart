import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/gostop/gostop_cards.dart';
import 'package:g42/games/gostop/gostop_logic.dart';

/// 테스트 편의: 임의의 state 생성.
Map<String, dynamic> mkState({
  List<int> hand0 = const [],
  List<int> hand1 = const [],
  List<int> floor = const [],
  List<int> stock = const [],
  List<int> cap0 = const [],
  List<int> cap1 = const [],
}) => <String, dynamic>{
  'phase': 'playing',
  'floor': List<int>.from(floor),
  'stock': List<int>.from(stock),
  'hands': <String, List<int>>{
    'a': List<int>.from(hand0),
    'b': List<int>.from(hand1),
  },
  'captured': <String, List<int>>{
    'a': List<int>.from(cap0),
    'b': List<int>.from(cap1),
  },
  'scores': <String, int>{'a': 0, 'b': 0},
  'go': <String, int>{'a': 0, 'b': 0},
  'shaken': <String, int>{'a': 0, 'b': 0},
  'bomb': <String, int>{'a': 0, 'b': 0},
  'ppeokCount': <String, int>{'a': 0, 'b': 0},
  'nagariMult': 1,
  'firstTurn': true,
  'awaitingGoStop': '',
  'lastEvent': 'none',
};

List<int> capA(Map<String, dynamic> s) =>
    ((s['captured'] as Map)['a'] as List).cast<int>();
List<int> capB(Map<String, dynamic> s) =>
    ((s['captured'] as Map)['b'] as List).cast<int>();
List<int> floorOf(Map<String, dynamic> s) => (s['floor'] as List).cast<int>();

void main() {
  group('카드 테이블 합계/분류', () {
    test('타입별 장수 + 총합 (광5 열끗9 띠10 피24 = 48, +보너스3 = 51)', () {
      final gwang = GoStopCards.all
          .where((c) => c.type == HwatuType.gwang)
          .length;
      final animal = GoStopCards.all
          .where((c) => c.type == HwatuType.animal)
          .length;
      final ribbon = GoStopCards.all
          .where((c) => c.type == HwatuType.ribbon)
          .length;
      final junk = GoStopCards.all
          .where((c) => c.type == HwatuType.junk)
          .length;
      final bonus = GoStopCards.all
          .where((c) => c.type == HwatuType.bonus)
          .length;
      expect(gwang, 5);
      expect(animal, 9);
      expect(ribbon, 10);
      expect(junk, 24);
      expect(bonus, 3);
      expect(gwang + animal + ribbon + junk, 48);
      expect(GoStopCards.all.length, 51);
    });

    test('monthOf: 각 월 4장 연속', () {
      expect(GoStopCards.monthOf(0), 1);
      expect(GoStopCards.monthOf(3), 1);
      expect(GoStopCards.monthOf(4), 2);
      expect(GoStopCards.monthOf(47), 12);
      expect(GoStopCards.monthOf(48), 0); // 보너스.
    });

    test('파생 id 집합 검증', () {
      expect(GoStopCards.gwangIds, [0, 8, 28, 40, 44]);
      expect(GoStopCards.gwangBiId, 44);
      expect(GoStopCards.isGwangBi(44), true);
      expect(GoStopCards.isGwangBi(0), false);
      expect(GoStopCards.godoriIds.toSet(), {4, 12, 29});
      expect(GoStopCards.godoriIds.every(GoStopCards.isGodori), true);
      expect(GoStopCards.gukjinId, 32);
      expect(GoStopCards.isGukjin(32), true);
    });

    test('띠 색 분류 (홍/청/초/비)', () {
      for (final id in GoStopCards.hongdanIds) {
        expect(GoStopCards.ribbonColorOf(id), RibbonColor.hong);
      }
      for (final id in GoStopCards.cheongdanIds) {
        expect(GoStopCards.ribbonColorOf(id), RibbonColor.cheong);
      }
      for (final id in GoStopCards.chodanIds) {
        expect(GoStopCards.ribbonColorOf(id), RibbonColor.cho);
      }
      expect(GoStopCards.ribbonColorOf(GoStopCards.bidaeId), RibbonColor.bi);
      // 비띠는 홍/청/초단 세트에 포함되지 않는다.
      expect(GoStopCards.hongdanIds.contains(46), false);
    });

    test('junkValue: 일반피1 / 쌍피2 / 3피3', () {
      expect(GoStopCards.junkValue(2), 1); // 일반피.
      expect(GoStopCards.junkValue(41), 2); // 11월 쌍피.
      expect(GoStopCards.junkValue(47), 2); // 12월 쌍피.
      expect(GoStopCards.junkValue(49), 2); // 보너스 쌍피.
      expect(GoStopCards.junkValue(50), 2); // 보너스 쌍피.
      expect(GoStopCards.junkValue(48), 3); // 보너스 3피.
      expect(GoStopCards.junkValue(0), 0); // 광은 0.
    });

    test('isBonus', () {
      expect(GoStopCards.isBonus(48), true);
      expect(GoStopCards.isBonus(49), true);
      expect(GoStopCards.isBonus(50), true);
      expect(GoStopCards.isBonus(47), false);
    });
  });

  group('점수 계산 - 광', () {
    test('3광 = 3점 (비광 없음)', () {
      expect(GoStopLogic.scoreOf([0, 8, 28]).total, 3);
    });
    test('비광 포함 3광 = 2점', () {
      expect(GoStopLogic.scoreOf([0, 8, 44]).total, 2);
    });
    test('4광 = 4점', () {
      expect(GoStopLogic.scoreOf([0, 8, 28, 40]).total, 4);
    });
    test('5광 = 15점', () {
      expect(GoStopLogic.scoreOf([0, 8, 28, 40, 44]).total, 15);
    });
    test('2광 이하 = 0점', () {
      expect(GoStopLogic.scoreOf([0, 8]).total, 0);
    });
  });

  group('점수 계산 - 띠', () {
    test('홍단 = 3점', () {
      expect(GoStopLogic.scoreOf(GoStopCards.hongdanIds).total, 3);
    });
    test('청단 = 3점', () {
      expect(GoStopLogic.scoreOf(GoStopCards.cheongdanIds).total, 3);
    });
    test('초단 = 3점', () {
      expect(GoStopLogic.scoreOf(GoStopCards.chodanIds).total, 3);
    });
    test('띠 5장 = 1점 (세트 합산)', () {
      // 홍단 3장(세트 3점) + 비세트 띠 2장 = 5장(장수 1점) → 합 4점.
      final s = GoStopLogic.scoreOf([1, 5, 9, 46, 17]);
      expect(s.ribbonCount, 5);
      expect(s.total, 4); // 세트3 + 장수1.
    });
    test('띠 6장 = 장수 2점', () {
      // 비세트 띠만 6장: 13,17,25(초단3) → 세트3 + ... 초단세트가 됨.
      // 순수 장수만 보려면 세트 없는 6장 구성.
      final s = GoStopLogic.scoreOf([1, 5, 21, 33, 46, 13]); // 세트 없음.
      expect(s.ribbonCount, 6);
      expect(s.total, 2); // 장수만 1 + 1.
    });
  });

  group('점수 계산 - 열끗/고도리', () {
    test('고도리 = 5점', () {
      expect(GoStopLogic.scoreOf(GoStopCards.godoriIds).total, 5);
    });
    test('열끗 5장 = 1점', () {
      // 비고도리 열끗 5장: 16,20,24,36,45.
      final s = GoStopLogic.scoreOf([16, 20, 24, 36, 45]);
      expect(s.animalCount, 5);
      expect(s.total, 1);
    });
    test('고도리 + 열끗 장수 합산', () {
      // 고도리 3장(4,12,29) + 비고도리 2장(16,20) = 5장 → 장수1 + 고도리5 = 6.
      final s = GoStopLogic.scoreOf([4, 12, 29, 16, 20]);
      expect(s.hasGodori, true);
      expect(s.total, 6);
    });
  });

  group('점수 계산 - 피/쌍피/3피', () {
    test('피 10장 = 1점', () {
      final s = GoStopLogic.scoreOf([2, 3, 6, 7, 10, 11, 14, 15, 18, 19]);
      expect(s.junkValue, 10);
      expect(s.total, 1);
    });
    test('쌍피=2 / 3피=3 카운트', () {
      // 3피(48)=3 + 쌍피(41)=2 + 일반피 5장 = 10 → 1점.
      final s = GoStopLogic.scoreOf([48, 41, 2, 3, 6, 7, 11]);
      expect(s.junkValue, 10);
      expect(s.total, 1);
    });
    test('피 12장 = 3점', () {
      final s = GoStopLogic.scoreOf([
        2,
        3,
        6,
        7,
        10,
        11,
        14,
        15,
        18,
        19,
        22,
        23,
      ]);
      expect(s.junkValue, 12);
      expect(s.total, 3);
    });
  });

  group('점수 계산 - 국진 자동 선택', () {
    test('국진을 5번째 열끗으로 쓰면 유리(열끗1점)', () {
      // 비고도리 열끗 4장 + 국진 → 열끗5장=1점 vs 쌍피로 0점.
      final s = GoStopLogic.scoreOf([16, 20, 24, 36, 32]);
      expect(s.gukjinAsJunk, false);
      expect(s.total, 1);
    });
    test('국진을 쌍피로 쓰면 유리(10피=1점)', () {
      // 일반피 8가치 + 국진 → 쌍피로 10피=1점 vs 열끗1장=0점.
      final s = GoStopLogic.scoreOf([2, 3, 6, 7, 10, 11, 14, 15, 32]);
      expect(s.gukjinAsJunk, true);
      expect(s.total, 1);
    });
    test('국진 단독 = 0점', () {
      expect(GoStopLogic.scoreOf([32]).total, 0);
    });
  });

  group('finalizeScore - 배수', () {
    test('고 공식: 1고 = +1', () {
      expect(GoStopLogic.finalizeScore(9, goCount: 1), 10);
    });
    test('고 공식: 2고 = +2', () {
      expect(GoStopLogic.finalizeScore(7, goCount: 2), 9);
    });
    test('고 공식: 3고 = (base+2)×2', () {
      expect(GoStopLogic.finalizeScore(7, goCount: 3), 18); // (7+2)*2.
    });
    test('고 공식: 4고 = (base+2)×4', () {
      expect(GoStopLogic.finalizeScore(7, goCount: 4), 36); // (7+2)*4.
    });
    test('사양서 예시1: 기본9 + 1고 + 피박 = 20', () {
      expect(GoStopLogic.finalizeScore(9, goCount: 1, pibak: true), 20);
    });
    test('사양서 예시2: 기본7 + 3고 + 흔들기1 = 36', () {
      expect(GoStopLogic.finalizeScore(7, goCount: 3, shakenCount: 1), 36);
    });
    test('흔들기 ×2 / 폭탄 ×2', () {
      expect(GoStopLogic.finalizeScore(5, shakenCount: 1), 10);
      expect(GoStopLogic.finalizeScore(5, bombCount: 1), 10);
      expect(GoStopLogic.finalizeScore(5, shakenCount: 1, bombCount: 1), 20);
    });
    test('나가리 누적 배수', () {
      expect(GoStopLogic.finalizeScore(5, nagariMult: 2), 10);
      expect(GoStopLogic.finalizeScore(5, nagariMult: 4), 20);
    });
    test('광박 + 고박 ×2 누적', () {
      expect(GoStopLogic.finalizeScore(5, gwangbak: true), 10);
      expect(GoStopLogic.finalizeScore(5, gobak: true), 10);
      expect(GoStopLogic.finalizeScore(5, gwangbak: true, gobak: true), 20);
    });
  });

  group('박 판정', () {
    test('피박: 이긴쪽 피점수 + 진쪽 피 7장 미만', () {
      final winner = [2, 3, 6, 7, 10, 11, 14, 15, 18, 19]; // 피10장=1점.
      final loser = [22, 23]; // 피 2장.
      expect(GoStopLogic.isPibak(winner, loser), true);
    });
    test('피박 미적용: 진쪽 피 7장 이상', () {
      final winner = [2, 3, 6, 7, 10, 11, 14, 15, 18, 19];
      final loser = [22, 23, 26, 27, 30, 31, 34]; // 피 7장.
      expect(GoStopLogic.isPibak(winner, loser), false);
    });
    test('피박 미적용: 이긴쪽 피로 점수 안 냄', () {
      final winner = [0, 8, 28]; // 광만(피점수 0).
      final loser = <int>[];
      expect(GoStopLogic.isPibak(winner, loser), false);
    });
    test('광박: 이긴쪽 광점수 + 진쪽 광 0', () {
      expect(GoStopLogic.isGwangbak([0, 8, 28], [22, 23]), true);
    });
    test('광박 미적용: 진쪽 광 보유', () {
      expect(GoStopLogic.isGwangbak([0, 8, 28], [40]), false);
    });

    test('junkCount: 국진은 쌍피(2)로 센다', () {
      // 국진(32) + 일반피 6장 = 2 + 6 = 8.
      expect(GoStopLogic.junkCount([32, 2, 3, 6, 7, 10, 11]), 8);
    });

    test('피박 오탐 방지: 진쪽 국진+일반피6 = 8피 → 7장 이상이라 피박 아님', () {
      // 이긴쪽 피 10장으로 피점수. 진쪽 = 국진(쌍피2)+일반피6 = 8피(>=7).
      final winner = [2, 3, 6, 7, 10, 11, 14, 15, 18, 19]; // 피10=1점.
      final loser = [32, 22, 23, 26, 27, 30, 31]; // 국진(2)+일반피6 = 8.
      expect(GoStopLogic.isPibak(winner, loser), false);
    });

    test('피박: 이긴쪽이 국진을 열끗으로 써도 피로 점수 냈으면 피박 성립', () {
      // 이긴쪽: 일반피 8가치 + 국진. scoreOf는 국진을 5번째 열끗(1점)으로
      // 쓰는 게 총점상 유리(국진 쌍피로 쓰면 10피=1점, 동점 → 열끗 선택)해
      // junkScore가 0으로 표시되지만, 피 가치(국진 쌍피 환산)는 10 → 피박 성립.
      final winner = [
        2, 3, 6, 7, 10, 11, 14, 15, // 일반피 8.
        32, // 국진.
        16, 20, 24, 36, // 비고도리 열끗 4장 → 국진 열끗 시 5장 1점.
      ];
      final ws = GoStopLogic.scoreOf(winner);
      expect(ws.gukjinAsJunk, false); // 열끗 배정이 채택됨.
      expect(ws.junkScore, 0); // 그래서 junkScore는 0으로 표시.
      final loser = [22, 23]; // 진쪽 피 2장(<7).
      expect(GoStopLogic.isPibak(winner, loser), true); // 그래도 피박.
    });
  });

  group('특수 플레이 - 턴 처리', () {
    test('일반 먹기: 바닥 1장과 매칭', () {
      final st = mkState(hand0: [0], floor: [2], stock: [16]);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evEat);
      expect(capA(r.state).toSet(), {0, 2});
      expect(floorOf(r.state), [16]); // 더미 16 매칭 없어 깔림.
    });

    test('뻑: 손패 쌍(2장) + 더미 같은 달 → 못 먹고 바닥에 쌓임', () {
      final st = mkState(hand0: [0], floor: [2], stock: [3], cap1: [6]);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evPpeok);
      expect(r.ppeok, true);
      expect(r.ppeokMonth, 1);
      expect(capA(r.state), isEmpty); // 아무것도 못 먹음.
      expect(floorOf(r.state).toSet(), {0, 2, 3}); // 3장 모두 바닥.
    });

    test('뻑(바닥 2장 + 손패 1장): 3장 모여 못 먹고 바닥에 쌓임', () {
      // 바닥 1월 2장(2,3) + 손패 1월 1장(0) = 3장 → 뻑. 더미 5월(16)은 무관.
      final st = mkState(hand0: [0], floor: [2, 3], stock: [16], cap1: [6]);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evPpeok);
      expect(r.ppeok, true);
      expect(r.ppeokMonth, 1);
      expect(capA(r.state), isEmpty); // 못 먹음.
      expect(capB(r.state), [6]); // 상대 피 안 뺏음.
      expect(floorOf(r.state).toSet(), {0, 2, 3, 16}); // 3장 쌓이고 16 깔림.
      expect((r.state['ppeokCount'] as Map)['a'], 1); // 뻑 카운트.
    });

    test('따닥: 손패가 한 쌍 + 더미가 다른 달 한 쌍 → 둘 다 먹고 상대 피 1장', () {
      // 손 1월(0)이 바닥 1월(2) 먹고, 더미 6월(22)이 바닥 6월(20) 먹음.
      // 바닥에 무관한 10월(38) 1장을 남겨 쓸기(바닥 비움)와 분리.
      final st = mkState(
        hand0: [0],
        floor: [2, 20, 38],
        stock: [22],
        cap1: [6],
      );
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evTtadak);
      expect(r.stoleJunk, 1);
      expect(capA(r.state).toSet().containsAll({0, 2, 22, 20}), true);
      expect(capA(r.state).contains(6), true); // 상대 피 뺏어옴.
      expect(floorOf(r.state), [38]); // 무관한 카드 남음.
      expect(capB(r.state), isEmpty);
    });

    test('자뻑: 손패로 만든 뻑(바닥 2장+손패 1장)을 같은 턴 더미 4번째로 해소', () {
      // 바닥 1월 2장(2,3) + 손패 1월 1장(0) = 뻑, 더미 1월 4번째(1)로 해소.
      // 무관한 10월(38) 1장을 남겨 쓸기와 분리.
      final st = mkState(hand0: [0], floor: [2, 3, 38], stock: [1], cap1: [6]);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evJappeok);
      expect(r.ppeok, false); // 해소되었으므로 뻑 아님.
      expect(capA(r.state).toSet().containsAll({0, 1, 2, 3}), true); // 4장 모두.
      expect(r.stoleJunk, 1); // 보너스로 상대 피 1장.
      expect(capA(r.state).contains(6), true);
      expect(floorOf(r.state), [38]); // 무관한 카드 남음.
      expect(capB(r.state), isEmpty);
      expect((r.state['ppeokCount'] as Map)['a'], 0); // 자뻑은 뻑 카운트 안 올림.
    });

    test('쪽: 바닥 매칭 없어 깔았는데 더미가 같은 달 → 둘 다 + 상대 피', () {
      final st = mkState(hand0: [0], floor: [20], stock: [2], cap1: [6]);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evJjok);
      expect(r.stoleJunk, 1);
      expect(capA(r.state).contains(0), true);
      expect(capA(r.state).contains(2), true);
      expect(floorOf(r.state), [20]); // 무관한 카드는 남음.
    });

    test('쓸기: 4장 쓸기로 바닥이 비면 상대 피 1장', () {
      // 바닥 1월 3장(1,2,3) + 손 1월 4번째(0) = 4장 쓸어 바닥 비움. 더미 없음.
      final st = mkState(hand0: [0], floor: [1, 2, 3], stock: [], cap1: [6, 7]);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evSseulgi);
      expect(floorOf(r.state), isEmpty);
      expect(r.stoleJunk, 1); // 쓸기 1장만(따닥 아님).
    });

    test('따닥+쓸기 동시: 두 쌍 먹어 바닥 비우면 상대 피 2장', () {
      // 손 1월(0)이 바닥 1월(2), 더미 5월(17)이 바닥 5월(16) 먹어 바닥 비움.
      // 서로 다른 두 쌍(따닥) + 바닥 비움(쓸기) → 둘 다 적용 = 2장.
      final st = mkState(hand0: [0], floor: [2, 16], stock: [17], cap1: [6, 7]);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evSseulgi); // 쓸기가 라벨을 덮음.
      expect(floorOf(r.state), isEmpty);
      expect(r.stoleJunk, 2); // 따닥 1 + 쓸기 1.
    });

    test('보너스패: 자동으로 내 피로, 한 장 더 뒤집기', () {
      final st = mkState(hand0: [0], floor: [2], stock: [48, 16]);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(capA(r.state).contains(48), true); // 보너스 3피 획득.
      expect(floorOf(r.state), [16]); // 보너스 다음 카드 16 깔림.
    });

    test('바닥 같은 달 3장(기존 뻑 더미) + 더미 1장 = 4장 쓸어담기(evEat)', () {
      // 손 5월(16) 깔림, 더미 1월(0)이 바닥 1월 3장(1,2,3) 전부 먹음.
      // 이것은 자뻑이 아니라 일반 4장 먹기(총통성 쓸기) → evEat, 보너스 없음.
      final st = mkState(hand0: [16], floor: [1, 2, 3], stock: [0], cap1: [6]);
      final r = GoStopLogic.playHandCard(st, 'a', 16);
      expect(r.event, GoStopLogic.evEat);
      expect(r.stoleJunk, 0); // 보너스(상대 피 뺏기) 없음.
      expect(capA(r.state).toSet(), {0, 1, 2, 3});
      expect(capB(r.state), [6]); // 상대 피 그대로.
      expect(floorOf(r.state), [16]);
    });

    test('상대 피 뺏기: 일반피 우선(쌍피 남김) — 따닥 경로', () {
      // 따닥(손 1월 0이 바닥 2 먹고, 더미 6월 22가 바닥 20 먹음)으로 1장 뺏기.
      // 무관한 10월(38)을 남겨 쓸기와 분리.
      final st = mkState(
        hand0: [0],
        floor: [2, 20, 38],
        stock: [22],
        cap1: [41, 6],
      );
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evTtadak);
      expect(capA(r.state).contains(6), true); // 일반피 6을 뺏음.
      expect(capB(r.state), [41]); // 쌍피 41은 남음.
    });

    test('상대 피 없으면 뺏기 패스 — 따닥 경로', () {
      final st = mkState(hand0: [0], floor: [2, 20, 38], stock: [22], cap1: []);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evTtadak);
      expect(capB(r.state), isEmpty); // 뺏을 게 없음.
    });

    test('손패/더미 모두 매칭 없으면 둘 다 바닥에 깔림', () {
      final st = mkState(hand0: [0], floor: [20], stock: [24]);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(r.event, GoStopLogic.evNone);
      expect(floorOf(r.state).toSet(), {20, 0, 24});
      expect(capA(r.state), isEmpty);
    });

    test('손패에 없는 카드를 내면 예외', () {
      final st = mkState(hand0: [0], floor: [2], stock: [16]);
      expect(() => GoStopLogic.playHandCard(st, 'a', 5), throwsArgumentError);
    });
  });

  group('흔들기 / 폭탄 / 총통', () {
    test('흔들기 선언: 같은 달 3장 보유 시 shaken +1', () {
      final st = mkState(hand0: [0, 1, 2, 16]); // 1월 3장.
      final s2 = GoStopLogic.declareShake(st, 'a', 1);
      expect((s2['shaken'] as Map)['a'], 1);
    });
    test('흔들기 불가: 같은 달 2장 이하', () {
      expect(GoStopLogic.canShake([0, 1, 16], 1), false);
      expect(GoStopLogic.canShake([0, 1, 2], 1), true);
    });
    test('폭탄: 손패 3장 + 바닥 1장 = 4장 먹고 추가 턴 + 상대 피 + 보충', () {
      // 손 1월 3장(0,2,3) + 잡카드(16) + 바닥 1월 1장(1). 더미에서 2장 보충.
      final st = mkState(
        hand0: [0, 2, 3, 16],
        floor: [1, 20],
        stock: [24, 36, 40],
        cap1: [6, 7, 10],
      );
      final r = GoStopLogic.playBomb(st, 'a', 1);
      expect(r.event, GoStopLogic.evBomb);
      expect((r.state['bomb'] as Map)['a'], 1);
      expect(capA(r.state).toSet().containsAll({0, 1, 2, 3}), true);
      expect(r.stoleJunk, 1);
      expect(r.extraTurn, true); // 추가 턴 신호.
      // 손패: 16(남음) + 보충 2장(24,36) = 3장. 더미는 40만 남음.
      final handA = ((r.state['hands'] as Map)['a'] as List).cast<int>();
      expect(handA.toSet(), {16, 24, 36});
      expect((r.state['stock'] as List).cast<int>(), [40]);
    });

    test('폭탄 보충 중 보너스패는 피 더미로 가고 추가로 더 뽑음', () {
      // 더미 첫 카드가 보너스(48) → 피로, 보충 2장은 24,36에서 채움.
      final st = mkState(
        hand0: [0, 2, 3, 16],
        floor: [1],
        stock: [48, 24, 36, 40],
      );
      final r = GoStopLogic.playBomb(st, 'a', 1);
      expect(capA(r.state).contains(48), true); // 보너스 3피 획득.
      final handA = ((r.state['hands'] as Map)['a'] as List).cast<int>();
      expect(handA.toSet(), {16, 24, 36}); // 보충 2장은 일반 카드.
      expect((r.state['stock'] as List).cast<int>(), [40]);
    });
    test('폭탄 불가 시 예외', () {
      final st = mkState(hand0: [0, 2, 16], floor: [1]); // 1월 2장뿐.
      expect(() => GoStopLogic.playBomb(st, 'a', 1), throwsArgumentError);
    });
    test('총통 감지: 같은 달 4장', () {
      expect(GoStopLogic.checkChongtong([0, 1, 2, 3, 16, 20]), 1);
      expect(GoStopLogic.checkChongtong([0, 1, 2, 16, 20]), isNull);
    });
  });

  group('고 / 스톱 / 나가리', () {
    test('canCallGoStop: 7점 경계', () {
      expect(GoStopLogic.canCallGoStop(6), false);
      expect(GoStopLogic.canCallGoStop(7), true);
    });
    test('declareGo: go +1, 다시 진행', () {
      final st = mkState();
      st['awaitingGoStop'] = 'a';
      st['phase'] = 'awaitingGoStop';
      final s2 = GoStopLogic.declareGo(st, 'a');
      expect((s2['go'] as Map)['a'], 1);
      expect(s2['phase'], 'playing');
      expect(s2['awaitingGoStop'], '');
    });
    test('declareStop: 종료 + 승자', () {
      final st = mkState();
      final s2 = GoStopLogic.declareStop(st, 'a');
      expect(s2['phase'], 'finished');
      expect(s2['winner'], 'a');
    });
    test('나가리: 더미+양손패 소진', () {
      expect(GoStopLogic.isNagari(mkState()), true);
      expect(GoStopLogic.isNagari(mkState(hand0: [0])), false);
      expect(GoStopLogic.isNagari(mkState(stock: [0])), false);
    });

    test('ppeokCount 누적: 뻑마다 +1', () {
      // 뻑 1회 발생.
      final st = mkState(hand0: [0], floor: [2, 3], stock: [16]);
      final r = GoStopLogic.playHandCard(st, 'a', 0);
      expect(GoStopLogic.ppeokCountOf(r.state, 'a'), 1);
      expect(GoStopLogic.ppeokCountOf(r.state, 'b'), 0);
    });

    test('3뻑 규칙: 한 사람이 뻑 3번 → 상대 즉시 승(옵션)', () {
      final st = mkState();
      (st['ppeokCount'] as Map)['a'] = 3;
      expect(GoStopLogic.checkThreePpeokWinner(st), 'b'); // a가 3뻑 → b 승.
      expect(GoStopLogic.checkThreePpeokWinner(st, enabled: false), isNull);
      (st['ppeokCount'] as Map)['a'] = 2;
      expect(GoStopLogic.checkThreePpeokWinner(st), isNull); // 2뻑은 미발동.
    });
    test('7점 도달 시 awaitingGoStop 진입', () {
      // 이미 광 4장(0,8,28,40)을 먹은 상태. 손 비광(44)을 내서 바닥 12월(45)과
      // 매칭 → 5광 완성 = 15점 → 고/스톱 대기.
      final st = mkState(
        hand0: [44],
        floor: [45],
        stock: [16],
        cap0: [0, 8, 28, 40],
      );
      final r = GoStopLogic.playHandCard(st, 'a', 44);
      expect(capA(r.state).contains(44), true); // 5번째 광 획득.
      expect(GoStopLogic.scoreOf(capA(r.state)).total, 15); // 5광.
      expect(r.canGoStop, true);
      expect(r.state['awaitingGoStop'], 'a');
      expect(r.state['phase'], 'awaitingGoStop');
    });
  });

  group('덱 / 딜 (결정적 시드)', () {
    test('newShuffledDeck: 51장, 중복 없음, 시드 결정적', () {
      final d1 = GoStopLogic.newShuffledDeck(42);
      final d2 = GoStopLogic.newShuffledDeck(42);
      final d3 = GoStopLogic.newShuffledDeck(43);
      expect(d1.length, 51);
      expect(d1.toSet().length, 51);
      expect(d1, d2); // 같은 시드 → 동일.
      expect(d1 == d3, false); // 다른 시드 → 보통 다름.
    });

    test('deal: 손패 10/10, 바닥 8, 더미 23', () {
      final deck = GoStopLogic.newShuffledDeck(7);
      final dealt = GoStopLogic.deal(deck);
      expect(dealt.hand0.length, 10);
      expect(dealt.hand1.length, 10);
      expect(dealt.floor.length, 8);
      expect(dealt.stock.length, 51 - 28);
      // 전체가 겹침 없이 51장.
      final all = {
        ...dealt.hand0,
        ...dealt.hand1,
        ...dealt.floor,
        ...dealt.stock,
      };
      expect(all.length, 51);
    });

    test('createInitialState: 스키마 + 분배', () {
      final st = GoStopLogic.createInitialState(['a', 'b'], 99);
      expect(st['phase'], 'playing');
      expect(((st['hands'] as Map)['a'] as List).length, 10);
      expect(((st['hands'] as Map)['b'] as List).length, 10);
      expect((st['floor'] as List).length, 8);
      expect((st['captured'] as Map)['a'], isEmpty);
      expect(st['nagariMult'], 1);
      // 같은 시드 → 동일 손패(결정적).
      final st2 = GoStopLogic.createInitialState(['a', 'b'], 99);
      expect((st['hands'] as Map)['a'], (st2['hands'] as Map)['a']);
    });
  });

  group('state JSON 안전성 (중첩 배열 금지)', () {
    test('playHandCard 후 state에 List 안의 List가 없다', () {
      final st = GoStopLogic.createInitialState(['a', 'b'], 5);
      final hand = ((st['hands'] as Map)['a'] as List).cast<int>();
      final r = GoStopLogic.playHandCard(st, 'a', hand.first);
      // floor/stock은 평탄 List<int>.
      expect(r.state['floor'], isA<List<int>>());
      expect(r.state['stock'], isA<List<int>>());
      // hands/captured는 Map<String, List<int>> (값은 평탄 List).
      for (final v in (r.state['hands'] as Map).values) {
        expect(v, isA<List<int>>());
      }
      for (final v in (r.state['captured'] as Map).values) {
        expect(v, isA<List<int>>());
      }
      // lastMove도 평탄(스펙 §B/§L "lastMove 평탄"): 모든 값은 스칼라 또는
      // List<int> — List 안의 List 금지. 새 안무 메타가 가장 회귀 위험이 큰 면이라
      // 명시적으로 가드한다.
      expectFlatLastMove(r.state['lastMove']);
    });

    test('playBomb 후 lastMove도 평탄(List 안의 List 없음)', () {
      // 손 1월 3장(0,2,3) + 잡카드(16) + 바닥 1월 1장(1), 더미 보충 2장.
      // (기존 폭탄 테스트와 동일 구성.)
      final st = mkState(
        hand0: [0, 2, 3, 16],
        floor: [1, 20],
        stock: [24, 36, 40],
        cap1: [6, 7, 10],
      );
      final r = GoStopLogic.playBomb(st, 'a', 1);
      // lastMove의 모든 값이 평탄(스칼라 또는 List<int>).
      expectFlatLastMove(r.state['lastMove']);
      // bombCards / replenished 가 평탄 List<int> 임을 명시 확인.
      final lm = r.state['lastMove'] as Map;
      expect(lm['bombCards'], isA<List<int>>());
      expect(lm['replenished'], isA<List<int>>());
    });
  });
}

/// lastMove 맵의 모든 값이 평탄(스칼라 int/String 또는 `List<int>`)인지 단언한다.
/// 스펙 §L "lastMove 평탄" 불변 가드: List 안의 List 회귀 방지.
void expectFlatLastMove(dynamic lastMove) {
  expect(lastMove, isA<Map>());
  final lm = lastMove as Map;
  lm.forEach((key, value) {
    if (value is List) {
      // List 값은 반드시 평탄(요소가 다시 List이면 안 됨) — List<int> 형태.
      expect(
        value,
        isA<List<int>>(),
        reason: 'lastMove["$key"]는 평탄 List<int>여야 함(List 안의 List 금지)',
      );
    } else {
      // 스칼라(int/String)만 허용.
      expect(
        value is int || value is String,
        isTrue,
        reason: 'lastMove["$key"]는 스칼라(int/String)여야 함 (실제: $value)',
      );
    }
  });
}
