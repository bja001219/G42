import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'core/services/identity_service.dart';
import 'core/services/room_service.dart';
import 'core/services/firebase_room_service.dart';
import 'core/services/local_room_service.dart';
import 'core/services/score_store.dart';
import 'core/services/firebase_score_store.dart';
import 'core/services/local_score_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 온라인 저장소는 인증이 완료된 경우에만 사용한다. Firebase 초기화만 성공하고
  // 인증이 실패한 상태에서 Firestore를 사용하면 보안 규칙을 개방해야 하므로,
  // 실패 시에는 명시적으로 로컬 구현으로 폴백한다.
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    firebaseReady = true;
    debugPrint('G42 온라인 모드 ON (Firebase 초기화 + 익명 인증 성공)');
  } catch (e) {
    debugPrint('Firebase 초기화/인증 실패 → 로컬 모드로 폴백합니다: $e');
  }

  final identity = await IdentityService.load();
  final RoomService roomService = firebaseReady
      ? FirebaseRoomService()
      : LocalRoomService();
  final ScoreStore scoreStore = firebaseReady
      ? FirebaseScoreStore()
      : LocalScoreStore();

  runApp(
    G42App(
      identity: identity,
      roomService: roomService,
      scoreStore: scoreStore,
      firebaseReady: firebaseReady,
    ),
  );
}
