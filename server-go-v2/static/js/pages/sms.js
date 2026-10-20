/* 短信记录页 */

import { api } from '../api.js';
import { state, loadDevices } from '../store.js';
import { $, $$, esc, fmtTime, fmtFull, dayStart, dayEnd, todayStr, emptyState, toast, openModal, confirmDialog, withBusy, badge, goto } from '../ui.js';
import { icon, paintIcons } from '../icons.js';

export const meta = { crumb: '通信', name: '短信记录' };

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
    <div><h1>短信记录</h1><p>接收与发送的短信全文 · 支持关键词检索</p></div>
    <div class="hero-actions">
      <button class="btn" id="smsExport">${icon('download')}导出 CSV</button>
      <button class="btn primary" id="smsSend">${icon('msg')}发送短信</button>
    </div>
  </div>

  <div class="card" style="margin-bottom:12px">
    <div class="mini-metrics" id="smsStats" style="grid-template-columns:repeat(3,minmax(0,180px));margin-top:0;justify-content:start">
      ${'<div class="mini"><div class="k">—</div><div class="v">—</div></div>'.repeat(3)}
    </div>
  </div>

  <div class="card filter-card" style="margin-bottom:12px">
    <div class="field"><label class="label">设备</label>
      <div class="select-wrap"><select class="select" id="smsDevice">
        <option value="">全部设备</option>
        ${state.devices.map((d) => `<option value="${esc(d.imei)}">${esc(d.name || d.imei)}</option>`).join('')}
      </select></div>
    </div>
    <div class="field"><label class="label">类型</label>
      <div class="select-wrap"><select class="select" id="smsType">
        <option value="">全部</option><option value="in">接收</option><option value="out">发送</option>
      </select></div>
    </div>
    <div class="field"><label class="label">开始日期</label><input class="input" type="date" id="smsFrom"></div>
    <div class="field"><label class="label">结束日期</label><input class="input" type="date" id="smsTo"></div>
    <div class="field grow"><label class="label">关键词</label><input class="input" id="smsKeyword" placeholder="号码或短信内容"></div>
    <button class="btn primary" id="smsQuery">${icon('search')}查询</button>
    <button class="btn ghost" id="smsReset">重置</button>
  </div>

  <div class="card data-card">
    <div class="data-scroll" style="--cols:104px 112px 66px 120px minmax(0,1fr) 76px 88px;--minw:820px">
      <div class="data-head">
        <span>时间</span><span>设备</span><span>类型</span><span>对方号码</span>
        <span>内容</span><span>通知</span><span style="text-align:right">操作</span>
      </div>
      <div id="smsRows"><div class="skeleton" style="height:200px;margin:8px"></div></div>
    </div>
    <div class="pager" id="smsPager"></div>
  </div>`;
}

function bind(root) {
  $('#smsFrom', root).value = todayStr();
  $('#smsTo', root).value = todayStr();
  $('#smsQuery', root).addEventListener('click', () => { page = 1; load(root); });
  $('#smsReset', root).addEventListener('click', () => {
    ['smsDevice', 'smsType', 'smsFrom', 'smsTo', 'smsKeyword'].forEach((id) => { $('#' + id, root).value = ''; });
    page = 1;
    load(root);
  });
  $('#smsSend', root).addEventListener('click', () => goto('tasks', { task: 'send_sms' }));
  $('#smsExport', root).addEventListener('click', exportCsv);
}

function filters() {
  return {
    imei: $('#smsDevice').value,
    direction: $('#smsType').value,
    from: dayStart($('#smsFrom').value),
    to: dayEnd($('#smsTo').value),
    keyword: $('#smsKeyword').value.trim()
  };
}

async function load(root) {
  try {
    const [data, st] = await Promise.all([
      api.sms(Object.assign({ page, pageSize: PAGE_SIZE }, filters())),
      api.stats().catch(() => null)
    ]);
    rows = data.sms || [];
    total = data.total || 0;
    stats = st;
    renderStats();
    renderRows();
  } catch (err) {
    $('#smsRows').innerHTML = emptyState(err.message, 'msg');
    toast(err.message, true);
  }
}

function renderStats() {
  const s = stats || {};
  $('#smsStats').innerHTML = `
    <div class="mini"><div class="k">今日短信</div><div class="v">${s.smsToday ?? 0}<small> 条</small></div></div>
    <div class="mini"><div class="k">接收</div><div class="v" style="color:var(--green)">${s.smsIn ?? 0}<small> 条</small></div></div>
    <div class="mini"><div class="k">发送</div><div class="v" style="color:var(--accent)">${s.smsOut ?? 0}<small> 条</small></div></div>`;
}

const NOTIFY = {
  sent: ['已通知', 'blue'], failed: ['失败', 'red'],
  blocked: ['已屏蔽', 'purple'], queued: ['排队', 'orange']
};

function renderRows() {
  const box = $('#smsRows');
  if (!rows.length) {
    box.innerHTML = emptyState('该时间范围内没有短信记录', 'msg');
    renderPager();
    return;
  }
  box.innerHTML = rows.map((r) => {
    const nt = NOTIFY[r.notifyStatus] || ['未通知', 'gray'];
    const dir = r.direction === 'out' ? ['发送', 'blue'] : ['接收', 'green'];
    return `
    <div class="data-row" data-id="${r.id}">
      <span class="cell" title="${esc(fmtFull(r.createdAt))}">${esc(fmtTime(r.createdAt))}</span>
      <span class="cell">${esc(r.deviceName || r.imei)}</span>
      <span class="cell">${badge(dir[0], dir[1])}</span>
      <span class="cell strong">${esc(r.number || '未知号码')}${r.spam ? '<span class="sub" style="color:var(--red)">命中 ' + esc(r.spamRule || '') + '</span>' : ''}</span>
      <span class="cell" title="${esc(r.content || '')}">${esc(r.content || '（空）')}</span>
      <span class="cell">${badge(nt[0], nt[1])}</span>
      <span class="cell row-actions">
        <button class="mini-btn" data-view="${r.id}" title="查看全文">${icon('doc')}</button>
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
  $('#smsPager').innerHTML = `
    <span>共 ${total} 条 · 第 ${page} / ${pages} 页</span>
    <div class="pager-btns">
      <button ${page <= 1 ? 'disabled' : ''} data-p="${page - 1}">‹</button>
      <button class="on">${page}</button>
      <button ${page >= pages ? 'disabled' : ''} data-p="${page + 1}">›</button>
    </div>`;
  $$('#smsPager [data-p]').forEach((b) => b.addEventListener('click', () => {
    page = +b.dataset.p;
    load(document.getElementById('content'));
  }));
}

