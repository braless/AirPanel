package main

// WebDAV 客户端：通话录音列表（PROPFIND）与播放（GET 代理流）

import (
	"context"
	"encoding/base64"
	"encoding/xml"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Recording 录音文件项
type Recording struct {
	Name    string `json:"name"`
	Size    int64  `json:"size"`
	ModTime string `json:"modTime"`
	URL     string `json:"url"` // 播放路径（本服务端代理）
}

// davMultistatus PROPFIND 响应结构（忽略命名空间，按 local name 匹配）
type davResponse struct {
	Href string `xml:"href"`
	// prop 实际位于 response → propstat → prop 层级
	PropStat struct {
		Prop struct {
			ContentLength string `xml:"getcontentlength"`
			LastModified  string `xml:"getlastmodified"`
			DisplayName   string `xml:"displayname"`
		} `xml:"prop"`
	} `xml:"propstat"`
}
type davMultistatus struct {
	Responses []davResponse `xml:"response"`
}

// webdavClient 构造带 Basic 认证的 WebDAV 请求客户端
// 解析策略：IPv4 优先（兼容纯 IPv4 网络/容器）；若域名无 A 记录则回退 IPv6。
func webdavHTTPClient() *http.Client {
	dialer := &net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}
	transport := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			host, port, err := net.SplitHostPort(addr)
			if err != nil {
				return nil, err
			}
			v4, err4 := net.DefaultResolver.LookupIP(ctx, "ip4", host)
			if err4 == nil && len(v4) > 0 {
				var last error
				for _, ip := range v4 {
					c, e := dialer.DialContext(ctx, "tcp", net.JoinHostPort(ip.String(), port))
					if e == nil {
						return c, nil
					}
					last = e
				}
				// IPv4 全部连接失败：尝试 IPv6 兜底
				v6, e6 := net.DefaultResolver.LookupIP(ctx, "ip6", host)
				if e6 != nil || len(v6) == 0 {
					return nil, last
				}
			}
			ips, err := net.DefaultResolver.LookupIP(ctx, "ip6", host)
			if err != nil || len(ips) == 0 {
				return nil, fmt.Errorf("resolve %s: %v", host, err)
			}
			var last error
			for _, ip := range ips {
				c, e := dialer.DialContext(ctx, "tcp", net.JoinHostPort(ip.String(), port))
				if e == nil {
					return c, nil
				}
				last = e
			}
			return nil, last
		},
	}
	return &http.Client{Transport: transport, Timeout: 30 * time.Second}
}

// webdavBrowserUA：绕过 Cloudflare 按 UA 的机器人拦截（默认 Go-http-client UA 会被 1010 拦）
const webdavBrowserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

func webdavAuthHeader(user, pass string) string {
	return "Basic " + base64.StdEncoding.EncodeToString([]byte(user+":"+pass))
}

// webdavBase 返回 WebDAV 根 + 录音目录（percent-encode 中文目录）
func webdavBase(cfg *WebDAVConfig) string {
	host := strings.TrimRight(cfg.URL, "/")
	if host == "" {
		return ""
	}
	dirEsc := url.PathEscape(cfg.Dir)
	if dirEsc == "" {
		return host
	}
	return host + "/" + dirEsc
}

// listRecordings 列出录音目录下的文件（PROPFIND Depth:1）
func listRecordings(cfg *WebDAVConfig) ([]Recording, error) {
	base := webdavBase(cfg)
	if base == "" || cfg.Username == "" {
		return nil, fmt.Errorf("WebDAV 未配置")
	}
	req, err := http.NewRequest("PROPFIND", base+"/", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", webdavAuthHeader(cfg.Username, cfg.Password))
	req.Header.Set("Depth", "1")
	req.Header.Set("Content-Type", "application/xml")
	req.Header.Set("User-Agent", webdavBrowserUA)
	body := `<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:getcontentlength/><d:getlastmodified/><d:displayname/></d:prop></d:propfind>`
	req.Body = io.NopCloser(strings.NewReader(body))
	req.ContentLength = int64(len(body))

	resp, err := webdavHTTPClient().Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// 目录不存在或列表失败：返回空列表，不视为致命错误
	if resp.StatusCode != 200 && resp.StatusCode != 207 {
		return nil, nil
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	var ms davMultistatus
	if err := xml.Unmarshal(data, &ms); err != nil {
		log.Printf("解析 WebDAV PROPFIND 响应失败: %v", err)
		return nil, nil
	}

	dirPrefix := base + "/"
	var out []Recording
	for _, r := range ms.Responses {
		// 跳过目录自身（href 以 / 结尾）
		href := strings.TrimSpace(r.Href)
		if href == "" || strings.HasSuffix(href, "/") {
			continue
		}
		name := href
		if i := strings.LastIndex(href, "/"); i >= 0 {
			name = href[i+1:]
		}
		name, _ = url.PathUnescape(name)
		if name == "" {
			continue
		}
		var size int64
		fmt.Sscanf(strings.TrimSpace(r.PropStat.Prop.ContentLength), "%d", &size)
		out = append(out, Recording{
			Name:    name,
			Size:    size,
			ModTime: strings.TrimSpace(r.PropStat.Prop.LastModified),
			URL:     "/api/recordings/play?file=" + url.QueryEscape(name),
		})
	}
	_ = dirPrefix
	return out, nil
}

// streamRecording 代理 WebDAV 文件为音频流供前端播放
func streamRecording(cfg *WebDAVConfig, name string, w http.ResponseWriter) error {
	base := webdavBase(cfg)
	if base == "" || cfg.Username == "" {
		return fmt.Errorf("WebDAV 未配置")
	}
	fileURL := base + "/" + url.PathEscape(name)
	req, err := http.NewRequest("GET", fileURL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", webdavAuthHeader(cfg.Username, cfg.Password))
	req.Header.Set("User-Agent", webdavBrowserUA)

	resp, err := webdavHTTPClient().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("WebDAV 返回 %d", resp.StatusCode)
	}
	w.Header().Set("Content-Type", "audio/wav")
	w.Header().Set("Content-Disposition", `inline; filename="`+name+`"`)
	if cl := resp.Header.Get("Content-Length"); cl != "" {
		w.Header().Set("Content-Length", cl)
	}
	w.WriteHeader(200)
	_, err = io.Copy(w, resp.Body)
	return err
}

// handleRecordings 列表接口
func (a *API) handleRecordings(w http.ResponseWriter, r *http.Request) {
	cfg := a.app.getSettings().WebDAV
	files, err := listRecordings(&cfg)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]interface{}{"success": false, "error": err.Error(), "files": []Recording{}})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"success": true, "files": files})
}

// handleRecordingPlay 播放接口：服务端代理 WebDAV 音频流
func (a *API) handleRecordingPlay(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("file")
	if name == "" {
		http.Error(w, "missing file", http.StatusBadRequest)
		return
	}
	cfg := a.app.getSettings().WebDAV
	if err := streamRecording(&cfg, name, w); err != nil {
		log.Printf("播放录音失败 %s: %v", name, err)
		http.Error(w, "play failed", http.StatusInternalServerError)
	}
}
