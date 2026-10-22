#!/usr/bin/env python3
"""AirPanel v2 本地联调服务端

严格按 server-go-v2 的 routes() / 各 handle 函数的返回结构实现，
用于在没有 Go 工具链、也没有真机的情况下把 iOS 客户端整条链路跑通。

    python3 tools/mock_server.py --port 9527 --user admin --password admin123

只实现契约，不实现业务：定时任务不会真的到点执行，设备指令直接回一份
合理的 JSON。数据形状与真实服务端逐字段对齐，客户端不该能分辨出真假。
"""

from __future__ import annotations

import argparse
import io
import json
import math
import struct
import time
import wave
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

# ---------------------------------------------------------------- 静态数据

NOW = int(time.time())
DAY = 86400
TZ = timezone(timedelta(hours=8))

DEVICES = [
    {
        "imei": "867726030123456",
        "phone": "13800138000",
        "name": "客厅 · Air724",
        "connected": True,
        "lastSeen": NOW - 12,
        "firstSeen": NOW - 96 * DAY,
    },
    {
        "imei": "867726030999888",
        "phone": "13912345678",
        "name": "工作室备用机",
        "connected": False,
        "lastSeen": NOW - 3 * 3600 - 720,
        "firstSeen": NOW - 41 * DAY,
    },
]

TELEMETRY_META = {
    "867726030123456": dict(
        netMode="4G", operator="中国移动", number="13800138000",
        imsi="460001234567890", simSlot="SIM1", iccid="89860012345678901234",
        version="v2.0.6", model="Air724UG", sn="AIR724UG20240512001",
    ),
    "867726030999888": dict(
        netMode="4G", operator="中国联通", number="13912345678",
        imsi="460019876543210", simSlot="SIM2", iccid="89860198765432109876",
        version="v2.0.5", model="Air724UG", sn="AIR724UG20231108007",
    ),
}


def telemetry_history(imei: str, count: int = 30, step: int = 1800):
    meta = TELEMETRY_META[imei]
    out = []
    for i in range(count):
        # 电压缓慢下滑，中间插一段充电
        phase = i / max(1, count - 1)
        voltage = int(4180 - 190 * phase - 12 * math.sin(i * 1.3))
        if 12 <= i <= 16:
            voltage = 4190
        temp = round(31.0 + 3.2 * math.sin(i * 0.7) + 0.8, 1)
        rssi = int(-72 + 12 * math.sin(i * 0.5))
        csq = max(1, min(31, int((rssi + 113) * 31 / 60)))
        out.append({
            "id": 5000 + i,
            "imei": imei,
            "voltage": voltage,
            "temperature": temp,
            "rssi": rssi,
            "rsrp": rssi - 20,
            "csq": csq,
            "netMode": meta["netMode"],
            "operator": meta["operator"],
            "number": meta["number"],
            "imsi": meta["imsi"],
            "simSlot": meta["simSlot"],
            "iccid": meta["iccid"],
            "version": meta["version"],
            "model": meta["model"],
            "sn": meta["sn"],
            "vbus": 12 <= i <= 16,
            "workTime": 3600 * 6 + i * step,
            "createdAt": NOW - (count - 1 - i) * step,
        })
    return out


HISTORY = {d["imei"]: telemetry_history(d["imei"]) for d in DEVICES}

CALL_NUMBERS = [
    ("13800138000", "incoming", "connected", 184),
    ("4001234567", "incoming", "missed", 0),
    ("13912345678", "outgoing", "connected", 62),
    ("106900012345", "incoming", "rejected", 0),
    ("02158881234", "outgoing", "connected", 431),
    ("13800138000", "outgoing", "connected", 96),
    ("4008208820", "incoming", "connected", 27),
    ("15900001111", "incoming", "no_answer", 0),
    ("13800138000", "incoming", "connected", 312),
    ("0085212345678", "incoming", "missed", 0),
    ("13912345678", "outgoing", "cancelled", 0),
    ("4001234567", "incoming", "rejected", 0),
]

