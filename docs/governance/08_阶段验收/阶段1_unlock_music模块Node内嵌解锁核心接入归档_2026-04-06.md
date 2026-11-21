# 阶段1 unlock_music 模块 Node 内嵌解锁核心接入归档

## 归档信息

- 归档日期：2026-04-06
- 归档范围：`apps/dj_flutter`、`runtime/dj_runtime_py`、`runtime/unlock_music_node` 中与 `unlock_music` 模块直接相关的 Flutter 入口、Python runtime、Node worker 与测试文件
- 当前结论：`unlock_music` 已完成首轮内嵌架构接入与部分解锁格式落地，模块处于"骨架打通 + 核心格式分批补完"阶段

## 本次归档目标

本轮工作的目标不是一次性完成全部 Unlock Music 能力，而是先把以下链路打通：

- Flutter 有独立模块入口
- Python runtime 能识别 `unlock_music` 模块并调度任务
- Node.js 作为内嵌子进程运行 JS 解锁核心
- Python <-> Node 通过 stdin/stdout JSON RPC 通信
- 至少一批可纯 JS 落地的格式先真实跑通
- 为后续继续补 `qmc v2 + wasm`、`kgm/vpr` 与正式 UI 做稳定基线

## 当前架构结论

截至本次归档，`unlock_music` 模块已明确采用如下架构：

| 层 | 职责 |
|---|---|
| Flutter | 模块入口、后续文件导入、输出配置、进度与结果展示 |
| Python runtime | `task_id`、状态机、事件轮询、停止任务、模块分发 |
| Node worker | 承接 Unlock Music 风格的 JS 解锁逻辑与本地文件落盘 |
| JS core | 具体格式的纯 JS 解锁能力，后续继续补 wasm 相关格式 |

本次已经明确不采用 WebView 承载整个网页 UI 的方案，而是只吸收 JS 解锁核心，把它包装成本地 worker 挂进现有桌面软件架构。

## 已完成内容

### 一、Flutter 侧

#### 1. 新增 unlock_music 模块入口页

已新增：

- `apps/dj_flutter/lib/features/unlock_music/presentation/unlock_music_entry_page.dart`

当前作用：

- 提供 `unlock_music` 模块独立入口页
- 自动向上查找项目根目录
- 优先使用项目内 `.venv/bin/python`
- 预留后续真实 UI 接入位置

#### 2. 新增 Flutter bridge 与模型骨架

已新增：

- `apps/dj_flutter/lib/features/unlock_music/presentation/controllers/python_unlock_music_task_bridge.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/models/unlock_music_models.dart`

当前作用：

- 固定 Flutter <-> Python 的 `unlock_music` 请求方式
- 定义 `UnlockMusicTaskSnapshot`、`UnlockMusicTaskEvent`、`UnlockMusicResult` 等模型
- 为后续真实 UI 轮询与结果展示提供数据契约

#### 3. 主壳已接入 unlock 模块入口

已修改：

- `apps/dj_flutter/lib/app/shell/app_shell_page.dart`

当前效果：

- 点击主壳中的"解锁工具"卡片后，不再停留在通用占位文案
- 已进入 `UnlockMusicEntryPage`

### 二、Python runtime 侧

#### 1. Python runtime 已支持多模块分发

已修改：

- `runtime/dj_runtime_py/dj_runtime_py/__main__.py`
- `runtime/dj_runtime_py/dj_runtime_py/protocol.py`
- `runtime/dj_runtime_py/dj_runtime_py/__init__.py`

当前效果：

- Python runtime 不再只支持 `cleanup_dup`
- 已可根据 `module` 字段分发到：
  - `cleanup_dup`
  - `unlock_music`
- `EventEnvelope` 已支持显式模块名

#### 2. 新增 Node bridge

已新增：

- `runtime/dj_runtime_py/dj_runtime_py/unlock_node_bridge.py`

当前能力：

- Python 能拉起 Node 子进程
- 可发送 `health_check`
- 可发送 `unlock_file`
- 可发送任意 JSON RPC action
- 已补进程关闭与资源释放处理

#### 3. 新增 unlock runtime 服务层

已新增：

- `runtime/dj_runtime_py/dj_runtime_py/unlock_music_service.py`

当前能力：

- `load_targets`
- `lock_config`
- `start_unlock_task`
- `stop_task`
- `subscribe_task_events`
- `fetch_unlock_result`

当前任务模型：

- Python 后台线程逐文件调用 Node worker
- 每处理一项更新一次进度
- 结果按 success / failed 汇总
- 支持取消请求

### 三、Node worker 侧

#### 1. 新增本地 Node worker 工程

已新增：

- `runtime/unlock_music_node/package.json`
- `runtime/unlock_music_node/src/main.js`

当前作用：

