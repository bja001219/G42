import 'dart:math';

import 'gostop_cards.dart';

/// 고스톱(2인 맞고) 순수 룰/점수 엔진 (UI / Firestore 의존 없음).
///
/// 기준: `docs/GOSTOP_RULES.md`. 카드 인코딩: `gostop_cards.dart`.
///
/// ## state 스키마 (JSON 안전, 중첩 배열 금지)
/// `Map<String, dynamic>`:
/// - `phase`        : `String`. 'playing' | 'awaitingGoStop' | 'finished' | 'chongtong'.
/// - `floor`        : `List<int>`. 바닥에 깔린 카드 id들 (평탄).
/// - `stock`        : `List<int>`. 더미(뒤집어 뽑는) 카드 id들 (평탄).
/// - `hands`        : `Map<String, List<int>>`. 플레이어별 손패.
/// - `captured`     : `Map<String, List<int>>`. 플레이어별 먹은 패(분류 안 함, 평탄).
/// - `scores`       : `Map<String, int>`. 플레이어별 통산(이 판 누적 반영용; 엔진은 갱신 안 함).
/// - `go`           : `Map<String, int>`. 플레이어별 이 판 고 외친 횟수.
/// - `shaken`       : `Map<String, int>`. 플레이어별 흔들기 횟수.
/// - `bomb`         : `Map<String, int>`. 플레이어별 폭탄 횟수.
/// - `ppeokCount`   : `Map<String, int>`. 플레이어별 이 판 뻑 횟수(3뻑 = 상대 즉시 승 판정용).
/// - `nagariMult`   : int. 나가리 누적 배수(기본 1).
/// - `firstTurn`    : bool. 아직 첫 턴(첫뻑 판정용)인가.
/// - `awaitingGoStop`: String. 고/스톱 판정 대기 중인 playerId('' = 없음).
/// - `lastEvent`    : `String`. 직전 턴 이벤트 코드(아래 `ev*` 상수).
///
/// `Map<String, List<int>>` (playerId 키)는 허용. 금지는 List 안의 List.
abstract class GoStopLogic {
  /// 손패 장수 (2인).
  static const int handSize = 10;

  /// 딜 직후 바닥 장수.
  static const int floorSize = 8;

  /// 고/스톱 가능 최소 점수.
  static const int goStopThreshold = 7;

  /// 피박 기준: 진 사람의 피가 이 장수 미만이면 피박.
  static const int pibakThreshold = 7;

  // ---- 이벤트 코드 ---------------------------------------------------------

  /// 턴/액션 결과 이벤트 코드.
  static const String evNone = 'none';
  static const String evEat = 'eat'; // 일반 먹기.
  static const String evPpeok = 'ppeok'; // 뻑(같은 달 3장 쌓여 못 먹음).
  static const String evJappeok = 'jappeok'; // 자뻑(같은 턴 본인 해소).
  static const String evTtadak = 'ttadak'; // 따닥.
  static const String evJjok = 'jjok'; // 쪽.
  static const String evSseulgi = 'sseulgi'; // 쓸기(바닥 비움).
  static const String evBonus = 'bonus'; // 보너스패 처리.
  static const String evBomb = 'bomb'; // 폭탄.
  static const String evChongtong = 'chongtong'; // 총통.

  // =========================================================================
  // 덱 / 딜
  // =========================================================================

  /// [seed]로 결정적 셔플한 51장 덱.
  static List<int> newShuffledDeck(int seed) {
    final deck = List<int>.generate(GoStopCards.totalCount, (i) => i);
    deck.shuffle(Random(seed));
    return deck;
  }

  /// 덱을 분배한다. (각자 손패 10장, 바닥 8장, 나머지 더미.)
  ///
  /// 분배 순서(단순): hand0 10장 → hand1 10장 → floor 8장 → 나머지 stock.
  /// 반환 Map: `{hands: List<List<int>>... }` 가 아니라 평탄 분리:
  /// `{hand0, hand1, floor, stock}`.
  static DealResult deal(List<int> deck) {
    final d = List<int>.from(deck);
    final hand0 = d.sublist(0, handSize);
    final hand1 = d.sublist(handSize, handSize * 2);
    final floor = d.sublist(handSize * 2, handSize * 2 + floorSize);
    final stock = d.sublist(handSize * 2 + floorSize);
    return DealResult(hand0: hand0, hand1: hand1, floor: floor, stock: stock);
  }

