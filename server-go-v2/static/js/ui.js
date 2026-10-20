/* 通用 UI 工具：DOM、格式化、提示、弹层 */

import { paintIcons, icon } from './icons.js';

export const $ = (sel, root) => (root || document).querySelector(sel);
export const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));

export function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/* ---------- 时间 / 数值 ---------- */
export function fmtTime(ts) {
  if (!ts) return '—';
  const d = new Date(ts * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

export function fmtFull(ts) {
  if (!ts) return '—';
  const d = new Date(ts * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

export function fmtClock(ts) {
  if (!ts) return '--:--:--';
  const d = new Date(ts * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

export function fmtDur(sec) {
  if (!sec || sec < 0) return '—';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

export function fmtDurationCN(sec) {
  if (!sec || sec < 0) return '—';
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  if (d > 0) return `${d} 天 ${h} 小时`;
  if (h > 0) return `${h} 小时 ${m} 分`;
  return `${m} 分`;
}

export function fmtSize(bytes) {
  if (!bytes || bytes <= 0) return '—';
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  return (bytes / 1024 / 1024 / 1024).toFixed(2) + ' GB';
}

export function fmtNumber(n) {
  return Number(n || 0).toLocaleString('zh-CN');
}

/** YYYY-MM-DD → 当天 00:00 的 Unix 秒 */
export function dayStart(dateStr) {
  if (!dateStr) return 0;
  const d = new Date(dateStr + 'T00:00:00');
  return Math.floor(d.getTime() / 1000);
}

/** YYYY-MM-DD → 当天 23:59:59 的 Unix 秒 */
export function dayEnd(dateStr) {
  if (!dateStr) return 0;
  const d = new Date(dateStr + 'T23:59:59');
  return Math.floor(d.getTime() / 1000);
}

export function todayStr() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/* ---------- 状态渲染 ---------- */
export function emptyState(text, iconKey) {
  return `<div class="empty">${icon(iconKey || 'inbox')}<div>${esc(text)}</div></div>`;
}

export function loadingState(rows) {
  return Array.from({ length: rows || 3 }, () => '<div class="skeleton" style="margin:8px 0"></div>').join('');
}

export function badge(text, tone) {
  return `<span class="badge ${tone || ''}">${esc(text)}</span>`;
}

/* ---------- 跨页跳转（由 app.js 监听） ---------- */
export function goto(page, opts) {
  window.dispatchEvent(new CustomEvent('app:goto', { detail: Object.assign({ page }, opts || {}) }));
}

/* ---------- 提示 ---------- */let toastTimer = null;
export function toast(msg, isError) {
  const box = $('#toast');
  if (!box) return;
  $('#toastText').textContent = msg;
  box.classList.toggle('err', !!isError);
  box.querySelector('.ic').dataset.i = isError ? 'info' : 'check';
  paintIcons(box);
  box.classList.add('on');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => box.classList.remove('on'), 2400);
}

/* ---------- 弹层 ---------- */
export function openModal({ title, sub, body, foot, wide }) {
  $('#modalTitle').textContent = title || '';
  $('#modalSub').textContent = sub || '';
  $('#modalBody').innerHTML = body || '';
  $('#modalFoot').innerHTML = foot || '<button class="btn ghost" data-close>关闭</button>';
  $('.modal-panel').style.width = wide ? 'min(760px, 100%)' : 'min(580px, 100%)';
  paintIcons($('#modal'));
  $('#modal').classList.add('open');
  return $('#modal');
}

export function closeModal() {
  $('#modal').classList.remove('open');
}

/** 确认框，返回 Promise<boolean> */
export function confirmDialog(title, message, { okText = '确认', danger = false } = {}) {
  return new Promise((resolve) => {
    openModal({
      title,
      sub: '该操作不可撤销',
      body: `<div style="font-size:12px;line-height:1.75">${message}</div>`,
      foot: `<button class="btn ghost" data-close>取消</button>
             <button class="btn ${danger ? 'danger' : 'primary'}" id="confirmOk">${esc(okText)}</button>`
    });
    const ok = $('#confirmOk');
    ok.addEventListener('click', () => { closeModal(); resolve(true); });
    $('#modal').addEventListener('click', function onClose(e) {
      if (e.target.closest('[data-close]')) {
        $('#modal').removeEventListener('click', onClose);
        resolve(false);
      }
    });
  });
}

/** 按钮忙碌态 */
export async function withBusy(btn, fn) {
  if (!btn) return fn();
  const html = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = '<i class="ic spin" data-i="refresh"></i>处理中…';
  paintIcons(btn);
  try {
    return await fn();
  } finally {
    btn.disabled = false;
    btn.innerHTML = html;
    paintIcons(btn);
  }
}

/* 全局关闭按钮 */
document.addEventListener('click', (e) => {
  const t = e.target;
  if (t && typeof t.closest === 'function' && t.closest('[data-close]')) closeModal();
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeModal();
});
