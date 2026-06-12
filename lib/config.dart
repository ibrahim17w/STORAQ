import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;

class AppConfig {
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;

    if (kDebugMode) {
      if (Platform.isAndroid) return 'http://10.0.2.2:3000';
      if (Platform.isIOS) return 'http://localhost:3000';
      return 'http://localhost:3000';
    }
    return 'https://storaq.onrender.com';
  }
}
