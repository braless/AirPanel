# AirPanel iOS v2 — iOS 26+ 原生客户端

基于 `server-go-v2` 已实现的能力，从零设计的 iOS 26+ 原生客户端。
**没有参考 `AirPanel-iOS`**（旧客户端）的任何代码或视觉。

- 平台：iOS 26.0+（Liquid Glass：`glassEffect`、玻璃 TabBar、`tabBarMinimizeBehavior`）
- 技术：SwiftUI + `@Observable`，无第三方依赖
- 数据：**真实接入 `server-go-v2`**，端点与网页端逐一对齐，没有本地假数据
- 鉴权：服务器地址 + 账号密码登录，JWT（60 天）+ Keychain 记住密码
- 工程：`AirPanelV2.xcodeproj`，scheme `AirPanelV2`，Bundle ID `com.oaife.airpanel.v2`

## 运行

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd AirPanel-iOS-v2
xcodebuild -project AirPanelV2.xcodeproj -scheme AirPanelV2 \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build

xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/AirPanelV2.app
xcrun simctl launch booted com.oaife.airpanel.v2
```

首次启动停在登录页：填服务器地址（域名或 `主机:端口` 都行，
没写 scheme 会按私网/公网自动补 `http`/`https`）、账号、密码，勾「记住密码」下次自动填。

启动参数（截图与联调用，仅 Debug 构建存在）：

| 参数 | 效果 |
| --- | --- |
| `-tab overview\|comms\|automation\|devices\|settings` | 打开指定 Tab |
| `-comms calls\|sms\|recordings` | 通信页子分段 |
| `-auto tasks\|schedules\|log` | 自动化页子分段 |
| `-settings notify\|led\|power\|record\|storage\|block\|logs\|brand` | 设置二级页 |
| `-runner` | 直接弹出指令执行面板 |
| `-device` | 直接弹出设备详情 |
| `-login` | 强制停在登录页（不自动进主界面） |
| `-autologin "url\|user\|pass"` | 跳过登录直接进；第四段写 `remember` 走记住密码 |
| `-send get_status` | 启动后真实下发一条指令，验证 executeTask 全链路 |
| `-autoplay` | 自动播第一条录音，验证带 token 取音频流 |
| `-loadmore` | 进通信页自动翻一页（跟随当前分段，通话/短信都能用），验证分页追加与去重 |
| `-swipeopen` | 把所有记录行停在「已左滑」状态，核对红色删除底 |
| `-deletetop` | 自动删掉第一条通话并打印前后计数，验证删除真的落到服务端 |
| `-runschedule 1` | 自动点第 2 张定时卡片的「执行任务」，验证执行中 → 回执 → 4 秒收起 |
| `-autorefresh 10` | 把前台自动刷新间隔改成 10 秒（默认 60） |
| `-appearance light\|dark\|system` | 强制外观（走 UserDefaults 参数域，不改偏好） |
| `-bottom` | 概览 / 通信页滚到底部 |

## 打包未签名 IPA

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd AirPanel-iOS-v2

xcodebuild -project AirPanelV2.xcodeproj -scheme AirPanelV2 -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build-ipa \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP=build-ipa/Build/Products/Release-iphoneos/AirPanelV2.app
rm -rf dist && mkdir -p dist/Payload
cp -R "$APP" dist/Payload/
find dist/Payload -name "_CodeSignature" -type d -exec rm -rf {} +
(cd dist && zip -qry -X AirPanelV2-unsigned.ipa Payload)
```

产物 `dist/AirPanelV2-unsigned.ipa`：arm64、未签名、最低 iOS 26.0。

**未签名包不能直接安装**，需要先重签（Sideloadly / AltStore / TrollStore，
或 `codesign` + 描述文件）。也可以只取 `Payload/AirPanelV2.app` 单独重签。

## 登录与凭据

```
登录页 ──POST /api/login──▶ { token, username }
   │
   ├── token        → Keychain（kSecClassGenericPassword，AfterFirstUnlockThisDeviceOnly）
   ├── 密码          → Keychain（仅勾了「记住密码」时）
   └── 地址/账号/开关 → UserDefaults
```

- 冷启动 `Credentials.restore()` 直接把会话装回 `PanelStore`，不闪登录页。
- 任何接口返回 401 一律当作会话结束：清 Keychain、回登录页，不在页面里弹错误。
- 退出登录先 `POST /api/logout` 让服务端拉黑 token，失败也照样本地退出。

