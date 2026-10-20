/* 通话录音页（WebDAV） */

import { api } from '../api.js';
import { state, loadSettings, loadDevices } from '../store.js';
import { $, $$, esc, fmtSize, emptyState, toast, confirmDialog, goto, withBusy, badge } from '../ui.js';
import { icon, paintIcons } from '../icons.js';

export const meta = { crumb: '通信', name: '通话录音' };

let files = [];
let keyword = '';
let audio = null;
let playingFile = '';
let objectUrl = '';

export async function render(root) {
  await Promise.all([loadDevices(), loadSettings()]);
  root.innerHTML = shell();
  paintIcons(root);
  bind(root);
  await load(root);
}

function shell() {
  const wd = (state.settings && state.settings.webdav) || {};
  const configured = !!wd.url && !!wd.username;
  return `
  <div class="hero">
    <div><h1>通话录音</h1><p>设备端录音并上传至 WebDAV · 在线试听与下载</p></div>
    <div class="hero-actions">
      <button class="btn" id="recSync">${icon('refresh')}同步列表</button>
      <button class="btn primary" id="recSettings">${icon('sliders')}存储设置</button>
    </div>
  </div>

  <div class="card" style="margin-bottom:12px">
    <div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap">
      <span style="width:38px;height:38px;border-radius:12px;display:grid;place-items:center;background:${configured ? 'rgba(52,199,89,.13)' : 'var(--fill)'};color:${configured ? '#1f9d45' : 'var(--ink3)'};flex:none">
        ${icon('server')}
      </span>
      <div style="flex:1;min-width:190px">
        <div style="font-size:11.5px;font-weight:650">${configured ? 'WebDAV 存储已配置' : 'WebDAV 尚未配置'}</div>
        <div style="font-size:9.5px;color:var(--ink3);margin-top:3px;font-family:var(--mono)">${esc(wd.url || '前往「基本设置 → 存储配置」填写地址与账号')}${wd.dir ? ' / ' + esc(wd.dir) : ''}</div>
      </div>
      <div style="display:flex;gap:18px;flex-wrap:wrap">
        <div><div style="font-size:9px;color:var(--ink3)">录音文件</div><div style="font-size:11.5px;font-weight:650;margin-top:2px" id="recCount">—</div></div>
        <div><div style="font-size:9px;color:var(--ink3)">占用空间</div><div style="font-size:11.5px;font-weight:650;margin-top:2px" id="recSize">—</div></div>
      </div>
      <span class="badge ${configured ? 'green' : 'orange'}" id="recStatus">${configured ? '已连接' : '未配置'}</span>
    </div>
  </div>

  <div class="card filter-card" style="margin-bottom:12px">
    <div class="field grow"><label class="label">文件名 / 号码</label><input class="input" id="recSearch" placeholder="输入文件名或号码关键字"></div>
    <button class="btn primary" id="recQuery">${icon('search')}筛选</button>
    <button class="btn ghost" id="recReset">重置</button>
  </div>

  <div class="rec-grid" id="recGrid"><div class="skeleton" style="height:80px"></div><div class="skeleton" style="height:80px"></div></div>

  <div class="player" id="recPlayer">
    <button class="rec-play" id="recPlayerBtn">${icon('play')}</button>
    <div style="min-width:0;flex:1">
      <div class="rec-name" id="recPlayerName">未选择录音</div>
      <div class="track" style="margin-top:6px"><i id="recProgress"></i></div>
    </div>
    <span style="font-size:10px;color:var(--ink3);font-variant-numeric:tabular-nums" id="recPlayerTime">0:00 / 0:00</span>
    <button class="mini-btn" id="recPlayerClose" title="关闭">${icon('x')}</button>
  </div>`;
}

function bind(root) {
  $('#recSync', root).addEventListener('click', (e) => withBusy(e.currentTarget, () => load(root)));
  $('#recSettings', root).addEventListener('click', () => goto('settings', { set: 'store' }));
  $('#recSearch', root).addEventListener('input', (e) => { keyword = e.target.value.trim().toLowerCase(); renderGrid(); });
  $('#recReset', root).addEventListener('click', () => { keyword = ''; $('#recSearch', root).value = ''; renderGrid(); });
  $('#recQuery', root).addEventListener('click', renderGrid);

  audio = new Audio();
  audio.addEventListener('timeupdate', () => {
    const pct = audio.duration ? (audio.currentTime / audio.duration) * 100 : 0;
    const bar = $('#recProgress');
    if (bar) bar.style.width = pct.toFixed(1) + '%';
    const el = $('#recPlayerTime');
    if (el) el.textContent = `${fmtSec(audio.currentTime)} / ${fmtSec(audio.duration)}`;
  });
  audio.addEventListener('ended', () => { playingFile = ''; updatePlayerBtn(); });
  audio.addEventListener('pause', updatePlayerBtn);
  audio.addEventListener('play', updatePlayerBtn);

  $('#recPlayerBtn', root).addEventListener('click', () => {
    if (!audio.src) { toast('请先选择一条录音', true); return; }
    if (audio.paused) audio.play(); else audio.pause();
  });
  $('#recPlayerClose', root).addEventListener('click', () => {
    audio.pause();
    audio.removeAttribute('src');
    playingFile = '';
    $('#recPlayerName').textContent = '未选择录音';
    $('#recProgress').style.width = '0%';
    $('#recPlayerTime').textContent = '0:00 / 0:00';
  });
}

