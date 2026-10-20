/* 应用入口：登录、路由、外壳交互、外观设置 */

import { api, getToken, setToken, clearToken } from './api.js';
import { $, $$, esc, toast, openModal, closeModal, confirmDialog, withBusy, fmtDurationCN } from './ui.js';
import { paintIcons, icon } from './icons.js';
import { state, loadDevices, loadSettings, setImei, renderDevicePicker, syncShell, onlineCount } from './store.js';

import * as overview from './pages/overview.js';
import * as devices from './pages/devices.js';
import * as calls from './pages/calls.js';
import * as sms from './pages/sms.js';
import * as recordings from './pages/recordings.js';
import * as tasks from './pages/tasks.js';
import * as schedules from './pages/schedules.js';
import * as tasklog from './pages/tasklog.js';
import * as logs from './pages/logs.js';
import * as block from './pages/block.js';
import * as settings from './pages/settings.js';

const PAGES = {
  overview, devices, calls, sms, recordings,
  tasks, schedules, tasklog, logs, block, settings
};

/* ==================== 外观 ==================== */
const UI_KEY = 'airpanel.v2.ui';
const BRAND_KEY = 'airpanel.v2.brand';
const DEFAULT_TITLE = 'AirPanel';

/* 内置默认 Logo（信号波形 + 渐变底），作为 favicon 与品牌位兜底 */
const DEFAULT_LOGO = 'data:image/svg+xml,' + encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
  + '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
  + '<stop offset="0" stop-color="#0A84FF"/><stop offset="1" stop-color="#5E5CE6"/></linearGradient></defs>'
  + '<rect width="64" height="64" rx="16" fill="url(#g)"/>'
  + '<path d="M19 45a3.2 3.2 0 1 0 6.4 0 3.2 3.2 0 0 0-6.4 0Zm0-11.5A14.7 14.7 0 0 1 33.7 48.2h6.1A20.8 20.8 0 0 0 19 27.4v6.1Zm0-11.5A26.2 26.2 0 0 1 45.2 48.2H51A32 32 0 0 0 19 16.2v5.8Z" fill="#fff"/>'
  + '</svg>'
);

const ui = Object.assign(
  { theme: 'light', glass: 58, density: 'standard', accent: '#0A84FF' },
  JSON.parse(localStorage.getItem(UI_KEY) || '{}')
);

/* 品牌：优先服务端设置，未登录时用本地缓存，避免刷新瞬间闪回默认标题 */
function brandOf() {
  const remote = (state.settings && state.settings.brand) || {};
  const cached = JSON.parse(localStorage.getItem(BRAND_KEY) || '{}');
  const title = (remote.title || cached.title || '').trim();
  const logo = remote.logo || cached.logo || '';
  return { title: title || DEFAULT_TITLE, logo: logo || DEFAULT_LOGO };
}

/** 把品牌应用到网页标题、标签页图标、侧栏与登录页 */
function applyBrand() {
  const { title, logo } = brandOf();
  localStorage.setItem(BRAND_KEY, JSON.stringify({ title, logo: logo === DEFAULT_LOGO ? '' : logo }));

  const pageName = ($('#pageName') || {}).textContent || '';
  document.title = pageName ? `${pageName} · ${title}` : title;

  const fav = $('#favicon');
  if (fav) fav.href = logo;
  const apple = $('#appleIcon');
  if (apple) apple.href = logo;

  const nameEl = $('#brandName');
  if (nameEl) nameEl.textContent = title;
  const loginTitle = $('#loginTitle');
  if (loginTitle) loginTitle.textContent = title;

  // 有自定义 Logo 时替换字母占位块
  const custom = logo !== DEFAULT_LOGO;
  [['brandMark', 'brand-mark'], ['loginLogo', 'login-logo']].forEach(([id]) => {
    const el = document.getElementById(id);
    if (!el) return;
    if (custom) {
      el.classList.add('has-img');
      el.style.backgroundImage = `url("${logo}")`;
      el.textContent = '';
    } else {
      el.classList.remove('has-img');
      el.style.backgroundImage = '';
      el.textContent = (title || DEFAULT_TITLE).slice(0, 1).toUpperCase();
    }
  });
}