## 网络层

四层，职责不混：

| 文件 | 职责 |
| --- | --- |
| `Network/Wire.swift` | 与服务端 JSON 逐字段对齐的纯 wire 层，`CodingKeys` 处理 `operator` 之类关键字，不含任何展示逻辑 |
| `Network/APIClient.swift` | 地址归一化、Bearer 注入、HTTP 状态码 → `APIError`、错误文案中文化；一个实例绑定一个 `baseURL` + `token` |
| `Network/Credentials.swift` | Keychain + UserDefaults 分层存储 |
| `Model/Models.swift` | 展示层模型，全部 `init(wire:)`，把服务端的枚举/时间戳/JSON 字符串转成 UI 能直接用的东西 |

地址归一化规则：已带 scheme 照用；私网/环回/`.local`/带端口的裸主机补 `http`；
其余裸域名补 `https`。面板多数跑在局域网明文端口，这个默认值省掉一半的登录失败。

## API 映射

端点全部照抄 `server-go-v2` 的 `routes()`，没有自造接口：

| 页面 | 端点 |
| --- | --- |
| 登录 / 登出 / 改账号 | `POST /api/login`、`/api/logout`、`/api/changeUserInfo` |
| 概览 | `GET /api/devices`、`/api/overview?imei=`、`/api/stats/summary` |
| 设备 | `POST /api/remarkDevice`、`/api/deleteDevice`、`/api/saveOverviewConfig` |
| 任务 | `GET /api/tasks?page=`、`POST /api/executeTask`、`/api/tasks/clear` |
| 定时 | `GET /api/schedules`、`POST /api/schedules/add`、`/toggle`、`/run`、`/delete` |
| 通话 / 短信 | `GET /api/calls`、`/api/sms`（分页 + 关键词 + 方向），`/delete`、`/clear` |
| 录音 | `GET /api/recordings`、`/api/recordings/play?file=`（二进制，带 Bearer）、`/delete` |
| 屏蔽 | `GET /api/blockrules?type=`、`/add`、`/update`、`/delete`、`/reset` |
| 设置 | `GET /api/settings`、`/saveSettings`、`/notify/channels`、`/notify/test` |
| 日志 | `GET /api/logs`、`/api/logs/server`、`/clear` |
| 运维 | `GET /api/health`、`POST /api/restart` |

设备端的 Lua 配置（录音开关、TTS 前置提示、省电窗口）走 `executeTask get_config` +
`write_config`，与网页端 `settings.js` 的 `patchLuaConfig` 同一套做法：读全文、按行替换、
写回，不做「拼一段配置」这种会覆盖用户手写内容的事。

## 刷新策略（真实网络下才暴露的问题）

公网服务端单次往返 1.5～2 秒，十几个接口串行要 30 秒以上。最终方案：

1. **设备列表先跑**（决定 `activeDeviceID`），其余 10 个接口并发，宽度 8。
   实测 12 个请求同时打也是全 200——Cloudflare 只按 UA 拦，不按并发限流。
2. **分段加载状态**：`PanelStore.Section` 逐段记录「拿到过没有」，页面只关心自己那一段。
   早先用一个全局 `isFirstLoad`，结果某个接口卡 30 秒（服务端等设备回执时会挂住），
   所有页面都跟着转圈——而这 30 秒里其它数据早就到了。
3. **加载中和真的空要分开说**：`EmptyOrLoading` 在数据没到时显示「正在读取执行记录…」，
   到了才显示「还没有执行记录」。这两句话对用户的意思完全不同。
4. **分页只翻两页**（任务 20 条、定时 10 条），总数按服务端 `total` 显示，
   列表底部注明「仅显示最近 20 条」。手机上无限滚动换来的只是更多次 1.5 秒往返。
5. **单页容错**：第一页失败才算失败，后续页失败就用已拿到的数据，不让整页变空。
6. **前台自动刷新**：`RootView` 每 60 秒跑一次 `refreshLive()`（概览 + 统计 + 设备，
   3 个请求），从后台切回来立刻再拉一次。之前只有下拉才更新，页面放着不动就一直显示旧数据。
