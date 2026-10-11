--- 模块功能：RGB 三色氛围灯模块（移植自闲鱼作者版，适配 AirPanel）
-- 引脚：GPIO24=红 / GPIO25=绿 / GPIO26=蓝（LDO_VMMC 电压域）
-- 提供：7 色控制、开机动画、霓虹呼吸、断电记忆灯效模式、网络/USB/短信反馈
-- 控制入口：①电源键菜单（handler_powerkey 调用）②服务端 MQTT 任务 set_led（util_mqtt 调用）
-- @module led_rgb
module(..., package.seeall)

require "pins"
require "pmd"

-- ============ 引脚与电压域 ============
local PIN_24 = pio.P0_24 -- 红 (R)
local PIN_25 = pio.P0_25 -- 绿 (G)
local PIN_26 = pio.P0_26 -- 蓝 (B)

-- ============ 运行状态 ============
local current_mode = 1        -- 当前灯效模式 (1~6)
local is_light_off = false    -- 手动关灯标志
local MAX_MODE = 6            -- 灯效模式种类
local is_blue_blinking = false -- 蓝灯闪烁（按键/短信反馈）
local is_usb_lighting = false  -- USB 插入黄灯
local usb_light_timer_id = nil
local network_ok = false      -- 网络/MQTT 是否就绪
local temp_color = nil        -- 临时单色（由 set_led color 动作设置），nil 表示未启用
-- 事件反馈灯效（来短信/来电话，由服务端 set_led feedback 触发）
local fb_color, fb_blink, fb_until = nil, false, 0
local CONFIG_FILE = "/led_mode.config"

-- ============ 基础点亮（每次点亮前先熄灭三脚，防止混色残留） ============
local function pin_off_all()
    pins.setup(PIN_24, nil)
    pins.setup(PIN_25, nil)
    pins.setup(PIN_26, nil)
end

function off()      pin_off_all() end
function red()      pin_off_all() pins.setup(PIN_24, 1) end
function green()    pin_off_all() pins.setup(PIN_25, 1) end
function blue()     pin_off_all() pins.setup(PIN_26, 1) end
function yellow()   pin_off_all() pins.setup(PIN_24, 1) pins.setup(PIN_25, 1) end
function purple()   pin_off_all() pins.setup(PIN_24, 1) pins.setup(PIN_26, 1) end
function cyan()     pin_off_all() pins.setup(PIN_25, 1) pins.setup(PIN_26, 1) end
function white()    pin_off_all() pins.setup(PIN_24, 1) pins.setup(PIN_25, 1) pins.setup(PIN_26, 1) end

-- 颜色名 -> 渲染函数映射
local COLOR_FN = {
    off = off, red = red, green = green, blue = blue,
    yellow = yellow, purple = purple, cyan = cyan, white = white,
}

-- ============ 动画 ============
-- 开机/关机白光轮转动画
function white_anim(ms)
    local count = math.floor((ms or 600) / 6)
    for _ = 1, count do
        red() sys.wait(2) green() sys.wait(2) blue() sys.wait(2)
    end
    off()
end

-- 霓虹三色渐变/呼吸（软件 PWM）
function neon_breath()
    for i = 1, 15 do red()   sys.wait(16 - i) green() sys.wait(i) end
    for i = 1, 15 do green() sys.wait(16 - i) blue()  sys.wait(i) end
    for i = 1, 15 do blue()  sys.wait(16 - i) red()   sys.wait(i) end
end

-- ============ 断电记忆 ============
local function load_mode()
    local f = io.open(CONFIG_FILE, "r")
    if f then
        local m = tonumber(f:read("*a")); f:close()
        if m and m >= 1 and m <= MAX_MODE then return m end
    end
    return 1 -- 默认模式 1 (黄灯常亮)
end

local function save_mode(m)
    local f = io.open(CONFIG_FILE, "w")
    if f then
        f:write(tostring(m)); f:close()
        log.info("LED", "灯效模式已保存:", m)
    end
end

-- ============ 反馈触发 ============
-- 蓝灯闪烁（按键反馈 / 短信提醒）
function blue_feedback(duration_ms)
    sys.taskInit(function()
        is_blue_blinking = true
        sys.wait(duration_ms or 800)
        is_blue_blinking = false
    end)
end

-- USB 插入黄灯提醒（默认 20 秒）
function usb_light(ms)
    is_usb_lighting = true
    if usb_light_timer_id then sys.timerStop(usb_light_timer_id) end
    usb_light_timer_id = sys.timerStart(function() is_usb_lighting = false end, ms or 20000)
end

-- ============ 网络状态 ============
function set_network(ok)
    if network_ok ~= ok then
        network_ok = ok
        log.info("LED", "网络状态:", ok and "就绪" or "离线")
    end
end

