import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g42/app.dart';
import 'package:g42/core/services/identity_service.dart';
import 'package:g42/core/services/local_room_service.dart';
import 'package:g42/core/services/local_score_store.dart';

Widget _app(IdentityService identity) => G42App(
  identity: identity,
  roomService: LocalRoomService(),
  scoreStore: LocalScoreStore(),
  firebaseReady: false,
);

void main() {
  testWidgets('최초 실행이면 로그인(닉네임) 화면이 뜬다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final identity = await IdentityService.load();
    expect(identity.nameConfirmed, isFalse);

    await tester.pumpWidget(_app(identity));
    await tester.pumpAndSettle();

    // 로그인 화면 요소.
    expect(find.text('닉네임을 정해주세요'), findsOneWidget);
    expect(find.text('시작'), findsOneWidget);
    // 홈의 버튼은 아직 없음.
    expect(find.text('방 만들기'), findsNothing);
  });

  testWidgets('닉네임을 입력하고 시작하면 홈(방 만들기/참가)으로 간다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final identity = await IdentityService.load();

    await tester.pumpWidget(_app(identity));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '말간');
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();

    expect(identity.nameConfirmed, isTrue);
    expect(find.text('방 만들기'), findsOneWidget);
    expect(find.text('방 참가'), findsOneWidget);
  });

  testWidgets('이미 닉네임을 확정한 사용자는 곧바로 홈으로 진입한다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'playerId': 'p-1234',
      'playerName': '말간',
      'nameConfirmed': true,
    });
    final identity = await IdentityService.load();
    expect(identity.nameConfirmed, isTrue);

    await tester.pumpWidget(_app(identity));
    await tester.pumpAndSettle();

    // 로그인 화면을 건너뛰고 홈이 보인다.
    expect(find.text('닉네임을 정해주세요'), findsNothing);
    expect(find.text('방 만들기'), findsOneWidget);
    expect(find.text('방 참가'), findsOneWidget);
  });
}
