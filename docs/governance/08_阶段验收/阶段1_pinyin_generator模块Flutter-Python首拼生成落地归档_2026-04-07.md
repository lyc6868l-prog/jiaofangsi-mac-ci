# 阶段1 pinyin_generator 模块 Flutter-Python 首拼生成落地归档

## 归档信息

- 归档日期：2026-04-07
- 归档范围：`apps/dj_flutter`、`runtime/dj_runtime_py`、`protocol` 中与 `pinyin_generator` 直接相关的 Flutter 页面、控制器、bridge、模型、Python runtime、协议样例与 schema、测试与治理文档
- 当前结论：`pinyin_generator` 模块已完成首版 Flutter -> Python 落地，当前进入"可交接继续联调 + 冻结前补验证"状态
- 对应阶段：阶段1

## 本阶段目标

- 将主壳中的"首拼生成"从占位入口推进到真实工作页
- 按已冻结架构完成 `Flutter -> Python` 首版链路，不在本阶段引入 Rust
- 完成中文标题首拼生成、停用词过滤、Album 写入、结果回读校验与统计回写
- 同步补齐 `pinyin_generator` 模块协议样例、schema 与阶段归档入口，形成可恢复现场

## 当前状态结论

截至本次归档，`pinyin_generator` 已完成首版功能闭环，主壳入口、Flutter 页面、Flutter <-> Python bridge、Python runtime、协议样例与 schema 均已落地。

当前已明确冻结的实现边界如下：

- 架构固定为 `Flutter -> Python`
- 跨层传输继续使用 JSON，字段继续使用 `snake_case`
- 输入支持音频文件与文件夹
- 标题读取优先 metadata `Title`，缺失时回退文件名
- 使用 `pypinyin` 生成中文首拼
- 默认停用词包含 `mp3 remix vip dj`
- 最大首拼长度默认 12
- 写入目标字段为 `Album`
- 支持 `overwrite` 与 `append`
- 写入后会重新读取元数据校验写入结果
- WAV 在当前版本中仅统计并跳过，不执行 Album 写入

当前模块已经不再是"只有路由和卡片的壳层预留"，而是具备实际导入、配置、启动、轮询、结果展示与错误回传能力的可运行模块。

## 已完成内容

### 一、Flutter 页面与主壳接线完成

已完成：

- 将主壳中的 `AppShellSection.pinyinGenerator` 从占位内容切换为真实页面
- 新建 `pinyin_generator` 模块展示层目录与入口页
- 完成目标导入区、配置区、进度区、结果区与状态统计展示
- 完成拖拽导入、文件选择、文件夹选择、开始写入、停止任务与清空列表交互
- 修复空列表拖拽区在测试窗口高度下的布局溢出问题

对应文件：

- `apps/dj_flutter/lib/app/shell/app_shell_page.dart`
- `apps/dj_flutter/lib/features/pinyin_generator/presentation/pinyin_generator_entry_page.dart`

### 二、Flutter 控制器与 bridge 完成

已完成：

- 新建 `PinyinGeneratorController`
- 完成目标加载、配置重置、任务启动、任务轮询、终态结果拉取与 toast 警告回写
- 新建 `PythonPinyinGeneratorTaskBridge`
- 完成 `load_targets`、`lock_config`、`start_pinyin_generator_task`、`fetch_pinyin_generator_result`、`stop_task`、`subscribe_task_events` 六个动作的 JSON RPC 封装
- 新建 `pinyin_generator` 模块模型文件，固定任务快照、事件、结果项、写入模式与状态枚举

对应文件：

- `apps/dj_flutter/lib/features/pinyin_generator/presentation/controllers/pinyin_generator_controller.dart`
- `apps/dj_flutter/lib/features/pinyin_generator/presentation/controllers/python_pinyin_generator_task_bridge.dart`
- `apps/dj_flutter/lib/features/pinyin_generator/presentation/models/pinyin_generator_models.dart`

### 三、Python runtime 主链路完成

已完成：

- 在 runtime 主入口注册 `pinyin_generator`
- 新建 `pinyin_generator_service.py`
- 完成递归收集目标文件、WAV 跳过统计、配置锁定、异步任务创建、事件轮询与终态结果返回
- 完成中文检测、停用词过滤、首拼生成、Album 写入、回读校验、成功/跳过/失败统计
- 复用 `mutagen` 完成音频元数据读写，并引入 `pypinyin`

对应文件：

