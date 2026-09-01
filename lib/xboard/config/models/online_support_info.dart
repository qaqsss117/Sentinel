import 'config_entry.dart';

/// 在线客服信息
/// 
/// 扩展ConfigEntry，添加在线客服特有的属性
class OnlineSupportInfo extends ConfigEntry {
  final String apiBaseUrl;
  final String wsBaseUrl;

  const OnlineSupportInfo({
    required String url,
    required String description,
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    Map<String, dynamic>? metadata,
  }) : super(url: url, description: description, metadata: metadata);

  /// 从JSON创建在线客服信息
  factory OnlineSupportInfo.fromJson(Map<String, dynamic> json) {
    return OnlineSupportInfo(
      url: json['url'] as String? ?? '',
      description: json['description'] as String? ?? '',
      apiBaseUrl: json['apiBaseUrl'] as String? ?? '',
      wsBaseUrl: json['wsBaseUrl'] as String? ?? '',
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'apiBaseUrl': apiBaseUrl,
      'wsBaseUrl': wsBaseUrl,
    });
    return json;
  }

  /// 验证URL格式
  bool validate() {
    return _isValidHttpUrl(url);
  }

  /// 获取验证错误信息
  List<String> getValidationErrors() {
    final errors = <String>[];

    if (!_isValidHttpUrl(url)) {
      errors.add('Support URL must use http or https protocol: $url');
    }

    return errors;
  }

  /// 检查是否为有效的HTTP URL
  bool _isValidHttpUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }

  @override
  String toString() {
    return 'OnlineSupportInfo(url: $url)';
  }
}