import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// 먹은 패 분류(겹친 가로 줄 4종). 순서는 시각 표시 순서(광→열끗→띠→피)와 일치.
///
/// 기존 [HwatuType]의 `gwang/animal/ribbon/junk` 와 1:1로 대응한다
/// (animal=열끗, ribbon=띠, junk=피). 보너스패는 피(junk) 줄에 합류.
enum GoStopGroup { gwang, animal, ribbon, junk }

/// 고스톱 테이블의 **순수 레이아웃 수학** (위젯/부수효과 없음).
///
/// 모든 좌표는 [size] 비율로만 산출한다(고정 픽셀 가정 금지). 작은 화면 대응은
/// `LayoutBuilder` 가 측정한 [Size] 를 주입하면 자동으로 비례 축소된다.
///
/// 세로 3-존(상대/중앙필드/나) 구성은 스펙 §E 비율을 따른다:
/// 상대 프로필 ~9% → 상대 손패 ~9% → 상대 먹은패 ~9% →
/// **중앙 필드(바닥+더미) ~35%** → 내 먹은패 ~9% → 내 손패 ~13% → 하단 ~16%.
///
/// 좌표계: 원점(0,0)은 좌상단, +x 오른쪽, +y 아래(Flutter 기본).
class GoStopGeometry {
  /// 테이블(게임판) 영역 크기.
  final Size size;

  const GoStopGeometry(this.size);

  // ────────────────────────────────────────────────────────────────────────
  // 세로 존 비율 (§E). 합 = 1.00.
  //   opponent 영역 = 프로필 + 상대손패 + 상대먹은패 = 0.09+0.09+0.09 = 0.27
  //   field(중앙)   = 0.35
  //   my 영역       = 내먹은패 0.09 + 내손패 0.13 + 하단 0.16 = 0.38
  // ────────────────────────────────────────────────────────────────────────
  static const double _opponentProfileFrac = 0.09;
  static const double _opponentHandFrac = 0.09;
  static const double _opponentCapturedFrac = 0.09;
  static const double _fieldFrac = 0.35;
  static const double _myCapturedFrac = 0.09;
  static const double _myHandFrac = 0.13;
  static const double _bottomFrac = 0.16;

  /// 좌우 우드 프레임 안쪽 여백(가로 비율). 카드가 프레임을 넘지 않게 한다.
  static const double _sideInsetFrac = 0.035;

  // 누적 경계(상단부터). [size.height] 기준 y 좌표.
  double get _yOpponentTop => 0;
  double get _yOpponentHandTop => size.height * _opponentProfileFrac;
  double get _yOpponentCapturedTop =>
      size.height * (_opponentProfileFrac + _opponentHandFrac);
  double get _yFieldTop =>
      size.height *
      (_opponentProfileFrac + _opponentHandFrac + _opponentCapturedFrac);
  double get _yMyCapturedTop => _yFieldTop + size.height * _fieldFrac;
  double get _yMyHandTop => _yMyCapturedTop + size.height * _myCapturedFrac;
  double get _yBottomTop => _yMyHandTop + size.height * _myHandFrac;

  double get _sideInset => size.width * _sideInsetFrac;
  double get _innerWidth => size.width - _sideInset * 2;

  // ────────────────────────────────────────────────────────────────────────
  // 존 사각형 (§D / §E)
  // ────────────────────────────────────────────────────────────────────────

  /// 상대 영역 전체(프로필 + 상대 손패 + 상대 먹은패).
  Rect get opponentZone => Rect.fromLTWH(
    _sideInset,
    _yOpponentTop,
    _innerWidth,
    size.height *
        (_opponentProfileFrac + _opponentHandFrac + _opponentCapturedFrac),
  );

  /// 중앙 필드(바닥패 + 더미). 바닥 앵커는 모두 이 사각형 안에 들어온다.
  Rect get fieldZone => Rect.fromLTWH(
    _sideInset,
    _yFieldTop,
    _innerWidth,
    size.height * _fieldFrac,
  );

  /// 내 영역 전체(내 먹은패 + 내 손패 + 하단 액션 밴드).
  Rect get myZone => Rect.fromLTWH(
    _sideInset,
    _yMyCapturedTop,
    _innerWidth,
    size.height * (_myCapturedFrac + _myHandFrac + _bottomFrac),
  );

  /// 상대 손패(뒷면 부채) 밴드. 상대 수 재생 시 손패 출발/도착 기준.
  Rect get opponentHandBand => Rect.fromLTWH(
    _sideInset,
    _yOpponentHandTop,
    _innerWidth,
    size.height * _opponentHandFrac,
  );

