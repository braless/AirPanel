/* 定时任务：周期编排、启停、立即执行、编辑与删除 */

import { api } from '../api.js';
import { state } from '../store.js';
import { $, $$, esc, fmtFull, fmtTime, emptyState, loadingState, toast, openModal, closeModal, confirmDialog, withBusy } from '../ui.js';
import { icon, paintIcons } from '../icons.js';
import { TASKS } from './tasks.js';

export const meta = { crumb: '自动化', name: '定时任务' };

const WEEKDAYS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const PAGE_SIZE = 5;

let page = 1;
let total = 0;
let list = [];

export async function render(root) {
  root.innerHTML = shell();
  paintIcons(root);
  bind(root);
  await load();
}

function shell() {
  return `
  <div class="hero">
    <div><h1>定时任务</h1><p>按周期自动向设备下发指令 · 设备离线时跳过本次执行</p></div>
    <div class="hero-actions">
      <button class="btn" id="schRefresh">${icon('refresh')}刷新</button>
      <button class="btn primary" id="schAdd">${icon('plus')}新建定时任务</button>
    </div>
  </div>
  <div class="schedules-layout">
    <div class="card">
      <div class="card-head">
        <div><div class="card-title">任务列表</div><div class="card-sub" id="schCount">—</div></div>
      </div>
      <div class="sch-list" id="schList">${loadingState(3)}</div>
      <div class="pager" style="padding:9px 0 0;border-top:0">
        <span id="schPageInfo">—</span>
        <div class="pager-btns" id="schPager"></div>
      </div>
    </div>
    <div class="card" id="schHelp">
      <div class="card-head">
        <div><div class="card-title">周期说明</div><div class="card-sub">调度器每分钟判定一次，命中即执行</div></div>
        <span class="badge blue">cron 替代</span>
      </div>
      <div class="detail-grid" style="grid-template-columns:1fr 1fr">
        <div class="cell"><div class="k">每天</div><div class="v">指定 时:分</div></div>
        <div class="cell"><div class="k">每周</div><div class="v">周几 + 时:分</div></div>
        <div class="cell"><div class="k">每月</div><div class="v">几号 + 时:分</div></div>
        <div class="cell"><div class="k">每小时</div><div class="v">指定分钟</div></div>
        <div class="cell"><div class="k">间隔</div><div class="v">每 N 分钟 / N 小时</div></div>
        <div class="cell"><div class="k">离线策略</div><div class="v">跳过并记录</div></div>
      </div>
      <div style="margin-top:14px;padding-top:12px;border-top:.5px solid var(--hair);font-size:10px;color:var(--ink3);line-height:1.75">
        定时任务由服务端调度器驱动，不依赖浏览器在线。若设备在执行时刻离线，本次执行会被跳过，
        不会补发；恢复在线后按下一个周期继续。同一周期内不会重复触发。
      </div>
      <div style="margin-top:12px">
        <div class="label">已启用任务</div>
        <div class="mini-metrics" style="grid-template-columns:1fr 1fr">
          <div class="mini"><div class="k">启用中</div><div class="v" id="schOn">—</div></div>
          <div class="mini"><div class="k">总数</div><div class="v" id="schTotal">—</div></div>
        </div>
      </div>
    </div>
  </div>`;
}

function bind(root) {
  $('#schAdd', root).addEventListener('click', () => openEditor(null));
  $('#schRefresh', root).addEventListener('click', async (e) => {
    await withBusy(e.currentTarget, async () => { await load(); toast('已刷新'); });
  });
}

async function load() {
  try {
    const res = await api.schedules(page);
    list = res.schedules || [];
    total = res.total || 0;
    const maxPage = Math.max(1, Math.ceil(total / PAGE_SIZE));
    if (page > maxPage) { page = maxPage; return load(); }
    renderList();
  } catch (err) {
    $('#schList').innerHTML = emptyState('加载失败：' + err.message, 'info');
    paintIcons($('#schList'));
  }
}

