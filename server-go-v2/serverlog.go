package main

// 服务端运行日志缓冲：为「日志中心」提供实时日志流。
// log 包默认写 stderr，这里用 MultiWriter 同时写 stderr 与内存环形缓冲，
// 前端通过 /api/server-logs 拉取最近 N 条，不落盘、不占磁盘。

import (
	"io"
	"strings"
	"sync"
	"time"
)

// ServerLogEntry 单条服务端日志
type ServerLogEntry struct {
	Time  int64  `json:"time"`  // Unix 秒
	Level string `json:"level"` // debug / info / warn / error
	Msg   string `json:"msg"`
}

// ServerLogBuffer 固定容量的环形日志缓冲
type ServerLogBuffer struct {
	mu    sync.RWMutex
	ring  []ServerLogEntry
	head  int // 下一个写入位置
	count int
	max   int
}

// NewServerLogBuffer 创建容量为 max 的日志缓冲
func NewServerLogBuffer(max int) *ServerLogBuffer {
	if max <= 0 {
		max = 2000
	}
	return &ServerLogBuffer{ring: make([]ServerLogEntry, max), max: max}
}

// Write 实现 io.Writer，按行拆分并写入环形缓冲
func (b *ServerLogBuffer) Write(p []byte) (int, error) {
	now := time.Now().Unix()
	for _, line := range strings.Split(strings.TrimRight(string(p), "\n"), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		b.mu.Lock()
		b.ring[b.head] = ServerLogEntry{Time: now, Level: detectLogLevel(line), Msg: line}
		b.head = (b.head + 1) % b.max
		if b.count < b.max {
			b.count++
		}
		b.mu.Unlock()
	}
	return len(p), nil
}

// detectLogLevel 依据日志文本粗略判定级别（log 包本身不带级别）
func detectLogLevel(s string) string {
	lower := strings.ToLower(s)
	switch {
	case strings.Contains(lower, "fatal"), strings.Contains(lower, "panic"),
		strings.Contains(lower, "error"), strings.Contains(s, "失败"), strings.Contains(s, "异常"):
		return "error"
	case strings.Contains(lower, "warn"), strings.Contains(s, "超时"),
		strings.Contains(s, "跳过"), strings.Contains(s, "重试"), strings.Contains(s, "未连接"):
		return "warn"
	case strings.Contains(lower, "debug"):
		return "debug"
	default:
		return "info"
	}
}

// Snapshot 按级别与关键字过滤，返回最近 limit 条（时间正序）
func (b *ServerLogBuffer) Snapshot(level, keyword string, limit int) []ServerLogEntry {
	b.mu.RLock()
	defer b.mu.RUnlock()

	out := make([]ServerLogEntry, 0, b.count)
	start := (b.head - b.count + b.max) % b.max
	kw := strings.ToLower(strings.TrimSpace(keyword))
	for i := 0; i < b.count; i++ {
		e := b.ring[(start+i)%b.max]
		if level != "" && level != "all" && e.Level != level {
			continue
		}
		if kw != "" && !strings.Contains(strings.ToLower(e.Msg), kw) {
			continue
		}
		out = append(out, e)
	}
	if limit > 0 && len(out) > limit {
		out = out[len(out)-limit:]
	}
	return out
}

// Len 当前缓冲内的日志条数
func (b *ServerLogBuffer) Len() int {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.count
}

// Clear 清空缓冲
func (b *ServerLogBuffer) Clear() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.ring = make([]ServerLogEntry, b.max)
	b.head = 0
	b.count = 0
}

// MultiWriter 组合 stderr 与日志缓冲
func (b *ServerLogBuffer) MultiWriter(stderr io.Writer) io.Writer {
	return io.MultiWriter(stderr, b)
}
