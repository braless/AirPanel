module(...)

-------------------------------------------------- 功能及使用说明 --------------------------------------------------

-- 本项目支持外接扬声器和麦克风, 可以实现接打电话等功能, 推荐连接后使用

-- 连接扬声器后, 可以通过短按/双击/长按 POWERKEY 来切换选择菜单项
-- 菜单项包含: 扬声器音量/通话音量/麦克音量/回拨电话/测试通知/网卡/短信播报/历史短信/来电动作/开机通知/查询流量/查询温度/查询时间/查询信号/查询内存/查询电压/状态指示灯/切换卡槽/重启/关机
-- 连接扬声器后, 可以播放: 通知发送成功提示音/来电铃声/通话外放声/短信验证码/短信内容
-- 来电动作配置为无操作时, 如果来电话, 可以通过短按/长按 POWERKEY 来手动接听/挂断电话

-- 支持虚拟U盘来存储历史短信, 需要使用 core 目录下的底层固件

-- 下面配置文件编辑时注意删除注释 (两个短横杠--是lua的注释), 推荐使用 VSCode 代码编辑器

-------------------------------------------------- 通知相关配置 --------------------------------------------------

-- 通知类型, 支持配置多个
-- NOTIFY_TYPE = { "custom_post", "telegram", "pushdeer", "bark", "dingtalk", "feishu", "wecom", "pushover", "inotify", "next-smtp-proxy", "gotify", "serverchan", "message-pusher" }
NOTIFY_TYPE = { "message-pusher", "bark","custom_post" }

-- custom_post 通知配置, 自定义 POST 请求
-- CUSTOM_POST_CONTENT_TYPE 支持 application/x-www-form-urlencoded 和 application/json
-- CUSTOM_POST_BODY_TABLE 中的 {msg} 会被替换为通知内容
CUSTOM_POST_URL = ""
CUSTOM_POST_CONTENT_TYPE = "application/json"
CUSTOM_POST_BODY_TABLE = { ["title"] = "这里是标题", ["text"] = "{msg}" }

-- telegram 通知配置, https://github.com/0wQ/telegram-notify 或者自行反代
-- TELEGRAM_API = "https://api.telegram.org/bot{token}/sendMessage"
-- TELEGRAM_CHAT_ID = ""

-- pushdeer 通知配置, https://www.pushdeer.com/
-- PUSHDEER_API = "https://api2.pushdeer.com/message/push"
-- PUSHDEER_KEY = ""

