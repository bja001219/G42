import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/player_stats.dart';
import '../models/head_to_head.dart';
import 'score_store.dart';

/// Firestore 기반 통산/상대 전적 저장소.
///
/// 컬렉션 구조:
///   - `profiles/{playerId}`  → PlayerStats 1개
///   - `headtohead/{pairKey}` → HeadToHead 1개
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
  }) async {
    final batch = _db.batch();
    final pairKey = HeadToHead.keyFor(winnerId, loserId);

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

    // head-to-head: 승자 칸만 증가, 라운드 증가. (점 표기로 맵 부분 갱신)
    batch.set(_h2h(pairKey), {
      'pairKey': pairKey,
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
  }) async {
    final batch = _db.batch();
    final pairKey = HeadToHead.keyFor(idA, idB);

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

    batch.set(_h2h(pairKey), {
      'pairKey': pairKey,
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
}
