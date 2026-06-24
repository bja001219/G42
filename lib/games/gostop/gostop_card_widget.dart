import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../theme.dart';
import 'gostop_cards.dart';

/// 화투 카드 1장을 그리는 위젯.
///
/// - id 0..47: `assets/hwatu/<manifest[id]>` 이미지를 그린다.
/// - id 48..50(보너스패): 이미지가 없어 코드드로우(라벨: 3피/쌍피).
/// - [faceDown] 이면 항상 뒷면(코드드로우, 무늬 + "화투").
///
/// 색맹 배려: 색뿐 아니라 라벨/아이콘으로도 분류를 구분한다.
///
/// 강조/연출 옵션:
/// - [selected]: 선택 시 위로 살짝 들림 + 노란 테두리(기존 동작 유지).
/// - [glow]: 매치 강조용 금색 외곽 글로우(붙을 카드 안내).
/// - [dim]: 비대상 카드 살짝 흐리게(대비 강조).
/// - [flipAngle]: Y축 3D 플립 각도(rad). 0이면 변환 없음. 뷰의 더미 플립에서
///   `Matrix4.identity()..setEntry(3,2,0.001)..rotateY(angle)` 형태로 회전하며,
///   |angle|이 π/2를 넘으면 앞/뒷면을 전환하고 뒷면은 미러링을 보정한다.
class GoStopCardWidget extends StatelessWidget {
  /// 카드 id(0..50). 뒷면이면 무시될 수 있다.
  final int cardId;

  /// 항상 뒷면으로 그릴지.
  final bool faceDown;

  /// 선택 강조 표시.
  final bool selected;

  /// 탭 콜백(null이면 비활성).
  final VoidCallback? onTap;

  /// 카드 가로 길이(세로는 비율 5:8로 자동).
  final double width;

  /// 매치 강조용 금색 외곽 글로우.
  final bool glow;

  /// 비대상(매치 불가) 카드 흐리게.
  final bool dim;

  /// Y축 3D 플립 각도(rad). 0이면 회전 없음.
  ///
  /// 카드 중심을 기준으로 [Matrix4.rotateY]로 회전하며, |각도|가 π/2를 넘는
  /// 순간 [faceDown] 의도와 반대 면으로 전환된다. 뒷면 구간에서는 텍스트/이미지
  /// 미러링을 막기 위해 콘텐츠를 추가로 π 만큼 반전 보정한다.
  final double flipAngle;

  const GoStopCardWidget({
    super.key,
    required this.cardId,
    this.faceDown = false,
    this.selected = false,
    this.onTap,
    this.width = 44,
    this.glow = false,
    this.dim = false,
    this.flipAngle = 0,
  });

  /// 카드 가로:세로 비율(5:8).
  static const double aspect = 5 / 8;

  double get _height => width / aspect;

  /// 현재 플립 각도 기준, 뒤집힌(반대 면이 보이는) 구간인지.
  ///
  /// |angle|이 π/2를 넘으면 카드가 반쯤 돌아 반대 면이 시청자를 향한다.
  bool get _isBackHalf {
    final a = (flipAngle.abs()) % (2 * math.pi);
    return a > math.pi / 2 && a < 3 * math.pi / 2;
  }

  @override
  Widget build(BuildContext context) {
    final card = _cardSurface(context);

    if (flipAngle == 0) {
      // 변환 없음: 종전 경로 그대로(탭 타깃 동일).
      return _wrapTap(card);
    }

    // 3D Y축 플립. Transform 은 paint-only 이므로 GestureDetector 가 Transform 을
    // 감싸 탭 타깃을 (회전 전) 원래 사각형 영역으로 유지한다.
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateY(flipAngle);
    return _wrapTap(
      Transform(alignment: Alignment.center, transform: transform, child: card),
    );
  }

  /// 탭 콜백이 있으면 [GestureDetector] 로 감싼다.
  ///
  /// 핵심: [Transform] 은 hit-test 영역을 바꾸지 않는 paint-only 위젯이므로,
  /// 반드시 GestureDetector 가 Transform 의 바깥(또는 동일)에 위치해야 한다.
  Widget _wrapTap(Widget child) {
    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }

