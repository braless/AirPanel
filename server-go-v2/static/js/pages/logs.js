/* 日志中心：设备上报日志 + 服务端运行日志 */

import { api } from '../api.js';
import { state } from '../store.js';
import { $, $$, esc, fmtTime, fmtFull, fmtClock, dayStart, dayEnd, todayStr, emptyState, loadingState, toast, openModal, withBusy } from '../ui.js';
import { icon, paintIcons } from '../icons.js';

export const meta = { crumb: '系统', name: '日志中心' };

const LOG_TYPES = [
  ['', '全部类型'],
  ['online', '上线 / 离线'],
  ['telemetry', '遥测上报'],
  ['call_record', '通话记录'],
  ['sms_record', '短信记录'],
  ['result', '任务回执'],
  ['powersave', '省电模式'],
  ['notify_result', '通知结果']
];

const TYPE_TONE = {
  online: 'green', telemetry: 'blue', call_record: 'purple',
  sms_record: 'orange', result: 'blue', powersave: 'gray', notify_result: 'gray'
};

let tab = 'device';

/* 设备日志状态 */
const dev = { page: 1, total: 0, list: [], from: '', to: '', imei: '', type: '', keyword: '', open: null };

/* 服务端日志状态 */
const srv = { level: '', keyword: '', lines: [], total: 0, timer: null, auto: true };

/* 登录日志状态 */
const lg = { page: 1, total: 0, list: [], keyword: '' };

export async function render(root) {
  stopAuto();
  root.innerHTML = shell();
  paintIcons(root);
  bind(root);
  if (tab === 'device') await loadDevice();
  else if (tab === 'login') await loadLogin();
  else { await loadServer(); if (srv.auto) startAuto(); }
}

function shell() {
  return `
  <div class="hero">
    <div><h1>日志中心</h1><p>设备上报的原始报文与服务端运行日志 · 支持按类型、设备、关键字检索</p></div>
    <div class="hero-actions">
      <div class="seg-tabs" id="logTabs">
        <button data-t="device" class="${tab === 'device' ? 'on' : ''}">设备日志</button>
        <button data-t="server" class="${tab === 'server' ? 'on' : ''}">服务端日志</button>
        <button data-t="login" class="${tab === 'login' ? 'on' : ''}">登录日志</button>
      </div>
      <button class="btn" id="logRefresh">${icon('refresh')}刷新</button>
    </div>
  </div>

  <div id="devicePanel" class="${tab === 'device' ? '' : 'hidden'}">
    <div class="card filter-card" style="margin-bottom:12px">
      <div class="field"><label class="label" for="logFrom">开始日期</label>
        <input class="input" id="logFrom" type="date" value="${esc(dev.from)}"></div>
      <div class="field"><label class="label" for="logTo">结束日期</label>
        <input class="input" id="logTo" type="date" value="${esc(dev.to)}"></div>
      <div class="field"><label class="label" for="logDevice">设备</label>
        <div class="select-wrap"><select class="select" id="logDevice">
          <option value="">全部设备</option>
          ${state.devices.map((d) => `<option value="${esc(d.imei)}"${dev.imei === d.imei ? ' selected' : ''}>${esc(d.name || d.imei)}</option>`).join('')}
        </select></div></div>
      <div class="field"><label class="label" for="logType">类型</label>
        <div class="select-wrap"><select class="select" id="logType">
          ${LOG_TYPES.map(([v, l]) => `<option value="${v}"${dev.type === v ? ' selected' : ''}>${l}</option>`).join('')}
        </select></div></div>
      <div class="field grow"><label class="label" for="logKeyword">关键字</label>
        <input class="input" id="logKeyword" placeholder="报文内容 / topic" value="${esc(dev.keyword)}"></div>
      <button class="btn primary" id="logSearch">${icon('search')}查询</button>
      <button class="btn ghost" id="logReset">重置</button>
      <button class="btn danger" id="logClear">${icon('trash')}清理</button>
    </div>
    <div class="card data-card">
      <div class="data-scroll">
        <div class="data-head" style="--cols:120px 96px minmax(0,1fr) minmax(0,1.6fr) 34px">
          <span>时间</span><span>类型</span><span>设备</span><span>内容</span><span></span>
        </div>
        <div id="logBody">${loadingState(5)}</div>
      </div>
      <div class="pager">
        <span id="logPageInfo">—</span>
        <div class="pager-btns" id="logPager"></div>
      </div>
    </div>
  </div>

  <div id="serverPanel" class="${tab === 'server' ? '' : 'hidden'}">
    <div class="card filter-card" style="margin-bottom:12px">
      <div class="field" style="min-width:auto"><label class="label">级别</label>
        <div class="seg" id="srvLevel">
          <button data-l="" class="${srv.level === '' ? 'on' : ''}">全部</button>
          <button data-l="info" class="${srv.level === 'info' ? 'on' : ''}">Info</button>
          <button data-l="warn" class="${srv.level === 'warn' ? 'on' : ''}">Warn</button>
          <button data-l="error" class="${srv.level === 'error' ? 'on' : ''}">Error</button>
        </div>
      </div>
      <div class="field grow"><label class="label" for="srvKeyword">关键字</label>
        <input class="input" id="srvKeyword" placeholder="日志内容" value="${esc(srv.keyword)}"></div>
      <button class="btn primary" id="srvSearch">${icon('search')}查询</button>
      <div class="field" style="min-width:auto"><label class="label">自动刷新</label>
        <label class="switch" style="margin-top:4px"><input type="checkbox" id="srvAuto"${srv.auto ? ' checked' : ''}><i></i></label>
      </div>
      <button class="btn danger" id="srvClear">${icon('trash')}清空</button>
      <span class="badge" id="srvCount" style="margin-left:auto">—</span>
    </div>
    <div class="card" style="padding:12px">
      <div class="console" id="srvConsole" style="min-height:420px;max-height:calc(100vh - 320px)"></div>
    </div>
  </div>

  <div id="loginPanel" class="${tab === 'login' ? '' : 'hidden'}">
    <div class="card filter-card" style="margin-bottom:12px">
      <div class="field grow"><label class="label" for="loginKeyword">关键字（IP / 用户名 / 客户端）</label>
        <input class="input" id="loginKeyword" placeholder="按 IP / 用户名 / 客户端信息过滤" value="${esc(lg.keyword)}"></div>
      <button class="btn primary" id="loginSearch">${icon('search')}查询</button>
      <button class="btn ghost" id="loginReset">重置</button>
      <button class="btn danger" id="loginClear">${icon('trash')}清空</button>
      <span class="badge" id="loginCount" style="margin-left:auto">—</span>
    </div>
    <div class="card data-card">
      <div class="data-scroll">
        <div class="data-head" style="--cols:160px minmax(0,.8fr) minmax(0,1.6fr)">
          <span>登录时间</span><span>来源 IP</span><span>客户端信息</span>
        </div>
        <div id="loginBody">${loadingState(4)}</div>
      </div>
      <div class="pager">
        <span id="loginPageInfo">—</span>
        <div class="pager-btns" id="loginPager"></div>
      </div>
    </div>
  </div>`;
}

