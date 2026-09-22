# 哨兵客户端 UI 更新

Windows 与 Android 共享 iOS 品牌深紫渐变、连接圆环及星球素材，提供完整浅色主题。新安装默认深色；已保存的浅色、系统模式、自定义强调色、文字缩放和纯黑偏好继续保留。旧默认粉灰强调色迁移为品牌紫。

- [主要页面预览](overview.png)
- [可筛选的完整截图图库](index.html)
- [历史界面参考对比](comparison.png)
- [素材来源与 SHA-256](ASSETS.md)
- [截图文件清单与 SHA-256](screenshots/manifest.json)

## 实现范围

| 范围 | 实现 |
| --- | --- |
| 设计体系 | `SentinelTheme`、`SentinelColors`、资源索引及背景、页面容器、卡片、动画组件；统一表单、按钮、弹窗、菜单、导航和标题栏 |
| 首页 | 公告、真实运行状态圆环、节点切换、代理模式、流量和到期信息；主内容宽度 ≥900 使用双栏，最大宽度 1200 |
| 导航 | 首页、套餐、客服、邀请四个 StatefulNavigationShell 分支；Android 始终保留主页面底栏，返回键先回首页；Windows ≥1200 展开侧栏文字 |
| 登录注册 | 共用 760 断点的响应式品牌布局，保留输入、密码选项、验证与焦点状态；支持低窗口和键盘避让 |
| 套餐购买 | 自适应套餐网格、周期、优惠券、金额明细和支付方式；购买页为独立详情路由，返回保留套餐列表 |
| 支付 | 支付等待、取消、失败和成功状态使用统一视觉；显式查询与自动查询仍调用原订单 SDK，只有订单状态 3 显示成功；移除未经查询就提示成功的操作 |
| 邀请客服 | 二维码、统计、钱包、佣金记录；桌面工单列表和会话双栏，窄屏会话与历史入口；输入区、发送中与错误提示继承主题 |
| 其他页面 | 订阅详情、节点入口、公告详情、主题菜单、更新提示、协议及高级配置共用主题；公告翻页和关闭按钮支持键盘、语义提示与 48 像素点击区域 |
| 动画 | 复用 iOS 连接、加载、锁定 Lottie；不可见分支停止动画，系统减少动态效果时显示静态状态 |

连接按钮等待命令完成，阻止重复提交，以运行时状态判定是否连接；未导入有效订阅时禁止启动，运行中仍允许停止。主路由实例保持稳定，切换主题不再重建路由；初始化结束后，已登录会话从加载页进入首页，退出登录后进入登录页。首次协议仍在业务初始化前完成。

后端 API、数据模型、VPN 内核、支付协议均未更改。MSIX 的 TUN 和外部更新等限制仍由原有能力判断控制。Android 调试截图运行于 widget 测试宿主，功能开关由测试构建参数决定；截图中的 TUN 不代表 MSIX 会显示该入口。

## 验证方法与边界

截图来自实际生产页面，通过 provider 和 SDK 接口注入固定的套餐、订阅、节点延迟、邀请和工单数据；支付链接使用 `example.invalid`，浏览器启动由测试替身接管。这部分自动化验证没有使用真实账号，没有发送工单、下单或支付，也没有连接实际 VPN。

覆盖 360×800、390×844、850×600、1440×900，以及 360×640、英文和两倍文字缩放。测试检查布局异常、四入口、分支草稿状态、详情返回、Android 返回键分发、Windows 窗口变化、主题配置兼容、键盘避让、连接等待和失败、缺失订阅、减少动画、支付查询结果及大字体弹窗。截图以 1.5× 输出，主要深浅截图使用逻辑尺寸 390×844 和 1440×900。

`comparison.png` 的上半部分取自仓库原有 `images/` 历史截图，下半部分为本次实际页面截图。两者不是同一版本、设备或业务数据的精确基线，不能用于像素差异回归。`index.html` 和 `screenshots/after/` 可逐页检查本次实际输出。

真实 VPN 连接、支付和工单发送未执行；widget 截图不能替代这些联网流程。真机启动时应用自动恢复设备已有会话，并按原有逻辑读取配置、验证会话和导入订阅；真实数据不放入交付截图。

## 复现

在 Sentinel 工程根目录执行（Flutter 3.47.2、Dart 3.13.2）：

```powershell
flutter --no-version-check test --no-pub
flutter --no-version-check test --no-pub --dart-define=CAPTURE_UI=true test/ui/sentinel_screens_test.dart
dart analyze --format machine lib test
flutter --no-version-check build windows --debug --no-pub
flutter --no-version-check build apk --debug --no-pub
python docs/ui-refresh/generate_gallery.py
```

截图命令在 Windows 从 `C:/Windows/Fonts/msyh.ttc` 加载中文字体；图库生成需要 Pillow。其他系统运行测试不依赖该字体，导出截图时应提供本地中文字体以避免缺字。首次拉取新增依赖需要先运行 `flutter pub get`。

Windows 运行时需保留 EXE 同目录 DLL 和 data 文件夹；APK 使用独立的 `.debug` 应用 ID。这次交付为调试构建验证，未签发发布包或 MSIX 安装包。

## 验证记录（2026-09-21）

| 检查 | 结果 |
| --- | --- |
| 全部 Flutter 测试 | 137 项通过，包含原有测试与新增 UI、动画、主题、路由和连接回归 |
| 截图 | 67 张；深浅、手机、桌面、加载后正常页、空白、错误、连接成功、支付等待/取消/成功、两倍字体公告和支付弹窗 |
| 静态分析 | 0 error；487 warning、86 info，主要来自既有生成代码、未使用成员和弃用接口，分析命令仍返回非零，未将其宣称为全量 lint 清零 |
| Windows | Debug 构建通过；`build/windows/x64/runner/Debug/SentinelVPN.exe` |
| Android | Debug APK 构建通过；`build/app/outputs/flutter-apk/app-debug.apk` |
| MSIX 能力限制 | 现有 BuildCapabilities 测试通过；本轮没有构建 MSIX 发布包 |
| 窗口与返回 | Widget 测试覆盖 850→1440 布局、760 登录断点、页面草稿保留、详情返回和 Android 根分支返回首页 |

本次 Android 初次编译曾输出 Kotlin 跨盘增量缓存告警并自动回退完成；后续增量构建成功。现有 Kotlin 插件版本的未来支持提示未在 UI 任务中升级依赖。`pubspec.lock` 保留原有依赖版本，仅新增 Lottie。

日志保留在本地 `build/ui-all-tests.log`、`build/ui-analyze.log`、`build/ui-windows-build.log`、`build/ui-android-build.log`。素材校验、截图索引及构建产物的大小和哈希见 `validation.json`。

Android 真机（24090RA29C）已成功安装并启动 `com.follow.clash.debug`。真机启动检查发现并修复了已登录会话停在加载页的问题，新增真实重定向函数的路由回归测试。用户解锁后，真机已验证首页、套餐、客服、邀请四入口均保留底栏且可切换；套餐购买详情的系统返回回到套餐列表；邀请页的系统返回回到首页。使用 UIAutomator 检查了导航选中状态，未提交购买、支付、工单或启动 VPN。Windows 原生运行窗口调整尚未人工验收，已由 Widget 测试覆盖布局断点。