CALLS = []
for i, (number, direction, status, duration) in enumerate(CALL_NUMBERS):
    started = NOW - i * 5400 - 900
    spam = 1 if number in ("4001234567", "0085212345678") else 0
    CALLS.append({
        "id": 9000 - i,
        "imei": DEVICES[0]["imei"] if i % 3 else DEVICES[1]["imei"],
        "deviceName": DEVICES[0]["name"] if i % 3 else DEVICES[1]["name"],
        "number": number,
        "direction": direction,
        "status": status,
        "duration": duration,
        "startedAt": started,
        "connectedAt": started + 4 if status == "connected" else 0,
        "endedAt": started + duration if status == "connected" else 0,
        "reason": "",
        "notifyStatus": "blocked" if spam else "sent",
        "spam": spam,
        "spamRule": ("号码 400" if number.startswith("400") else "号码 00852") if spam else "",
    })

SMS_SEED = [
    ("10086", "in", "【中国移动】您本月已使用流量 8.2GB，剩余 12.8GB。", 0, ""),
    ("106900012345", "in", "【XX娱乐城】注册即送888元彩金，点击领取…", 1, "关键字 娱乐城"),
    ("13800138000", "out", "到楼下了，稍等两分钟", 0, ""),
    ("95588", "in", "【工商银行】您尾号 8899 的账户 10 月 21 日支出 128.00 元。", 0, ""),
    ("1065502100", "in", "【发票代开】专业代开各类发票，税点低至 1%，联系电话…", 1, "关键字 发票代开"),
    ("13912345678", "in", "会议改到下午三点，会议室 3B", 0, ""),
    ("10010", "in", "【中国联通】您的套餐将于本月 30 日到期。", 0, ""),
    ("106900098765", "in", "【验证码】您正在登录，验证码 482913，5 分钟内有效。", 0, ""),
]

SMS = []
for i, (number, direction, content, spam, rule) in enumerate(SMS_SEED):
    SMS.append({
        "id": 8000 - i,
        "imei": DEVICES[0]["imei"],
        "deviceName": DEVICES[0]["name"],
        "number": number,
        "direction": direction,
        "content": content,
        "createdAt": NOW - i * 3600 - 600,
        "notifyStatus": "blocked" if spam else "sent",
        "spam": spam,
        "spamRule": rule,
    })

TASKS = []
TASK_SEED = [
    ("get_status", "success", '{"voltage":3987,"temp":34.2,"csq":18,"carrier":"中国移动"}'),
    ("send_sms", "success", '{"sent":true,"segments":1}'),
    ("get_config", "success", '{"bytes":2148}'),
    ("dial_call", "success", '{"dialing":true}'),
    ("set_volume", "success", '{"vol":6}'),
    ("reboot", "success", '{"accepted":true}'),
    ("get_temperature", "success", '{"temp":33.8,"unit":"C"}'),
    ("ussd_query", "success", '{"queued":true}'),
    ("set_gpio", "failed", 'GPIO 1 被占用，写入失败'),
    ("query_traffic", "success", '{"queued":true}'),
    ("get_device_info", "success", '{"imei":"867726030123456","model":"Air724UG","fw":"v2.0.6"}'),
    ("tts_speak", "success", '{"played":true}'),
]
for i, (task, status, result) in enumerate(TASK_SEED):
    created = NOW - i * 2700 - 300
    TASKS.append({
        "taskId": f"t-{1000 - i}",
        "imei": DEVICES[0]["imei"],
        "deviceName": DEVICES[0]["name"],
        "task": task,
        "params": "{}",
        "result": result if status == "success" else "",
        "error": "" if status == "success" else result,
        "status": status,
        "createdAt": created,
        "finishedAt": created + (1 if status == "success" else 30),
    })

