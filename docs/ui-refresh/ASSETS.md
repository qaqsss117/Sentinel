# 素材来源清单

来源工程：`../SentineliOS`，参考提交 `d8c6e86fdedad5328edfd407fb22ac38fd710a39`。iOS 工程保持未修改。

以下素材按用户授权复用；本清单记录工程来源，不另行声明第三方授权。素材文件保持字节一致，通过 SHA-256 校验。

| 客户端资源 | iOS 相对路径 | 用途 |
| --- | --- | --- |
| `assets/images/sentinel/planet.png` | `XiaoXiong/Assets.xcassets/mars.imageset/cartoon-1298905_1280.png` | 品牌背景装饰 |
| `assets/images/sentinel/globe.png` | `XiaoXiong/Assets.xcassets/globe.imageset/globe.png` | 桌面登录品牌插画 |
| `assets/animations/sentinel/connection.json` | `XiaoXiong/DefaultUI/8dfa14a6.json` | 连接操作中的外环 |
| `assets/animations/sentinel/loading.json` | `XiaoXiong/DefaultUI/65ea130a.json` | 连接与支付处理中 |
| `assets/animations/sentinel/secured.json` | `XiaoXiong/DefaultUI/51a05581.json` | 实际连接成功状态 |

## SHA-256

- `assets/images/sentinel/planet.png`: `ac805e4b6fff40fe94c6c72bf0faf41695540e2726dbd3e1ebe50585ede6f7fe`
- `assets/images/sentinel/globe.png`: `a268f7694bb5c6530e7a553de630858236044687c3194bef86b07f611d2cc605`
- `assets/animations/sentinel/connection.json`: `3f91f43a8e8bc0715e5647df76df6c712a8d31787baf527451f1ba986343093a`
- `assets/animations/sentinel/loading.json`: `c7323a564ca52f65976344f8e7d0ef3cb2e2792ac92ada589d1ed46e68087be5`
- `assets/animations/sentinel/secured.json`: `0d27c955b144f8c3ac19bb67890e8c5bea83631e2a19b6a3d04d0abdf84c9780`

## 使用约定

- 资源索引位于 `lib/theme/sentinel_assets.dart`，资源目录已在 `pubspec.yaml` 注册。
- 继续使用客户端原有透明标志 `assets/images/icon.png`；没有替换应用图标或启动图标。
- 三份 Lottie 均可解析且不引用外部图片；减少动态效果或分支隐藏时显示静态图标。
- 新增 Lottie 3.3.0；限定为 `<3.3.1`，兼容现有 archive 3.x 依赖。其他已锁定依赖版本未更改。
- 截图字体从本机 Microsoft YaHei 读取，字体文件未复制、未加入应用资源。
- 文案仍由 Flutter 本地化和业务数据渲染；没有复制 iOS 图片中的价格或收益宣传。
