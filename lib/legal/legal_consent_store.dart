import 'package:shared_preferences/shared_preferences.dart';

import 'legal_documents.dart';

class LegalConsentStore {
  static const acceptedVersionKey = 'legal_consent_accepted_version';
  static const acceptedAtKey = 'legal_consent_accepted_at';

  static Future<bool> isAccepted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(acceptedVersionKey) == legalConsentVersion;
  }

  static Future<bool> accept() async {
    final preferences = await SharedPreferences.getInstance();
    final versionSaved = await preferences.setString(
      acceptedVersionKey,
      legalConsentVersion,
    );
    final timeSaved = await preferences.setString(
      acceptedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    return versionSaved && timeSaved;
  }
}