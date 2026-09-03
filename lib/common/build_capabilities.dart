class BuildCapabilities {
  const BuildCapabilities({
    required this.isMsix,
    this.isStoreBuild = false,
  });

  final bool isMsix;
  final bool isStoreBuild;

  bool get supportsTun => !isMsix;
  bool get supportsHelperService => !isMsix;
  bool get supportsLoopbackExemption => !isMsix;
  bool get supportsAutoLaunchControl => !isMsix;
  bool get supportsExternalUpdateCheck => !isStoreBuild;

  bool resolveTunEnabled(bool requested) => supportsTun && requested;
}

const buildCapabilities = BuildCapabilities(
  isMsix: bool.fromEnvironment('MSIX_BUILD'),
  isStoreBuild: bool.fromEnvironment('STORE_BUILD'),
);
