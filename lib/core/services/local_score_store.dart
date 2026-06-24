import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_stats.dart';
import '../models/head_to_head.dart';
import 'score_store.dart';

/// 인메모리/로컬 영구 전적 저장소 (Firebase 미설정 시 폴백).
///
/// shared_preferences 에 JSON 으로 저장한다:
///   - `stats:<playerId>`        → PlayerStats.toMap() 의 jsonEncode (게임 무관 통산)
///   - `h2h:<pairKey__gameId>`   → HeadToHead.toMap() 의 jsonEncode (페어 × 게임)
///
/// watch* 는 LocalRoomService 와 동일하게 키별 broadcast StreamController 로
/// 변경을 emit 한다. 같은 앱 인스턴스 안에서만 동작(동일 기기 핫시트 용).
class LocalScoreStore implements ScoreStore {
  SharedPreferences? _prefs;
  final Map<String, StreamController<PlayerStats>> _statsCtrls = {};
  final Map<String, StreamController<HeadToHead?>> _h2hCtrls = {};

  @override
  String get label => '로컬 (동일 기기)';

  Future<SharedPreferences> _p() async =>
      _prefs ??= await SharedPreferences.getInstance();

  String _statsKey(String id) => 'stats:$id';
  String _h2hKey(String key) => 'h2h:$key';

  // ----- 직렬화 헬퍼 -----

  Future<PlayerStats?> _readStats(SharedPreferences p, String id) {
    final raw = p.getString(_statsKey(id));
    if (raw == null) return Future.value(null);
    return Future.value(
      PlayerStats.fromMap(Map<String, dynamic>.from(jsonDecode(raw) as Map)),
    );
  }

  Future<void> _writeStats(SharedPreferences p, PlayerStats s) async {
    await p.setString(_statsKey(s.playerId), jsonEncode(s.toMap()));
    _statsCtrls[s.playerId]?.add(s);
  }

