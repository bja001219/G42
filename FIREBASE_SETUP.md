# Firebase 온라인 멀티플레이 설정

G42는 Firebase가 **설정돼 있으면 온라인 대전**, 없으면 자동으로 **로컬(동일 기기 핫시트)**
모드로 실행된다. 아래는 온라인을 켜는 절차다.

## 1. 도구 설치 (최초 1회)

```bash
# Firebase CLI
npm install -g firebase-tools
firebase login

# FlutterFire CLI
dart pub global activate flutterfire_cli
```

`~/.pub-cache/bin` 이 PATH에 있어야 한다.

## 2. Firebase 프로젝트 생성 + 앱 연결

```bash
# (Firebase 콘솔에서 프로젝트를 미리 만들어도 됨: https://console.firebase.google.com)
cd G42
flutterfire configure
```

- 사용할 프로젝트 선택(또는 새로 생성)
- 플랫폼 선택: android / ios / web
- 완료되면 `lib/firebase_options.dart` 와 각 플랫폼 설정 파일이 생성된다.

## 3. `main.dart`에서 옵션 사용 (configure 후)

`flutterfire configure`가 `lib/firebase_options.dart`를 만들면, `lib/main.dart`의
초기화를 다음과 같이 바꾼다:

```dart
import 'firebase_options.dart';
// ...
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

> 파일이 없으면 import에서 컴파일 에러가 나므로, **configure를 먼저** 실행한 뒤 수정한다.
> 수정 전에도 앱은 로컬 모드로 잘 실행된다.

## 4. Firestore 데이터베이스 켜기

Firebase 콘솔 → **Firestore Database** → 데이터베이스 만들기 →
**Native 모드** → 위치 선택.

보안 규칙은 `firestore.rules` 참고(이미 `rooms` + 고스톱 전적용 `profiles`/`headtohead`
규칙 포함). 데모용으로는 다음(개방형)으로 시작할 수 있다:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /rooms/{code}        { allow read, write: if true; } // ⚠ 데모용
    match /profiles/{id}       { allow read, write: if true; } // 고스톱 통산 전적
    match /headtohead/{key}    { allow read, write: if true; } // 고스톱 상대 전적
  }
}
```
> ⚠ 모두 데모/개발용 개방형. 운영 전 Firebase Auth + 본인/당사자 문서만 쓰기,
> 카운터 increment 검증으로 강화할 것.

배포:

```bash
firebase deploy --only firestore:rules
```

## 5. 실행

```bash
flutter run -d chrome      # 웹에서 테스트가 가장 쉽다
# 또는
flutter run                # 연결된 안드로이드/iOS 기기
```

두 기기(또는 두 브라우저 탭)에서 같은 방 코드로 접속하면 실시간 대전이 된다.

## 데이터 구조

```
rooms/{CODE} = {
  code, gameId, status: waiting|playing|finished,
  players: [ {id, name}, ... ],
  hostId, turn, winner,
  state: { ...게임별 동기화 상태... }
}

# 고스톱 전적 (없어도 게임은 동작 — 미설정 시 로컬 저장)
profiles/{playerId}   = { playerId, name, totalScore, wins, losses, rounds, nagari }
headtohead/{pairKey}  = { pairKey, wins:{pid:n}, scores:{pid:n}, rounds, nagari }
```

> 온라인 미설정(로컬 폴백) 상태에서는 전적이 기기 `shared_preferences`에 저장된다.
> Firebase를 켜면 자동으로 Firestore의 위 컬렉션을 사용한다.
