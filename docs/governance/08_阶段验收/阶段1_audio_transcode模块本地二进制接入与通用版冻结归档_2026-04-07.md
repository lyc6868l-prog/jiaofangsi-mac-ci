# 阶段1 audio_transcode 模块本地二进制接入与通用版冻结归档

## 归档信息

- 归档日期：2026-04-07
- 归档范围：`apps/dj_flutter`、`runtime/dj_runtime_py`、`crates/dj_transcode_core`、`ff`、`tmp_ffmpeg_universal_builder`、`docs/governance` 中与 `audio_transcode` 本地转码链路、协议配置、二进制分发与治理归档直接相关的实现文件与治理文件
- 当前结论：`audio_transcode` 模块已完成本地 `ffmpeg` / `ffprobe` 通用版接入，当前进入"可交接继续验收 + 二进制随包分发冻结"状态
- 对应阶段：阶段1

## 本阶段目标

- 将主壳中的 `audio_transcode` 从"页面已接通但运行依赖外部系统 ffmpeg"推进到"优先使用项目内置 ffmpeg / ffprobe"状态
- 完成适用于 macOS 英特尔与 M 芯片的 `universal` 本地二进制产出与替换
- 保留音频转码、封面图读写与元数据链路所需的最小能力，去掉视频与字幕相关能力
- 将 Flutter -> Python -> Rust -> ffmpeg/ffprobe 的路径显式固定为项目内二进制优先
- 形成阶段快照，作为后续打包接入与端到端实音频验收的恢复入口

## 当前状态结论

截至本次归档，`audio_transcode` 已不再是单纯依赖系统环境中 `ffmpeg` / `ffprobe` 的模块，而是具备项目内本地二进制优先解析能力的真实转码链路。

当前已明确冻结的实现边界如下：

- Flutter 页面继续负责目标导入、输出格式、输出位置、任务启动、进度轮询与结果展示
- Flutter 启动默认 Python runtime 时会解析项目根目录下的 `ff/ffmpeg` 与 `ff/ffprobe`
- Flutter 锁定转码配置时会显式下发 `ffmpeg_path` 与 `ffprobe_path`
- Python runtime 继续作为调度层，接收配置并转交 Rust bridge
- Rust 转码核心继续负责 `ffprobe` 探测、命令构建、队列与执行
- 项目根目录 `ff/` 当前已替换为 `universal` 二进制，支持 `x86_64 + arm64`
- 当前编译配置保留"音频 + 封面图"能力，不保留视频与字幕能力
- 当前构建路径已确认关闭易出问题的汇编优化，以换取稳定可分发的通用版产物

当前模块已经具备本地二进制接入能力，但仍未完成一轮真实音频素材的端到端实转码验收，因此状态定义为"可交接继续验收 + 二进制分发冻结"，而不是"最终功能冻结"。

## 已完成内容

### 一、Flutter 页面与控制器已完成本地二进制接线

已完成：

- `audio_transcode` 页面初始化时自动解析项目根目录
- 启动默认 Python bridge 时继续复用项目内 `.venv` / `runtime/dj_runtime_py`
- 额外解析 `ff/ffmpeg` 与 `ff/ffprobe`
- 仅在对应文件存在时才下发显式路径，缺失时继续允许后端回退系统路径
- `AudioTranscodeController` 已新增 `ffmpeg_path` 与 `ffprobe_path` 配置字段
- `lock_config` 下发内容已补齐本地二进制路径

对应文件：

- `apps/dj_flutter/lib/features/audio_transcode/presentation/audio_transcode_entry_page.dart`
- `apps/dj_flutter/lib/features/audio_transcode/presentation/controllers/audio_transcode_controller.dart`

### 二、Python / Rust 链路确认可直接承接本地二进制路径

已确认：

- Python runtime 已接受 `ffmpeg_path` 与 `ffprobe_path`
- Python runtime 已在启动 Rust 转码任务时向下传递二进制路径
- Rust 层本来就支持外部传入二进制路径，缺失时才回退默认 `ffmpeg` / `ffprobe`
- 因此本轮接入无需再改 Python 或 Rust 主体实现

对应文件：

- `runtime/dj_runtime_py/dj_runtime_py/audio_transcode_service.py`
- `runtime/dj_runtime_py/dj_runtime_py/transcode_rust_bridge.py`
- `crates/dj_transcode_core/src/lib.rs`
- `crates/dj_transcode_core/src/audio_probe.rs`
- `crates/dj_transcode_core/src/transcode_runner.rs`

### 三、本地 ffmpeg / ffprobe 已替换为项目内通用版二进制

已完成：

- 审核旧版 `ff/ffmpeg`、`ff/ffprobe` 可执行性、架构与动态链接情况
- 确认旧版仅为 `x86_64`，不满足通用分发目标
- 通过本地 builder 产出新的 `universal` 版本
- 最终替换根目录 `ff/ffmpeg` 与 `ff/ffprobe`
- 已验证二进制均为 `Mach-O universal binary`，包含 `x86_64 + arm64`
- 已验证版本输出正常
- 已验证仅依赖系统库与系统 Framework

当前二进制体积：

- `ff/ffmpeg`：`12,879,736 bytes`
- `ff/ffprobe`：`12,473,400 bytes`
- 合计约 `24.2 MB`

对应目录：

- `ff/ffmpeg`
- `ff/ffprobe`

### 四、通用版构建策略已收敛为"音频 + 封面图"

本次构建明确保留：

