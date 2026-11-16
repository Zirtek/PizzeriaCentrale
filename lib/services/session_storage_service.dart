import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class SessionStorageService {
  SessionStorageService._();
  static final SessionStorageService instance = SessionStorageService._();

  static const String _sessionKey = 'pizzeria_persistent_session_v1';

  /// Salva la sessione localmente affinché resti attiva anche chiudendo l'app
  Future<void> saveSession(AppUserSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    } catch (_) {}
  }

  /// Ripristina l'ultima sessione salvata (null se non presente o dopo logout)
  Future<AppUserSession?> loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey);
      if (raw == null || raw.isEmpty) return null;

      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final session = AppUserSession.fromJson(map);
      if (session.id.isEmpty || session.role.isEmpty) {
        await clearSession();
        return null;
      }
      return session;
    } catch (_) {
      await clearSession();
      return null;
    }
  }

  /// Rimuove la sessione salvata (chiamato al logout esplicito)
  Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
    } catch (_) {}
  }
}