import 'encrypted_subscription_service.dart';

/// 兼容旧调用点。订阅 token 不再通过多个明文 URL 竞速。
class ConcurrentSubscriptionService {
  static Future<SubscriptionResult> raceGetEncryptedSubscriptionFromLogin({
    bool preferEncrypt = true,
  }) {
    return EncryptedSubscriptionService.getEncryptedSubscriptionFromLogin();
  }

  static Future<SubscriptionResult> raceGetEncryptedSubscription(
    String token, {
    bool preferEncrypt = true,
  }) {
    return EncryptedSubscriptionService.getEncryptedSubscription(token);
  }
}