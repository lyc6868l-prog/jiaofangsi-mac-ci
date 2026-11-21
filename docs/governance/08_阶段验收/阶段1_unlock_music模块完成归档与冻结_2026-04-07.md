# 阶段1 unlock_music 模块完成归档与冻结

## 归档信息

- 归档日期：2026-04-07
- 归档范围：`apps/dj_flutter`、`runtime/dj_runtime_py`、`runtime/unlock_music_node`、`protocol` 中与 `unlock_music`、`search_download` 直接相关的 Flutter 页面、bridge、模型、Python runtime、Node worker、协议样例与 schema、测试与治理文档
- 当前结论：`unlock_music` 模块主功能已完成，当前正式进入"完成归档 + 冻结维护"状态
- 对应阶段：阶段1

## 本阶段目标

- 将 `unlock_music` 从"架构已接通、能力补完中"推进到"主流程完成且可回归验证"
- 确认音乐解锁、全网搜索、更多平台、歌单 URL 解析、搜索下载、Python runtime 回归、Flutter 全工程验证均已闭环
- 形成模块冻结快照，作为后续恢复现场与修正型工作的基线

## 当前状态结论

截至本次归档，`unlock_music` 已不再属于继续扩写主流程的模块，而属于已完成并冻结的模块。

当前冻结的是：

- Flutter 页面结构与交互闭环
- Flutter <-> Python 的 `unlock_music` / `search_download` 双模块通信方式
- Python runtime 中解锁、搜索、歌单解析、下载三类后台任务链路
- Python <-> Node 的解锁执行方式
- 搜索平台选择、歌单 URL 解析、结果选择、下载启动与结果回写流程
- 模块级回归测试与当前验证命令

当前不再将 `unlock_music` 视为"需要继续补主能力才能可用"的模块，而视为"主功能已完成，后续按真实使用反馈修正边界"的模块。

## 已完成内容

### 一、Flutter 侧主功能完成

#### 1. 解锁页已形成真实工作页

已完成：

- 文件 / 目录导入
- 输出目录配置
- overwrite / keep_source 配置
- 开始 / 停止
- 任务进度展示
- 结果列表展示
- 错误项筛选

对应文件：

- `apps/dj_flutter/lib/features/unlock_music/presentation/unlock_music_entry_page.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/controllers/python_unlock_music_task_bridge.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/models/unlock_music_models.dart`

#### 2. 搜索下载页已形成真实工作页

已完成：

- 关键词搜索
- 歌单 URL 解析
- 搜索结果展示
- 曲目勾选
- 下载任务启动
- 下载进度与日志展示
- 更多平台面板与真实配置写入

对应文件：

- `apps/dj_flutter/lib/features/unlock_music/presentation/unlock_music_entry_page.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/controllers/python_search_download_task_bridge.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/models/search_download_models.dart`

#### 3. 搜索页交互与布局问题已收口

本次完成归档前，已修复以下直接影响实际使用的问题：

- 搜索中不再错误驱动下载按钮状态
- 搜索结果不再默认全选
- 更多平台从假 UI 改为真实配置入口
- 紧凑尺寸下搜索页溢出与无界高度问题已修复
- 更多平台面板在测试环境中可稳定交互并真实回写搜索源

### 二、Python runtime 主链路完成

#### 1. `unlock_music` runtime 已完成

当前已稳定支持：

- `load_targets`
- `lock_config`
- `start_unlock_task`
- `stop_task`
- `subscribe_task_events`
- `fetch_unlock_result`

对应文件：

- `runtime/dj_runtime_py/dj_runtime_py/unlock_music_service.py`
- `runtime/dj_runtime_py/dj_runtime_py/unlock_node_bridge.py`

#### 2. `search_download` runtime 已完成

当前已稳定支持：

- `lock_config`
- `start_search_task`
- `start_playlist_parse_task`
- `fetch_search_result`
- `start_download_task`
- `fetch_download_result`
- `stop_task`
- `subscribe_task_events`

对应文件：

- `runtime/dj_runtime_py/dj_runtime_py/search_download_service.py`

#### 3. 歌单 URL 解析链路已真实补齐

本次归档前已确认并修复：

- `start_playlist_parse_task`
- `_run_playlist_task`
- `MusicClient.parseplaylist(...)`
- 解析结果回写 `task.search_results`
- `fetch_search_result` 可获取歌单解析结果

这意味着歌单 URL -> Python runtime -> 结果展示链路已不再存在结构性缺口。

### 三、Node 解锁执行层完成

当前 Node worker 已作为解锁执行层稳定接入，继续保留以下已完成能力：

- `health_check`
- `unlock_file`
- `unlock_batch`
- raw 直出
- `uc/cache`
- `tm0/tm2/tm3/tm6`
- `kwm`
- `xm`
- `mg3d`
- `ncm`
- `qmc` 最小可跑分支

对应文件：

- `runtime/unlock_music_node/package.json`
- `runtime/unlock_music_node/src/main.js`

### 四、回归验证已恢复并通过

#### 1. Python runtime 回归

当前环境已改用 `python3.11` 建立：

- `runtime/dj_runtime_py/.venv`

已通过：

