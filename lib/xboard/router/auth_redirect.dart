/// Redirect only authentication boundaries, preserving the current branch and
/// detail route when an initialized session refreshes.
String? redirectForAuth({
  required String path,
  required bool isInitialized,
  required bool isAuthenticated,
}) {
  if (!isInitialized) return path == '/loading' ? null : '/loading';
  if (!isAuthenticated) return path == '/login' ? null : '/login';
  if (path == '/login' || path == '/loading') return '/';
  return null;
}