function bind(root) {
  $$('#logTabs button', root).forEach((b) => b.addEventListener('click', async () => {
    tab = b.dataset.t;
    $$('#logTabs button', root).forEach((x) => x.classList.toggle('on', x === b));
    $('#devicePanel').classList.toggle('hidden', tab !== 'device');
    $('#serverPanel').classList.toggle('hidden', tab !== 'server');
    $('#loginPanel').classList.toggle('hidden', tab !== 'login');
    if (tab === 'device') { stopAuto(); await loadDevice(); }
    else if (tab === 'login') { stopAuto(); await loadLogin(); }
    else { await loadServer(); if (srv.auto) startAuto(); }
  }));

  $('#logRefresh', root).addEventListener('click', async (e) => {
    await withBusy(e.currentTarget, async () => {
      if (tab === 'device') await loadDevice();
      else if (tab === 'login') await loadLogin();
      else await loadServer();
      toast('已刷新');
    });
  });

  /* 设备日志 */
  $('#logSearch', root).addEventListener('click', () => {
    dev.from = $('#logFrom').value;
    dev.to = $('#logTo').value;
    dev.imei = $('#logDevice').value;
    dev.type = $('#logType').value;
    dev.keyword = $('#logKeyword').value.trim();
    dev.page = 1;
    loadDevice();
  });
  $('#logReset', root).addEventListener('click', () => {
    Object.assign(dev, { page: 1, from: '', to: '', imei: '', type: '', keyword: '' });
    $('#logFrom').value = '';
    $('#logTo').value = '';
    $('#logDevice').value = '';
    $('#logType').value = '';
    $('#logKeyword').value = '';
    loadDevice();
  });
  $('#logClear', root).addEventListener('click', clearDeviceLogs);

  /* 服务端日志 */
  $$('#srvLevel button', root).forEach((b) => b.addEventListener('click', () => {
    srv.level = b.dataset.l;
    $$('#srvLevel button', root).forEach((x) => x.classList.toggle('on', x === b));
    loadServer();
  }));
  $('#srvSearch', root).addEventListener('click', () => {
    srv.keyword = $('#srvKeyword').value.trim();
    loadServer();
  });
  $('#srvKeyword', root).addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { srv.keyword = e.target.value.trim(); loadServer(); }
  });
  $('#srvAuto', root).addEventListener('change', (e) => {
    srv.auto = e.target.checked;
    if (srv.auto) startAuto(); else stopAuto();
  });
  $('#srvClear', root).addEventListener('click', async () => {
    try {
      await api.clearServerLogs();
      toast('服务端日志已清空');
      await loadServer();
    } catch (err) { toast(err.message, true); }
  });

  /* 登录日志 */
  $('#loginSearch', root).addEventListener('click', () => {
    lg.keyword = $('#loginKeyword').value.trim();
    lg.page = 1;
    loadLogin();
  });
  $('#loginKeyword', root).addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { lg.keyword = e.target.value.trim(); lg.page = 1; loadLogin(); }
  });
  $('#loginReset', root).addEventListener('click', () => {
    lg.keyword = '';
    $('#loginKeyword').value = '';
    lg.page = 1;
    loadLogin();
  });
  $('#loginClear', root).addEventListener('click', clearLoginLogs);
}

