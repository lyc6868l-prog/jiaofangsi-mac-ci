# 阶段1 cleanup_dup 模块本地可用化与 macOS 导入链路修复归档

## 归档信息

- 归档日期：2026-04-06
- 归档范围：`apps/dj_flutter` 的 cleanup_dup 本地可用化、真实文件导入接入、macOS 调试权限修复、Rust/Python 本地运行链路打通
- 当前状态：本项目按本地开发工具模式运行，cleanup_dup 已可在 macOS 调试构建中真实导入文件/文件夹、启动 Python runtime、执行标题清理与查重删除主流程

## 本次归档结论

### 一、cleanup_dup 已进入本地可用状态

当前 macOS 调试版已具备以下可用能力：

- 点击导入可打开系统文件选择器
- 可选择真实音频文件
- 可选择真实文件夹
- Finder 拖拽文件或文件夹到导入区可触发真实导入
- Flutter 可启动项目内 Python runtime
- Python runtime 可继续驱动 Rust `dj_scan_core`
- 标题清理、极速比对、内容比对、审阅删除链路已能按现有实现运行

### 二、本次修复的导入失败根因

本轮发现的导入失败不是单点问题，而是三个根因叠加。

#### 1. 点击导入最初仍是 mock 行为

早期 `cleanup_dup_controller.dart` 中的点击导入只是生成假路径，并未接入系统文件选择器。

影响：

- 点击后不会打开 macOS 文件选择界面
- UI 看似有入口，但并不具备真实导入能力

本次修复：

- 接入 `file_selector`
- 改为真实 `openFiles(...)` 与 `getDirectoryPath(...)`

#### 2. 拖拽导入最初只支持 Flutter 内部拖拽，不支持 Finder 系统拖拽

早期拖拽区使用的是 `DragTarget<String>`，它只能接收 Flutter 应用内部的 `Draggable` 数据，不能接收 Finder 拖入的系统文件。

影响：

- 界面可以做出拖拽高亮反馈
- 但 Finder 文件不会真正落入业务导入链路

本次修复：

- 接入 `desktop_drop`
- 改为 `DropTarget`
- 将系统拖放得到的真实路径传给现有 `loadTargets(...)`

#### 3. macOS App Sandbox 阻止 Flutter 启动外部 Python 进程

这是本轮最关键的真实阻塞点。

现象：

- 界面点击导入后仍无法进入真实处理
- 顶部错误提示为 `无法启动 Python runtime: Operation not permitted`

真实原因：

- `macos/Runner/DebugProfile.entitlements`
- `macos/Runner/Release.entitlements`

中开启了 `com.apple.security.app-sandbox`

而本项目属于本地开发工具，不是受限上架应用。Flutter 桌面端需要通过 `Process.start(...)` 拉起外部 Python runtime，这在 sandbox 下会被系统拒绝。

影响：

- 不能启动 Python runtime
- 所有依赖 runtime 的导入、扫描、删除流程都会被卡死
- 从 UI 看像是导入失败，实质是后端进程创建被系统权限拦截

本次修复：

- 将调试与发布 entitlement 中的 `com.apple.security.app-sandbox` 改为 `false`
- 保持项目按本地开发工具模式运行

### 三、后续模块必须遵守的通用规则

#### 规则 1：不要把导入入口做成 mock

如果模块需要文件导入：

- 必须直接接系统文件选择器
- 必须明确支持的是文件、文件夹，还是二者都支持
- 不允许再用假路径占位替代真实导入流程

#### 规则 2：不要把 Finder 拖拽误当作 Flutter 内部拖拽

如果模块需要桌面拖拽：

- 不能使用普通 `DragTarget` 代替系统拖放
- 必须使用桌面系统拖放插件或原生桥接
- 必须验证 Finder 拖入后得到的是可读真实路径，而不是只有视觉反馈

#### 规则 3：凡是需要 `Process.start(...)`、调用外部解释器、外部工具、worker 进程的本地工具模块，都必须先检查 macOS sandbox

适用场景包括：

- 启动 Python runtime
- 启动 Rust worker 二进制
- 调用 ffmpeg
- 调用外部脚本、命令行工具、OCR、转码器等

开发期默认规则：

- 本项目是本地开发工具，不按受限上架应用模式运行
- 新模块如需拉起外部进程，必须先确认 `com.apple.security.app-sandbox` 不处于阻断状态
- 否则 UI 层经常只会表现为 `无法启动 runtime`、`导入无反应`、`按钮无效`，但根因其实是 macOS 权限拒绝

### 四、本次落地改动

#### Flutter 依赖

- `desktop_drop`
- `file_selector`

#### 关键文件

- `apps/dj_flutter/pubspec.yaml`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/controllers/cleanup_dup_controller.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/controllers/python_cleanup_dup_task_bridge.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/widgets/hardware_widgets.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/widgets/title_cleanup_panel.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/widgets/duplicate_search_panel.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/cleanup_dup_entry_page.dart`
- `apps/dj_flutter/macos/Runner/DebugProfile.entitlements`
- `apps/dj_flutter/macos/Runner/Release.entitlements`

### 五、本次验证结果

已通过：

- `flutter analyze`
- `flutter test test/widget_test.dart`
- `flutter build macos --debug`

## 当前阶段结论

截至本次归档：

1. cleanup_dup 已从界面可看升级为本地可用
2. 文件选择、文件夹选择、Finder 拖拽三条真实导入链路已接通
3. Python runtime 启动失败的根因已确认为 macOS sandbox，并已修复
4. 该问题已上升为后续所有本地工具模块的通用接入规则
5. 后续新模块凡涉及外部进程与本地文件导入，必须先做系统权限与桌面拖放能力检查

## 归档用途

本归档用于：

- 作为 cleanup_dup 进入本地可用阶段的阶段证据
- 作为后续模块接入文件导入、桌面拖拽、外部 runtime 的先行避坑记录
- 避免其他模块重复踩入 mock 导入、伪拖拽、sandbox 阻断外部进程三类问题

## 关联文件

- `docs/governance/08_阶段验收/阶段1_cleanup_dup模块Python真实任务落地与Rust桥接环境归档_2026-04-05.md`
- `docs/governance/09_更新记录/09_更新记录.md`
- `文件对照表.md`
- `apps/dj_flutter/macos/Runner/DebugProfile.entitlements`
- `apps/dj_flutter/macos/Runner/Release.entitlements`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/controllers/cleanup_dup_controller.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/widgets/hardware_widgets.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/controllers/python_cleanup_dup_task_bridge.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/cleanup_dup_entry_page.dart`
- `apps/dj_flutter/pubspec.yaml`