/** 侧栏底部：服务端在线状态与运行时长 */
async function syncServerStatus() {
  const titleEl = $('#srvTitle');
  const subEl = $('#srvSub');
  const dot = $('#srvDot');
  try {
    const h = await api.health();
    state.health = h;
    if (dot) dot.classList.remove('off');
    if (titleEl) titleEl.textContent = '服务端在线';
    if (subEl) subEl.textContent = `已运行 ${fmtDurationCN(h.uptimeSec)}`;
  } catch {
    if (dot) dot.classList.add('off');
    if (titleEl) titleEl.textContent = '服务端离线';
    if (subEl) subEl.textContent = '无法连接';
  }
}

function applyUI() {
  document.documentElement.dataset.theme = ui.theme;
  document.documentElement.style.setProperty('--ga', String(0.35 + Number(ui.glass) / 100 * 1.15));
  document.documentElement.style.setProperty('--accent', ui.accent);
  document.body.dataset.density = ui.density;

  const seg = $('#themeSeg');
  if (seg) $$('button', seg).forEach((b) => b.classList.toggle('on', b.dataset.themeSet === ui.theme));
  const range = $('#glassRange');
  if (range) range.value = String(ui.glass);
  const out = $('#glassOut');
  if (out) out.textContent = ui.glass + '%';

  localStorage.setItem(UI_KEY, JSON.stringify(ui));
}

/* ==================== 登录 ==================== */
async function bootLogin() {
  applyUI();
  const form = $('#loginForm');
  const btn = $('#loginBtn');
  const errBox = $('#loginErr');
  const dot = $('#loginDot');
  const foot = $('#loginFoot');

  try {
    const h = await api.health();
    dot.classList.remove('off');
    foot.textContent = `服务端在线 · ${h.version || 'v2'} · 已运行 ${fmtDurationCN(h.uptimeSec)}`;
  } catch {
    dot.classList.add('off');
    foot.textContent = '无法连接服务端，请确认进程已启动';
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    errBox.textContent = '';
    const username = $('#loginUser').value.trim();
    const password = $('#loginPass').value;
    if (!username || !password) { errBox.textContent = '请填写用户名与密码'; return; }
    await withBusy(btn, async () => {
      try {
        const res = await api.login(username, password);
        setToken(res.token);
        state.username = res.username || username;
        await enterApp();
      } catch (err) {
        errBox.textContent = err.message;
      }
    });
  });

  // 已登录则直接进入
  if (getToken()) {
    try {
      await api.health();
      await enterApp();
    } catch {
      clearToken();
    }
  }
}

async function enterApp() {
  $('#loginView').classList.add('hidden');
  $('#appView').classList.remove('hidden');

  try {
    await loadDevices();
  } catch { /* 设备加载失败不阻塞进入 */ }
  try {
    await loadSettings();
  } catch { /* 设置失败仅影响设置页 */ }

  applyAccount();
  applyBrand();
  await syncServerStatus();
  await showPage(location.hash.replace('#', '') || 'overview');
}

function applyAccount() {
  const name = (state.settings && state.settings.username) || state.username || 'admin';
  const ch = name.slice(0, 1).toUpperCase();
  const avatar = $('#topAvatar');
  const acctAvatar = $('#acctAvatar');
  if (avatar) avatar.textContent = ch;
  if (acctAvatar) acctAvatar.textContent = ch;
  const acctName = $('#acctName');
  if (acctName) acctName.textContent = name;
}

/* ==================== 路由 ==================== */
let rendering = false;

async function showPage(key, opts) {
  if (!PAGES[key]) key = 'overview';
  state.page = key;
  const mod = PAGES[key];

  $$('#nav .nav-item').forEach((b) => b.classList.toggle('on', b.dataset.page === key));
  if (mod.meta) {
    $('#crumb').textContent = mod.meta.crumb || '';
    $('#pageName').textContent = mod.meta.name || '';
    applyBrand();
  }
  if (location.hash !== '#' + key) history.replaceState(null, '', '#' + key);
  closeSidebar();

  const content = $('#content');
  content.scrollTop = 0;
  rendering = true;
  try {
    await mod.render(content, opts || {});
  } catch (err) {
    content.innerHTML = `<div class="card"><div class="empty">${icon('info')}<div>页面加载失败：${esc(err.message)}</div></div></div>`;
    paintIcons(content);
  } finally {
    rendering = false;
  }
}

function closeSidebar() {
  $('#sidebar').classList.remove('open');
  $('#scrim').classList.remove('on');
}

