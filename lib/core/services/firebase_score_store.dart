import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/player_stats.dart';
import '../models/head_to_head.dart';
import 'score_store.dart';

/// Firestore 기반 통산/상대 전적 저장소.
///
/// 컬렉션 구조:
///   - `profiles/{playerId}`            → PlayerStats 1개 (게임 무관 통산)
///   - `headtohead/{pairKey__gameId}`   → HeadToHead 1개 (페어 × 게임 단위 승판수)
///
/// 원자성: 한 라운드 기록은 승자 profile / 패자 profile / h2h 문서 3개를 동시에
/// 갱신해야 하므로 [WriteBatch] 로 묶어 하나의 원자적 커밋으로 처리한다.
/// 카운터 누적은 [FieldValue.increment] 를 쓰고, 중첩 맵 키(h2h의 wins/scores)는
/// `wins.<id>` 같은 점 표기 필드 경로로 부분 increment 한다.
/// 문서가 없을 수도 있으므로 모든 set 은 `SetOptions(merge:true)` 를 쓴다.
class FirebaseScoreStore implements ScoreStore {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _profile(String id) =>
      _db.collection('profiles').doc(id);

  DocumentReference<Map<String, dynamic>> _h2h(String key) =>
      _db.collection('headtohead').doc(key);

  @override
  String get label => '온라인 (Firebase)';

  @override
  Future<void> recordRound({
    required String winnerId,
    required String winnerName,
    required String loserId,
    required String loserName,
    required int score,
    required String gameId,
  }) async {
    final batch = _db.batch();
    final pairKey = HeadToHead.keyFor(winnerId, loserId);
    final docKey = HeadToHead.docKeyFor(winnerId, loserId, gameId);

    // 승자 profile: 점수/승/라운드 누적 + 식별자·이름 보장.
    batch.set(_profile(winnerId), {
      'playerId': winnerId,
      'name': winnerName,
      'totalScore': FieldValue.increment(score),
      'wins': FieldValue.increment(1),
      'rounds': FieldValue.increment(1),
    }, SetOptions(merge: true));

    // 패자 profile: 패/라운드 누적 + 식별자·이름 보장.
    batch.set(_profile(loserId), {
      'playerId': loserId,
      'name': loserName,
      'losses': FieldValue.increment(1),
      'rounds': FieldValue.increment(1),
    }, SetOptions(merge: true));

    // head-to-head(페어×게임): 승자 칸만 증가, 라운드 증가. (점 표기로 맵 부분 갱신)
    batch.set(_h2h(docKey), {
      'pairKey': pairKey,
      'gameId': gameId,
      'wins': {winnerId: FieldValue.increment(1)},
      'scores': {winnerId: FieldValue.increment(score)},
      'rounds': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  @override
  Future<void> recordNagari({
    required String idA,
    required String nameA,
    required String idB,
    required String nameB,
    required String gameId,
  }) async {
    final batch = _db.batch();
    final pairKey = HeadToHead.keyFor(idA, idB);
    final docKey = HeadToHead.docKeyFor(idA, idB, gameId);

    batch.set(_profile(idA), {
      'playerId': idA,
      'name': nameA,
      'nagari': FieldValue.increment(1),
      'rounds': FieldValue.increment(1),
    }, SetOptions(merge: true));

    batch.set(_profile(idB), {
      'playerId': idB,
      'name': nameB,
      'nagari': FieldValue.increment(1),
      'rounds': FieldValue.increment(1),
    }, SetOptions(merge: true));

    batch.set(_h2h(docKey), {
      'pairKey': pairKey,
      'gameId': gameId,
      'nagari': FieldValue.increment(1),
      'rounds': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  @override
  Future<PlayerStats> statsOf(String playerId, {String? fallbackName}) async {
    final snap = await _profile(playerId).get();
    if (!snap.exists || snap.data() == null) {
      return PlayerStats.empty(playerId, fallbackName ?? '플레이어');
    }
    return PlayerStats.fromMap(snap.data()!);
  }

  @override
  Stream<PlayerStats> watchStats(String playerId, {String? fallbackName}) {
    return _profile(playerId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return PlayerStats.empty(playerId, fallbackName ?? '플레이어');
      }
      return PlayerStats.fromMap(snap.data()!);
    });
  }

  @override
  Future<HeadToHead?> headToHead(String idA, String idB) async {
    final key = HeadToHead.keyFor(idA, idB);
    final snap = await _h2h(key).get();
    if (!snap.exists || snap.data() == null) return null;
    return HeadToHead.fromMap(snap.data()!);
  }

  @override
  Stream<HeadToHead?> watchHeadToHead(String idA, String idB) {
    final key = HeadToHead.keyFor(idA, idB);
    return _h2h(key).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return HeadToHead.fromMap(snap.data()!);
    });
  }

  @override
  Future<HeadToHead?> headToHeadForGame(
    String idA,
    String idB,
    String gameId,
  ) async {
    final pairKey = HeadToHead.keyFor(idA, idB);
    final docKey = HeadToHead.docKeyFor(idA, idB, gameId);
    final snap = await _h2h(docKey).get();
    if (!snap.exists || snap.data() == null) {
      // 새 페어/새 게임: 자동 0-0.
      return HeadToHead(pairKey: pairKey, gameId: gameId);
    }
    return HeadToHead.fromMap(snap.data()!);
  }

  @override
  Stream<HeadToHead?> watchHeadToHeadForGame(
    String idA,
    String idB,
    String gameId,
  ) {
    final pairKey = HeadToHead.keyFor(idA, idB);
    final docKey = HeadToHead.docKeyFor(idA, idB, gameId);
    return _h2h(docKey).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return HeadToHead(pairKey: pairKey, gameId: gameId);
      }
      return HeadToHead.fromMap(snap.data()!);
    });
  }

  @override
  Future<void> resetHeadToHead(String idA, String idB, String gameId) async {
    final docKey = HeadToHead.docKeyFor(idA, idB, gameId);
    // 그 (페어, 게임) 문서만 삭제 → 다음 조회 시 자동 0-0. 다른 게임/페어/통산 불변.
    await _h2h(docKey).delete();
  }
}
