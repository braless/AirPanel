/* 设备页：列表 + 详情（备注、删除、快捷指令） */

import { api } from '../api.js';
import { state, activeDevice, loadDevices, setImei, syncShell } from '../store.js';
import { $, $$, esc, fmtTime, fmtDurationCN, emptyState, toast, goto, confirmDialog, openModal, withBusy } from '../ui.js';
import { icon, paintIcons } from '../icons.js';

export const meta = { crumb: '监控', name: '设备' };

let filter = 'all';
let keyword = '';
let detail = null;

export async function render(root) {
  await loadDevices();
  root.innerHTML = shell();
  paintIcons(root);
  bind(root);
  renderList();
  await renderDetail();
}

function shell() {
  return `
  <div class="hero">
    <div><h1>设备</h1><p>通过 MQTT 接入的 Air 系列设备 · 在线状态与基础信息</p></div>
    <div class="hero-actions">
      <span class="badge" id="devUpdated">—</span>
      <button class="btn" id="devRefresh">${icon('refresh')}刷新</button>
    </div>
  </div>
  <div class="devices-layout">
    <div class="card">
      <div class="dev-tools"><input class="input" id="devSearch" placeholder="搜索名称 / IMEI"></div>
      <div class="seg" id="devFilter" style="width:100%">
        <button class="on" data-f="all" style="flex:1">全部 <span id="cntAll">0</span></button>
        <button data-f="online" style="flex:1">在线 <span id="cntOn">0</span></button>
        <button data-f="offline" style="flex:1">离线 <span id="cntOff">0</span></button>
      </div>
      <div class="dev-list" id="devList"></div>
    </div>
    <div class="card" id="devDetail">${emptyState('选择左侧设备查看详情', 'cpu')}</div>
  </div>`;
}

function bind(root) {
  $('#devSearch', root).addEventListener('input', (e) => { keyword = e.target.value.trim().toLowerCase(); renderList(); });
  $$('#devFilter button', root).forEach((b) => b.addEventListener('click', () => {
    filter = b.dataset.f;
    $$('#devFilter button', root).forEach((x) => x.classList.toggle('on', x === b));
    renderList();
  }));
  $('#devRefresh', root).addEventListener('click', async (e) => {
    await withBusy(e.currentTarget, async () => {
      await loadDevices();
      renderList();
      await renderDetail();
      $('#devUpdated', root).textContent = '更新于 ' + fmtTime(Math.floor(Date.now() / 1000));
      toast('设备列表已刷新');
    });
  });
}

function renderList() {
  const list = state.devices.filter((d) => {
    if (filter === 'online' && !d.connected) return false;
    if (filter === 'offline' && d.connected) return false;
    if (keyword && !(d.name + d.imei).toLowerCase().includes(keyword)) return false;
    return true;
  });

  $('#cntAll').textContent = state.devices.length;
  $('#cntOn').textContent = state.devices.filter((d) => d.connected).length;
  $('#cntOff').textContent = state.devices.filter((d) => !d.connected).length;

  const box = $('#devList');
  box.innerHTML = list.length ? list.map((d) => `
    <div class="dev-row ${d.imei === state.imei ? 'on' : ''}" data-imei="${esc(d.imei)}">
      <div class="dev-avatar ${d.connected ? '' : 'off'}">${icon('cpu')}</div>
      <div style="min-width:0">
        <div class="dev-name">${esc(d.name || '未命名设备')}</div>
        <div class="dev-meta">${esc(d.imei)} · ${d.connected ? '在线' : '最后在线 ' + fmtTime(d.lastSeen)}</div>
      </div>
      <span class="badge ${d.connected ? 'green' : 'gray'}">${d.connected ? '在线' : '离线'}</span>
    </div>`).join('') : emptyState('没有匹配的设备', 'cpu');

  paintIcons(box);
  $$('.dev-row', box).forEach((row) => row.addEventListener('click', async () => {
    setImei(row.dataset.imei);
    renderList();
    await renderDetail();
  }));
}

