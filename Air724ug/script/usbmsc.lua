module(..., package.seeall)

-- U盘功能测试程序
-- 注意:
-- 1. U盘的盘符固定为: /usbmsc0
-- 2. 开机可以先 mount, 如果 mount 失败就使用格式化 format, 一般 mount 之后需要等待2秒左右再对文件进行操作
-- 3. 读写接口都是标准的
-- 4. lua 写文件和 PC 端并不能同步显示, 需要重新插拔一下 USB

local function mscTask()
    sys.wait(1000)
    -- 虚拟 U 盘开关：默认禁用，不挂载（插入电脑不弹出 U 盘盘符）
    if not config.USB_MS_ENABLE then
        log.info("usbmsc.mscTask", "虚拟 U 盘已禁用 (config.USB_MS_ENABLE=false), 跳过挂载")
        return
    end
    -- 挂载U盘
    if io.mount(io.USBMSC) == 0 then
        log.warn("usbmsc.mscTask", "挂载U盘失败, 尝试格式化")
        if rtos.get_fs_total_size(2) > 1024 * 1024 then
            io.format(io.USBMSC)
        end
    end
    sys.wait(2000)
    log.info("usbmsc.mscTask", "usb storage free size: " .. rtos.get_fs_free_size(2) .. "/" .. rtos.get_fs_total_size(2) .. "B")
end

function write(path, str)
    if type(path) ~= "string" or type(str) ~= "string" then
        return
    end
    -- 虚拟 U 盘开关：默认禁用，不写入历史短信到 U 盘
    if not config.USB_MS_ENABLE then
        return
    end
    sys.taskInit(function()
        local result

        log.info("usbmsc.write", "usb storage free size: " .. rtos.get_fs_free_size(2) .. "/" .. rtos.get_fs_total_size(2) .. "B")

        -- 判断文件夹是否存在
        result = io.opendir("/usbmsc0")
        io.closedir("/usbmsc0") -- 必须关闭才能再次打开
        log.info("usbmsc.write", "io.opendir", result)
        if result ~= 1 then
            return
        end

        -- 判断剩余空间, 写入文件
        local freeSize = rtos.get_fs_free_size(2)
        if freeSize < 4096 then
            -- 删除已有内容, 然后从起始位置开始写入
            result = io.writeFile(path, str, "w")
        else
            -- 追加写入
            result = io.writeFile(path, str, "a")
        end
        log.info("usbmsc.write", "io.writeFile", path, result)
    end)
end

sys.taskInit(mscTask)