  /// 테두리·그림자·들림·글로우·dim 을 적용한 카드 표면 1장.
  Widget _cardSurface(BuildContext context) {
    // 플립 중 반대 면이 보이는 구간이면 앞/뒷면 의도를 뒤집는다.
    final showBack = _isBackHalf ? !faceDown : faceDown;

    final shadows = <BoxShadow>[
      const BoxShadow(
        color: Color(0x55000000),
        blurRadius: 3,
        offset: Offset(0, 1),
      ),
      if (glow)
        const BoxShadow(
          color: Color(0xCCFFD54F),
          blurRadius: 10,
          spreadRadius: 1.5,
        ),
    ];

    Widget surface = SizedBox(
      width: width,
      height: _height,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: glow
                ? const Color(0xFFFFC107)
                : selected
                ? G42Colors.warn
                : Colors.black.withValues(alpha: 0.35),
            width: (selected || glow) ? 3 : 1,
          ),
          boxShadow: shadows,
        ),
        transform: selected
            ? (Matrix4.identity()..translateByDouble(0.0, -8.0, 0.0, 1.0))
            : Matrix4.identity(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: _faceFor(showBack),
        ),
      ),
    );

    // 뒷면 구간에서는 콘텐츠가 거울처럼 좌우 반전되어 보이므로 한 번 더 돌려 보정.
    if (_isBackHalf) {
      surface = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..rotateY(math.pi),
        child: surface,
      );
    }

    if (dim) {
      surface = Opacity(opacity: 0.45, child: surface);
    }
    return surface;
  }

  /// [showBack] 에 따라 앞/뒷면을 고른다(플립 전환 포함).
  Widget _faceFor(bool showBack) {
    if (showBack) return _back();
    if (GoStopCards.isBonus(cardId)) return _bonus();
    return _imageWithBadge();
  }

  // ---- 앞면(이미지 + 월 배지) ----------------------------------------------

  /// 앞면 이미지 위에 월 번호 배지를 겹쳐 그린다(보너스패는 배지 없음).
  Widget _imageWithBadge() {
    final base = _image();
    // 보너스패(month==0)는 월 개념이 없어 배지를 그리지 않는다.
    if (GoStopCards.isBonus(cardId)) return base;
    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        Positioned(top: 1, left: 1, child: _monthBadge()),
      ],
    );
  }

  /// 작은 화면 가독용 월 번호 배지(좌상단).
  Widget _monthBadge() {
    final month = GoStopCards.card(cardId).month;
    // 카드 폭에 비례해 배지 크기를 정한다(아주 작게 그려도 읽히도록).
    final fontSize = (width * 0.26).clamp(7.0, 13.0);
    final pad = (width * 0.05).clamp(1.0, 3.0);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad + 1, vertical: pad - 0.5),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x66FFFFFF), width: 0.5),
      ),
      child: Text(
        '$month',
        style: TextStyle(
          fontSize: fontSize,
          height: 1.0,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _image() {
    return FutureBuilder<Map<String, String>>(
      future: _manifest(),
      builder: (context, snap) {
        final path = snap.data?['$cardId'];
        if (path == null) {
          // 매니페스트 로딩 전/누락: 플레이스홀더.
          return Container(color: Colors.white);
        }
        return Image.asset(
          'assets/hwatu/$path',
          fit: BoxFit.cover,
          width: width,
          height: _height,
          errorBuilder: (context, error, stack) => _imageFallback(),
        );
      },
    );
  }

  /// 이미지 로드 실패 시 카드 정보를 코드로 표시(색맹 배려 라벨 포함).
  Widget _imageFallback() {
    final card = GoStopCards.card(cardId);
    final label = _typeLabel(card.type);
    final color = _typeColor(card.type);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(2),
      // 작은 카드에서도 넘치지 않게 콘텐츠를 스케일 다운.
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${card.month}월',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 보너스패(코드드로우) ------------------------------------------------

  Widget _bonus() {
    final value = GoStopCards.junkValue(cardId);
    final label = value == 3 ? '3피' : '쌍피';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE082), Color(0xFFFFB300)],
        ),
      ),
      child: Center(
        // 작은 카드(부채/축소 표시)에서도 넘치지 않게 콘텐츠를 스케일 다운.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: Color(0xFF7B3F00),
                ),
                const SizedBox(height: 2),
                const Text(
                  '보너스',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7B3F00),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF5D2E00),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- 뒷면(코드드로우) ----------------------------------------------------

  Widget _back() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8E2A2A), Color(0xFF5A1212)],
        ),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
      ),
      child: Center(
        // 작은 카드(상대 손패/축소 더미)에서도 넘치지 않게 콘텐츠를 스케일 다운.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.local_florist_rounded,
                  size: 18,
                  color: Color(0xFFE8C96A),
                ),
                SizedBox(height: 2),
                Text(
                  '화투',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE8C96A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- 색맹 배려 라벨/색 ----------------------------------------------------

  static String _typeLabel(HwatuType t) {
    switch (t) {
      case HwatuType.gwang:
        return '광';
      case HwatuType.animal:
        return '열끗';
      case HwatuType.ribbon:
        return '띠';
      case HwatuType.junk:
        return '피';
      case HwatuType.bonus:
        return '보너스';
    }
  }

  static Color _typeColor(HwatuType t) {
    switch (t) {
      case HwatuType.gwang:
        return const Color(0xFFB8860B);
      case HwatuType.animal:
        return const Color(0xFF2E7D32);
      case HwatuType.ribbon:
        return const Color(0xFFC62828);
      case HwatuType.junk:
        return const Color(0xFF455A64);
      case HwatuType.bonus:
        return const Color(0xFFEF6C00);
    }
  }

  // ---- 매니페스트 캐싱 ------------------------------------------------------

  static Future<Map<String, String>>? _manifestFuture;

  /// `assets/hwatu/manifest.json` 을 앱 생애 1회만 로드해 캐싱한다.
  static Future<Map<String, String>> _manifest() {
    return _manifestFuture ??= rootBundle
        .loadString('assets/hwatu/manifest.json')
        .then((raw) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final out = <String, String>{};
          decoded.forEach((k, v) {
            if (v is String) out[k] = v;
          });
          return out;
        });
  }
}