function describe(spec) {
  if (!spec || !spec.type) return '未知周期';
  const hm = `${String(spec.hour || 0).padStart(2, '0')}:${String(spec.minute || 0).padStart(2, '0')}`;
  switch (spec.type) {
    case 'weekly': return `每${WEEKDAYS[spec.weekday || 0]} ${hm}`;
    case 'monthly': return `每月 ${spec.day} 日 ${hm}`;
    case 'daily': return `每天 ${hm}`;
    case 'hourly': return `每小时 ${String(spec.minute || 0).padStart(2, '0')} 分`;
    case 'interval': return spec.unit === 'hour' ? `每 ${spec.n} 小时` : `每 ${spec.n} 分钟`;
    default: return '未知周期';
  }
}

function specOf(sc) {
  if (!sc.spec) return {};
  if (typeof sc.spec === 'string') {
    try { return JSON.parse(sc.spec); } catch { return {}; }
  }
  return sc.spec;
}

function renderList() {
  const box = $('#schList');
  const enabled = list.filter((s) => s.enabled).length;
  $('#schCount').textContent = `共 ${total} 条 · 本页启用 ${enabled} 条`;
  $('#schOn').textContent = enabled;
  $('#schTotal').textContent = total;

  if (!list.length) {
    box.innerHTML = emptyState('还没有定时任务，点击右上角「新建定时任务」开始。', 'clock');
    paintIcons(box);
    renderPager();
    return;
  }

  box.innerHTML = list.map((s) => {
    const spec = specOf(s);
    const tone = s.enabled ? 'var(--accent)' : 'var(--ink4)';
    const taskLabel = (TASKS[s.task] && TASKS[s.task].label) || s.task;
    return `<div class="sch-row" style="--sc:${tone}" data-id="${s.id}">
      <div class="sch-main">
        <div class="sch-name">${esc(s.name || taskLabel)}</div>
        <div class="sch-meta">
          <span class="badge ${s.enabled ? 'blue' : 'gray'}">${s.enabled ? '启用中' : '已暂停'}</span>
          <span class="badge purple">${esc(taskLabel)}</span>
          <span class="badge">${esc(s.deviceName || s.imei)}</span>
          <span class="badge orange">${esc(describe(spec))}</span>
        </div>
        <div class="sch-meta" style="margin-top:4px">
          <span style="font-size:9px;color:var(--ink3)">
            上次执行 ${s.lastExecuted ? fmtTime(s.lastExecuted) : '从未执行'} · 创建于 ${fmtTime(s.createdAt)}
          </span>
        </div>
      </div>
      <div class="sch-actions">
        <button class="mini-btn" data-act="run" title="立即执行">${icon('play')}</button>
        <button class="mini-btn" data-act="edit" title="编辑">${icon('pencil')}</button>
        <button class="mini-btn" data-act="del" title="删除">${icon('trash')}</button>
        <label class="switch sm" title="${s.enabled ? '暂停' : '启用'}">
          <input type="checkbox" data-act="toggle"${s.enabled ? ' checked' : ''}><i></i>
        </label>
      </div>
    </div>`;
  }).join('');

  paintIcons(box);
  $$('.sch-row', box).forEach((row) => {
    const id = Number(row.dataset.id);
    const sc = list.find((x) => x.id === id);
    row.querySelectorAll('[data-act]').forEach((el) => {
      const act = el.dataset.act;
      if (act === 'toggle') {
        el.addEventListener('change', async () => {
          try {
            await api.toggleSchedule(id, el.checked);
            toast(el.checked ? '已启用' : '已暂停');
            await load();
          } catch (err) { toast(err.message, true); el.checked = !el.checked; }
        });
        return;
      }
      el.addEventListener('click', async () => {
        if (act === 'run') await runNow(sc);
        if (act === 'edit') openEditor(sc);
        if (act === 'del') await remove(sc);
      });
    });
  });

  renderPager();
}