  /// 하단 액션 밴드(고/스톱·폭탄 등 버튼/패널 영역). 손패 밴드 아래.
  Rect get bottomBand => Rect.fromLTWH(
    _sideInset,
    _yBottomTop,
    _innerWidth,
    size.height * _bottomFrac,
  );

  /// 더미(stock) 중심 = 필드 정중앙(한쪽 몰림 금지, §F).
  Offset get deckCenter => fieldZone.center;

  // ────────────────────────────────────────────────────────────────────────
  // 카드 크기
  // ────────────────────────────────────────────────────────────────────────

  /// 카드 가로 길이(세로는 5:8 비율, [GoStopCardWidget.aspect]).
  ///
  /// 손패가 최대 ~10장 부채로 겹쳐도, 또 바닥 군집이 필드를 넘지 않도록
  /// 화면 폭과 필드 높이 양쪽을 고려한 비율로 정한다(스크롤 없이 맞춤).
  double get cardWidth {
    // 폭 기준: 내부 폭의 ~13% (10장 부채 + 겹침 가정).
    final byWidth = _innerWidth * 0.13;
    // 높이 기준: 필드 높이의 ~26% 가 카드 높이가 되도록 (군집 2~3겹 여유).
    //   cardHeight = cardWidth / aspect  →  cardWidth = cardHeight * aspect
    const aspect = 5 / 8; // GoStopCardWidget.aspect 와 동일
    final byHeight = (size.height * _fieldFrac * 0.26) * aspect;
    final w = math.min(byWidth, byHeight);
    // 너무 작아지지 않게 하한(아주 작은 화면 보호). 비율 기반 하한.
    final floor = size.shortestSide * 0.07;
    return math.max(w, floor);
  }

  double get _cardHeight => cardWidth / (5 / 8);

  // ────────────────────────────────────────────────────────────────────────
  // 바닥(마당) 배치 (§D / §F)
  // ────────────────────────────────────────────────────────────────────────

  /// 월(1..12)별 바닥 무더기의 **앵커(중심)** 오프셋.
  ///
  /// 규칙(레퍼런스 = 실제 맞고 바닥):
  ///  - 더미를 **정중앙**에 두고, 바닥패는 **위 줄 / 아래 줄** 두 줄로 나눠
  ///    더미를 위아래로 감싼다(위 줄이 한 장 더 가짐). 깔끔한 줄 배치.
  ///  - 같은 달은 **항상 같은 앵커**(같은 [presentMonths] 집합에서 결정적).
  ///  - 등장 순서([presentMonths] 의 정렬·인덱스)로 결정적 배치.
  ///  - 각 줄은 가로 균등·가운데 정렬. 줄이 많아지면 간격을 좁혀(겹침 허용)
  ///    [fieldZone] 안에 머문다(오버플로 금지).
  ///
  /// [month] 가 [presentMonths] 에 없으면 정렬 후 끝에 가상으로 덧붙여 위치를
  /// 계산한다(신규 등장 달도 안정적으로 자리 잡도록).
  Offset floorAnchor(int month, List<int> presentMonths) {
    // 결정적 정렬(중복 제거). 같은 집합이면 같은 인덱스 → 같은 앵커.
    final months = <int>{...presentMonths, month}.toList()..sort();
    final n = months.length;
    var idx = months.indexOf(month);
    if (idx < 0) idx = n - 1; // 방어적(정상적으로는 항상 포함됨)

    // 위/아래 두 줄로 분배(위 줄이 더 많이 가짐). 더미는 두 줄 사이 정중앙.
    final topCount = (n + 1) ~/ 2;
    final isTop = idx < topCount;
    final rowCount = isTop ? topCount : (n - topCount);
    final posInRow = isTop ? idx : (idx - topCount);

    final field = fieldZone;
    // 줄 y: 위 줄은 필드 상단 근처, 아래 줄은 필드 하단 근처(더미는 가운데 떠 있음).
    final y = isTop
        ? field.top + _cardHeight * 0.72
        : field.bottom - _cardHeight * 0.72;

    // 가로 균등 배치(가운데 정렬). 줄이 넘치면 간격을 좁힌다(겹침 허용).
    final marginX = _cardHalfWidth + _sideInset * 0.5;
    final usableW = field.width - marginX * 2;
    final step = rowCount <= 1
        ? 0.0
        : math.min(cardWidth * 1.15, usableW / rowCount);
    final rowW = step * (rowCount - 1);
    final x = rowCount <= 1
        ? field.center.dx
        : field.center.dx - rowW / 2 + posInRow * step;

    return Offset(x, y);
  }

