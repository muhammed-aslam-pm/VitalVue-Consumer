import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/user_profile.dart';

class BackgroundPreferences {
  static const _kProfile = 'bg_profile';
  static const _kDeviceId = 'bg_device_id';
  static const _kDeviceMac = 'bg_device_mac';
  static const _kDeviceName = 'bg_device_name';
  static const _kEnableTTS = 'bg_enable_tts';
  static const _kEnablePush = 'bg_enable_push';

  static Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfile, jsonEncode(profile.toJson()));
  }

  static Future<UserProfile?> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kProfile);
    if (str == null) return null;
    try {
      return UserProfile.fromJson(jsonDecode(str));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDevice(String id, String mac, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceId, id);
    await prefs.setString(_kDeviceMac, mac);
    await prefs.setString(_kDeviceName, name);
  }

  static Future<Map<String, String>?> getDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kDeviceId);
    final mac = prefs.getString(_kDeviceMac);
    final name = prefs.getString(_kDeviceName);
    if (id == null || mac == null) return null;
    return {'id': id, 'mac': mac, 'name': name ?? id};
  }
  
  static Future<void> clearDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDeviceId);
    await prefs.remove(_kDeviceMac);
    await prefs.remove(_kDeviceName);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProfile);
    await prefs.remove(_kDeviceId);
    await prefs.remove(_kDeviceMac);
    await prefs.remove(_kDeviceName);
  }

  static Future<bool> getEnableTts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(_kEnableTTS) ?? true;
  }

  static Future<void> setEnableTts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnableTTS, value);
  }

  static Future<bool> getEnablePush() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(_kEnablePush) ?? true;
  }

  static Future<void> setEnablePush(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnablePush, value);
  }
}
