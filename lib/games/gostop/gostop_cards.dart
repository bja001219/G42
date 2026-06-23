/// 고스톱(맞고) 화투 카드 정적 데이터 (UI / Firestore 의존 없음).
///
/// ## 카드 인코딩
/// - id 0..47 = 화투 48장, id 48..50 = 보너스패 3장.
/// - 월(month) = id ~/ 4 + 1 (id 0..47 한정). 각 월 4장이 연속 id.
/// - 타입: gwang(광) / animal(열끗) / ribbon(띠) / junk(피) / bonus(보너스).
///
/// ## 합계 검증 (코드에서 성립)
/// - 광 5 + 열끗 9 + 띠 10 + 피 24 = 48, + 보너스 3 = 51.
library;

/// 화투 카드 타입.
enum HwatuType { gwang, animal, ribbon, junk, bonus }

/// 띠(단)의 색. 홍/청/초단 세트 판정 및 비띠 구분.
enum RibbonColor { hong, cheong, cho, bi, none }

/// 한 장의 화투 카드 정적 데이터.
class HwatuCard {
  /// 카드 id (0..50).
  final int id;

  /// 월 (1..12). 보너스패는 0.
  final int month;

  /// 카드 타입.
  final HwatuType type;

  /// 띠 색 (띠가 아니면 [RibbonColor.none]).
  final RibbonColor ribbon;

  /// 광 중 비광(12월 광)인가.
  final bool isGwangBi;

  /// 고도리(2·4·8월 새)인가.
  final bool isGodori;

  /// 국진(9월 열끗/쌍피 겸용)인가.
  final bool isGukjin;

  /// 피로 카운트할 때의 장수 값. 일반피=1, 쌍피=2, 3피=3, 피가 아니면 0.
  /// (국진을 쌍피로 쓸 때의 2는 점수 계산 로직에서 별도 처리.)
  final int junkValue;

  const HwatuCard({
    required this.id,
    required this.month,
    required this.type,
    this.ribbon = RibbonColor.none,
    this.isGwangBi = false,
    this.isGodori = false,
    this.isGukjin = false,
    this.junkValue = 0,
  });
}

/// 고스톱 화투 카드 정적 데이터 테이블 + 헬퍼.
abstract class GoStopCards {
  /// 화투 본패 장수 (보너스 제외).
  static const int hwatuCount = 48;

  /// 보너스패 장수.
  static const int bonusCount = 3;

  /// 전체 장수 (본패 48 + 보너스 3).
  static const int totalCount = 51;

  /// 광 카드 id들. (1·3·8·11·12월)
  static const List<int> gwangIds = [0, 8, 28, 40, 44];

  /// 비광 id (12월 광).
  static const int gwangBiId = 44;

  /// 고도리 id들 (2·4·8월 새).
  static const List<int> godoriIds = [4, 12, 29];

  /// 국진 id (9월 열끗/쌍피 겸용).
  static const int gukjinId = 32;

  /// 홍단 id들 (1·2·3월).
  static const List<int> hongdanIds = [1, 5, 9];

  /// 청단 id들 (6·9·10월).
  static const List<int> cheongdanIds = [21, 33, 37];

  /// 초단 id들 (4·5·7월).
  static const List<int> chodanIds = [13, 17, 25];

  /// 비띠 id (12월).
  static const int bidaeId = 46;

  /// 쌍피(2장 가치) id들 (11월 오동·12월 비·보너스 쌍피 2장).
  /// 국진(32)을 쌍피로 쓸 때의 2는 점수 로직에서 별도 처리한다.
  static const List<int> ssangpiIds = [41, 47, 49, 50];

  /// 3피(3장 가치) id (보너스).
  static const int threePiId = 48;