/* ---------------- 设备日志 ---------------- */
async function loadDevice() {
  const box = $('#logBody');
  if (!box) return;
  box.innerHTML = loadingState(4);
  try {
    const params = {
      page: dev.page, pageSize: 20, type: dev.type, keyword: dev.keyword,
      imei: dev.imei, from: dev.from ? dayStart(dev.from) : '', to: dev.to ? dayEnd(dev.to) : ''
    };
    const res = await api.logs(params);
    dev.list = res.logs || [];
    dev.total = res.total || 0;
    const size = res.pageSize || 20;
    const maxPage = Math.max(1, Math.ceil(dev.total / size));
    if (dev.page > maxPage) { dev.page = maxPage; return loadDevice(); }
    renderDevice();
  } catch (err) {
    box.innerHTML = emptyState('加载失败：' + err.message, 'info');
    paintIcons(box);
  }
}

function summarize(l) {
  const p = l.payload || '';
  try {
    const obj = JSON.parse(p);
    if (l.logType === 'telemetry') {
      return `电压 ${((obj.voltage || 0) / 1000).toFixed(2)}V · ${obj.temperature != null ? obj.temperature + '℃' : '—'} · RSSI ${obj.rssi ?? '—'} · ${obj.operator || ''}`;
    }
    if (l.logType === 'online') return obj.connected === false ? '设备离线' : '设备上线';
    if (l.logType === 'result') return `${obj.task || '任务'} → ${typeof obj.result === 'string' ? obj.result : JSON.stringify(obj.result)}`;
    if (l.logType === 'call_record') {
      const dir = obj.direction === 'outgoing' ? '去电' : '来电';
      const dur = obj.duration ? ` · ${obj.duration}s` : '';
      return `${dir} ${obj.number || '未知号码'} · ${obj.status || '—'}${dur}`;
    }
    if (l.logType === 'sms_record') {
      const dir = obj.direction === 'out' ? '发送' : '接收';
      return `${dir} ${obj.number || '未知号码'}：${obj.content || ''}`;
    }
    if (l.logType === 'powersave') return `省电模式：${obj.action || obj.state || JSON.stringify(obj)}`;
    if (l.logType === 'notify_result') return `通知 ${obj.channel || ''} ${obj.success === false ? '失败' : '成功'}`;
    return JSON.stringify(obj).slice(0, 160);
  } catch {
    return p.slice(0, 160);
  }
}

