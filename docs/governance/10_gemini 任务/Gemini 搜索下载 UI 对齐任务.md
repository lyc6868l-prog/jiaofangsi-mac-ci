# Gemini 任务：全网搜索下载 UI/UX 对齐参考 HTML

## 任务目标

把 Flutter 页面中的"全网搜索下载"视图的 UI/UX 对齐到参考 HTML 文件，保持现有所有状态接口、事件入口和 bridge 协议不变。

## 参考文件

| 类型 | 路径 |
|---|---|
| 参考 HTML | `/Users/tattoo/Desktop/全新教坊司/6模块ui参考/解锁ui.html` |
| 目标 Flutter | `apps/dj_flutter/lib/features/unlock_music/presentation/unlock_music_entry_page.dart` |
| 模型文件 | `apps/dj_flutter/lib/features/unlock_music/presentation/models/search_download_models.dart` |
| Bridge 文件 | `apps/dj_flutter/lib/features/unlock_music/presentation/controllers/python_search_download_task_bridge.dart` |

## 不可修改的内容

### 1. Bridge 接口（禁止修改）

```dart
abstract class SearchDownloadTaskBridge {
  Future<void> ensureStarted();
  Future<List<SearchDownloadSourceOption>> lockConfig(Map<String, Object?> config);
  Future<SearchDownloadTaskSnapshot> startSearchTask();
  Future<SearchDownloadTaskSnapshot> startPlaylistParseTask();
  Future<SearchDownloadTaskSnapshot> startDownloadTask(List<Map<String, Object?>> songInfos);
  Future<SearchDownloadTaskSnapshot> stopTask(String taskId);
  Future<List<SearchDownloadTaskEvent>> subscribeTaskEvents({String? taskId});
  Future<SearchDownloadResult> fetchSearchResult(String taskId);
  Future<SearchDownloadResult> fetchDownloadResult(String taskId);
  Future<void> close();
}
```

### 2. 状态接口（禁止修改）

必须继续复用这些状态和事件：

```dart
// 状态
_searchQueryController
_searchSources
_searchSongs
_searchSnapshot
_searchResult
_isSearchRunning
_searchProgressHintText
_searchLogLines
_searchTotalProgress
_searchCurrentProgress
_selectedSearchSongKeys

// 事件
_submitSearchOrPlaylist()
_startSearchDownloadTask()
_stopSearchTask()
_toggleSearchSource(String label)
_toggleSearchSongSelection(SearchDownloadSongItem item, bool value)
_pickOutputDirectory()
```

### 3. 数据模型（禁止修改）

- `SearchDownloadSourceOption`
- `SearchDownloadTaskSnapshot`
- `SearchDownloadSongItem`
- `SearchDownloadResult`

---

## UI 对齐清单

### 区块 1：顶部 LCD 状态条

**参考 HTML：** `.lcd-status-strip` (第 66-76 行)

**当前 Flutter：** `_StatusStrip` (约第 1001 行)

**对齐要求：**

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 背景 | `#020202` | 需确认 | 对齐 |
| 高度 | `36px` | 需确认 | 对齐 |
| 圆角 | `6px` | 需确认 | 对齐 |
| 内阴影 | `inset 0 2px 10px rgba(0, 0, 0, 1)` | 需确认 | 对齐 |
| 外光边 | `0 1px 0 rgba(255, 255, 255, 0.03)` | 需确认 | 对齐 |
| 字体 | `monospace 13px` | 需确认 | 对齐 |
| 颜色 | `#6b7280` | 需确认 | 对齐 |
| 状态值颜色 | `#d1d5db` | 需确认 | 对齐 |
| 成功色 | `#10b981` | 需确认 | 对齐 |
| 失败色 | `#e11d48` | 需确认 | 对齐 |
| 状态点 | `6px` 圆点，运行态 `#e11d48` 发光 | 需确认 | 对齐 |
| 分隔线 | `1px` 宽，`rgba(255, 255, 255, 0.05)` | 需确认 | 对齐 |

**必须保留的接口：**

