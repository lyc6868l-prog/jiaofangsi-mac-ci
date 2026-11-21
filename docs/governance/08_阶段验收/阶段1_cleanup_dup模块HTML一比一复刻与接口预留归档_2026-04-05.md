# 阶段1 cleanup_dup 模块 HTML 一比一复刻与接口预留归档

## 归档信息

- 归档日期：2026-04-05
- 归档范围：Flutter Desktop `cleanup_dup` 模块 UI 复刻、交互校正、主壳接线、测试验证与 Python 对接预留
- 执行方式：基于已定稿 HTML 参考文件进行对照式实现与回归修复
- 当前状态：已完成可运行接入，已通过 `flutter analyze` 与 `flutter test`

## 本次归档对应的参考文件

- `/Users/tattoo/Desktop/全新教坊司/6模块ui参考/查重清理ui.html`

## 本次实际落地文件

- `/Users/tattoo/Desktop/全新教坊司/apps/dj_flutter/lib/features/cleanup_dup/presentation/cleanup_dup_entry_page.dart`
- `/Users/tattoo/Desktop/全新教坊司/apps/dj_flutter/lib/features/cleanup_dup/presentation/models/cleanup_dup_models.dart`
- `/Users/tattoo/Desktop/全新教坊司/apps/dj_flutter/lib/features/cleanup_dup/presentation/controllers/cleanup_dup_controller.dart`
- `/Users/tattoo/Desktop/全新教坊司/apps/dj_flutter/lib/features/cleanup_dup/presentation/widgets/hardware_widgets.dart`
- `/Users/tattoo/Desktop/全新教坊司/apps/dj_flutter/lib/features/cleanup_dup/presentation/widgets/title_cleanup_panel.dart`
- `/Users/tattoo/Desktop/全新教坊司/apps/dj_flutter/lib/features/cleanup_dup/presentation/widgets/duplicate_search_panel.dart`
- `/Users/tattoo/Desktop/全新教坊司/apps/dj_flutter/lib/features/cleanup_dup/presentation/widgets/duplicate_review_modal.dart`
- `/Users/tattoo/Desktop/全新教坊司/apps/dj_flutter/lib/app/shell/app_shell_page.dart`
- `/Users/tattoo/Desktop/全新教坊司/apps/dj_flutter/test/widget_test.dart`

## 已完成增量归档

### 一、模块页面已从占位接入改为真实页面接入

- `cleanupDup` 主壳入口已从内联占位结构切换为真实 `CleanupDupEntryPage`
- 当前主壳进入 `cleanupDup` 时显示真实模块页，不再显示占位文案

### 二、已完成双面板工作区复刻

已落地以下 HTML 核心结构对应物：

- 左侧 `曲目标题广告清理` 面板
- 右侧 `查找删除重复歌曲` 面板
- `lcd-status-strip`
- `config-row`
- `hardware-dropzone`
- `progress-wrapper`
- `main-action-row`
- `review-modal`

### 三、已完成暗黑硬件风视觉层落地

- 使用现有 `flutter_inset_box_shadow` 实现模块面板、输入框、进度轨道等凹槽感
- 补齐深黑底、低透明高光、内阴影、红/绿状态光效
- 补齐 32px 网格背景纹理
- 补齐深色金属风滚动条
- 补齐按钮顶部高光边、hover 光效、下压反馈、绿光闪烁
- 补齐拖拽槽虚线边框、drag-active 红光态、loaded 列表态
- 补齐审阅弹窗遮罩模糊、scale 动画、重型遮罩风格

### 四、已完成 HTML 对照修正后的关键交互闭环

- 点击 `确定` 后配置锁定，开始按钮触发 3 次绿光闪烁
- 点击拖拽槽后载入模拟文件并更新文件数与状态提示
- 开始按钮支持空目标提示
- 左侧开始后进入运行态，完成后显示 `任务执行完毕。`
- 右侧开始后进入运行态，完成后切换为 `🔍 展开全屏审阅`
- 打开审阅弹窗后可查看重复分组
- `自动保留` 项不可勾选删除
- 点击 `确认并删除已选` 后进入 `处理中...`，完成后关闭弹窗并清空右侧面板

### 五、已完成进度条按 HTML 结构重构

- 轨道、填充、流光、段纹分层已重新对齐 HTML 结构
- 修复了 100% 进度时填充不完整的问题
- 进度段纹节奏已改为接近 HTML 的全轨覆盖条纹层
- 右端流光头保留独立白色拖尾效果

### 六、已完成状态机冻结与 UI 映射

左侧状态机：

- `idle -> target_ready -> config_locked -> running -> success / cancelled / error`

右侧状态机：

- `idle -> target_ready -> config_locked -> running -> review_ready -> executing -> success / cancelled / error`

已映射到 UI 的内容包括：

- 状态灯颜色
- 状态文案
- 进度提示文案
- 按钮形态切换
- 审阅弹窗开关

### 七、已完成 Python 对接边界预留

已冻结接口：

- `loadTargets(...)`
- `lockConfig(...)`
- `startTitleCleanTask()`
- `startDuplicateCheckTask()`
- `stopTask(...)`
- `fetchReviewResult()`
- `executeDelete(...)`
- `bindTaskProgressStream(...)`

已冻结数据模型：

- `FileItem`
- `DuplicateEntry`
- `DuplicateGroup`
- `CleanupDupApiEnvelope<T>`
- `CleanupDupApiError`
- `CleanupDupErrorCode`

已冻结错误码：

- `INVALID_MODULE`
- `INVALID_CONFIG`
- `EMPTY_TARGETS`
- `TARGET_NOT_FOUND`
- `TASK_NOT_FOUND`
- `TASK_ALREADY_RUNNING`
- `TASK_NOT_REVIEW_READY`
- `DELETE_SELECTION_EMPTY`
- `FILE_DELETE_FAILED`
- `INTERNAL_ERROR`

### 八、已完成测试验证

已验证命令：

```bash
flutter analyze lib/features/cleanup_dup/presentation test/widget_test.dart
flutter test test/widget_test.dart
```

验证结论：

- 分析通过
- Widget 测试通过
- `cleanup_dup` 模块关键交互链路已具备回归保障

## 当前明确未完成项

以下事项仍未落地为真实运行链路：

1. 尚未接入真实 Python 通信层
2. 尚未实现 `cleanup_dup_service.dart` 或 `python_bridge.dart`
3. 当前任务流仍为 UI mock + 状态机驱动，不涉及真实文件扫描、重复计算与删除执行

## 本次归档结论

本次 `cleanup_dup` 模块已从占位页推进为真实接入模块页，并完成：

1. 基于 HTML 参考的双面板 UI 复刻
2. 关键交互和硬件质感补齐
3. 主壳接线切换
4. 对照式差异修正
5. Python 对接接口与契约冻结
6. 分析与测试验证通过

当前可作为后续接入 Python 业务层的稳定 UI 基线。