  /// 초기 state 생성. [playerIds]는 [host, guest].
  static Map<String, dynamic> createInitialState(
    List<String> playerIds,
    int seed,
  ) {
    final deck = newShuffledDeck(seed);
    final dealt = deal(deck);
    final p0 = playerIds[0];
    final p1 = playerIds[1];
    return <String, dynamic>{
      'phase': 'playing',
      'floor': dealt.floor,
      'stock': dealt.stock,
      'hands': <String, dynamic>{p0: dealt.hand0, p1: dealt.hand1},
      'captured': <String, dynamic>{p0: <int>[], p1: <int>[]},
      'scores': <String, dynamic>{p0: 0, p1: 0},
      'go': <String, dynamic>{p0: 0, p1: 0},
      'shaken': <String, dynamic>{p0: 0, p1: 0},
      'bomb': <String, dynamic>{p0: 0, p1: 0},
      'ppeokCount': <String, dynamic>{p0: 0, p1: 0},
      'nagariMult': 1,
      'firstTurn': true,
      'awaitingGoStop': '',
      'lastEvent': evNone,
    };
  }

  // =========================================================================
  // 점수 계산
  // =========================================================================

  /// 먹은 패 [captured]의 점수 분해 + 합계.
  ///
  /// 국진(32)은 열끗/쌍피 중 점수 최대가 되도록 자동 선택한다.
  static GoStopScore scoreOf(List<int> captured) {
    final hasGukjin = captured.contains(GoStopCards.gukjinId);

    // 국진을 열끗으로 쓰는 경우 / 쌍피로 쓰는 경우 둘 다 평가 후 최대 선택.
    if (hasGukjin) {
      final asAnimal = _scoreWith(captured, gukjinAsJunk: false);
      final asJunk = _scoreWith(captured, gukjinAsJunk: true);
      return asAnimal.total >= asJunk.total ? asAnimal : asJunk;
    }
    return _scoreWith(captured, gukjinAsJunk: false);
  }

  static GoStopScore _scoreWith(
    List<int> captured, {
    required bool gukjinAsJunk,
  }) {
    // ---- 광 ----
    final gwang = captured.where(GoStopCards.isGwang).toList();
    final gwangCount = gwang.length;
    final hasBi = gwang.contains(GoStopCards.gwangBiId);
    var gwangScore = 0;
    if (gwangCount >= 5) {
      gwangScore = 15;
    } else if (gwangCount == 4) {
      gwangScore = 4;
    } else if (gwangCount == 3) {
      gwangScore = hasBi ? 2 : 3;
    }

    // ---- 띠 ----
    final ribbons = captured.where(GoStopCards.isRibbon).toList();
    final ribbonCount = ribbons.length;
    var ribbonScore = ribbonCount >= 5 ? 1 + (ribbonCount - 5) : 0;
    // 홍/청/초단 세트 (비띠는 제외).
    final hasHong = GoStopCards.hongdanIds.every(captured.contains);
    final hasCheong = GoStopCards.cheongdanIds.every(captured.contains);
    final hasCho = GoStopCards.chodanIds.every(captured.contains);
    var ribbonSetScore = 0;
    if (hasHong) ribbonSetScore += 3;
    if (hasCheong) ribbonSetScore += 3;
    if (hasCho) ribbonSetScore += 3;
    ribbonScore += ribbonSetScore;

    // ---- 열끗(동물) ----
    final animals = captured.where(GoStopCards.isAnimal).toList();
    // 국진을 쌍피로 쓰면 열끗에서 제외.
    final animalCount = gukjinAsJunk
        ? animals.where((id) => id != GoStopCards.gukjinId).length
        : animals.length;
    var animalScore = animalCount >= 5 ? 1 + (animalCount - 5) : 0;
    // 고도리.
    final hasGodori = GoStopCards.godoriIds.every(captured.contains);
    if (hasGodori) animalScore += 5;

    // ---- 피 ----
    var junkValue = 0;
    for (final id in captured) {
      if (GoStopCards.isGukjin(id)) {
        if (gukjinAsJunk) junkValue += 2; // 국진 쌍피.
        continue;
      }
      junkValue += GoStopCards.junkValue(id);
    }
    final junkScore = junkValue >= 10 ? 1 + (junkValue - 10) : 0;

    final total = gwangScore + ribbonScore + animalScore + junkScore;

    return GoStopScore(
      gwangCount: gwangCount,
      gwangScore: gwangScore,
      ribbonCount: ribbonCount,
      ribbonScore: ribbonScore,
      hasHong: hasHong,
      hasCheong: hasCheong,
      hasCho: hasCho,
      animalCount: animalCount,
      animalScore: animalScore,
      hasGodori: hasGodori,
      junkValue: junkValue,
      junkScore: junkScore,
      gukjinAsJunk: gukjinAsJunk,
      total: total,
    );
  }

