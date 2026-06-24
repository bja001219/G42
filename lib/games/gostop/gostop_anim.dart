import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'gostop_logic.dart';

/// 고스톱 턴 안무용 애니메이션 프리미티브 (뷰에서 사용).
///
/// 스펙 §C(아키텍처)·§G(타이밍/붙음·낙하)·§H(콜아웃)·§K(햅틱)를 한 곳에 모은다.
/// 모든 타이밍 상수는 [GoStopAnimTimings] 한 블록에 두어 추후 노말/스피드 토글에
/// 대비한다. 위젯/부수효과는 최소화하고, 프레임-크리티컬 타이밍은 뷰의
/// `AnimationController` 가 이 구간 비율로 구동한다.

/// 안무 타이밍 카탈로그 (§G). 단일 진실 소스.
///
/// 한 "수(move)"의 전체 길이 = [totalMoveMs]. 각 단계는 전체 길이 대비 비율
/// [Interval] 로 구동된다(컨트롤러 1개로 체이닝, `Future.delayed` 금지).
abstract class GoStopAnimTimings {
  // ── 단계별 권장 길이(ms) — research §3 카탈로그 노말 값 ──
  /// 손패 → 바닥 슬라이드.
  static const int handSlideMs = 230;

  /// 바닥 매치 하이라이트(글로우).
  static const int floorHighlightMs = 90;

  /// 손패/뒤집기 캡처 스윕(먹은 패로 쓸어담기).
  static const int captureSweepMs = 260;

  /// 더미 플립(3D 회전).
  static const int deckFlipMs = 190;

  /// 서스펜스 홀드(뒤집은 카드 정지).
  static const int suspenseHoldMs = 420;

  /// 매치 스냅(붙음) + 글로우 플래시.
  static const int matchSnapMs = 140;

  /// 낙하(안 붙음) 드롭.
  static const int dropMs = 240;

  /// 인-플레이 콜아웃 배너 등장.
  static const int calloutInMs = 240;

  /// 콜아웃 홀드.
  static const int calloutHoldMs = 640;

  /// 콜아웃 페이드아웃.
  static const int calloutOutMs = 260;

  // ── 한 수 전체 길이 + 단계 경계(0..1 비율) ──
  // 비행/스윕 위주로 합산(콜아웃은 병렬 오버레이라 본문 길이엔 미포함).
  static const int totalMoveMs =
      handSlideMs +
      floorHighlightMs +
      captureSweepMs +
      deckFlipMs +
      suspenseHoldMs +
      matchSnapMs +
      captureSweepMs; // 뒤집기 캡처 스윕

  /// [0..1] 정규화된 단계 경계. 순서:
  /// handSlide → floorHighlight → handCapture → deckFlip → suspense →
  /// flipSnap/drop → flipCapture.
  static double get _t => totalMoveMs.toDouble();
  static double get handSlideEnd => handSlideMs / _t;
  static double get floorHighlightEnd => (handSlideMs + floorHighlightMs) / _t;
  static double get handCaptureEnd =>
      (handSlideMs + floorHighlightMs + captureSweepMs) / _t;
  static double get deckFlipEnd =>
      (handSlideMs + floorHighlightMs + captureSweepMs + deckFlipMs) / _t;
  static double get suspenseEnd =>
      (handSlideMs +
          floorHighlightMs +
          captureSweepMs +
          deckFlipMs +
          suspenseHoldMs) /
      _t;
  static double get flipSnapEnd =>
      (handSlideMs +
          floorHighlightMs +
          captureSweepMs +
          deckFlipMs +
          suspenseHoldMs +
          matchSnapMs) /
      _t;
  // flipCaptureEnd == 1.0
}

/// 햅틱 매핑 (§K). 이벤트 코드 → 적절한 [HapticFeedback].
abstract class GoStopHaptics {
  /// 카드 내기/일반 먹기: 가벼운 선택 클릭.
  static void play() => HapticFeedback.selectionClick();

  /// 매치 스냅(붙음)·쪽·따닥·폭탄·쓸기: 중간 임팩트.
  static void matchSnap() => HapticFeedback.mediumImpact();