7. **切分段就抓新数据**：通信页切到通话/短信/录音时各自刷新一次——
   用户切过来是想看「现在的」，不是几分钟前的缓存。
8. **取消不算错误**：下拉刷新被系统打断时 `URLSession` 抛 `URLError.cancelled`，
   原来会被包成 `APIError.transport` 并弹「已取消，重试」。现在单独映射成
   `CancellationError`，`handle()` 直接忽略；`refreshAll` 也加了 `defer` 复位
   `isRefreshing`，避免卡在「正在读取」。

## 列表：分页与左滑删除

- **一次 20 条**：通话/短信首屏只取第一页，底部给「加载更多 · 还有 N 条」按钮，
  点一次追加一页。不做无限滚动——滚到底自动请求，用户永远不知道自己在等什么。
  翻页时按 id 去重：期间来了新记录，服务端的分页会错位，不去重就会出现重复行。
- **左滑删除**：列表不是 `List`（玻璃卡片 + 按天分组），用不了系统 `.swipeActions`，
  所以自己接了水平拖拽（`SwipeToDelete`）：
  - 短滑停在「删除」按钮上，再点一下才删；
  - 长滑（> 150pt）直接删。
  红色底只出现在「行让出来的空间」里（宽度 = -offset），不给行加不透明背景，
  卡片的玻璃质感不会被破坏。竖直方向的手势仍然交给 `ScrollView`。
- **行里不能包 `Button`**：这是修过的一个真 bug。`Button` 的点击在拖拽抬手时照样会触发，
  于是左滑会顺带打开详情、上下滚动也会莫名进详情页。现在点击交给 `SwipeToDelete` 的
  `onTapGesture` 处理（手指移动超过阈值就不算点击），拖拽和点击各走各的。
- **手势先判方向再接管**：原来的实现每一帧都写 `offset`，竖直滚动时行会跟着手指抖，
  `ScrollView` 也像被卡住。现在第一次移动就锁轴（`axis`），判成竖直就彻底不碰 `offset`。
- **删除是乐观更新**：先本地摘掉、再发请求，失败把行放回原位。
  等网络往返再消失的话，用户划完会有半秒「怎么没反应」的空窗——那半秒就是
  「删除动画卡顿」的主要来源。删除动画只跑一层（列表 `withAnimation` + 行的
  `move(.trailing) + opacity` 过渡），不再自己把行先推到 -420 再删。

## 与真实服务端对齐时踩到的坑

这些是本地 mock 全绿、接上真实服务端才暴露的：

| 现象 | 原因 | 修法 |
| --- | --- | --- |
| 任务记录页永远空 | 并发 8+ 请求整批失败，`drain` 抛错后整页丢弃 | 并发宽度收敛 + 分段加载 + 单页容错 |
| 超时的任务显示「成功」 | 设备把 `{"error":"任务执行超时"}` 写在 `result` 里，`status` 仍是 `done` | `TaskStatus` 除了 `error` 字段也解析 `result` |
| 耗时全显示 `0.0s` | 服务端时间戳精确到秒，同秒完成就是 0 | `duration < 1` 显示「—」（和网页端一致） |
| 录音日期解析不出来 | 真实值可能是 ISO8601 带偏移，也可能是 WebDAV 的 RFC1123 | `Recording.parseDate` 两种都试 |
| 通知渠道列表缺「自定义 POST」 | 它不在 `/notify/channels` 的定义表里，只存在于 settings | 取「定义 ∪ 已启用」并集 |
| 遥测趋势线贴底 | RSSI 恒为 31，min == max 时 min-max 归一化退化成 0 | `Sparkline` 加 `flat` 分支画中线 |
| 概览「已拦截」和另外三个数字口径不一 | 前三个是今日，拦截数原来算全部 | 统一为今日 |
| 设备详情电量/电压全是 0 | `sheet(item:)` 捕获了打开那一刻的快照，overview 回来也不刷新 | 详情页只认 `imei`，数据每次从 store 现取 |

## 本地联调（不需要真机）

`tools/mock_server.py` 是严格照 `server-go-v2` 契约写的本地服务端，
用来在没有设备、没有网络的情况下跑通全部页面：

```bash
python3 tools/mock_server.py --port 9527 --user admin --password admin123
# 登录页填 127.0.0.1:9527 / admin / admin123
```

