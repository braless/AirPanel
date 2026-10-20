/* 全局状态：设备、当前设备、设置缓存 */

import { api } from './api.js';
import { $ } from './ui.js';
import { paintIcons } from './icons.js';

const IMEI_KEY = 'airpanel.v2.imei';

export const state = {
  username: 'admin',
  devices: [],
  imei: localStorage.getItem(IMEI_KEY) || '',
  settings: null,
  channels: null,
  page: 'overview',
  health: null
};

export function activeDevice() {
  return state.devices.find((d) => d.imei === state.imei) || state.devices[0] || null;
}

export function deviceName(imei) {
  const d = state.devices.find((x) => x.imei === imei);
  return d && d.name ? d.name : imei || '—';
}

export function onlineCount() {
  return state.devices.filter((d) => d.connected).length;
}

export function setImei(imei) {
  state.imei = imei || '';
  localStorage.setItem(IMEI_KEY, state.imei);
  syncShell();
}

export async function loadDevices() {
  state.devices = await api.devices() || [];
  if (!state.devices.some((d) => d.imei === state.imei)) {
    const online = state.devices.find((d) => d.connected);
    state.imei = (online || state.devices[0] || {}).imei || '';
    localStorage.setItem(IMEI_KEY, state.imei);
  }
  syncShell();
  return state.devices;
}

export async function loadSettings(force) {
  if (!state.settings || force) state.settings = await api.settings();
  return state.settings;
}

export async function loadChannels() {
  if (!state.channels) state.channels = await api.notifyChannels();
  return state.channels;
}

/** 同步侧栏 / 顶栏中的设备信息 */
export function syncShell() {
  const dev = activeDevice();
  const countEl = $('#navDevCount');
  if (countEl) countEl.textContent = String(state.devices.length);

  const nameEl = $('#topDeviceName');
  if (nameEl) nameEl.textContent = dev ? (dev.name || dev.imei) : '未添加设备';

  const dot = $('#topDeviceDot');
  if (dot) dot.classList.toggle('off', !(dev && dev.connected));

  const statusText = $('#statusText');
  if (statusText) statusText.textContent = `${onlineCount()} 台在线`;
}

/** 刷新顶栏设备下拉（供 app.js 调用） */
export function renderDevicePicker() {
  return state.devices.map((d) => `
    <div class="cmd-card" data-pick="${d.imei}">
      <div class="tile" style="background:${d.connected ? 'rgba(52,199,89,.14)' : 'var(--fill)'};color:${d.connected ? '#1f9d45' : 'var(--ink3)'}">
        <i class="ic" data-i="cpu"></i>
      </div>
      <div style="min-width:0">
        <div class="t">${d.name || d.imei}</div>
        <div class="c">${d.connected ? '在线' : '离线'} · ${d.imei}</div>
      </div>
    </div>`).join('');
}

/** 供页面渲染后统一重绘图标 */
export function repaint(root) {
  paintIcons(root || document);
}