  /// 최종 점수 (배수 적용). 사양서 8장 순서:
  /// `(base + min(go,2)) × 2^max(0, go-2)` → 흔들기×2^shaken → 폭탄×2^bomb
  /// → 나가리×nagariMult → 피박×2 → 광박×2 → 고박×2.
  static int finalizeScore(
    int base, {
    int goCount = 0,
    int shakenCount = 0,
    int bombCount = 0,
    int nagariMult = 1,
    bool pibak = false,
    bool gwangbak = false,
    bool gobak = false,
  }) {
    final goBonus = goCount < 2 ? goCount : 2;
    final goMult = _pow2(goCount > 2 ? goCount - 2 : 0);
    var score = (base + goBonus) * goMult;
    score *= _pow2(shakenCount);
    score *= _pow2(bombCount);
    score *= nagariMult;
    if (pibak) score *= 2;
    if (gwangbak) score *= 2;
    if (gobak) score *= 2;
    return score;
  }

  /// 2^[n] (정수). n<0이면 1.
  static int _pow2(int n) {
    if (n <= 0) return 1;
    var v = 1;
    for (var i = 0; i < n; i++) {
      v *= 2;
    }
    return v;
  }

  // =========================================================================
  // 박 판정
  // =========================================================================

  /// 피박: 이긴 사람이 피로 점수를 냈는데 진 사람의 피가 7장 미만.
  ///
  /// 박 판정은 [scoreOf]의 "총점 최대" 배정과 분리한다(사양서 6장, 3.4):
  /// - 이긴 사람이 "피로 점수를 냈는가"는 국진을 어느 쪽으로 써도 피 점수가
  ///   나는지(winner의 피 가치가 10 이상) 기준으로 본다.
  /// - 진 사람의 피 장수는 국진을 쌍피(2장)로 세어(=피 더미에 있는 가치)
  ///   [junkCount]로 계산한다.
  static bool isPibak(List<int> winnerCaptured, List<int> loserCaptured) {
    if (!_scoredWithJunk(winnerCaptured)) return false; // 피로 점수를 내지 않았으면 미적용.
    return junkCount(loserCaptured) < pibakThreshold;
  }

  /// 광박: 이긴 사람이 광으로 점수를 냈는데 진 사람의 광이 0장.
  static bool isGwangbak(List<int> winnerCaptured, List<int> loserCaptured) {
    final ws = scoreOf(winnerCaptured);
    if (ws.gwangScore <= 0) return false;
    return loserCaptured.where(GoStopCards.isGwang).isEmpty;
  }

  /// 이긴 사람이 "피로 점수를 냈는지"를 [scoreOf]의 총점 최대 배정과 무관하게
  /// 판정한다. 국진을 쌍피로 쓰면 피 점수가 나는데, 열끗 배정이 총점상 유리해
  /// junkScore가 0으로 표시되는 경우에도 피박은 성립해야 한다(사양서 6장).
  /// 따라서 국진을 쌍피로 센 피 가치가 10 이상이면 피로 점수를 낸 것으로 본다.
  static bool _scoredWithJunk(List<int> captured) {
    var junkValue = 0;
    for (final id in captured) {
      if (GoStopCards.isGukjin(id)) {
        junkValue += 2; // 박 판정에서 국진은 쌍피로 센다.
        continue;
      }
      junkValue += GoStopCards.junkValue(id);
    }
    return junkValue >= 10;
  }

  /// 먹은 패의 피 장수 합(쌍피=2, 3피=3, 국진은 쌍피=2로 셈).
  /// 박 판정·표시용. 국진은 피 더미에 들어가 있는 쪽(쌍피)으로 세어
  /// 진 사람이 실제로 쥔 피 장수를 반영한다(사양서 3.4·6장).
  static int junkCount(List<int> captured) {
    var junkValue = 0;
    for (final id in captured) {
      if (GoStopCards.isGukjin(id)) {
        junkValue += 2; // 국진 쌍피.
        continue;
      }
      junkValue += GoStopCards.junkValue(id);
    }
    return junkValue;
  }