- `runtime/dj_runtime_py/dj_runtime_py/__main__.py`
- `runtime/dj_runtime_py/dj_runtime_py/pinyin_generator_service.py`
- `runtime/dj_runtime_py/pyproject.toml`

### 四、协议样例与 schema 完成

已完成：

- 新建 `pinyin_generator` Flutter -> Python 协议样例
- 新建 `pinyin_generator` schema
- 保持模块名、动作名、错误码与事件名与实现一致

对应文件：

- `protocol/examples/pinyin_generator_flutter_python_rpc_examples.json`
- `protocol/schemas/pinyin_generator_flutter_python_rpc.schema.json`

### 五、测试与静态验证完成

已完成：

- 在 `widget_test.dart` 中新增 `pinyin_generator` 模块测试夹具与假 bridge
- 覆盖主壳入口跳转与结果态展示验证
- 修复首拼页面测试中的布局溢出后重新通过全量测试

对应文件：

- `apps/dj_flutter/test/widget_test.dart`

## 修改 / 新增文件

### 本次功能落地涉及的关键实现文件

- `apps/dj_flutter/lib/app/shell/app_shell_page.dart`
- `apps/dj_flutter/lib/features/pinyin_generator/presentation/pinyin_generator_entry_page.dart`
- `apps/dj_flutter/lib/features/pinyin_generator/presentation/controllers/pinyin_generator_controller.dart`
- `apps/dj_flutter/lib/features/pinyin_generator/presentation/controllers/python_pinyin_generator_task_bridge.dart`
- `apps/dj_flutter/lib/features/pinyin_generator/presentation/models/pinyin_generator_models.dart`
- `apps/dj_flutter/test/widget_test.dart`
- `runtime/dj_runtime_py/dj_runtime_py/__main__.py`
- `runtime/dj_runtime_py/dj_runtime_py/pinyin_generator_service.py`
- `runtime/dj_runtime_py/pyproject.toml`
- `protocol/examples/pinyin_generator_flutter_python_rpc_examples.json`
- `protocol/schemas/pinyin_generator_flutter_python_rpc.schema.json`

### 本次新增 / 更新治理文件

- `docs/governance/08_阶段验收/阶段1_pinyin_generator模块Flutter-Python首拼生成落地归档_2026-04-07.md`
- `docs/governance/09_更新记录/09_更新记录.md`
- `docs/governance/03_协议与接口/03_协议与接口规范.md`
- `文件对照表.md`

## 验证结果

| 验证项 | 结果 | 说明 |
|---|---|---|
| Python 依赖安装 | 已通过 | 根目录 `.venv` 已安装 `pypinyin` |
| Python runtime 编译检查 | 已通过 | `"/Users/tattoo/Desktop/全新教坊司/.venv/bin/python" -m compileall dj_runtime_py` 已成功 |
| Flutter 静态分析 | 已通过 | `flutter analyze` 无 issue |
| Flutter 全量测试 | 已通过 | `flutter test` 15 个测试全量通过 |
| 首拼页面入口跳转测试 | 已通过 | `pinyin generator card opens entry page` 已通过 |
| 首拼结果态测试 | 已通过 | `pinyin generator page processes result states` 已通过 |
| 协议样例与 schema | 已完成 | `protocol/examples` 与 `protocol/schemas` 已补齐 |

## 风险与遗留问题

- 尚未补一条真实 Python roundtrip 自动化测试，当前 Python 侧仍主要依赖编译检查与 Flutter 假 bridge 测试
- 尚未补充 WAV 跳过 warning 的界面断言
- 尚未执行 `flutter build macos --debug` 作为桌面端最终验收
- Flutter 内部存在 `plan_ready` 作为页面状态，但该值不属于 Flutter -> Python 线上的冻结协议状态，后续维护时不能误写入跨层协议

## 对后续阶段的影响

- 后续若继续补充首拼生成模块，应在当前 `Flutter -> Python` 基线之上推进，不应回退到占位页状态
- 若后续决定引入 Rust，只能作为 Python 下层能力接入，不能改写本阶段已确认的跨层主链
- 后续新增协议动作或错误码时，必须同步更新 `03_协议与接口规范.md`、schema、样例与阶段归档

## 下一步动作

- 补充 `pinyin_generator` Python roundtrip 测试
- 补充 WAV 跳过 warning 的 Flutter 断言
- 运行 `flutter build macos --debug` 做桌面端最终验收
- 在实机样本上复验不同音频容器的 Album 写入结果与回读一致性