/* ==================== 外壳交互 ==================== */
function bindShell() {
  $$('#nav .nav-item').forEach((b) => b.addEventListener('click', () => showPage(b.dataset.page)));

  $('#menuBtn').addEventListener('click', () => {
    $('#sidebar').classList.add('open');
    $('#scrim').classList.add('on');
  });
  $('#scrim').addEventListener('click', closeSidebar);

  // 视口变宽（横屏 / 平板）时收起抽屉，避免残留遮罩
  window.addEventListener('resize', () => {
    if (window.innerWidth > 980) closeSidebar();
  });

  // 顶栏设备切换
  $('#topDevice').addEventListener('click', () => {
    if (!state.devices.length) {
      openModal({
        title: '还没有设备',
        sub: '设备通过 MQTT 上报 online 后会自动出现在这里',
        body: `<div style="font-size:12px;color:var(--ink2);line-height:1.7">请在设备脚本中把 MQTT 地址指向本服务端，设备上线后会自动注册。</div>`
      });
      return;
    }
    openModal({
      title: '切换设备',
      sub: `共 ${state.devices.length} 台 · ${onlineCount()} 台在线`,
      body: `<div class="cmd-grid">${renderDevicePicker()}</div>`
    });
    paintIcons($('#modal'));
    $$('#modalBody [data-pick]').forEach((el) => el.addEventListener('click', () => {
      setImei(el.dataset.pick);
      closeModal();
      toast('已切换设备');
      showPage(state.page);
    }));
  });

  // 刷新
  $('#refreshBtn').addEventListener('click', async (e) => {
    await withBusy(e.currentTarget, async () => {
      try {
        await loadDevices();
        syncShell();
        await showPage(state.page);
        toast('已刷新');
      } catch (err) { toast(err.message, true); }
    });
  });

  // 外观弹层
  $('#appearanceBtn').addEventListener('click', (e) => {
    e.stopPropagation();
    $('#appearancePop').classList.toggle('open');
  });
  $('#appearancePop').addEventListener('click', (e) => e.stopPropagation());
  document.addEventListener('click', () => $('#appearancePop').classList.remove('open'));

  $$('#themeSeg button').forEach((b) => b.addEventListener('click', () => {
    ui.theme = b.dataset.themeSet;
    applyUI();
  }));
  $('#glassRange').addEventListener('input', (e) => {
    ui.glass = Number(e.target.value);
    applyUI();
  });

  // 退出
  $('#logoutBtn').addEventListener('click', async () => {
    const ok = await confirmDialog('退出登录', '退出后需要重新输入账号密码。', { okText: '退出登录' });
    if (!ok) return;
    try { await api.logout(); } catch { /* 忽略 */ }
    clearToken();
    location.reload();
  });

  // 重启
  $('#restartBtn').addEventListener('click', async () => {
    const ok = await confirmDialog('重启服务端', '重启期间面板会短暂不可用，约 3~10 秒后恢复。', { okText: '确认重启', danger: true });
    if (!ok) return;
    try {
      const res = await api.restart();
      if (res && res.success === false) toast(res.message || '当前平台不支持重启', true);
      else toast('服务端正在重启…');
    } catch (err) { toast(err.message, true); }
  });

  // 跨页跳转
  window.addEventListener('app:goto', (e) => {
    const d = e.detail || {};
    showPage(d.page, d);
  });

  // 设置页修改外观
  window.addEventListener('app:ui', (e) => {
    Object.assign(ui, e.detail || {});
    applyUI();
  });

  // 设置页修改品牌（标题 / Logo）
  window.addEventListener('app:brand', (e) => {
    const d = e.detail || {};
    if (!state.settings) state.settings = {};
    state.settings.brand = { title: d.title || '', logo: d.logo || '' };
    applyBrand();
  });

  // 登录失效
  window.addEventListener('auth:expired', () => {
    $('#appView').classList.add('hidden');
    $('#loginView').classList.remove('hidden');
    const errBox = $('#loginErr');
    if (errBox) errBox.textContent = '登录已失效，请重新登录';
  });

  // 顶栏在线数定时刷新
  setInterval(async () => {
    if (rendering || $('#appView').classList.contains('hidden')) return;
    try {
      await loadDevices();
      syncShell();
    } catch { /* 静默 */ }
  }, 30000);

  // 左下角运行时长：每分钟与服务端校准一次
  setInterval(() => {
    if ($('#appView').classList.contains('hidden')) return;
    syncServerStatus();
  }, 60000);
}

/* ==================== 启动 ==================== */
applyUI();
applyBrand();
bootLogin();
bindShell();
paintIcons(document);