  /// 낙하(안 붙음): 약한 임팩트.
  static void drop() => HapticFeedback.lightImpact();

  /// 뻑·총통·고/스톱 확정: 강한 임팩트.
  static void heavy() => HapticFeedback.heavyImpact();

  /// 이벤트 코드에 맞는 햅틱을 한 번 재생한다(연출 분기에서 호출).
  static void forEvent(String event) {
    switch (event) {
      case GoStopLogic.evPpeok:
      case GoStopLogic.evJappeok:
      case GoStopLogic.evChongtong:
        heavy();
        break;
      case GoStopLogic.evJjok:
      case GoStopLogic.evTtadak:
      case GoStopLogic.evSseulgi:
      case GoStopLogic.evBomb:
        matchSnap();
        break;
      case GoStopLogic.evEat:
        matchSnap();
        break;
      case GoStopLogic.evBonus:
        play();
        break;
    }
  }
}

/// 인-플레이 콜아웃(가운데 큰 배너) 데이터.
class GoStopCallout {
  final String text;
  final Color color;
  final IconData icon;

  const GoStopCallout({
    required this.text,
    required this.color,
    required this.icon,
  });

  /// 이벤트 코드 → 콜아웃(없으면 null). 결과 화면 전용(피박/광박/고박)은 제외.
  static GoStopCallout? forEvent(String event) {
    switch (event) {
      case GoStopLogic.evPpeok:
        return const GoStopCallout(
          text: '뻑!',
          color: Color(0xFFFF6B6B),
          icon: Icons.block_rounded,
        );
      case GoStopLogic.evJappeok:
        return const GoStopCallout(
          text: '자뻑!',
          color: Color(0xFFFFA726),
          icon: Icons.flash_on_rounded,
        );
      case GoStopLogic.evTtadak:
        return const GoStopCallout(
          text: '따닥!',
          color: Color(0xFF42A5F5),
          icon: Icons.double_arrow_rounded,
        );
      case GoStopLogic.evJjok:
        return const GoStopCallout(
          text: '쪽!',
          color: Color(0xFF26C6DA),
          icon: Icons.favorite_rounded,
        );
      case GoStopLogic.evSseulgi:
        return const GoStopCallout(
          text: '쓸기!',
          color: Color(0xFFAB47BC),
          icon: Icons.cleaning_services_rounded,
        );
      case GoStopLogic.evBomb:
        return const GoStopCallout(
          text: '폭탄!',
          color: Color(0xFFEF5350),
          icon: Icons.bolt_rounded,
        );
      case GoStopLogic.evBonus:
        return const GoStopCallout(
          text: '보너스!',
          color: Color(0xFFFFCA28),
          icon: Icons.star_rounded,
        );
      case GoStopLogic.evChongtong:
        return const GoStopCallout(
          text: '총통!',
          color: Color(0xFFFFD54F),
          icon: Icons.emoji_events_rounded,
        );
    }
    return null;
  }

  /// 흔들기 콜아웃(이벤트 코드와 별개로 트리거).
  static const GoStopCallout shake = GoStopCallout(
    text: '흔들기!',
    color: Color(0xFFFFD54F),
    icon: Icons.vibration_rounded,
  );

  /// 고! 콜아웃.
  static const GoStopCallout go = GoStopCallout(
    text: '고!',
    color: Color(0xFF26DE81),
    icon: Icons.arrow_forward_rounded,
  );

  /// 스톱! 콜아웃.
  static const GoStopCallout stop = GoStopCallout(
    text: '스톱!',
    color: Color(0xFFFF6B6B),
    icon: Icons.front_hand_rounded,
  );
}

/// 가운데 큰 콜아웃 배너 위젯 (스케일-인 + 페이드, §H).
///
/// [progress] 0..1 로 등장→홀드→퇴장을 표현한다(컨트롤러가 구동).
class GoStopCalloutBanner extends StatelessWidget {
  final GoStopCallout callout;
  final double progress;
  final double width;

