# 阶段1 cleanup_dup 模块冻结归档

## 归档信息

- 归档日期：2026-04-06
- 归档范围：`apps/dj_flutter`、`runtime/dj_runtime_py`、`crates/dj_scan_core` 中与 `cleanup_dup` 模块直接相关的 UI、协议、runtime、Rust 扫描与删除能力
- 当前结论：`cleanup_dup` 模块主功能冻结，进入"可交付试用 + 实际使用中发现边界问题"阶段

## 模块冻结结论

截至本次归档，`cleanup_dup` 已满足本地开发工具场景下的主流程需求，可以视为阶段性冻结。

当前冻结的是：

- 功能边界
- 交互闭环
- Flutter <-> Python 协议使用方式
- Python runtime 调度方式
- Rust 核心接入方向

当前不再将 `cleanup_dup` 视为"功能继续扩写中"模块，而视为"主流程完成，后续按真实使用反馈修边界"模块。

## 已冻结的能力范围

### 一、导入与启动链路

- 支持点击导入真实音频文件
- 支持点击导入真实文件夹
- 支持 Finder 拖入文件和文件夹
- 支持 Flutter 启动项目内 Python runtime
- 支持 Python runtime 调用 Rust `dj_scan_core`

### 二、标题清理能力

- 用户输入 `delete_text` 后可批量清理文件名中的对应文案
- 处理范围覆盖当前导入目标中的全部音频文件
- 后台任务运行期间可轮询进度
- 支持停止任务
- 改名冲突时自动生成唯一文件名
- 该流程只改名，不删除文件

### 三、查重能力

- 支持 `极速比对`
- 支持 `内容比对`
- `极速比对` 以文件名归一化规则分组
- `内容比对` 走 Rust + `czkawka_core` 内容扫描链路
- 查重任务支持后台运行、进度轮询、停止任务
- 结果支持进入 review modal 审阅

### 四、审阅与删除能力

- 支持自动保留 1 份文件
- 支持其余重复项默认勾选删除
- 支持用户在审阅结果中手动调整删除项
- 支持执行删除
- 支持直接删除与回收站策略
- 删除执行优先走 Rust，失败时由 Python 回退处理

## 本次冻结判断依据

### 已完成的主流程

| 项目 | 状态 | 说明 |
|---|---|---|
| 文件导入 | 已完成 | 点击选择与 Finder 拖拽均已接通真实链路 |
| Python runtime 启动 | 已完成 | 本地调试模式下可稳定拉起 |
| 标题清理 | 已完成 | 已后台化，支持进度与取消 |
| 极速比对 | 已完成 | 已可分组、审阅、删除 |
| 内容比对 | 已完成 | 已接 Rust 真扫描、进度与取消 |
| 审阅与删除 | 已完成 | 已形成完整闭环 |
| Flutter 验证 | 已完成 | `flutter analyze`、`flutter test`、`flutter build macos --debug` 已通过 |
| Python 验证 | 已完成 | `test_service.py`、`test_rust_bridge.py` 已通过 |
| Rust 验证 | 已完成 | `cargo test -p dj_scan_core` 已通过 |

### 已确认不再属于主功能缺失的问题

当前剩余事项不再是主流程缺失，而是以下类型：

- 真实音频样本下的更强断言测试
- Rust 自身测试覆盖增强
- `title_clean` 边界测试补齐
- Finder 权限与不同路径场景的额外实机验证

这些属于加固项，不影响当前将模块判定为"主功能已完成"。

## 当前运行逻辑冻结说明

### 标题清理

当前标题清理逻辑冻结为：

1. 导入文件或文件夹
2. `load_targets`
3. `lock_config` 写入 `delete_text`
4. `start_title_clean_task` 创建后台任务
5. `subscribe_task_events` 轮询进度与完成状态
6. 文件名按大小写不敏感方式删除输入文案，并做空格、分隔符清理
7. 若改名后目标文件已存在，则自动补 `(1)`、`(2)` 避免冲突

### 查重

当前查重逻辑冻结为：

1. 导入文件或文件夹
2. `load_targets`
3. `lock_config` 写入 `matching_mode`
4. `start_duplicate_check_task` 创建任务
5. 若为 `极速比对`，由 Python 按名称归一化规则分组
6. 若为 `内容比对`，由 Rust 发起内容扫描任务并轮询结果
7. 发现重复后进入 `review_ready`
8. `fetch_review_result` 获取分组结果
9. `execute_delete` 执行删除

### 极速比对与内容比对的冻结差异

| 模式 | 当前冻结定义 |
|---|---|
| 极速比对 | 按文件名归一化后的结果判断是否重复，速度优先 |
| 内容比对 | 按音频内容相似性判断是否重复，准确性优先 |

## 本次冻结时同步补齐的回归项

本次冻结前，已补充一项名称归一化回归测试，并修复对应实际缺口：

- 新增 `copy`、`copy 2`、`副本`、全角字符场景下的重复分组测试
- 修复 `copy 2` 变体未被完整归一化的问题

对应文件：

- `runtime/dj_runtime_py/test_service.py`
- `runtime/dj_runtime_py/dj_runtime_py/service.py`

## 冻结后的维护原则

### 一、后续不再随意扩大功能边界

`cleanup_dup` 后续默认不新增新的产品型能力，除非明确提出新的模块需求。

冻结后优先处理的是：

- 实际使用中暴露的误判、漏判
- 导入或拖拽在特殊路径下的不稳定问题
- 标题清理与删除中的边界错误
- 真实音频样本下的回归用例补齐

### 二、后续修改默认归类为修正型工作

后续对 `cleanup_dup` 的新增工作，默认按以下类型管理：

- Bug 修复
- 回归测试增强
- 稳定性加固
- macOS 实机兼容性修正

### 三、后续模块开发不再以 `cleanup_dup` 为阻塞项

本模块现已满足阶段性交付条件，后续可进入其他模块推进。

## 仍保留的未冻结加固项

以下项目未纳入"主功能未完成"范围，但仍建议后续补齐：

| 项目 | 当前状态 |
|---|---|
| 真实音频样本内容比对强断言测试 | 未补齐 |
| Rust `dj_scan_core` 自身强断言测试 | 未补齐 |
| `title_clean` 边界测试 | 未补齐 |
| Finder 更多权限场景实机验证 | 未补齐 |

## 冻结结论

本次正式冻结 `cleanup_dup` 模块内容，结论如下：

1. `cleanup_dup` 主功能已完成
2. 当前版本已满足本地开发工具场景下的实际使用要求
3. 后续工作以使用中发现问题后的修正和加固为主
4. 模块不再作为当前阶段的主开发阻塞项

## 关联文件

- `docs/governance/08_阶段验收/阶段1_cleanup_dup模块Python真实任务落地与Rust桥接环境归档_2026-04-05.md`
- `docs/governance/08_阶段验收/阶段1_cleanup_dup模块本地可用化与macOS导入链路修复归档_2026-04-06.md`
- `docs/governance/09_更新记录/09_更新记录.md`
- `文件对照表.md`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/cleanup_dup_entry_page.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/controllers/cleanup_dup_controller.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/controllers/python_cleanup_dup_task_bridge.dart`
- `apps/dj_flutter/lib/features/cleanup_dup/presentation/widgets/hardware_widgets.dart`
- `runtime/dj_runtime_py/dj_runtime_py/service.py`
- `runtime/dj_runtime_py/test_service.py`
- `runtime/dj_runtime_py/test_rust_bridge.py`
- `crates/dj_scan_core/src/lib.rs`