- 音频输入：`aac`、`aiff`、`flac`、`m4a/mp4`、`mp3`、`ogg`、`wav`
- 音频输出：`adts`、`aiff`、`flac`、`m4a/mp4`、`mp3`、`ogg`、`opus`、`wav`
- 音频编码：`aac`、`libfdk_aac`、`alac`、`flac`、`libmp3lame`、`libopus`、`libspeex`、`libvorbis`、`pcm_*`
- 图片输入：`jpeg`、`png`、`webp`
- 图片输出：`mjpeg`、`png`、`webp`
- 基础音频处理：`aresample`、`atrim`、`channelmap`、`channelsplit`、`format`、`anull`
- 元数据与封面链路所需容器能力

本次构建明确去掉：

- 视频编码相关依赖
- 视频硬件加速链路
- 字幕与字体渲染链路
- 大部分视频图像扩展依赖
- 易导致通用版失败的汇编优化路径

对应目录与脚本：

- `tmp_ffmpeg_universal_builder/build-ffmpeg.sh`
- `tmp_ffmpeg_universal_builder/output/`

### 五、验证已完成到静态接通级别

已完成：

- `flutter analyze`
- `flutter test test/widget_test.dart`
- `file ff/ffmpeg ff/ffprobe`
- `ffmpeg -version`
- `ffprobe -version`
- `otool -L ff/ffmpeg ff/ffprobe`
- 启用能力核对：`-muxers`、`-demuxers`、`-encoders`

已确认：

- Flutter 侧接线无新增分析错误
- 现有聚焦 Widget 测试全部通过
- 本地二进制可正常执行并暴露预期能力

## 修改 / 新增文件

### 本次功能落地涉及的关键实现文件

- `apps/dj_flutter/lib/features/audio_transcode/presentation/audio_transcode_entry_page.dart`
- `apps/dj_flutter/lib/features/audio_transcode/presentation/controllers/audio_transcode_controller.dart`
- `runtime/dj_runtime_py/dj_runtime_py/audio_transcode_service.py`
- `runtime/dj_runtime_py/dj_runtime_py/transcode_rust_bridge.py`
- `crates/dj_transcode_core/src/lib.rs`
- `crates/dj_transcode_core/src/audio_probe.rs`
- `crates/dj_transcode_core/src/transcode_runner.rs`
- `ff/ffmpeg`
- `ff/ffprobe`
- `tmp_ffmpeg_universal_builder/build-ffmpeg.sh`

### 本次新增 / 更新治理文件

- `docs/governance/08_阶段验收/阶段1_audio_transcode模块本地二进制接入与通用版冻结归档_2026-04-07.md`
- `docs/governance/09_更新记录/09_更新记录.md`
- `docs/governance/03_协议与接口/03_协议与接口规范.md`
- `文件对照表.md`

## 验证结果

| 验证项 | 结果 | 说明 |
|---|---|---|
| Flutter 静态分析 | 已通过 | `flutter analyze` 通过，本次改动未引入新错误，现存 warning/info 来自其他模块 |
| Flutter 聚焦测试 | 已通过 | `flutter test test/widget_test.dart` 20/20 通过 |
| 本地 ffmpeg 架构 | 已通过 | `ff/ffmpeg` 为 `x86_64 + arm64` |
| 本地 ffprobe 架构 | 已通过 | `ff/ffprobe` 为 `x86_64 + arm64` |
| 二进制版本输出 | 已通过 | `ffmpeg -version`、`ffprobe -version` 正常 |
| 动态链接检查 | 已通过 | 仅依赖系统库与系统 Framework |
| Flutter -> Python 接线 | 已完成 | `ffmpeg_path`、`ffprobe_path` 已纳入 `lock_config` |
| Python -> Rust 接线 | 已完成 | Python runtime 已继续向 Rust 透传本地路径 |
| 实机真实音频转码验收 | 未完成 | 本次仅完成静态接线与二进制替换，未跑真实素材端到端验收 |

## 风险与遗留问题

- 当前尚未执行真实音频文件的端到端转码、输出文件校验与回放验证
- 当前打包链路尚未明确把 `ff/ffmpeg` 与 `ff/ffprobe` 一并打入最终应用包
- 若打包后这两个文件未被随包带上，当前代码会回退到系统 PATH 中的 `ffmpeg` / `ffprobe`
- 当前 builder 目录为本地阶段性产物，后续若继续维护通用版构建链路，需要决定是否长期保留
- 现有 Python runtime 自动化测试仍未覆盖真实 `ffmpeg` 二进制路径回传与成功转码样例

## 对后续阶段的影响

- 后续 `audio_transcode` 模块联调应以项目内 `ff/` 二进制为默认基线，不应再默认依赖系统环境
- 后续如果调整 `lock_config` 字段、错误码、动作名或事件名，必须同步更新协议文档与归档
- 后续打包链路必须显式处理 `ff/ffmpeg` 与 `ff/ffprobe` 的随包分发，否则本次本地二进制接入无法在发布态稳定生效
- 后续若继续压缩体积，应基于当前"音频 + 封面图"边界微调，不应重新引入视频与字幕依赖

## 下一步动作

- 在真实音频样本上执行一轮端到端转码验收，至少覆盖 `mp3`、`wav`、`flac` 与封面图场景
- 为 `audio_transcode` 增加一条真实 Python roundtrip 测试，验证显式 `ffmpeg_path` / `ffprobe_path` 生效
- 明确 macOS 打包流程中 `ff/ffmpeg`、`ff/ffprobe` 的随包位置与运行时解析策略
- 视发布体积目标，决定是否进一步裁剪图片编码或冗余格式支持