  // =========================================================================
  // 턴 처리 (핵심)
  // =========================================================================

  /// 플레이어 [pid]가 손패 카드 [handCardId]를 내는 한 턴 처리.
  ///
  /// 순서: 손패 1장 내기 → 바닥 같은 달 매칭(2장이면 [floorTargetId]로 선택,
  /// 3장이면 4장 모두) → 더미 1장 뒤집기 → 매칭 → captured 적립.
  /// 보너스패는 즉시 captured로 가고 한 장 더 뽑는다(반복).
  ///
  /// 반환: 새 state(Map) + 이벤트([PlayResult]).
  static PlayResult playHandCard(
    Map<String, dynamic> state,
    String pid,
    int handCardId, {
    int? floorTargetId,
  }) {
    final s = _clone(state);
    final hand = _intList(_hands(s)[pid]);
    final floor = _intList(s['floor']);
    final stock = _intList(s['stock']);
    final captured = _intList(_captured(s)[pid]);
    final opponent = _opponentOf(s, pid);
    final opCaptured = _intList(_captured(s)[opponent]);

    if (!hand.contains(handCardId)) {
      throw ArgumentError('손패에 없는 카드: $handCardId (pid=$pid)');
    }

    var event = evNone;
    var stealCount = 0; // 상대 피 뺏을 장수.
    var ppeokThisTurn = false;
    var ppeokMonth = -1;

    hand.remove(handCardId);
    final playedMonth = GoStopCards.monthOf(handCardId);

    // ---- 1단계: 손패 카드 매칭 (잠정) ----
    final handMatches = floor
        .where((c) => GoStopCards.monthOf(c) == playedMonth)
        .toList();

    // 손패 카드가 먹은(잠정) 카드들 — 뻑 발생 시 되돌리기 위해 추적.
    final handTaken = <int>[];
    var handPlacedOnFloor = false;
    // 손패가 바닥 1장과 매칭해 쌍 1개를 먹었는가(따닥 판정용).
    var handAteSinglePair = false;
    // 손패로 바닥 2장 위에 1장을 더해 뻑(바닥 3장)을 만들었는가(자뻑 판정용).
    var handMadePpeokFromFloor2 = false;

    if (handMatches.length >= 3) {
      // 같은 달 3장 이상 + 낸 1장 = 4장 모두 가져옴(총통성/4장 먹기).
      handTaken.add(handCardId);
      for (final m in handMatches) {
        floor.remove(m);
        handTaken.add(m);
      }
      event = evEat;
    } else if (handMatches.length == 2) {
      // 바닥 2장 + 손패 1장 = 3장 → 뻑(못 먹고 그대로 쌓임). 사양서 2.3/4.1.
      // 손패 카드를 바닥에 올려 3장이 쌓인 상태로 둔다. (같은 턴 더미가 4번째
      // 카드면 자뻑으로 4장 모두 가져간다 — 아래 더미 단계에서 처리.)
      floor.add(handCardId);
      handMadePpeokFromFloor2 = true;
      event = evPpeok;
      ppeokThisTurn = true;
      ppeokMonth = playedMonth;
    } else if (handMatches.length == 1) {
      // 바닥에 같은 달 1장 → 잠정으로 쌍을 먹는다. (더미 뒤집기로 같은 달이
      // 또 나오면 뻑으로 되돌린다.)
      final target = handMatches.first;
      floor.remove(target);
      handTaken.add(handCardId);
      handTaken.add(target);
      handAteSinglePair = true;
      event = evEat;
    } else {
      // 바닥에 같은 달 없음 → 손패 카드를 바닥에 놓는다. (쪽 가능성.)
      floor.add(handCardId);
      handPlacedOnFloor = true;
    }

    // ---- 2단계: 더미 1장 뒤집기 (보너스 자동 처리 포함) ----
    int? flipped;
    var sawBonus = false;
    while (stock.isNotEmpty) {
      final top = stock.removeAt(0);
      if (GoStopCards.isBonus(top)) {
        // 보너스패: 즉시 내 피 더미로, 한 장 더 뽑는다.
        captured.add(top);
        sawBonus = true;
        continue;
      }
      flipped = top;
      break;
    }

    if (flipped != null) {
      final flipMonth = GoStopCards.monthOf(flipped);
      final flipMatches = floor
          .where((c) => GoStopCards.monthOf(c) == flipMonth)
          .toList();

      if (handMadePpeokFromFloor2 && flipMonth == playedMonth) {
        // 자뻑: 이번 턴 손패로 만든 뻑(바닥 3장)을 같은 턴 더미 카드(4번째)로
        // 본인이 해소 → 그 달 4장 모두 가져감 + 보너스(상대 피 1장).
        // floor에는 이미 3장(바닥 2장 + 방금 올린 손패 1장)이 있고 flipped가 4번째.
        for (final m in flipMatches) {
          floor.remove(m);
          captured.add(m);
        }
        captured.add(flipped);
        event = evJappeok;
        ppeokThisTurn = false; // 해소되었으므로 뻑 카운트는 올리지 않는다.
        ppeokMonth = -1;
        stealCount += 1;
      } else if (handMatches.length == 1 && flipMonth == playedMonth) {
        // 뻑: 손패로 잠정 먹은 쌍(2장) + 더미 같은 달 1장 = 3장 → 못 먹고 쌓임.
        // 손패가 먹었던 2장을 바닥으로 되돌리고, 뒤집은 카드도 바닥에 쌓는다.
        floor.addAll(handTaken);
        handTaken.clear();
        floor.add(flipped);
        event = evPpeok;
        ppeokThisTurn = true;
        ppeokMonth = flipMonth;
        handAteSinglePair = false; // 먹기 무효 → 따닥 아님.
      } else if (handPlacedOnFloor && flipMonth == playedMonth) {
        // 쪽: 바닥에 깔아둔 손패 카드 + 더미가 같은 달 → 둘 다 가져감.
        // (이때 floor에는 방금 깔린 손패 카드가 있으므로 flipMatches에 포함됨.)
        floor.remove(handCardId);
        captured.add(handCardId);
        captured.add(flipped);
        handPlacedOnFloor = false;
        event = evJjok;
        stealCount += 1;
      } else if (flipMatches.length == 3) {
        // 바닥 같은 달 3장(기존 뻑 더미 등) + 뒤집은 1장 = 4장 모두 가져감.
        // (총통성 쓸기. 자뻑이 아니므로 보너스 없음 — 자뻑은 위에서 선처리.)
        captured.add(flipped);
        for (final m in flipMatches) {
          floor.remove(m);
          captured.add(m);
        }
        if (event == evNone || event == evEat) event = evEat;
      } else if (flipMatches.length == 2) {
        // 더미가 2장과 매칭: 1장 골라 먹고 1장 남김.
        final pick =
            floorTargetId != null && flipMatches.contains(floorTargetId)
            ? floorTargetId
            : flipMatches.first;
        floor.remove(pick);
        captured.add(flipped);
        captured.add(pick);
        // 따닥: 손패가 한 쌍을 먹고, 더미가 (다른 달) 한 쌍을 또 먹음.
        if (handAteSinglePair && flipMonth != playedMonth) {
          event = evTtadak;
          stealCount += 1;
        } else if (event == evNone) {
          event = evEat;
        }
      } else if (flipMatches.length == 1) {
        final target = flipMatches.first;
        floor.remove(target);
        captured.add(flipped);
        captured.add(target);
        // 따닥: 손패가 한 쌍을 먹고, 더미가 (다른 달) 한 쌍을 또 먹음.
        if (handAteSinglePair && flipMonth != playedMonth) {
          event = evTtadak;
          stealCount += 1;
        } else if (event == evNone) {
          event = evEat;
        }
      } else {
        // 더미 카드도 매칭 없음 → 바닥에 놓는다.
        floor.add(flipped);
      }
    }

    // 손패로 잠정 먹은 카드 확정 적립(뻑이면 handTaken은 비어 있음).
    captured.addAll(handTaken);

    if (event == evNone && sawBonus) event = evBonus;

    // ---- 뻑 횟수 누적 (3뻑 = 상대 즉시 승 판정용) ----
    if (ppeokThisTurn) {
      final ppeokCount = _intMap(s['ppeokCount']);
      ppeokCount[pid] = (ppeokCount[pid] ?? 0) + 1;
      s['ppeokCount'] = ppeokCount;
    }

    // ---- 3단계: 쓸기(싹쓸이) 판정 ----
    if (floor.isEmpty &&
        (event == evEat ||
            event == evJjok ||
            event == evTtadak ||
            event == evJappeok)) {
      event = evSseulgi;
      stealCount += 1;
    }

    // ---- 4단계: 상대 피 뺏기 ----
    for (var i = 0; i < stealCount; i++) {
      final stolen = _stealJunk(opCaptured);
      if (stolen == null) break;
      captured.add(stolen);
    }

    // ---- state 반영 ----
    _hands(s)[pid] = hand;
    s['floor'] = floor;
    s['stock'] = stock;
    _captured(s)[pid] = captured;
    _captured(s)[opponent] = opCaptured;
    s['lastEvent'] = event;
    s['firstTurn'] = false;

    // ---- 고/스톱 판정 대기 ----
    final myScore = scoreOf(captured);
    final goCount = _intMap(s['go'])[pid] ?? 0;
    final canGoStop = myScore.total >= goStopThreshold;
    if (canGoStop) {
      s['awaitingGoStop'] = pid;
      s['phase'] = 'awaitingGoStop';
    }

    return PlayResult(
      state: s,
      event: event,
      stoleJunk: stealCount,
      ppeok: ppeokThisTurn,
      ppeokMonth: ppeokMonth,
      score: myScore.total,
      canGoStop: canGoStop,
      currentGo: goCount,
      extraTurn: false,
    );
  }