SCHEDULES = [
    {"id": 1, "name": "每日重启", "imei": DEVICES[0]["imei"], "deviceName": DEVICES[0]["name"],
     "task": "reboot", "params": "{}",
     "spec": {"type": "daily", "hour": 4, "minute": 0},
     "enabled": True, "createdAt": NOW - 20 * DAY, "lastExecuted": NOW - 6 * 3600},
    {"id": 2, "name": "每小时温度采样", "imei": DEVICES[0]["imei"], "deviceName": DEVICES[0]["name"],
     "task": "get_temperature", "params": "{}",
     "spec": {"type": "interval", "n": 60, "unit": "minute"},
     "enabled": True, "createdAt": NOW - 12 * DAY, "lastExecuted": NOW - 24 * 60},
    {"id": 3, "name": "工作日查流量", "imei": DEVICES[0]["imei"], "deviceName": DEVICES[0]["name"],
     "task": "query_traffic", "params": "{}",
     "spec": {"type": "weekly", "weekday": 1, "hour": 9, "minute": 0},
     "enabled": True, "createdAt": NOW - 8 * DAY, "lastExecuted": NOW - 26 * 3600},
    {"id": 4, "name": "每月话费查询", "imei": DEVICES[0]["imei"], "deviceName": DEVICES[0]["name"],
     "task": "ussd_query", "params": '{"code":"*108#"}',
     "spec": {"type": "monthly", "day": 1, "hour": 10, "minute": 0},
     "enabled": False, "createdAt": NOW - 30 * DAY, "lastExecuted": NOW - 21 * DAY},
    {"id": 5, "name": "夜间静音音量", "imei": DEVICES[1]["imei"], "deviceName": DEVICES[1]["name"],
     "task": "set_volume", "params": '{"vol":"0"}',
     "spec": {"type": "daily", "hour": 23, "minute": 30},
     "enabled": True, "createdAt": NOW - 5 * DAY, "lastExecuted": NOW - 18 * 3600},
]

BLOCK_RULES = [
    {"id": 1, "ruleType": "keyword", "value": "娱乐城", "matchMode": "contains", "source": "builtin",
     "enabled": 1, "note": "内置垃圾短信词库", "createdAt": NOW - 60 * DAY, "updatedAt": NOW - 60 * DAY, "hits": 12},
    {"id": 2, "ruleType": "keyword", "value": "发票代开", "matchMode": "contains", "source": "builtin",
     "enabled": 1, "note": "", "createdAt": NOW - 60 * DAY, "updatedAt": NOW - 60 * DAY, "hits": 7},
    {"id": 3, "ruleType": "keyword", "value": "贷款", "matchMode": "contains", "source": "builtin",
     "enabled": 1, "note": "", "createdAt": NOW - 60 * DAY, "updatedAt": NOW - 60 * DAY, "hits": 3},
    {"id": 4, "ruleType": "keyword", "value": "博彩", "matchMode": "contains", "source": "builtin",
     "enabled": 0, "note": "", "createdAt": NOW - 60 * DAY, "updatedAt": NOW - 60 * DAY, "hits": 0},
    {"id": 5, "ruleType": "number", "value": "400", "matchMode": "prefix", "source": "user",
     "enabled": 1, "note": "400 开头一律不推", "createdAt": NOW - 20 * DAY, "updatedAt": NOW - 20 * DAY, "hits": 5},
    {"id": 6, "ruleType": "number", "value": "00852", "matchMode": "prefix", "source": "user",
     "enabled": 0, "note": "", "createdAt": NOW - 15 * DAY, "updatedAt": NOW - 15 * DAY, "hits": 1},
]