  /// h2h 문서를 [docKey]('pairKey__gameId')로 읽는다. 없으면 null.
  HeadToHead? _readH2h(SharedPreferences p, String docKey) {
    final raw = p.getString(_h2hKey(docKey));
    if (raw == null) return null;
    return HeadToHead.fromMap(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  Future<void> _writeH2h(
    SharedPreferences p,
    String docKey,
    HeadToHead h,
  ) async {
    await p.setString(_h2hKey(docKey), jsonEncode(h.toMap()));
    _h2hCtrls[docKey]?.add(h);
  }

  // ----- 기록 -----

  @override
  Future<void> recordRound({
    required String winnerId,
    required String winnerName,
    required String loserId,
    required String loserName,
    required int score,
    required String gameId,
  }) async {
    final p = await _p();

    final curWinner =
        await _readStats(p, winnerId) ??
        PlayerStats.empty(winnerId, winnerName);
    final curLoser =
        await _readStats(p, loserId) ?? PlayerStats.empty(loserId, loserName);

    await _writeStats(
      p,
      curWinner.copyWith(
        name: winnerName,
        totalScore: curWinner.totalScore + score,
        wins: curWinner.wins + 1,
        rounds: curWinner.rounds + 1,
      ),
    );
    await _writeStats(
      p,
      curLoser.copyWith(
        name: loserName,
        losses: curLoser.losses + 1,
        rounds: curLoser.rounds + 1,
      ),
    );

    final pairKey = HeadToHead.keyFor(winnerId, loserId);
    final docKey = HeadToHead.docKeyFor(winnerId, loserId, gameId);
    final curH2h =
        _readH2h(p, docKey) ?? HeadToHead(pairKey: pairKey, gameId: gameId);
    await _writeH2h(
      p,
      docKey,
      HeadToHead(
        pairKey: pairKey,
        gameId: gameId,
        wins: {...curH2h.wins, winnerId: curH2h.winsOf(winnerId) + 1},
        scores: {...curH2h.scores, winnerId: curH2h.scoreOf(winnerId) + score},
        rounds: curH2h.rounds + 1,
        nagari: curH2h.nagari,
      ),
    );
  }

  @override
  Future<void> recordNagari({
    required String idA,
    required String nameA,
    required String idB,
    required String nameB,
    required String gameId,
  }) async {
    final p = await _p();

    final curA = await _readStats(p, idA) ?? PlayerStats.empty(idA, nameA);
    final curB = await _readStats(p, idB) ?? PlayerStats.empty(idB, nameB);

    await _writeStats(
      p,
      curA.copyWith(
        name: nameA,
        nagari: curA.nagari + 1,
        rounds: curA.rounds + 1,
      ),
    );
    await _writeStats(
      p,
      curB.copyWith(
        name: nameB,
        nagari: curB.nagari + 1,
        rounds: curB.rounds + 1,
      ),
    );

    final pairKey = HeadToHead.keyFor(idA, idB);
    final docKey = HeadToHead.docKeyFor(idA, idB, gameId);
    final curH2h =
        _readH2h(p, docKey) ?? HeadToHead(pairKey: pairKey, gameId: gameId);
    await _writeH2h(
      p,
      docKey,
      HeadToHead(
        pairKey: pairKey,
        gameId: gameId,
        wins: curH2h.wins,
        scores: curH2h.scores,
        rounds: curH2h.rounds + 1,
        nagari: curH2h.nagari + 1,
      ),
    );
  }

  // ----- 조회 -----

  @override
  Future<PlayerStats> statsOf(String playerId, {String? fallbackName}) async {
    final p = await _p();
    return (await _readStats(p, playerId)) ??
        PlayerStats.empty(playerId, fallbackName ?? '플레이어');
  }

  @override
  Stream<PlayerStats> watchStats(String playerId, {String? fallbackName}) {
    final ctrl = _statsCtrls.putIfAbsent(
      playerId,
      () => StreamController<PlayerStats>.broadcast(),
    );
    // 구독 시작 시 현재값을 비동기로 1회 emit.
    scheduleMicrotask(() async {
      final p = await _p();
      final s =
          (await _readStats(p, playerId)) ??
          PlayerStats.empty(playerId, fallbackName ?? '플레이어');
      ctrl.add(s);
    });
    return ctrl.stream;
  }

  @override
  Future<HeadToHead?> headToHead(String idA, String idB) async {
    // 게임 무관 레거시 조회: bare pairKey 문서(현재는 기록되지 않음).
    final p = await _p();
    return _readH2h(p, HeadToHead.keyFor(idA, idB));
  }

  @override
  Stream<HeadToHead?> watchHeadToHead(String idA, String idB) {
    final key = HeadToHead.keyFor(idA, idB);
    final ctrl = _h2hCtrls.putIfAbsent(
      key,
      () => StreamController<HeadToHead?>.broadcast(),
    );
    scheduleMicrotask(() async {
      final p = await _p();
      ctrl.add(_readH2h(p, key));
    });
    return ctrl.stream;
  }

  @override
  Future<HeadToHead?> headToHeadForGame(
    String idA,
    String idB,
    String gameId,
  ) async {
    final p = await _p();
    final pairKey = HeadToHead.keyFor(idA, idB);
    final docKey = HeadToHead.docKeyFor(idA, idB, gameId);
    // 새 페어/새 게임: 자동 0-0.
    return _readH2h(p, docKey) ?? HeadToHead(pairKey: pairKey, gameId: gameId);
  }

  @override
  Stream<HeadToHead?> watchHeadToHeadForGame(
    String idA,
    String idB,
    String gameId,
  ) {
    final pairKey = HeadToHead.keyFor(idA, idB);
    final docKey = HeadToHead.docKeyFor(idA, idB, gameId);
    final ctrl = _h2hCtrls.putIfAbsent(
      docKey,
      () => StreamController<HeadToHead?>.broadcast(),
    );
    scheduleMicrotask(() async {
      final p = await _p();
      ctrl.add(
        _readH2h(p, docKey) ?? HeadToHead(pairKey: pairKey, gameId: gameId),
      );
    });
    return ctrl.stream;
  }

  @override
  Future<void> resetHeadToHead(String idA, String idB, String gameId) async {
    final p = await _p();
    final pairKey = HeadToHead.keyFor(idA, idB);
    final docKey = HeadToHead.docKeyFor(idA, idB, gameId);
    // 그 (페어, 게임) 문서만 제거 → 0-0. 빈 0-0 을 구독자에게 emit.
    await p.remove(_h2hKey(docKey));
    _h2hCtrls[docKey]?.add(HeadToHead(pairKey: pairKey, gameId: gameId));
  }
}