  /// 상대 피 더미에서 1장 가져오기(쌍피보다 일반 피 우선). 없으면 null.
  /// [opCaptured]에서 제거하고 그 id를 반환.
  static int? _stealJunk(List<int> opCaptured) {
    // 일반 피(junkValue==1) 우선.
    for (final id in opCaptured) {
      if (GoStopCards.isJunk(id) && GoStopCards.junkValue(id) == 1) {
        opCaptured.remove(id);
        return id;
      }
    }
    // 없으면 쌍피/3피라도(국진 제외 — 국진은 열끗 가치 가능성).
    for (final id in opCaptured) {
      if (GoStopCards.isJunk(id)) {
        opCaptured.remove(id);
        return id;
      }
    }
    return null;
  }

  // =========================================================================
  // 흔들기 / 폭탄 / 총통
  // =========================================================================

  /// 흔들기 선언: 손패에 같은 달 3장이 있는 [month]를 처음 낼 때.
  /// 가능하면 shaken 카운트 +1 한 새 state 반환, 아니면 원본 그대로.
  static Map<String, dynamic> declareShake(
    Map<String, dynamic> state,
    String pid,
    int month,
  ) {
    final s = _clone(state);
    final hand = _intList(_hands(s)[pid]);
    final sameMonth = hand.where((c) => GoStopCards.monthOf(c) == month).length;
    if (sameMonth >= 3) {
      final shaken = _intMap(s['shaken']);
      shaken[pid] = (shaken[pid] ?? 0) + 1;
      s['shaken'] = shaken;
    }
    return s;
  }

