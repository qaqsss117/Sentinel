# Notice Feature - 公告功能模块

## 📖 概述

`notice` 是一个**数据服务型**功能模块，负责从服务器获取和管理公告数据。

## 🎯 设计特点

与其他 feature 模块不同，`notice` 模块：
- ❌ **不包含 UI 页面**（pages/）
- ❌ **不包含独立组件**（widgets/）
- ✅ **只提供数据服务**（providers/）

这是因为公告的展示通常以**横幅、提示、对话框**等形式集成在其他页面中，而不需要独立的页面。

## 🏗️ 模块结构

```
notice/
├── README.md               # 本文档
├── notice.dart             # 模块导出文件
└── providers/
    └── notice_provider.dart # 公告数据提供者
```

## 🚀 使用方式

### 1. 导入模块

```dart
import 'package:fl_clash/xboard/features/notice/notice.dart';
```

### 2. 在 UI 中使用

```dart
@override
Widget build(BuildContext context) {
  // 监听公告数据
  final noticesAsync = ref.watch(noticesProvider);
  
  return noticesAsync.when(
    data: (notices) {
      if (notices == null || notices.isEmpty) {
        return SizedBox.shrink();
      }
      
      // 显示公告横幅
      return NoticeBanner(notices: notices);
    },
    loading: () => CircularProgressIndicator(),
    error: (error, stack) => SizedBox.shrink(),
  );
}
```

### 3. 常见使用场景

#### a) 首页横幅
```dart
// 在首页顶部显示最新公告
class HomePage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider).value ?? [];
    
    return Column(
      children: [
        if (notices.isNotEmpty)
          NoticeBanner(notice: notices.first),
        // ... 其他内容
      ],
    );
  }
}
```

#### b) 公告对话框
```dart
// 显示重要公告弹窗
Future<void> showImportantNotices(BuildContext context, WidgetRef ref) async {
  final notices = await ref.read(noticesProvider.future);
  final important = notices?.where((n) => n.isImportant).toList() ?? [];
  
  if (important.isNotEmpty) {
    showDialog(
      context: context,
      builder: (_) => NoticeDialog(notices: important),
    );
  }
}
```

#### c) 设置页面列表
```dart
// 在设置页面显示公告列表
ListTile(
  title: Text('系统公告'),
  trailing: Consumer(
    builder: (_, ref, __) {
      final count = ref.watch(noticesProvider).value?.length ?? 0;
      return Badge(
        label: Text('$count'),
        child: Icon(Icons.notifications),
      );
    },
  ),
  onTap: () => showNoticesList(context),
)
```

## 📊 Provider 说明

### noticesProvider

提供公告列表数据。

**返回类型**: `AsyncValue<List<Notice>?>`

**特性**:
- ✅ 自动缓存
- ✅ 自动刷新
- ✅ 错误处理

**手动刷新**:
```dart
// 刷新公告数据
ref.invalidate(noticesProvider);
// 或
await ref.refresh(noticesProvider.future);
```

## 🔄 数据流

```
UI Layer
  ↓
noticesProvider (监听)
  ↓
XBoardDomainService.getNotices()
  ↓
XBoard API
```

## 💡 为什么不包含 pages/?

公告功能的特点：
1. **展示方式灵活**：横幅、弹窗、列表等多种形式
2. **集成在其他页面**：通常不需要独立的公告页面
3. **轻量级数据**：只需提供数据源，由各页面自行决定如何展示

如果未来需要独立的"公告中心"页面，可以：
- 在 `notice/` 下添加 `pages/notice_page.dart`
- 更新 `notice.dart` 导出该页面

## 📝 数据模型

公告数据通过 XBoard SDK 提供，主要字段：

```dart
class Notice {
  final int id;
  final String title;
  final String content;
  final DateTime createdAt;
  final bool isImportant;
  // ... 其他字段
}
```

具体字段定义参考 `flutter_xboard_sdk` 的 `Notice` 模型。

## 🤝 相关模块

- **shared/widgets/notice_banner.dart**: 公告横幅组件（如果存在）
- **XBoardDomainService**: 提供 `getNotices()` API

## 📞 相关文档

- [XBoard 主文档](../../README.md)
- [Features 模块说明](../README.md)
- [XBoard Domain Service](../../sdk/README.md)

---

**维护者**: SentinelVPN Team
**最后更新**: 2025-10-15
**模块类型**: 数据服务型