-- ============ 渲染主逻辑（必须在协程内执行） ============
local function render()
    -- 1. 蓝灯闪烁（按键反馈 / 新短信）
    if is_blue_blinking then blue() sys.wait(100) return end
    -- 2. 事件反馈灯效（来短信/来电话，服务端配置下发）
    if fb_color and rtos.tick() < fb_until then
        if fb_blink then
            COLOR_FN[fb_color]() sys.wait(200)
            off() sys.wait(200)
        else
            COLOR_FN[fb_color]() sys.wait(100)
        end
        return
    end
    -- 3. USB 插入黄灯提醒
    if is_usb_lighting then yellow() sys.wait(100) return end
    -- 4. 无网络强制红灯告警
    if not network_ok then red() sys.wait(500) return end
    -- 5. 手动关灯
    if is_light_off then off() sys.wait(200) return end
    -- 6. 临时单色（服务端 set_led color 动作）
    if temp_color and COLOR_FN[temp_color] then
        COLOR_FN[temp_color]() sys.wait(200) return
    end
    -- 7. 按模式渲染
    if     current_mode == 1 then yellow()    sys.wait(200)
    elseif current_mode == 2 then neon_breath()
    elseif current_mode == 3 then cyan()      sys.wait(200)
    elseif current_mode == 4 then yellow() sys.wait(800) purple() sys.wait(800) cyan() sys.wait(800)
    elseif current_mode == 5 then green()     sys.wait(200)
    elseif current_mode == 6 then red() sys.wait(800) green() sys.wait(800) blue() sys.wait(800)
    end
end

-- ============ 控制接口（供按键 / 服务端 set_led 调用） ============
-- 开关灯
function toggle()
    is_light_off = not is_light_off
    if not is_light_off then blue_feedback(800) end
    log.info("LED", "开关灯:", is_light_off and "关" or "开")
    return not is_light_off
end

function light_on()  if is_light_off then is_light_off = false blue_feedback(800) end return true end
function light_off() is_light_off = true return false end

-- 切换灯效模式
function next_mode()
    current_mode = current_mode + 1
    if current_mode > MAX_MODE then current_mode = 1 end
    save_mode(current_mode)
    temp_color = nil -- 退出临时色
    blue_feedback(800)
    log.info("LED", "切换灯效:", current_mode)
    return current_mode
end

function prev_mode()
    current_mode = current_mode - 1
    if current_mode < 1 then current_mode = MAX_MODE end
    save_mode(current_mode)
    temp_color = nil
    blue_feedback(800)
    log.info("LED", "切换灯效:", current_mode)
    return current_mode
end

function set_mode(m)
    m = tonumber(m)
    if not m or m < 1 or m > MAX_MODE then return nil end
    current_mode = m
    save_mode(current_mode)
    temp_color = nil
    if not is_light_off then is_light_off = false end
    log.info("LED", "设置灯效模式:", current_mode)
    return current_mode
end

-- 显示临时单色（如 red/green/blue/white/off），off 表示熄灭
function set_color(name)
    if not name or not COLOR_FN[name] then return nil end
    temp_color = name
    return name
end

-- 清除临时色（恢复模式渲染）
function clear_color()
    temp_color = nil
end

-- 事件反馈灯效（来短信/来电话，服务端 set_led feedback 触发）
-- color: 颜色名；blink: 是否闪烁；ms: 持续时间(默认5000)，到期自动恢复模式渲染
function feedback(color, blink, ms)
    if not color or not COLOR_FN[color] then return nil end
    fb_color = color
    fb_blink = blink and true or false
    fb_until = rtos.tick() + ((ms and ms > 0) and ms or 5000)
    log.info("LED", "事件灯光:", color, "闪烁:", fb_blink, "时长ms:", fb_until - rtos.tick())
    return color
end

-- 查询状态（供 set_led 返回）
function status()
    return { mode = current_mode, off = is_light_off, temp = temp_color }
end

-- ============ 事件订阅 ============
sys.subscribe("IP_READY_IND", function() set_network(true) end)
sys.subscribe("IP_ERROR_IND", function() set_network(false) end)
-- 新短信：蓝灯提示 1.2 秒
sys.subscribe("SMS_ADD", function() blue_feedback(1200) end)

-- ============ 启动（渲染协程 + 开机动画） ============
function start()
    current_mode = load_mode()
    -- 开启 GPIO 供电电压域（GPIO24-28 属 LDO_VMMC）
    pmd.ldoset(2, pmd.LDO_VMMC)
    -- 默认先视为无网，等待网络事件置位
    sys.taskInit(function()
        sys.wait(1000)
        log.info("LED", "播放开机白光动画...")
        white_anim(800)
        log.info("==========================================")
        log.info(" RGB 氛围灯 + 强网告警 + USB 检测已启动 ")
        log.info("==========================================")
        while true do
            render()
        end
    end)
end
