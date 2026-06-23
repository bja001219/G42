import 'dart:convert';

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

  const GoStopCardWidget({
    super.key,
    required this.cardId,
    this.faceDown = false,
    this.selected = false,
    this.onTap,
    this.width = 44,
  });

  /// 카드 가로:세로 비율(5:8).
  static const double aspect = 5 / 8;

  double get _height => width / aspect;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: width,
      height: _height,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? G42Colors.warn
                : Colors.black.withValues(alpha: 0.35),
            width: selected ? 3 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        transform: selected
            ? (Matrix4.identity()..translateByDouble(0.0, -8.0, 0.0, 1.0))
            : Matrix4.identity(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: _face(),
        ),
      ),
    );

    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }

  Widget _face() {
    if (faceDown) return _back();
    if (GoStopCards.isBonus(cardId)) return _bonus();
    return _image();
  }

  // ---- 앞면(이미지) --------------------------------------------------------

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
      child: Column(
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.star_rounded, size: 16, color: Color(0xFF7B3F00)),
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
        child: Column(
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