LOG_TYPES = ["telemetry", "call_record", "sms_record", "online", "result", "notify_result"]
DEVICE_LOGS = []
for i in range(40):
    lt = LOG_TYPES[i % len(LOG_TYPES)]
    if lt == "telemetry":
        payload = json.dumps({"voltage": 3980 + i, "temp": 33.4, "csq": 18}, ensure_ascii=False)
    elif lt == "call_record":
        payload = json.dumps({"number": "13800138000", "direction": "incoming",
                              "status": "connected", "duration": 184}, ensure_ascii=False)
    elif lt == "sms_record":
        payload = json.dumps({"number": "10086", "direction": "in", "content": "流量提醒"}, ensure_ascii=False)
    elif lt == "online":
        payload = json.dumps({"imei": DEVICES[0]["imei"], "phone": "13800138000"}, ensure_ascii=False)
    elif lt == "result":
        payload = json.dumps({"taskId": f"t-{1000 - (i % 12)}", "result": {"ok": True}}, ensure_ascii=False)
    else:
        payload = json.dumps({"type": "sms", "number": "106900012345", "status": "failed"}, ensure_ascii=False)
    DEVICE_LOGS.append({
        "id": 7000 - i,
        "imei": DEVICES[0]["imei"],
        "deviceName": DEVICES[0]["name"],
        "topic": f"device/{DEVICES[0]['imei']}/up",
        "logType": lt,
        "payload": payload,
        "createdAt": NOW - i * 900,
    })

SERVER_LOGS = [
    {"time": NOW - 900, "level": "info", "msg": "定时任务调度器已启动（每 30 秒检查一次，设备离线时静默跳过）"},
    {"time": NOW - 860, "level": "info", "msg": "[MQTT] 设备已上线 imei=867726030123456"},
    {"time": NOW - 600, "level": "warn", "msg": "[定时任务] #5 命中周期但设备离线，已跳过（每天 23 点 30 分）"},
    {"time": NOW - 420, "level": "error", "msg": "播放录音失败 13800138000_20261020142210.wav: WebDAV 返回 404"},
    {"time": NOW - 300, "level": "info", "msg": "[MQTT] 收到 telemetry，已入库"},
]

SETTINGS = {
    "username": "admin",
    "notifyEnabled": True,
    "notifyChannels": ["bark", "serverchan"],
    "notifyConfig": {
        "bark": {"api": "https://api.day.app/XXXXXXXX", "title": "AirPanel"},
        "serverchan": {"api": "https://sctapi.ftqq.com/SCTxxxx.send", "title": "AirPanel"},
    },
    "smsLed": {"enabled": True, "color": "green", "blink": True, "duration": 5000},
    "callLed": {"enabled": True, "color": "blue", "blink": True, "duration": 5000},
    "webdav": {"url": "https://web.oaife.com", "username": "oaife",
               "password": "secret", "dir": "通话录音"},
    "brand": {"title": "AirPanel", "logo": "", "avatar": ""},
}

NOTIFY_CHANNELS = [
    {"name": "bark", "label": "Bark", "fields": [
        {"key": "api", "label": "推送地址", "type": "text", "placeholder": "https://api.day.app/KEY", "required": True},
        {"key": "title", "label": "消息标题", "type": "text", "placeholder": "可选"},
    ]},
    {"name": "serverchan", "label": "Server酱", "fields": [
        {"key": "api", "label": "SendKey 地址", "type": "text", "required": True},
        {"key": "title", "label": "消息标题", "type": "text", "required": True},
    ]},
    {"name": "dingtalk", "label": "钉钉", "fields": [
        {"key": "webhook", "label": "Webhook 地址", "type": "text", "required": True},
    ]},
    {"name": "message-pusher", "label": "Message-Pusher", "fields": [
        {"key": "api", "label": "服务地址", "type": "text", "required": True},
        {"key": "username", "label": "用户名", "type": "text", "required": True},
        {"key": "token", "label": "令牌", "type": "password"},
    ]},
    {"name": "telegram", "label": "Telegram", "fields": [
        {"key": "token", "label": "Bot Token", "type": "password", "required": True},
        {"key": "chat_id", "label": "Chat ID", "type": "text", "required": True},
    ]},
]

