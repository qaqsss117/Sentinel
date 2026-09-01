import 'dart:convert';

import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/infrastructure/http/user_agent_config.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';

final _logger = FileLogger('encrypted_subscription_service.dart');

class EncryptedSubscriptionService {
  static Future<SubscriptionResult> getEncryptedSubscriptionFromLogin({
    bool preferEncrypt = true,
    bool enableRace = true,
  }) async {
    try {
      final subscriptionData = await XBoardSDK.instance.subscription.getSubscription();
      final token = subscriptionData.token ??
          _extractTokenFromSubscriptionUrl(subscriptionData.subscribeUrl);
      if (token == null || token.isEmpty) {
        return SubscriptionResult.failure('订阅凭证无效');
      }

      return await getEncryptedSubscription(token);
    } catch (error, stackTrace) {
      _logger.error('通过加密网关获取订阅失败', error, stackTrace);
      return SubscriptionResult.failure('获取订阅失败');
    }
  }

  static Future<SubscriptionResult> getEncryptedSubscription(
    String token, {
    bool preferEncrypt = true,
    bool enableRace = true,
  }) async {
    if (token.isEmpty) {
      return SubscriptionResult.failure('订阅凭证无效');
    }

    try {
      final userAgent = await UserAgentConfig.get(UserAgentScenario.subscription);
      final path = Uri(
        path: '/api/v1/client/subscribe',
        queryParameters: {
          'token': token,
          'flag': 'flclash',
        },
      ).toString();
      final response = await XBoardSDK.instance.httpService.getEncryptedRawRequest(
        path,
        headers: {
          'Accept': '*/*',
          'User-Agent': userAgent,
        },
      );
      final content = utf8.decode(response.body, allowMalformed: false);
      if (content.trim().isEmpty) {
        return SubscriptionResult.failure('订阅内容为空');
      }

      return SubscriptionResult.success(
        content: content,
        subscriptionUserInfo: response.headers['subscription-userinfo'],
      );
    } catch (error, stackTrace) {
      _logger.error('加密订阅请求失败', error, stackTrace);
      return SubscriptionResult.failure('加密订阅请求失败');
    }
  }

  static Future<SubscriptionResult> getSubscriptionSmart(
    String? token, {
    bool preferEncrypt = true,
    bool enableRace = true,
  }) {
    if (token == null || token.isEmpty) {
      return getEncryptedSubscriptionFromLogin();
    }
    return getEncryptedSubscription(token);
  }

  static Future<SubscriptionResult> getRaceEncryptedSubscriptionFromLogin({
    bool preferEncrypt = true,
    bool enableRace = true,
  }) {
    return getEncryptedSubscriptionFromLogin();
  }

  static Future<SubscriptionResult> getRaceEncryptedSubscription(
    String token, {
    bool preferEncrypt = true,
    bool enableRace = true,
  }) {
    return getEncryptedSubscription(token);
  }

  static String? _extractTokenFromSubscriptionUrl(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    try {
      final uri = Uri.parse(url);
      final queryToken = uri.queryParameters['token'];
      if (queryToken != null && queryToken.isNotEmpty) {
        return queryToken;
      }
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.length >= 16) {
        return uri.pathSegments.last;
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class SubscriptionResult {
  final bool success;
  final String? content;
  final bool encryptionUsed;
  final String? keyUsed = null;
  final String? originalUrl = null;
  final String? subscriptionUserInfo;
  final String? error;

  const SubscriptionResult._({
    required this.success,
    this.content,
    this.encryptionUsed = false,
    this.subscriptionUserInfo,
    this.error,
  });

  factory SubscriptionResult.success({
    required String content,
    String? subscriptionUserInfo,
  }) =>
      SubscriptionResult._(
        success: true,
        content: content,
        encryptionUsed: true,
        subscriptionUserInfo: subscriptionUserInfo,
      );

  factory SubscriptionResult.failure(String error) =>
      SubscriptionResult._(success: false, error: error);

  @override
  String toString() => 'SubscriptionResult(success: $success, encryption: $encryptionUsed)';
}