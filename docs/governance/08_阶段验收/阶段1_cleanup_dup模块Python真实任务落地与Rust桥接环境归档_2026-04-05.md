# 阶段1 cleanup_dup 模块 Python 真实任务落地与 Rust 桥接环境归档

## 归档信息

- 归档日期：2026-04-05
- 归档范围：`cleanup_dup` 模块 Python 真实文件处理落地、Python <-> Rust 首轮桥接骨架、Rust/PyO3/maturin 正式环境修复
- 当前状态：Flutter <-> Python 真链路已可运行，Python 真实任务已落地，Rust 扩展环境已打通，下一步进入 `czkawka_core` 真能力接入阶段

## 本次归档结论

### 一、Python 真实任务已落地

当前 `runtime/dj_runtime_py` 已不再只是 mock 结构，已经具备真实文件处理能力：

- `load_targets` 支持文件与目录输入
- 目录输入支持递归收集音频文件
- `title_clean` 已可按 `delete_text` 真实重命名文件
- `duplicate_check` 已可按文件名归一化规则生成重复组
- `fetch_review_result` 已返回真实重复组数据
- `execute_delete` 已支持直接删除与移动到 `~/.Trash`
- 删除执行前会校验只允许删除审阅结果中的可删项

### 二、Flutter <-> Python 真链路已完成

当前 Flutter 已通过 stdin/stdout RPC 与 Python Runtime 真正联通，已形成可运行闭环：

1. Flutter 发起 `load_targets`
2. Python 返回统一 `ok/data/error`
3. Flutter 发起 `start_*`
4. Python 创建 `task_id`
5. Flutter 轮询 `subscribe_task_events`
6. Python 返回任务状态与进度事件
7. 右侧查重任务进入 `review_ready`
8. Flutter 再调用 `fetch_review_result`
9. 删除确认后调用 `execute_delete`

### 三、Python <-> Rust 首轮桥接骨架已建立

已新增 Rust 工作区与 `dj_scan_core` crate，并完成首轮 Python 绑定骨架：

- 根工作区 `Cargo.toml` 已建立
- `crates/dj_scan_core` 已可被 `cargo` 正常检查与测试
- 已建立 PyO3 模块入口 `dj_scan_core`
- 已暴露首批 Rust 对外接口：
  - `health_check`
  - `scan_music_by_tags`
- Python 侧已建立 `rust_bridge.py` 适配层
- Python 运行时测试已可识别并调用 Rust 扩展模块

说明：当前 `scan_music_by_tags` 仍是占位实现，下一阶段将替换为 `czkawka_core::same_music` 的真实调用。

## 本次修复的环境根因问题

### 一、Rust 工具链路径问题已正式修复

已完成：

- 在 `~/.zshrc` 写入 `~/.cargo/bin`
- 在 `~/.zprofile` 写入 `~/.cargo/bin`
- 通过 `launchctl setenv PATH ...` 同步 GUI 环境变量

结果：

- 新终端可直接使用 `cargo`
- Rust 工具链不再依赖手工写绝对路径执行

### 二、PyO3 Python 版本问题已正式修复

已完成：

- 安装 Homebrew `python@3.11`
- 创建项目级虚拟环境 `/.venv`
- 在 shell 配置中固定：

```bash
export PYO3_PYTHON="/Users/tattoo/Desktop/全新教坊司/.venv/bin/python"
```

- `runtime/dj_runtime_py/pyproject.toml` 已恢复为：

```toml
requires-python = ">=3.11"
```

- `crates/dj_scan_core/Cargo.toml` 已恢复为：

```toml
abi3-py311
```

结果：

- PyO3 不再错误绑定系统 Python 3.9
- Rust 扩展编译与 Python Runtime 要求重新统一到 Python 3.11

### 三、PyO3 测试与扩展构建链路已分离

已完成：

- 在 `dj_scan_core` 中新增 feature：

```toml
python-extension = ["pyo3/extension-module"]
```

- 普通 Rust 测试链路不依赖扩展模块 feature
- Python 扩展构建改走 `maturin develop`

结果：

- `cargo test -p dj_scan_core` 可正常执行
- `maturin develop -m crates/dj_scan_core/Cargo.toml --features python-extension` 可正常安装模块
- Python 可在项目 venv 中直接 `import dj_scan_core`

## 本次验证结果

### Rust 侧

已通过：

- `cargo check -p dj_scan_core`
- `cargo test -p dj_scan_core`

### Python 侧

已通过：

- `python -m unittest test_service.py`
- `python -m unittest test_service.py test_rust_bridge.py`

### Rust 扩展安装链路

已通过：

- `maturin develop -m crates/dj_scan_core/Cargo.toml --features python-extension`
- `python -c "import dj_scan_core; print(dj_scan_core.health_check())"`

输出结果已成功返回：

```json
{"ok":true,"core_version":"0.1.0","capabilities":["health_check","scan_music_by_tags"]}
```

## 当前阶段边界

### 已完成

- Flutter <-> Python 真链路
- Python 真实 title clean
- Python 真实 duplicate check
- Python 真实 delete 执行
- Rust 工作区建立
- Rust `dj_scan_core` crate 建立
- PyO3 绑定骨架建立
- Python `rust_bridge.py` 适配层建立
- Rust/Python/maturin 正式环境修复完成

### 未完成

- `czkawka_core` 接入 `dj_scan_core`
- `scan_music_by_tags` 从占位实现切换为真实 `SameMusic`
- `scan_music_by_content` 实现
- Rust 侧删除执行替换 Python 当前删除逻辑
- Python Runtime 真实改走 Rust 核心

## 下一阶段建议顺序

1. 将 `czkawka_core` 接入 `dj_scan_core`
2. 用 `SameMusic` 真正实现 `scan_music_by_tags`
3. 将 Rust 返回结果映射成当前 Flutter 审阅结构
4. 再接 `delete_entries`
5. 最后升级到内容级查重

## 本次归档结论

截至本次归档：

1. `cleanup_dup` 模块已完成 Flutter <-> Python 真联调
2. Python Runtime 已具备真实文件处理能力
3. Python <-> Rust 正式构建与安装环境已打通
4. Rust 桥接骨架已就绪，已具备接入 `czkawka_core` 的工程基础
5. 下一步应正式进入 Rust 核心能力替换阶段