function renderDevice() {
  const box = $('#logBody');
  if (!dev.list.length) {
    box.innerHTML = emptyState('没有符合条件的日志', 'list');
    paintIcons(box);
    renderPager();
    return;
  }
  box.innerHTML = dev.list.map((l, i) => {
    const tone = TYPE_TONE[l.logType] || 'gray';
    return `<div class="data-row" style="--cols:120px 96px minmax(0,1fr) minmax(0,1.6fr) 34px" data-i="${i}">
      <div class="cell">${fmtTime(l.createdAt)}<span class="sub">${esc(l.topic)}</span></div>
      <div class="cell"><span class="badge ${tone}">${esc(l.logType)}</span></div>
      <div class="cell">${esc(l.deviceName || l.imei)}<span class="sub">${esc(l.imei)}</span></div>
      <div class="cell" title="${esc(l.payload || '')}">${esc(summarize(l))}</div>
      <div class="cell row-actions"><button class="mini-btn" data-detail="${i}" title="查看原始报文">${icon('doc')}</button></div>
    </div>`;
  }).join('');

  paintIcons(box);
  $$('[data-detail]', box).forEach((b) => b.addEventListener('click', () => showLog(dev.list[Number(b.dataset.detail)])));
  renderPager();
}

function showLog(l) {
  let body = l.payload || '';
  try { body = JSON.stringify(JSON.parse(body), null, 2); } catch { /* 原文 */ }
  openModal({
    title: '原始报文',
    sub: `${fmtFull(l.createdAt)} · ${l.deviceName || l.imei} · ${l.logType}`,
    wide: true,
    body: `
      <div class="detail-grid" style="grid-template-columns:1fr 1fr;margin-bottom:12px">
        <div class="cell"><div class="k">Topic</div><div class="v">${esc(l.topic)}</div></div>
        <div class="cell"><div class="k">类型</div><div class="v">${esc(l.logType)}</div></div>
      </div>
      <div class="label">Payload</div>
      <pre style="margin:0;padding:11px;border-radius:12px;background:var(--fill2);border:.5px solid var(--hair);font-family:var(--mono);font-size:10.5px;line-height:1.65;white-space:pre-wrap;word-break:break-word;max-height:380px;overflow:auto">${esc(body)}</pre>`,
    foot: `<button class="btn ghost" data-close>关闭</button>`
  });
  paintIcons($('#modal'));
}

function renderPager() {
  const size = 20;
  const maxPage = Math.max(1, Math.ceil(dev.total / size));
  $('#logPageInfo').textContent = `第 ${dev.page} / ${maxPage} 页 · 共 ${dev.total} 条`;
  const box = $('#logPager');
  let html = `<button data-p="prev"${dev.page <= 1 ? ' disabled' : ''}>‹</button>`;
  for (let i = 1; i <= maxPage; i++) html += `<button data-p="${i}" class="${i === dev.page ? 'on' : ''}">${i}</button>`;
  html += `<button data-p="next"${dev.page >= maxPage ? ' disabled' : ''}>›</button>`;
  box.innerHTML = html;
  $$('button', box).forEach((b) => b.addEventListener('click', () => {
    const v = b.dataset.p;
    if (v === 'prev') dev.page = Math.max(1, dev.page - 1);
    else if (v === 'next') dev.page = Math.min(maxPage, dev.page + 1);
    else dev.page = Number(v);
    loadDevice();
  }));
}

async function clearDeviceLogs() {
  openModal({
    title: '清理设备日志',
    sub: '删除后不可恢复',
    body: `<div class="field"><label class="label">清理范围</label>
      <div class="select-wrap"><select class="select" id="clearLogDays">
        <option value="7">7 天前的日志</option>
        <option value="30">30 天前的日志</option>
        <option value="90">90 天前的日志</option>
        <option value="0">全部日志</option>
      </select></div></div>`,
    foot: `<button class="btn ghost" data-close>取消</button><button class="btn danger" id="clearLogOk">确认清理</button>`
  });
  $('#clearLogOk').addEventListener('click', async (e) => {
    const days = Number($('#clearLogDays').value);
    await withBusy(e.currentTarget, async () => {
      try {
        const res = await api.clearLogs(days);
        $('#modal').classList.remove('open');
        toast(`已清理 ${res.deleted || 0} 条日志`);
        dev.page = 1;
        await loadDevice();
      } catch (err) { toast(err.message, true); }
    });
  });
}

/* ---------------- 服务端日志 ---------------- */
async function loadServer() {
  const box = $('#srvConsole');
  if (!box) return;
  try {
    const res = await api.serverLogs({ level: srv.level, keyword: srv.keyword, limit: 400 });
    srv.lines = res.lines || [];
    srv.total = res.total || 0;
    renderServer();
  } catch (err) {
    box.innerHTML = `<div class="ln"><span class="err">✕</span><span>${esc(err.message)}</span></div>`;
  }
}

