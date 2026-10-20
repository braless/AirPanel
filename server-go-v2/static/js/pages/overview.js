/* 概览页：设备状态、趋势、续航、快捷操作 */

import { api } from '../api.js';
import { state, activeDevice, loadDevices } from '../store.js';
import { $, esc, fmtTime, fmtClock, fmtDurationCN, emptyState, toast, goto, badge, withBusy } from '../ui.js';
import { icon, paintIcons } from '../icons.js';

export const meta = { crumb: '监控', name: '概览' };

let current = null;

export async function render(root) {
  const dev = activeDevice();
  root.innerHTML = shell(dev);
  paintIcons(root);
  bind(root);
  if (!dev) {
    $('#ovBody').innerHTML = emptyState('还没有设备接入。设备通过 MQTT 上报 online 后会自动出现在这里。', 'cpu');
    return;
  }
  await load(root);
}

function shell(dev) {
  return `
  <div class="hero">
    <div>
      <h1>设备概览</h1>
      <p>${dev ? esc(dev.name || dev.imei) + ' · ' : ''}实时状态 · 信号 / 功耗 / 在线时长 / 续航估算</p>
    </div>
    <div class="hero-actions">
      <span class="badge" id="ovUpdated">尚未加载</span>
      <button class="btn" id="ovRefresh">${icon('refresh')}刷新</button>
      <button class="btn primary" id="ovTask">${icon('bolt')}下发任务</button>
    </div>
  </div>
  <div id="ovBody">
    <div class="metric-grid" id="ovMetrics">${'<div class="skeleton" style="height:116px"></div>'.repeat(4)}</div>
    <div class="ov-main">
      <div style="display:flex;flex-direction:column;gap:12px;min-width:0">
        <div class="card">
          <div class="card-head">
            <div><div class="card-title">信号 / 电压 / 温度趋势</div><div class="card-sub">最近 30 次上报</div></div>
            <span class="badge blue">实时</span>
          </div>
          <div class="chart-wrap" id="ovChart"></div>
          <div class="legend">
            <span><i style="background:#5AC8FA"></i>信号 RSSI (dBm)</span>
            <span><i style="background:#34C759"></i>电压 (V)</span>
            <span><i style="background:#FF9F0A"></i>温度 (℃)</span>
            <span style="margin-left:auto" id="ovPointCount">—</span>
          </div>
        </div>
        <div class="card">
          <div class="card-head">
            <div><div class="card-title">续航估算配置</div><div class="card-sub">电池容量用于电量估算；平均电流填 0 表示按功耗模型自动估算</div></div>
          </div>
          <div class="power-form">
            <div class="field">
              <label class="label" for="ovMah">电池容量 (mAh)</label>
              <input class="input" id="ovMah" type="number" min="100" step="50" value="1800">
            </div>
            <div class="field">
              <label class="label" for="ovCurrent">平均电流 (mA，0=自动)</label>
              <input class="input" id="ovCurrent" type="number" min="0" step="1" value="0">
            </div>
            <button class="btn primary" id="ovSave">${icon('check')}保存</button>
          </div>
        </div>
      </div>
      <div class="ov-side">
        <div class="card">
          <div class="card-head">
            <div><div class="card-title">电池与续航</div><div class="card-sub">按当前功耗模型估算</div></div>
            <span class="badge" id="ovChargeBadge">—</span>
          </div>
          <div class="batt">
            <div class="ring" id="ovRing"><div class="rv" id="ovRingVal">—</div></div>
            <div class="batt-info" id="ovBattInfo"></div>
          </div>
        </div>
        <div class="card">
          <div class="card-head">
            <div><div class="card-title">设备信息</div><div class="card-sub">当前选中设备</div></div>
            <button class="btn sm" id="ovDetail">${icon('chevR')}详情</button>
          </div>
          <div class="info-grid" id="ovInfo"></div>
        </div>
        <div class="card">
          <div class="card-head"><div><div class="card-title">快捷操作</div><div class="card-sub">常用远程指令</div></div></div>
          <div class="quick-grid">
            <button class="quick" data-task="get_temperature"><span class="tile" style="--qt:rgba(255,159,10,.14);--qf:#FF9F0A">${icon('temp')}</span>查询温度</button>
            <button class="quick" data-task="get_config"><span class="tile" style="--qt:rgba(90,200,250,.16);--qf:#32ADE6">${icon('doc')}</span>读取配置</button>
            <button class="quick" data-task="set_led"><span class="tile" style="--qt:rgba(175,82,222,.14);--qf:#AF52DE">${icon('lightbulb')}</span>灯光控制</button>
            <button class="quick" data-task="get_status"><span class="tile" style="--qt:rgba(10,132,255,.14);--qf:#0A84FF">${icon('signal')}</span>查询状态</button>
          </div>
        </div>
      </div>
    </div>
  </div>`;
}

