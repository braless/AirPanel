/* 任务记录：下发历史、回执详情、按状态筛选与清理 */

import { api } from '../api.js';
import { state } from '../store.js';
import { $, $$, esc, fmtTime, fmtFull, emptyState, loadingState, toast, openModal, confirmDialog, withBusy } from '../ui.js';
import { icon, paintIcons } from '../icons.js';
import { TASKS } from './tasks.js';

export const meta = { crumb: '自动化', name: '任务记录' };

let page = 1;
let total = 0;
let list = [];
let filter = 'all';
let keyword = '';

export async function render(root) {
  root.innerHTML = shell();
  paintIcons(root);
  bind(root);
  await load();
}

function shell() {
  return `
  <div class="hero">
    <div><h1>任务记录</h1><p>每一次下发与设备回执的完整留痕 · 参数与结果可展开查看</p></div>
    <div class="hero-actions">
      <button class="btn" id="tlRefresh">${icon('refresh')}刷新</button>
      <button class="btn danger" id="tlClear">${icon('trash')}清理</button>
    </div>
  </div>
  <div class="card filter-card" style="margin-bottom:12px">
    <div class="field grow">
      <label class="label" for="tlSearch">搜索</label>
      <input class="input" id="tlSearch" placeholder="任务名 / 设备 / 参数关键字">
    </div>
    <div class="field" style="min-width:auto">
      <label class="label">状态</label>
      <div class="seg" id="tlFilter">
        <button class="on" data-f="all">全部</button>
        <button data-f="done">成功</button>
        <button data-f="failed">失败</button>
      </div>
    </div>
    <span class="badge" id="tlCount" style="margin-left:auto">—</span>
  </div>
  <div class="card data-card">
    <div class="data-scroll">
      <div class="data-head" style="--cols:112px minmax(0,1.1fr) minmax(0,1fr) 84px 68px 62px">
        <span>时间</span><span>任务</span><span>设备</span><span>状态</span><span>耗时</span><span style="text-align:right">操作</span>
      </div>
      <div id="tlBody">${loadingState(4)}</div>
    </div>
    <div class="pager">
      <span id="tlPageInfo">—</span>
      <div class="pager-btns" id="tlPager"></div>
    </div>
  </div>`;
}

function bind(root) {
  $('#tlSearch', root).addEventListener('input', (e) => {
    keyword = e.target.value.trim().toLowerCase();
    renderList();
  });
  $$('#tlFilter button', root).forEach((b) => b.addEventListener('click', () => {
    filter = b.dataset.f;
    $$('#tlFilter button', root).forEach((x) => x.classList.toggle('on', x === b));
    renderList();
  }));
  $('#tlRefresh', root).addEventListener('click', async (e) => {
    await withBusy(e.currentTarget, async () => { await load(); toast('已刷新'); });
  });
  $('#tlClear', root).addEventListener('click', clearRecords);
}

async function load() {
  try {
    const res = await api.tasks(page);
    list = res.tasks || [];
    total = res.total || 0;
    const size = res.pageSize || 10;
    const maxPage = Math.max(1, Math.ceil(total / size));
    if (page > maxPage) { page = maxPage; return load(); }
    renderList();
  } catch (err) {
    $('#tlBody').innerHTML = emptyState('加载失败：' + err.message, 'info');
    paintIcons($('#tlBody'));
  }
}

function statusOf(t) {
  if (t.error) return { key: 'failed', label: '失败', tone: 'red' };
  if (t.status === 'done') return { key: 'done', label: '成功', tone: 'green' };
  if (t.status === 'pending') return { key: 'failed', label: '进行中', tone: 'orange' };
  return { key: 'failed', label: t.status || '未知', tone: 'gray' };
}

function renderList() {
  const box = $('#tlBody');
  const rows = list.filter((t) => {
    const st = statusOf(t);
    if (filter === 'done' && st.key !== 'done') return false;
    if (filter === 'failed' && st.key === 'done') return false;
    if (keyword) {
      const hay = [t.task, t.imei, t.deviceName, t.params, t.result, t.error].join(' ').toLowerCase();
      if (!hay.includes(keyword)) return false;
    }
    return true;
  });

  $('#tlCount').textContent = `共 ${total} 条 · 本页 ${rows.length} 条`;

  if (!rows.length) {
    box.innerHTML = emptyState(list.length ? '当前筛选无匹配记录' : '还没有任务记录，去「任务执行」下发一条试试。', 'checkSquare');
    paintIcons(box);
    renderPager();
    return;
  }

  box.innerHTML = rows.map((t, i) => {
    const st = statusOf(t);
    const label = (TASKS[t.task] && TASKS[t.task].label) || t.task;
    const cost = t.finishedAt && t.createdAt ? Math.max(0, t.finishedAt - t.createdAt) : 0;
    return `<div class="data-row" style="--cols:112px minmax(0,1.1fr) minmax(0,1fr) 84px 68px 62px" data-i="${i}">
      <div class="cell">${fmtTime(t.createdAt)}<span class="sub">${esc(t.taskId)}</span></div>
      <div class="cell strong">${esc(label)}<span class="sub">${esc(t.task)}</span></div>
      <div class="cell">${esc(t.deviceName || t.imei)}<span class="sub">${esc(t.imei)}</span></div>
      <div class="cell"><span class="badge ${st.tone}">${esc(st.label)}</span></div>
      <div class="cell">${cost ? cost + 's' : '—'}</div>
      <div class="cell row-actions"><button class="mini-btn" data-detail="${i}" title="详情">${icon('doc')}</button></div>
    </div>`;
  }).join('');

  paintIcons(box);
  $$('[data-detail]', box).forEach((b) => b.addEventListener('click', () => {
    showDetail(rows[Number(b.dataset.detail)]);
  }));
  renderPager();
}