function showDetail(id) {
  const r = rows.find((x) => x.id === id);
  if (!r) return;
  openModal({
    title: '短信详情',
    sub: `${r.deviceName || r.imei} · ${fmtFull(r.createdAt)}`,
    body: `
      <div class="info-grid" style="margin-bottom:14px">
        <div><div class="k">对方号码</div><div class="v">${esc(r.number || '—')}</div></div>
        <div><div class="k">类型</div><div class="v">${r.direction === 'out' ? '发送' : '接收'}</div></div>
      </div>
      <div class="label">短信内容</div>
      <div style="font-size:12px;line-height:1.8;padding:12px;border-radius:12px;background:var(--fill2);white-space:pre-wrap;word-break:break-word">${esc(r.content || '（空）')}</div>
      ${r.spam ? `<div style="margin-top:12px;padding:10px 12px;border-radius:12px;background:rgba(255,59,48,.08);font-size:10.5px;color:var(--red)">命中屏蔽规则：${esc(r.spamRule || '—')}</div>` : ''}`,
    foot: `<button class="btn ghost" data-close>关闭</button>
           <button class="btn" id="smsCopy">${icon('copy')}复制内容</button>`
  });
  $('#smsCopy').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(r.content || '');
      toast('已复制到剪贴板');
    } catch { toast('复制失败，请手动选择文本', true); }
  });
}

async function remove(id) {
  const ok = await confirmDialog('删除短信记录', '确认删除这条短信记录？', { okText: '删除', danger: true });
  if (!ok) return;
  try {
    await api.deleteSms(id);
    toast('已删除');
    await load(document.getElementById('content'));
  } catch (err) { toast(err.message, true); }
}

async function exportCsv() {
  try {
    const data = await api.sms(Object.assign({ page: 1, pageSize: 200 }, filters()));
    const list = data.sms || [];
    const head = ['时间', '设备', 'IMEI', '类型', '号码', '内容', '通知状态'];
    const lines = [head.join(',')].concat(list.map((r) => [
      fmtFull(r.createdAt), r.deviceName || '', r.imei,
      r.direction === 'out' ? '发送' : '接收', r.number, r.content, r.notifyStatus
    ].map((v) => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"').join(',')));
    const blob = new Blob(['\ufeff' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'sms-' + todayStr() + '.csv';
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    toast(`已导出 ${list.length} 条记录`);
  } catch (err) { toast(err.message, true); }
}
