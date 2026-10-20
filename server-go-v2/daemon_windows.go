//go:build windows

package main

import "os/exec"

// newRestartCmd Windows 本地调试构建：不支持远程重启，返回 nil，由 API 层给出明确提示。
func newRestartCmd() *exec.Cmd {
	return nil
}
