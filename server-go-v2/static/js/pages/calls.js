/* 通话记录页 */

import { api } from '../api.js';
import { state, loadDevices } from '../store.js';
import { $, $$, esc, fmtTime, fmtFull, fmtDur, dayStart, dayEnd, todayStr, emptyState, toast, openModal, confirmDialog, withBusy, badge } from '../ui.js';
import { icon, paintIcons } from '../icons.js';

export const meta = { crumb: '通信', name: '通话记录' };

const PAGE_SIZE = 20;
let page = 1;
let total = 0;
let rows = [];
let stats = null;

export async function render(root) {
  await loadDevices();
  root.innerHTML = shell();
  paintIcons(root);
  bind(root);
  await load(root);
}

function shell() {
  return `
  <div class="hero">
    <div><h1>通话记录</h1><p>设备侧呼入与呼出记录 · 按方向、号码、时间区间筛选</p></div>
    <div class="hero-actions">
      <button class="btn" id="callExport">${icon('download')}导出 CSV</button>
      <button class="btn" id="callRefresh">${icon('refresh')}刷新</button>
    </div>
  </div>

  <div class="card" style="margin-bottom:12px">
    <div class="mini-metrics" id="callStats" style="grid-template-columns:repeat(4,1fr);margin-top:0">
      ${'<div class="mini"><div class="k">—</div><div class="v">—</div></div>'.repeat(4)}
    </div>
  </div>

  <div class="card filter-card" style="margin-bottom:12px">
    <div class="field"><label class="label">设备</label>
      <div class="select-wrap"><select class="select" id="callDevice">
        <option value="">全部设备</option>
        ${state.devices.map((d) => `<option value="${esc(d.imei)}">${esc(d.name || d.imei)}</option>`).join('')}
      </select></div>
    </div>
    <div class="field"><label class="label">方向</label>
      <div class="select-wrap"><select class="select" id="callDir">
        <option value="">全部</option><option value="incoming">呼入</option><option value="outgoing">呼出</option>
      </select></div>
    </div>
    <div class="field"><label class="label">开始日期</label><input class="input" type="date" id="callFrom"></div>
    <div class="field"><label class="label">结束日期</label><input class="input" type="date" id="callTo"></div>
    <div class="field grow"><label class="label">号码 / 原因</label><input class="input" id="callKeyword" placeholder="输入号码或挂断原因"></div>
    <button class="btn primary" id="callQuery">${icon('search')}查询</button>
    <button class="btn ghost" id="callReset">重置</button>
  </div>

  <div class="card data-card">
    <div class="data-scroll" style="--cols:112px 116px 68px 124px 64px 84px 76px 1fr;--minw:840px">
      <div class="data-head">
        <span>时间</span><span>设备</span><span>方向</span><span>号码</span>
        <span>时长</span><span>状态</span><span>通知</span><span style="text-align:right">操作</span>
      </div>
      <div id="callRows"><div class="skeleton" style="height:200px;margin:8px"></div></div>
    </div>
    <div class="pager" id="callPager"></div>
  </div>`;
}

function bind(root) {
  $('#callFrom', root).value = todayStr();
  $('#callTo', root).value = todayStr();
  $('#callQuery', root).addEventListener('click', () => { page = 1; load(root); });
  $('#callReset', root).addEventListener('click', () => {
    $('#callDevice', root).value = '';
    $('#callDir', root).value = '';
    $('#callFrom', root).value = '';
    $('#callTo', root).value = '';
    $('#callKeyword', root).value = '';
    page = 1;
    load(root);
  });
  $('#callRefresh', root).addEventListener('click', (e) => withBusy(e.currentTarget, () => load(root)));
  $('#callExport', root).addEventListener('click', exportCsv);
}

function filters() {
  return {
    imei: $('#callDevice').value,
    direction: $('#callDir').value,
    from: dayStart($('#callFrom').value),
    to: dayEnd($('#callTo').value),
    keyword: $('#callKeyword').value.trim()
  };
}

async function load(root) {
  try {
    const [data, st] = await Promise.all([
      api.calls(Object.assign({ page, pageSize: PAGE_SIZE }, filters())),
      api.stats().catch(() => null)
    ]);
    rows = data.calls || [];
    total = data.total || 0;
    stats = st;
    renderStats();
    renderRows(root);
  } catch (err) {
    $('#callRows').innerHTML = emptyState(err.message, 'phone');
    toast(err.message, true);
  }
}

function renderStats() {
  const box = $('#callStats');
  if (!box) return;
  const s = stats || {};
  box.innerHTML = `
    <div class="mini"><div class="k">今日通话</div><div class="v">${s.callsToday ?? 0}<small> 次</small></div></div>
    <div class="mini"><div class="k">呼入</div><div class="v" style="color:var(--green)">${s.callIn ?? 0}<small> 次</small></div></div>
    <div class="mini"><div class="k">呼出</div><div class="v" style="color:var(--accent)">${s.callOut ?? 0}<small> 次</small></div></div>
    <div class="mini"><div class="k">未接</div><div class="v" style="color:var(--red)">${s.callMissed ?? 0}<small> 次</small></div></div>`;
}

const STATUS = {
  connected: ['已接通', 'green'],
  missed: ['未接', 'red'],
  rejected: ['已拒接', 'gray'],
  no_answer: ['无人接听', 'orange'],
  cancelled: ['已取消', 'gray']
};

