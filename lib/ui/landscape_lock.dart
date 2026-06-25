import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 자식(인게임 화면)을 가로(landscape)로 눕혀 보여주는 래퍼.
///
/// [enabled]가 true가 되면:
///   1) 네이티브(Android/iOS)에서는 [SystemChrome.setPreferredOrientations]로
///      화면을 가로로 고정한다 → OS가 앱 전체를 실제로 회전시킨다(안전영역 정상).
///   2) 웹 브라우저 탭처럼 OS 회전이 먹지 않는 환경([rotateFallback])에서는
///      세로 뷰포트일 때 콘텐츠를 90° 회전시켜 항상 가로로 보이게 한다.
///
/// [enabled]가 false면 자식을 그대로 보여주고 방향 고정을 해제한다(세로 복귀).
///
/// 게임마다 새로 push되는 [GameHostScreen] 안에 마운트되므로, 게임을 나가
/// 위젯이 dispose되면 자동으로 방향 고정이 풀린다.
class LandscapeLock extends StatefulWidget {
  /// 가로 고정 활성화 여부(게임의 `prefersLandscape`).
  final bool enabled;

  /// 가로로 보여줄 인게임 화면.
  final Widget child;

  /// 세로 뷰포트일 때 콘텐츠를 회전시켜 강제로 가로처럼 보이게 할지.
  ///
  /// null(기본)이면 웹([kIsWeb])에서만 켜진다. 네이티브는 OS가 실제로 회전하므로
  /// 회전 폴백을 꺼(=중복 회전/깜빡임 방지), 웹은 회전 폴백으로 가로를 흉내 낸다.
  /// 테스트에서 true/false 를 명시적으로 주입할 수 있게 노출한다.
  final bool? rotateFallback;

  const LandscapeLock({
    super.key,
    required this.enabled,
    required this.child,
    this.rotateFallback,
  });

  @override
  State<LandscapeLock> createState() => _LandscapeLockState();
}

class _LandscapeLockState extends State<LandscapeLock> {
  /// 회전 폴백 실제 적용 여부(미지정이면 웹에서만 true).
  bool get _useRotateFallback => widget.rotateFallback ?? kIsWeb;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _lockLandscape();
  }

  @override
  void didUpdateWidget(covariant LandscapeLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _lockLandscape();
      } else {
        _unlock();
      }
    }
  }

  @override
  void dispose() {
    // 게임을 떠나(이 위젯이 사라지면) 세로 자유 회전으로 복귀시킨다.
    if (widget.enabled) _unlock();
    super.dispose();
  }

  void _lockLandscape() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _unlock() {
    // 원래 앱은 방향 고정이 없었으므로 전체 방향 허용으로 되돌린다.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  Widget build(BuildContext context) {
    // 비활성이거나 회전 폴백이 꺼져 있으면(네이티브) 자식을 그대로 — OS가 회전한다.
    if (!widget.enabled || !_useRotateFallback) return widget.child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait = constraints.maxHeight > constraints.maxWidth;
        // 이미 가로 뷰포트면 회전할 필요가 없다.
        if (!isPortrait) return widget.child;

        // 세로 뷰포트 → 콘텐츠를 시계 방향 90° 회전해 가로로 눕힌다.
        // RotatedBox가 자식에 가로 제약(가로↔세로 swap)을 전달하므로, 게임은
        // 가로 캔버스에 레이아웃된 뒤 회전되어 세로 화면을 가득 채운다.
        final media = MediaQuery.of(context);
        return RotatedBox(
          quarterTurns: 1,
          child: MediaQuery(
            // 자식이 보는 화면 크기도 가로(swap)로 맞춰 준다.
            data: media.copyWith(
              size: Size(constraints.maxHeight, constraints.maxWidth),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}