function bind(root) {
  $('#ovRefresh', root)?.addEventListener('click', (e) => withBusy(e.currentTarget, () => load(root)));
  $('#ovTask', root)?.addEventListener('click', () => goto('tasks'));
  $('#ovDetail', root)?.addEventListener('click', () => goto('devices'));
  $('#ovSave', root)?.addEventListener('click', async (e) => {
    const mah = parseInt($('#ovMah', root).value, 10) || 1800;
    const cur = parseInt($('#ovCurrent', root).value, 10) || 0;
    await withBusy(e.currentTarget, async () => {
      try {
        await api.saveOverviewConfig(mah, cur);
        toast('续航估算配置已保存');
        await load(root);
      } catch (err) { toast(err.message, true); }
    });
  });
  root.querySelectorAll('[data-task]').forEach((btn) => {
    btn.addEventListener('click', () => goto('tasks', { task: btn.dataset.task }));
  });
}

async function load(root) {
  const dev = activeDevice();
  if (!dev) return;
  try {
    const [ov, stats] = await Promise.all([api.overview(dev.imei), api.stats().catch(() => null)]);
    current = ov;
    renderMetrics(ov, stats);
    renderChart(ov.history || []);
    renderBattery(ov);
    renderInfo(ov);
    $('#ovMah', root).value = ov.battery?.mah || 1800;
    $('#ovCurrent', root).value = ov.power?.avgCurrentMa || 0;
    $('#ovUpdated', root).textContent = '更新于 ' + fmtClock(Math.floor(Date.now() / 1000));
  } catch (err) {
    toast(err.message, true);
  }
}

