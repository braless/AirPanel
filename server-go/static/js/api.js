// API 封装：与服务端 REST 接口交互
const API = {
  token: localStorage.getItem('panel_token') || '',

  async request(method, path, body) {
    const headers = { 'Content-Type': 'application/json' };
    if (this.token) headers['Authorization'] = 'Bearer ' + this.token;
    const res = await fetch('/api' + path, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
    const data = await res.json().catch(() => ({}));
    if (res.status === 401 || res.status === 403) {
      this.clearToken();
      throw new Error(data.message || '登录已失效，请重新登录');
    }
    if (!res.ok) throw new Error(data.message || '请求失败');
    return data;
  },

  setToken(t) {
    this.token = t;
    localStorage.setItem('panel_token', t);
  },
  clearToken() {
    this.token = '';
    localStorage.removeItem('panel_token');
  },

  login(username, password) {
    return this.request('POST', '/login', { username, password });
  },
  logout() {
    return this.request('POST', '/logout');
  },
  userPool() {
    return this.request('GET', '/userPool');
  },
  updateDeviceRemark(payload) {
    return this.request('POST', '/device/remark', payload);
  },
  deleteDevice(payload) {
    return this.request('POST', '/device/delete', payload);
  },
  getOverview(imei) {
    return this.request('GET', '/device/overview?imei=' + encodeURIComponent(imei));
  },
  saveOverviewConfig(payload) {
    return this.request('POST', '/device/overview/config', payload);
  },
  executeTask(payload) {
    return this.request('POST', '/executeTask', payload);
  },
  tasks(page = 1) {
    return this.request('GET', '/tasks?page=' + encodeURIComponent(page));
  },
  clearTasks(payload) {
    return this.request('POST', '/tasks/clear', payload);
  },
  schedules(page = 1) {
    return this.request('GET', '/schedules?page=' + encodeURIComponent(page));
  },
  addSchedule(payload) {
    return this.request('POST', '/schedules/add', payload);
  },
  updateSchedule(payload) {
    return this.request('POST', '/schedules/update', payload);
  },
  toggleSchedule(payload) {
    return this.request('POST', '/schedules/toggle', payload);
  },
  deleteSchedule(payload) {
    return this.request('POST', '/schedules/delete', payload);
  },
  runSchedule(payload) {
    return this.request('POST', '/schedules/run', payload);
  },
  changeUserInfo(payload) {
    return this.request('POST', '/change-user-info', payload);
  },
  // 设置：离线判定超时 + 离线通知
  getSettings() {
    return this.request('GET', '/settings');
  },
  saveSettings(payload) {
    return this.request('POST', '/settings/save', payload);
  },
  notifyChannels() {
    return this.request('GET', '/notify/channels');
  },
  testNotify(payload) {
    return this.request('POST', '/notify/test', payload);
  },
  // 通话记录
  calls(page, params) {
    const q = '?page=' + encodeURIComponent(page) + buildRecordFilter(params);
    return this.request('GET', '/calls' + q);
  },
  clearCalls(payload) {
    return this.request('POST', '/calls/clear', payload);
  },
  deleteCall(id) {
    return this.request('POST', '/calls/delete', { id });
  },
  // 短信记录
  sms(page, params) {
    const q = '?page=' + encodeURIComponent(page) + buildRecordFilter(params);
    return this.request('GET', '/sms' + q);
  },
  clearSms(payload) {
    return this.request('POST', '/sms/clear', payload);
  },
  deleteSms(id) {
    return this.request('POST', '/sms/delete', { id });
  },
  // 设备日志（日志中心）
  logs(page, params) {
    const q = '?page=' + encodeURIComponent(page) + buildRecordFilter(params);
    return this.request('GET', '/logs' + q);
  },
  clearLogs(payload) {
    return this.request('POST', '/logs/clear', payload);
  },
  // 屏蔽规则（关键字 / 号码）。opts: { type?, page?, size? }，缺省分页参数时返回全部
  blockRules(opts) {
    const params = new URLSearchParams();
    if (opts && typeof opts === 'object') {
      if (opts.type) params.set('type', opts.type);
      if (opts.page) params.set('page', opts.page);
      if (opts.size) params.set('size', opts.size);
    }
    const q = params.toString();
    return this.request('GET', '/block-rules' + (q ? '?' + q : ''));
  },
  addBlockRule(payload) {
    return this.request('POST', '/block-rules/add', payload);
  },
  updateBlockRule(payload) {
    return this.request('POST', '/block-rules/update', payload);
  },
  deleteBlockRule(payload) {
    return this.request('POST', '/block-rules/delete', payload);
  },
  resetBlockRules() {
    return this.request('POST', '/block-rules/reset', {});
  },
};

// 构建记录筛选参数（时间范围 / 设备 / 类型 / 关键字），params: {from, to, imei, type, keyword}，均为 Unix 秒或空
function buildRecordFilter(params) {
  params = params || {};
  let q = '';
  if (params.from) q += '&from=' + encodeURIComponent(params.from);
  if (params.to) q += '&to=' + encodeURIComponent(params.to);
  if (params.imei) q += '&imei=' + encodeURIComponent(params.imei);
  if (params.type) q += '&type=' + encodeURIComponent(params.type);
  if (params.keyword) q += '&keyword=' + encodeURIComponent(params.keyword);
  return q;
}