function renderServer() {
  const box = $('#srvConsole');
  if (!box) return;
  $('#srvCount').textContent = `缓冲 ${srv.total} 条 · 显示 ${srv.lines.length} 条`;
  if (!srv.lines.length) {
    box.innerHTML = '<div class="ln"><span class="muted">›</span><span>暂无日志</span></div>';
    return;
  }
  box.innerHTML = srv.lines.map((l) => {
    const cls = l.level === 'error' ? 'err' : l.level === 'warn' ? 'warn' : 'muted';
    const mark = l.level === 'error' ? '✕' : l.level === 'warn' ? '!' : '›';
    return `<div class="ln"><span class="tm">${fmtClock(l.time)}</span><span class="${cls}">${mark}</span><span>${esc(l.msg)}</span></div>`;
  }).join('');
  box.scrollTop = box.scrollHeight;
}

function startAuto() {
  stopAuto();
  srv.timer = setInterval(() => {
    if (state.page !== 'logs' || tab !== 'server') return;
    if (document.hidden) return;
    loadServer();
  }, 5000);
}

function stopAuto() {
  if (srv.timer) { clearInterval(srv.timer); srv.timer = null; }
}

/* ---------------- 登录日志 ---------------- */
async function loadLogin() {
  const box = $('#loginBody');
  if (!box) return;
  box.innerHTML = loadingState(4);
  try {
    const res = await api.loginLogs({ page: lg.page, pageSize: 15, keyword: lg.keyword });
    lg.list = res.logs || [];
    lg.total = res.total || 0;
    const size = res.pageSize || 15;
    const maxPage = Math.max(1, Math.ceil(lg.total / size));
    if (lg.page > maxPage) { lg.page = maxPage; return loadLogin(); }
    renderLogin();
  } catch (err) {
    box.innerHTML = emptyState('加载失败：' + err.message, 'info');
    paintIcons(box);
  }
}

function renderLogin() {
  const box = $('#loginBody');
  $('#loginCount').textContent = `共 ${lg.total} 条`;
  if (!lg.list.length) {
    box.innerHTML = emptyState('暂无登录日志', 'clock');
    paintIcons(box);
    renderLoginPager();
    return;
  }
  box.innerHTML = lg.list.map((l) => `
    <div class="data-row" style="--cols:160px minmax(0,.8fr) minmax(0,1.6fr)">
      <div class="cell">${fmtTime(l.loginAt)}<span class="sub">${esc(l.username)}</span></div>
      <div class="cell">${esc(l.ip || '—')}</div>
      <div class="cell" title="${esc(l.userAgent || '')}">${esc(l.userAgent || '—')}</div>
    </div>`).join('');
  paintIcons(box);
  renderLoginPager();
}

function renderLoginPager() {
  const size = 15;
  const maxPage = Math.max(1, Math.ceil(lg.total / size));
  $('#loginPageInfo').textContent = `第 ${lg.page} / ${maxPage} 页 · 共 ${lg.total} 条`;
  const box = $('#loginPager');
  let html = `<button data-p="prev"${lg.page <= 1 ? ' disabled' : ''}>‹</button>`;
  for (let i = 1; i <= maxPage; i++) html += `<button data-p="${i}" class="${i === lg.page ? 'on' : ''}">${i}</button>`;
  html += `<button data-p="next"${lg.page >= maxPage ? ' disabled' : ''}>›</button>`;
  box.innerHTML = html;
  $$('button', box).forEach((b) => b.addEventListener('click', () => {
    const v = b.dataset.p;
    if (v === 'prev') lg.page = Math.max(1, lg.page - 1);
    else if (v === 'next') lg.page = Math.min(maxPage, lg.page + 1);
    else lg.page = Number(v);
    loadLogin();
  }));
}

async function clearLoginLogs() {
  openModal({
    title: '清空登录日志',
    sub: '删除后不可恢复',
    body: `<div style="font-size:11.5px;color:var(--ink3);line-height:1.7">确认清空全部登录日志？当前共 <b>${lg.total}</b> 条。</div>`,
    foot: `<button class="btn ghost" data-close>取消</button><button class="btn danger" id="loginClearOk">确认清空</button>`
  });
  $('#loginClearOk').addEventListener('click', async (e) => {
    await withBusy(e.currentTarget, async () => {
      try {
        await api.clearLoginLogs();
        $('#modal').classList.remove('open');
        toast('登录日志已清空');
        lg.page = 1;
        await loadLogin();
      } catch (err) { toast(err.message, true); }
    });
  });
}