  /// 전체 카드 정적 테이블 (id 순서).
  static const List<HwatuCard> all = [
    // 1월 송학
    HwatuCard(id: 0, month: 1, type: HwatuType.gwang),
    HwatuCard(
      id: 1,
      month: 1,
      type: HwatuType.ribbon,
      ribbon: RibbonColor.hong,
    ),
    HwatuCard(id: 2, month: 1, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 3, month: 1, type: HwatuType.junk, junkValue: 1),
    // 2월 매조
    HwatuCard(id: 4, month: 2, type: HwatuType.animal, isGodori: true),
    HwatuCard(
      id: 5,
      month: 2,
      type: HwatuType.ribbon,
      ribbon: RibbonColor.hong,
    ),
    HwatuCard(id: 6, month: 2, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 7, month: 2, type: HwatuType.junk, junkValue: 1),
    // 3월 벚꽃
    HwatuCard(id: 8, month: 3, type: HwatuType.gwang),
    HwatuCard(
      id: 9,
      month: 3,
      type: HwatuType.ribbon,
      ribbon: RibbonColor.hong,
    ),
    HwatuCard(id: 10, month: 3, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 11, month: 3, type: HwatuType.junk, junkValue: 1),
    // 4월 흑싸리
    HwatuCard(id: 12, month: 4, type: HwatuType.animal, isGodori: true),
    HwatuCard(
      id: 13,
      month: 4,
      type: HwatuType.ribbon,
      ribbon: RibbonColor.cho,
    ),
    HwatuCard(id: 14, month: 4, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 15, month: 4, type: HwatuType.junk, junkValue: 1),
    // 5월 난초
    HwatuCard(id: 16, month: 5, type: HwatuType.animal),
    HwatuCard(
      id: 17,
      month: 5,
      type: HwatuType.ribbon,
      ribbon: RibbonColor.cho,
    ),
    HwatuCard(id: 18, month: 5, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 19, month: 5, type: HwatuType.junk, junkValue: 1),
    // 6월 모란(나비)
    HwatuCard(id: 20, month: 6, type: HwatuType.animal),
    HwatuCard(
      id: 21,
      month: 6,
      type: HwatuType.ribbon,
      ribbon: RibbonColor.cheong,
    ),
    HwatuCard(id: 22, month: 6, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 23, month: 6, type: HwatuType.junk, junkValue: 1),
    // 7월 홍싸리(멧돼지)
    HwatuCard(id: 24, month: 7, type: HwatuType.animal),
    HwatuCard(
      id: 25,
      month: 7,
      type: HwatuType.ribbon,
      ribbon: RibbonColor.cho,
    ),
    HwatuCard(id: 26, month: 7, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 27, month: 7, type: HwatuType.junk, junkValue: 1),
    // 8월 공산(보름달)
    HwatuCard(id: 28, month: 8, type: HwatuType.gwang),
    HwatuCard(id: 29, month: 8, type: HwatuType.animal, isGodori: true),
    HwatuCard(id: 30, month: 8, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 31, month: 8, type: HwatuType.junk, junkValue: 1),
    // 9월 국화(국진)
    HwatuCard(id: 32, month: 9, type: HwatuType.animal, isGukjin: true),
    HwatuCard(
      id: 33,
      month: 9,
      type: HwatuType.ribbon,
      ribbon: RibbonColor.cheong,
    ),
    HwatuCard(id: 34, month: 9, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 35, month: 9, type: HwatuType.junk, junkValue: 1),
    // 10월 단풍(사슴)
    HwatuCard(id: 36, month: 10, type: HwatuType.animal),
    HwatuCard(
      id: 37,
      month: 10,
      type: HwatuType.ribbon,
      ribbon: RibbonColor.cheong,
    ),
    HwatuCard(id: 38, month: 10, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 39, month: 10, type: HwatuType.junk, junkValue: 1),
    // 11월 오동(똥)
    HwatuCard(id: 40, month: 11, type: HwatuType.gwang),
    HwatuCard(id: 41, month: 11, type: HwatuType.junk, junkValue: 2), // 쌍피
    HwatuCard(id: 42, month: 11, type: HwatuType.junk, junkValue: 1),
    HwatuCard(id: 43, month: 11, type: HwatuType.junk, junkValue: 1),
    // 12월 비
    HwatuCard(id: 44, month: 12, type: HwatuType.gwang, isGwangBi: true), // 비광
    HwatuCard(id: 45, month: 12, type: HwatuType.animal),
    HwatuCard(
      id: 46,
      month: 12,
      type: HwatuType.ribbon,
      ribbon: RibbonColor.bi,
    ),
    HwatuCard(id: 47, month: 12, type: HwatuType.junk, junkValue: 2), // 쌍피
    // 보너스패
    HwatuCard(id: 48, month: 0, type: HwatuType.bonus, junkValue: 3), // 3피
    HwatuCard(id: 49, month: 0, type: HwatuType.bonus, junkValue: 2), // 쌍피
    HwatuCard(id: 50, month: 0, type: HwatuType.bonus, junkValue: 2), // 쌍피
  ];

  /// id로 카드 데이터 조회.
  static HwatuCard card(int id) => all[id];

  /// 월 (id 0..47). 보너스패는 0.
  static int monthOf(int id) => all[id].month;

  /// 타입.
  static HwatuType typeOf(int id) => all[id].type;

  /// 띠 색.
  static RibbonColor ribbonColorOf(int id) => all[id].ribbon;

  /// 비광인가.
  static bool isGwangBi(int id) => all[id].isGwangBi;

  /// 고도리인가.
  static bool isGodori(int id) => all[id].isGodori;

  /// 국진인가.
  static bool isGukjin(int id) => all[id].isGukjin;

  /// 피 장수 값(일반피1/쌍피2/3피3). 피가 아니면 0.
  static int junkValue(int id) => all[id].junkValue;

  /// 보너스패인가.
  static bool isBonus(int id) => all[id].type == HwatuType.bonus;

  /// 광인가.
  static bool isGwang(int id) => all[id].type == HwatuType.gwang;

  /// 열끗(동물)인가.
  static bool isAnimal(int id) => all[id].type == HwatuType.animal;

  /// 띠인가.
  static bool isRibbon(int id) => all[id].type == HwatuType.ribbon;

  /// 피(피 더미로 들어가는 카드)인가. 본패 피 + 보너스패 포함.
  static bool isJunk(int id) =>
      all[id].type == HwatuType.junk || all[id].type == HwatuType.bonus;
}
