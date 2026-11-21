# macOS v2.0.0 双架构构建

本目录是从 Windows v2.0.0 主线同步出的 macOS 源码副本。

## 版本

```text
pubspec.yaml: 2.0.0
```

包含最新：

- 登录 / SSO
- 用户中心新版 UI
- 打赏作者
- 安全存储
- 忘记密码
- 最新 Python Runtime

保留 macOS：

- `apps/dj_flutter/macos/`
- `ff/ffmpeg`、`ff/ffprobe`（Universal Mach-O）
- macOS 打包脚本
- `一键修复并打开.command`

## 构建两个版本

在 macOS 上：

```bash
chmod +x scripts/*.sh
chmod +x apps/dj_flutter/macos/Runner/bundle_runtime_assets.sh

# Intel
./scripts/build_macos_dual_release.sh x86_64

# Apple Silicon
./scripts/build_macos_dual_release.sh arm64
```

输出：

```text
dist/教坊司DJ便捷工具_v2.0.0_Intel.dmg
dist/教坊司DJ便捷工具_v2.0.0_AppleSilicon.dmg
```

## GitHub Actions

工作流：

```text
.github/workflows/release-macos.yml
```

矩阵：

```text
macos-15-intel  → x86_64 → Intel
macos-15        → arm64  → AppleSilicon
```

触发方式：

```text
Actions → Build macOS Release DMGs → Run workflow
```

两个 runner 会分别构建原生运行时和 DMG，并在 Actions 运行结果页提供 artifact 下载。

## 重要说明

- CI 构建的是 ad-hoc 签名包，适合测试和内部交付
- 对外分发需要 Apple Developer ID 证书、codesign 和 notarization
- 运行时需要分别构建，Intel 和 Apple Silicon 不能混用
- 构建时间较长，主要耗在 Python/Node/FFmpeg/Rust 运行时编译