  /// 같은 달 무더기 안에서 [indexInMonth] 번째(0-base) 카드의 **앵커 대비 오프셋**.
  /// ~20% 겹침 캐스케이드(페어/트리플이 부채처럼 보이게, §F).
  Offset stackOffset(int indexInMonth) {
    // 오른쪽-아래로 살짝씩 밀어 겹침(카드 폭/높이의 ~20%/~12%).
    final dx = indexInMonth * cardWidth * 0.20;
    final dy = indexInMonth * _cardHeight * 0.12;
    return Offset(dx, dy);
  }

  // ────────────────────────────────────────────────────────────────────────
  // 손패 부채꼴 (§D)
  // ────────────────────────────────────────────────────────────────────────

  /// 내 손패의 [i] 번째(0-base, 총 [n] 장) 카드 **중심 위치 + Z회전(rad)**.
  ///
  /// - 부채(fan) 아크: 전체 스프레드 ~26~30°(중앙 0°, 양끝 ±spread/2).
  /// - 피벗은 카드 **아래쪽**(아크 중심이 손패 밴드 하단보다 더 아래) → 위로 볼록.
  /// - 가로 중앙(myZone hand band 중앙)에 정렬, 카드끼리 겹침.
  ({Offset pos, double angle}) handSlot(int i, int n) {
    final bandCenterX = myZone.center.dx;
    // 손패 밴드의 세로 중심: 내 먹은패 아래, 하단 위.
    final handBandTop = _yMyHandTop;
    final handBandH = size.height * _myHandFrac;
    final bandCenterY = handBandTop + handBandH * 0.5;

    if (n <= 1) {
      return (pos: Offset(bandCenterX, bandCenterY), angle: 0.0);
    }

    // 전체 스프레드 28°(라디안). 장수 많아도 ~30° 넘지 않게 캡.
    const maxSpread = 30 * math.pi / 180;
    const perCard = 4.2 * math.pi / 180; // 카드당 각 간격(많아질수록 좁아짐)
    final spread = math.min(maxSpread, perCard * (n - 1));

    // i 를 -0.5..0.5 정규화 → 각도. 중앙이 0.
    final frac = (i / (n - 1)) - 0.5; // -0.5..0.5
    final angle = frac * spread;

    // 아크 피벗 반경: 카드 높이의 ~2.6배(완만한 호). 피벗은 밴드 중심 아래.
    final pivotR = _cardHeight * 2.6;
    final pivotY = bandCenterY + pivotR;

    // 피벗을 중심으로 각 angle 만큼 회전한 카드 중심 위치.
    final px = bandCenterX + math.sin(angle) * pivotR;
    final py = pivotY - math.cos(angle) * pivotR;

    return (pos: Offset(px, py), angle: angle);
  }

  // ────────────────────────────────────────────────────────────────────────
  // 먹은 패 분류 줄 (§D / §I)
  // ────────────────────────────────────────────────────────────────────────

  /// 먹은 패: 분류 [group] 줄의 [i] 번째(0-base) 카드 위치.
  /// [mine] 이면 내 먹은패 밴드, 아니면 상대 먹은패 밴드.
  ///
  /// 4줄(광/열끗/띠/피)을 세로로 쌓고, 줄 안에서 ~15~20% 겹침 캐스케이드(§I).
  /// 상대 줄은 더 작게 그리는 건 위젯 책임이지만, 좌표 자체도 상대 밴드 안에서 산출.
  Offset capturedSlot(GoStopGroup group, int i, bool mine) {
    final Rect band = mine ? _myCapturedBand : _opponentCapturedBand;

    const rows = 4; // gwang, animal, ribbon, junk
    final rowH = band.height / rows;
    final rowIndex = group.index; // enum 선언 순서 = 표시 순서(광→열끗→띠→피)
    final rowCenterY = band.top + rowH * (rowIndex + 0.5);

    // 줄 시작 x(왼쪽 정렬) + 겹침 캐스케이드(카드 폭의 ~18%).
    final startX = band.left + cardWidth * 0.5;
    final x = startX + i * cardWidth * 0.18;

    return Offset(x, rowCenterY);
  }

  // 내 먹은패 밴드(존 안 별도 사각형).
  Rect get _myCapturedBand => Rect.fromLTWH(
    _sideInset,
    _yMyCapturedTop,
    _innerWidth,
    size.height * _myCapturedFrac,
  );

  // 상대 먹은패 밴드.
  Rect get _opponentCapturedBand => Rect.fromLTWH(
    _sideInset,
    _yOpponentCapturedTop,
    _innerWidth,
    size.height * _opponentCapturedFrac,
  );

  // ────────────────────────────────────────────────────────────────────────
  // 내부 헬퍼
  // ────────────────────────────────────────────────────────────────────────

  double get _cardHalfWidth => cardWidth * 0.5;
}
