# G42 🎮

**둘이서 즐기는 미니게임 모음** — Flutter 기반, 방을 만들고 상대가 들어오면 온라인으로 대전.

첫 화면은 **게임 선택 로비**다. 게임을 하나 추가할 때마다(`all_games.dart`에 한 줄)
로비에 카드가 자동으로 늘어난다.

## 수록 게임

| 게임 | 설명 |
|------|------|
| ♟️ **체스** | 클래식 2인 전략. 합법수/체크/체크메이트/캐슬링/앙파상 (perft 검증 완료) |
| ⚫ **오목** | 15×15, 5목을 먼저 만들면 승리 |
| 🚢 **배틀쉽** | 10×10에 함선(5·4·3·2칸)을 숨기고 번갈아 폭격, 먼저 전멸시키면 승리 |
| ⚡ **반응속도** | 초록 불에 먼저 반응하면 라운드 승, 베스트 오브 N |
| ♠️ **블랙잭** | 21에 더 가까운 사람이 승리 (2인 헤드투헤드) |
| 🃏 **원카드** | 무늬·숫자 맞춰 내고, 카드를 먼저 다 내면 승리 |
| 🔠 **보글** | 4×4 글자판에서 제한시간 동안 영어 단어를 더 많이 찾기 |
| 🔠 **보글 (한글)** | 한글 음절판에서 제한시간 동안 한글 단어를 더 많이 찾기 (한글 사전 6만 단어 내장) |
| 🎴 **고스톱 (맞고)** | 2인 맞고. 화투 48장+보너스패, 7점 룰, 고/스톱·박·뻑·따닥·쪽·쓸기·흔들기·폭탄·총통·나가리. 실제 화투 이미지. **통산/전적 영구 저장** |

## 멀티플레이

- **온라인 (Firebase)**: 방 코드로 매칭, Firestore로 실시간 동기화. → [FIREBASE_SETUP.md](FIREBASE_SETUP.md)
- **로컬 폴백**: Firebase가 설정 안 돼 있으면 자동으로 **동일 기기 핫시트**(한 화면에서 둘이 번갈아) 모드로 실행.
  설정 없이도 앱이 바로 켜지고 모든 게임을 플레이할 수 있다.

전송 계층은 `RoomService` 인터페이스로 추상화돼 있어, 게임 로직 수정 없이
Firebase / 로컬 / (향후) WebSocket 구현을 갈아끼울 수 있다.

## 실행

```bash
cd G42
flutter pub get

# 가장 쉬운 테스트: 웹
flutter run -d chrome

# 또는 연결된 기기
flutter run
```

Firebase 미설정 상태면 로비 상단에 "로컬" 배지가 뜨고 핫시트로 즐길 수 있다.
온라인 대전은 [FIREBASE_SETUP.md](FIREBASE_SETUP.md)를 따라 켤 수 있다.

## 구조

```
lib/
  main.dart                  # 진입점: Firebase 초기화 시도 → 서비스 선택
  app.dart                   # 앱 루트 + AppServices(DI)
  theme.dart                 # 다크 테마 / 색상
  core/
    game_definition.dart     # 게임 1개 = 클래스 1개 (추상)
    game_session.dart        # 게임 ↔ 방 동기화 다리 (watch / submit)
    game_registry.dart       # 등록된 게임 목록
    models/room.dart         # Room / RoomPlayer / 상태 모델
    services/
      room_service.dart      # 전송 계층 추상 인터페이스
      firebase_room_service.dart  # 온라인 (Firestore)
      local_room_service.dart     # 로컬 핫시트 폴백
      identity_service.dart  # 로컬 플레이어 id / 닉네임
      score_store.dart       # 통산/전적 저장 추상 (+ firebase_/local_ 구현)
  ui/
    lobby_screen.dart        # 게임 선택 로비 (+ 전적 버튼)
    room_screen.dart         # 방 만들기 / 코드로 참가
    game_host_screen.dart    # 인게임 컨테이너(상단바 + 게임 위젯)
    stats_screen.dart        # 내 통산 전적 화면
  games/
    chess/  omok/  battleship/  gostop/  ...   # 각 게임 구현
    all_games.dart           # ← 여기에 한 줄 추가하면 로비에 등장
docs/
  GAME_CONTRACT.md           # 게임 구현 계약(필독)
  GOSTOP_RULES.md            # 고스톱(2인 맞고) 룰 사양서
  HANDOFF_PROMPTS.md         # 게임별 작업 프롬프트(여러 Claude로 분담용)
```

## 새 게임 추가하기

1. `lib/games/<id>/<id>_game.dart`에 `GameDefinition` 상속 클래스 작성
2. `lib/games/all_games.dart` 리스트에 `XxxGame()` 한 줄 추가
3. 끝 — 로비에 자동으로 카드가 생긴다.

자세한 규칙은 [docs/GAME_CONTRACT.md](docs/GAME_CONTRACT.md) 참고.
