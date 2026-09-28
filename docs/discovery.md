# 官网与发现页

首页快捷入口和用户菜单打开 `/discover`，沿用现有登录保护，不增加主导航项。
官网默认 `https://vpn.donghuyun.top`；目录来自 Xboard 的 SentinelDiscovery 插件。
所有链接通过系统外部浏览器打开，不追加认证参数、账户信息或订阅链接。

## 配置与缓存

SDK 原始 ConfigData、统一 ConfigModel 和两个面板适配器均支持 `discovery`。
继续使用加密网关内的 `GET /api/v1/guest/comm/config`，不新增明文请求。
`landing_page_url` 是独立官网设置，不读取面板 `app_url`。

- 分类为 search、video、social、ai、developer，分类内按 sort_order、id 升序。
- 缺失、错误类型或非法的 discovery/站点字段不会破坏注册配置解码。
- 进入首页快捷入口区域或发现页时刷新，同一时刻的请求合并。
- SharedPreferences 的 `sentinel.discovery.v1` 保存上次成功目录；断网保留缓存并提示重试。
- 成功收到空目录或缺少 discovery 时覆盖缓存，保证下架和插件停用生效。
- 分类筛选与名称、域名、简介搜索在本地完成，无连通性检测。
- 浏览器返回失败或抛错时提供错误提示与复制链接操作。

## 开发检查

SDK 是子模块，提交时先提交 `lib/sdk/flutter_xboard_sdk` 内的修改，再更新父仓库引用。
SDK 的生成文件被其 gitignore 排除；干净检出后按既有构建流程生成：

```sh
cd lib/sdk/flutter_xboard_sdk
dart run build_runner build
cd ../../..
dart run intl_utils:generate
flutter test test/xboard/discovery_test.dart test/ui/discovery_page_test.dart
flutter test test/ui/sentinel_theme_navigation_test.dart test/ui/sentinel_screens_test.dart
```

可选 `flutter test --dart-define=CAPTURE_UI=true test/ui/discovery_page_test.dart`，
布局截图写入 `build/discovery-previews`（手机/宽屏，浅色/深色）。此目录不提交。

## 发布验收

先安装并启用 Xboard 插件，确认官网设置、搜索、编辑、排序、上下架管理页面可用，
再发布客户端。两端刷新应同步后台变更；停用插件后成功刷新应清空推荐。
真机检查外部浏览器返回、VPN 连接保持，以及弱网下的缓存与重试。
本功能不验证、不承诺推荐站点当前可访问。
