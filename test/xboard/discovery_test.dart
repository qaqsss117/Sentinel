import 'dart:async';
import 'dart:convert';
import 'package:fl_clash/xboard/features/discovery/discovery_store.dart';
import 'package:fl_clash/xboard/router/auth_redirect.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:flutter_xboard_sdk/src/adapters/xboard/xboard_config_adapter.dart';
import 'package:flutter_xboard_sdk/src/adapters/v2board/v2board_config_adapter.dart';
import 'package:flutter_xboard_sdk/src/panels/xboard/apis/xboard_config_api.dart';
import 'package:flutter_xboard_sdk/src/panels/v2board/apis/v2board_config_api.dart';
import 'package:flutter_xboard_sdk/src/panels/xboard/models/xboard_config_models.dart';

Map<String, Object?> site(
  int id, {
  String category = 'search',
  int order = 10,
  String? logoUrl,
}) => {
  'id': id,
  'name': 'Site $id',
  'url': 'https://site$id.example.com/',
  'category': category,
  'description': 'Useful tools',
  'sort_order': order,
  if (logoUrl != null) 'logo_url': logoUrl,
};

final sample = DiscoveryCatalog.fromJson({
  'landing_page_url': 'https://official.example.com/',
  'sites': [site(1), site(2, category: 'developer')],
});

class _XBoardApi implements XBoardConfigApi {
  _XBoardApi(this.data);
  final ConfigData data;
  @override
  Future<ConfigData> getConfig() async => data;
}

class _V2BoardApi implements V2BoardConfigApi {
  _V2BoardApi(this.data);
  final ConfigData data;
  @override
  Future<ConfigData> getConfig() async => data;
}