- `runtime/dj_runtime_py/test_service.py`
- `runtime/dj_runtime_py/test_unlock_node_bridge.py`

本次归档时复验命令：

- `"runtime/dj_runtime_py/.venv/bin/python" -m pytest runtime/dj_runtime_py/test_service.py runtime/dj_runtime_py/test_unlock_node_bridge.py`

结果：

- `23 passed`

#### 2. Flutter 验证

本次归档时复验命令：

- `flutter analyze`
- `flutter test`
- `flutter build macos --debug`

结果：

- `flutter analyze` 无问题
- `flutter test` 全量通过
- `flutter build macos --debug` 已成功输出 `dj_flutter.app`

## 修改 / 新增文件

### 本次完成归档前已完成的关键实现文件

- `apps/dj_flutter/lib/features/unlock_music/presentation/unlock_music_entry_page.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/controllers/python_unlock_music_task_bridge.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/controllers/python_search_download_task_bridge.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/models/unlock_music_models.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/models/search_download_models.dart`
- `runtime/dj_runtime_py/dj_runtime_py/unlock_music_service.py`
- `runtime/dj_runtime_py/dj_runtime_py/search_download_service.py`
- `runtime/dj_runtime_py/dj_runtime_py/unlock_node_bridge.py`
- `runtime/dj_runtime_py/test_service.py`
- `runtime/dj_runtime_py/test_unlock_node_bridge.py`
- `runtime/unlock_music_node/src/main.js`

### 本次归档新增 / 更新治理文件

- `docs/governance/08_阶段验收/阶段1_unlock_music模块完成归档与冻结_2026-04-07.md`
- `docs/governance/09_更新记录/09_更新记录.md`
- `文件对照表.md`
- `docs/governance/03_协议与接口/03_协议与接口规范.md`
- `protocol/examples/unlock_music_flutter_python_rpc_examples.json`
- `protocol/schemas/unlock_music_flutter_python_rpc.schema.json`

## 验证结果

| 验证项 | 结果 | 说明 |
|---|---|---|
| Flutter 静态分析 | 已通过 | `flutter analyze` 无 issue |
| Flutter 全量测试 | 已通过 | `flutter test` 全量通过 |
| Flutter macOS 调试构建 | 已通过 | `flutter build macos --debug` 成功 |
| Python runtime 回归 | 已通过 | `23 passed` |
| 歌单 URL 解析链路 | 已完成 | `start_playlist_parse_task` -> `_run_playlist_task` -> `fetch_search_result` 已闭环 |
| 更多平台真实配置 | 已完成 | 测试已验证平台选择真实进入 `sources` |
| 搜索下载闭环 | 已完成 | 搜索、勾选、下载、结果回写已闭环 |
| 解锁任务闭环 | 已完成 | 目标加载、配置锁定、启动、轮询、结果获取已闭环 |

## 协议冻结说明

本次归档同步正式补齐 `unlock_music` 模块协议冻结。

冻结后的模块边界如下：

### 一、模块名冻结

- `unlock_music`
- `search_download`

### 二、解锁动作冻结

- `load_targets`
- `lock_config`
- `start_unlock_task`
- `fetch_unlock_result`
- `stop_task`
- `subscribe_task_events`

### 三、搜索下载动作冻结

- `lock_config`
- `start_search_task`
- `start_playlist_parse_task`
- `fetch_search_result`
- `start_download_task`
- `fetch_download_result`
- `stop_task`
- `subscribe_task_events`

### 四、冻结状态值

#### `unlock_music`

- `idle`
- `target_ready`
- `config_locked`
- `running`
- `success`
- `cancelled`
- `error`

#### `search_download`

- `idle`
- `config_locked`
- `running`
- `success`
- `cancelled`
- `error`

### 五、冻结事件值

- `task_created`
- `task_progress`
- `task_status_changed`
- `task_finished`

`search_download` 额外保留但当前未作为主流程事件使用的历史兼容值：

- `review_ready`

## 风险与遗留问题

当前剩余事项已不再属于主功能未完成，而属于加固项或扩展项：

- `qmc` 完整纯 JS 分支仍未补齐
- `qmc v2 + wasm` 仍未补齐
- `kgm / vpr` 仍未补齐
- 更完整的元数据写回仍未补齐
- 真实音乐平台与外部网络环境下仍可继续补充实机验证样本

这些项不影响当前将模块判断为"主功能已完成并冻结"。

## 对后续阶段的影响

- 后续其他模块推进不再以 `unlock_music` 为阻塞项
- `unlock_music` 后续新增工作默认归类为修正型或增强型工作
- 若后续继续补 `qmc v2 / kgm / vpr / wasm`，应作为冻结后增强，而不是重新定义本轮主流程完成状态
- 后续恢复现场时，应优先查看本归档、更新记录、文件对照表与补齐后的协议样例 / schema

## 下一步动作

- 默认冻结 `unlock_music` 当前主流程，不再继续扩大页面或协议边界
- 后续仅在以下情形下继续改动：
  - 实际使用中发现 Bug
  - 需要补强回归测试
  - 需要补齐剩余格式算法
  - 需要处理平台兼容性或外部环境边界问题
- 若进入下一轮能力扩展，应新建新的增强归档，而不是继续向本归档追加主状态变化