const NOTIFY = {
  sent: ['已通知', 'blue'],
  failed: ['失败', 'red'],
  blocked: ['已屏蔽', 'purple'],
  queued: ['排队', 'orange']
};

function renderRows(root) {
  const box = $('#callRows');
  if (!rows.length) {
    box.innerHTML = emptyState('该时间范围内没有通话记录', 'phone');
    renderPager();
    return;
  }
  box.innerHTML = rows.map((r) => {
    const st = STATUS[r.status] || [r.status || '未知', 'gray'];
    const nt = NOTIFY[r.notifyStatus] || ['未通知', 'gray'];
    const dir = r.direction === 'outgoing'
      ? ['呼出', 'blue'] : ['呼入', 'green'];
    return `
    <div class="data-row" data-id="${r.id}">
      <span class="cell" title="${esc(fmtFull(r.startedAt))}">${esc(fmtTime(r.startedAt))}</span>
      <span class="cell">${esc(r.deviceName || r.imei)}</span>
      <span class="cell">${badge(dir[0], dir[1])}</span>
      <span class="cell strong">${esc(r.number || '未知号码')}${r.spam ? '<span class="sub" style="color:var(--red)">疑似骚扰 · ' + esc(r.spamRule || '') + '</span>' : ''}</span>
      <span class="cell">${fmtDur(r.duration)}</span>
      <span class="cell">${badge(st[0], st[1])}</span>
      <span class="cell">${badge(nt[0], nt[1])}</span>
      <span class="cell row-actions">
        <button class="mini-btn" data-view="${r.id}" title="详情">${icon('doc')}</button>
        <button class="mini-btn" data-del="${r.id}" title="删除">${icon('trash')}</button>
      </span>
    </div>`;
  }).join('');
  paintIcons(box);

  $$('[data-view]', box).forEach((b) => b.addEventListener('click', () => showDetail(+b.dataset.view)));
  $$('[data-del]', box).forEach((b) => b.addEventListener('click', () => remove(+b.dataset.del)));
  renderPager();
}

function renderPager() {
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  $('#callPager').innerHTML = `
    <span>共 ${total} 条 · 第 ${page} / ${pages} 页</span>
    <div class="pager-btns">
      <button ${page <= 1 ? 'disabled' : ''} data-p="${page - 1}">‹</button>
      <button class="on">${page}</button>
      <button ${page >= pages ? 'disabled' : ''} data-p="${page + 1}">›</button>
    </div>`;
  $$('#callPager [data-p]').forEach((b) => b.addEventListener('click', () => {
    page = +b.dataset.p;
    load(document.getElementById('content'));
  }));
}

function showDetail(id) {
  const r = rows.find((x) => x.id === id);
  if (!r) return;
  const st = STATUS[r.status] || [r.status || '未知', 'gray'];
  const nt = NOTIFY[r.notifyStatus] || ['未通知', 'gray'];
  openModal({
    title: '通话详情',
    sub: `${r.deviceName || r.imei} · ${fmtFull(r.startedAt)}`,
    body: `
      <div class="info-grid">
        <div><div class="k">号码</div><div class="v">${esc(r.number || '—')}</div></div>
        <div><div class="k">方向</div><div class="v">${r.direction === 'outgoing' ? '呼出' : '呼入'}</div></div>
        <div><div class="k">状态</div><div class="v">${esc(st[0])}</div></div>
        <div><div class="k">通话时长</div><div class="v">${fmtDur(r.duration)}</div></div>
        <div><div class="k">接通时间</div><div class="v">${r.connectedAt ? fmtFull(r.connectedAt) : '—'}</div></div>
        <div><div class="k">挂断时间</div><div class="v">${r.endedAt ? fmtFull(r.endedAt) : '—'}</div></div>
        <div><div class="k">挂断原因</div><div class="v">${esc(r.reason || '—')}</div></div>
        <div><div class="k">通知状态</div><div class="v">${esc(nt[0])}</div></div>
      </div>
      ${r.spam ? `<div style="margin-top:14px;padding:10px 12px;border-radius:12px;background:rgba(255,59,48,.08);font-size:10.5px;color:var(--red)">命中屏蔽规则：${esc(r.spamRule || '—')}</div>` : ''}`,
    foot: '<button class="btn ghost" data-close>关闭</button>'
  });
}

async function remove(id) {
  const ok = await confirmDialog('删除通话记录', '确认删除这条通话记录？', { okText: '删除', danger: true });
  if (!ok) return;
  try {
    await api.deleteCall(id);
    toast('已删除');
    await load(document.getElementById('content'));
  } catch (err) { toast(err.message, true); }
}

async function exportCsv() {
  try {
    const data = await api.calls(Object.assign({ page: 1, pageSize: 200 }, filters()));
    const list = data.calls || [];
    const head = ['时间', '设备', 'IMEI', '方向', '号码', '状态', '时长(秒)', '挂断原因', '通知状态'];
    const lines = [head.join(',')].concat(list.map((r) => [
      fmtFull(r.startedAt), r.deviceName || '', r.imei,
      r.direction === 'outgoing' ? '呼出' : '呼入', r.number, r.status, r.duration, r.reason, r.notifyStatus
    ].map((v) => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"').join(',')));
    download('calls-' + todayStr() + '.csv', '\ufeff' + lines.join('\r\n'));
    toast(`已导出 ${list.length} 条记录`);
  } catch (err) { toast(err.message, true); }
}

function download(name, text) {
  const blob = new Blob([text], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}
