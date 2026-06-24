import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

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

  // 온라인 여부는 **Firebase 초기화 성공만으로** 결정한다.
  // (익명 인증은 best-effort — 실패해도 온라인 모드를 유지한다. 익명 인증을
  //  온라인 판정에 묶으면, 웹에서 signInAnonymously가 실패할 때 앱 전체가
  //  로컬 모드로 떨어져 다른 기기끼리 방이 안 보이는 문제가 생긴다.)
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
    debugPrint('G42 온라인 모드 ON (Firebase 초기화 성공)');
  } catch (e) {
    debugPrint('Firebase 초기화 실패 → 로컬 모드로 폴백합니다: $e');
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
