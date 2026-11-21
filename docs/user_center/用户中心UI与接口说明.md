# 软件端用户中心 UI 与接口整理

> 对应版本：教坊司 DJ 便捷工具 v2.0.0  
> 整理时间：2026-11-21  
> 说明：本文按当前 Flutter 桌面端代码整理，不包含官网个人中心页面本身。

---

## 1. 涉及文件

| 作用 | 文件 |
|---|---|
| 用户中心悬浮面板 UI | `apps/dj_flutter/lib/app/shell/user_center_panel.dart` |
| 顶部头像入口 / 面板显示控制 | `apps/dj_flutter/lib/app/shell/app_shell_page.dart` |
| 登录态数据模型 | `apps/dj_flutter/lib/features/auth/presentation/models/auth_session_snapshot.dart` |
| 接口结果模型 | `apps/dj_flutter/lib/features/auth/presentation/models/auth_models.dart` |
| 用户中心业务控制器 | `apps/dj_flutter/lib/features/auth/presentation/controllers/auth_controller.dart` |
| Python RPC 桥接 | `apps/dj_flutter/lib/features/auth/presentation/controllers/python_auth_task_bridge.dart` |
| 统一账号接口 | `apps/dj_flutter/lib/features/auth/presentation/controllers/unified_account_service.dart` |
| 个人中心 SSO | `apps/dj_flutter/lib/features/auth/presentation/controllers/sso_service.dart` |
| Python 认证运行时 | `runtime/dj_runtime_py/dj_runtime_py/auth_runtime.py` |
| Python 认证 HTTP 服务 | `runtime/dj_runtime_py/dj_runtime_py/auth_service.py` |
| 面板颜色 token | `apps/dj_flutter/lib/app/shell/shell_tokens.dart` |

---

## 2. UI 整体结构

面板入口在 `AppShellPage`：

- `AppShellTopBar` 显示头像
- 鼠标进入头像 → 显示用户中心
- 点击头像 → 固定用户中心
- 点击面板外遮罩 → 关闭
- 游客不显示用户中心入口

面板代码：

```text
UserCenterPanel
└── Container 320px 宽
    ├── _UserHeader              艺名 / 账号
    ├── _BindWechatButton        仅非 unified 账号显示
    ├── _UserMenuList            个人中心
    ├── _UserActionGroup         当前为空
    ├── 会员权益标题
    ├── _PrivilegeSection        VIP 会员
    └── _LogoutButton            退出登录
```

### 2.1 面板容器

对应代码：`user_center_panel.dart:77-161`

关键参数：

```dart
width: 320
padding: EdgeInsets.all(20)
borderRadius: BorderRadius.circular(12)
gradient: shellPanelTop -> shellPanelBottom
```

面板为深色悬浮层，顶部有一根 `shellAccentBlue` 状态线。

### 2.2 用户信息区 `_UserHeader`

对应代码：`user_center_panel.dart:408-479`

显示：

```text
艺名：<stageName 或 这个神秘人还没有名字>
账号：<loginName>
```

逻辑：

- `loginName` 为空时显示“未登录账号”
- `stageName` 与 `loginName` 相同 → 显示“这个神秘人还没有名字”
- 否则显示 `stageName`

样式：

```text
艺名标签：shellTextPrimary，14px，w600
艺名值：shellTextPrimary，12px，w500
账号标签：shellTextMuted，14px，w500
账号值：shellTextMuted，12px，monospace
```

### 2.3 绑定微信 `_BindWechatButton`

对应代码：`user_center_panel.dart:164-199`

显示条件：

```dart
snapshot.isUser && snapshot.authMode != 'unified'
```

即：邮箱/旧版账号显示，统一账号不显示。

文案：

```text
微信
绑定微信，扫码和邮箱共用同一账号
```

点击后打开 `_WechatBindDialog`。

### 2.4 菜单区 `_UserMenuList`

对应代码：`user_center_panel.dart:481-524`

当前只有一个菜单：

```text
👤 个人中心
```