-- bark 通知配置, https://github.com/Finb/Bark
BARK_API = "https://api.day.app"
BARK_KEY = ""
-- bark 主标题 (支持 {msg} 占位符, 留空则使用默认标题"来自 Air724UG 的通知")
BARK_TITLE = "中国移动"
-- bark 通知内容 (支持 {msg} 占位符, 留空则使用原始通知消息)
BARK_CONTENT = "{msg}"
-- bark 推送图标 (图标 URL, 留空则使用 Bark 默认图标)
BARK_ICON = "https://i.postimg.cc/DZ6PBynW/IMG-0171.png"
-- bark 消息分组 (iOS 通知中心按此分组展示, 默认 "汉中移动")
BARK_GROUP = "中国移动"
-- bark 推送声音 (Bark 内置声音名, 默认 "glass")
BARK_SOUND = "glass"
-- bark 设备事件标题 (设备事件如 #BOOT_软件重启(3) 等以 # 开头的消息, 标题固定为该值, 默认 "设备事件")
BARK_EVENT_TITLE = "设备事件"
-- bark 设备事件图标 (独立于普通通知图标的 URL, 用于设备事件推送)
BARK_EVENT_ICON = "https://i.postimg.cc/s2m0ryT5/IMG-6281.png"

-- dingtalk 通知配置, https://open.dingtalk.com/document/robots/custom-robot-access
-- 自定义关键词方式可填写 ":" "#" "号码"
-- 如果是加签方式, 请填写 DINGTALK_SECRET, 否则留空为自定义关键词方式, https://open.dingtalk.com/document/robots/customize-robot-security-settings
-- DINGTALK_WEBHOOK = "https://oapi.dingtalk.com/robot/send?access_token=xxx"
-- DINGTALK_SECRET = ""

-- feishu 通知配置, https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN
-- FEISHU_WEBHOOK = "https://open.feishu.cn/open-apis/bot/v2/hook/xxx"

-- wecom 通知配置, https://developer.work.weixin.qq.com/document/path/91770
-- WECOM_WEBHOOK = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"

-- pushover 通知配置, https://pushover.net/api
-- PUSHOVER_API_TOKEN = ""
-- PUSHOVER_USER_KEY = ""

-- inotify 通知配置, https://github.com/xpnas/Inotify 或者使用合宙提供的 https://push.luatos.org
-- INOTIFY_API = "https://push.luatos.org/xxx.send"

-- next-smtp-proxy 通知配置, https://github.com/0wQ/next-smtp-proxy
-- NEXT_SMTP_PROXY_API = ""
-- NEXT_SMTP_PROXY_USER = ""
-- NEXT_SMTP_PROXY_PASSWORD = ""
-- NEXT_SMTP_PROXY_HOST = "smtp-mail.outlook.com"
-- NEXT_SMTP_PROXY_PORT = 587
-- NEXT_SMTP_PROXY_FORM_NAME = "Air724UG"
-- NEXT_SMTP_PROXY_TO_EMAIL = ""
-- NEXT_SMTP_PROXY_SUBJECT = "来自 Air724UG 的通知"

-- gotify 通知配置, https://gotify.net/
-- GOTIFY_API = "http://127.0.0.1:8080"
--GOTIFY_API = ""
-- gotify 标题
--GOTIFY_TITLE = "转发器"
--GOTIFY_PRIORITY = 8
-- gotify token为创建的apps的token(需注意，需在gotify上创建一个名为"sms"的app)
--GOTIFY_TOKEN = ""
-- gotify 客户端token(即为配置好的client的token)
--GOTIFY_CLIENT_TOKEN=""

-- message-pusher 通知配置, https://github.com/vipxkw/message-pusher
-- 部署后通过 {服务端}/push/{用户名} 接口发送, description 为必填字段
-- MESSAGE_PUSHER_API = "https://push.example.com"   -- 服务端地址(自建则填 http://IP:3000)
-- MESSAGE_PUSHER_USERNAME = "your-username"         -- 推送用户名
-- MESSAGE_PUSHER_TOKEN = ""                         -- 后台若设置了推送 token 则必填, 否则留空
-- MESSAGE_PUSHER_CHANNEL = "wechat"                 -- 指定推送通道类型(如 lark/telegram/bark/ding/corp...), 留空使用后台默认通道
-- MESSAGE_PUSHER_TITLE = "来自 Air724UG 的通知"     -- 标题(选填)

-------------------------------------------------- 服务端 MQTT 对接配置 --------------------------------------------------

-- 通过 MQTT 对接自建服务端（Go 服务端内置 broker），替代原 WebSocket 方式以节省流量
-- ==================== 推荐：单链接配置 MQTT_URL ====================
-- 直接填写一条链接即可，支持以下格式（任选其一）：
--   MQTT_URL = "wss://panel.example.com/websocket"  -- 加密 WebSocket（推荐，nginx 反代 443 到面板端口）
--   MQTT_URL = "ws://192.168.1.100:9527/websocket"  -- 明文 WebSocket（直接连面板端口）
--   MQTT_URL = "mqtt://panel.example.com:1883"      -- MQTT 明文（需服务端 config.json 中 mqtt.port > 0）
--   MQTT_URL = "mqtts://panel.example.com:8883"     -- MQTT over TLS
MQTT_URL = "ws://panel.example.com/websocket"
-- ==================== 旧参数（MQTT_URL 留空时才生效） ====================
-- MQTT_HOST 填写服务端地址，例如 "192.168.1.100" 或 "panel.example.com"
MQTT_HOST = ""
-- MQTT 端口，默认 1883
MQTT_PORT = 1883
-- 心跳间隔（秒），默认 30 秒。经 nginx 反代时需小于其 proxy_read_timeout（默认 60s），
-- 否则空闲连接会被反代掐断导致任务下发超时；每次心跳仅 2 字节，流量开销极小
MQTT_KEEPALIVE = 30
-- 客户端 ID，留空自动使用 IMEI
MQTT_CLIENT_ID = ""
-- 服务端若启用了 MQTT 认证则填写，否则留空
MQTT_USERNAME = ""
MQTT_PASSWORD = ""
-- 应用心跳间隔（毫秒），默认 2 分钟。设备周期上报 online 主题，供服务端离线判定
-- （建议 ≤ 服务端"离线判定超时"的一半，防止网络抖动被误判离线）
HEARTBEAT_INTERVAL = 120000
-- 遥测上报间隔（毫秒），默认 60 秒。设备周期上报电压/信号/温度/网络等，供服务端概览留存
TELEMETRY_INTERVAL = 60000

-------------------------------------------------- 省电模式配置 --------------------------------------------------

-- 省电模式开关，false 关闭。开启后设备在设定的时段内进入低功耗状态以降低待机功耗
POWERSAVE_ENABLE = false
-- 省电开始小时（0-23），默认 1 点
POWERSAVE_START_HOUR = 1
-- 省电结束小时（0-23），默认 8 点。支持跨天（如开始 22 结束 8 表示 22 点至次日 8 点）
POWERSAVE_END_HOUR = 8
-- 省电档位：false=半在线（保持 MQTT 在线，仅停周期任务/关灯/拉长心跳，接收短信来电不丢失）；
-- true=彻底离线深睡（进入飞行模式断网，射频全关最省电，但夜间失联，短信存 SIM 卡醒来补收，来电会丢失）
POWERSAVE_DEEP = false
-- 半在线时应用心跳间隔（毫秒），默认 10 分钟。省电期间拉长心跳降低唤醒频率，供服务端离线判定
POWERSAVE_HEARTBEAT = 600000
-- 省电期间遥测上报间隔（毫秒），0 表示省电时暂停遥测上报
POWERSAVE_TELEMETRY = 0

-- 连接看门狗（毫秒），默认 15 分钟。持续该时长未能连上服务端则自动重启模块自愈
-- （兜底防止 socket 通道耗尽/网络栈异常导致设备再也连不上、只能人工断电），0 关闭
MQTT_REBOOT_TIMEOUT = 900000
-- 假死看门狗（毫秒），默认 5 分钟。MQTT 主循环超过该时长无任何响应（卡死在某个
-- 永不返回的阻塞调用中）则自动重启模块自愈，0 关闭
MQTT_STUCK_TIMEOUT = 300000

-- serverchan 通知配置
-- SERVERCHAN_TITLE = "来自 Air724UG 的通知"
-- SERVERCHAN_API = ""

-- 定时查询流量间隔, 单位毫秒, 设置为 0 关闭 (建议检查 util_mobile.lua 文件中运营商号码和查询流量代码是否正确, 以免发错短信导致扣费)
QUERY_TRAFFIC_INTERVAL = 0

-- 开机通知
BOOT_NOTIFY = true

-- 通知内容追加更多信息
NOTIFY_APPEND_MORE_INFO = true

-- 通知最大重发次数
NOTIFY_RETRY_MAX = 100

-------------------------------------------------- 短信来电配置 --------------------------------------------------

-- 允许发短信控制设备的号码, 如果注释掉或者为空, 则禁止所有号码, 短信格式示例:
-- 拨打电话 CALL,10086
-- 发送短信 SMS,10086,查询流量
-- 查询所有呼转状态 CCFC,?
-- 设置无条件呼转 CCFC,18888888888
-- 关闭所有呼转 CCFC,18888888888
-- 切换卡槽优先级 SIMSWITCH
-- SMS_CONTROL_WHITELIST_NUMBERS = { "18xxxxxxx", "18xxxxxxx", "18xxxxxxx" }
SMS_CONTROL_WHITELIST_NUMBERS = {}  

-- 扬声器 TTS 播放短信内容, 0:关闭(默认), 1:仅验证码, 2:全部
SMS_TTS = 0

-- 电话接通后 TTS 语音内容, 在播放完后开始录音, 如果注释掉或者为空则播放 audio_pickup_record.amr 或 audio_pickup_hangup.amr 文件
TTS_TEXT = "您好,本号码已启用托管,请听到滴声后留言,嘀嘀嘀,嘀嘀嘀"  -- 您好,本号码已启用托管,您的来电已被记录，机主核实后会联系您! 感谢您的来电! 再见
-- 自定义前置音频：在播放 TTS_TEXT 之前先播放该音频文件（位于 script/audio 目录，Luatools 平铺到设备 /lua 根目录），留空则直接播放 TTS
-- 注意：Air724UG 的 mp3 解码要求码率 >=64kbps（体积大），来电场景请使用 AMR 文件（如 /lua/audio_greeting.amr），走 audioStream 播放最稳定
TTS_BEFORE_MP3 = "/lua/audio_greeting.amr"

-- 来电动作, 0:无操作, 1:自动接听(默认), 2:挂断, 3:自动接听后挂断, 4:等待30秒后自动接听
-- 无操作 / 等待30秒后自动接听, 可以长按 POWERKEY 来手动接听挂断电话
CALL_IN_ACTION = 1

-------------------------------------------------- 其他配置 --------------------------------------------------

-- 扬声器音量, 0-7
AUDIO_VOLUME = 1

-- 通话音量 0-7
CALL_VOLUME = 0

-- 麦克音量 0-7
MIC_VOLUME = 7

-- 开启 RNDIS 网卡
RNDIS_ENABLE = false

-- 状态指示灯开关
LED_ENABLE = true

-- SIM 卡 pin 码
PIN_CODE = ""

-- ============================================================
-- 本文件为公开模板（已脱敏）。真实运行配置（Bark Key、MQTT 地址、
-- WebDAV、个人密钥等）由本地 config.lua 自行维护，不入库、不上传。
-- 说明：BARK_KEY / 服务器地址等敏感项在本模板中留空或为示例值。
-- ============================================================
