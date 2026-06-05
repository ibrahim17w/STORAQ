// lib/utils/tr.dart
import '../lang/translations.dart';

String tr(String key, {required String fallback}) {
  final result = t(key);
  if (result == null || result == key) return fallback;
  return result;
}