点击流程：

```text
读取 sessionStore.snapshot
→ SsoService.issueCode(...)
→ 成功：打开
  https://www.jiaofangsi.top/personal-center#sso_code=<code>
→ 失败：回退到普通官网个人中心
  https://www.jiaofangsi.top/personal-center
```

这里已修复一次性码没有拼进 URL 的问题。

### 2.5 会员权益区 `_PrivilegeSection`

对应代码：`user_center_panel.dart:712-735`

当前只保留一个权益卡片：

```text
👑 VIP会员
```

`DJ工具` 权益卡片已删除。

权益卡片包含：

- 图标
- 权益名称
- 状态（例如 `30天` / `未激活`）
- 操作按钮（`开通` / `续费`）

点击开通/续费：

```text
AuthTaskBridge.createVipOrder(token)
→ 获取 payment_url
→ openUrl(payment_url)
→ 800ms 后 refreshEntitlement()
```

权益状态由：

```dart
snapshot.entitlementStatusText('web_vip')
snapshot.hasActiveEntitlement('web_vip')
```

决定。

### 2.6 退出登录 `_LogoutButton`

对应代码：`user_center_panel.dart:1002-1091`

点击后调用：

```dart
widget.onLogout()
```

实际逻辑在 `app_shell_page.dart:274-318`：

1. 检查是否有运行中任务，有则确认
2. 关闭面板
3. 切换登录窗口尺寸
4. `autoLogin = false`
5. 清理 sessionStore
6. 后台清理 Python 本地会话 / 调用登出
7. 跳登录页

---

## 3. 用户中心生命周期

### 3.1 首次打开

对应代码：`user_center_panel.dart:27-57`

```text
didChangeDependencies
→ 读取 DjAppScope.sessionStore.snapshot
→ 立即展示缓存快照
→ 后台调用 authController.refreshAccountSnapshot()
→ 成功后更新 sessionStore + setState
→ 失败保留旧快照
```

刷新过程中没有 loading 占位，界面先显示旧数据。

### 3.2 刷新账号快照

对应代码：`auth_controller.dart:390-447`

#### unified 账号

```text
UnifiedAccountService.profile(token)
UnifiedAccountService.entitlements(token)
→ 更新软快照
→ authBridge.syncUnifiedSession(...)
→ Python 运行时同步权益/资料
```

接口：

```text
GET https://auth.jiaofangsi.top/wechat-auth/v1/account/profile
GET https://auth.jiaofangsi.top/wechat-auth/v1/account/entitlements
```

#### legacy 邮箱账号

```text
authBridge.checkEntitlement(token)
authBridge.getProfile(token)
→ 更新软快照
```

底层 HTTP：

```text
GET https://auth.jiaofangsi.top/entitlements/check
GET https://auth.jiaofangsi.top/api/user/info
```

---

## 4. 绑定微信流程

对应代码：`user_center_panel.dart:201-406`

### 4.1 创建二维码

```text
POST /v1/wechat/challenges
```

响应字段：

```json
{
  "challenge_id": "...",
  "poll_token": "...",
  "expires_at": "...",
  "qr_ticket": "..."
}
```

二维码地址：

```text
https://mp.weixin.qq.com/cgi-bin/showqrcode?ticket=<qr_ticket>
```

### 4.2 轮询扫码状态

```text
POST /v1/wechat/challenges/{challenge_id}/poll
Header: X-Poll-Token: <poll_token>
```

每 2 秒轮询一次。

状态处理：

- `authorized` / `awaiting_bind` → 执行绑定
- `expired` / `cancelled` / `consumed` → 提示二维码失效
- 其他 → 继续等待

### 4.3 绑定到当前邮箱账号

```text
POST /v1/auth/bind
Content-Type: application/json

{
  "challenge_id": "...",
  "poll_token": "...",
  "jiaofangsi_access_token": "<当前 legacy token>",
  "device_name": "desktop"
}
```