function fmtSec(s) {
  if (!isFinite(s)) return '0:00';
  const m = Math.floor(s / 60);
  const sec = Math.floor(s % 60);
  return `${m}:${String(sec).padStart(2, '0')}`;
}

/** 清洗 WebDAV 返回的错误：去掉 HTML 标签与换行，限制长度 */
function cleanErr(msg, fallback) {
  if (!msg) return fallback || 'WebDAV 连接失败';
  const t = String(msg).replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
  if (!t) return fallback || 'WebDAV 连接失败';
  return t.length > 150 ? t.slice(0, 150) + '…' : t;
}

async function load(root) {
  const box = $('#recGrid');
  try {
    const data = await api.recordings();
    if (!data.success) {
      files = [];
      box.innerHTML = emptyState(cleanErr(data.error, 'WebDAV 未配置或连接失败'), 'server');
      $('#recStatus').textContent = '连接失败';
      $('#recStatus').className = 'badge red';
      return;
    }
    files = data.files || [];
    const totalSize = files.reduce((s, f) => s + (f.size || 0), 0);
    $('#recCount').textContent = files.length + ' 个';
    $('#recSize').textContent = fmtSize(totalSize);
    renderGrid();
  } catch (err) {
    const msg = cleanErr(err.message, '录音列表加载失败');
    box.innerHTML = emptyState(msg, 'server');
    toast(msg, true);
  }
}

function renderGrid() {
  const box = $('#recGrid');
  const list = files.filter((f) => !keyword || f.name.toLowerCase().includes(keyword));
  if (!list.length) {
    box.innerHTML = emptyState(files.length ? '没有匹配的录音' : '录音目录为空，设备上传后会出现在这里', 'mic');
    return;
  }
  box.innerHTML = list.map((f) => `
    <div class="rec-card" data-file="${esc(f.name)}">
      <button class="rec-play" data-play="${esc(f.name)}" title="播放">${icon('play')}</button>
      <div class="rec-main">
        <div class="rec-name" title="${esc(f.name)}">${esc(f.name)}</div>
        <div class="rec-meta">${esc(f.modTime || '')} · ${fmtSize(f.size)}</div>
        <div class="wave">${waveBars(f.name)}</div>
      </div>
      <div style="display:flex;flex-direction:column;gap:3px">
        <button class="mini-btn" data-dl="${esc(f.name)}" title="下载">${icon('download')}</button>
        <button class="mini-btn" data-del="${esc(f.name)}" title="删除">${icon('trash')}</button>
      </div>
    </div>`).join('');
  paintIcons(box);

  $$('[data-play]', box).forEach((b) => b.addEventListener('click', () => play(b.dataset.play)));
  $$('[data-dl]', box).forEach((b) => b.addEventListener('click', () => download(b.dataset.dl)));
  $$('[data-del]', box).forEach((b) => b.addEventListener('click', () => remove(b.dataset.del)));
}

function waveBars(name) {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 9973;
  return Array.from({ length: 18 }, (_, i) => {
    h = (h * 1103515245 + 12345) % 2147483648;
    const height = 25 + (h % 70);
    return `<i style="height:${height}%"></i>`;
  }).join('');
}

async function play(file) {
  const name = file.replace(/\.[^.]+$/, '');
  if (playingFile === file && !audio.paused) { audio.pause(); return; }
  $('#recPlayerName').textContent = name;
  try {
    const blob = await api.recordingBlob(file);
    if (objectUrl) URL.revokeObjectURL(objectUrl);
    objectUrl = URL.createObjectURL(blob);
    audio.src = objectUrl;
    playingFile = file;
    await audio.play();
    toast('正在播放：' + name);
  } catch (err) {
    toast(err.message, true);
  }
}

function updatePlayerBtn() {
  const btn = $('#recPlayerBtn');
  if (!btn) return;
  btn.innerHTML = icon(audio && !audio.paused ? 'pause' : 'play');
  paintIcons(btn);
}

async function download(file) {
  try {
    const blob = await api.recordingBlob(file);
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = file;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 3000);
    toast('已开始下载');
  } catch (err) { toast(err.message, true); }
}

async function remove(file) {
  const ok = await confirmDialog('删除录音', `确认删除 WebDAV 上的「<b>${esc(file)}</b>」？`, { okText: '删除', danger: true });
  if (!ok) return;
  try {
    const res = await api.deleteRecording(file);
    if (!res.success) { toast(res.message || '删除失败', true); return; }
    if (playingFile === file) { audio.pause(); audio.removeAttribute('src'); playingFile = ''; }
    toast('录音已删除');
    await load(document.getElementById('content'));
  } catch (err) { toast(err.message, true); }
}