void main() {
  test(
    'missing and malformed discovery preserve registration configuration',
    () {
      for (final value in [
        null,
        false,
        1,
        'invalid',
        [],
        {'sites': 'invalid'},
        {
          'sites': [null, {}, 2],
        },
      ]) {
        final json = <String, dynamic>{
          'is_email_verify': 1,
          'is_invite_force': 1,
          'discovery': value,
        };
        final raw = ConfigData.fromJson(json);
        final adapted = ConfigModel.fromJson(json);
        expect(raw.isEmailVerify, isTrue);
        expect(adapted.isInviteForce, isTrue);
        expect(raw.discovery.sites, isEmpty);
        expect(
          adapted.discovery.landingPageUrl,
          DiscoveryCatalog.defaultLandingPageUrl,
        );
      }
      expect(ConfigData.fromJson({}).discovery.sites, isEmpty);
      expect(ConfigModel.fromJson({}).discovery.sites, isEmpty);
    },
  );

  test(
    'malformed entries are skipped, IDs deduplicated, category and order respected',
    () {
      final catalog = DiscoveryCatalog.fromJson({
        'landing_page_url': 'http://invalid.example.com',
        'sites': [
          site(9, category: 'developer'),
          site(3),
          site(2),
          site(1, order: 1),
          site(1),
          null,
          false,
          [],
          {'id': 'invalid'},
          {...site(4), 'url': 'https://user:pass@example.com'},
          {...site(5), 'url': 'http://example.com'},
          {...site(6), 'enabled': false},
          {...site(7), 'category': 'other'},
          {...site(8), 'name': '  '},
        ],
      });
      expect(catalog.landingPageUrl, DiscoveryCatalog.defaultLandingPageUrl);
      expect(catalog.sites.map((s) => s.id), [1, 2, 3, 9]);
      expect(
        DiscoveryCatalog.fromJson(
          jsonDecode(jsonEncode(catalog.toJson())),
        ).toJson(),
        catalog.toJson(),
      );
    },
  );

  test('logo URLs are optional and invalid values fall back to initials', () {
    final catalog = DiscoveryCatalog.fromJson({
      'sites': [
        site(1, logoUrl: 'https://images.example.com/google.png'),
        {...site(2), 'logo_url': 'http://images.example.com/logo.png'},
        {...site(3), 'logo_url': 'https://user:pass@example.com/logo.png'},
      ],
    });
    expect(catalog.sites.map((entry) => entry.logoUrl), [
      'https://images.example.com/google.png',
      null,
      null,
    ]);
    expect(
      catalog.toJson()['sites'],
      contains(
        containsPair('logo_url', 'https://images.example.com/google.png'),
      ),
    );
    expect(
      catalog.toJson()['sites'],
      isNot(contains(containsPair('logo_url', isNull))),
    );
  });

  test('only valid credential-free HTTPS URLs are accepted', () {
    for (final url in [
      'http://example.com',
      'javascript:alert(1)',
      'https://user:pass@example.com',
      'https://',
      'https://example.com/a b',
      r'https://example.com\path',
      'https://example.com:99999',
      'https://example.com:bad',
    ]) {
      expect(DiscoveryCatalog.httpsUri(url), isNull, reason: url);
    }
    expect(
      DiscoveryCatalog.httpsUri('https://example.com/path?q=search#section'),
      isNotNull,
    );
  });

  test(
    'both SDK adapters carry discovery while keeping existing config fields',
    () async {
      final raw = ConfigData.fromJson({
        'app_url': 'https://panel.example.com',
        'is_email_verify': 1,
        'discovery': sample.toJson(),
      });
      for (final result in [
        await XBoardConfigAdapter(_XBoardApi(raw)).getConfig(),
        await V2BoardConfigAdapter(_V2BoardApi(raw)).getConfig(),
      ]) {
        expect(result.discovery.toJson(), sample.toJson());
        expect(result.appUrl, 'https://panel.example.com');
        expect(result.isEmailVerify, isTrue);
      }
    },
  );

  test(
    'failed refresh keeps cache; successful empty and missing fields clear it',
    () async {
      var fail = true;
      var response = sample;
      String? saved;
      final store = DiscoveryStore(
        fetch: () async {
          if (fail) throw Exception('offline');
          return response;
        },
        readCache: () async => jsonEncode(sample.toJson()),
        writeCache: (value) async {
          saved = value;
        },
      );
      addTearDown(store.dispose);
      await store.refresh();
      expect(store.catalog.toJson(), sample.toJson());
      expect(store.refreshFailed, isTrue);
      expect(saved, isNull);
      fail = false;
      response = const DiscoveryCatalog();
      await store.refresh();
      expect(store.refreshFailed, isFalse);
      expect(store.catalog.sites, isEmpty);
      response = sample;
      await store.refresh();
      expect(store.catalog.sites, hasLength(2));
      response = ConfigModel.fromJson({}).discovery;
      await store.refresh();
      expect(store.catalog.sites, isEmpty);
      expect(DiscoveryCatalog.fromJson(jsonDecode(saved!)).sites, isEmpty);
    },
  );

  test(
    'corrupt cache and disk errors do not discard a fresh directory',
    () async {
      final store = DiscoveryStore(
        fetch: () async => sample,
        readCache: () async => 'not json',
        writeCache: (_) async => throw Exception('disk unavailable'),
      );
      addTearDown(store.dispose);
      await store.refresh();
      expect(store.refreshFailed, isFalse);
      expect(store.catalog.toJson(), sample.toJson());
      expect(
        store.filtered(category: 'developer', query: 'TOOLS').map((s) => s.id),
        [2],
      );
      expect(store.filtered(query: 'site1.example.com').map((s) => s.id), [1]);
      expect(store.filtered(category: 'video'), isEmpty);
    },
  );

  test('concurrent refresh coalesces requests and disposal is safe', () async {
    final response = Completer<DiscoveryCatalog>();
    var calls = 0;
    final store = DiscoveryStore(
      fetch: () {
        calls++;
        return response.future;
      },
      readCache: () async => null,
      writeCache: (_) async {},
    );
    final first = store.refresh();
    final second = store.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(store.isLoading, isTrue);
    store.dispose();
    response.complete(sample);
    await Future.wait([first, second]);
    expect(store.isLoading, isFalse);
  });

  test('discovery inherits existing authentication requirement', () {
    expect(
      redirectForAuth(
        path: '/discover',
        isInitialized: true,
        isAuthenticated: false,
      ),
      '/login',
    );
    expect(
      redirectForAuth(
        path: '/discover',
        isInitialized: true,
        isAuthenticated: true,
      ),
      isNull,
    );
  });
}
