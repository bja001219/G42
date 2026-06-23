# 여러 Claude로 나눠서 작업하기 (역할 분담 프롬프트)

G42는 **공용 골격(로비 · 방 · 동기화)** 이 이미 완성돼 있고, 게임 3개는 서로
**독립된 폴더**(`lib/games/<id>/`)만 건드리므로 **3개의 Claude 세션에서 병렬로** 작업할 수 있다.

> 충돌 방지 규칙: 각 세션은 자기 게임 폴더만 수정한다. `lib/core`, `lib/ui`,
> `lib/main.dart`, `lib/games/all_games.dart` 는 **읽기만** 한다(이미 다 세팅됨).

각 세션에 아래 프롬프트를 그대로 붙여넣으면 된다. 셋 다 먼저
[`docs/GAME_CONTRACT.md`](GAME_CONTRACT.md)를 읽고 그 계약을 100% 따른다.

---

## 🟣 Claude #1 — 체스 (chess)

```
/home/malgnst/pers/G42 Flutter 프로젝트에서 체스 게임을 구현해줘.
먼저 docs/GAME_CONTRACT.md 를 읽고 그 계약(GameDefinition / GameSession / Room / 동기화 규칙)을 100% 지켜.
lib/games/chess/ 폴더 안에서만 작업하고, lib/core·lib/ui·main.dart·all_games.dart 는 읽기만 해.
기존 lib/games/chess/chess_game.dart 의 '../_stub.dart' import 와 ComingSoon 을 제거하고 실제 게임으로 교체해(클래스명 ChessGame, id 'chess'는 유지).

요구사항:
- 완전한 합법수 체스 엔진(순수 Dart): 폰 2칸/대각 잡기/앙파상/프로모션(자동 퀸), 나이트·비숍·룩·퀸·킹, 캐슬링, 자기 킹이 체크되는 수 금지, 체크/체크메이트/스테일메이트 판정.
- state 인코딩: 'board' 64자 String(index=rank*8+file, 0=a8 ... 63=h1, 백 대문자/흑 소문자/빈칸 '.'), 'castling'('KQkq' 부분집합 또는 '-'), 'enPassant'(int, 없으면 -1), 'lastMove'({'from':int,'to':int}). 중첩 배열 금지.
- seat 0(호스트)=백(선공), seat 1=흑. firstTurn=호스트.
- UI: 자기 말이 아래로 보이게 보드 flip, 탭 선택→합법수 하이라이트→이동, 체크 표시, 결과 오버레이+재대국(session.rematch).
- 온라인 2인 + hotseat 양쪽 동작.
- 완료 조건: (cd /home/malgnst/pers/G42 && flutter analyze) 무경고, dart format. 가능하면 test/chess_logic_test.dart(초기 합법수 20개 등) 추가.
```

---

## 🟠 Claude #2 — 오목 (omok)

```
/home/malgnst/pers/G42 Flutter 프로젝트에서 오목 게임을 구현해줘.
먼저 docs/GAME_CONTRACT.md 를 읽고 계약을 100% 지켜.
lib/games/omok/ 폴더 안에서만 작업하고 나머지는 읽기만 해.
기존 lib/games/omok/omok_game.dart 의 '../_stub.dart' import 와 ComingSoon 제거(클래스명 OmokGame, id 'omok' 유지).

요구사항:
- 15x15 자유 5목. state: 'board' 225자 String(index=row*15+col, '.'/'B'/'W'), 'lastMove' int(없으면 -1). 중첩 배열 금지.
- seat 0(호스트)=흑(선공), seat 1=백. firstTurn=호스트(흑).
- 자기 차례에 빈 교차점 탭 → 착수. 가로/세로/대각 5목 이상이면 승리(finished, winner). 보드 가득 차면 draw.
- UI: 우드톤 바둑판 격자 + 화점, 흑/백 돌, 마지막 착수 강조, 결과 오버레이+재대국.
- 온라인 2인 + hotseat 양쪽 동작.
- 완료 조건: flutter analyze 무경고, dart format. 가능하면 승리판정 단위 테스트 추가.
```

---

## 🔵 Claude #3 — 배틀쉽 (battleship)

```
/home/malgnst/pers/G42 Flutter 프로젝트에서 배틀쉽 게임을 구현해줘.
먼저 docs/GAME_CONTRACT.md 를 읽고 계약을 100% 지켜.
lib/games/battleship/ 폴더 안에서만 작업하고 나머지는 읽기만 해.
기존 lib/games/battleship/battleship_game.dart 의 '../_stub.dart' import 와 ComingSoon 제거(클래스명 BattleshipGame, id 'battleship' 유지).

요구사항:
- 10x10, 함선 크기 [5,4,3,2](4척). 각자 함대를 숨기고 번갈아 폭격, 상대 함대 먼저 전멸시키면 승리.
- state(중첩 배열 금지, 전부 평탄 String/Map):
  'phase': 'placing'|'battle'|'finished'
  'boards': {'<playerId>': '100자 String'} ('.'=물, '0'~'3'=함선 인덱스, index=row*10+col)
  'ready': {'<playerId>': bool}
  'shots': {'<playerId>': '100자 String'} (그 사람이 상대에 쏜 결과 '.'/'O'(미스)/'X'(히트))
- seat 0=호스트, firstTurn=호스트. createInitialState: placing, 빈 보드, ready false, shots 미발사.
- placing: 자기 보드에 함선 배치(탭+회전 토글, '랜덤 배치' 버튼), 겹침/범위 검증, 완료 시 ready=true. 항상 최신 room.state에서 내 키만 바꿔 통째로 submit. 둘 다 ready면 phase='battle', turn=호스트.
- battle: 자기 차례에 상대 격자 미발사 칸 탭 → 명중/미스 판정, 명중이어도 턴은 상대로. 상대 함선 칸 전부 명중되면 승리(finished). 격침 안내.
- hotseat: placing 순차 + '기기를 넘기세요' 가림막, battle 턴 전환 시에도 가림막(정보 은닉). session.hotseat / actingPlayerId 활용.
- UI: 내 함대 격자 + 상대 해역 격자 2개, 차례/남은 함선 표시, 결과 오버레이+재대국.
- 완료 조건: flutter analyze 무경고, dart format.
```

---

## 작업 후 통합

세 게임이 모두 끝나면 한 번 더:

```bash
cd /home/malgnst/pers/G42
flutter analyze     # No issues found! 확인
flutter test
dart format lib test
```

새 게임을 더 추가하고 싶으면 `lib/games/<id>/` 를 만들고
`lib/games/all_games.dart` 리스트에 한 줄 추가하면 로비에 자동 등장한다.
