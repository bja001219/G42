# G42 게임 구현 계약 (Game Contract)

모든 게임은 이 계약만 지키면 **로비 · 방 생성/참가 · 온라인 동기화 · 핫시트 폴백**에
자동으로 통합된다. 게임 구현자는 게임 규칙과 UI에만 집중하면 된다.

---

## 1. 폴더 / 파일 규칙

- `lib/games/<id>/<id>_game.dart` : `GameDefinition`을 상속한 클래스 **정확히 1개** (필수)
- 같은 폴더에 로직/위젯 파일을 자유롭게 추가 (예: `<id>_logic.dart`, `<id>_board.dart`)
- 등록은 `lib/games/all_games.dart` 리스트에 이미 되어 있음 (수정 불필요)
- **`import '../_stub.dart';` 와 `ComingSoon` 사용을 제거**할 것

---

## 2. 구현할 인터페이스: `GameDefinition`
파일: `lib/core/game_definition.dart`

```dart
abstract class GameDefinition {
  String get id;            // 'chess' (방의 gameId로 저장)
  String get title;         // '체스'
  String get subtitle;      // 한 줄 설명
  IconData get icon;        // 로비 카드 아이콘
  List<Color> get gradient; // 로비 카드 배경 그라데이션
  Map<String, dynamic> createInitialState(List<String> playerIds); // index0=호스트
  String firstTurn(List<String> playerIds) => playerIds.first;     // 첫 차례
  Widget buildGame(BuildContext context, GameSession session);
}
```

---

## 3. 핵심 도구: `GameSession`
파일: `lib/core/game_session.dart`

```dart
Stream<Room> watch();                              // 방 실시간 구독 (StreamBuilder)
bool isMyTurn(Room room);                           // 핫시트면 항상 true
String actingPlayerId(Room room);                   // 지금 내가 조작하는 playerId
bool hotseat;                                        // 동일 기기 2인 모드 여부
int seatIndex(Room room, String playerId);          // 0=호스트, 1=게스트
RoomPlayer? opponentOf(Room room, String playerId);
Future<void> submit(Map<String,dynamic> state, {String? nextTurn, RoomStatus? status, String? winner});
Future<void> rematch(Map<String,dynamic> freshState, String firstTurn);
```

## 4. 동기화 상태: `Room`
파일: `lib/core/models/room.dart`

```dart
Map<String,dynamic> state;   // 게임별 동기화 상태 (핵심)
String? turn;                // 현재 차례 playerId
String? winner;              // 승자 playerId / 'draw' / null(진행중)
RoomStatus status;           // waiting | playing | finished
List<String> playerIds;      // [호스트, 게스트]
List<RoomPlayer> players;
RoomPlayer? opponentOf(String id);
RoomPlayer? playerById(String id);
```

---

## 5. 동기화 규칙 (반드시 준수)

1. **state는 항상 통째로 제출**한다. `session.submit(newWholeState, ...)`. 부분 갱신 금지.
2. **Firestore JSON 제약**: state에는 String / num / bool / List / Map(String 키)만 담는다.
   - ❗ **중첩 배열(List 안의 List) 금지.** 2D 보드는 **평탄화된 List**나 **단일 String**으로 인코딩.
   - playerId를 키로 갖는 Map은 허용. 예: `{'boards': {'<id>': '..100자..'}}`
3. 수를 둘 때: `submit(state, nextTurn: <상대 playerId>)`. 종료 시 `status`/`winner`도 함께.
4. **턴 게이팅**: 입력 핸들러 맨 앞에서 `if (!session.isMyTurn(room)) return;`
5. **내 진영 판별**:
   ```dart
   final me = session.actingPlayerId(room);
   final seat = session.seatIndex(room, me); // 0 or 1 → 색/선공 결정
   ```
6. **게임 종료**: `submit(state, status: RoomStatus.finished, winner: <id 또는 'draw'>)`
7. **재대국**: 종료 오버레이에서
   `session.rematch(createInitialState(room.playerIds), firstTurn(room.playerIds))`
8. **핫시트**: `session.hotseat == true`면 한 화면에서 양쪽을 조작.
   - 차례는 `room.turn` 기준으로 표시.
   - 정보 은닉이 필요한 게임(배틀쉽)은 차례 전환 시 "기기를 넘기세요" 가림막을 끼운다.

---

## 6. `buildGame` 표준 패턴

```dart
@override
Widget buildGame(BuildContext context, GameSession session) {
  return StreamBuilder<Room>(
    stream: session.watch(),
    builder: (context, snap) {
      final room = snap.data;
      if (room == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return MyBoard(session: session, room: room); // StatefulWidget 권장
    },
  );
}
```

- 동기화 상태는 `room.state`에서만 읽는다.
- 위젯의 **로컬 임시 상태**(선택된 칸, 배치 중인 함선 등)는 StatefulWidget의 State에 둔다.

---

## 7. 품질 기준 (Definition of Done)

- [ ] `flutter analyze` → **No issues**
- [ ] `dart format lib/games/<id>`
- [ ] 차례/승패가 화면에 명확히 표시 (색맹 배려: 색 + 라벨/아이콘)
- [ ] 승리/무승부 시 결과 오버레이 + **재대국** 버튼
- [ ] 온라인 2인 + 핫시트 양쪽에서 동작
- [ ] state에 중첩 배열 없음 (Firestore 안전)