function renderPager() {
  const maxPage = Math.max(1, Math.ceil(total / PAGE_SIZE));
  $('#schPageInfo').textContent = `第 ${page} / ${maxPage} 页 · 每页 ${PAGE_SIZE} 条`;
  const box = $('#schPager');
  let html = `<button data-p="prev"${page <= 1 ? ' disabled' : ''}>‹</button>`;
  for (let i = 1; i <= maxPage; i++) {
    html += `<button data-p="${i}" class="${i === page ? 'on' : ''}">${i}</button>`;
  }
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

async function runNow(sc) {
  if (!sc) return;
  toast('正在下发…');
  try {
    const res = await api.runSchedule(sc.id);
    if (!res || res.success === false) { toast((res && res.message) || '执行失败', true); return; }
    toast('已执行：' + (typeof res.result === 'string' ? res.result : '设备已回报'));
    await load();
  } catch (err) { toast(err.message, true); }
}

async function remove(sc) {
  const ok = await confirmDialog('删除定时任务', `确认删除「<b>${esc(sc.name || sc.task)}</b>」？删除后不再自动执行。`, { okText: '删除', danger: true });
  if (!ok) return;
  try {
    await api.deleteSchedule(sc.id);
    toast('已删除');
    await load();
  } catch (err) { toast(err.message, true); }
}

/* ---------------- 编辑器 ---------------- */
function openEditor(sc) {
  const editing = !!sc;
  const spec = sc ? specOf(sc) : { type: 'daily', hour: 8, minute: 0, weekday: 1, day: 1, n: 30, unit: 'minute' };
  let params = {};
  if (sc && sc.params) {
    try { params = typeof sc.params === 'string' ? JSON.parse(sc.params) : sc.params; } catch { params = {}; }
  }

  const taskOpts = Object.entries(TASKS).map(([k, v]) =>
    `<option value="${k}"${sc && sc.task === k ? ' selected' : ''}>${esc(v.label)} · ${k}</option>`).join('');

  const devOpts = state.devices.map((d) =>
    `<option value="${esc(d.imei)}"${sc ? (sc.imei === d.imei ? ' selected' : '') : (d.imei === state.imei ? ' selected' : '')}>${esc(d.name || d.imei)}${d.connected ? '' : '（离线）'}</option>`).join('');

  openModal({
    title: editing ? '编辑定时任务' : '新建定时任务',
    sub: '到达周期后由服务端自动向设备下发指令',
    wide: true,
    body: `
      <div class="form-grid">
        <div class="field"><label class="label">任务名称</label>
          <input class="input" id="schName" maxlength="40" value="${esc(sc ? sc.name : '')}" placeholder="如：每天上报状态"></div>
        <div class="field"><label class="label">目标设备</label>
          <div class="select-wrap"><select class="select" id="schDevice">${devOpts || '<option value="">暂无设备</option>'}</select></div></div>
        <div class="field"><label class="label">任务类型</label>
          <div class="select-wrap"><select class="select" id="schTask">${taskOpts}</select></div></div>
        <div class="field"><label class="label">周期类型</label>
          <div class="select-wrap"><select class="select" id="schType">
            <option value="daily">每天</option>
            <option value="weekly">每周</option>
            <option value="monthly">每月</option>
            <option value="hourly">每小时</option>
            <option value="interval">固定间隔</option>
          </select></div></div>

        <div class="full" id="schSpecBox"></div>
        <div class="full">
          <label class="label">任务参数（JSON 对象，留空表示无参数）</label>
          <textarea class="textarea" id="schParams" spellcheck="false" style="font-family:var(--mono);font-size:10.5px" placeholder='{"rcv_phone":"13800138000","content":"心跳"}'>${esc(Object.keys(params).length ? JSON.stringify(params, null, 2) : '')}</textarea>
          <div style="font-size:9.5px;color:var(--ink3);margin-top:6px" id="schParamsHint"></div>
        </div>
        <div class="full">
          <div class="switch-row">
            <div class="grow"><div class="t">创建后立即启用</div><div class="s">关闭则先保存为暂停状态，稍后手动启用</div></div>
            <label class="switch"><input type="checkbox" id="schEnabled"${!sc || sc.enabled ? ' checked' : ''}><i></i></label>
          </div>
        </div>
      </div>`,
    foot: `<button class="btn ghost" data-close>取消</button>
           <button class="btn primary" id="schSave">${editing ? '保存修改' : '创建任务'}</button>`
  });
  paintIcons($('#modal'));

  $('#schType').value = spec.type || 'daily';
  renderSpecBox(spec);

  const taskSel = $('#schTask');
  const updateHint = () => {
    const def = TASKS[taskSel.value];
    const hint = $('#schParamsHint');
    if (!def) { hint.textContent = ''; return; }
    if (!def.fields.length) {
      hint.textContent = '该任务无需参数，留空即可。';
      return;
    }
    hint.textContent = '可用字段：' + def.fields.filter((f) => !f.showIf).map((f) => f.k).join('、');
  };
  taskSel.addEventListener('change', updateHint);
  updateHint();

  $('#schType').addEventListener('change', () => {
    renderSpecBox({ type: $('#schType').value });
  });

  $('#schSave').addEventListener('click', async (e) => {
    const imei = $('#schDevice').value;
    const task = $('#schTask').value;
    if (!imei) { toast('请选择设备', true); return; }
    if (!task) { toast('请选择任务类型', true); return; }

    const raw = ($('#schParams').value || '').trim();
    let paramsObj = {};
    if (raw) {
      try {
        paramsObj = JSON.parse(raw);
        if (typeof paramsObj !== 'object' || Array.isArray(paramsObj)) throw new Error('x');
      } catch { toast('任务参数必须是合法的 JSON 对象', true); return; }
    }

    const body = {
      id: editing ? sc.id : 0,
      name: ($('#schName').value || '').trim() || (TASKS[task] ? TASKS[task].label : task),
      imei, task,
      params: paramsObj,
      spec: readSpec(),
      enabled: $('#schEnabled').checked
    };

    await withBusy(e.currentTarget, async () => {
      try {
        if (editing) await api.updateSchedule(body);
        else await api.addSchedule(body);
        closeModal();
        toast(editing ? '已保存' : '已创建');
        page = 1;
        await load();
      } catch (err) { toast(err.message, true); }
    });
  });
}

function renderSpecBox(spec) {
  const type = spec.type || 'daily';
  const h = spec.hour != null ? spec.hour : 8;
  const m = spec.minute != null ? spec.minute : 0;
  const box = $('#schSpecBox');
  let html = '<div class="label">执行时间</div><div class="cycle-detail" style="margin-top:0">';

  if (type === 'weekly') {
    html += `<span class="lbl">每周</span>
      <div class="select-wrap" style="width:96px"><select class="select" id="specWeekday" style="height:30px;font-size:11px">
        ${WEEKDAYS.map((w, i) => `<option value="${i}"${(spec.weekday || 0) === i ? ' selected' : ''}>${w}</option>`).join('')}
      </select></div>`;
  }
  if (type === 'monthly') {
    html += `<span class="lbl">每月</span>
      <input class="input" id="specDay" type="number" min="1" max="31" value="${spec.day || 1}"><span class="lbl">日</span>`;
  }
  if (type === 'daily' || type === 'weekly' || type === 'monthly') {
    html += `<span class="lbl">${type === 'daily' ? '每天' : '时间'}</span>
      <input class="input" id="specHour" type="number" min="0" max="23" value="${h}"><span class="lbl">时</span>
      <input class="input" id="specMinute" type="number" min="0" max="59" value="${m}"><span class="lbl">分</span>`;
  }
  if (type === 'hourly') {
    html += `<span class="lbl">每小时</span>
      <input class="input" id="specMinute" type="number" min="0" max="59" value="${spec.minute || 0}"><span class="lbl">分</span>`;
  }
  if (type === 'interval') {
    html += `<span class="lbl">每</span>
      <input class="input" id="specN" type="number" min="1" max="59" value="${spec.n || 30}">
      <div class="select-wrap" style="width:96px"><select class="select" id="specUnit" style="height:30px;font-size:11px">
        <option value="minute"${(spec.unit || 'minute') === 'minute' ? ' selected' : ''}>分钟</option>
        <option value="hour"${spec.unit === 'hour' ? ' selected' : ''}>小时</option>
      </select></div>`;
  }
  html += '</div>';
  box.innerHTML = html;
  paintIcons(box);
}

function readSpec() {
  const type = $('#schType').value;
  const num = (id, def) => {
    const el = $('#' + id);
    if (!el) return def;
    const v = Number(el.value);
    return Number.isFinite(v) ? v : def;
  };
  const spec = { type };
  if (type === 'weekly') spec.weekday = num('specWeekday', 0);
  if (type === 'monthly') spec.day = num('specDay', 1);
  if (type === 'daily' || type === 'weekly' || type === 'monthly') {
    spec.hour = num('specHour', 8);
    spec.minute = num('specMinute', 0);
  }
  if (type === 'hourly') spec.minute = num('specMinute', 0);
  if (type === 'interval') {
    spec.n = num('specN', 30);
    spec.unit = $('#specUnit').value;
  }
  return spec;
}