它带 2 台设备、30 条遥测历史、12 通通话、8 条短信、12 条任务、5 个定时、
6 条屏蔽规则、40 条设备日志、5 个服务端日志，以及 4 个**真实可播的 WAV**
（用 `wave` 合成），`/api/recordings/play` 支持 `Range` 返回 206。

## 信息架构

对齐 `server-go-v2` 的 11 个模块，收敛为 5 个 Tab —— 网页端的侧栏在手机上必须重新分组，
否则 11 个一级入口会让底部栏失去意义。

```
概览   设备健康一屏读完：在线 + 续航、电量、电压/温度/信号、今日计数、24h 趋势、最近事件
       （标题右边跟服务端运行时长）
通信   通话 / 短信 / 录音（三段切换，按天分组）
自动化 任务（18 条指令）/ 定时（可手动执行一次）/ 记录
设备   设备卡片列表 → 详情（遥测网格、身份信息、设为当前、删除）
设置   通知 / 灯光 / 省电 / 录音 / 存储 / 屏蔽 / 日志 / 界面 / 运维
```

指令目录与 `static/js/pages/tasks.js` 的 `TASKS` 一一对应，共 18 条：
查询 5（温度、状态、设备信息、配置、流量）、通信 7（短信、拨号、挂断、DTMF、TTS、呼转、USSD）、
配置与系统 6（写配置、编辑配置、音量、GPIO、切卡、重启）。

## 设计系统

所有令牌集中在 `Design/Theme.swift`，页面里不写魔法数字。

| 类别 | 取值 |
| --- | --- |
| 画布 | `#F2F2F6` / `#08080B`（浅 / 深） |
| 主色 | `#0071E3` / `#0A84FF` |
| 语义色 | 在线 `#30D158`、警告 `#FF9F0A`、危险 `#FF453A`、自动化 `#BF5AF2`、信息 `#64D2FF` |
| 间距 | 4 / 8 / 12 / 16 / 20 / 26 / 34，页面边距 20 |
| 圆角 | chip 13 / tile 18 / card 26 / sheet 34 |
| 字阶 | 30 标题（字距 −0.8）、22 / 17 / 15 / 14 / 12 / 11 |

三条排版规则：

1. **字距随字号走**：大标题收紧（−0.8），小字放开（+0.6），不用一个值套全站。
2. **数字一律等宽**（`monospacedDigit`）：电量、时长、信号每秒都可能变，宽度不能抖。
3. **层级靠字重而非只靠字号**：`15/medium` 与 `15/regular` 的差别足够区分标题和正文。

## 动效决策

按「先问要不要动」的顺序逐项判断，不是先写动画再找理由。

### 1. 哪些不动

| 交互 | 频率 | 决策 |
| --- | --- | --- |
| 切换 Tab | 每天上百次 | **不动画**，只跟系统 TabBar 的默认行为 |
| 列表滚动、按压态 | 高频 | 只做 120ms 的缩放/透明度，不做位移 |
| 状态点（在线/离线） | 常驻 | **不做呼吸灯**。常驻循环运动会持续抢注意力 |
| 数值刷新 | 每分钟 | 不做数字滚动，直接替换 |

### 2. 哪些动，动多久

| 元素 | 曲线 | 时长 / 参数 | 理由 |
| --- | --- | --- | --- |
| 按钮按压 | `easeOut` | 120ms，`scale 0.97` | 按下即反馈，不等抬起 |
| 分段控件指示块 | 弹簧 | `response 0.34 / damping 1.0` | 临界阻尼，不过冲；位移必须跟手 |
| 卡片展开、开关状态 | 弹簧 | `response 0.34 / damping 1.0` | 布局变化，过冲会显得廉价 |
| 录音播放进度 | `linear` | 等于音频时长 | 匀速运动就该用 linear，用弹簧会「一顿一顿」 |
| 控制台追加行 | `easeOut` | 180ms 透明度 | 高频追加，不能有位移 |
| 弹层进出 | 系统手势 | 原生 | 交给系统，保留下拉中断能力 |

**全站没有超过 300ms 的 UI 动画**，也没有任何 `scale(0)` 进场——最小从 `0.96 + opacity 0` 开始。

### 3. 减弱动态效果