  /// 흔들기 가능 여부: 손패에 같은 달 3장.
  static bool canShake(List<int> hand, int month) =>
      hand.where((c) => GoStopCards.monthOf(c) == month).length >= 3;

  /// 폭탄: 손패의 같은 달 3장을 바닥의 같은 달 1장에 몰아 내기 → 4장 먹고
  /// **추가 턴**(`PlayResult.extraTurn == true`) + 상대 피 1장.
  /// ([month]의 카드 3장이 손패에, 1장이 바닥에 있어야 함.)
  ///
  /// 폭탄은 한 턴에 손패 3장을 소모하므로(일반 턴은 1장), 정상 진행 대비 더
  /// 소모한 2장을 더미에서 보충한다(사양서 4.2 "손이 비는 만큼 더미에서 보충").
  /// 보충 중 보너스패가 나오면 즉시 captured로 가고 한 장 더 뽑는다.
  static PlayResult playBomb(
    Map<String, dynamic> state,
    String pid,
    int month,
  ) {
    final s = _clone(state);
    final hand = _intList(_hands(s)[pid]);
    final floor = _intList(s['floor']);
    final stock = _intList(s['stock']);
    final captured = _intList(_captured(s)[pid]);
    final opponent = _opponentOf(s, pid);
    final opCaptured = _intList(_captured(s)[opponent]);

    final handSame = hand
        .where((c) => GoStopCards.monthOf(c) == month)
        .toList();
    final floorSame = floor
        .where((c) => GoStopCards.monthOf(c) == month)
        .toList();
    if (handSame.length < 3 || floorSame.isEmpty) {
      throw ArgumentError(
        '폭탄 불가: 손패 ${handSame.length}장 / 바닥 ${floorSame.length}장',
      );
    }

    // 손패 3장 + 바닥 1장 = 4장 먹기.
    for (final c in handSame.take(3)) {
      hand.remove(c);
      captured.add(c);
    }
    final fTarget = floorSame.first;
    floor.remove(fTarget);
    captured.add(fTarget);

    // 손패 보충: 일반 턴(1장 소모) 대비 더 쓴 2장을 더미에서 채운다.
    var replenish = 2;
    while (replenish > 0 && stock.isNotEmpty) {
      final top = stock.removeAt(0);
      if (GoStopCards.isBonus(top)) {
        captured.add(top); // 보너스패는 손패가 아니라 피 더미로.
        continue; // 보충 카운트는 그대로(보너스는 손패 보충에 안 셈).
      }
      hand.add(top);
      replenish -= 1;
    }

    // 폭탄 카운트 + 상대 피 1장.
    final bomb = _intMap(s['bomb']);
    bomb[pid] = (bomb[pid] ?? 0) + 1;
    s['bomb'] = bomb;
    final stolen = _stealJunk(opCaptured);
    if (stolen != null) captured.add(stolen);

    _hands(s)[pid] = hand;
    s['floor'] = floor;
    s['stock'] = stock;
    _captured(s)[pid] = captured;
    _captured(s)[opponent] = opCaptured;
    s['lastEvent'] = evBomb;
    s['firstTurn'] = false;

    final myScore = scoreOf(captured);
    final canGoStop = myScore.total >= goStopThreshold;
    if (canGoStop) {
      s['awaitingGoStop'] = pid;
      s['phase'] = 'awaitingGoStop';
    }

    return PlayResult(
      state: s,
      event: evBomb,
      stoleJunk: stolen != null ? 1 : 0,
      ppeok: false,
      ppeokMonth: -1,
      score: myScore.total,
      canGoStop: canGoStop,
      currentGo: _intMap(s['go'])[pid] ?? 0,
      extraTurn: true,
    );
  }