```dart
_StatusStrip(
  statusText: _statusText,
  targetCount: _targetCount,
  successCount: _successCount,
  failedCount: _failedCount,
  active: _isSearchRunning,
  statusColor: _statusColor,
)
```

---

### 区块 2：引擎 Tabs

**参考 HTML：** `.engine-tabs` (第 78-83 行)

**当前 Flutter：** `_buildTabs()` (约第 1017 行)

**对齐要求：**

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 背景 | `#020202` | 需确认 | 对齐 |
| 内边距 | `6px` | 需确认 | 对齐 |
| 圆角 | `8px` | 需确认 | 对齐 |
| 内阴影 | `inset 0 2px 10px rgba(0,0,0,0.9)` | 需确认 | 对齐 |
| 按钮间距 | `8px` | 需确认 | 对齐 |
| 按钮内边距 | `8px 24px` | 需确认 | 对齐 |
| 按钮字体 | `13px` 粗体，字距 `1px` | 需确认 | 对齐 |
| 按钮颜色 | 未激活 `#6b7280`，激活 `#e11d48` | 需确认 | 对齐 |
| 激活背景 | `rgba(225,29,72,0.1)` + 边框 | 需确认 | 对齐 |
| 激活光晕 | `inset 0 0 10px rgba(225,29,72,0.1)` | 需确认 | 对齐 |

**必须保留的接口：**

```dart
_EngineTabButton(
  label: '🔓 音乐解锁引擎',
  active: _activeView == _UnlockMusicPanelView.unlock,
  onTap: () { ... },
)
_EngineTabButton(
  label: '🌐 全网搜索下载',
  active: _activeView == _UnlockMusicPanelView.search,
  onTap: () { ... },
)
```

---

### 区块 3：搜索控制区

**参考 HTML：** `.search-console-block` (第 198-200 行 + 第 317-344 行)

**当前 Flutter：** `_buildSearchConsole()` (约第 1448 行)

**对齐要求：**

#### 3.1 搜索输入框

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 高度 | `44px` (giant) | 需确认 | 对齐 |
| 背景 | `#020202` | 需确认 | 对齐 |
| 边框 | `1px solid rgba(255,255,255,0.03)` | 需确认 | 对齐 |
| 圆角 | `8px` | 需确认 | 对齐 |
| 内阴影 | `inset 0 2px 10px rgba(0,0,0,0.9)` | 需确认 | 对齐 |
| 聚焦边框 | `rgba(225, 29, 72, 0.5)` | 需确认 | 对齐 |
| 聚焦光晕 | `0 0 15px rgba(225, 29, 72, 0.15)` | 需确认 | 对齐 |
| 占位文字 | `#4b5563` | 需确认 | 对齐 |
| 文字颜色 | `#e5e7eb` | 需确认 | 对齐 |

#### 3.2 搜索按钮

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 高度 | `44px` | 需确认 | 对齐 |
| 内边距 | `0 24px` | 需确认 | 对齐 |
| 字体 | `14px` 粗体，字距 `2px` | 需确认 | 对齐 |
| 颜色 | `#e11d48` | 需确认 | 对齐 |
| 边框 | `1px solid rgba(225, 29, 72, 0.3)` | 需确认 | 对齐 |
| 悬停颜色 | `#f43f5e` | 需确认 | 对齐 |
| 悬停光晕 | `0 0 15px rgba(225, 29, 72, 0.2)` | 需确认 | 对齐 |

#### 3.3 平台筛选区

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 标签颜色 | `#8b8f98` | 需确认 | 对齐 |
| 复选框间距 | `16px` | 需确认 | 对齐 |
| 分隔线 | `1px` 宽，`12px` 高，`rgba(255,255,255,0.1)` | 需确认 | 对齐 |
| 更多平台按钮 | 与 HTML 一致 | 需确认 | 对齐 |

#### 3.4 更多平台下拉面板

