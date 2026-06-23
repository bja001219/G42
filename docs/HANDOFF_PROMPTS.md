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

---

# 2차: 추가 게임 4종 (3-Claude 분담)

반응속도 · 블랙잭 · 원카드 · 보글을 3개의 Claude 세션으로 나눠 작업한다.
4개 게임을 3명에게 균형 있게 배분: A가 가벼운 둘(반응속도+블랙잭), B·C가 무거운 하나씩.

> 충돌 방지: 각 세션은 배정된 게임 폴더만 수정. `core/ui/main/all_games.dart`는 읽기만.
> (예외: 보글 세션만, 사전을 에셋으로 쓸 경우 `pubspec.yaml`의 assets 섹션 수정 허용.)
> 셋 다 먼저 `docs/GAME_CONTRACT.md`를 읽고 따른다. 기존 `lib/games/chess`·`battleship`을 예시로 참고.

## ⚡♠️ Claude A — 반응속도 + 블랙잭

```
/home/malgnst/pers/G42 에서 두 게임을 구현해줘. 먼저 docs/GAME_CONTRACT.md 준수.
lib/games/reaction/ 와 lib/games/blackjack/ 안에서만 작업, 나머지는 읽기만.
각 _stub.dart import/ComingSoon 제거(클래스 ReactionGame/BlackjackGame, id 'reaction'/'blackjack' 유지).

[반응속도] 베스트 오브 5. 무작위 지연 후 빨강→초록 전환, 더 빨리 반응한 사람이 라운드 승.
레이턴시 공정성: 각자 '내 화면 초록 렌더→내 탭'의 로컬 반응시간(ms)을 측정해 state에 기록 후 비교.
부정출발(초록 전 탭)=라운드 패. state: phase/round/wins{pid}/reaction{pid:ms}. 호스트가 라운드 진행 주도.
hotseat는 순차 측정+가림막. UI: 큰 반응 패널, 라운드 스코어, ms 표시, 결과+재대국.

[블랙잭] 2인 헤드투헤드(딜러 없음). 각자 hit/stand, 버스트=패, 살아있으면 21에 가까운 쪽 승, 동점 push.
덱 52장 셔플 순서를 state에 평탄 리스트로, hand는 카드 리스트, A=1/11 유연. 턴제(room.turn).
라운드 점수 누적. blackjack_logic.dart 분리 + 단위테스트. 완료조건: flutter analyze 무경고.
```

## 🃏 Claude B — 원카드

```
/home/malgnst/pers/G42 에서 원카드를 구현해줘. docs/GAME_CONTRACT.md 준수.
lib/games/onecard/ 안에서만 작업. _stub 제거(클래스 OneCardGame, id 'onecard' 유지).

Uno류. 52장, 각자 7장. 버린 더미 top과 무늬 또는 숫자 일치 카드 내기, 못 내면 1장 뽑고 턴 종료.
손패 먼저 비우면 승리. 특수카드(고정 룰, 인게임 도움말 표시):
 2=다음 사람 2장(2로 누적 가능), A=스킵(2인이라 한번 더), 7=무늬 변경(와일드), 그 외 일반.
드로우 더미 소진 시 버린 더미 섞어 재활용. state: deck[]/discardTop/activeSuit/hands{pid:[]}/pending.
카드는 'H7','SA','D10' 문자열. 상대 손패는 장수만 표시, hotseat는 가림막.
onecard_logic.dart 분리 + 단위테스트(합법수/2 누적/7 무늬변경/승리). 완료조건: flutter analyze 무경고.
```

## 🔠 Claude C — 보글

```
/home/malgnst/pers/G42 에서 보글(영어 글자판 단어찾기)을 구현해줘. docs/GAME_CONTRACT.md 준수.
lib/games/boggle/ 안에서만 작업(사전을 에셋으로 쓸 경우 pubspec.yaml assets 섹션만 예외 허용+pub get).
_stub 제거(클래스 BoggleGame, id 'boggle' 유지).

4x4 글자판. 인접 8방향으로 글자 이어 단어 만들기(같은 칸 재사용 금지). 제한시간 90초 동안 점수 많은 사람 승.
점수: 3~4자=1,5=2,6=3,7=5,8+자=11. 검증: 보드 인접경로 + 사전 등재 + 미제출 + 3자 이상.
사전은 boggle_words.dart에 Set<String> 내장(원하면 /usr/share/dict/words에서 3~8자 영단어 추출).
state: grid(16자)/deadlineMillis 또는 phase/found{pid:[]}/scores{pid}. 온라인은 같은 판 동시, 각자 로컬 90초.
hotseat는 순차+가림막. 시간 종료 시 점수 비교 finished+winner(동점 draw)+재대국.
boggle_logic.dart(경로검증/점수/사전) 분리 + 단위테스트. 완료조건: flutter analyze 무경고.
```