RECORDINGS = [
    {"name": "13800138000_20261020142210.wav", "size": 184320, "duration": 24},
    {"name": "13912345678_20261019181005.wav", "size": 96256, "duration": 12},
    {"name": "4008208820_20261018093012.wav", "size": 43008, "duration": 6},
    {"name": "13800138000_20261017081544.wav", "size": 251904, "duration": 33},
]


def wav_bytes(seconds: int) -> bytes:
    """生成一段可播放的音频，让客户端能真的听到声音并验证进度条"""
    rate = 8000
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = bytearray()
        total = rate * seconds
        for i in range(total):
            # 两个音交替，音量随包络衰减，听感上像提示音
            freq = 440 if (i // (rate // 2)) % 2 == 0 else 660
            env = 0.35 * (1 - (i % rate) / rate)
            frames += struct.pack("<h", int(32767 * env * math.sin(2 * math.pi * freq * i / rate)))
        w.writeframes(bytes(frames))
    return buf.getvalue()


WAV_CACHE = {r["name"]: wav_bytes(r["duration"]) for r in RECORDINGS}


def recording_entry(rec):
    ts = datetime.strptime(rec["name"].split("_")[1].split(".")[0], "%Y%m%d%H%M%S").replace(tzinfo=TZ)
    return {
        "name": rec["name"],
        "size": len(WAV_CACHE[rec["name"]]),
        "modTime": ts.strftime("%a, %d %b %Y %H:%M:%S GMT"),
        "url": "/api/recordings/play?file=" + rec["name"],
    }


# ---------------------------------------------------------------- 服务端

class State:
    def __init__(self, user: str, password: str):
        self.user = user
        self.password = password
        self.token = "mock-token-" + user
        self.start = time.time()
        self.settings = json.loads(json.dumps(SETTINGS))
        self.settings["username"] = user
        self.devices = json.loads(json.dumps(DEVICES))
        self.calls = json.loads(json.dumps(CALLS))
        self.sms = json.loads(json.dumps(SMS))
        self.tasks = json.loads(json.dumps(TASKS))
        self.schedules = json.loads(json.dumps(SCHEDULES))
        self.rules = json.loads(json.dumps(BLOCK_RULES))
        self.logs = json.loads(json.dumps(DEVICE_LOGS))


class Handler(BaseHTTPRequestHandler):
    state: State

    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # 安静一点
        pass

    # -------------------------------------------------- 工具

    def json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def raw(self, code, body: bytes, ctype="application/octet-stream", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except json.JSONDecodeError:
            return {}

    def authed(self):
        h = self.headers.get("Authorization", "")
        if not h.startswith("Bearer ") or h[7:] != self.state.token:
            self.json(401, {"message": "无效的认证令牌"})
            return False
        return True

    def paged(self, items, q, key):
        page = int((q.get("page") or ["1"])[0] or 1)
        size = int((q.get("pageSize") or q.get("size") or ["10"])[0] or 10)
        total = len(items)
        chunk = items[(page - 1) * size: page * size]
        return {key: chunk, "total": total, "page": page, "pageSize": size}

    # -------------------------------------------------- 路由

    def do_GET(self):
        u = urlparse(self.path)
        p, q = u.path, parse_qs(u.query)

        if p == "/api/health":
            return self.json(200, {"ok": True, "version": "v2",
                                   "uptimeSec": int(time.time() - self.state.start)})

        if not self.authed():
            return

        if p == "/api/userPool":
            return self.json(200, self.state.devices)

        if p == "/api/device/overview":
            imei = (q.get("imei") or [""])[0]
            return self.overview(imei)

        if p == "/api/stats/summary":
            return self.stats()

        if p == "/api/tasks":
            return self.json(200, self.paged(self.state.tasks, q, "tasks"))

        if p == "/api/schedules":
            return self.json(200, self.paged(self.state.schedules, q, "schedules"))

        if p == "/api/calls":
            return self.json(200, self.paged(self.state.calls, q, "calls"))

        if p == "/api/sms":
            return self.json(200, self.paged(self.state.sms, q, "sms"))

        if p == "/api/logs":
            return self.json(200, self.paged(self.state.logs, q, "logs"))

        if p == "/api/server-logs":
            limit = int((q.get("limit") or ["300"])[0])
            return self.json(200, {"lines": SERVER_LOGS[:limit], "total": len(SERVER_LOGS)})

        if p == "/api/block-rules":
            t = (q.get("type") or [""])[0]
            rules = [r for r in self.state.rules if not t or r["ruleType"] == t]
            return self.json(200, {"rules": rules, "total": len(rules)})

        if p == "/api/settings":
            return self.json(200, self.state.settings)

        if p == "/api/notify/channels":
            return self.json(200, NOTIFY_CHANNELS)

        if p == "/api/recordings":
            return self.json(200, {"success": True,
                                   "files": [recording_entry(r) for r in RECORDINGS]})

        if p == "/api/recordings/play":
            name = (q.get("file") or [""])[0]
            if name not in WAV_CACHE:
                return self.raw(404, b"not found", "text/plain")
            data = WAV_CACHE[name]
            rng = self.headers.get("Range")
            if rng and rng.startswith("bytes="):
                start = int(rng[6:].split("-")[0] or 0)
                chunk = data[start:]
                return self.raw(206, chunk, "audio/wav", {
                    "Content-Range": f"bytes {start}-{len(data) - 1}/{len(data)}",
                    "Accept-Ranges": "bytes",
                })
            return self.raw(200, data, "audio/wav", {"Accept-Ranges": "bytes"})

        return self.json(404, {"message": "not found"})

    def do_POST(self):
        u = urlparse(self.path)
        p = u.path
        b = self.body()

        if p == "/api/login":
            if b.get("username") == self.state.user and b.get("password") == self.state.password:
                return self.json(200, {"token": self.state.token, "username": self.state.user})
            return self.json(401, {"message": "用户名或密码错误"})

        if not self.authed():
            return

        if p == "/api/logout":
            return self.json(200, {"message": "退出登录成功"})

        if p == "/api/device/remark":
            for d in self.state.devices:
                if d["imei"] == b.get("imei"):
                    d["name"] = b.get("name", "")
            return self.json(200, {"success": True, "message": "备注已保存"})

        if p == "/api/device/delete":
            self.state.devices = [d for d in self.state.devices if d["imei"] != b.get("imei")]
            return self.json(200, {"success": True, "message": "设备已删除"})

        if p == "/api/device/overview/config":
            return self.json(200, {"success": True, "message": "保存成功"})

        if p == "/api/executeTask":
            return self.execute(b)

        if p == "/api/tasks/clear":
            self.state.tasks = []
            return self.json(200, {"success": True, "message": "删除成功", "deleted": 12})

        if p == "/api/schedules/toggle":
            for s in self.state.schedules:
                if s["id"] == b.get("id"):
                    s["enabled"] = bool(b.get("enabled"))
            return self.json(200, {"success": True, "message": "状态已更新"})

        if p == "/api/schedules/run":
            # 真服务端是「在任务自己那台设备上执行」，这里照抄：
            # 命中离线设备时才能复现 success:false + 设备当前离线 这条分支。
            sched = next((s for s in self.state.schedules if s["id"] == b.get("id")), None)
            return self.execute({"imei": (sched or {}).get("imei", self.state.devices[0]["imei"]),
                                 "task": (sched or {}).get("task", "get_status")})

        if p == "/api/schedules/delete":
            self.state.schedules = [s for s in self.state.schedules if s["id"] != b.get("id")]
            return self.json(200, {"success": True, "message": "删除成功"})

        if p == "/api/calls/delete":
            self.state.calls = [c for c in self.state.calls if c["id"] != b.get("id")]
            return self.json(200, {"success": True, "message": "删除成功", "deleted": 1})

        if p == "/api/sms/delete":
            self.state.sms = [s for s in self.state.sms if s["id"] != b.get("id")]
            return self.json(200, {"success": True, "message": "删除成功", "deleted": 1})

        if p in ("/api/calls/clear", "/api/sms/clear", "/api/logs/clear", "/api/tasks/clear"):
            return self.json(200, {"success": True, "message": "清理成功", "deleted": 0})

        if p == "/api/server-logs/clear":
            return self.json(200, {"success": True, "message": "日志已清空"})

        if p == "/api/block-rules/add":
            nid = max((r["id"] for r in self.state.rules), default=0) + 1
            self.state.rules.append({
                "id": nid, "ruleType": b.get("ruleType", "keyword"),
                "value": b.get("value", ""), "matchMode": b.get("matchMode", "contains"),
                "source": "user", "enabled": 1, "note": b.get("note", ""),
                "createdAt": int(time.time()), "updatedAt": int(time.time()), "hits": 0,
            })
            return self.json(200, {"success": True, "message": "规则已添加"})

        if p == "/api/block-rules/update":
            for r in self.state.rules:
                if r["id"] == b.get("id"):
                    r["enabled"] = 1 if b.get("enabled") else 0
                    r["value"] = b.get("value", r["value"])
                    r["matchMode"] = b.get("matchMode", r["matchMode"])
                    r["note"] = b.get("note", r["note"])
            return self.json(200, {"success": True, "message": "规则已更新"})

        if p == "/api/block-rules/delete":
            self.state.rules = [r for r in self.state.rules if r["id"] != b.get("id")]
            return self.json(200, {"success": True, "message": "删除成功"})

        if p == "/api/block-rules/reset":
            return self.json(200, {"success": True, "message": "已恢复内置规则"})

        if p == "/api/settings/save":
            for k in ("notifyEnabled", "notifyChannels", "notifyConfig",
                      "smsLed", "callLed", "webdav", "brand"):
                if k in b:
                    self.state.settings[k] = b[k]
            return self.json(200, {"success": True, "message": "设置已保存"})

        if p == "/api/notify/test":
            if not b.get("channels"):
                return self.json(200, {"success": False, "message": "请先选择至少一个通知渠道"})
            return self.json(200, {"success": True, "message": "测试通知已发送"})

        if p == "/api/recordings/delete":
            return self.json(200, {"success": True, "message": "已删除"})

        if p == "/api/restart":
            return self.json(200, {"success": True, "message": "正在重启服务端，请稍候…"})

        if p == "/api/change-user-info":
            return self.json(200, {"success": True, "message": "用户信息修改成功",
                                   "username": self.state.user, "needRelogin": False})

        return self.json(404, {"message": "not found"})

    # -------------------------------------------------- 业务片段

    def overview(self, imei):
        dev = next((d for d in self.state.devices if d["imei"] == imei), None)
        if dev is None:
            return self.json(200, {"device": None, "connectedAt": 0, "onlineSeconds": 0,
                                   "latest": None, "history": None,
                                   "battery": {"mah": 1800, "percent": 0, "voltage": 0, "charging": False},
                                   "power": {"currentMa": 60, "estHours": 0, "avgCurrentMa": 0}})
        hist = HISTORY.get(imei, [])
        latest = hist[-1] if hist else None
        percent = voltage_percent(latest["voltage"]) if latest else 0
        charging = bool(latest["vbus"]) if latest else False
        current = 30 if charging else 60
        est = (1800 * percent / 100) / current if percent else 0
        connected_at = NOW - 6 * 3600 if dev["connected"] else 0
        return self.json(200, {
            "device": dev,
            "connectedAt": connected_at,
            "onlineSeconds": (NOW - connected_at) if dev["connected"] else 0,
            "latest": latest,
            "history": hist,
            "battery": {"mah": 1800, "percent": percent,
                        "voltage": latest["voltage"] if latest else 0, "charging": charging},
            "power": {"currentMa": current, "estHours": round(est, 1), "avgCurrentMa": 0},
        })

    def stats(self):
        day_start = int(datetime.now(TZ).replace(hour=0, minute=0, second=0, microsecond=0).timestamp())
        calls = [c for c in self.state.calls if c["startedAt"] >= day_start]
        sms = [s for s in self.state.sms if s["createdAt"] >= day_start]
        tasks = [t for t in self.state.tasks if t["createdAt"] >= day_start]
        return self.json(200, {
            "devices": len(self.state.devices),
            "online": sum(1 for d in self.state.devices if d["connected"]),
            "callsToday": len(calls),
            "callIn": sum(1 for c in calls if c["direction"] == "incoming"),
            "callOut": sum(1 for c in calls if c["direction"] == "outgoing"),
            "callMissed": sum(1 for c in calls if c["status"] == "missed"),
            "smsToday": len(sms),
            "smsIn": sum(1 for s in sms if s["direction"] == "in"),
            "smsOut": sum(1 for s in sms if s["direction"] == "out"),
            "tasksToday": len(tasks),
            "tasksOK": sum(1 for t in tasks if t["status"] == "success"),
            "tasksFailed": sum(1 for t in tasks if t["status"] == "failed"),
            "uptimeSec": int(time.time() - self.state.start),
        })

    def execute(self, b):
        imei = b.get("imei", "")
        task = b.get("task", "")
        if not imei or not task:
            return self.json(400, {"success": False, "message": "缺少必要参数"})
        if not any(d["imei"] == imei and d["connected"] for d in self.state.devices):
            return self.json(200, {"success": False, "message": "设备当前离线"})

        result = {
            "get_status": {"voltage": 3987, "temp": 34.2, "csq": 18, "carrier": "中国移动"},
            "get_temperature": {"temp": 33.8, "unit": "C"},
            "get_device_info": {"imei": imei, "model": "Air724UG", "fw": "v2.0.6"},
            "get_config": {"content": "RECORD_ENABLE = true\nTTS_BEFORE_ENABLE = true\n"
                                      "POWERSAVE_ENABLE = false\nPOWERSAVE_START_HOUR = 1\n"
                                      "POWERSAVE_END_HOUR = 8\nVOLUME = 6\n"},
            "set_config": {"ok": True},
            "send_sms": {"sent": True, "segments": 1},
            "dial_call": {"dialing": True},
            "reboot": {"accepted": True},
        }.get(task, {"ok": True})

        created = int(time.time())
        self.state.tasks.insert(0, {
            "taskId": f"t-{created}", "imei": imei,
            "deviceName": next((d["name"] for d in self.state.devices if d["imei"] == imei), ""),
            "task": task, "params": json.dumps({k: v for k, v in b.items() if k not in ("imei", "task")},
                                               ensure_ascii=False),
            "result": json.dumps(result, ensure_ascii=False), "error": "",
            "status": "success", "createdAt": created, "finishedAt": created + 1,
        })
        return self.json(200, {"success": True, "result": result})


def voltage_percent(mv: int) -> int:
    v = mv / 1000
    if mv <= 0 or v <= 3.30:
        return 0
    if v >= 4.20:
        return 100
    if v <= 3.60:
        return int((v - 3.30) / 0.30 * 30 + 0.5)
    if v <= 3.80:
        return int((v - 3.60) / 0.20 * 30 + 30 + 0.5)
    if v <= 4.05:
        return int((v - 3.80) / 0.25 * 25 + 60 + 0.5)
    return int((v - 4.05) / 0.15 * 15 + 85 + 0.5)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=9527)
    ap.add_argument("--user", default="admin")
    ap.add_argument("--password", default="admin123")
    args = ap.parse_args()

    Handler.state = State(args.user, args.password)
    srv = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"AirPanel mock server on http://0.0.0.0:{args.port}  "
          f"user={args.user} password={args.password}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