  /// 총통 감지: 손패에 같은 달 4장이 있으면 그 달, 없으면 null.
  static int? checkChongtong(List<int> hand) {
    final counts = <int, int>{};
    for (final c in hand) {
      final m = GoStopCards.monthOf(c);
      if (m == 0) continue; // 보너스패 제외.
      counts[m] = (counts[m] ?? 0) + 1;
    }
    for (final entry in counts.entries) {
      if (entry.value >= 4) return entry.key;
    }
    return null;
  }

  // =========================================================================
  // 고 / 스톱 / 나가리
  // =========================================================================

  /// 고/스톱 가능 여부 (점수 7 이상).
  static bool canCallGoStop(int score) => score >= goStopThreshold;

  /// 고 선언: go 카운트 +1, 다시 진행(phase='playing').
  static Map<String, dynamic> declareGo(
    Map<String, dynamic> state,
    String pid,
  ) {
    final s = _clone(state);
    final go = _intMap(s['go']);
    go[pid] = (go[pid] ?? 0) + 1;
    s['go'] = go;
    s['awaitingGoStop'] = '';
    s['phase'] = 'playing';
    return s;
  }

  /// 스톱 선언: 판 종료(phase='finished'), 승자 지정.
  static Map<String, dynamic> declareStop(
    Map<String, dynamic> state,
    String pid,
  ) {
    final s = _clone(state);
    s['awaitingGoStop'] = '';
    s['phase'] = 'finished';
    s['winner'] = pid;
    return s;
  }

  /// 나가리: 더미 + 양쪽 손패 모두 소진, 아무도 스톱 못함.
  static bool isNagari(Map<String, dynamic> state) {
    if (state['phase'] == 'finished') return false;
    final stock = _intList(state['stock']);
    if (stock.isNotEmpty) return false;
    final hands = _hands(state);
    for (final h in hands.values) {
      if (_intList(h).isNotEmpty) return false;
    }
    return true;
  }

  /// 플레이어 [pid]가 이 판에 만든 뻑 횟수.
  static int ppeokCountOf(Map<String, dynamic> state, String pid) =>
      _intMap(state['ppeokCount'])[pid] ?? 0;

