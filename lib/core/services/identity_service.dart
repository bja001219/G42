import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 로컬에 영구 저장되는 내 정체성(플레이어 id + 표시 이름).
class IdentityService {
  String playerId;
  String name;

  /// 사용자가 닉네임을 직접 확정(로그인)했는지 여부.
  /// false면 앱 진입 시 로그인(닉네임 입력) 화면을 강제한다.
  bool nameConfirmed;

  final SharedPreferences _prefs;

  IdentityService._(this._prefs, this.playerId, this.name, this.nameConfirmed);

  static Future<IdentityService> load() async {
    final prefs = await SharedPreferences.getInstance();

    var id = prefs.getString('playerId');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString('playerId', id);
    }

    // 최초엔 이름을 자동 생성하되, 사용자가 직접 확정하기 전까지는
    // nameConfirmed=false 로 두어 로그인 화면을 거치게 한다.
    var name = prefs.getString('playerName');
    if (name == null || name.isEmpty) {
      name = '플레이어-${id.substring(0, 4)}';
      await prefs.setString('playerName', name);
    }

    final confirmed = prefs.getBool('nameConfirmed') ?? false;

    return IdentityService._(prefs, id, name, confirmed);
  }

  /// 닉네임 변경(이미 확정된 사용자가 닉네임만 바꾸는 경우).
  Future<void> setName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    name = trimmed;
    await _prefs.setString('playerName', name);
  }

  /// 로그인: 닉네임을 저장하고 확정 플래그를 세운다.
  Future<void> confirmName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    name = trimmed;
    nameConfirmed = true;
    await _prefs.setString('playerName', name);
    await _prefs.setBool('nameConfirmed', true);
  }
}
