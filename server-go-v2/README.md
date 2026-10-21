# AirPanel v2

**Air724UG 4G 模块的 Web 控制台** —— 单二进制部署、零构建前端、内嵌 MQTT Broker。

设备通过 MQTT over WebSocket 接入，浏览器即可实时查看信号 / 电压 / 温度、收发短信、拨打电话、下载通话录音，
并下发 18 类 AT 指令、编排定时任务、配置黑白名单与多渠道路通知。

<p>
  <img alt="Go" src="https://img.shields.io/badge/Go-1.22-00ADD8?logo=go&logoColor=white">
  <img alt="SQLite" src="https://img.shields.io/badge/SQLite-pure--Go-003B57?logo=sqlite&logoColor=white">
  <img alt="MQTT" src="https://img.shields.io/badge/MQTT-over%20WebSocket-660066?logo=mqtt&logoColor=white">
  <img alt="Deps" src="https://img.shields.io/badge/frontend-zero--dependency-34C759">
</p>

---

## 目录

- [界面预览](#界面预览)
- [功能特性](#功能特性)
- [技术栈](#技术栈)
- [快速开始](#快速开始)
- [配置说明](#配置说明)
- [设备端接入](#设备端接入)
- [API 一览](#api-一览)
- [目录结构](#目录结构)
- [从旧版迁移](#从旧版迁移)
- [安全说明](#安全说明)

---

## 界面预览

> 截图中涉及隐私的字段（IMEI、ICCID、手机号、WebDAV 地址与账号、通知密钥）均已打码处理。

### 登录

<img src="docs/screenshots/01-login.png" alt="登录页" width="880">

### 监控

<table>
<tr>
<td width="50%"><b>概览</b><br>在线设备、今日通话 / 短信统计，信号、电压、温度的实时趋势<br>
<img src="docs/screenshots/02-overview.png" alt="概览"></td>
<td width="50%"><b>设备</b><br>设备卡片列表、连接状态、运行时长与详情抽屉<br>
<img src="docs/screenshots/03-devices.png" alt="设备"></td>
</tr>
</table>

### 通信

<table>
<tr>
<td width="50%"><b>通话记录</b><br>按设备 / 方向 / 日期 / 号码筛选，支持导出 CSV<br>
<img src="docs/screenshots/04-calls.png" alt="通话记录"></td>
<td width="50%"><b>短信记录</b><br>收件箱与发件箱、关键字检索、单条删除<br>
<img src="docs/screenshots/05-sms.png" alt="短信记录"></td>
</tr>
<tr>
<td colspan="2"><b>通话录音</b> —— 直连 WebDAV 浏览、在线播放、下载与删除，时间按本地时区格式化并按时间倒序排列<br>
<img src="docs/screenshots/06-recordings.png" alt="通话录音" width="880"></td>
</tr>
</table>

### 自动化

<table>
<tr>
<td width="50%"><b>任务执行</b><br>18 条命令目录，参数表单随命令动态生成，结果实时回显<br>
<img src="docs/screenshots/07-tasks.png" alt="任务执行"></td>
<td width="50%"><b>定时任务</b><br>按周 / 月 / 日 / 小时 / 间隔编排，支持立即执行与启停<br>
<img src="docs/screenshots/08-schedules.png" alt="定时任务"></td>
</tr>
<tr>
<td colspan="2"><b>任务记录</b> —— 每次下发的参数、回执与失败原因全程留痕<br>
<img src="docs/screenshots/09-tasklog.png" alt="任务记录" width="880"></td>
</tr>
</table>

### 系统

<table>
<tr>
<td width="50%"><b>日志中心</b><br>设备上报的原始报文与服务端运行日志<br>
<img src="docs/screenshots/10-logs.png" alt="日志中心"></td>
<td width="50%"><b>屏蔽配置</b><br>号码前缀 / 关键字黑白名单，规则命中次数可查<br>
<img src="docs/screenshots/11-block.png" alt="屏蔽配置"></td>
</tr>
</table>

### 基本设置

<table>
<tr>
<td width="50%"><b>账号与安全</b><br>改用户名 / 密码，修改后全部会话失效<br>
<img src="docs/screenshots/12-settings-account.png" alt="账号与安全"></td>
<td width="50%"><b>通知推送</b><br>13 种渠道，可组合启用并发送测试<br>
<img src="docs/screenshots/13-settings-notify.png" alt="通知推送"></td>
</tr>
<tr>
<td width="50%"><b>灯光指示</b><br>远程灯光控制 + 来短信 / 来电的事件灯效，共用保存按钮<br>
<img src="docs/screenshots/14-settings-led.png" alt="灯光指示"></td>
<td width="50%"><b>存储配置</b><br>WebDAV 地址、账号与录音目录<br>
<img src="docs/screenshots/15-settings-storage.png" alt="存储配置"></td>
</tr>
<tr>
<td colspan="2"><b>界面设置</b> —— 自定义站点标题、Logo URL 与管理员头像 URL，以及主题、玻璃通透度、信息密度、强调色<br>
<img src="docs/screenshots/16-settings-ui.png" alt="界面设置" width="880"></td>
</tr>
</table>

### 移动端

<table>
<tr>
<td width="50%"><b>响应式布局</b><br>≤980px 自动折叠为抽屉式导航<br>
<img src="docs/screenshots/17-mobile-overview.png" alt="移动端概览" width="300"></td>
<td width="50%"><b>抽屉导航</b><br>毛玻璃抽屉 + 背景模糊遮罩，点遮罩或横屏自动收起<br>
<img src="docs/screenshots/18-mobile-drawer.png" alt="移动端抽屉" width="300"></td>
</tr>
</table>

---

## 功能特性

**设备监控**
- 设备上线自动注册，实时展示信号强度、电压、温度、运营商、ICCID 等遥测
- 概览页趋势图按实际数据自适应量程，不会因固定坐标把波动压平
- 离线判定内置 5 分钟超时（省电模式下放宽至 30 分钟），避免心跳抖动误报

**通信**
- 通话记录：呼入 / 呼出 / 未接、时长、挂断原因、通知状态，支持筛选与 CSV 导出
- 短信记录：收发双栏、关键字检索
- 通话录音：直连 WebDAV（PROPFIND / GET / DELETE），浏览器内播放，不落本地磁盘

**自动化**
- 18 条命令：状态 / 温度 / 设备信息 / 读配置 / 流量查询 / 发短信 / 拨号 / 挂断 / DTMF / TTS / 呼叫转移 / USSD / 写配置 / 编辑配置 / 音量 / GPIO / 切换 SIM / 重启
- 参数表单严格对齐设备端 `util_mqtt.lua` 的字段名，避免"能点但设备不认"
- 定时任务支持 每周 / 每月 / 每天 / 每小时 / 固定间隔 五种周期，可手动触发
- 任务回执按 `taskId` 匹配，30 秒超时兜底，失败原因完整留痕

**系统**
- 日志中心：设备上报报文 + 服务端运行日志（2000 行环形缓冲），支持级别与关键字过滤、5 秒自动刷新
- 屏蔽配置：号码前缀 / 完全一致 / 包含，关键字包含，规则改动即时下发全设备
- 通知推送：Message-Pusher、Server酱、钉钉、飞书、企业微信、Bark、PushDeer、Pushover、Telegram、Gotify、自定义 HTTP POST、iNotify、SMTP 邮件转发

**外观**
- 站点标题、Logo URL、管理员头像 URL 均可自定义：Logo 一个地址同时作用于侧栏左上角、登录页与 favicon，头像一个地址同时作用于右上角与左下角
- 浅色 / 深色主题、玻璃通透度、信息密度、强调色，实时生效
- Liquid Glass 视觉：浮动玻璃侧栏、玻璃顶栏、弥散光斑背景

---

## 技术栈

| 层 | 选型 | 说明 |
|---|---|---|
| 服务端 | Go 1.22 + `net/http` | 标准库 `ServeMux`，无 Web 框架 |
| 数据库 | SQLite（`modernc.org/sqlite`） | 纯 Go 实现，**无需 CGO**，可静态交叉编译 |
| 鉴权 | JWT（`golang-jwt/jwt/v5`） | Bearer Token + `tokenVersion` 失效机制 |
| 密码 | bcrypt + `crypto/subtle` | 常量时间比较，防时序侧信道 |
| MQTT | `mochi-mqtt/server/v2` | 内嵌 Broker，走 WebSocket 与 HTTP 同端口 |
| 前端 | 原生 ES Module | 零构建、零依赖，`go:embed` 内嵌进二进制 |

单端口同时提供 **HTTP 面板** 与 **MQTT over WebSocket**（`/websocket`），公网只需开放一个端口。

---

## 快速开始

### 方式一：二进制

```bash
# 编译（产物约 19MB，已内嵌全部前端资源）
go build -o panel-v2 .

# 运行；首次启动会自动生成 config.json（账号 admin / 密码 admin123）
./panel-v2 -config config.json -db panel-v2.db -http-port 9600
```

浏览器打开 `http://<服务器IP>:9600`，用 `admin` / `admin123` 登录，**请立即在「基本设置 → 账号与安全」修改密码**。

### 方式二：Docker

```bash
# 单架构
docker build -t airpanel-v2 .

# 多架构（amd64 / arm64）
docker buildx build --platform linux/amd64,linux/arm64 -t airpanel-v2 .

docker run -d --name airpanel-v2 \
  -p 9600:9600 \
  -v $(pwd)/data:/app/data \
  --restart unless-stopped \
  airpanel-v2
```

> 容器内默认监听 `9527`（见 `Dockerfile` 的 `CMD`），需要改成 9600 时覆盖启动参数即可。
> `config.json` 含敏感凭据，**不入镜像也不入库**，首次启动自动生成到挂载卷。

### 命令行参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `-config` | `config.json` | 配置文件路径，不存在则自动生成 |
| `-db` | 取配置文件 `dbPath` | SQLite 数据库路径，覆盖配置文件 |
| `-http-port` | 取配置文件 `port` | HTTP 监听端口，覆盖配置文件 |

---

## 配置说明

`config.json` 首次启动自动生成：

```json
{
  "jwtSecret": "<启动时随机生成>",
  "user": { "username": "admin", "password": "<bcrypt 哈希>" },
  "tokenVersion": 1,
  "port": 9600,
  "mqtt": { "host": "0.0.0.0", "port": 0 },
  "dbPath": "panel-v2.db"
}
```

| 字段 | 说明 |
|---|---|
| `jwtSecret` | JWT 签名密钥，首次启动随机生成 32 字节 |
| `user` | 初始管理账号；登录后以数据库中的设置为准 |
| `tokenVersion` | 令牌版本，自增即可让所有已签发 Token 立即失效 |
| `port` | HTTP 端口，同时承载面板与 MQTT over WebSocket |
| `mqtt.port` | MQTT TCP 监听端口，`0` 表示不启用（默认只走 WebSocket） |
| `dbPath` | SQLite 文件路径 |

除 `jwtSecret` / `port` 等启动项外，通知渠道、灯光、WebDAV、品牌等运行期设置都保存在数据库的 `settings` 表中，
可在面板内修改，无需重启。

---

## 设备端接入

设备端脚本（`Air724ug/script`）把 MQTT 指向本服务端即可，走 WebSocket：

```
ws://<服务器IP>:9600/websocket      # 或 wss:// 反向代理后
```

Topic 约定：

| 方向 | Topic | 说明 |
|---|---|---|
| 设备 → 服务端 | `device/{imei}/online` | 上线注册 / 心跳 |
| 设备 → 服务端 | `device/{imei}/telemetry` | 遥测上报（电压 / 温度 / 信号） |
| 设备 → 服务端 | `device/{imei}/result` | 指令回执，按 `taskId` 匹配 |
| 设备 → 服务端 | `device/{imei}/{type}` | 通话 / 短信 / 录音等业务上报，全部落库并进日志中心 |
| 服务端 → 设备 | `device/{imei}/cmd` | 面板下发的指令 |

---

## API 一览

除 `/api/login`、`/api/health` 外，全部接口需在请求头携带 `Authorization: Bearer <token>`。

| 分组 | 端点 |
|---|---|
| 鉴权 | `POST /api/login`、`POST /api/logout`、`POST /api/change-user-info` |
| 设备 | `GET /api/userPool`、`POST /api/device/remark`、`POST /api/device/delete`、`GET /api/device/overview`、`POST /api/device/overview/config`、`GET /api/stats/summary` |
| 任务 | `POST /api/executeTask`、`GET /api/tasks`、`POST /api/tasks/clear` |
| 定时 | `GET /api/schedules`、`POST /api/schedules/{add,update,toggle,delete,run}` |
| 记录 | `GET /api/calls`、`POST /api/calls/{clear,delete}`、`GET /api/sms`、`POST /api/sms/{clear,delete}` |
| 日志 | `GET /api/logs`、`POST /api/logs/clear`、`GET /api/server-logs`、`POST /api/server-logs/clear` |
| 屏蔽 | `GET /api/block-rules`、`POST /api/block-rules/{add,update,delete,reset}` |
| 录音 | `GET /api/recordings`、`GET /api/recordings/{play,download}`、`POST /api/recordings/delete` |
| 设置 | `GET /api/settings`、`POST /api/settings/save`、`GET /api/notify/channels`、`POST /api/notify/test` |
| 运维 | `GET /api/health`、`POST /api/restart` |
| MQTT | `GET /websocket`（WebSocket Upgrade） |

---

## 目录结构

```
server-go-v2/
├── main.go                 # 入口：参数解析、日志缓冲、HTTP 启动
├── config.go               # 配置加载与默认值生成
├── api.go                  # 路由注册、鉴权中间件、静态资源与 SPA 回退
├── api_devices.go          # 设备列表 / 备注 / 删除 / 概览 / 统计
├── api_tasks.go            # 指令下发与任务记录
├── api_schedules.go        # 定时任务 CRUD 与手动执行
├── api_records.go          # 通话 / 短信记录（共用 RecordFilter）
├── api_logs.go             # 设备日志 + 服务端日志
├── api_blocks.go           # 屏蔽规则
├── api_settings.go         # 面板设置与通知测试
├── broker.go               # 内嵌 MQTT Broker、Topic 分发、指令回执
├── notify.go               # 13 种通知渠道实现
├── scheduler.go            # 定时任务调度（每周/月/日/时/间隔）
├── settings.go             # 设置模型与读写
├── webdav.go               # WebDAV 录音列表 / 播放 / 下载 / 删除
├── db.go                   # SQLite 建表与查询
├── serverlog.go            # 服务端日志环形缓冲
├── Dockerfile
├── docs/screenshots/       # README 配图
└── static/                 # 前端（go:embed 内嵌）
    ├── index.html
    ├── css/app.css
    └── js/
        ├── app.js          # 路由、外观、品牌、服务端状态
        ├── api.js          # 45 个接口封装
        ├── store.js        # 全局状态
        ├── ui.js           # 通用组件与格式化
        ├── icons.js        # 62 个 SVG 图标
        └── pages/          # 11 个页面模块
```

---

## 从旧版迁移

数据库 schema 与旧版 `server-go` 一致，直接复制即可：

```bash
cp /path/to/old/panel.db /path/to/new/panel-v2.db
./panel-v2 -config config.json -db panel-v2.db -http-port 9600
```

v2 默认使用 **9600 端口** 与 **`panel-v2.db`**，可与旧版同时运行、并行验证，确认无误后再切换端口。

---

## 安全说明

- 密码使用 bcrypt 哈希存储，登录校验走常量时间比较
- 修改账号或密码会自增 `tokenVersion`，所有已签发 Token 立即失效
- `config.json` 含 JWT 密钥与账号哈希，已在 `.gitignore` 中排除，请勿提交
- 面板默认走 HTTP，公网部署建议前置 Nginx / Caddy 配置 TLS，并使用 `wss://` 接入设备
- README 配图中的 IMEI、ICCID、手机号、WebDAV 凭据、通知密钥均为演示数据或已打码

---

## 许可证

本项目为个人自用项目，未附带开源许可证。如需引用请先联系作者。