**参考 HTML：** `.dropdown-panel` (第 122-130 行)

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 背景 | `#08080a` | 需确认 | 对齐 |
| 边框 | `1px solid rgba(255,255,255,0.1)` | 需确认 | 对齐 |
| 圆角 | `6px` | 需确认 | 对齐 |
| 外阴影 | `0 10px 30px rgba(0,0,0,0.95)` | 需确认 | 对齐 |
| 内阴影 | `inset 0 2px 5px rgba(255,255,255,0.05)` | 需确认 | 对齐 |
| 内边距 | `16px` | 需确认 | 对齐 |
| 间距 | `12px` | 需确认 | 对齐 |
| 淡入动画 | `0.2s` | 需确认 | 对齐 |

**必须保留的接口：**

```dart
_searchQueryController
_searchSources.map((option) => _SearchToggle(label: option.label, value: option.selected, onTap: () => _toggleSearchSource(option.label)))
_ShowMorePlatforms
```

---

### 区块 4：搜索结果表格

**参考 HTML：** `.hardware-table-container` (第 203-209 行 + 第 346-360 行)

**当前 Flutter：** `_buildSearchTable()` (约第 1535 行)

**对齐要求：**

#### 4.1 表格容器

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 背景 | `#020202` | 需确认 | 对齐 |
| 边框 | `1px solid rgba(255,255,255,0.05)` | 需确认 | 对齐 |
| 圆角 | `6px` | 需确认 | 对齐 |
| 内阴影 | `inset 0 4px 15px rgba(0,0,0,0.9)` | 需确认 | 对齐 |
| 布局 | `flex: 1; min-height: 0` (防重叠) | 需确认 | 对齐 |

#### 4.2 表头

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 背景 | `#0a0a0c` | 需确认 | 对齐 |
| 底边框 | `1px solid rgba(255,255,255,0.05)` | 需确认 | 对齐 |
| 内边距 | `8px 16px` | 需确认 | 对齐 |
| 字体 | `13px` 粗体 | 需确认 | 对齐 |
| 颜色 | `#9ca3af` | 需确认 | 对齐 |
| 列布局 | `30px 3fr 1.5fr 1fr 1fr 1fr` | 需确认 | 对齐 |

#### 4.3 表格行

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 内边距 | `8px 16px` | 需确认 | 对齐 |
| 底边框 | `1px solid rgba(255,255,255,0.02)` | 需确认 | 对齐 |
| 字体 | `13px` | 需确认 | 对齐 |
| 颜色 | `#d1d5db` | 需确认 | 对齐 |
| 悬停背景 | `rgba(255,255,255,0.03)` | 需确认 | 对齐 |
| 列布局 | 同表头 | 需确认 | 对齐 |

#### 4.4 列样式

| 列 | HTML 参考 | 动作 |
|---|---|---|
| 歌曲名称 | `color:#fff; font-weight:bold` | 对齐 |
| 歌手 | `#d1d5db` | 对齐 |
| 来源 | 多彩：QQ`#10b981` / 网易`#e11d48` / 酷狗`#3b82f6` | 对齐 |
| 大小 | `#9ca3af` + `monospace` | 对齐 |
| 音质 | 边框 + 圆角 + 居中 + `10px` | 对齐 |

#### 4.5 空态提示

**参考 HTML：** 第 356-360 行

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 颜色 | `#4b5563` | 需确认 | 对齐 |
| 字体 | `13px` | 需确认 | 对齐 |
| 文字 | `📡 等待检索信号输入...` | 需确认 | 对齐 |

**必须保留的接口：**

```dart
_searchSongs
_selectedSearchSongKeys
_isSearchSongSelected(item)
_toggleSearchSongSelection(item, value)
```

---

### 区块 5：进度与日志区

**参考 HTML：** `.progress-log-zone` (第 211-215 行 + 第 362-385 行)

**当前 Flutter：** `_buildSearchProgressLog()` (约第 1713 行)

**对齐要求：**

#### 5.1 进度条容器

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 高度 | `64px` | 需确认 | 对齐 |
| 间距 | `16px` | 需确认 | 对齐 |

#### 5.2 进度行

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 字体 | `11px monospace` | 需确认 | 对齐 |
| 标签颜色 | `#8b8f98` | 需确认 | 对齐 |
| 标签宽度 | `35px` 右对齐 | 需确认 | 对齐 |
| 百分比宽度 | `35px` 右对齐，`#e11d48` 粗体 | 需确认 | 对齐 |

