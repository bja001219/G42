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

  // Firebase 초기화 시도. firebase_options(또는 google-services 설정)이 없으면
  // 예외가 나는데, 그 경우 로컬(동일 기기 핫시트) 모드로 폴백한다.
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // 익명 인증: Firestore 규칙이 인증된 사용자만 허용하므로, 온라인 모드는
    // 시작 시 익명 로그인해 uid를 확보한다(외부의 무단 DB 접근 차단).
    // provider가 아직 안 켜졌거나 실패하면 firebaseReady=false로 로컬 폴백.
    await FirebaseAuth.instance.signInAnonymously();
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase 초기화/익명 인증 실패 → 로컬 모드로 폴백합니다: $e');
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
