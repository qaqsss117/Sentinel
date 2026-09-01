# Packaging signing material

This directory is the single location for packaging certificates and private
signing configuration. Private keys, passwords, and account-specific files are
ignored by Git. Back them up in an encrypted password manager or secrets vault.

## Android

Generate the Android release key from the project root:

```powershell
dart run tool/generate_android_signing.dart
```

The command creates:

- `android/sentinel-release.jks`: release private key and certificate.
- `android/sentinel-release-cert.pem`: exportable public certificate.
- `android/signing.properties`: passwords and Gradle references.

Do not regenerate the key after publishing an APK or AAB. Losing it can prevent
future updates unless Google Play App Signing and key reset options are in use.

## Microsoft Store MSIX

Microsoft Store signs an accepted MSIX with a Microsoft certificate. A PFX is
not required for Store submission. In Partner Center, open the app, then
**Product management > Product identity > View app identity details** and copy:

- `Package/Identity/Name` to `identity_name`.
- `Package/Identity/Publisher` to `publisher`.
- `Properties/PublisherDisplayName` to `publisher_display_name`.

Copy `windows/store_identity.yaml.example` to
`windows/store_identity.yaml`, replace the values exactly, including case and
punctuation, then build normally:

```powershell
dart setup.dart windows --arch amd64
```

The MSIX packager automatically loads that private file, sets Store mode, and
leaves the upload package unsigned for Microsoft Store signing.

To use another private MSIX configuration file for one build:

```powershell
$env:SENTINEL_MSIX_CONFIG = 'signing/windows/sideload_signing.yaml'
dart setup.dart windows --arch amd64
Remove-Item Env:SENTINEL_MSIX_CONFIG
```

Outside Microsoft Store, the MSIX must be signed with your own trusted PFX.
Use `windows/sideload_signing.yaml.example` as the private configuration.

## Apple platforms

Keep exported `.p12`, `.cer`, and `.mobileprovision` files under `apple/`.
These files are ignored by Git. Apple signing is not currently wired into
`setup.dart`.