成功后返回统一账号 session：

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "access_expires_at": "...",
  "refresh_expires_at": "...",
  "account_id": "...",
  "user": {
    "nickname": "...",
    "avatar_url": "..."
  }
}
```

### 4.4 绑定完成后的本地操作

```text
GET /v1/account/profile
GET /v1/account/entitlements
→ 构造 authMode='unified' 的 AuthSessionSnapshot
→ authController.importUnifiedSession(...)
→ 写入 Python 安全存储
→ 返回快照并刷新面板
```

---

## 5. 个人中心 SSO 接口

对应代码：

- App：`sso_service.dart`
- 账号服务器：`/wechat-auth/v1/sso/issue`
- 官网：`/wechat-auth/v1/sso/redeem`

### 5.1 App 申请一次性码

```text
POST https://auth.jiaofangsi.top/wechat-auth/v1/sso/issue
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "access_token": "<access_token>",
  "refresh_token": "<refresh_token|null>",
  "user_id": "<user_id>",
  "login_name": "<login_name>"
}
```

实际后端以 `Authorization` 为准。

响应：

```json
{
  "success": true,
  "code": "<one-time-code>",
  "expires_in": 60
}
```

### 5.2 打开个人中心

```text
https://www.jiaofangsi.top/personal-center#sso_code=<urlencoded-code>
```

### 5.3 官网兑换

```text
POST https://auth.jiaofangsi.top/wechat-auth/v1/sso/redeem
Content-Type: application/json

