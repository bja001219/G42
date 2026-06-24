import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../core/game_definition.dart';
import '../core/game_registry.dart';
import '../core/game_session.dart';
import '../core/models/room.dart';
import '../core/services/room_service.dart';
import '../theme.dart';
import 'game_host_screen.dart';
import 'widgets/game_card.dart';

/// 방 대기실(핵심). 둘 다 입장 → 방장이 게임 선택 → 참가자 수락 → 게임 시작 →
/// 게임 종료 후 대기실 복귀(재선택/재대국). 온라인 전용.
class RoomLobbyScreen extends StatefulWidget {
  final String code;
  final bool isHost;

  const RoomLobbyScreen({super.key, required this.code, required this.isHost});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  StreamSubscription<Room>? _sub;
  Room? _room;

  /// GameHostScreen으로 이동한 상태인지(중복 push 방지).
  bool _inGame = false;

  /// startGame을 이미 트리거했는지(단일 기록자=방장 중복 호출 방지).
  bool _startTriggered = false;

  /// 이번 playing 세션을 이미 소비했는지(게임에서 '방으로' 복귀 후 재진입 래치).
  ///
  /// 게임 화면에서 pop으로 돌아오면 _inGame이 즉시 false가 되지만, 방 status는
  /// 여전히 playing(또는 게임 종료 시 finished)일 수 있다. 그 상태에서 다음
  /// 스트림 emit이 오면 `status==playing && !_inGame` 조건이 다시 참이 되어
  /// 사용자를 게임 화면으로 도로 튕겨 보낸다. 이 래치로 "같은 세션에서는 한 번만
  /// _goToGame을 트리거"하도록 막고, status가 waiting으로 되돌아오면 해제한다.
  bool _consumedPlaying = false;

  RoomService get _service => AppServices.of(context).roomService;
  String get _myId => AppServices.of(context).identity.playerId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= _service.watchRoom(widget.code).listen(_onRoom);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---- 방 상태 수신 ----
  void _onRoom(Room room) {
    if (!mounted) return;
    setState(() => _room = room);

    // status가 waiting으로 되돌아오면(=대기실 리셋 완료) 재진입 래치를 푼다.
    // 이로써 다음 게임 세션에서는 다시 한 번 _goToGame이 트리거될 수 있다.
    if (room.status == RoomStatus.waiting) {
      _consumedPlaying = false;
    }

    // 역전이: 게임 화면에 있는데 더 이상 playing이 아니면(방장이 대기실로 리셋했거나
    // 게임이 끝난 직후 등) 게임 화면을 자동으로 빠져나온다. 이게 없으면 게스트가
    // gameId='' 상태의 게임 화면에서 무한 스피너에 갇힌다(단일 기록자 리셋이
    // 상대를 게임 밖으로 끌어내는 신호로 작동하도록 만든다).
    if (_inGame && room.status == RoomStatus.waiting) {
      Navigator.of(context).pop();
      return;
    }

    final accept = (room.state['accept'] as String?) ?? '';

    // 단일 기록자(방장): 참가자가 수락하면 게임을 시작한다.
    if (widget.isHost &&
        !_startTriggered &&
        room.status == RoomStatus.waiting &&
        room.isFull &&
        room.gameId.isNotEmpty &&
        accept == 'accepted') {
      final game = GameRegistry.byId(room.gameId);
      if (game != null) {
        _startTriggered = true;
        final ids = room.playerIds;
        final config = Map<String, dynamic>.from(
          (room.state['config'] as Map?) ?? const <String, dynamic>{},
        );
        _service.startGame(
          widget.code,
          initialState: game.createInitialStateConfigured(ids, config),
          firstTurn: game.firstTurn(ids),
        );
      }
    }

    // 양쪽: status==playing 되면 게임 화면으로(같은 세션에서 한 번만).
    if (room.status == RoomStatus.playing && !_inGame && !_consumedPlaying) {
      _goToGame(room.gameId);
    }
  }

