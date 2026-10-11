--- 省电模式管理器
-- 在配置的时段内（默认凌晨 1:00-8:00）进入低功耗状态：
--   · 半在线（POWERSAVE_DEEP=false）：停温度/NTP 等周期任务、关闭氛围灯、拉长应用心跳/暂停遥测，
--     保持 MQTT 在线，接收短信/来电不丢失
--   · 深睡（POWERSAVE_DEEP=true）：半在线基础上进入飞行模式断网，射频全关最省电，但夜间失联
-- Air724UG 的 CPU 不休眠（定时器/网络始终运行），pm 仅控制外设供电，故省电通过"降低活动+关射频"实现，
-- 时段检查由 sys 定时器驱动，到点自动退出，不存在"睡死"问题
-- @module util_powersave
module(..., package.seeall)

local sys = require "sys"
local config = require "config"
local util_mqtt = require "util_mqtt"

-- 省电时暂停的定时器注册表：name -> { create=创建函数, id=当前定时器ID(nil 表示已暂停) }
local registry = {}

-- 当前是否处于省电状态
local active = false
-- 当前省电档位（true=深睡离线，false=半在线）
local deep = false
-- 进入省电前备份的配置（退出时恢复）
local savedConfig = {}

--- 注册一个需在省电时暂停的周期定时器
-- @string name 唯一名称（如 "temperature"）
-- @function create 创建函数，返回 sys.timerLoopStart 的 timerId
-- @usage powersave.trackTimer("temperature", function() return sys.timerLoopStart(util_temperature.get, 60000) end)
function trackTimer(name, create)
    registry[name] = { create = create, id = create() }
end

--- 当前是否处于省电状态
function inPowerSave()
    return active
end

--- 当前是否为深睡（离线）档位
function isDeep()
    return deep
end

-- 判定小时 hour 是否落在 [start, end) 区间（支持跨天，如开始22结束8表示22点至次日8点）
local function inWindow(hour, start, stop)
    start = tonumber(start) or 1
    stop = tonumber(stop) or 8
    if start == stop then return hour == start end
    if start < stop then return hour >= start and hour < stop end
    return hour >= start or hour < stop
end

-- 暂停所有已注册的周期定时器
local function pauseTimers()
    for name, r in pairs(registry) do
        if r.id then
            sys.timerStop(r.id)
            r.id = nil
        end
    end
end

-- 恢复所有已暂停的周期定时器
local function resumeTimers()
    for name, r in pairs(registry) do
        if not r.id then
            r.id = r.create()
        end
    end
end

-- 进入省电
local function enter()
    active = true
    deep = config.POWERSAVE_DEEP == true
    log.info("POWERSAVE", "进入省电模式", deep and "深睡(离线)" or "半在线")

    -- 上报省电状态：服务端据此放宽半在线离线阈值（避免心跳拉长被误判离线）
    pcall(function() util_mqtt.reportPowerSave(true) end)

    -- 暂停温度/NTP 等周期任务（外设随之掉电）
    pauseTimers()

    -- 关闭 RGB 氛围灯
    local ok, led = pcall(require, "led_rgb")
    if ok and led and led.light_off then
        pcall(led.light_off)
    end

    -- 拉长应用心跳、暂停遥测（util_mqtt 主循环每次读取 config，改表即时生效）
    savedConfig.HEARTBEAT_INTERVAL = config.HEARTBEAT_INTERVAL
    savedConfig.TELEMETRY_INTERVAL = config.TELEMETRY_INTERVAL
    config.HEARTBEAT_INTERVAL = tonumber(config.POWERSAVE_HEARTBEAT) or 600000
    config.TELEMETRY_INTERVAL = tonumber(config.POWERSAVE_TELEMETRY) or 0

    if deep then
        -- 深睡：关闭连接看门狗/假死看门狗，防止飞行模式下持续重连触发自动重启；再进飞行模式断网
        savedConfig.MQTT_REBOOT_TIMEOUT = config.MQTT_REBOOT_TIMEOUT
        savedConfig.MQTT_STUCK_TIMEOUT = config.MQTT_STUCK_TIMEOUT
        config.MQTT_REBOOT_TIMEOUT = 0
        config.MQTT_STUCK_TIMEOUT = 0
        pcall(function() require("net").switchFly(true) end)
    end
end

-- 退出省电
local function exit()
    log.info("POWERSAVE", "退出省电模式")

    -- 上报退出省电：服务端恢复该设备常规离线阈值
    pcall(function() util_mqtt.reportPowerSave(false) end)

    if deep then
        -- 先恢复网络再恢复看门狗
        pcall(function() require("net").switchFly(false) end)
        config.MQTT_REBOOT_TIMEOUT = savedConfig.MQTT_REBOOT_TIMEOUT
        config.MQTT_STUCK_TIMEOUT = savedConfig.MQTT_STUCK_TIMEOUT
    end

    -- 恢复心跳/遥测配置（还原为进入前值，未设置则回退 util_mqtt 默认）
    config.HEARTBEAT_INTERVAL = savedConfig.HEARTBEAT_INTERVAL
    config.TELEMETRY_INTERVAL = savedConfig.TELEMETRY_INTERVAL
    savedConfig = {}

    -- 恢复周期任务
    resumeTimers()

    active = false
    deep = false
end

-- 周期性检查并应用省电状态（每 60 秒，Air724UG CPU 常驻运行可保证到点自动切换）
local function check()
    if config.POWERSAVE_ENABLE == false then
        if active then exit() end
        return
    end
    local t = os.date("*t")
    local hour = t and t.hour or 0
    local inW = inWindow(hour, config.POWERSAVE_START_HOUR, config.POWERSAVE_END_HOUR)
    if inW and not active then
        enter()
    elseif not inW and active then
        exit()
    end
end

--- 启动省电模式调度（在 main.lua 调用一次）
function start()
    sys.timerLoopStart(check, 1000 * 60)
    log.info("POWERSAVE", "省电模式调度已启动 时段:", tostring(config.POWERSAVE_START_HOUR), "-", tostring(config.POWERSAVE_END_HOUR))
end
