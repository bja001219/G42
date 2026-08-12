# G42 🎮

**둘이서 즐기는 미니게임 모음** — Flutter 기반, 방을 만들고 상대가 들어오면 온라인으로 대전.

> ⚠️ **데모/포트폴리오 프로젝트.**
> Firebase 익명 인증을 사용하는 데모 수준의 접근 경계이며, 방 멤버별 권한 모델을
> 구현한 운영 서비스는 아닙니다. 재사용할 때는 자신의 Firebase 프로젝트로 설정 파일을
> 재생성하고 `firestore.rules`를 사용자·방 멤버 기준으로 강화해야 합니다.

첫 화면에서 방을 만들거나 코드로 참가하고, 대기실에서 함께 플레이할 게임을 선택합니다.

## 이 프로젝트에서 AI를 사용한 방식

AI 코딩 에이전트는 게임별 정형 구현과 테스트 케이스 확장에 사용했습니다. 저는 먼저
공용 계약(`GameDefinition`, `GameSession`, `RoomService`)과 Firestore 상태 경계를 정하고,
작업 디렉터리를 게임별로 격리한 뒤 결과를 diff·정적 분석·회귀 테스트로 검토했습니다.

특히 동시 탭에 의한 상태 덮어쓰기, 재대국 soft-lock, 연결 단절, 작은 화면 overflow처럼
정상 실행만으로 놓치기 쉬운 조건을 재현 테스트로 고정한 뒤에만 변경을 수용했습니다.
즉 AI에게 구현 속도는 위임했지만, 아키텍처·보안 범위·완료 기준과 최종 수용/반려 판단은
프로젝트 오너가 책임지는 방식입니다.

구체적인 역할 분담, 수용 판정 절차, 알려진 기술 부채는
[`docs/AI_DEVELOPMENT.md`](docs/AI_DEVELOPMENT.md)에 정리했습니다.

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

- **온라인 (Firebase)**: 익명 인증 후 방 코드로 매칭하고 Firestore로 실시간 동기화합니다.
  → [FIREBASE_SETUP.md](FIREBASE_SETUP.md)
- **로컬 폴백**: Firebase 초기화 또는 인증 실패 시 인메모리 `LocalRoomService`로 전환합니다.
  현재 사용자 흐름은 두 기기 온라인 대전을 중심으로 검증했으며, 로컬 구현은 전송 계층
  개발·테스트용 폴백입니다.

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

온라인 대전은 Firebase 콘솔에서 익명 로그인을 활성화한 뒤
[FIREBASE_SETUP.md](FIREBASE_SETUP.md)를 따라 설정할 수 있습니다.

## 검증

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
```

동일한 명령은 [GitHub Actions](.github/workflows/ci.yml)에서도 실행됩니다. 규칙 엔진뿐 아니라
동시 갱신, 재연결, presence, 화면 크기 회귀를 함께 검증합니다.

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
    login_screen.dart        # 최초 닉네임 확정
    home_screen.dart         # 방 만들기 / 코드로 참가
    room_lobby_screen.dart   # 참가자 수락 + 게임 선택
    game_host_screen.dart    # 인게임 컨테이너(상단바 + 게임 위젯)
    stats_screen.dart        # 내 통산 전적 화면
  games/
    chess/  omok/  battleship/  gostop/  ...   # 각 게임 구현
    all_games.dart           # ← 여기에 한 줄 추가하면 로비에 등장
docs/
  GAME_CONTRACT.md           # 게임 구현 계약(필독)
  GOSTOP_RULES.md            # 고스톱(2인 맞고) 룰 사양서
  AI_DEVELOPMENT.md          # AI 위임 범위 + 사람의 수용 판정 절차
  HANDOFF_PROMPTS.md         # 격리된 게임별 작업 입력 예시
```

## 새 게임 추가하기

1. `lib/games/<id>/<id>_game.dart`에 `GameDefinition` 상속 클래스 작성
2. `lib/games/all_games.dart` 리스트에 `XxxGame()` 한 줄 추가
3. 끝 — 로비에 자동으로 카드가 생긴다.

자세한 규칙은 [docs/GAME_CONTRACT.md](docs/GAME_CONTRACT.md) 참고.
