# 一次性码 SSO

正式实现位于账号服务器 `wechat-auth` 服务。

## 接口

- `POST https://auth.jiaofangsi.top/wechat-auth/v1/sso/issue`
  - App 使用当前 access token 调用
  - 返回 60 秒有效、单次使用的一次性码
- `POST https://auth.jiaofangsi.top/wechat-auth/v1/sso/redeem`
  - 官网使用一次性码兑换网页登录态
  - 统一账号返回独立网页 session
  - 旧邮箱账号返回旧版账号 token，保持官网和 App 数据来源一致

## 服务端文件

部署到：

```text
/srv/wechat-auth/artifacts/wechat-auth-service/app/
```

对应文件：

- `api.py`：新增 `/v1/sso/issue`、`/v1/sso/redeem`
- `unified.py`：解析统一账号 / 旧邮箱账号
- `sso_codes.py`：一次性码存储（60 秒、单次使用、进程内）

修改后：

```bash
systemctl restart wechat-auth
curl https://auth.jiaofangsi.top/wechat-auth/healthz
```

## 官网

`website_sso_bootstrap.js` 注入到 `/var/www/html/index.html`，负责：

- 读取 `#sso_code`
- 调用账号服务器兑换
- 保存 `jiaofangsi_user`
- 跳转到个人中心

## 桌面端

- `SsoService` 调用账号服务器 `/v1/sso/issue`
- 打开 `https://www.jiaofangsi.top/personal-center#sso_code=...`

## 安全

- 一次性码 60 秒有效、单次使用
- token 不进入 URL
- 官网兑换接口由账号服务器签发独立会话
- 原官网临时 Broker 已停用并移除
