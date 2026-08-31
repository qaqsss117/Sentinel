class BuildCapabilities {
  const BuildCapabilities({required this.isMsix});

  final bool isMsix;

  bool get supportsTun => !isMsix;
  bool get supportsHelperService => !isMsix;
  bool get supportsLoopbackExemption => !isMsix;
  bool get supportsAutoLaunchControl => !isMsix;

  bool resolveTunEnabled(bool requested) => supportsTun && requested;
}

const buildCapabilities = BuildCapabilities(
  isMsix: bool.fromEnvironment('MSIX_BUILD'),
);