- 作为本地内嵌 JS 解锁 worker
- 从 stdin 读 JSON
- 向 stdout 写 JSON
- 提供：
  - `health_check`
  - `unlock_file`
  - `unlock_batch`

#### 2. 已落地的格式能力

当前已完成一批不依赖 wasm 的格式：

| 格式/能力 | 状态 | 说明 |
|---|---|---|
| raw 直出 | 已完成 | 直接按嗅探后的扩展名落盘 |
| `uc` / `cache` | 已完成 | 已按异或规则解码并落盘 |
| `tm0` / `tm2` / `tm3` / `tm6` | 已完成 | 已改写头部后输出 `m4a` |
| `kwm` | 已完成 | 已按纯 JS 规则解码并落盘 |
| `xm` | 已完成 | 已按纯 JS 规则解码并落盘 |
| `mg3d` | 已完成 | 已按纯 JS 规则解码并落盘 |
| `ncm` | 已完成一版 | 已接 AES-ECB、key box、meta 与音频解密主链 |
| `qmc` v1 静态类 | 已完成最小版 | 当前仅保留最小可跑实现 |

#### 3. 仍未完成的格式能力

| 格式/能力 | 状态 |
|---|---|
| `qmc` 完整纯 JS 分支 | 未完成 |
| `qmc v2 + wasm` | 未完成 |
| `kgm` / `vpr` | 未完成 |
| 更完整的元数据写回 | 未完成 |

## 测试与验证

### 已新增测试

- `runtime/dj_runtime_py/test_unlock_node_bridge.py`

当前已覆盖：

| 测试项 | 状态 |
|---|---|
| `health_check` | 已通过 |
| raw mp3 直出 | 已通过 |
| `uc/cache` 解码 | 已通过 |
| `tm2` 输出 `m4a` | 已通过 |
| batch mixed result | 已通过 |
| `ncm` 解码 | 已通过 |

### 已通过命令

- `node "src/main.js"` 的 `health_check` 请求已通过
- `"/Users/tattoo/Desktop/全新教坊司/.venv/bin/python" -m unittest test_unlock_node_bridge.py` 已通过
- `flutter test test/widget_test.dart` 已通过，并包含 unlock 模块入口测试

## 当前模块状态判断

当前 `unlock_music` 还不能定义为"模块已完成"，但已经明显越过了最早的空壳阶段。

当前更准确的状态是：

- 模块架构已定型
- Flutter / Python / Node 三层链路已打通
- 一批纯 JS 格式已真实可用
- 后续重点转入继续补剩余解锁算法和正式 UI

## 后续最自然的推进顺序

### 第一优先级

- 补 `qmc` 完整纯 JS 分支
- 补 `kgm` / `vpr` 解锁

### 第二优先级

- 再决定是否接 `qmc_wasm` / `kgm_wasm`
- 评估是否继续复用参考项目中的 wasm 路径，而不是重写

### 第三优先级

- 把 Flutter 占位入口页替换为真实工作页：
  - 文件导入
  - 输出目录配置
  - overwrite / keep_source 控件
  - 开始 / 停止
  - 进度条
  - 结果列表

## 当前恢复工作时应优先查看的文件

### Flutter

- `apps/dj_flutter/lib/app/shell/app_shell_page.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/unlock_music_entry_page.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/controllers/python_unlock_music_task_bridge.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/models/unlock_music_models.dart`
- `apps/dj_flutter/test/widget_test.dart`

### Python runtime

- `runtime/dj_runtime_py/dj_runtime_py/__main__.py`
- `runtime/dj_runtime_py/dj_runtime_py/protocol.py`
- `runtime/dj_runtime_py/dj_runtime_py/unlock_node_bridge.py`
- `runtime/dj_runtime_py/dj_runtime_py/unlock_music_service.py`
- `runtime/dj_runtime_py/test_unlock_node_bridge.py`

### Node worker

- `runtime/unlock_music_node/package.json`
- `runtime/unlock_music_node/src/main.js`

### 参考实现

- `解锁功能参考/下载后解锁/unlock-music-web-master/src/decrypt/index.ts`
- `解锁功能参考/下载后解锁/unlock-music-web-master/src/decrypt/ncm.ts`
- `解锁功能参考/下载后解锁/unlock-music-web-master/src/decrypt/qmc.ts`
- `解锁功能参考/下载后解锁/unlock-music-web-master/src/decrypt/kgm.ts`
- `解锁功能参考/下载后解锁/unlock-music-web-master/src/decrypt/kwm.ts`
- `解锁功能参考/下载后解锁/unlock-music-web-master/src/decrypt/xm.ts`
- `解锁功能参考/下载后解锁/unlock-music-web-master/src/decrypt/tm.ts`
- `解锁功能参考/下载后解锁/unlock-music-web-master/src/decrypt/mg3d.ts`

## 补充更新：全网搜索下载接入进展