`Design/Motion.swift` 用 `.motion(...)` 统一接管：开启「减弱动态效果」后，
所有弹簧自动降级为 180ms 的透明度过渡，位移取消、按压的缩放取消但保留透明度反馈。
减弱动态效果不是「什么都不动」，而是换成不引起前庭不适的等价反馈。

## Liquid Glass 使用规则

- **一层玻璃**：`GlassCard` 是页面唯一允许使用 `glassEffect` 的层级。卡片内部一律用
  `SolidPanel`（半透明实色），避免玻璃叠玻璃导致文字可读性崩塌。
- **有东西可折射**：`AppBackground` 在画布上放了三团静态环境光（蓝 + 状态色 + 底部蓝）。
  玻璃之所以像玻璃，是因为背后有内容；纯黑底上的玻璃只会变成一块黑卡。
- **材质表达层级**：玻璃卡片 = 内容层；TabBar / 弹层 = 系统材质；页面底色 = 最底层。
- **边缘高光**：每块卡片有一道 `0.75pt` 的上亮下暗渐变描边，模拟光打在材料上沿。
- **滚动边缘不画分割线**：内容直接滚到浮动 TabBar 下面，靠系统滚动边缘效果过渡。

## 交互细节

- **按压反馈**：所有可点元素走 `PressableStyle`，`scale 0.97` + 120ms，按下即变。
- **续航跟在在线状态后面**：概览的「在线」胶囊右边跟一枚「续航 18 小时」。
  数据来自 `overview.power.estHours`（服务端按「剩余容量 ÷ 估测电流」算好，
  电池容量和平均电流是用户在网页端配的，客户端不重算）。
  充电时改显示「充电中」——「续航 充电中」这种话不成立。
- **通知状态**：通话/短信每行都带一枚 `notifyStatus` 胶囊，文案与网页端一致
  （已通知 / 通知失败 / 排队中 / 已屏蔽 / 未通知）。正常投递用最轻的样式，
  失败和屏蔽才用重色——否则每条都跳出来，反而盖住真正要看的信息。
- **外观三态**：设置 → 外观与界面 → 自动 / 白天 / 黑夜。
  `Theme` 的颜色本来就是 `Color(light:dark:)` 动态色，切外观不用重设任何颜色；
  偏好存 UserDefaults，根视图读同一个 key 转成 `preferredColorScheme`。
- **主题配色**：蓝 / 紫 / 青 / 绿 / 橙 / 粉六选一，只换主色（按钮、链接、选中态、图表主线），
  **不动**在线/警告/危险这三档语义色——语义色要是能改，红色就不代表危险了。
  `Theme.accent` 是计算属性，背后是 `@Observable` 的 `AccentTheme`：
  视图 body 里访问它就会自动订阅，切换配色整个界面跟着换，不用重启。
- **Tab 图标**：自动化用 `wand.and.stars`（闪电读作「充电/快」，和「定时任务」没关系）；
  通信用 `phone.bubble.left`——原来的「双气泡」符号本身宽一圈，而系统会把 Tab 图标
  统一归一化，改字号没用（试过），只能换符号。
- **服务端已运行时间**：挂在「概览」标题右边，`·` 小点接一枚 `server.rack` 图标和时长，
  **不写「服务端已运行」这几个字**——标题行本来就窄，文案留给图标。
  数据是 `/api/stats/summary` 的 `uptimeSec`（服务端进程启动到现在），
  **不是**设备在线时长——设备掉线重连不影响它，服务端重启也不影响设备。
  `PageHeader` 为此加了 `titleAccessory`（标题与副标题之间那一行，跟标题同基线）。
- **定时任务可手动执行**：定时卡片右下角「▶ 执行任务」，走 `POST /api/schedules/run`，
  执行中变成转圈 + 「执行中」，回执直接落在卡片里（成功绿、失败红，4 秒后自动收起）。
  设备离线时服务端回 `success:false` + 「设备当前离线」，卡片原样显示这句话，
  不用去「记录」里翻。执行完顺带刷新定时列表和记录，`上次` 时间立刻跟着变。
  卡片副标题写「周期 · 设备名」而不是「任务名 · 周期 · 设备名」——
  任务名基本等于卡片标题，重复一遍只会把设备名挤成省略号。
