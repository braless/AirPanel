# AirPanel

基于合宙 **Air724UG** 4G 模组（LuatOS-Air）的远程管理面板与短信 / 通话转发器。

本项目由 [vipxkw/AirPanel](https://github.com/vipxkw/AirPanel) **修改而来**，在其基础上扩展了通话 / 短信记录留存、垃圾屏蔽、设备概览（功耗 / 信号 / 续航）等能力。

服务端为 **Go 单二进制**（内置 HTTP 面板 + MQTT Broker），前端使用 **Tailwind CSS** 构建并以 `go:embed` 内嵌进二进制，相比原 WebSocket 方案显著降低设备流量消耗。

> 请勿用于非法用途及盈利。

## 特性

- **设备远程管理**：设备列表、在线状态、一键下发任务（查询温度 / 发送短信 / 拨打电话 / 读取配置 / 写入配置 / 重启等）、删除设备
- **MQTT 接入**：Go 服务端内置 MQTT Broker，设备端经 **MQTT over WebSocket（WSS）** 接入，心跳仅 2 字节、间隔 30s，省流量
- **通话记录 / 短信记录**：设备端自动上报通话（来电 / 去电、接通 / 未接 / 拒接 / 未应答、时长）与短信（收 / 发、内容），服务端 SQLite 留存，面板支持**时间范围与设备筛选、分页查看、单条删除、批量清理**
- **通知状态列**：通话 / 短信记录展示每条记录的 **Bark 通知推送状态**（已推送 / 被屏蔽 / 失败）
- **垃圾屏蔽**：支持**关键字屏蔽**与**号码屏蔽**，内置常见垃圾 / 骚扰规则（默认数据），命中规则后标记为垃圾并**不再发送通知**，记录中标明命中规则
- **设备概览**：实时遥测——信号强度（RSRP / CSQ / RSSI）、功耗、在线时长、当前电压 / 电流、**预估续航**（电池容量可配置，默认 1800mAh），含趋势图
- **定时任务**：宝塔面板式计划任务，支持每周 / 每月 / 每天 / 每小时 / 每 N 分钟 / 每 N 小时周期自动下发，设备离线时静默跳过该次执行
- **远程配置**：读取 / 写入设备端 `nvm_para.lua` 参数文件，支持动态修改设备配置
- **多通道通知**：设备端支持 gotify / telegram / bark / 钉钉 / 飞书 / 企业微信 / pushover / message-pusher 等通知渠道
- **Bark 定制**：主标题（自动取发件人 / 来电号码）、自定义图标（icon）、分组（默认 `汉中移动`）、推送声音（默认 `glass`）、精简内容
- **离线通知**：服务端通过心跳超时或连接断开判定设备离线，支持 13 个通知渠道推送离线告警
- **断线自愈**：设备端连接失败指数退避重连（5s→60s 封顶），内置双重看门狗，服务端重部署后设备自动恢复连接
- **单二进制部署**：前端静态资源通过 `go:embed` 内嵌进 Go 二进制，支持 Docker 一键部署
- **PWA 现代 UI**：Tailwind 现代化界面、移动端适配，支持 **iOS「添加到主屏幕」** 以全屏方式运行

## 界面预览

### 设备列表

![设备列表](screenshots/ScreenShot_2026-08-27_224939_410.png)

### 任务执行

![任务执行](screenshots/ScreenShot_2026-08-27_224957_057.png)

### 任务记录

![任务记录](screenshots/ScreenShot_2026-08-27_225002_085.png)

### 设置界面

![设置界面](screenshots/ScreenShot_2026-08-27_225007_118.png)

## 系统架构

```
┌────────────┐   wss://host/websocket  ┌──────────────────────────────┐
│ Air724UG   │ ◄──────(443 加密)──────►│        nginx / xray (443)    │
│ 设备端Lua  │    MQTT over WebSocket   │  /websocket ──┐              │
│ 固件 script│    cmd/{imei} 等主题      │  /  ──────────┼────────────┐ │
└────────────┘                          │              ▼            │ │
                                        │  ┌──────────────────────┐ │ │
                                        │  │   panel-server :9527 │ │ │
                                        │  │ ┌───────┐ ┌────────┐ │ │ │
                                        │  │ │ MQTT  │ │ HTTP   │ │ │ │
                                        │  │ │ Broker│ │ 面板    │ │ │ │
                                        │  │ │ (WS)  │ │ REST+前端│ │ │ │
                                        │  │ └───────┘ └────────┘ │ │ │
                                        │  │        │ SQLite      │ │ │
                                        │  └────────┴─────────────┘ │ │
                                        └──────────────────────────┘ ┘
```

- 公网仅开放 **一个端口**：443 终结 TLS（`/websocket` 与 `/` 都反代到 `panel-server` 的 **9527** 端口）——MQTT over WSS 与 Web 面板共用同一端口，无需再暴露 1883/8083
- 设备经 **wss（443）** 接入，MQTT 数据封装在 WebSocket 帧中传输，加密且省流量；内网也可用 `ws://host:9527/websocket` 直连，或可选启用 MQTT TCP 内网直连
- 设备订阅 `cmd/{imei}` 接收指令，上报 `device/{imei}/online`（上线）、`device/{imei}/result`（任务结果）与 `device/{imei}/telemetry`（遥测）
- 面板通过 REST API 下发任务，服务端转 MQTT 推送给设备并等待回报（30 秒超时）

## 目录结构

```
AirPanel/
├── Air724ug/             # Air724UG 设备端 Lua 固件（LuatOS-Air）
│   ├── core/             # 底层固件包（.pac）
│   └── script/
│       ├── main.lua      # 入口：初始化、MQTT/通知/监听启动
│       ├── config.lua    # 设备端默认配置（通知/MQTT/音量/来电动作/Bark 等，含注释示例）
│       ├── nvm_para.lua  # 设备端参数文件【参考模板】（可写入配置的示例）
│       ├── lib/          # 底层库（nvm / mqtt / websocket / sys 等）
│       ├── utils/        # 功能模块（util_mqtt / util_notify / util_mobile / util_record / util_block 等）
│       └── handler/      # 事件处理（短信 / 来电 / 电源键菜单）
├── server-go/            # Go 服务端（当前主版本）
│   ├── main.go           # 入口：加载配置、启动 HTTP + MQTT + 定时任务调度器
│   ├── api.go            # REST API 与静态资源（go:embed）
│   ├── broker.go         # MQTT Broker、设备在线管理、任务下发、遥测接收
│   ├── notify.go         # 离线通知渠道 + Bark 推送（标题/icon/分组/声音）
│   ├── db.go             # SQLite 持久化（设备/任务/通话/短信/屏蔽规则/遥测）
│   ├── scheduler.go      # 定时任务调度器
│   ├── settings.go       # 面板设置（账号/通知/概览配置，SQLite 持久化）
│   ├── config.go         # 配置加载/保存
│   ├── config.example.json # 服务端配置示例
│   ├── static/           # 前端单页应用（PWA，编译进二进制，改动后重新 build）
│   ├── sim_device_ws.py  # 模拟设备脚本（WebSocket MQTT 联调用）
│   ├── Dockerfile
│   └── gen_icons.py      # PWA 图标生成脚本
├── screenshots/          # 界面截图
├── docker-compose.yml    # Docker 一键部署
└── README.md
```

## 快速开始（Go 服务端）

### 本地运行

前置：Go 1.22+（本项目使用纯 Go 的 `modernc.org/sqlite`，无需 CGO）。

```bash
cd server-go
go build -o panel-server.exe .
./panel-server.exe
```

默认配置：

- HTTP 面板 + MQTT over WebSocket（`/websocket`）：`http://127.0.0.1:9527`（单端口）
- 默认账号：`admin / admin123`（可在面板「设置」中修改用户名/密码，或编辑 `config.json`）

### 前端修改（改动 static/ 后需重新构建）

前端资源在 `server-go/static/`（页面、JS、CSS），编译时通过 `go:embed` 内嵌进二进制，改动后重新 `go build` 即生效：

```powershell
cd server-go
go build -o panel-server.exe .
```

> `static/css/style.css` 为 Tailwind 编译产物，缺少的工具类请用内联样式或手动补齐。

### Docker 部署

**方式一：本地构建 + docker-compose**

```bash
docker-compose up -d
```

`docker-compose.yml` 仅发布 `9527`（HTTP 面板 + MQTT over WebSocket 共用），SQLite 数据库与 `config.json` 通过卷 `panel-data` 持久化到容器 `/app/data/` 下。

**方式二：Dockerfile 构建**

```bash
cd server-go
docker build -t airpanel .
docker run -d --name airpanel --restart unless-stopped \
  -p 9527:9527 \
  -v panel-data:/app/data \
  airpanel
```

- `-p 9527` HTTP 面板 + MQTT over WebSocket（`/websocket`）共用，**只需这一个端口**
- `-v panel-data:/app/data` SQLite 数据与 `config.json` 配置统一持久化到命名卷；首次启动自动生成默认配置（账号 `admin / admin123`），升级容器不丢失配置

> **低配服务器提示**：若服务器资源紧张，可直接在本地交叉编译 Linux 二进制上传运行（`GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build`），无需 Docker。

### WSS 加密接入（推荐，公网部署）

MQTT over WebSocket 与 Web 面板共享 `9527` 端口（路径 `/websocket`）。公网部署用 nginx 做 TLS 终结并反代，设备以 `wss://你的域名/websocket` 一条链接接入，全程加密：

```nginx
server {
    listen 443 ssl;
    server_name panel.example.com;

    ssl_certificate     /etc/nginx/ssl/fullchain.pem;   # 你的证书
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    # 设备 MQTT over WSS：/websocket -> 127.0.0.1:9527
    location /websocket {
        proxy_pass http://127.0.0.1:9527;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }

    # Web 面板
    location / {
        proxy_pass http://127.0.0.1:9527;
    }
}
```

> 若 80/443 与 Go 服务端不在同一台机器，把 `proxy_pass` 指向服务端 IP 即可；仅需开放 443，**无需**再暴露任何其它端口。

## 设备端固件对接

1. 将 `Air724ug/script/` 目录内容按原结构烧录到设备（底层固件见 `Air724ug/core/`）
2. 在 `Air724ug/script/config.lua` 中配置服务端地址，**推荐单链接 `MQTT_URL`**（一条链接搞定）：

```lua
-- 公网（推荐）：wss 加密，nginx 反代 443 → 面板端口 /websocket
MQTT_URL = "wss://panel.example.com/websocket"
-- 内网明文 WebSocket（直接连面板端口）：
-- MQTT_URL = "ws://192.168.1.100:9527/websocket"
-- 内网 MQTT TCP（需服务端 config.json 中 mqtt.port > 0 启用）：
-- MQTT_URL = "mqtt://192.168.1.100:1883"

MQTT_KEEPALIVE = 30    -- 心跳间隔（秒），仅在此间隔发 2 字节心跳包，可降低流量
```

> 也兼容旧参数 `MQTT_HOST` / `MQTT_PORT`（TCP 明文，`MQTT_URL` 留空时生效）。

3. `main.lua` 检测到 `MQTT_URL` 或 `MQTT_HOST` 任一非空即自动启动 MQTT 连接；同时需配置一个通知渠道（如 gotify / bark）用于接收设备事件。

### 断线重连与自愈机制

- **重连指数退避**：连接失败后按 5s→10s→20s→40s→60s（封顶）间隔重试；服务端恢复后最多 60 秒内自动重连
- **静默断开检测**：超过 2 个 keepalive 周期未收到服务端任何数据即判定断线，主动重连
- **应用层心跳**：按 `HEARTBEAT_INTERVAL`（默认 120 秒）周期上报 `device/{imei}/online`，服务端据此判定在线状态
- **双重看门狗**：`MQTT_STUCK_TIMEOUT`（假死，默认 5 分钟）/ `MQTT_REBOOT_TIMEOUT`（持续连不上，默认 15 分钟），自动重启模块自愈；置 0 可关闭
- **开机通知带原因**：开机推送显示重启原因（按键开机 / 充电开机 / 软件重启 / 异常复位）

### 设备端参数文件 nvm_para.lua

设备端掉电保存的实时参数文件（`/nvm_para.lua`），优先级高于 `config.lua`。仓库内 `Air724ug/script/nvm_para.lua` 提供了**全部可写参数的注释示例**，可直接复制到面板「任务执行 → 写入配置」中使用，支持远程配置：

- **通知方式**：`NOTIFY_TYPE` 及 gotify/telegram/bark/钉钉/飞书/企业微信等渠道参数（Bark 含 `BARK_TITLE`/`BARK_ICON`/`BARK_GROUP`/`BARK_SOUND`）
- **MQTT 参数**：`MQTT_URL` / `MQTT_HOST` / `MQTT_PORT` / `MQTT_KEEPALIVE` / `HEARTBEAT_INTERVAL`
- **自愈参数**：`MQTT_STUCK_TIMEOUT` / `MQTT_REBOOT_TIMEOUT`（0 关闭）
- 音量、来电动作、短信播报、开机通知、网卡、指示灯、SIM pin、录音上传地址等

> 生效规则：固件用 `nvm.get()` 读取的参数（音量/来电动作/短信播报/开机通知等）写入后**重启持久生效**；用 `config.xxx` 读取的参数（MQTT 地址/通知渠道）写入后**当前运行立即生效**。

## Web 面板功能

- **设备列表**：IMEI / 备注 / 手机号 / 在线状态 / 接入时间，支持在线编辑备注、跳转执行任务、删除设备
- **设备概览**：信号强度（RSRP / CSQ / RSSI）、功耗、在线时长、当前电压 / 电流、预估续航，遥测趋势图（电池容量可配置）
- **任务执行**：三步向导式指挥台（选择设备 → 选择任务类型 → 下发执行），内置终端风格实时控制台；任务类型含查询温度 / 发送短信 / 拨打电话 / 读取配置 / 写入配置 / 重启等
- **定时任务**：宝塔面板式计划任务管理（新增 / 编辑 / 启停 / 删除 / 立即执行），设备离线时静默跳过
- **任务记录**：执行记录分页查看（成功/失败 + 结果详情，可清理旧日志）
- **通话记录**：通话历史（来电 / 去电、接通 / 未接 / 拒接 / 未应答、时长），支持时间范围与设备筛选、分页、单条删除、清理；展示通知推送状态与垃圾标记（命中规则）
- **短信记录**：短信历史（收 / 发、内容），支持时间范围与设备筛选、分页、单条删除、清理；展示通知推送状态与垃圾标记（命中规则）
- **屏蔽配置**：关键字屏蔽与号码屏蔽规则管理（新增 / 编辑 / 删除 / 重置），内置默认垃圾规则；命中规则后不再发送通知
- **设置**：Tab 式设置页——登录账号、离线通知（开关 / 渠道配置 / 测试通知）、Bark 推送参数

## API 一览

| 方法 | 路径 | 说明 | 鉴权 |
| --- | --- | --- | --- |
| POST | `/api/login` | 登录，返回 JWT | 否 |
| POST | `/api/logout` | 退出登录 | 是 |
| POST | `/api/change-user-info` | 修改用户名/密码 | 是 |
| GET | `/api/userPool` | 设备列表 | 是 |
| POST | `/api/device/remark` | 设置设备备注 | 是 |
| POST | `/api/device/delete` | 删除设备 | 是 |
| GET | `/api/device/overview` | 设备概览（信号/功耗/在线时长/电流/续航/遥测） | 是 |
| POST | `/api/device/overview/config` | 保存概览配置（如电池容量） | 是 |
| POST | `/api/executeTask` | 下发任务（含拨打电话 `dial_call` 等） | 是 |
| GET | `/api/tasks` | 任务记录（分页） | 是 |
| POST | `/api/tasks/clear` | 清理任务记录 | 是 |
| GET | `/api/schedules` | 定时任务列表（分页） | 是 |
| POST | `/api/schedules/add` | 新增定时任务 | 是 |
| POST | `/api/schedules/update` | 编辑定时任务 | 是 |
| POST | `/api/schedules/toggle` | 启用 / 停用定时任务 | 是 |
| POST | `/api/schedules/delete` | 删除定时任务 | 是 |
| POST | `/api/schedules/run` | 立即执行一次定时任务 | 是 |
| GET | `/api/settings` | 读取面板设置 | 是 |
| POST | `/api/settings/save` | 保存面板设置 | 是 |
| GET | `/api/notify/channels` | 获取通知渠道定义 | 是 |
| POST | `/api/notify/test` | 发送测试通知 | 是 |
| GET | `/api/calls` | 通话记录（分页；`from/to`、`imei` 筛选） | 是 |
| POST | `/api/calls/clear` | 清理通话记录 | 是 |
| POST | `/api/calls/delete` | 删除单条通话记录 | 是 |
| GET | `/api/sms` | 短信记录（分页；`from/to`、`imei` 筛选） | 是 |
| POST | `/api/sms/clear` | 清理短信记录 | 是 |
| POST | `/api/sms/delete` | 删除单条短信记录 | 是 |
| GET | `/api/block-rules` | 屏蔽规则列表（分页） | 是 |
| POST | `/api/block-rules/add` | 新增屏蔽规则 | 是 |
| POST | `/api/block-rules/update` | 编辑屏蔽规则 | 是 |
| POST | `/api/block-rules/delete` | 删除屏蔽规则 | 是 |
| POST | `/api/block-rules/reset` | 重置为内置默认规则 | 是 |
| GET | `/api/health` | 健康检查 | 否 |
| WS | `/websocket` | MQTT over WebSocket（设备接入） | - |

## 服务端配置（config.json）

```json
{
  "jwtSecret": "会话签名密钥",
  "user": { "username": "登录用户名", "password": "bcrypt 密文" },
  "tokenVersion": 1,
  "port": 9527,
  "mqtt": { "host": "0.0.0.0", "port": 0 },
  "dbPath": "panel.db"
}
```

- `mqtt.port`：MQTT TCP 监听端口，0 表示不启用；公网默认只走 WebSocket/WSS（与面板共享 9527，路径 `/websocket`）
- 账号、离线通知、屏蔽规则、概览配置等存储在 SQLite（首次启动自动从 `config.json` 迁移账号），面板「设置」中修改即时生效

## 模拟设备联调（无实体设备）

`server-go/sim_device_ws.py`：通过 MQTT over WebSocket 模拟接入（验证 wss 链路），依赖 `paho-mqtt`

```bash
cd server-go
python sim_device_ws.py
```

> 脚本默认连公网 wss（`panel.example.com:443`），内网联调请改为 `BROKER = "127.0.0.1"`、`WS_PORT = 9527`、`USE_TLS = False`。

## 致谢与许可

本项目基于 [vipxkw/AirPanel](https://github.com/vipxkw/AirPanel) 修改而来，感谢原作者的开源贡献。

> 本项目仅供学习与技术研究，请勿用于非法用途及盈利。