function renderPager() {
  const size = 10;
  const maxPage = Math.max(1, Math.ceil(total / size));
  $('#tlPageInfo').textContent = `第 ${page} / ${maxPage} 页`;
  const box = $('#tlPager');
  let html = `<button data-p="prev"${page <= 1 ? ' disabled' : ''}>‹</button>`;
  for (let i = 1; i <= maxPage; i++) html += `<button data-p="${i}" class="${i === page ? 'on' : ''}">${i}</button>`;
  html += `<button data-p="next"${page >= maxPage ? ' disabled' : ''}>›</button>`;
  box.innerHTML = html;
  $$('button', box).forEach((b) => b.addEventListener('click', () => {
    const v = b.dataset.p;
    if (v === 'prev') page = Math.max(1, page - 1);
    else if (v === 'next') page = Math.min(maxPage, page + 1);
    else page = Number(v);
    load();
  }));
}

function pretty(raw) {
  if (!raw) return '—';
  try { return JSON.stringify(JSON.parse(raw), null, 2); } catch { return raw; }
}

function showDetail(t) {
  if (!t) return;
  const st = statusOf(t);
  const label = (TASKS[t.task] && TASKS[t.task].label) || t.task;
  openModal({
    title: label + ' · ' + (st.label),
    sub: `${fmtFull(t.createdAt)} · ${t.deviceName || t.imei}`,
    wide: true,
    body: `
      <div class="detail-grid" style="grid-template-columns:1fr 1fr;margin-bottom:12px">
        <div class="cell"><div class="k">任务 ID</div><div class="v">${esc(t.taskId)}</div></div>
        <div class="cell"><div class="k">命令</div><div class="v">${esc(t.task)}</div></div>
        <div class="cell"><div class="k">设备</div><div class="v">${esc(t.deviceName || '—')} · ${esc(t.imei)}</div></div>
        <div class="cell"><div class="k">完成时间</div><div class="v">${t.finishedAt ? fmtFull(t.finishedAt) : '—'}</div></div>
      </div>
      ${t.error ? `<div class="label">错误信息</div>
        <div style="padding:10px;border-radius:11px;background:rgba(255,59,48,.1);color:var(--red);font-size:11px;margin-bottom:12px">${esc(t.error)}</div>` : ''}
      <div class="label">下发参数</div>
      <pre style="margin:0 0 12px;padding:11px;border-radius:12px;background:var(--fill2);border:.5px solid var(--hair);font-family:var(--mono);font-size:10.5px;line-height:1.65;white-space:pre-wrap;word-break:break-word;max-height:200px;overflow:auto">${esc(pretty(t.params))}</pre>
      <div class="label">设备回执</div>
      <pre style="margin:0;padding:11px;border-radius:12px;background:var(--fill2);border:.5px solid var(--hair);font-family:var(--mono);font-size:10.5px;line-height:1.65;white-space:pre-wrap;word-break:break-word;max-height:280px;overflow:auto">${esc(pretty(t.result))}</pre>`,
    foot: `<button class="btn ghost" data-close>关闭</button>`
  });
  paintIcons($('#modal'));
}

async function clearRecords() {
  const body = `
    <div class="field" style="margin-bottom:10px">
      <label class="label">清理范围</label>
      <div class="select-wrap"><select class="select" id="clearDays">
        <option value="7">7 天前的记录</option>
        <option value="30">30 天前的记录</option>
        <option value="90">90 天前的记录</option>
        <option value="0">全部记录</option>
      </select></div>
    </div>
    <div style="font-size:10.5px;color:var(--ink3);line-height:1.65">清理后不可恢复，仅删除任务历史，不影响设备与定时任务。</div>`;
  openModal({
    title: '清理任务记录',
    sub: `当前共 ${total} 条`,
    body,
    foot: `<button class="btn ghost" data-close>取消</button><button class="btn danger" id="clearOk">确认清理</button>`
  });
  $('#clearOk').addEventListener('click', async (e) => {
    const days = Number($('#clearDays').value);
    await withBusy(e.currentTarget, async () => {
      try {
        const res = await api.clearTasks(days);
        $('#modal').classList.remove('open');
        toast(`已清理 ${res.deleted || 0} 条记录`);
        page = 1;
        await load();
      } catch (err) { toast(err.message, true); }
    });
  });
}