async function renderDetail() {
  const dev = activeDevice();
  const box = $('#devDetail');
  if (!dev) {
    box.innerHTML = emptyState('还没有设备接入', 'cpu');
    return;
  }
  box.innerHTML = '<div class="skeleton" style="height:260px"></div>';

  try {
    detail = await api.overview(dev.imei);
  } catch {
    detail = null;
  }
  const latest = (detail && detail.latest) || {};
  const batt = (detail && detail.battery) || {};
  const power = (detail && detail.power) || {};

  box.innerHTML = `
    <div class="detail-head">
      <div class="dev-avatar big ${dev.connected ? '' : 'off'}">${icon('cpu')}</div>
      <div style="min-width:0">
        <h2>${esc(dev.name || '未命名设备')}</h2>
        <div class="sub">IMEI ${esc(dev.imei)} · ${esc(latest.model || 'Air724UG')} · 固件 ${esc(latest.version || '—')}</div>
      </div>
      <div class="detail-actions">
        <button class="btn sm" id="devGoTask">${icon('bolt')}下发任务</button>
        <button class="btn sm ghost" id="devRename">${icon('pencil')}备注</button>
        <button class="btn sm danger" id="devDelete">${icon('trash')}删除</button>
      </div>
    </div>
    <div class="detail-grid">
      <div class="cell"><div class="k">在线状态</div><div class="v">${dev.connected ? '在线' : '离线'}</div></div>
      <div class="cell"><div class="k">信号强度</div><div class="v">${latest.rssi ?? '—'} dBm · CSQ ${latest.csq ?? '—'}</div></div>
      <div class="cell"><div class="k">电池电压</div><div class="v">${((latest.voltage || 0) / 1000).toFixed(2)} V</div></div>
      <div class="cell"><div class="k">模组温度</div><div class="v">${latest.temperature != null ? Number(latest.temperature).toFixed(1) + ' ℃' : '—'}</div></div>
      <div class="cell"><div class="k">ICCID</div><div class="v" title="${esc(latest.iccid || '')}">${esc(latest.iccid || '—')}</div></div>
      <div class="cell"><div class="k">本机号码</div><div class="v">${esc(latest.number || dev.phone || '—')}</div></div>
    </div>
    <div class="mini-metrics">
      <div class="mini"><div class="k">电量</div><div class="v">${batt.percent ?? 0}<small> %</small></div></div>
      <div class="mini"><div class="k">平均电流</div><div class="v">${power.currentMa ?? 0}<small> mA</small></div></div>
      <div class="mini"><div class="k">运行时长</div><div class="v" style="font-size:14px">${fmtDurationCN(detail ? detail.onlineSeconds : 0)}</div></div>
    </div>
    <div style="margin-top:14px;padding-top:14px;border-top:.5px solid var(--hair)">
      <div class="label">快捷操作</div>
      <div class="quick-grid" style="margin-top:7px">
        <button class="quick" data-task="get_temperature"><span class="tile" style="--qt:rgba(255,159,10,.14);--qf:#FF9F0A">${icon('temp')}</span>查询温度</button>
        <button class="quick" data-task="get_config"><span class="tile" style="--qt:rgba(90,200,250,.16);--qf:#32ADE6">${icon('doc')}</span>读取配置</button>
        <button class="quick" data-task="set_led"><span class="tile" style="--qt:rgba(175,82,222,.14);--qf:#AF52DE">${icon('lightbulb')}</span>灯光控制</button>
        <button class="quick" data-task="get_status"><span class="tile" style="--qt:rgba(10,132,255,.14);--qf:#0A84FF">${icon('signal')}</span>查询状态</button>
      </div>
    </div>`;
  paintIcons(box);

  $('#devGoTask', box).addEventListener('click', () => goto('tasks'));
  $$('[data-task]', box).forEach((b) => b.addEventListener('click', () => goto('tasks', { task: b.dataset.task })));
  $('#devRename', box).addEventListener('click', () => renameDevice(dev));
  $('#devDelete', box).addEventListener('click', () => removeDevice(dev));
}

function renameDevice(dev) {
  openModal({
    title: '修改设备备注',
    sub: '备注仅影响面板显示，不会下发到设备',
    body: `<div class="field"><label class="label">设备名称</label>
             <input class="input" id="remarkInput" maxlength="30" value="${esc(dev.name || '')}" placeholder="如：客厅模块"></div>
           <div style="font-size:9.5px;color:var(--ink3);margin-top:8px">IMEI ${esc(dev.imei)}</div>`,
    foot: `<button class="btn ghost" data-close>取消</button><button class="btn primary" id="remarkSave">保存</button>`
  });
  $('#remarkInput').focus();
  $('#remarkSave').addEventListener('click', async (e) => {
    const name = $('#remarkInput').value.trim();
    await withBusy(e.currentTarget, async () => {
      try {
        await api.remarkDevice(dev.imei, name);
        await loadDevices();
        renderList();
        await renderDetail();
        $('#modal').classList.remove('open');
        toast('备注已保存');
      } catch (err) { toast(err.message, true); }
    });
  });
}

async function removeDevice(dev) {
  const ok = await confirmDialog('删除设备', `确认删除「<b>${esc(dev.name || dev.imei)}</b>」？<br>设备记录会从面板移除，设备重新上报 online 后会再次出现。`, { okText: '确认删除', danger: true });
  if (!ok) return;
  try {
    await api.deleteDevice(dev.imei);
    await loadDevices();
    syncShell();
    renderList();
    await renderDetail();
    toast('设备已删除');
  } catch (err) { toast(err.message, true); }
}