#### 5.3 进度轨道

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 高度 | `10px` | 需确认 | 对齐 |
| 背景 | `#020202` | 需确认 | 对齐 |
| 圆角 | `5px` | 需确认 | 对齐 |
| 内阴影 | `inset 0 2px 6px rgba(0,0,0,0.9)` | 需确认 | 对齐 |
| 外光边 | `0 1px 0 rgba(255,255,255,0.05)` | 需确认 | 对齐 |
| 边框 | `1px solid rgba(0,0,0,0.8)` | 需确认 | 对齐 |

#### 5.4 进度填充

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 渐变 | `linear-gradient(90deg, #4c0519 0%, #be123c 80%, #fb7185 100%)` | 需确认 | 对齐 |
| 光晕 | `0 0 15px rgba(225,29,72,0.6)` | 需确认 | 对齐 |
| 过渡 | `0.1s linear` | 需确认 | 对齐 |

#### 5.5 进度发光头

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 宽度 | `15px` | 需确认 | 对齐 |
| 渐变 | `linear-gradient(90deg, transparent, #ffffff)` | 需确认 | 对齐 |
| 光晕 | `0 0 15px 3px rgba(255,255,255,0.8), 0 0 25px 8px rgba(225,29,72,0.8)` | 需确认 | 对齐 |

#### 5.6 分段遮罩

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 图案 | `repeating-linear-gradient(90deg, transparent, transparent 4px, rgba(0,0,0,0.7) 4px, rgba(0,0,0,0.7) 6px)` | 需确认 | 对齐 |

#### 5.7 日志终端

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 宽度 | `320px` (紧凑时 `100%`) | 需确认 | 对齐 |
| 背景 | `#020202` | 需确认 | 对齐 |
| 边框 | `1px solid rgba(255,255,255,0.05)` | 需确认 | 对齐 |
| 圆角 | `6px` | 需确认 | 对齐 |
| 内阴影 | `inset 0 2px 8px rgba(0,0,0,0.9)` | 需确认 | 对齐 |
| 内边距 | `8px 12px` | 需确认 | 对齐 |
| 字体 | `monospace 11px` | 需确认 | 对齐 |
| 颜色 | `#10b981` | 需确认 | 对齐 |
| 行高 | `1.4` | 需确认 | 对齐 |

**必须保留的接口：**

```dart
_searchProgressHintText
_searchTotalProgress
_searchCurrentProgress
_searchLogLines
```

---

### 区块 6：底部运输控制区

**参考 HTML：** `.transport-controls` (第 217-219 行 + 第 387-400 行)

**当前 Flutter：** `_buildSearchTransportControls()` (约第 1780 行)

**对齐要求：**

#### 6.1 控制区容器

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 高度 | `42px` | 需确认 | 对齐 |
| 背景 | `rgba(0,0,0,0.3)` | 需确认 | 对齐 |
| 内边距 | `4px 12px` | 需确认 | 对齐 |
| 圆角 | `6px` | 需确认 | 对齐 |
| 边框 | `1px solid rgba(255,255,255,0.02)` | 需确认 | 对齐 |

#### 6.2 控制组

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 间距 | `10px` | 需确认 | 对齐 |
| 对齐 | `center` | 需确认 | 对齐 |

#### 6.3 输出路径按钮

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 背景 | `rgba(255,255,255,0.05)` | 需确认 | 对齐 |
| 边框 | `transparent` | 需确认 | 对齐 |

#### 6.4 组内分隔线

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 宽度 | `1px` | 需确认 | 对齐 |
| 高度 | `16px` | 需确认 | 对齐 |
| 背景 | `rgba(255,255,255,0.1)` | 需确认 | 对齐 |
| 边距 | `0 4px` | 需确认 | 对齐 |

#### 6.5 音质优先下拉

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 宽度 | `100px` | 需确认 | 对齐 |
| 高度 | `26px` | 需确认 | 对齐 |
| 内边距 | `0 6px` | 需确认 | 对齐 |
| 背景 | `#020202` | 需确认 | 对齐 |
| 圆角 | `6px` | 需确认 | 对齐 |
| 字体 | `12px` | 需确认 | 对齐 |
| 颜色 | `#e5e7eb` | 需确认 | 对齐 |