{ "code": "<one-time-code>" }
```

统一账号响应：

```json
{
  "mode": "unified",
  "account_id": "...",
  "access_token": "...",
  "refresh_token": "...",
  "access_expires_at": "...",
  "refresh_expires_at": "...",
  "user": {
    "nickname": "...",
    "avatar_url": ""
  }
}
```

旧邮箱账号响应：

```json
{
  "mode": "legacy",
  "user_id": "...",
  "token": "...",
  "login_name": "...",
  "display_name": "..."
}
```

网页把结果写入 `localStorage.jiaofangsi_user`，然后跳转：

```text
https://www.jiaofangsi.top/personal-center#account
```

---

## 6. 用户中心涉及的 HTTP 接口总表

### 6.1 统一账号（wechat-auth）

Base：

```text
https://auth.jiaofangsi.top/wechat-auth
```

| 功能 | 方法 | 路径 | 认证 |
|---|---|---|---|
| 创建扫码 challenge | POST | `/v1/wechat/challenges` | 无 |
| 轮询扫码状态 | POST | `/v1/wechat/challenges/{id}/poll` | `X-Poll-Token` |
| 扫码登录换 session | POST | `/v1/auth/exchange` | challenge |
| 邮箱账号绑定微信 | POST | `/v1/auth/bind` | challenge + legacy token |
| 刷新统一账号 token | POST | `/v1/auth/refresh` | refresh_token |
| 读取统一账号资料 | GET | `/v1/account/profile` | Bearer |
| 读取统一账号权益 | GET | `/v1/account/entitlements` | Bearer |
| 创建统一账号订单 | POST | `/v1/account/purchase` | Bearer |
| SSO 发码 | POST | `/v1/sso/issue` | Bearer |
| SSO 兑换 | POST | `/v1/sso/redeem` | code |

`/v1/account/purchase` 请求：

```json
{ "product": "vip" }
```

或：

```json
{ "product": "dj-workspace" }
```

### 6.2 旧版邮箱账号（auth server）

Base：

```text
https://auth.jiaofangsi.top
```

| 功能 | 方法 | 路径 | 认证 |
|---|---|---|---|
| 邮箱密码登录 | POST | `/auth/login` | 无 |
| 退出登录 | POST | `/auth/logout` | Bearer |
| 查询权益 | GET | `/entitlements/check` | Bearer |
| 读取简要资料 | GET | `/api/user/info` | Bearer |
| 读取完整资料 | GET | `/profile/me` | Bearer |
| 创建 VIP 订单 | POST | `/order/create/vip` | Bearer |
| 创建 DJ 工具订单 | POST | `/order/create/dj-tool` | Bearer |

订单请求 body：

```json
{ "device_type": "pc" }
```

### 6.3 Python RPC 桥接动作

Dart → Python 的 action：

| action | 用途 |
|---|---|
| `login` | 邮箱密码登录 |
| `restore_session` | 恢复本地 session |
| `check_entitlement` | 查询权益 |
| `get_profile` | 读取简要资料 |
| `get_full_profile` | 读取完整资料 |
| `create_vip_order` | 创建 VIP 订单 |
| `create_dj_tool_order` | 创建 DJ 工具订单 |
| `import_unified_session` | 导入统一账号 session |
| `sync_unified_session` | 同步统一账号资料/权益 |
| `logout` | 退出登录 |
| `clear_local_session` | 清理本地 session |
| `save_login_credential` | 保存加密密码 |
| `load_login_credential` | 读取加密密码 |
| `clear_login_credential` | 删除加密密码 |

---

## 7. 登录态数据结构

`AuthSessionSnapshot` 主要字段：

```dart
AuthSessionKind kind;      // anonymous / user / guest
String? authMode;          // legacy / unified
String? token;
String? userId;
String? loginName;
String? stageName;
String? avatarType;
String? avatarUrl;
bool isVip;
DateTime? tokenExpiresAt;
String? refreshToken;
DateTime? refreshExpiresAt;
DateTime? vipExpiresAt;
List<EntitlementInfo>? entitlements;
```

用户中心依赖：

- `snapshot.isUser`
- `snapshot.authMode`
- `snapshot.loginName`
- `snapshot.stageName`
- `snapshot.token`
- `snapshot.isVip`
- `snapshot.entitlements`

权益辅助方法：

```dart
snapshot.hasActiveEntitlement('web_vip')
snapshot.entitlementStatusText('web_vip')
```

---

## 8. 当前 UI 中值得注意的点

### 8.1 已不再显示的模块

- `DJ工具` 权益卡片已删除
- `_UserActionGroup` 当前是空组件
- `_UserActionButton` 仍保留代码但当前没有使用
- `_GuestStatusCard` 仍保留代码，但游客不显示用户中心入口，因此正常情况下不会出现

### 8.2 权益刷新后的 UI

购买支付返回后，代码会调用：

```text
refreshEntitlement()
```

但当前只更新了 `sessionStore`，没有直接更新 `UserCenterPanel` 的内部 `_snapshot`。  
因此如果支付完成后面板仍保持打开，权益文字可能要重新打开用户中心才会刷新。

### 8.3 绑定微信按钮

只在：

```dart
snapshot.authMode != 'unified'
```

时显示。  
因此邮箱账号绑定成功并切换成 unified 后，绑定按钮会消失。

### 8.4 个人中心 SSO 回退

如果 `/sso/issue` 失败，App 会打开普通个人中心链接，不会自动登录。  
这是当前设计，不是登录态丢失。

---

## 9. 建议后续整理方向

如果要把用户中心拆成独立 UI 模块，建议按以下边界拆分：

```text
user_center/
├── user_center_panel.dart        // 容器与状态
├── widgets/
│   ├── user_header.dart
│   ├── bind_wechat_button.dart
│   ├── personal_center_menu.dart
│   ├── privilege_section.dart
│   └── logout_button.dart
├── dialogs/
│   └── bind_wechat_dialog.dart
└── models/
    └── user_center_view_model.dart
```

接口层继续保留在 `UnifiedAccountService`、`AuthController`、`SsoService`，UI 不直接拼 URL。

---

## 10. 结论

当前软件端用户中心是一个 **320px 宽、深色悬浮面板**，主要包含：

```text
用户资料
绑定微信
个人中心 SSO
VIP 会员权益
退出登录
```

所有资料/权益读取都经过 `AuthController.refreshAccountSnapshot()`，统一账号和旧邮箱账号分别走两套接口。  
个人中心通过一次性码 SSO 打开官网，不在 URL 中传递长期 token。
