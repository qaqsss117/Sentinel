import 'package:fl_clash/xboard/config/models/online_support_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a Crisp hosted chat URL without legacy API fields', () {
    final config = OnlineSupportInfo.fromJson({
      'url': 'https://go.crisp.chat/chat/embed/?website_id=test-website-id',
      'description': 'Customer support',
    });

    expect(config.validate(), isTrue);
    expect(config.apiBaseUrl, isEmpty);
    expect(config.wsBaseUrl, isEmpty);
    expect(config.getValidationErrors(), isEmpty);
  });

  test('rejects non-HTTP support URLs', () {
    final config = OnlineSupportInfo.fromJson({
      'url': 'wss://example.com/support',
      'description': 'Customer support',
    });

    expect(config.validate(), isFalse);
  });
}