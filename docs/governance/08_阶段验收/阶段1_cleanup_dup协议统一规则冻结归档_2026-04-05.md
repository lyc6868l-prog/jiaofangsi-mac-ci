# 阶段1 cleanup_dup 协议统一规则冻结归档

## 归档信息

- 归档日期：2026-04-05
- 归档范围：`cleanup_dup` 模块 Flutter <-> Python 协议统一规则定稿
- 当前状态：已按最新决策统一总协议、模块协议、样例与 schema

## 本次统一冻结的 4 条决策

1. 以 `cleanup_dup` 当前模块冻结协议为准
2. 响应壳统一使用 `ok / data / error`
3. 传输层字段统一 `snake_case`，Flutter 内部模型保留 `camelCase`
4. `task_id` 在 `start_*` 时创建，之后所有任务型动作必须携带

## 本次实际更新位置

- `/Users/tattoo/Desktop/全新教坊司/docs/governance/03_协议与接口/03_协议与接口规范.md`
- `/Users/tattoo/Desktop/全新教坊司/protocol/examples/cleanup_dup_flutter_python_rpc_examples.json`
- `/Users/tattoo/Desktop/全新教坊司/protocol/schemas/cleanup_dup_flutter_python_rpc.schema.json`

## 统一后的关键结果

### 一、总协议已与模块协议对齐

已消除以下旧冲突：

- 旧的 `success / code / message` 响应壳要求
- 旧的“所有任务接口必须携带 `task_id`”要求
- 旧协议未区分 Flutter 内部字段风格与传输层字段风格的问题

### 二、cleanup_dup 进入 Python 实现阶段的协议基础已具备

Python 后续可直接按以下约束实现：

- 请求 / 响应采用 JSON
- 传输字段统一使用 `snake_case`
- 响应壳统一使用 `ok / data / error`
- 任务型动作在 `start_*` 之后一律依赖 `task_id`
- 当前事件流名称与动作名称已冻结

### 三、Python <-> Rust 协议仍暂不冻结

当前确认：

- 先完成 Python 本地服务入口、任务调度器、状态机、桥接层
- Python 层稳定后再冻结 `Python <-> Rust` 协议

## 当前阶段结论

本次冻结后，`cleanup_dup` 当前阶段的协议边界已经统一，后续 Python 搭建可以直接以本次规则为基准推进。