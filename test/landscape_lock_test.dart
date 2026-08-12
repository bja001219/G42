import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:g42/core/game_registry.dart';
import 'package:g42/games/chess/chess_game.dart';
import 'package:g42/games/gostop/gostop_game.dart';
import 'package:g42/games/omok/omok_game.dart';
import 'package:g42/ui/landscape_lock.dart';

/// 주어진 크기의 박스 안에 [LandscapeLock]을 마운트하고, 자식이 보는
/// MediaQuery 크기를 캡처해 돌려준다.
Future<Size?> _pumpLock(
  WidgetTester tester, {
  required bool enabled,
  required bool rotateFallback,
  required double width,
  required double height,
}) async {
  // 뷰포트 자체를 원하는 크기로 설정해 LayoutBuilder 제약을 결정적으로 만든다.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Size? captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LandscapeLock(
          enabled: enabled,
          rotateFallback: rotateFallback,
          child: Builder(
            builder: (ctx) {
              captured = MediaQuery.of(ctx).size;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  group('LandscapeLock 회전 폴백(웹 경로)', () {
    testWidgets('세로 뷰포트면 콘텐츠를 90° 회전해 가로로 눕힌다', (tester) async {
      final size = await _pumpLock(
        tester,
        enabled: true,
        rotateFallback: true,
        width: 400, // 세로(높이 > 너비)
        height: 800,
      );

      // RotatedBox 가 끼어들어 콘텐츠가 회전된다.
      expect(find.byType(RotatedBox), findsOneWidget);
      // 자식은 가로(가로↔세로 swap)로 본다: 800 x 400.
      expect(size, const Size(800, 400));
    });

    testWidgets('이미 가로 뷰포트면 회전하지 않는다', (tester) async {
      await _pumpLock(
        tester,
        enabled: true,
        rotateFallback: true,
        width: 800, // 가로(너비 > 높이)
        height: 400,
      );
      expect(find.byType(RotatedBox), findsNothing);
    });

    testWidgets('비활성(enabled=false)이면 회전하지 않는다', (tester) async {
      await _pumpLock(
        tester,
        enabled: false,
        rotateFallback: true,
        width: 400,
        height: 800,
      );
      expect(find.byType(RotatedBox), findsNothing);
    });
  });

  testWidgets('네이티브 경로(rotateFallback=false)는 세로라도 회전하지 않는다(OS가 회전)', (
    tester,
  ) async {
    await _pumpLock(
      tester,
      enabled: true,
      rotateFallback: false,
      width: 400,
      height: 800,
    );
    expect(find.byType(RotatedBox), findsNothing);
  });

  testWidgets('활성화되면 화면을 가로로 고정 요청한다(SystemChrome)', (tester) async {
    final orientationCalls = <List<String>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientationCalls.add((call.arguments as List).cast<String>());
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpLock(
      tester,
      enabled: true,
      rotateFallback: false,
      width: 800,
      height: 400,
    );

    // 가로 방향(landscapeLeft/Right)으로 고정 요청이 들어가야 한다.
    expect(orientationCalls, isNotEmpty);
    final last = orientationCalls.last;
    expect(last, contains('DeviceOrientation.landscapeLeft'));
    expect(last, contains('DeviceOrientation.landscapeRight'));
    expect(last, isNot(contains('DeviceOrientation.portraitUp')));
  });

  group('게임별 prefersLandscape 플래그', () {
    test('고스톱은 가로 모드를 선호한다', () {
      expect(GoStopGame().prefersLandscape, isTrue);
    });

    test('체스/오목 등 보드 게임은 세로(기본)다', () {
      expect(ChessGame().prefersLandscape, isFalse);
      expect(OmokGame().prefersLandscape, isFalse);
    });

    test('가로 선호 게임은 고스톱뿐이다(현재)', () {
      final landscapeGames = GameRegistry.games
          .where((g) => g.prefersLandscape)
          .toList();
      expect(landscapeGames.map((g) => g.id), <String>['gostop']);
    });
  });
}
