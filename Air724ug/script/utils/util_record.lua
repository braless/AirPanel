-- 通话记录 / 短信记录 上报模块
-- 依赖 util_mqtt.report()：记录只入队，由 MQTT 主循环统一串行发布到服务端，避免并发写 socket。
--
-- 上报主题约定（与服务端保持一致）：
--   通话记录: device/{imei}/call_record
--   短信记录: device/{imei}/sms_record
--
-- 通话记录通过订阅 CALL_INCOMING / CALL_CONNECTED / CALL_DISCONNECTED 事件生成：
--   - 来电（incoming）：收到 CALL_INCOMING 记为来电；接通则状态 connected，未接通按挂断原因记为 missed（未接）或 rejected（拒接）
--   - 去电（outgoing）：调用 cc.dial 前需先调 markOutgoingStart() 记录起点；接通经 CALL_CONNECTED 更新，未接通记为 no_answer（未应答）
local util_mqtt = require "util_mqtt"
local sys = require "sys"
local log = require "log"
local misc = require "misc"

-- 当前活跃通话表：number -> {direction=incoming|outgoing, startAt, connectAt}
local active = {}

-- 最近一次上报的通话键（供通知结果回填匹配服务端记录）
local lastCallKey = { number = "", startedAt = 0 }

-- 上报一条通话记录
-- notifyStatus: '' 未通知 / queued 排队中 / blocked 被屏蔽（设备端判断）
local function reportCall(number, direction, status, duration, startedAt, connectedAt, endedAt, reason, notifyStatus)
    util_mqtt.report("device/" .. misc.getImei() .. "/call_record", {
        number = number or "",
        direction = direction,
        status = status,
        duration = duration or 0,
        startedAt = startedAt or 0,
        connectedAt = connectedAt or 0,
        endedAt = endedAt or 0,
        reason = reason or "",
        notifyStatus = notifyStatus or ""
    })
    lastCallKey = { number = number or "", startedAt = startedAt or 0 }
    log.info("util_record", "上报通话记录", number, direction, status, duration, "秒", "通知状态:", notifyStatus or "")
end

-- 获取最近一次上报的通话键（通知结果回填用）
local function getLastCallKey()
    return lastCallKey.number, lastCallKey.startedAt
end

-- 来电
sys.subscribe("CALL_INCOMING", function(num)
    num = num or "unknown"
    -- 同一号码可能多次触发 CALL_INCOMING（状态轮询去重），保留最早起点
    if not active[num] then
        active[num] = { direction = "incoming", startAt = os.time(), connectAt = 0 }
    end
end)

-- 通话接通（来电接听 或 去电接通）
sys.subscribe("CALL_CONNECTED", function(num)
    num = num or "unknown"
    local now = os.time()
    if active[num] then
        if active[num].connectAt == 0 then
            active[num].connectAt = now
        end
    else
        -- 无来电记录（设备主叫被接通），视为去电
        active[num] = { direction = "outgoing", startAt = now, connectAt = now }
    end
end)

-- 通话挂断：为活跃通话生成记录并上报
sys.subscribe("CALL_DISCONNECTED", function(reason)
    local endedAt = os.time()
    reason = reason or ""
    local numbers = {}
    for num in pairs(active) do
        numbers[#numbers + 1] = num
    end
    for _, num in ipairs(numbers) do
        local c = active[num]
        if c then
            active[num] = nil
            local startAt = c.startAt or endedAt
            local connectAt = c.connectAt or 0
            local status, duration
            if connectAt > 0 then
                status = "connected"
                duration = math.max(0, endedAt - connectAt)
            elseif c.direction == "incoming" then
                -- 来电未接通：主动挂断视为拒接，否则视为未接
                status = (reason == "CHUP" and "rejected") or "missed"
                duration = 0
            else
                status = "no_answer"
                duration = 0
            end
            -- 来电记录初始通知状态：命中屏蔽=blocked，否则排队中（由通知回调回填 sent/failed）
            local notifyStatus = ""
            if c.direction == "incoming" then
                local util_block = require "util_block"
                notifyStatus = util_block.isBlockedCall(num) and "blocked" or "queued"
            end
            reportCall(num, c.direction, status, duration, startAt, connectAt, endedAt, reason, notifyStatus)
        end
    end
end)

-- 去电起点标记：调用 cc.dial 拨号前调用，保证未接通（未应答/忙）也能生成去电记录
function markOutgoingStart(num)
    if num == nil or num == "" then
        return
    end
    if not active[num] then
        active[num] = { direction = "outgoing", startAt = os.time(), connectAt = 0 }
    end
end

-- 上报一条短信记录（direction: in 接收 / out 发送）
-- content 传入明文内容（UTF-8），number 为对端号码
-- notifyStatus: '' 未通知 / queued 排队中 / blocked 被屏蔽（设备端判断）
-- time: 记录时间（Unix 秒），缺省 os.time()；与通知结果回填保持一致
function reportSms(direction, number, content, notifyStatus, time)
    util_mqtt.report("device/" .. misc.getImei() .. "/sms_record", {
        number = number or "",
        direction = direction == "out" and "out" or "in",
        content = content or "",
        time = time or os.time(),
        notifyStatus = notifyStatus or ""
    })
    log.info("util_record", "上报短信记录", number, direction, "内容长度:", #(content or ""), "通知状态:", notifyStatus or "")
end

-- 上报通知发送结果（回填服务端记录的通知状态）
-- @param recordType sms / call
-- @param number 对端号码
-- @param time 记录时间键（sms: created_at / call: started_at）
-- @param status sent / failed
function reportNotifyResult(recordType, number, time, status)
    util_mqtt.report("device/" .. misc.getImei() .. "/notify_result", {
        type = recordType,
        number = number or "",
        time = time or 0,
        status = status or "failed"
    })
    log.info("util_record", "上报通知结果", recordType, number, "状态:", status)
end

-- 上报发送短信（供各 sms.send 调用点的回调使用）
-- @param result 发送是否成功（true 才上报）
-- @param number 接收方号码
-- @param content 发送内容原文
function reportSmsOut(result, number, content)
    if result then
        reportSms("out", number, content)
    else
        log.warn("util_record", "短信发送失败，不上报记录", number)
    end
end

return {
    markOutgoingStart = markOutgoingStart,
    reportSms = reportSms,
    reportSmsOut = reportSmsOut,
    reportNotifyResult = reportNotifyResult,
    getLastCallKey = getLastCallKey
}