function renderMetrics(ov, stats) {
  const latest = ov.latest || {};
  const batt = ov.battery || {};
  const power = ov.power || {};
  const dev = ov.device || {};

  const csq = latest.csq ?? 0;
  const rssi = latest.rssi ?? 0;
  const temp = latest.temperature ?? 0;
  const hours = ((ov.onlineSeconds || 0) / 3600).toFixed(1);

  const signalTone = dev.connected ? (csq >= 18 ? 'green' : csq >= 12 ? 'orange' : 'red') : 'gray';
  const signalText = dev.connected ? (csq >= 18 ? '良好' : csq >= 12 ? '一般' : '较弱') : '离线';

  $('#ovMetrics').innerHTML = `
    <div class="card metric" style="--tint:rgba(90,200,250,.9)">
      <div class="k">信号强度</div>
      <span class="badge ${signalTone}">${signalText}</span>
      <div class="v">${dev.connected ? csq : '—'}<span class="u">CSQ</span></div>
      <div class="foot">${dev.connected ? `${rssi} dBm · ${esc(latest.netMode || 'LTE')}` : '设备离线'}</div>
      <svg class="spark" viewBox="0 0 82 26" preserveAspectRatio="none"><path d="M0 18 L10 15 L20 17 L30 12 L40 14 L50 10 L60 12 L70 8 L82 10" fill="none" stroke="#5AC8FA" stroke-width="1.6" stroke-linecap="round"/></svg>
    </div>
    <div class="card metric" style="--tint:rgba(52,199,89,.9)">
      <div class="k">电池电量</div>
      <span class="badge ${batt.percent > 30 ? 'green' : 'orange'}">${batt.charging ? '充电中' : '放电'}</span>
      <div class="v">${batt.percent ?? 0}<span class="u">%</span></div>
      <div class="foot">${((batt.voltage || 0) / 1000).toFixed(2)} V · 容量 ${batt.mah || 1800} mAh</div>
      <svg class="spark" viewBox="0 0 82 26" preserveAspectRatio="none"><path d="M0 20 L10 19 L20 18 L30 18 L40 16 L50 15 L60 14 L70 13 L82 12" fill="none" stroke="#34C759" stroke-width="1.6" stroke-linecap="round"/></svg>
    </div>
    <div class="card metric" style="--tint:rgba(255,159,10,.9)">
      <div class="k">模组温度</div>
      <span class="badge ${temp > 45 ? 'orange' : 'green'}">${temp > 45 ? '偏高' : '正常'}</span>
      <div class="v">${Number(temp).toFixed(1)}<span class="u">℃</span></div>
      <div class="foot">采样间隔 30 秒</div>
      <svg class="spark" viewBox="0 0 82 26" preserveAspectRatio="none"><path d="M0 16 L10 14 L20 17 L30 13 L40 15 L50 12 L60 14 L70 11 L82 13" fill="none" stroke="#FF9F0A" stroke-width="1.6" stroke-linecap="round"/></svg>
    </div>
    <div class="card metric" style="--tint:rgba(10,132,255,.9)">
      <div class="k">在线时长</div>
      <span class="badge ${dev.connected ? 'green' : 'gray'}">${dev.connected ? '心跳正常' : '离线'}</span>
      <div class="v">${hours}<span class="u">小时</span></div>
      <div class="foot">${dev.connected ? '本次连接' : '等待重连'} · 今日任务 ${stats ? stats.tasksToday : 0}</div>
      <svg class="spark" viewBox="0 0 82 26" preserveAspectRatio="none"><path d="M0 21 L10 21 L20 19 L30 19 L40 16 L50 16 L60 12 L70 12 L82 9" fill="none" stroke="#0A84FF" stroke-width="1.6" stroke-linecap="round"/></svg>
    </div>`;
  paintIcons($('#ovMetrics'));
}

function linePath(values, min, max, w, h, pad) {
  if (!values.length) return '';
  const span = Math.max(1, max - min);
  return values.map((v, i) => {
    const x = values.length === 1 ? w / 2 : (i / (values.length - 1)) * w;
    const clamped = Math.max(min, Math.min(max, v));
    const y = h - pad - ((clamped - min) / span) * (h - pad * 2);
    return (i ? 'L' : 'M') + x.toFixed(1) + ' ' + y.toFixed(1);
  }).join(' ');
}