---

# 3차: 한계 항목 업그레이드 (3-Claude 분담)

> 참고: 이 게임들은 **이미 다 만들어져 동작**한다. 아래는 의도적으로 단순화했던 부분을
> "정식 버전"으로 끌어올리는 선택적 업그레이드 작업이다.
> (반응속도의 2폰 시계 동기화 이슈는 이미 수정 완료 — 각 기기 로컬 기준 지연으로 변경.)
> 각 세션은 배정 폴더만 수정, 나머지는 읽기만. 먼저 `docs/GAME_CONTRACT.md`를 읽는다.

## 🃏 Claude 1 — 원카드 조커 정식 활성화

```
/home/malgnst/pers/G42 에서 원카드 조커를 정식 활성화해줘. docs/GAME_CONTRACT.md 준수.
lib/games/onecard/ 안에서만 작업, 나머지는 읽기만.
- OneCardGame.useJokers 를 true 로 바꿔 조커 2장(JR/JB)을 덱에 포함.
- onecard_logic.dart는 이미 조커 공격 +5 / 조커-전용 방어(2와 혼합 금지) 지원 — onecard_view.dart에서
  조커 표시, 낼 수 있는 카드 강조, 공격 누적(pending/attackKind 'joker') 처리, '조커로만 방어' 안내가
  제대로 동작하는지 확인하고 빠진 UI를 구현.
- 조커는 무늬가 없으므로 낼 때 다음 유효 무늬(activeSuit)를 어떻게 정할지 규칙을 정해 구현
  (권장: 조커도 와일드 — 낸 사람이 무늬 지정). 인게임 규칙 도움말 갱신.
- onecard_logic_test.dart에 조커 시나리오 테스트 추가(조커 공격/조커로만 방어/조커 후 무늬 지정).
- 완료조건: cd /home/malgnst/pers/G42 && flutter analyze 무경고, flutter test 통과, dart format.
```

## ♠️ Claude 2 — 블랙잭 정식 룰 확장

```
/home/malgnst/pers/G42 에서 블랙잭을 정식 룰에 가깝게 확장해줘. docs/GAME_CONTRACT.md 준수.
lib/games/blackjack/ 안에서만 작업, 나머지는 읽기만. 기존 2인 헤드투헤드 구조 유지.
- 칩 베팅: 각자 시작 칩, 라운드마다 베팅 → 승자 획득(무승부 push 환수). 칩 0이면 매치 종료(winner).
- 더블다운(한 장만 받고 베팅 2배), 내추럴 블랙잭(2장 21) 보너스(예 1.5배). 가능하면 스플릿도.
- blackjack_logic.dart에 베팅/배당/더블다운/내추럴 판정 순수 함수 + 단위테스트 추가.
- blackjack_view.dart에 베팅 UI, 더블다운 버튼, 칩 잔고 표시. 온라인+hotseat 양쪽, _freshState 패턴.
- 완료조건: flutter analyze 무경고, flutter test 통과, dart format.
```

## 🔠 Claude 3 — 보글 한글 모드

```
/home/malgnst/pers/G42 에서 보글에 한글 모드를 추가해줘. docs/GAME_CONTRACT.md 준수.
lib/games/boggle/ 안에서만 작업(한글 사전을 에셋으로 쓰면 pubspec.yaml assets 섹션만 예외 허용+pub get).
- 한글 글자판: 권장은 '음절 타일' 방식(가/나/다... 자주 쓰는 음절 가중)으로 인접 음절을 이어 단어 만들기.
  자모 조합 방식은 난이도 높음 — 택1하고 문서화.
- 한글 사전: 표준 한국어 단어 목록을 boggle_words_ko.dart(Set<String>) 또는 에셋으로 내장(2글자+ 명사 위주).
- 영어/한글 모드 선택: BoggleGame에 모드 옵션 또는 별도 BoggleKoGame 등록(기존 영어 모드 유지).
  ※ 별도 등록 시 lib/games/all_games.dart 한 줄 추가는 예외 허용.
- boggle_logic.dart의 경로검증/점수는 재사용, 사전/보드 생성만 한글용으로 분기. 점수표는 한글에 맞게 조정.
- boggle_logic_test.dart에 한글 경로/사전 테스트 추가. 한글 폰트 렌더 확인.
- 완료조건: flutter analyze 무경고, flutter test 통과, dart format.
```
