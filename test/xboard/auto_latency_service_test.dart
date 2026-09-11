import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/xboard/features/latency/services/auto_latency_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _nodes = [
  Proxy(name: 'vless-1', type: 'Vless'),
  Proxy(name: 'vless-2', type: 'Vless'),
  Proxy(name: 'hy2-1', type: 'Hysteria2'),
  Proxy(name: 'hy2-2', type: 'Hysteria2'),
];

// Same structure as a delivered subscription, with credentials removed.
const _subscriptionGroups = [
  Group(
    name: 'main',
    type: GroupType.Selector,
    all: [
      Proxy(name: 'auto', type: 'URLTest'),
      Proxy(name: 'fallback', type: 'Fallback'),
      Proxy(name: 'DIRECT', type: 'Direct'),
      ..._nodes,
    ],
  ),
  Group(name: 'auto', type: GroupType.URLTest, now: 'vless-1', all: _nodes),
  Group(
    name: 'fallback',
    type: GroupType.Fallback,
    now: 'vless-1',
    all: _nodes,
  ),
];

class _TestGroups extends Groups {
  _TestGroups(this.groups);
  final List<Group> groups;
  @override
  List<Group> build() => groups;
}

class _TestConfig extends PatchClashConfig {
  @override
  ClashConfig build() => const ClashConfig(mode: Mode.rule);
}

class _TestSettings extends AppSetting {
  @override
  AppSettingProps build() => const AppSettingProps();
}

Future<void> _initialize(
  WidgetTester tester,
  AutoLatencyService service,
  List<Group> groups,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        groupsProvider.overrideWith(() => _TestGroups(groups)),
        patchClashConfigProvider.overrideWith(_TestConfig.new),
        appSettingProvider.overrideWith(_TestSettings.new),
        selectedMapProvider.overrideWithValue({'main': 'vless-1'}),
      ],
      child: Consumer(
        builder: (context, ref, child) {
          service.initialize(ref);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  addTearDown(service.dispose);
}

void main() {
  testWidgets(
    'automatically tests Hysteria2 nodes after subscription group entries',
    (tester) async {
      final automatic = <String>[];
      final manual = <String>[];
      final service = AutoLatencyService(
        delayTest: (nodes, _) async =>
            automatic.addAll(nodes.map((p) => p.name)),
        proxyDelayTest: (node, _) async => manual.add(node.name),
      );
      await _initialize(tester, service, _subscriptionGroups);

      // The manually selected Hysteria2 node works, so it must also be scheduled
      // automatically without depending on its position in the subscription.
      await service.testProxy(_nodes.last, forceTest: true);
      expect(manual, ['hy2-2']);
      await service.testCurrentGroupNodes();
      expect({...automatic, ...manual}, containsAll(_nodes.map((p) => p.name)));
      expect(automatic, isNot(contains('DIRECT')));
      expect(automatic, isNot(contains('auto')));
      expect(automatic.toSet().length, automatic.length);
      service.dispose();
    },
  );

  testWidgets('initial automatic pass covers nodes beyond the first five', (
    tester,
  ) async {
    final tested = <String>[];
    final nodes = [
      for (var i = 0; i < 7; i++)
        Proxy(name: 'node-$i', type: i < 5 ? 'Vless' : 'Hysteria2'),
    ];
    final service = AutoLatencyService(
      delayTest: (batch, _) async => tested.addAll(batch.map((p) => p.name)),
    );
    await _initialize(tester, service, [
      Group(name: 'main', type: GroupType.Selector, all: nodes),
    ]);

    await service.testCurrentGroupNodes();
    expect(tested, nodes.map((p) => p.name).toList());
    service.dispose();
  });

  testWidgets('nested groups are expanded once and group cycles terminate', (
    tester,
  ) async {
    final tested = <String>[];
    final service = AutoLatencyService(
      delayTest: (batch, _) async => tested.addAll(batch.map((p) => p.name)),
    );
    await _initialize(tester, service, [
      const Group(
        name: 'main',
        type: GroupType.Selector,
        all: [
          Proxy(name: 'nested', type: 'Selector'),
          Proxy(name: 'REJECT', type: 'Reject'),
          ..._nodes,
        ],
      ),
      const Group(
        name: 'nested',
        type: GroupType.Selector,
        all: [
          Proxy(name: 'main', type: 'Selector'),
          ..._nodes,
        ],
      ),
    ]);

    await service.testCurrentGroupNodes();
    expect(tested, _nodes.map((p) => p.name).toList());
    service.dispose();
  });

  testWidgets(
    'batches wait for completion and overlapping triggers do not duplicate requests',
    (tester) async {
      final batches = <List<String>>[];
      final firstBatch = Completer<void>();
      final service = AutoLatencyService(
        delayTest: (batch, _) async {
          batches.add(batch.map((p) => p.name).toList());
          if (batches.length == 1) await firstBatch.future;
        },
      );
      await _initialize(tester, service, _subscriptionGroups);

      final testing = service.testCurrentGroupNodes(batchSize: 3);
      expect(batches, [
        ['vless-1', 'vless-2', 'hy2-1'],
      ]);
      await service.testCurrentGroupNodes(batchSize: 3);
      expect(batches.length, 1);
      firstBatch.complete();
      await testing;
      expect(batches, [
        ['vless-1', 'vless-2', 'hy2-1'],
        ['hy2-2'],
      ]);

      // A connection/startup trigger arriving just after completion uses cache.
      await service.testCurrentGroupNodes(batchSize: 3);
      expect(batches.length, 2);
      service.dispose();
    },
  );

  testWidgets('disposing the service stops the remaining queued batches', (
    tester,
  ) async {
    final tested = <String>[];
    final firstBatch = Completer<void>();
    final service = AutoLatencyService(
      delayTest: (batch, _) async {
        tested.addAll(batch.map((p) => p.name));
        await firstBatch.future;
      },
    );
    await _initialize(tester, service, _subscriptionGroups);

    final testing = service.testCurrentGroupNodes(batchSize: 1);
    expect(tested, ['vless-1']);
    service.dispose();
    firstBatch.complete();
    await testing;
    expect(tested, ['vless-1']);
  });
}
