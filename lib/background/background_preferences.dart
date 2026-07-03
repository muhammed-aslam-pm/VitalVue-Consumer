import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/patient_profile.dart';

class BackgroundPreferences {
  static const _kProfile = 'bg_profile';
  static const _kDeviceId = 'bg_device_id';
  static const _kDeviceMac = 'bg_device_mac';
  static const _kDeviceName = 'bg_device_name';

  static Future<void> saveProfile(PatientProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfile, jsonEncode(profile.toJson()));
  }

  static Future<PatientProfile?> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kProfile);
    if (str == null) return null;
    try {
      return PatientProfile.fromJson(jsonDecode(str));
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
}
