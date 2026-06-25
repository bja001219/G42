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

  /// 인게임 화면을 가로(landscape)로 눕혀서 진행할지 여부.
  ///
  /// true 면 [GameHostScreen]이 게임 시작 시 화면을 가로로 고정한다
  /// (고스톱 등 카드/테이블 게임). 기본은 세로(false). 다른 게임도 이 게터를
  /// true 로 오버라이드하면 한 줄로 가로 모드를 켤 수 있다.
  bool get prefersLandscape => false;

  // ---- 시작 전 방장 설정(옵션) -------------------------------------------------
  // 게임에 따라 시작 전 방장이 옵션을 고를 수 있다(예: 보글의 보드 크기/언어).
  // 설정을 지원하지 않는 게임은 아래 기본 구현을 그대로 쓰며 영향이 없다.

  /// 시작 전 방장이 설정할 옵션이 있으면 true.
  bool get hasSetup => false;

  /// 설정 기본값(설정 지원 게임만 의미 있음). [createInitialStateConfigured]에 전달된다.
  Map<String, dynamic> get defaultConfig => const <String, dynamic>{};

  /// 시작 전 설정 UI. [config]는 현재 설정값(불변 취급)이며, 사용자가 바꾸면
  /// 새 맵을 만들어 [onChanged]로 전달한다. 설정 미지원 게임은 호출되지 않는다.
  Widget buildSetup(
    BuildContext context,
    Map<String, dynamic> config,
    ValueChanged<Map<String, dynamic>> onChanged,
  ) => const SizedBox.shrink();

  /// 설정을 한 줄로 요약(수락 화면/대기 표시용). 예: "6×6 · 한글". 없으면 빈 문자열.
  String configSummary(Map<String, dynamic> config) => '';

  /// 방장 설정([config])을 반영한 초기 상태.
  /// 기본 구현은 설정을 무시하고 [createInitialState]에 위임한다.
  Map<String, dynamic> createInitialStateConfigured(
    List<String> playerIds,
    Map<String, dynamic> config,
  ) => createInitialState(playerIds);

  /// 인게임 위젯. [session]으로 상태를 구독(`watch`)하고 수를 제출(`submit`)한다.
  Widget buildGame(BuildContext context, GameSession session);
}
