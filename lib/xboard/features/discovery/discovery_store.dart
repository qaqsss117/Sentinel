import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';

/// Failed requests keep the last catalog; successful empty responses clear it.
class DiscoveryStore extends ChangeNotifier {
  DiscoveryStore({
    required this.fetch,
    required this.readCache,
    required this.writeCache,
  });

  final Future<DiscoveryCatalog> Function() fetch;
  final Future<String?> Function() readCache;
  final Future<void> Function(String) writeCache;
  DiscoveryCatalog catalog = const DiscoveryCatalog();
  bool isLoading = false;
  bool refreshFailed = false;
  bool _cacheLoaded = false;
  bool _disposed = false;
  Future<void>? _inFlight;

  Future<void> refresh() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<void> _refresh() async {
    isLoading = true;
    refreshFailed = false;
    _notify();
    if (!_cacheLoaded) {
      _cacheLoaded = true;
      try {
        final cached = await readCache();
        if (cached != null) {
          catalog = DiscoveryCatalog.fromJson(jsonDecode(cached));
        }
      } catch (_) {
        // Corrupt local storage must not block a network refresh.
      }
      _notify();
    }
    try {
      catalog = await fetch();
      try {
        await writeCache(jsonEncode(catalog.toJson()));
      } catch (_) {
        // A successfully fetched catalog remains usable without disk storage.
      }
    } catch (_) {
      refreshFailed = true;
    } finally {
      isLoading = false;
      _notify();
    }
  }

  List<DiscoverySite> filtered({String? category, String query = ''}) {
    final term = query.trim().toLowerCase();
    return catalog.sites
        .where(
          (site) =>
              (category == null || site.category == category) &&
              (term.isEmpty ||
                  [
                    site.name,
                    site.url,
                    site.description,
                  ].join(' ').toLowerCase().contains(term)),
        )
        .toList();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