  // ---- 게임 화면 진입 후 복귀 처리 ----
  Future<void> _goToGame(String gameId) async {
    _inGame = true;
    final session = GameSession(
      myPlayerId: _myId,
      roomCode: widget.code,
      service: _service,
      hotseat: false, // 온라인 전용.
    );
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(builder: (_) => GameHostScreen(session: session)),
    );
    // 게임 화면에서 돌아옴('방으로' 복귀 또는 게임 종료 후 복귀).
    _inGame = false;
    _startTriggered = false;
    // 같은 playing/finished 세션에서 재진입하지 않도록 래치를 건다.
    // 단, 이미 status가 waiting으로 리셋된 뒤에 돌아왔다면(역전이 pop 등) 래치를
    // 걸지 않는다 — 그래야 다음 게임 세션 진입이 막히지 않는다.
    final returnedStatus = _room?.status;
    _consumedPlaying =
        returnedStatus == RoomStatus.playing ||
        returnedStatus == RoomStatus.finished;
    if (!mounted) return;

    // 방장이 대기실 리셋을 책임진다(단일 기록자).
    //
    // 핵심: '게임 자연 종료(finished)'와 '상대 퇴장(leaveRoom)'을 구분한다. 둘 다
    // status=finished를 쓰지만, 퇴장은 players를 제거하므로 players.length로 갈린다.
    //  - 두 명 그대로 남아있다 → 게임이 끝났거나 도중에 '방으로' 나온 것 → 대기실 리셋.
    //  - 한 명만 남았다(상대 퇴장) → 리셋하지 않고 finished 화면을 유지한다.
    if (widget.isHost) {
      final current = _room;
      if (current != null && current.isFull) {
        await _resetToWaiting();
      }
    }
  }

  Future<void> _resetToWaiting() async {
    await _service.updateRoom(widget.code, {
      'status': RoomStatus.waiting.name,
      'gameId': '',
      'turn': null,
      'winner': null,
      'state': <String, dynamic>{},
    });
  }

  // ---- 방장: 게임 선택 ----
  Future<void> _pickGame(GameDefinition game) async {
    // 시작 전 설정이 있는 게임(예: 보글)은 설정 시트를 먼저 띄운다.
    if (game.hasSetup) {
      final config = await _showSetupSheet(game);
      if (config == null) return; // 취소
      await _service.updateRoom(widget.code, {
        'gameId': game.id,
        'state': <String, dynamic>{'accept': 'pending', 'config': config},
      });
      return;
    }
    await _service.updateRoom(widget.code, {
      'gameId': game.id,
      'state': <String, dynamic>{'accept': 'pending'},
    });
  }

  /// 방장 설정 시트. 선택한 설정 맵을 반환(취소 시 null).
  Future<Map<String, dynamic>?> _showSetupSheet(GameDefinition game) {
    var config = Map<String, dynamic>.from(
      (_room?.state['config'] as Map?) ?? game.defaultConfig,
    );
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: G42Colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(game.icon, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    '${game.title} 설정',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              game.buildSetup(ctx, config, (c) => setSheet(() => config = c)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, config),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('이 설정으로 준비'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 참가자: 수락/거절 ----
  Future<void> _accept() async {
    await _service.updateRoom(widget.code, {
      'state': <String, dynamic>{'accept': 'accepted'},
    });
  }

  Future<void> _decline() async {
    await _service.updateRoom(widget.code, {
      'gameId': '',
      'state': <String, dynamic>{'accept': 'declined'},
    });
  }

  // ---- 방 나가기 ----
  Future<void> _leave() async {
    final navigator = Navigator.of(context);
    await _service.leaveRoom(widget.code, _myId);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _confirmLeave,
          ),
          title: const Text('대기실'),
          actions: [_roomCodeChip(), const SizedBox(width: 12)],
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: G42Colors.surface,
        title: const Text('방 나가기'),
        content: const Text('대기실에서 나갈까요? 상대방의 방도 종료됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: G42Colors.bad),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (ok == true) await _leave();
  }

  Widget _body() {
    final room = _room;
    if (room == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // 상대가 실제로 빠졌을 때만(=players<2) '상대 퇴장' 화면을 띄운다.
    // 게임 자연 종료(finished지만 두 명 그대로)는 여기 해당하지 않는다.
    if (!room.isFull && room.status == RoomStatus.finished) {
      return _finishedView();
    }

    // 게임 화면 push 중이면 잠깐 로딩만 보여준다.
    if (_inGame) {
      return const Center(child: CircularProgressIndicator());
    }

    // 게임에서 복귀했지만 아직 status가 playing/finished다.
    //  - 방장: 곧 _resetToWaiting을 호출하므로 잠깐 로딩.
    //  - 게스트: 방장의 waiting 리셋 전파를 기다린다(재진입 금지, 명시적 대기 UI).
    if (room.status == RoomStatus.playing ||
        room.status == RoomStatus.finished) {
      return _returningView();
    }

    // 혼자(상대 미입장): 코드 안내.
    if (!room.isFull) {
      return _waitingForOpponentView(room);
    }

    // 둘 다 입장(waiting): picker / accept 흐름.
    return widget.isHost ? _hostPickerView(room) : _guestView(room);
  }

  // ---- 게임 복귀 직후: 대기실 리셋 대기 ----
  Widget _returningView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 16),
          Text(
            '대기실로 돌아가는 중...',
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ---- 혼자: 코드 표시 ----
  Widget _waitingForOpponentView(Room room) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '방 코드',
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: room.code));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('코드를 복사했어요')));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
              decoration: BoxDecoration(
                color: G42Colors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: G42Colors.accent, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    room.code,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.copy_rounded,
                    size: 22,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          const Text(
            '상대를 기다리는 중...',
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ---- 방장: 게임 선택 그리드 ----
  Widget _hostPickerView(Room room) {
    final accept = (room.state['accept'] as String?) ?? '';
    final games = GameRegistry.games;
    final pendingGame = room.gameId.isEmpty
        ? null
        : GameRegistry.byId(room.gameId);
    final pendingConfig = Map<String, dynamic>.from(
      (room.state['config'] as Map?) ?? const <String, dynamic>{},
    );
    final pendingSummary = pendingGame?.configSummary(pendingConfig) ?? '';
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '게임을 골라주세요',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                if (accept == 'pending' && room.gameId.isNotEmpty)
                  Text(
                    pendingSummary.isEmpty
                        ? '상대의 수락을 기다리는 중... (다른 게임으로 바꿔도 돼요)'
                        : '상대의 수락을 기다리는 중 · $pendingSummary (바꿔도 돼요)',
                    style: const TextStyle(color: G42Colors.warn, fontSize: 13),
                  )
                else if (accept == 'declined')
                  const Text(
                    '참가자가 거절했어요. 다른 게임을 골라보세요.',
                    style: TextStyle(color: G42Colors.bad, fontSize: 13),
                  )
                else
                  const Text(
                    '상대가 입장했어요. 함께 할 게임을 선택하세요.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.92,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => GameCard(
                game: games[i],
                selected: room.gameId == games[i].id,
                onTap: () => _pickGame(games[i]),
              ),
              childCount: games.length,
            ),
          ),
        ),
      ],
    );
  }

  // ---- 참가자: 게임 고르는 중 / 수락·거절 ----
  Widget _guestView(Room room) {
    final accept = (room.state['accept'] as String?) ?? '';

    if (room.gameId.isEmpty || accept != 'pending') {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 16),
            Text(
              '방장이 게임을 고르는 중...',
              style: TextStyle(color: Colors.white60, fontSize: 15),
            ),
          ],
        ),
      );
    }

    final game = GameRegistry.byId(room.gameId);
    if (game == null) {
      return const Center(
        child: Text('알 수 없는 게임이에요.', style: TextStyle(color: Colors.white60)),
      );
    }

    final summary = game.configSummary(
      Map<String, dynamic>.from(
        (room.state['config'] as Map?) ?? const <String, dynamic>{},
      ),
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '방장이 선택한 게임',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(colors: game.gradient),
              ),
              child: Column(
                children: [
                  Icon(game.icon, size: 48, color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    game.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    game.subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        summary,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _decline,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: G42Colors.bad),
                    ),
                    child: const Text(
                      '거절',
                      style: TextStyle(color: G42Colors.bad),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _accept,
                    child: const Text('수락'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- 상대가 나가서 방이 종료됨 ----
  Widget _finishedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.exit_to_app_rounded,
              size: 48,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            const Text(
              '상대가 방을 나갔어요.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _leave, child: const Text('홈으로')),
          ],
        ),
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
            widget.code,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
