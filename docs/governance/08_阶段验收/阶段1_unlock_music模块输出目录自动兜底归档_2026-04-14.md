# 阶段1 unlock_music 模块输出目录自动兜底归档

## 归档信息

- 归档时间：2026-04-14
- 归档范围：`apps/dj_flutter`、`runtime/dj_runtime_py`、`docs/governance` 中与 `unlock_music` 任务启动前输出目录自动兜底、完成弹窗打开实际输出目录、协议冻结补充、测试补充直接相关的实现与治理文件
- 当前状态：`unlock_music` 模块在既有冻结基线之上，已补齐“默认输出目录不存在时自动创建源目录下任务级时间戳子目录”的兜底逻辑，形成新的可恢复维护快照
- 对应阶段：阶段1 模块冻结后的维护修正归档

## 本阶段目标

- 修复解锁工具在默认输出目录不存在时直接报错的问题，避免首次使用或环境差异导致任务无法启动。
- 将输出目录策略收敛为“进入任务前检测，不存在则在源目录创建一次任务级时间戳子目录”，而不是把失败留给用户手动处理。
- 保证完成弹窗、历史记录与实际任务写入目录保持一致，实现“输出到哪里就打开哪里”。
- 将本次行为变化补入治理文档，避免后续实现回退到旧逻辑。

## 当前状态

当前 `unlock_music` 模块的输出目录行为已从“依赖预设目录存在”切换为“任务启动前自动兜底创建”。

当前规则如下：

- 若用户当前使用的是自动托管输出目录策略，则启动任务前会根据本次已载入文件的源目录公共父目录，创建一次任务级目录：`解锁输出-时间`。
- 同一批次任务仅创建一个输出子目录，所有本次解锁结果都写入该目录，不会按歌曲逐首创建子目录。
- 完成弹窗与历史记录打开的目录，均以本次任务实际输出目录为准，不再出现显示路径与真实落盘路径不一致的问题。
- Runtime 侧也已补齐兜底，因此即使绕过 Flutter 页面直接调用 `unlock_music_service`，仍会自动创建任务级输出目录。

## 已完成内容

### 一、Flutter 侧输出目录托管逻辑补齐

已完成：

- 在 `UnlockMusicEntryPage` 初始化时识别默认 `output` 目录是否存在。
- 当默认目录不存在时，改为进入自动托管模式，不再把一个无效目录直接传入任务配置。
- 在点击“开始批量解锁”前，统一调用输出目录准备逻辑。
- 自动托管模式下，将实际输出目录改为本次源目录公共父目录下的 `解锁输出-时间`。
- 完成弹窗继续打开任务实际输出目录，保持“输出到哪里就打开哪里”。

对应文件：

- `apps/dj_flutter/lib/features/unlock_music/presentation/unlock_music_entry_page.dart`

### 二、Python runtime 侧任务前兜底补齐

已完成：

- 在 `unlock_music_service.py` 的 `_start_task` 中加入输出目录预处理。
- 若传入的 `output_dir` 已存在，则继续按该目录执行。
- 若传入的 `output_dir` 不存在，则自动改为在源目录公共父目录下创建 `解锁输出-时间`。
- 启动任务前完成目录创建，并把实际输出目录写回任务配置。
- 新增针对该行为的 Python 测试，验证目录确实创建在源目录下且目录名符合约定。

对应文件：

- `runtime/dj_runtime_py/dj_runtime_py/unlock_music_service.py`
- `runtime/dj_runtime_py/test_unlock_music_service.py`

### 三、协议与冻结规则补充

已完成补充说明：

- `unlock_music` 的 `output_dir` 现允许作为用户意图输入，但实际执行目录以任务启动前归一化结果为准。
- 当默认目录不存在或处于自动托管模式时，系统会生成一次任务级的 `源目录/解锁输出-时间`。
- 完成弹窗、历史记录与打开目录动作必须指向本次任务实际输出目录。

## 修改 / 新增文件

### 本次涉及的关键实现文件

- `apps/dj_flutter/lib/features/unlock_music/presentation/unlock_music_entry_page.dart`
- `runtime/dj_runtime_py/dj_runtime_py/unlock_music_service.py`
- `runtime/dj_runtime_py/test_unlock_music_service.py`

### 本次新增 / 更新治理文件

- 新增 `docs/governance/08_阶段验收/阶段1_unlock_music模块输出目录自动兜底归档_2026-04-14.md`
- 更新 `docs/governance/09_更新记录/09_更新记录.md`
- 更新 `docs/governance/03_协议与接口/03_协议与接口规范.md`
- 更新 `文件对照表.md`

## 验证结果

- `python3 -m py_compile dj_runtime_py/unlock_music_service.py test_unlock_music_service.py`：已通过
- `flutter analyze lib/features/unlock_music/presentation/unlock_music_entry_page.dart`：已通过语法与静态分析，存在既有 info 级 lint 提示，无新增阻断错误
- `python3 -m unittest test_unlock_music_service.py`：当前环境缺少 `requests` 依赖，未能完整执行
- `apps/dj_flutter/test/widget_test.dart`：文件内存在本次任务无关的既有大范围测试桩缺失问题，不适合作为本次归档的有效全量回归结论

## 风险与遗留问题

- 当前 Python 测试环境缺少 `requests`，导致 `test_unlock_music_service.py` 不能在现环境中完整跑通，只能先以 `py_compile` 和新增测试代码审查作为阶段验证。
- Flutter 全量测试文件存在与本次任务无关的既有测试桩缺失问题，本次未顺带清理该历史债务。
- 当前策略遵循“源目录创建任务级子目录”的要求；若后续明确要求“用户手填不存在目录时也强制按该路径创建”，则需要再做一次规则调整并重新归档。

## 对后续模块 / 阶段的影响

- 后续所有 `unlock_music` 输出目录相关修正，都应以本次归档作为恢复现场入口，不再回退到“默认输出目录不存在即报错”的旧行为。
- 若 `search_download` 未来也需要统一到“任务级输出目录托管”策略，应沿用本次命名与归一化规则，保持模块间一致性。
- 若后续补齐 Flutter / Python 全量回归环境，应优先把本次新增的输出目录兜底场景纳入正式自动化回归用例。

## 下一步动作

- 在可用 Python 依赖环境中补跑 `test_unlock_music_service.py`，把本次新增场景纳入正式通过记录。
- 后续如推进 `search_download` 输出目录统一策略，可基于本次规则继续补齐并单独归档。