#### 6.6 下载按钮

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 高度 | `44px` | 需确认 | 对齐 |
| 字体 | `14px` 粗体，字距 `2px` | 需确认 | 对齐 |
| 颜色 | `#e11d48` (激活时更亮) | 需确认 | 对齐 |
| 边框 | `1px solid rgba(225, 29, 72, 0.2)` | 需确认 | 对齐 |
| 激活态 | 下沉 `3px` + 强光晕 | 需确认 | 对齐 |

#### 6.7 终止按钮

| 属性 | HTML 参考 | Flutter 当前 | 动作 |
|---|---|---|---|
| 宽度 | `140px` | 需确认 | 对齐 |
| 颜色 | `#9ca3af` | 需确认 | 对齐 |
| 边框 | `1px solid rgba(255,255,255,0.1)` | 需确认 | 对齐 |
| 悬停 | `#d1d5db` | 需确认 | 对齐 |
| 激活态 | 下沉 `3px` | 需确认 | 对齐 |

**必须保留的接口：**

```dart
_pickOutputDirectory
_isSearchRunning
_startSearchDownloadTask
_stopSearchTask
```

---

## 视觉风格统一要求

### 颜色系统

| 用途 | 色值 |
|---|---|
| 主背景 | `#030303` |
| 面板背景 | `#08080a` |
| 输入背景 | `#020202` |
| 表头背景 | `#0a0a0c` |
| 主强调色 | `#e11d48` |
| 成功色 | `#10b981` |
| 失败色 | `#e11d48` |
| 警告色 | `#d97706` |
| 文字主色 | `#e5e7eb` |
| 文字次色 | `#d1d5db` |
| 文字再次 | `#9ca3af` |
| 文字禁用 | `#6b7280` |
| 占位文字 | `#4b5563` |
| 日志文字 | `#10b981` |

### 圆角系统

| 组件 | 圆角 |
|---|---|
| 主面板 | `12px` |
| 大按钮 | `8px` |
| 小按钮 | `6px` |
| 输入框 | `6px` / `8px`(giant) |
| 表格容器 | `6px` |
| 进度轨道 | `5px` |
| 状态条 | `6px` |
| Tabs 容器 | `8px` |
| 下拉面板 | `6px` |

### 阴影系统

| 类型 | 阴影 |
|---|---|
| 面板外阴影 | `0 0 50px rgba(0,0,0,0.8)` |
| 输入框内阴影 | `inset 0 2px 10px rgba(0,0,0,0.9)` |
| 表格内阴影 | `inset 0 4px 15px rgba(0,0,0,0.9)` |
| 进度条内阴影 | `inset 0 2px 6px rgba(0,0,0,0.9)` |
| 按钮外阴影 | `0 4px 6px rgba(0,0,0,0.5)` |
| 激活光晕 | `0 0 15px rgba(225,29,72,0.2)` |

### 字体系统

| 用途 | 字体 | 大小 | 字重 | 字距 |
|---|---|---|---|---|
| 面板标题 | -apple-system | `18px` | 500 | `1px` |
| Tab 按钮 | -apple-system | `13px` | 700 | `1px` |
| 输入文字 | -apple-system | `13-14px` | 400 | - |
| 表格文字 | -apple-system | `13px` | 400 | - |
| 表头 | -apple-system | `13px` | 700 | - |
| 状态条 | monospace | `13px` | 700 | - |
| 日志 | monospace | `11px` | 400 | - |
| 进度标签 | monospace | `11px` | 400 | `1px` |
| 按钮 | -apple-system | `13-14px` | 700 | `2px` |

---

## 交互行为要求

### 1. Tab 切换

- 运行中禁止切换
- 切换时更新水印文字（解/搜）
- 切换时更新面板标题
- 切换时重置状态条

### 2. 搜索按钮

- 运行中显示 `⏳ 检索中...`
- 空闲显示 `🔍 搜索 / 解析`
- 点击后禁用输入框
- 完成后恢复

### 3. 平台勾选