  const GoStopCalloutBanner({
    super.key,
    required this.callout,
    required this.progress,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    // 등장 구간(0..0.25) 스케일-인, 마지막(0.7..1) 페이드아웃.
    const inEnd = 0.25;
    const outStart = 0.72;
    double opacity;
    double scale;
    if (progress < inEnd) {
      final t = (progress / inEnd).clamp(0.0, 1.0);
      opacity = t;
      scale = 0.6 + 0.4 * Curves.easeOutBack.transform(t);
    } else if (progress > outStart) {
      final t = ((progress - outStart) / (1 - outStart)).clamp(0.0, 1.0);
      opacity = 1 - t;
      scale = 1 + 0.08 * t;
    } else {
      opacity = 1;
      scale = 1;
    }

    final fontSize = (width * 0.13).clamp(28.0, 64.0);
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: width * 0.06,
              vertical: width * 0.035,
            ),
            decoration: BoxDecoration(
              color: const Color(0xCC10241A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: callout.color, width: 3),
              boxShadow: [
                BoxShadow(
                  color: callout.color.withValues(alpha: 0.5),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(callout.icon, color: callout.color, size: fontSize),
                SizedBox(width: width * 0.025),
                Text(
                  callout.text,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: callout.color.withValues(alpha: 0.8),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 한 수(move)의 안무를 기술하는 불변 명세.
///
/// 뷰가 권위 상태 변화(내 수/상대 수 동일 경로)를 감지하면 `lastMove` + diff 로
/// 이 명세를 만들어 컨트롤러로 재생한다. 재생 동안 displayed 상태가 점진적으로
/// new 로 모핑되고, 끝나면 displayed=authoritative 로 스냅한다.
class GoStopMoveAnim {
  /// 수를 둔 플레이어 id.
  final String actor;

  /// 손패에서 낸 대표 카드(비행 출발).
  final int playedCard;

  /// 폭탄이면 손패 3장(없으면 비어 있음).
  final List<int> bombCards;

  /// 더미에서 뒤집은 카드(없으면 -1).
  final int flippedCard;

  /// 손패 단계가 먹은 카드들(캡처 스윕 대상).
  final List<int> handCaptured;

  /// 뒤집기 단계가 먹은 카드들(매치 스냅 + 캡처 스윕 대상).
  final List<int> flipCaptured;

  /// 손패 카드가 바닥에 안착했는가(매치 없이 낙하).
  final bool handToFloor;

  /// 뒤집은 카드가 바닥에 안착했는가(매치 없이 낙하).
  final bool flipToFloor;

  /// 이벤트 코드(콜아웃/햅틱 분기).
  final String event;

  const GoStopMoveAnim({
    required this.actor,
    required this.playedCard,
    required this.bombCards,
    required this.flippedCard,
    required this.handCaptured,
    required this.flipCaptured,
    required this.handToFloor,
    required this.flipToFloor,
    required this.event,
  });

  /// 손패 단계에서 무언가 먹었는가(매치 발생).
  bool get handMatched => handCaptured.isNotEmpty;

  /// 뒤집기 단계에서 무언가 먹었는가(붙음 vs 낙하 분기).
  bool get flipMatched => flipCaptured.isNotEmpty;

  /// `lastMove` 메타(JSON 평탄 맵)에서 안무 명세를 만든다. null/비호환이면 null.
  static GoStopMoveAnim? fromLastMove(dynamic raw) {
    if (raw is! Map) return null;
    List<int> il(dynamic v) =>
        v is List ? v.map((e) => (e as num).toInt()).toList() : <int>[];
    int iv(dynamic v) => v is num ? v.toInt() : -1;
    final actor = raw['actor'];
    if (actor is! String) return null;
    final played = iv(raw['playedCard']);
    if (played < 0) return null;
    return GoStopMoveAnim(
      actor: actor,
      playedCard: played,
      bombCards: il(raw['bombCards']),
      flippedCard: iv(raw['flippedCard']),
      handCaptured: il(raw['handCaptured']),
      flipCaptured: il(raw['flipCaptured']),
      handToFloor: il(raw['handToFloor']).isNotEmpty,
      flipToFloor: il(raw['flipToFloor']).isNotEmpty,
      event: (raw['event'] as String?) ?? GoStopLogic.evNone,
    );
  }
}
