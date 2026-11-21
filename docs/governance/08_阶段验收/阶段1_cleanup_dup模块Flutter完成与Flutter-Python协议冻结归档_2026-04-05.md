# 阶段1 cleanup_dup 模块 Flutter 完成与 Flutter-Python 协议冻结归档

## 归档信息

- 归档日期：2026-04-05
- 归档范围：`cleanup_dup` 模块 Flutter 展示层完成情况与 Flutter <-> Python 协议冻结结果
- 当前状态：Flutter 页面与交互基线已完成，Flutter <-> Python 协议已冻结，后续进入 Python 实现阶段

## 本次冻结结论

### 一、Flutter 侧已完成范围冻结

当前 `cleanup_dup` 模块在 Flutter 侧已完成以下内容：

- 模块页面
- 左右双面板工作区
- 控制器
- 状态展示
- 拖拽槽与文件列表 mock 交互
- 进度条与按钮交互
- 审阅弹窗
- 用户操作入口
- 主壳真实接线
- Widget 测试覆盖关键流程

对应结论：

- Flutter 展示层已完成
- Flutter 模块交互层已完成
- Flutter mock 状态机已完成
- Flutter 当前不再承担新增业务判断职责

### 二、Flutter 当前明确不承担的职责冻结

以下内容不在 Flutter 层承担：

- 文件扫描
- 重复判断
- 自动保留策略
- 删除 / 恢复执行核心
- 任务编排
- 跨任务状态权威维护

结论：Flutter 仅负责 UI、交互、展示与最终用户操作提交。

## Flutter <-> Python 协议冻结结果

### 一、通信模式冻结

冻结为两类：

1. RPC 请求 / 响应
2. 事件流推送

### 二、模块标识冻结

- `module = cleanup_dup`

### 三、面板标识冻结

- `titleClean`
- `duplicateSearch`

### 四、任务类型冻结

- `title_clean`
- `duplicate_check`

### 五、状态机冻结

左侧：

- `idle -> target_ready -> config_locked -> running -> success / cancelled / error`

右侧：

- `idle -> target_ready -> config_locked -> running -> review_ready -> executing -> success / cancelled / error`

### 六、错误码冻结

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

### 七、Flutter 已冻结方法名

- `loadTargets(...)`
- `lockConfig(...)`
- `startTitleCleanTask()`
- `startDuplicateCheckTask()`
- `stopTask(...)`
- `fetchReviewResult()`
- `executeDelete(...)`
- `bindTaskProgressStream(...)`

### 八、协议动作名冻结

- `load_targets`
- `lock_config`
- `start_title_clean_task`
- `start_duplicate_check_task`
- `stop_task`
- `fetch_review_result`
- `execute_delete`
- `subscribe_task_events`

### 九、事件名冻结

- `task_created`
- `task_progress`
- `task_status_changed`
- `review_ready`
- `task_finished`
- `task_error`

### 十、统一响应壳冻结

成功：

```json
{
  "ok": true,
  "data": {},
  "error": null
}
```

失败：

```json
{
  "ok": false,
  "data": null,
  "error": {
    "code": "ERROR_CODE",
    "message": "错误说明"
  }
}
```

## 当前已冻结的数据结构

- `FileItem`
- `DuplicateEntry`
- `DuplicateGroup`
- `CleanupDupApiEnvelope<T>`
- `CleanupDupApiError`
- `CleanupDupErrorCode`

## 三层职责冻结结果

### Flutter

负责：

- 模块页面
- 控制器
- 状态展示
- 审阅弹窗
- 用户操作入口

### Python

负责：

- 本地服务入口
- 任务调度器
- 状态机
- API / WebSocket
- Rust 调用桥

### Rust

负责：

- `title_clean` 功能模块
- `duplicate_check` 功能模块
- `delete/restore strategy` 相关执行核心
- 后续其他音频处理能力模块

## 当前推进顺序冻结

当前阶段确认以下推进顺序：

1. Flutter 保持当前冻结状态，不继续塞业务逻辑
2. 进入 Python 实现阶段
3. `Python <-> Rust` 调用协议表待 Python 层搭建完成后再冻结
4. Python 层稳定后，再将 Flutter mock 接到真实通信层

## 当前未完成项

以下事项仍未落地：

1. Python 本地服务实现
2. Python 任务调度器实现
3. Python 状态机实现
4. Python 与 Rust 桥接实现
5. `Python <-> Rust` 协议冻结
6. Flutter 真实联调接线

## 本次归档的使用方式

本文件用于明确当前阶段的“已冻结更新”，后续开发应遵循：

- Flutter 不再扩张业务职责
- Python 开始按已冻结协议实现
- Rust 协议在 Python 调度层稳定后再冻结

## 本次归档结论

当前 `cleanup_dup` 模块已形成可继续推进的稳定阶段边界：

1. Flutter 已完成展示层与交互层工作
2. Flutter <-> Python 协议已冻结
3. Python 进入实现阶段
4. `Python <-> Rust` 协议暂缓到 Python 结构完成后再冻结

该状态可作为下一阶段开发接力基线。