- **账户头像**：设置页账户卡渲染 `settings.brand.avatar`（和网页端「界面设置」同一份数据）。
  服务端存的是字符串，三种形态都支持：图床直链、站内相对路径、旧版 base64。
  `AsyncImage` 只认 http(s)，data URI 会直接失败，所以走自己的加载器 + 首字母兜底 + 内存缓存。
  头像地址在「界面设置」里也能改，保存走 `/api/settings/save` 的 brand 段。
- **指令下发是可见的**：点「下发任务」后控制台立刻出现 `› cmd/imei › task {}`，
  设备回执到了追加 `‹ {json}`，失败/超时给红行。等待过程有内容，而不是一个转圈。
- **录音播放可中断**：再点一次立即停止；进度条是 `AVAudioPlayer` 的真实进度。
  音频必须先用 Bearer 取回 `Data` 再本地播——WebDAV 的地址不能直接丢给播放器。
- **危险操作二次确认**：删除设备用 `confirmationDialog`，并写明「会同时移除通话、短信与任务记录」。
  其他操作不做确认——过度确认会训练用户闭眼点掉。
- **登录页键盘避让**：键盘弹起时品牌区自动收窄（图标 36、标题 22、隐藏副标题），
  保证主按钮不被键盘压住。
- **触觉反馈**：只在「测试通知成功」这类真正有意义的时刻触发，不是每个按钮都震。

## 无障碍

- 颜色全部动态色（浅/深各一套），已在两种外观下截图验证。
- 正文最小 11pt（仅用于辅助标签），主要信息 ≥ 12pt，正文 15pt。
- 弱化文字对比度保持在 4.5:1 以上；玻璃上的文字不用纯灰，用提高对比的次级墨色。
- 所有列表行有 `contentShape(Rectangle())`，扩大点击区。

## 验证（真实服务端）

逐页对照真实数据跑过一遍，实测读数：1 台设备（中国移动，在线）、
电量 53～62%、电压 3.75～3.82 V、温度 30.9～34.3 ℃、RSSI 29～31、
通话 43 条、短信 204 条、录音 18 个、任务 424 条、定时 2 个、屏蔽规则 84 条。

| 验证项 | 结果 |
| --- | --- |
| 登录（地址 + 账号 + 密码） | ✅ 拿到 JWT，进主界面 |
| 记住密码 → 冷启动 | ✅ 直接进主界面；`-login` 时账号/密码/开关都已填好 |
| 概览（遥测 + 24h 趋势 + 今日计数） | ✅ 电压/温度/信号/电量与 curl 一致 |
| 通话 / 短信（按天分组、垃圾标记） | ✅ 垃圾短信带「垃圾」标记 |
| 录音列表 + 播放 | ✅ `/api/recordings/play` 返回 `audio/wav` 3.48s，`AVAudioPlayer` 正常播放 |
| 任务记录（分页、状态、耗时） | ✅ 超时记录标红「失败」，耗时显示「—」 |
| 真实下发 `get_status` | ✅ 回执 `{"net_state":"REGISTERED",...,"voltage":3773}` 并写入记录 |
| 定时任务 | ✅ 2 个，`humanSpec`/下次执行时间与 `scheduler.go` 一致 |
| 设备详情 | ✅ IMEI / SN / ICCID / 固件 / 连续在线时长全部有值 |
| 通知渠道 / 屏蔽规则 / 日志中心 | ✅ 13 个渠道（含自定义 POST）、84 条规则、设备与服务端双日志源 |
| 录音设置（读设备 Lua 配置） | ✅ `get_config` 回读到「接通即录音 / 前置语音提示」 |
| 续航估算 | ✅ 直接展示 `power.estHours`；充电时显示「充电中」而不是「续航 充电中」 |
| 前台自动刷新 | ✅ `-autorefresh 10` 实测每 11 秒触发一次 `refreshLive()` |
| 通话/短信分页 | ✅ 通话首屏 20 条 →「还有 27 条」；短信首屏 20 条 →「还有 184 条」，翻页后 40 条、还剩 164 条（总数 204 对得上） |
| 左滑删除 | ✅ 短滑停在删除按钮、长滑直接删；`-deletetop` 实测删掉 id 130 后**服务端 total 44 → 43**、本地 20 → 19 条 |
| 通知状态 | ✅ 通话/短信每行渲染 `notifyStatus`：已通知 / 通知失败 / 排队中 / 已屏蔽 / 未通知（真实数据里能看到「排队中」） |
| 外观切换 | ✅ 设置 → 外观与界面：自动 / 白天 / 黑夜，切换即时生效并持久化 |
| 主题配色 | ✅ 六色实测（蓝/紫/青/绿/橙/粉），整套界面（TabBar、图标、背景光晕）一起换 |
| 录音删除 | ✅ 左滑出红底垃圾桶，删除走乐观更新；正在播放的那条会先停播 |
| 账户头像 | ✅ 服务端 `brand.avatar` 有值时账户卡正常渲染（图床直链 / 站内相对路径 / base64 三种都支持）；界面设置可改 |
| 服务端运行时间 | ✅ 概览标题右边显示「· 🖥 1 天 1 小时」（只留图标 + 时长），取自 `/api/stats/summary` 的 `uptimeSec` |
| 定时任务手动执行 | ✅ `-runschedule 1` 实测：按钮 → 转圈「执行中」→ 绿色 `{"temp":33.8,"unit":"C"}`，4 秒后收起；把 mock 设备置离线后同一按钮回红色「设备当前离线」 |

