-- 屏蔽规则模块：垃圾短信/垃圾电话本地屏蔽
-- 规则由服务端下发（MQTT cmd/{imei} type=block_rules），nvm 持久化；
-- 命中规则的新短信/来电不再发送通知（记录仍上报，notify_status=blocked）。
local nvm = require "nvm"
local log = require "log"

-- 规则缓存：{ {ruleType="keyword"|"number", value="...", matchMode="contains"|"prefix"|"exact"}, ... }
local rules = {}

-- 从 nvm 加载规则
local function load()
    local data = nvm.get("BLOCK_RULES")
    if data and data ~= "" then
        local ok, t = pcall(json.decode, data)
        if ok and type(t) == "table" then
            rules = t
            log.info("util_block", "已加载本地屏蔽规则", #rules, "条")
        end
    end
end

-- 保存到 nvm
local function save()
    nvm.set("BLOCK_RULES", json.encode(rules))
end

-- 号码匹配：prefix 前缀 / exact 精确 / contains 包含
local function matchNumber(number, value, mode)
    if number == nil or number == "" or value == nil or value == "" then
        return false
    end
    if mode == "exact" then
        return number == value
    elseif mode == "contains" then
        return string.find(number, value, 1, true) ~= nil
    else -- prefix（默认）
        return string.sub(number, 1, #value) == value
    end
end

-- 更新规则（服务端下发时调用）
function update(rulesList)
    rules = {}
    if type(rulesList) == "table" then
        for _, r in ipairs(rulesList) do
            if type(r) == "table" and r.ruleType and r.value then
                table.insert(rules, {
                    ruleType = r.ruleType,
                    value = r.value,
                    matchMode = r.matchMode or "contains"
                })
            end
        end
    end
    save()
    log.info("util_block", "屏蔽规则已更新", #rules, "条")
end

-- 判断短信是否命中屏蔽（垃圾短信）：关键字包含 或 号码匹配
function isBlockedSms(number, content)
    for _, r in ipairs(rules) do
        if r.ruleType == "keyword" and content and content ~= "" then
            if string.find(content, r.value, 1, true) ~= nil then
                return true
            end
        elseif r.ruleType == "number" and matchNumber(number, r.value, r.matchMode) then
            return true
        end
    end
    return false
end

-- 判断来电是否命中屏蔽（垃圾电话）：号码匹配
function isBlockedCall(number)
    for _, r in ipairs(rules) do
        if r.ruleType == "number" and matchNumber(number, r.value, r.matchMode) then
            return true
        end
    end
    return false
end

load()

return {
    update = update,
    isBlockedSms = isBlockedSms,
    isBlockedCall = isBlockedCall
}
