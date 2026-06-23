import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g42/app.dart';
import 'package:g42/core/services/identity_service.dart';
import 'package:g42/core/services/local_room_service.dart';

void main() {
  testWidgets('로비에 등록된 게임 카드가 표시된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final identity = await IdentityService.load();

    await tester.pumpWidget(
      G42App(
        identity: identity,
        roomService: LocalRoomService(),
        firebaseReady: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('체스'), findsOneWidget);
    expect(find.text('오목'), findsOneWidget);
    expect(find.text('배틀쉽'), findsOneWidget);
  });
}