- 运行中禁止修改
- 点击立即生效
- 更多平台下拉有淡入动画

### 4. 表格勾选

- 运行中禁止修改
- 表头全选控制所有行
- 单击行内复选框切换

### 5. 下载按钮

- 运行中显示 `⏳ 下载中...`
- 空闲显示 `▶ 开始下载选中项`
- 激活态下沉 `3px` + 强光晕

### 6. 终止按钮

- 无任务时禁用
- 运行中可点击
- 点击后显示停止状态

### 7. 日志区

- 自动滚动到底部
- 支持多行
- 紧凑时占满宽度

---

## 验收标准

### 必须通过

- [ ] `flutter analyze` 无错误
- [ ] `flutter test test/widget_test.dart` 通过
- [ ] 所有状态接口保持不变
- [ ] 所有事件入口保持不变
- [ ] 所有 bridge 调用保持不变

### 视觉对齐

- [ ] 顶部 LCD 状态条与 HTML 一致
- [ ] Tabs 与 HTML 一致
- [ ] 搜索输入框与 HTML 一致
- [ ] 搜索按钮与 HTML 一致
- [ ] 平台筛选区与 HTML 一致
- [ ] 更多平台下拉与 HTML 一致
- [ ] 表格容器与 HTML 一致
- [ ] 表头与 HTML 一致
- [ ] 表格行与 HTML 一致
- [ ] 空态提示与 HTML 一致
- [ ] 进度条与 HTML 一致
- [ ] 日志终端与 HTML 一致
- [ ] 底部控制区与 HTML 一致

### 交互对齐

- [ ] Tab 切换行为与 HTML 一致
- [ ] 搜索按钮行为与 HTML 一致
- [ ] 平台勾选行为与 HTML 一致
- [ ] 表格勾选行为与 HTML 一致
- [ ] 下载按钮行为与 HTML 一致
- [ ] 终止按钮行为与 HTML 一致
- [ ] 日志滚动行为与 HTML 一致

---

## 工作顺序建议

1. **先读状态**：理解 `_searchSnapshot`、`_searchResult`、`_searchSongs` 等状态来源
2. **再改视觉**：从顶部状态条开始，逐区块对齐
3. **最后验证**：运行 `flutter analyze` 和 `flutter test`

---

## 禁止事项

- ❌ 不要修改 `SearchDownloadTaskBridge` 接口
- ❌ 不要修改 `SearchDownloadSongItem` 字段
- ❌ 不要修改 `_submitSearchOrPlaylist()` 调用逻辑
- ❌ 不要修改 `_startSearchDownloadTask()` 调用逻辑
- ❌ 不要修改 `_stopSearchTask()` 调用逻辑
- ❌ 不要修改 `_toggleSearchSource()` 调用逻辑
- ❌ 不要修改 `_toggleSearchSongSelection()` 调用逻辑
- ❌ 不要修改 Python runtime 协议
- ❌ 不要修改模型文件
- ❌ 不要修改 bridge 文件

---

## 可修改事项

- ✅ 可以修改 `_buildSearchConsole()` 的视觉
- ✅ 可以修改 `_buildSearchTable()` 的视觉
- ✅ 可以修改 `_buildSearchProgressLog()` 的视觉
- ✅ 可以修改 `_buildSearchTransportControls()` 的视觉
- ✅ 可以修改 `_StatusStrip` 的视觉
- ✅ 可以修改 `_buildTabs()` 的视觉
- ✅ 可以修改 `_SearchToggle` 的视觉
- ✅ 可以修改 `_SearchDropdown` 的视觉
- ✅ 可以修改进度条样式
- ✅ 可以修改日志终端样式
- ✅ 可以修改按钮样式
- ✅ 可以修改输入框样式
- ✅ 可以修改布局间距
- ✅ 可以修改颜色、圆角、阴影

---

## 开始工作前请确认

1. 已阅读参考 HTML 全文（650 行）
2. 已理解 Flutter 现有状态接口
3. 已理解哪些可以改、哪些不能改
4. 已准备好从顶部状态条开始逐区块对齐

如有疑问，请先确认再继续。
