import 'package:flutter_test/flutter_test.dart';
import 'package:storaq/config.dart';

void main() {
  test('AppConfig defaults to local backend outside Android', () {
    expect(AppConfig.baseUrl, 'http://localhost:3000');
  });
}
