import 'package:flutter/material.dart';

import 'game_session.dart';

/// 게임 하나를 정의하는 추상 클래스.
///
/// 새 게임을 추가하려면:
/// 1. 이 클래스를 상속한 `XxxGame`을 만들고
/// 2. `lib/games/all_games.dart`의 리스트에 `XxxGame()`을 한 줄 추가하면 끝.
///    → 로비에 자동으로 카드가 늘어난다.
abstract class GameDefinition {
  /// const 하위 클래스(예: 크기별 보글 모드)를 허용하기 위한 const 생성자.
  const GameDefinition();

  /// 고유 식별자 (예: 'chess'). 방의 gameId로 저장된다.
  String get id;

  /// 로비에 표시할 제목.
  String get title;

  /// 한 줄 설명.
  String get subtitle;

  /// 로비 카드 아이콘.
  IconData get icon;

  /// 로비 카드 배경 그라데이션 (2색 이상).
  List<Color> get gradient;

  /// 두 명이 모였을 때 만들어질 초기 동기화 상태.
  ///
  /// [playerIds]는 순서가 보장된다: index 0 = 호스트(먼저), index 1 = 게스트.
  Map<String, dynamic> createInitialState(List<String> playerIds);

  /// 첫 차례 플레이어 id. 기본은 호스트.
  String firstTurn(List<String> playerIds) => playerIds.first;

  /// 인게임 위젯. [session]으로 상태를 구독(`watch`)하고 수를 제출(`submit`)한다.
  Widget buildGame(BuildContext context, GameSession session);
}
