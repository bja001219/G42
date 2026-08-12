import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../core/game_definition.dart';
import '../core/game_registry.dart';
import '../core/game_session.dart';
import '../core/models/head_to_head.dart';
import '../core/models/room.dart';
import '../core/services/presence.dart';
import '../core/services/room_service.dart';
import '../theme.dart';
import 'game_host_screen.dart';
import 'widgets/game_card.dart';

/// 방 대기실(핵심). 둘 다 입장 → 누구든 게임 제안 → 상대 수락 → 게임 시작 →
/// 게임 종료 후 통합 프롬프트(같은 게임 더 / 게임 선택으로). 온라인 전용.
///
/// 게임 선택은 대칭이다: 방장/게스트 구분 없이 누구든 먼저 게임 카드를 고르면
/// "제안자"(state["proposedBy"])가 되고, 상대는 [참가]/[거절]을 본다. 단, 실제
/// startGame 트리거(단일 기록자)는 그대로 호스트만 담당한다(중복 시작 방지).
class RoomLobbyScreen extends StatefulWidget {
  final String code;
  final bool isHost;

  const RoomLobbyScreen({super.key, required this.code, required this.isHost});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen>
    with WidgetsBindingObserver {
  StreamSubscription<Room>? _sub;
  Room? _room;

  /// GameHostScreen으로 이동한 상태인지(중복 push 방지).
  bool _inGame = false;

  /// startGame을 이미 트리거했는지(단일 기록자=방장 중복 호출 방지).
  bool _startTriggered = false;

  /// 상대 퇴장 자동 홈 복귀를 이미 처리했는지(중복 토스트/pop 방지).
  bool _opponentLeftHandled = false;

  /// 이번 playing 세션을 이미 소비했는지(게임에서 복귀 후 재진입 래치).
  ///
  /// 게임 화면에서 pop으로 돌아오면 _inGame이 즉시 false가 되지만, 방 status는
  /// 여전히 playing(또는 게임 종료 시 finished)일 수 있다. 그 상태에서 다음
  /// 스트림 emit이 오면 `status==playing && !_inGame` 조건이 다시 참이 되어
  /// 사용자를 게임 화면으로 도로 튕겨 보낸다. 이 래치로 "같은 세션에서는 한 번만
  /// _goToGame을 트리거"하도록 막고, status가 waiting으로 되돌아오면 해제한다.
  bool _consumedPlaying = false;

  // ---- 상대 연결(presence) 감지 ----
  /// 내 heartbeat 를 주기적으로 보낸다(방에 있는 동안 계속).
  HeartbeatSender? _heartbeat;

  /// 상대 heartbeat 침묵을 감지하는 감지기(보수적: arm 전엔 절대 끊김 판정 안 함).
  OpponentPresence? _presence;

  /// 주기적으로 stale 여부를 확인하는 타이머.
  Timer? _presenceTimer;

  /// "상대 연결 끊김?" 안내가 떠 있는지(중복 표시/재진입 방지).
  bool _presenceDialogOpen = false;

  /// 떠 있는 presence 안내의 자체 context(정확히 그 다이얼로그만 닫기 위함).
  BuildContext? _presenceDialogCtx;

  /// 앱이 백그라운드 상태인지(복귀 직후 오판 방지).
  bool _appPaused = false;

  /// 방 나가기가 진행 중인지(_leave 와 _handleOpponentLeft 의 중복 popUntil 방지).
  bool _leaving = false;

  RoomService get _service => AppServices.of(context).roomService;
  String get _myId => AppServices.of(context).identity.playerId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // onError 를 둬서 전송 계층이 에러를 흘려도 구독이 조용히 죽지 않게 한다.
    // (FirebaseRoomService.watchRoom 은 이미 자동 재구독으로 에러를 흡수하지만,
    //  방어적으로 한 겹 더 둔다.)
    _sub ??= _service
        .watchRoom(widget.code)
        .listen(
          _onRoom,
          onError: (Object e, StackTrace st) =>
              debugPrint('대기실 방 구독 에러(무시하고 유지): $e'),
        );

    // presence: 온라인일 때만. 내 heartbeat 송신을 시작하고, 상대 침묵을 주기적으로
    // 확인한다. (대기실에 머무는 동안 계속 돌아 인게임에서도 유효하다.)
    if (_service.isOnline && _heartbeat == null) {
      _heartbeat = HeartbeatSender(
        service: _service,
        code: widget.code,
        playerId: _myId,
      )..start();
      _presence = OpponentPresence();
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkPresence(),
      );
      // 앱 백그라운드/복귀 감지: 백그라운드 동안 스냅샷이 끊겨 멀쩡한 상대를
      // 끊겼다고 오판하는 것을 막기 위해, 백그라운드로 가면 presence 를 무장 해제하고
      // 복귀 후 새 heartbeat 를 다시 관측할 때까지 stale 판정을 하지 않는다.
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (!resumed) {
      // 백그라운드/비활성 진입: 다음 임계 카운트의 기준을 리셋(무장 해제).
      _appPaused = true;
      _presence?.disarm();
    } else {
      _appPaused = false;
      // 복귀 즉시엔 stale 판정을 미룬다. 다음 스냅샷의 observe 가 다시 arm 한다.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _heartbeat?.stop();
    _presenceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---- 방 상태 수신 ----
  void _onRoom(Room room) {
    if (!mounted) return;
    setState(() => _room = room);

    // presence: 상대 heartbeat 관측. 값이 다시 움직였으면(상대 복귀) 떠 있던 "연결
    // 끊김?" 안내를 자동으로 닫는다.
    final presence = _presence;
    if (presence != null) {
      final oppId = room.opponentOf(_myId)?.id;
      final beat = oppId == null ? null : room.heartbeatOf(oppId);
      final revived = presence.observe(beat);
      if (revived && _presenceDialogOpen) {
        // 상대 복귀 → 떠 있던 안내만 정확히 닫는다(그 다이얼로그 자체 context 로).
        _dismissPresenceDialog();
      }
    }

    // status가 waiting으로 되돌아오면(=대기실 리셋/재제안 완료) 재진입 래치를 푼다.
    // 이로써 다음 게임 세션에서는 다시 한 번 _goToGame이 트리거될 수 있다.
    if (room.status == RoomStatus.waiting) {
      _consumedPlaying = false;
    }

    // 상대 퇴장 감지(나가기 대칭): 한 명만 남고 finished면 상대가 완전히 나간 것.
    // 게임 중이든 대기실이든, _inGame 여부와 무관하게 홈까지 자동 복귀시킨다.
    // (정상 종료 finished&&isFull 은 이 분기에 걸리지 않고 GameHostScreen의
    //  통합 프롬프트가 처리한다.)
    if (!room.isFull &&
        room.status == RoomStatus.finished &&
        !_opponentLeftHandled) {
      _opponentLeftHandled = true;
      _handleOpponentLeft(room);
      return;
    }

    // 역전이: 게임 화면에 있는데 더 이상 playing이 아니면(상대/내가 대기실로
    // 리셋했거나 게임이 끝난 직후 등) 게임 화면을 자동으로 빠져나온다. 이게 없으면
    // gameId='' 상태의 게임 화면에서 무한 스피너에 갇힌다.
    if (_inGame && room.status == RoomStatus.waiting) {
      Navigator.of(context).pop();
      return;
    }

    final accept = (room.state['accept'] as String?) ?? '';

    // 단일 기록자(방장): 누가 제안했든 상대가 수락하면 게임을 시작한다.
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

  /// 상대가 완전히 나갔다. 게임 중이든 대기실이든 홈까지 자동 복귀한다.
  /// 상대 기권으로 내가 승점을 얻었으면 그에 맞는 토스트를 띄운다.
  void _handleOpponentLeft(Room room) {
    if (_leaving) return; // 내가 이미 나가는 중이면 중복 popUntil 하지 않는다.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // 내가 나간 경우(players에서 내가 빠짐)엔 토스트 없이 홈으로만.
    final iLeft = room.playerById(_myId) == null;
    final forfeit = room.state['forfeit'] == true;
    final forfeitWinnerId = room.state['forfeitWinnerId'] as String?;
    final iWonByForfeit = forfeit && forfeitWinnerId == _myId;

    navigator.popUntil((r) => r.isFirst);
    if (iLeft) return;
    messenger.showSnackBar(
      SnackBar(content: Text(iWonByForfeit ? '상대 기권 — 1점 획득!' : '상대가 나갔습니다')),
    );
  }

  // ---- 상대 연결 끊김 감지(보수적) ----
  /// 주기 타이머가 호출. 인게임 중 상대 heartbeat 가 임계 시간 넘게 침묵하면(=상대
  /// 새로고침/강제종료 추정) 안내한다. 정상 플레이 중엔 절대 끼어들지 않는다:
  /// presence 가 arm 된(상대를 한 번이라도 관측한) 뒤, 완전 침묵이 임계를 넘을 때만.
  void _checkPresence() {
    if (!mounted || _presenceDialogOpen) return;
    // 오판 방지의 *실제* 안전장치는 disarm()이다: 백그라운드 진입 시 presence 를
    // 무장 해제하면 새 heartbeat 를 다시 관측하기 전까지 isStale() 가 항상 false 다.
    // 아래 _appPaused 게이트는 그 위의 최적화(불필요한 체크 스킵)일 뿐이다.
    if (_appPaused) return;
    if (_opponentLeftHandled || _leaving) return; // 이미 홈으로 가는 중.
    final room = _room;
    final presence = _presence;
    if (room == null || presence == null) return;
    if (!_inGame) return; // 인게임에서만(대기실은 직접 나가면 되므로 안 띄움).
    if (!room.isFull) return; // 상대가 실제로 빠졌으면 _handleOpponentLeft 가 처리.
    if (presence.isStale()) {
      _showPresenceDialog();
    }
  }

  /// 떠 있는 presence 안내를 **그 다이얼로그 자체 context** 로 정확히 닫는다.
  /// 루트 내비게이터를 직접 pop 하지 않으므로 어떤 타이밍에도 게임 화면을 잘못 닫지
  /// 않는다(context.mounted 로 이미 사라진 경우도 안전).
  void _dismissPresenceDialog() {
    _presenceDialogOpen = false;
    final dctx = _presenceDialogCtx;
    _presenceDialogCtx = null;
    if (dctx != null && dctx.mounted) Navigator.of(dctx).pop(true);
  }

  /// 절대 자동으로 끊지 않는다 — 사용자에게 [계속 기다리기]/[나가기] 선택권만 준다.
  /// 상대가 다시 응답하면(_onRoom 에서) 이 안내는 자동으로 닫힌다.
  Future<void> _showPresenceDialog() async {
    if (!mounted) return; // 타이머 틱과 dispose 사이 레이스 방어.
    final oppName = _room?.opponentOf(_myId)?.name ?? '상대';
    _presenceDialogOpen = true;
    final stay = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _presenceDialogCtx = ctx; // 자동 닫기에서 이 다이얼로그만 정확히 닫기 위함.
        return AlertDialog(
          backgroundColor: G42Colors.surface,
          title: const Text('상대 연결 확인'),
          content: Text('$oppName 님의 응답이 한동안 없어요. 연결이 끊겼을 수 있습니다.\n계속 기다릴까요?'),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: G42Colors.bad),
              onPressed: () {
                _presenceDialogOpen = false;
                _presenceDialogCtx = null;
                Navigator.pop(ctx, false);
              },
              child: const Text('나가기'),
            ),
            FilledButton(
              onPressed: () {
                _presenceDialogOpen = false;
                _presenceDialogCtx = null;
                Navigator.pop(ctx, true);
              },
              child: const Text('계속 기다리기'),
            ),
          ],
        );
      },
    );
    _presenceDialogOpen = false;
    _presenceDialogCtx = null;
    if (!mounted) return;
    if (stay == false) {
      await _leave(); // 끊김 추정 → 페널티 없이 방을 떠나 홈으로.
    } else {
      _presence?.snooze(); // 다음 임계까지 다시 기다린다.
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
    // 게임 화면에서 돌아옴. 복귀 경로는 둘 중 하나다:
    //  - 통합 프롬프트가 status=waiting(재제안/게임선택)으로 바꿔 역전이 pop된 경우.
    //  - 상대 퇴장 등으로 빠져나온 경우.
    // 어느 쪽이든 status 리셋/재제안은 게임 화면의 프롬프트가 책임지므로, 여기서는
    // 더 이상 호스트가 대기실을 리셋하지 않는다(프롬프트의 재제안을 덮어쓰지 않게).
    _inGame = false;
    _startTriggered = false;
    // 같은 playing/finished 세션에서 재진입하지 않도록 래치를 건다. 단, 이미
    // status가 waiting으로 리셋된 뒤에 돌아왔다면(역전이 pop) 래치를 걸지 않는다.
    final returnedStatus = _room?.status;
    _consumedPlaying =
        returnedStatus == RoomStatus.playing ||
        returnedStatus == RoomStatus.finished;
  }

  // ---- 게임 선택(대칭): 누구든 제안할 수 있다 ----
  Future<void> _pickGame(GameDefinition game) async {
    // 시작 전 설정이 있는 게임(예: 보글)은 설정 시트를 먼저 띄운다.
    if (game.hasSetup) {
      final config = await _showSetupSheet(game);
      if (config == null) return; // 취소
      await _service.updateRoom(widget.code, {
        'gameId': game.id,
        'state': <String, dynamic>{
          'accept': 'pending',
          'proposedBy': _myId,
          'config': config,
        },
      });
      return;
    }
    await _service.updateRoom(widget.code, {
      'gameId': game.id,
      'state': <String, dynamic>{'accept': 'pending', 'proposedBy': _myId},
    });
  }

  /// 설정 시트. 선택한 설정 맵을 반환(취소 시 null).
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

  // ---- 상대(피제안자): 수락/거절 ----
  Future<void> _accept(Room room) async {
    // 기존 state(proposedBy/config 등)를 보존하고 accept만 갱신한다.
    final newState = Map<String, dynamic>.from(room.state);
    newState['accept'] = 'accepted';
    await _service.updateRoom(widget.code, {'state': newState});
  }

  Future<void> _decline() async {
    await _service.updateRoom(widget.code, {
      'gameId': '',
      'state': <String, dynamic>{'accept': 'declined'},
    });
  }

  // ---- 전적 초기화 핸드셰이크(accept 와 별개 state 키: resetBy/resetGameId) ----

  /// 전적 초기화 제안: 기존 state 보존 후 resetBy/resetGameId 표식만 추가.
  Future<void> _proposeReset(String gameId) async {
    final room = _room;
    if (room == null) return;
    final newState = Map<String, dynamic>.from(room.state);
    newState['resetBy'] = _myId;
    newState['resetGameId'] = gameId;
    await _service.updateRoom(widget.code, {'state': newState});
  }

  /// 초기화 수락(상대): 수락한 클라이언트가 resetHeadToHead 를 1회 호출한 뒤
  /// reset 표식을 제거(중복 방지). 통산 profile 은 건드리지 않는다.
  Future<void> _acceptReset(Room room) async {
    final gameId = room.state['resetGameId'] as String?;
    final opp = room.opponentOf(_myId);
    if (gameId != null && gameId.isNotEmpty && opp != null) {
      await AppServices.of(
        context,
      ).scoreStore.resetHeadToHead(_myId, opp.id, gameId);
    }
    await _clearResetMarks(room);
  }

  /// 초기화 거절/취소: 표식만 제거.
  Future<void> _declineReset(Room room) => _clearResetMarks(room);

  Future<void> _clearResetMarks(Room room) async {
    final newState = Map<String, dynamic>.from(room.state)
      ..remove('resetBy')
      ..remove('resetGameId');
    await _service.updateRoom(widget.code, {'state': newState});
  }

  // ---- 방 나가기 ----
  Future<void> _leave() async {
    if (_leaving) return; // 중복 호출/중복 popUntil 방지(_handleOpponentLeft 와의 레이스).
    _leaving = true;
    final navigator = Navigator.of(context);
    await _service.leaveRoom(widget.code, _myId);
    if (!mounted) return;
    navigator.popUntil((r) => r.isFirst);
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

    // 상대 퇴장(players<2 && finished)은 _onRoom에서 자동 홈 복귀로 처리하므로,
    // 여기서는 잠깐 로딩만 보여준다(곧 popUntil로 빠져나간다).
    if (!room.isFull && room.status == RoomStatus.finished) {
      return _returningView();
    }

    // 게임 화면 push 중이면 잠깐 로딩만 보여준다.
    if (_inGame) {
      return const Center(child: CircularProgressIndicator());
    }

    // 게임에서 복귀했지만 아직 status가 playing/finished다(곧 waiting으로 전이).
    if (room.status == RoomStatus.playing ||
        room.status == RoomStatus.finished) {
      return _returningView();
    }

    // 혼자(상대 미입장): 코드 안내.
    if (!room.isFull) {
      return _waitingForOpponentView(room);
    }

    // 둘 다 입장(waiting): 제안 상태/proposedBy 기준으로 분기(대칭).
    return _lobbyView(room);
  }

  // ---- 대기실 본문: 제안 상태로 분기(방장/게스트 구분 없음) ----
  Widget _lobbyView(Room room) {
    final accept = (room.state['accept'] as String?) ?? '';
    final proposedBy = room.state['proposedBy'] as String?;
    final hasActiveProposal = room.gameId.isNotEmpty && accept == 'pending';

    // 활성 제안 없음: 양쪽 다 picker. (거절 직후면 안내 후 picker.)
    if (!hasActiveProposal) {
      return _pickerView(room, declined: accept == 'declined');
    }

    // 활성 제안 있음: 제안자는 picker(변경 가능), 상대는 수락/거절.
    if (proposedBy == _myId) {
      return _pickerView(room, waitingAccept: true);
    }
    return _acceptView(room);
  }

  // ---- 게임 복귀 직후 / 전이 대기 ----
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

  // ---- 게임 선택 그리드(대칭: 누구나 제안 가능) ----
  ///
  /// [waitingAccept]가 true면 "내가 제안자, 상대 수락 대기 중(바꿔도 됨)" 안내.
  /// [declined]가 true면 "상대가 거절했어요" 안내 후 다시 고르도록 한다.
  Widget _pickerView(
    Room room, {
    bool waitingAccept = false,
    bool declined = false,
  }) {
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
                if (waitingAccept)
                  Text(
                    pendingSummary.isEmpty
                        ? '상대 수락 대기 중 (다른 게임으로 바꿔도 됨)'
                        : '상대 수락 대기 중 · $pendingSummary (바꿔도 됨)',
                    style: const TextStyle(color: G42Colors.warn, fontSize: 13),
                  )
                else if (declined)
                  const Text(
                    '상대가 거절했어요. 다른 게임을 골라보세요.',
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
        // 제안자(수락 대기 중): 제안한 게임의 head-to-head + 전적 초기화.
        if (waitingAccept && room.gameId.isNotEmpty)
          SliverToBoxAdapter(child: _h2hPanel(room, room.gameId)),
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
                selected: waitingAccept && room.gameId == games[i].id,
                onTap: () => _pickGame(games[i]),
              ),
              childCount: games.length,
            ),
          ),
        ),
      ],
    );
  }

  // ---- 피제안자: 상대가 고른 게임 수락/거절 ----
  Widget _acceptView(Room room) {
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
              '상대가 선택한 게임',
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
            const SizedBox(height: 20),
            // 이 게임의 head-to-head + 전적 초기화 핸드셰이크.
            _h2hPanel(room, room.gameId),
            const SizedBox(height: 16),
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
                    onPressed: () => _accept(room),
                    child: const Text('참가'),
                  ),
                ),
              ],
            ),
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

  // ---- 게임이 제안/선택된 상태에서의 head-to-head + 전적 초기화 핸드셰이크 ----
  ///
  /// [gameId] 의 (나, 상대) 승판수를 "나 X : 상대 Y" 로 보여주고, 옆에 "전적 초기화"
  /// 버튼을 둔다. 누군가 초기화를 제안하면(state.resetBy) 상대 화면에 수락/거절 행이
  /// 뜬다(내가 제안자면 "수락 대기 중" 안내).
  Widget _h2hPanel(Room room, String gameId) {
    final opp = room.opponentOf(_myId);
    if (opp == null || gameId.isEmpty) return const SizedBox.shrink();
    final gameTitle = GameRegistry.byId(gameId)?.title ?? '게임';
    final resetBy = room.state['resetBy'] as String?;
    final resetGameId = room.state['resetGameId'] as String?;
    final hasReset =
        resetBy != null && resetBy.isNotEmpty && resetGameId == gameId;
    final iProposedReset = hasReset && resetBy == _myId;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 16,
                color: Colors.white38,
              ),
              const SizedBox(width: 8),
              StreamBuilder<HeadToHead?>(
                stream: AppServices.of(
                  context,
                ).scoreStore.watchHeadToHeadForGame(_myId, opp.id, gameId),
                builder: (context, snap) {
                  final h2h = snap.data;
                  final myWins = h2h?.winsOf(_myId) ?? 0;
                  final oppWins = h2h?.winsOf(opp.id) ?? 0;
                  return _h2hScoreText(myWins, oppWins);
                },
              ),
              const Spacer(),
              if (!hasReset)
                TextButton.icon(
                  onPressed: () => _proposeReset(gameId),
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('전적 초기화'),
                  style: TextButton.styleFrom(
                    foregroundColor: G42Colors.warn,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          if (hasReset)
            _resetHandshakeRow(room, gameTitle, iProposedReset, opp),
        ],
      ),
    );
  }

  Widget _h2hScoreText(int myWins, int oppWins) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14),
        children: [
          const TextSpan(
            text: '나 ',
            style: TextStyle(color: Colors.white54),
          ),
          TextSpan(
            text: '$myWins',
            style: const TextStyle(
              color: G42Colors.good,
              fontWeight: FontWeight.w900,
            ),
          ),
          const TextSpan(
            text: ' : ',
            style: TextStyle(color: Colors.white38),
          ),
          TextSpan(
            text: '$oppWins',
            style: const TextStyle(
              color: G42Colors.bad,
              fontWeight: FontWeight.w900,
            ),
          ),
          const TextSpan(
            text: ' 상대',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _resetHandshakeRow(
    Room room,
    String gameTitle,
    bool iProposed,
    RoomPlayer opp,
  ) {
    if (iProposed) {
      // 내가 제안자: 상대 수락 대기 중(취소 가능).
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '상대 수락 대기 중 (전적 초기화 제안함)',
                style: TextStyle(color: G42Colors.warn, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => _declineReset(room),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('취소'),
            ),
          ],
        ),
      );
    }
    // 상대가 제안: 수락/거절.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${opp.name}님이 $gameTitle 전적 초기화를 제안했어요',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _declineReset(room),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('거절'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _acceptReset(room),
                  style: FilledButton.styleFrom(
                    backgroundColor: G42Colors.warn,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('초기화 수락'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
