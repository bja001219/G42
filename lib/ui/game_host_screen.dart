import 'package:flutter/material.dart';

import '../app.dart';
import '../core/game_registry.dart';
import '../core/game_session.dart';
import '../core/models/head_to_head.dart';
import '../core/models/room.dart';
import '../theme.dart';
import 'landscape_lock.dart';

/// 인게임 화면 컨테이너. 상단 바(게임 제목 / 방 코드 / 나가기) + 실제 게임 위젯.
///
/// 게임 종류는 room.gameId 로 동적으로 조회한다(GameHostScreen은 특정 게임을
/// 알지 못한다). 온라인 전용이므로 session.hotseat 은 항상 false다.
///
/// 매 게임마다 새로 push되는 StatefulWidget이라, [initState]에서 기록한
/// 게임 시작 시각이 게임마다 자연히 리셋된다(30초 기권 판정 기준).
class GameHostScreen extends StatefulWidget {
  final GameSession session;

  const GameHostScreen({super.key, required this.session});

  @override
  State<GameHostScreen> createState() => _GameHostScreenState();
}

class _GameHostScreenState extends State<GameHostScreen> {
  GameSession get session => widget.session;

  /// 게임 시작 시각(이 화면 진입 시점 = status==playing 진입). 30초 기권 기준.
  late final DateTime _startedAt;