在本次归档形成后，又继续完成了 `unlock_music` 页面内 `search_download` 链路的首轮真实接入，范围仍落在既有归档范围内的 Flutter 与 Python runtime 文件，不新增独立 UI 参考工程承载。

### 已完成补充内容

#### 1. Flutter 搜索下载页已从静态壳切为真实 bridge 驱动

已补齐：

- 搜索输入
- 平台勾选
- 任务轮询
- 搜索结果展示
- 勾选待下载曲目
- 下载触发
- 日志区与进度区状态联动

涉及文件：

- `apps/dj_flutter/lib/features/unlock_music/presentation/unlock_music_entry_page.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/controllers/python_search_download_task_bridge.dart`
- `apps/dj_flutter/lib/features/unlock_music/presentation/models/search_download_models.dart`

#### 2. Python runtime 已新增 `search_download` 模块服务

已补齐：

- `lock_config`
- `start_search_task`
- `start_playlist_parse_task`
- `fetch_search_result`
- `start_download_task`
- `fetch_download_result`
- `stop_task`
- `subscribe_task_events`

涉及文件：

- `runtime/dj_runtime_py/dj_runtime_py/__main__.py`
- `runtime/dj_runtime_py/dj_runtime_py/search_download_service.py`

#### 3. 已将 `musicdl` 作为 vendor 功能库接入

已完成：

- 复制 `musicdl` 代码到 `runtime/dj_runtime_py/vendor/musicdl/`
- 补运行依赖声明与安装
- 验证真实 Python 环境可导入 `musicdl`

相关文件：

- `runtime/dj_runtime_py/vendor/musicdl/`
- `runtime/dj_runtime_py/vendor/musicdl_requirements.txt`
- `runtime/dj_runtime_py/pyproject.toml`

#### 4. 已修复 Python runtime 与 `musicdl` 集成时的协议污染问题

`musicdl` 真实运行时会向 stdout/stderr 输出内容，最初会污染 Python runtime 的 JSON RPC 输出。当前已在 `search_download_service.py` 中加入输出捕获，避免协议流被破坏。

#### 5. 搜索链路已完成一次关键提速改造

初版接入直接调用 `client.search()`，会在搜索阶段同步做完整补全，导致 UI 长时间停在"正在搜索"。

当前已改为：

- 搜索阶段优先执行"轻搜索"
- 先返回歌曲名称、歌手、来源、时长等基础信息
- 不在搜索阶段同步探测下载地址
- 仅在用户点击"开始下载选中项"后，再对选中曲目执行完整补全解析与真实下载

这使得真实搜索联调已从"长时间无返回"改善到"可快速返回候选结果"。

#### 6. 日志与结果文件回收已接入第一版

当前已在 runtime 中加入：

- `musicdl.log` 读取回传
- `search_results.pkl` 回收
- `download_results.pkl` 回收

但仍属于第一版，后续还需继续细化每首歌曲级别的失败明细。

#### 7. 测试与验证已补齐到当前阶段

已通过：

- `"/Users/tattoo/Desktop/全新教坊司/.venv/bin/python" -m unittest test_service.py`
- `flutter analyze`
- `flutter test test/widget_test.dart`

其中：

- `runtime/dj_runtime_py/test_service.py` 已补 `search_download` 基本流程单测
- `apps/dj_flutter/test/widget_test.dart` 已补搜索下载页面交互测试

### 当前补充状态判断

截至本次补充更新，`unlock_music` 入口页已不再只承载解锁子模块，也已经承接了"全网搜索下载"的首轮真实功能接入。

更准确的状态是：

- `unlock_music` 页面中的搜索下载分区已从静态展示升级为真实可交互功能页
- 搜索 -> 勾选 -> 下载前补全 -> 下载 的主链已基本可用
- 当前仍不能定义为"全部平台稳定完成"，但已经越过了只做 UI 壳和协议预留的阶段

### 当前仍未完成的部分

- 歌单解析仍偏重，尚未轻量化
- 下载前补全过程的逐首超时与失败明细仍需补齐
- 每首补全失败原因尚未完整透出到 Flutter
- 后处理状态尚未做细粒度可视化
- 停止任务的中断点仍可继续细化

## 归档结论

本次归档后，`unlock_music` 的当前结论是：

1. 方向已确认：Node.js 内嵌 worker 方案成立
2. 当前项目中已存在可继续迭代的正式 `unlock_music` 模块骨架
3. `unlock_music` 页面内的"全网搜索下载"已完成首轮真实接入，主链达到基本可用状态
4. 后续不需要再重复搭架构，直接继续补解锁算法、搜索下载稳定性与正式 UI 即可
5. 下一次恢复工作时，优先目标应是 `qmc` 与 `kgm/vpr` 的补完，以及搜索下载链路的逐首失败治理，而不是重新讨论整体方案
