//go:build linux

package main

import (
	"os/exec"
	"syscall"
)

// newRestartCmd 构建重启服务端的后台命令（Linux：setsid 脱离会话，后台守护运行）。
func newRestartCmd() *exec.Cmd {
	c := exec.Command("bash", "/root/airpanel/start.sh")
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	return c
}
