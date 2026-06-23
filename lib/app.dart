import 'package:flutter/material.dart';

import 'core/services/identity_service.dart';
import 'core/services/room_service.dart';
import 'core/services/score_store.dart';
import 'ui/lobby_screen.dart';
import 'theme.dart';

/// 앱 루트.
class G42App extends StatelessWidget {
  final IdentityService identity;
  final RoomService roomService;
  final ScoreStore scoreStore;
  final bool firebaseReady;

  const G42App({
    super.key,
    required this.identity,
    required this.roomService,
    required this.scoreStore,
    required this.firebaseReady,
  });

  @override
  Widget build(BuildContext context) {
    return AppServices(
      identity: identity,
      roomService: roomService,
      scoreStore: scoreStore,
      firebaseReady: firebaseReady,
      child: MaterialApp(
        title: 'G42',
        debugShowCheckedModeBanner: false,
        theme: g42Theme(),
        home: const LobbyScreen(),
      ),
    );
  }
}

/// 전역 서비스 주입용 InheritedWidget (가벼운 DI).
///
/// 어디서든 `AppServices.of(context).roomService` 형태로 접근.
class AppServices extends InheritedWidget {
  final IdentityService identity;
  final RoomService roomService;
  final ScoreStore scoreStore;
  final bool firebaseReady;

  const AppServices({
    super.key,
    required this.identity,
    required this.roomService,
    required this.scoreStore,
    required this.firebaseReady,
    required super.child,
  });

  static AppServices of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(widget != null, 'AppServices가 위젯 트리에 없습니다.');
    return widget!;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) =>
      identity != oldWidget.identity ||
      roomService != oldWidget.roomService ||
      scoreStore != oldWidget.scoreStore ||
      firebaseReady != oldWidget.firebaseReady;
}