  /// 3뻑 규칙(옵션): 한 사람이 한 판에 뻑 3번을 만들면 **상대 즉시 승**.
  /// [enabled]가 false면 항상 null. 3뻑을 만든 사람이 있으면 그 상대 playerId
  /// 를(=승자) 반환, 없으면 null. (사양서 4.1 연뻑/3뻑, G42 표준·옵션화.)
  static String? checkThreePpeokWinner(
    Map<String, dynamic> state, {
    bool enabled = true,
  }) {
    if (!enabled) return null;
    final ppeokCount = _intMap(state['ppeokCount']);
    for (final entry in ppeokCount.entries) {
      if (entry.value >= 3) {
        return _opponentOf(state, entry.key);
      }
    }
    return null;
  }

  // =========================================================================
  // 내부 헬퍼
  // =========================================================================

  static Map<String, dynamic> _clone(Map<String, dynamic> state) {
    return <String, dynamic>{
      'phase': state['phase'],
      'floor': _intList(state['floor']),
      'stock': _intList(state['stock']),
      'hands': _cloneIntListMap(state['hands']),
      'captured': _cloneIntListMap(state['captured']),
      'scores': _intMap(state['scores']),
      'go': _intMap(state['go']),
      'shaken': _intMap(state['shaken']),
      'bomb': _intMap(state['bomb']),
      'ppeokCount': _intMap(state['ppeokCount']),
      'nagariMult': state['nagariMult'] ?? 1,
      'firstTurn': state['firstTurn'] ?? false,
      'awaitingGoStop': state['awaitingGoStop'] ?? '',
      'lastEvent': state['lastEvent'] ?? evNone,
      if (state.containsKey('winner')) 'winner': state['winner'],
    };
  }

  static Map<String, List<int>> _hands(Map<String, dynamic> s) =>
      s['hands'] as Map<String, List<int>>;

  static Map<String, List<int>> _captured(Map<String, dynamic> s) =>
      s['captured'] as Map<String, List<int>>;

  static Map<String, List<int>> _cloneIntListMap(dynamic raw) {
    final out = <String, List<int>>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        out['$k'] = _intList(v);
      });
    }
    return out;
  }

  static Map<String, int> _intMap(dynamic raw) {
    final out = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        out['$k'] = (v as num).toInt();
      });
    }
    return out;
  }

  static List<int> _intList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => (e as num).toInt()).toList();
    }
    return <int>[];
  }

  static String _opponentOf(Map<String, dynamic> s, String pid) {
    final keys = _hands(s).keys.toList();
    return keys.firstWhere((k) => k != pid, orElse: () => pid);
  }
}

/// [GoStopLogic.deal] 결과.
class DealResult {
  final List<int> hand0;
  final List<int> hand1;
  final List<int> floor;
  final List<int> stock;

  const DealResult({
    required this.hand0,
    required this.hand1,
    required this.floor,
    required this.stock,
  });
}

/// 점수 분해 결과.
class GoStopScore {
  final int gwangCount;
  final int gwangScore;
  final int ribbonCount;
  final int ribbonScore;
  final bool hasHong;
  final bool hasCheong;
  final bool hasCho;
  final int animalCount;
  final int animalScore;
  final bool hasGodori;
  final int junkValue;
  final int junkScore;
  final bool gukjinAsJunk;
  final int total;

  const GoStopScore({
    required this.gwangCount,
    required this.gwangScore,
    required this.ribbonCount,
    required this.ribbonScore,
    required this.hasHong,
    required this.hasCheong,
    required this.hasCho,
    required this.animalCount,
    required this.animalScore,
    required this.hasGodori,
    required this.junkValue,
    required this.junkScore,
    required this.gukjinAsJunk,
    required this.total,
  });
}

/// 턴/액션 처리 결과.
class PlayResult {
  final Map<String, dynamic> state;
  final String event;
  final int stoleJunk;
  final bool ppeok;
  final int ppeokMonth;
  final int score;
  final bool canGoStop;
  final int currentGo;

  /// 같은 플레이어가 추가 턴을 한 번 더 진행해야 하는가(폭탄). 호출자(턴 전환)가
  /// 이 신호를 보고 차례를 넘기지 않고 같은 플레이어에게 한 턴을 더 준다.
  final bool extraTurn;

  const PlayResult({
    required this.state,
    required this.event,
    required this.stoleJunk,
    required this.ppeok,
    required this.ppeokMonth,
    required this.score,
    required this.canGoStop,
    required this.currentGo,
    this.extraTurn = false,
  });
}