function renderChart(history) {
  const box = $('#ovChart');
  if (!history.length) {
    box.innerHTML = emptyState('暂无遥测数据，等待设备上报', 'signal');
    $('#ovPointCount').textContent = '0 次';
    return;
  }
  const rssi = history.map((h) => h.rssi);
  const volt = history.map((h) => h.voltage / 1000);
  const temp = history.map((h) => h.temperature);

  /** 按数据实际范围留 15% 余量，避免曲线贴边或被压平 */
  const span = (arr, fbMin, fbMax, minGap) => {
    const vals = arr.filter((v) => Number.isFinite(v));
    if (!vals.length) return [fbMin, fbMax];
    let mn = Math.min(...vals);
    let mx = Math.max(...vals);
    if (mx - mn < minGap) {
      const mid = (mx + mn) / 2;
      mn = mid - minGap / 2;
      mx = mid + minGap / 2;
    }
    const pad = (mx - mn) * 0.15;
    return [mn - pad, mx + pad];
  };

  const [sMin, sMax] = span(rssi, -95, -55, 20);
  const [vMin, vMax] = span(volt, 3.4, 4.2, 0.3);
  const [tMin, tMax] = span(temp, 20, 45, 8);

  const sigPath = linePath(rssi, sMin, sMax, 640, 200, 14);
  const volPath = linePath(volt, vMin, vMax, 640, 200, 14);
  const tmpPath = linePath(temp, tMin, tMax, 640, 200, 14);
  const area = sigPath ? `${sigPath} L640 200 L0 200 Z` : '';

  box.innerHTML = `
    <svg viewBox="0 0 640 200" preserveAspectRatio="none">
      <defs>
        <linearGradient id="sigArea" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#5AC8FA" stop-opacity=".22"/>
          <stop offset="1" stop-color="#5AC8FA" stop-opacity="0"/>
        </linearGradient>
      </defs>
      <g stroke="currentColor" stroke-width="1" opacity=".07">
        <line x1="0" y1="40" x2="640" y2="40"/><line x1="0" y1="80" x2="640" y2="80"/>
        <line x1="0" y1="120" x2="640" y2="120"/><line x1="0" y1="160" x2="640" y2="160"/>
      </g>
      ${area ? `<path d="${area}" fill="url(#sigArea)"/>` : ''}
      <path d="${sigPath}" fill="none" stroke="#5AC8FA" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="${volPath}" fill="none" stroke="#34C759" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" opacity=".95"/>
      <path d="${tmpPath}" fill="none" stroke="#FF9F0A" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" opacity=".95"/>
    </svg>`;
  $('#ovPointCount').textContent = `最近 ${history.length} 次`;
}

function renderBattery(ov) {
  const batt = ov.battery || {};
  const power = ov.power || {};
  const pct = Math.max(0, Math.min(100, batt.percent || 0));
  const ring = $('#ovRing');
  ring.style.background = `conic-gradient(var(--green) 0 ${pct}%, var(--fill) ${pct}% 100%)`;
  $('#ovRingVal').innerHTML = `${pct}<small>%</small>`;

  const badgeEl = $('#ovChargeBadge');
  badgeEl.textContent = batt.charging ? 'USB 供电' : '电池供电';
  badgeEl.className = 'badge ' + (batt.charging ? 'green' : 'gray');

  const hours = power.estHours > 0 ? power.estHours.toFixed(1) + ' 小时' : '—';
  $('#ovBattInfo').innerHTML = `
    <div class="row"><span class="k">当前电流</span><span class="v">${power.currentMa || 0} mA</span></div>
    <div class="row"><span class="k">预估续航</span><span class="v">${hours}</span></div>
    <div class="row"><span class="k">电池容量</span><span class="v">${batt.mah || 1800} mAh</span></div>
    <div class="row"><span class="k">电池电压</span><span class="v">${((batt.voltage || 0) / 1000).toFixed(2)} V</span></div>`;
}

function renderInfo(ov) {
  const dev = ov.device || {};
  const latest = ov.latest || {};
  const rows = [
    ['设备名称', dev.name || '未命名'],
    ['IMEI', dev.imei || '—'],
    ['型号', latest.model || '—'],
    ['固件版本', latest.version || '—'],
    ['信号', (latest.rssi ?? 0) + ' dBm'],
    ['电压', ((latest.voltage || 0) / 1000).toFixed(2) + ' V'],
    ['ICCID', latest.iccid || '—'],
    ['开机时长', fmtDurationCN(latest.workTime || 0)]
  ];
  $('#ovInfo').innerHTML = rows.map(([k, v]) =>
    `<div><div class="k">${esc(k)}</div><div class="v" title="${esc(v)}">${esc(v)}</div></div>`).join('');
}
