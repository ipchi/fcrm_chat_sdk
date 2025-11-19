import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for storing chat-related data locally
class ChatStorageService {
  static const String _browserKeyPrefix = 'fcrm_chat_browser_';
  static const String _userDataPrefix = 'fcrm_chat_user_';

  final String appKey;

  ChatStorageService({required this.appKey});

  String get _browserStorageKey => '$_browserKeyPrefix$appKey';
  String get _userDataStorageKey => '$_userDataPrefix$appKey';

  /// Save browser key
  Future<void> saveBrowserKey(String browserKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_browserStorageKey, browserKey);
  }

  /// Get browser key
  Future<String?> getBrowserKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_browserStorageKey);
  }

  /// Clear browser key
  Future<void> clearBrowserKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_browserStorageKey);
  }

  /// Save user data
  Future<void> saveUserData(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userDataStorageKey, jsonEncode(userData));
  }

  /// Get user data
  Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_userDataStorageKey);
    if (data != null) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return null;
  }

  /// Clear user data
  Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userDataStorageKey);
  }

  /// Check if user is registered
  Future<bool> isRegistered() async {
    final userData = await getUserData();
    return userData != null && userData['registered'] == true;
  }

  /// Clear all stored data
  Future<void> clearAll() async {
    await clearBrowserKey();
    await clearUserData();
  }
}
