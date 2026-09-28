import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'discovery_store.dart';

final discoveryProvider = ChangeNotifierProvider<DiscoveryStore>((ref) {
  const cacheKey = 'sentinel.discovery.v1';
  return DiscoveryStore(
    fetch: () async => (await XBoardSDK.instance.config.getConfig()).discovery,
    readCache: () async =>
        (await SharedPreferences.getInstance()).getString(cacheKey),
    writeCache: (value) async {
      await (await SharedPreferences.getInstance()).setString(cacheKey, value);
    },
  );
});