  /// 중앙 전적 기록 in-flight 가드(중복 기록 방지). recorded 표식이 전파되기
  /// 전에 다음 프레임이 또 기록을 시도하는 것을 막는다.
  bool _recordInFlight = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
  }

  /// 라운드 종료 시 전적을 게임 무관하게 중앙에서 1회 기록한다(§B).
  ///
  /// 트리거 조건: status==finished && winner!=null && room.state["recorded"]!=true.
  /// 처리 주체(중복 방지):
  ///   - 승부(winner != "draw"): 승자 클라이언트(myPlayerId == winner)만 기록.
  ///   - 무승부(winner == "draw"): 호스트(hostId) 클라이언트가 recordNagari.
  /// 기록 성공 시 room.state["recorded"]=true 로 갱신(기존 state 보존)하여 잠근다.
  Future<void> _maybeRecordRound(Room room) async {
    if (_recordInFlight) return;
    if (room.status != RoomStatus.finished) return;
    if (room.state['recorded'] == true) return;
    final winner = room.winner;
    if (winner == null || winner.isEmpty) return;
    // 상대 퇴장으로 한 명만 남은 방은 기록 대상이 아니다(기권은 _leave 에서 처리).
    if (!room.isFull) return;

    final services = AppServices.of(context);
    final me = session.myPlayerId;
    final ids = room.playerIds;
    if (ids.length < 2) return;

    if (winner == 'draw') {
      // 무승부: 호스트만 기록.
      if (me != room.hostId) return;
      final aId = ids[0];
      final bId = ids[1];
      _recordInFlight = true;
      try {
        await services.scoreStore.recordNagari(
          idA: aId,
          nameA: room.playerById(aId)?.name ?? '플레이어',
          idB: bId,
          nameB: room.playerById(bId)?.name ?? '플레이어',
          gameId: room.gameId,
        );
        await _markRecorded(room);
      } catch (_) {
        // 기록 실패: recorded 미설정 → 다음 프레임 재시도.
      } finally {
        _recordInFlight = false;
      }
      return;
    }

    // 승부: 승자 클라이언트만 기록.
    if (me != winner) return;
    final loser = room.opponentOf(winner);
    if (loser == null) return;
    final score = (room.state['roundScore'] as num?)?.toInt() ?? 1;
    _recordInFlight = true;
    try {
      await services.scoreStore.recordRound(
        winnerId: winner,
        winnerName: room.playerById(winner)?.name ?? '플레이어',
        loserId: loser.id,
        loserName: loser.name,
        score: score,
        gameId: room.gameId,
      );
      await _markRecorded(room);
    } catch (_) {
      // 기록 실패: recorded 미설정 → 다음 프레임 재시도.
    } finally {
      _recordInFlight = false;
    }
  }

  /// 기존 state 를 보존하면서 recorded 표식만 추가해 잠근다.
  Future<void> _markRecorded(Room room) {
    final newState = Map<String, dynamic>.from(room.state);
    newState['recorded'] = true;
    return AppServices.of(
      context,
    ).roomService.updateRoom(session.roomCode, {'state': newState});
  }

  /// 완전 퇴장: 방을 떠나고 홈까지 돌아간다.
  ///
  /// status==playing 이고 시작 후 30초가 지났으면 기권 처리(상대 +1점 기록 +
  /// 기권 표식)한 뒤 나간다. 30초 미만이면 페널티 없이 일반 확인 후 나간다.
  Future<void> _leave(BuildContext context, Room room) async {
    final services = AppServices.of(context);
    final navigator = Navigator.of(context);

    final isPlaying = room.status == RoomStatus.playing;
    final elapsed = DateTime.now().difference(_startedAt);
    final isForfeit = isPlaying && elapsed.inSeconds >= 30;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: G42Colors.surface,
        title: Text(isForfeit ? '게임 기권' : '게임 나가기'),
        content: Text(
          isForfeit
              ? '지금 나가면 상대에게 1점이 들어가요. 나갈까요?'
              : '방에서 나갈까요? 상대방의 게임도 종료됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속하기'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: G42Colors.bad),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (isForfeit) {
      final me = session.myPlayerId;
      final opp = room.opponentOf(me);
      if (opp != null) {
        final myName = room.playerById(me)?.name ?? '나';
        // (a) 상대에게 1점 기록(이 게임 전적). 기권은 즉시 leaveRoom 으로 방이
        //     사라지므로 recorded 가드 없이 나가는 클라이언트가 1회만 기록한다.
        await services.scoreStore.recordRound(
          winnerId: opp.id,
          winnerName: opp.name,
          loserId: me,
          loserName: myName,
          score: 1,
          gameId: room.gameId,
        );
        // (b) 기권 표식(기존 state 보존 후 키 추가).
        final newState = Map<String, dynamic>.from(room.state);
        newState['forfeit'] = true;
        newState['forfeitWinnerId'] = opp.id;
        await services.roomService.updateRoom(session.roomCode, {
          'state': newState,
        });
      }
    }

    // (c) 방 떠나기.
    await services.roomService.leaveRoom(session.roomCode, session.myPlayerId);
    // (d) 홈까지 한 번에 복귀. popUntil은 루트까지 멱등이라 대기실 watcher의
    //     자동 복귀(popUntil)와 겹쳐도 빈 화면/중복 pop이 나지 않는다.
    if (!mounted) return;
    navigator.popUntil((r) => r.isFirst);
  }

  /// "같은 게임 한 판 더": 같은 게임을 재제안한다. status=waiting로 가면 양쪽이
  /// 대기실로 빠져나오고, 상대는 [참가]/[거절]을 본다. 수락하면 호스트가 startGame.
  Future<void> _rematchSameGame(BuildContext context, Room room) async {
    final services = AppServices.of(context);
    final newState = <String, dynamic>{
      'accept': 'pending',
      'proposedBy': session.myPlayerId,
    };
    // 게임 설정(config)이 있었다면 보존한다.
    final config = room.state['config'];
    if (config != null) newState['config'] = config;
    await services.roomService.updateRoom(session.roomCode, {
      'status': RoomStatus.waiting.name,
      'gameId': room.gameId,
      'turn': null,
      'winner': null,
      'state': newState,
    });
  }

  /// "게임 선택으로": 방을 비워 양쪽 대기실 picker로 보낸다.
  Future<void> _backToPicker(BuildContext context) async {
    final services = AppServices.of(context);
    await services.roomService.updateRoom(session.roomCode, {
      'status': RoomStatus.waiting.name,
      'gameId': '',
      'turn': null,
      'winner': null,
      'state': <String, dynamic>{},
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 게임 중엔 뒤로가기로 빠져나가지 못하게 막는다(상단바 '나가기'만 허용).
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: StreamBuilder<Room>(
            stream: session.watch(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final room = snap.data!;

              // 라운드 종료 전적 기록(게임 무관 중앙화). 빌드 중 부작용을 피하려
              // 다음 프레임에 호출한다. 가드(_recordInFlight + state.recorded)로 1회만.
              if (room.status == RoomStatus.finished &&
                  room.winner != null &&
                  room.state['recorded'] != true) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _maybeRecordRound(room);
                });
              }

              final game = room.gameId.isEmpty
                  ? null
                  : GameRegistry.byId(room.gameId);

              // 고스톱처럼 가로로 진행하는 게임이면 화면을 가로로 눕힌다.
              // (LandscapeLock 을 트리에 항상 두어 enabled 변화가 didUpdateWidget
              //  으로 반영되게 한다 — 게임 종료/선택 화면으로 돌아가면 세로 복귀.)
              final wantsLandscape = game?.prefersLandscape ?? false;

              final Widget content = game == null
                  ? _waiting(context, room)
                  : Stack(
                      children: [
                        Column(
                          children: [
                            _topBar(context, room, game.title, game.icon),
                            _opponentBar(context, room),
                            Expanded(child: game.buildGame(context, session)),
                          ],
                        ),
                        // 정상 종료(둘 다 남아있음)면 통합 결과/프롬프트 풀 오버레이로
                        // 게임 위젯의 자체 결과/재대국 UI를 덮는다.
                        if (room.status == RoomStatus.finished && room.isFull)
                          _resultOverlay(context, room),
                      ],
                    );

              return LandscapeLock(enabled: wantsLandscape, child: content);
            },
          ),
        ),
      ),
    );
  }

  Widget _waiting(BuildContext context, Room room) {
    return Column(
      children: [
        _topBar(context, room, '게임', Icons.sports_esports_rounded),
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ],
    );
  }

  Widget _topBar(BuildContext context, Room room, String title, IconData icon) {
    // status==playing 동안은 '방으로'를 숨기고 '나가기'만 노출한다.
    // (finished면 결과 프롬프트 오버레이가 화면을 덮으므로 상단바 버튼은 무관.)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _roomCodeChip(),
          IconButton(
            tooltip: '나가기',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _leave(context, room),
          ),
        ],
      ),
    );
  }

  Widget _roomCodeChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tag_rounded, size: 14, color: Colors.white38),
          const SizedBox(width: 2),
          Text(
            session.roomCode,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _opponentBar(BuildContext context, Room room) {
    final me = session.myPlayerId;
    final opp = room.opponentOf(me);
    final services = AppServices.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: G42Colors.surface,
      child: Row(
        children: [
          const Icon(
            Icons.person_outline_rounded,
            size: 16,
            color: Colors.white38,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              opp == null ? '상대 없음' : '상대: ${opp.name}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 이 게임의 head-to-head 승판수("나 X : 상대 Y").
          if (opp != null && room.gameId.isNotEmpty)
            StreamBuilder<HeadToHead?>(
              stream: services.scoreStore.watchHeadToHeadForGame(
                me,
                opp.id,
                room.gameId,
              ),
              builder: (context, snap) {
                final h2h = snap.data;
                final myWins = h2h?.winsOf(me) ?? 0;
                final oppWins = h2h?.winsOf(opp.id) ?? 0;
                return _h2hChip(myWins, oppWins);
              },
            ),
        ],
      ),
    );
  }

  /// "나 X : 상대 Y" 승판수 칩.
  Widget _h2hChip(int myWins, int oppWins) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: G42Colors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '나 ',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          Text(
            '$myWins',
            style: const TextStyle(
              color: G42Colors.good,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            ' : ',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          Text(
            '$oppWins',
            style: const TextStyle(
              color: G42Colors.bad,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            ' 상대',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ---- 정상 종료 통합 프롬프트(게임 위젯 자체 오버레이를 덮는 풀 오버레이) ----
  Widget _resultOverlay(BuildContext context, Room room) {
    final me = session.myPlayerId;
    final winner = room.winner;
    final isDraw = winner == 'draw';
    final iWon = winner == me;
    final score = (room.state['roundScore'] as num?)?.toInt();

    final String headline;
    final Color headlineColor;
    final IconData headlineIcon;
    if (isDraw) {
      headline = '무승부';
      headlineColor = Colors.white;
      headlineIcon = Icons.handshake_rounded;
    } else if (iWon) {
      headline = '승리!';
      headlineColor = G42Colors.good;
      headlineIcon = Icons.emoji_events_rounded;
    } else {
      headline = '패배';
      headlineColor = G42Colors.bad;
      headlineIcon = Icons.sentiment_dissatisfied_rounded;
    }

    return Positioned.fill(
      // 탭 차단 배경: 게임 위젯의 자체 버튼이 눌리지 않도록 전체를 덮는다.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          color: Colors.black.withValues(alpha: 0.82),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(headlineIcon, size: 64, color: headlineColor),
                const SizedBox(height: 16),
                Text(
                  headline,
                  style: TextStyle(
                    color: headlineColor,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (score != null && score > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '획득 점수 $score점',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _rematchSameGame(context, room),
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('같은 게임 한 판 더'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _backToPicker(context),
                    icon: const Icon(Icons.grid_view_rounded),
                    label: const Text('게임 선택으로'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.white24),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
