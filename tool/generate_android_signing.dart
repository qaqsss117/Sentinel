import 'dart:io';
import 'dart:math';

const _alias = 'sentinel-release';
const _keystoreName = 'sentinel-release.jks';
const _certificateName = 'sentinel-release-cert.pem';

Future<void> main() async {
  final projectDirectory = Directory.current;
  if (!File('${projectDirectory.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('Run this command from the Sentinel project root.');
    exitCode = 2;
    return;
  }

  final signingDirectory = Directory(
    '${projectDirectory.path}/signing/android',
  );
  signingDirectory.createSync(recursive: true);

  final keystore = File('${signingDirectory.path}/$_keystoreName');
  final certificate = File(
    '${signingDirectory.path}/$_certificateName',
  );
  final properties = File('${signingDirectory.path}/signing.properties');

  if (keystore.existsSync() || properties.existsSync()) {
    stderr.writeln(
      'Android signing files already exist. Refusing to overwrite them.',
    );
    exitCode = 2;
    return;
  }

  final storePassword = _randomPassword();
  final keyPassword = _randomPassword();

  final generateResult = await Process.run(
    'keytool',
    [
      '-genkeypair',
      '-v',
      '-keystore',
      keystore.path,
      '-storetype',
      'JKS',
      '-storepass',
      storePassword,
      '-keypass',
      keyPassword,
      '-alias',
      _alias,
      '-keyalg',
      'RSA',
      '-keysize',
      '4096',
      '-sigalg',
      'SHA256withRSA',
      '-validity',
      '10000',
      '-dname',
      'CN=Sentinel VPN, OU=Mobile, O=Sentinel, L=Unknown, ST=Unknown, C=CN',
      '-noprompt',
    ],
    runInShell: Platform.isWindows,
  );

  if (generateResult.exitCode != 0) {
    stderr.write(generateResult.stderr);
    exitCode = generateResult.exitCode;
    return;
  }

  final exportResult = await Process.run(
    'keytool',
    [
      '-exportcert',
      '-rfc',
      '-keystore',
      keystore.path,
      '-storepass',
      storePassword,
      '-alias',
      _alias,
      '-file',
      certificate.path,
    ],
    runInShell: Platform.isWindows,
  );

  if (exportResult.exitCode != 0) {
    keystore.deleteSync();
    stderr.write(exportResult.stderr);
    exitCode = exportResult.exitCode;
    return;
  }

  properties.writeAsStringSync(
    'storeFile=$_keystoreName\n'
    'storePassword=$storePassword\n'
    'keyAlias=$_alias\n'
    'keyPassword=$keyPassword\n',
    flush: true,
  );

  stdout.writeln('Android release signing created:');
  stdout.writeln('  Keystore: ${keystore.path}');
  stdout.writeln('  Public certificate: ${certificate.path}');
  stdout.writeln('  Gradle properties: ${properties.path}');
  stdout.writeln('Passwords were saved only in signing.properties.');
}

String _randomPassword() {
  const alphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  final random = Random.secure();
  return List.generate(
    32,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}