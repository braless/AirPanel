/* API 客户端：统一鉴权、错误处理与查询串构造 */

const TOKEN_KEY = 'airpanel.v2.token';

export function getToken() { return localStorage.getItem(TOKEN_KEY) || ''; }
export function setToken(t) { localStorage.setItem(TOKEN_KEY, t); }
export function clearToken() { localStorage.removeItem(TOKEN_KEY); }

function qs(params) {
  if (!params) return '';
  const sp = new URLSearchParams();
  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== '') sp.set(k, v);
  });
  const s = sp.toString();
  return s ? '?' + s : '';
}

async function request(path, { method = 'GET', body, params } = {}) {
  const headers = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const token = getToken();
  if (token) headers.Authorization = 'Bearer ' + token;

  let res;
  try {
    res = await fetch(path + qs(params), {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body)
    });
  } catch (e) {
    throw new Error('网络请求失败，请检查服务端是否在线');
  }

  if (res.status === 401) {
    clearToken();
    window.dispatchEvent(new Event('auth:expired'));
    throw new Error('登录已失效，请重新登录');
  }

  const text = await res.text();
  let data = null;
  if (text) {
    try { data = JSON.parse(text); } catch { data = { message: text }; }
  }
  if (!res.ok) {
    const err = new Error((data && (data.message || data.error)) || ('HTTP ' + res.status));
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

async function fetchBlob(path) {
  const res = await fetch(path, { headers: { Authorization: 'Bearer ' + getToken() } });
  if (!res.ok) throw new Error('文件读取失败（HTTP ' + res.status + '）');
  return res.blob();
}

export const api = {
  /* 认证 */
  login: (username, password) => request('/api/login', { method: 'POST', body: { username, password } }),
  logout: () => request('/api/logout', { method: 'POST' }),
  changeUserInfo: (oldPassword, newUsername, newPassword) =>
    request('/api/change-user-info', { method: 'POST', body: { oldPassword, newUsername, newPassword } }),

  /* 设备 */
  devices: () => request('/api/userPool'),
  remarkDevice: (imei, name) => request('/api/device/remark', { method: 'POST', body: { imei, name } }),
  deleteDevice: (imei) => request('/api/device/delete', { method: 'POST', body: { imei } }),
  overview: (imei) => request('/api/device/overview', { params: { imei } }),
  saveOverviewConfig: (batteryMah, avgCurrentMa) =>
    request('/api/device/overview/config', { method: 'POST', body: { batteryMah, avgCurrentMa } }),
  stats: () => request('/api/stats/summary'),

  /* 任务 */
  executeTask: (payload) => request('/api/executeTask', { method: 'POST', body: payload }),
  tasks: (page) => request('/api/tasks', { params: { page } }),
  clearTasks: (days) => request('/api/tasks/clear', { method: 'POST', body: { days } }),

  /* 定时任务 */
  schedules: (page) => request('/api/schedules', { params: { page } }),
  addSchedule: (body) => request('/api/schedules/add', { method: 'POST', body }),
  updateSchedule: (body) => request('/api/schedules/update', { method: 'POST', body }),
  toggleSchedule: (id, enabled) => request('/api/schedules/toggle', { method: 'POST', body: { id, enabled } }),
  deleteSchedule: (id) => request('/api/schedules/delete', { method: 'POST', body: { id } }),
  runSchedule: (id) => request('/api/schedules/run', { method: 'POST', body: { id } }),

  /* 记录 */
  calls: (params) => request('/api/calls', { params }),
  clearCalls: (days) => request('/api/calls/clear', { method: 'POST', body: { days } }),
  deleteCall: (id) => request('/api/calls/delete', { method: 'POST', body: { id } }),
  sms: (params) => request('/api/sms', { params }),
  clearSms: (days) => request('/api/sms/clear', { method: 'POST', body: { days } }),
  deleteSms: (id) => request('/api/sms/delete', { method: 'POST', body: { id } }),

  /* 日志 */
  logs: (params) => request('/api/logs', { params }),
  clearLogs: (days) => request('/api/logs/clear', { method: 'POST', body: { days } }),
  serverLogs: (params) => request('/api/server-logs', { params }),
  clearServerLogs: () => request('/api/server-logs/clear', { method: 'POST' }),

  /* 屏蔽 */
  blockRules: (params) => request('/api/block-rules', { params }),
  addBlockRule: (body) => request('/api/block-rules/add', { method: 'POST', body }),
  updateBlockRule: (body) => request('/api/block-rules/update', { method: 'POST', body }),
  deleteBlockRule: (id) => request('/api/block-rules/delete', { method: 'POST', body: { id } }),
  resetBlockRules: () => request('/api/block-rules/reset', { method: 'POST' }),

  /* 设置 */
  settings: () => request('/api/settings'),
  saveSettings: (body) => request('/api/settings/save', { method: 'POST', body }),
  notifyChannels: () => request('/api/notify/channels'),
  testNotify: (channels, config) => request('/api/notify/test', { method: 'POST', body: { channels, config } }),

  /* 录音 */
  recordings: () => request('/api/recordings'),
  recordingBlob: (file) => fetchBlob('/api/recordings/play?file=' + encodeURIComponent(file)),
  recordingDownloadUrl: (file) => '/api/recordings/download?file=' + encodeURIComponent(file),
  deleteRecording: (file) => request('/api/recordings/delete', { method: 'POST', body: { file } }),

  /* 运维 */
  health: () => request('/api/health'),
  restart: () => request('/api/restart', { method: 'POST' })
};