## 已知取舍

- **Swift 5 语言模式**：工程用 `SWIFT_VERSION = 5.0`；代码按 Swift 6 时代写法组织
  （值类型优先、`@Observable`、`@MainActor` 隔离、单一状态源）。
- **不做推送**：服务端已有通知渠道，客户端侧 APNs 注册未接（需要真实签名与证书）。
- **不做离线缓存**：冷启动没有本地快照，靠分段加载把「第一屏」压到 5～6 秒。
  下一步要做的话，是把上一份 `Wire` 快照落盘、启动先渲染旧数据。
- **列表靠按钮翻页**：一次 20 条，不自动无限滚动、也不预取下一页。
  用户不点「加载更多」就不会多发请求；更早的记录仍可继续翻，但没人往下翻就不浪费流量。

## 截图

`shots/` 下按页面编号：

| 文件 | 内容 |
| --- | --- |
| `01-overview.png` | 概览（仪表盘 / 快捷操作 / 今日计数 / 趋势） |
| `01b-overview-events.png` | 概览底部（最近事件） |
| `02-calls.png` | 通话记录（按天分组、垃圾标记） |
| `03-sms.png` | 短信记录 |
| `04-recordings.png` | 通话录音（播放器） |
| `05-tasks.png` | 自动化 · 任务（常用指令 + 18 条目录） |
| `06-schedules.png` | 自动化 · 定时 |
| `06b-tasklog.png` | 自动化 · 记录 |
| `07-devices.png` | 设备列表 |
| `08-settings.png` | 设置 |
| `09-runner.png` | 指令执行面板（表单 + 控制台） |
| `10-device-detail.png` | 设备详情 |
| `11-notify.png` | 通知推送 |
| `12-led.png` | 灯光指示 |
| `13-logs.png` | 日志中心 |
| `14-light.png` | 浅色模式 |
| `17-sms-loadmore.png` | 短信底部「加载更多 · 还有 164 条」（已加载 40 / 共 204） |
| `18-swipe-delete.png` | 左滑删除态（红色底与行高对齐、图标居中） |
| `19-notify-calls.png` | 通话列表的通知状态胶囊 |
| `20-notify-sms.png` | 短信列表的通知状态（含「排队中」） |
| `21-appearance-light.png` | 设置 · 外观与界面（白天） |
| `22-overview-light.png` | 浅色模式下的概览 |
| `23-overview-chip.png` | 概览右上角设备胶囊（按内容收窄） |
| `24-appearance-accent.png` | 外观与界面：主题配色六选一（青色选中） |
| `25-recordings-swipe.png` | 通话录音的左滑删除 |
| `26-account-avatar.png` | 设置页账户卡渲染服务端头像 |
| `27-brand-avatar-edit.png` | 界面设置里的头像地址编辑 |
| `28-overview-server-uptime.png` | 概览标题右边「· 🖥 1 天 1 小时」 |
| `29-overview-uptime-light.png` | 浅色模式下同一位置（小点与图标跟标题同基线） |
| `30-schedule-run-ok.png` | 定时卡片「执行任务」成功回执（绿色 `{"temp":33.8,"unit":"C"}`） |
| `31-schedule-run-offline.png` | 定时卡片执行失败（红色「设备当前离线」） |
