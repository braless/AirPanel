// 应用逻辑：登录、导航、设备列表、任务执行、任务记录、设置
(function () {
  'use strict';

  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));

  /* ---------- iOS27 图标库（SF Symbols 线稿 SVG） ---------- */
  const ICONS = {
    grid:'<rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/>',
    cpu:'<rect x="6.5" y="6.5" width="11" height="11" rx="2.5"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/>',
    bolt:'<path d="M13 2.5 5.5 13.5h5l-1 8 8-11.5h-5z"/>',
    clock:'<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5.5l3.5 2"/>',
    phone:'<path d="M6.2 3.8h3l1.4 3.6-1.8 1.4a12.5 12.5 0 0 0 5.4 5.4l1.4-1.8 3.6 1.4v3c0 1-.8 1.8-1.8 1.8C10.6 18.6 5.4 13.4 4.4 5.6c0-1 .8-1.8 1.8-1.8Z"/>',
    msg:'<path d="M4 5.5h16v11H9l-5 4z"/><path d="M8 9.5h8M8 12.5h5"/>',
    mic:'<rect x="9" y="3" width="6" height="10" rx="3"/><path d="M6 11a6 6 0 0 0 12 0M12 17v3M9 20h6"/>',
    list:'<path d="M8 6h12M8 12h12M8 18h12"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>',
    shield:'<path d="M12 3 5 6v6c0 4.2 3 7.2 7 9 4-1.8 7-4.8 7-9V6z"/><path d="m9 12 2 2 4-4"/>',
    gear:'<circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v3M12 18.2v3M2.8 12h3M18.2 12h3M5.5 5.5l2.1 2.1M16.4 16.4l2.1 2.1M18.5 5.5l-2.1 2.1M7.6 16.4l-2.1 2.1"/>',
    search:'<circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 4 4"/>',
    refresh:'<path d="M20 12a8 8 0 1 1-2.4-5.7"/><path d="M20 4v4h-4"/>',
    plus:'<path d="M12 5v14M5 12h14"/>',
    chevR:'<path d="m9 5 7 7-7 7"/>',
    more:'<circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/>',
    play:'<path d="M8 5.5v13l11-6.5z"/>',
    pause:'<path d="M8 5v14M16 5v14"/>',
    trash:'<path d="M4.5 7h15M9 7V5h6v2M6.5 7l1 13h9l1-13M10 11v5M14 11v5"/>',
    pencil:'<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4M4 20v-4"/>',
    check:'<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    x:'<path d="M6 6l12 12M18 6 6 18"/>',
    wifi:'<path d="M4 9a12 12 0 0 1 16 0M7 12.5a8 8 0 0 1 10 0M10 16a4 4 0 0 1 4 0"/><circle cx="12" cy="19" r="1"/>',
    battery:'<rect x="2.5" y="7.5" width="17" height="9" rx="3"/><path d="M21 11v2"/><path d="M6 10.5v3"/>',
    signal:'<path d="M4 20v-4M9 20v-8M14 20V7M19 20V4"/>',
    temp:'<path d="M10 14.5V5a2 2 0 1 1 4 0v9.5a4 4 0 1 1-4 0Z"/><path d="M12 9v6"/>',
    power:'<path d="M12 3v9"/><path d="M7.5 6.5a8 8 0 1 0 9 0"/>',
    key:'<circle cx="8" cy="12" r="4"/><path d="M12 12h8M17 12v3M20 12v2"/>',
    person:'<circle cx="12" cy="8" r="3.5"/><path d="M5 20c0-3.5 3-6 7-6s7 2.5 7 6"/>',
    bell:'<path d="M6 9a6 6 0 0 1 12 0c0 4 1.5 5.5 1.5 5.5h-15S6 13 6 9Z"/><path d="M10 18a2 2 0 0 0 4 0"/>',
    terminal:'<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="m7.5 9 3 3-3 3M13 15h4"/>',
    doc:'<path d="M7 3.5h6.5L18 8v12.5H7z"/><path d="M13.5 3.5V8H18M9.5 12h6M9.5 15.5h6"/>',
    sliders:'<path d="M4 7h6M14 7h6M4 17h10M18 17h2"/><circle cx="12" cy="7" r="2"/><circle cx="16" cy="17" r="2"/>',
    lightbulb:'<path d="M9 18h6M10 21h4"/><path d="M8.5 14.5a6 6 0 1 1 7 0c-.8.6-1 1.4-1 2.5h-5c0-1.1-.2-1.9-1-2.5Z"/>',
    wave:'<path d="M3 12h2l2-6 3 12 3-9 2 5 2-3h4"/>',
    cal:'<rect x="3.5" y="5.5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3.5v4M16 3.5v4"/>',
    palette:'<path d="M12 3a9 9 0 1 0 0 18h1.5a2 2 0 0 0 0-4H13a2 2 0 0 1 0-4h4a4 4 0 0 0 4-4c0-3.3-4-6-9-6Z"/><circle cx="7.5" cy="10" r="1"/><circle cx="10" cy="6.5" r="1"/><circle cx="14" cy="6.5" r="1"/>',
    logout:'<path d="M10 4H5v16h5M15 8l4 4-4 4M19 12H9"/>',
    restart:'<path d="M20 12a8 8 0 1 1-2.4-5.7"/><path d="M20 4v4h-4"/>',
    info:'<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.01"/>',
    copy:'<rect x="8" y="8" width="12" height="12" rx="3"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
    upload:'<path d="M12 16V4M7 9l5-5 5 5M4 20h16"/>',
    download:'<path d="M12 3v12M7 10l5 5 5-5M4 20h16"/>',
    chevD:'<path d="m5 9 7 7 7-7"/>',
    chevL:'<path d="m15 5-7 7 7 7"/>'
  };
  const FILLED = new Set(['bolt', 'play', 'pause', 'signal']);
  function paintIcons(root) {
    (root || document).querySelectorAll('.ic[data-i]').forEach((el) => {
      const body = ICONS[el.dataset.i];
      if (!body) return;
      const fill = FILLED.has(el.dataset.i);
      el.innerHTML = '<svg viewBox="0 0 24 24" fill="' + (fill ? 'currentColor' : 'none') +
        '" stroke="' + (fill ? 'none' : 'currentColor') + '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>';
    });
  }

  let currentPage = 'devices';
  let devices = [];
  let currentDevice = null;

  // ---------------- 工具函数 ----------------

  function fmtTime(ts) {
    if (!ts) return '—';
    const d = new Date(ts * 1000);
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  }

  function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }

  let toastTimer = null;
  function toast(msg, ok = true) {
    const el = $('#toast');
    $('#toast-text').textContent = msg;
    const ic = el.querySelector('.ic');
    if (ic) ic.style.color = ok ? '' : 'var(--red)';
    el.classList.add('on');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('on'), 3000);
  }

  // ---------------- 登录 / 登出 ----------------

  async function handleLogin(e) {
    e.preventDefault();
    const username = $('#login-username').value.trim();
    const password = $('#login-password').value;
    const errEl = $('#login-error');
    errEl.classList.add('hidden');
    const btn = $('#login-btn');
    btn.disabled = true;
    btn.textContent = '登录中...';
    try {
      const data = await API.login(username, password);
      API.setToken(data.token);
      localStorage.setItem('panel_username', username);
      enterMain();
    } catch (err) {
      errEl.textContent = err.message;
      errEl.classList.remove('hidden');
    } finally {
      btn.disabled = false;
      btn.textContent = '登 录';
    }
  }

  async function handleLogout() {
    try { await API.logout(); } catch (_) { /* 忽略 */ }
    API.clearToken();
    showLogin();
  }

  // 重启服务端：确认后调用 /api/restart，提示后等待服务恢复并自动刷新
  async function handleServerRestart() {
    const ok = await showConfirm('确定重启服务端吗？设备将短暂断线并自动重连，页面稍后自动刷新。');
    if (!ok) return;
    const btn = $('#restart-btn');
    const oldText = btn.textContent;
    btn.disabled = true; btn.textContent = '重启中...';
    try {
      await API.restart();
      toast('正在重启服务端，稍后自动刷新...');
      // 轮询 /api/health，服务恢复后刷新页面
      let waited = 0;
      const poll = async () => {
        try {
          const r = await fetch('/api/health', { cache: 'no-store' });
          if (r.ok) { location.reload(); return; }
        } catch (_) { /* 服务未就绪 */ }
        if (waited < 60) { waited += 2; setTimeout(poll, 2000); }
        else { btn.disabled = false; btn.textContent = oldText; toast('重启超时，请手动刷新', false); }
      };
      setTimeout(poll, 3000);
    } catch (err) {
      btn.disabled = false; btn.textContent = oldText;
      toast(err.message, false);
    }
  }

  // 格式化时长（秒 -> X天X小时X分钟）
  function fmtDuration(sec) {
    sec = Math.max(0, Math.floor(sec));
    const d = Math.floor(sec / 86400);
    const h = Math.floor((sec % 86400) / 3600);
    const m = Math.floor((sec % 3600) / 60);
    let r = '';
    if (d) r += d + '天';
    if (h) r += h + '小时';
    if (m || (!d && !h)) r += m + '分钟';
    return r || '0分钟';
  }

  // 顶部 Logo hover 显示"已运行时长"浮层
  function bindBrandUptime() {
    const logo = $('#brand-logo');
    if (!logo) return;
    const tip = document.createElement('div');
    tip.id = 'uptime-tip';
    tip.classList.add('hidden');
    document.body.appendChild(tip);
    let uptimeSec = 0;
    let lastFetch = 0;
    logo.addEventListener('mouseenter', async () => {
      if (Date.now() - lastFetch > 15000) {
        lastFetch = Date.now();
        try {
          const d = await (await fetch('/api/health', { cache: 'no-store' })).json();
          uptimeSec = d.uptimeSec || 0;
        } catch (_) { /* 保留上次值 */ }
      }
      tip.textContent = '已运行时长：' + fmtDuration(uptimeSec);
      tip.classList.remove('hidden');
    });
    logo.addEventListener('mousemove', (e) => {
      if (tip.classList.contains('hidden')) return;
      let x = e.clientX + 12, y = e.clientY + 12;
      if (x + tip.offsetWidth > window.innerWidth - 8) x = e.clientX - tip.offsetWidth - 12;
      if (y + tip.offsetHeight > window.innerHeight - 8) y = Math.max(8, e.clientY - tip.offsetHeight - 12);
      tip.style.left = x + 'px';
      tip.style.top = y + 'px';
    });
    logo.addEventListener('mouseleave', () => tip.classList.add('hidden'));
  }

  function showLogin() {
    toggleSidebar(false);
    $('#main-view').classList.add('hidden');
    $('#login-view').classList.remove('hidden');
    $('#login-password').value = '';
  }

  async function enterMain() {
    $('#login-view').classList.add('hidden');
    $('#main-view').classList.remove('hidden');
    const uname = localStorage.getItem('panel_username') || 'admin';
    $('#m-user-name').textContent = uname;
    applyBrandUI();
    loadUiSettings();
    await loadDevices();
    switchPage('overview'); // 默认进入设备概览
  }

  // ---------------- 界面自定义（标题/头像 Logo） ----------------
  function applyBrandUI() {
    const title = localStorage.getItem('brand_title') || 'AirPanel';
    const logo = localStorage.getItem('brand_logo') || '';
    $('#brand-title').textContent = title;
    $('#m-brand-title').textContent = title;
    document.title = title + ' 管理面板';
    const el = $('#brand-logo');
    el.style.overflow = 'hidden'; el.style.padding = '0';
    if (/^https?:\/\//i.test(logo)) {
      el.innerHTML = '<img src="' + logo + '" alt="logo" style="width:100%;height:100%;object-fit:cover">';
    } else {
      el.style.overflow = ''; el.style.padding = '';
      el.textContent = logo || 'A';
    }
  }

  function loadUiSettings() {
    $('#ui-title').value = localStorage.getItem('brand_title') || 'AirPanel';
    $('#ui-logo').value = localStorage.getItem('brand_logo') || '';
    updateUiPreview();
  }

  function updateUiPreview() {
    const v = $('#ui-logo').value.trim();
    const p = $('#ui-logo-preview');
    p.style.overflow = 'hidden'; p.style.padding = '0';
    if (/^https?:\/\//i.test(v)) {
      p.innerHTML = '<img src="' + v + '" alt="logo" style="width:100%;height:100%;object-fit:cover">';
    } else {
      p.style.overflow = ''; p.style.padding = '';
      p.textContent = v || 'A';
    }
  }

  function saveUiSettings() {
    const title = $('#ui-title').value.trim() || 'AirPanel';
    const logo = $('#ui-logo').value.trim();
    localStorage.setItem('brand_title', title);
    localStorage.setItem('brand_logo', logo);
    applyBrandUI();
    $('#ui-msg').textContent = '已保存';
    $('#ui-msg').className = 'text-sm text-emerald-600';
    toast('界面设置已保存');
  }

  function resetUiSettings() {
    localStorage.removeItem('brand_title');
    localStorage.removeItem('brand_logo');
    $('#ui-title').value = 'AirPanel';
    $('#ui-logo').value = '';
    updateUiPreview();
    applyBrandUI();
    $('#ui-msg').textContent = '已恢复默认';
    $('#ui-msg').className = 'text-sm text-emerald-600';
  }

  // ---------------- 导航 ----------------

  // 移动端抽屉开关（内联样式避免依赖 Tailwind 未生成的工具类）
  function toggleSidebar(open) {
    $('#sidebar').classList.toggle('open', !!open);
    $('#sidebar-overlay').classList.toggle('on', !!open);
  }

  const PAGE_META = {
    overview: ['监控', '设备概览'], devices: ['监控', '设备列表'],
    calls: ['通信', '通话记录'], sms: ['通信', '短信记录'], recordings: ['通信', '通话录音'],
    tasks: ['自动化', '任务执行'], schedules: ['自动化', '定时任务'], logs: ['自动化', '任务记录'],
    logcenter: ['系统', '日志中心'], block: ['系统', '屏蔽配置'], settings: ['系统', '基本设置'],
  };

  function switchPage(name) {
    currentPage = name;
    $$('.page').forEach((s) => s.classList.toggle('on', s.id === 'page-' + name));
    $$('.nav-item').forEach((a) => a.classList.toggle('on', a.dataset.nav === name));
    const meta = PAGE_META[name];
    if (meta) { $('#crumb').textContent = meta[0]; $('#pageName').textContent = meta[1]; }
    if (name === 'devices') loadDevices();
    if (name === 'overview') { fillOverviewDevice(); loadOverview(); }
    if (name === 'tasks') renderDeviceSelect();
    if (name === 'schedules') { renderSchDeviceSelect(); renderSchTaskSelect(); onSchCycleChange(); onSchTaskChange(); loadSchedules(); }
    if (name === 'calls') { fillRecordImeiFilter('#calls-filter-imei'); loadCalls(); }
    if (name === 'sms') { fillRecordImeiFilter('#sms-filter-imei'); loadSms(); }
    if (name === 'recordings') loadRecordings();
    if (name === 'logcenter') { fillRecordImeiFilter('#log-filter-imei'); loadLogs(); }
    if (name === 'logs') loadTasks();
    if (name === 'block') loadBlockRules();
    if (name === 'settings') {
      const uname = localStorage.getItem('panel_username') || 'admin';
      const cur = $('#set-current-username');
      if (cur) {
        cur.value = uname;
        $('#set-new-username').placeholder = '当前：' + uname;
      }
      loadNotifySettings();
      loadStoreSettings();
    }
  }

  // ---------------- 设备概览 ----------------

  function fillOverviewDevice() {
    const sel = $('#overview-device');
    if (!sel) return;
    const prev = sel.value;
    if (!devices.length) {
      sel.innerHTML = '<option value="">暂无设备</option>';
      return;
    }
    sel.innerHTML = devices.map((d) =>
      `<option value="${esc(d.imei)}" ${d.imei === prev ? 'selected' : ''}>${d.name ? esc(d.name) + ' · ' : ''}${esc(d.imei)}（${esc(d.phone || '未知')}）${d.connected ? '' : ' [离线]'}</option>`).join('');
    if (prev) sel.value = prev;
    else if (devices.length === 1) sel.value = devices[0].imei;
  }

  function fmtDur(sec) {
    if (sec === null || sec === undefined || sec < 0) return '—';
    sec = sec | 0;
    const d = Math.floor(sec / 86400);
    const h = Math.floor((sec % 86400) / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (d > 0) return `${d}天 ${h}小时`;
    if (h > 0) return `${h}小时 ${m}分`;
    if (m > 0) return `${m}分 ${s}秒`;
    return `${s}秒`;
  }

  async function loadOverview() {
    const sel = $('#overview-device');
    const imei = sel ? sel.value : '';
    const empty = $('#overview-empty');
    const body = $('#overview-body');
    if (!imei) {
      if (empty) { empty.classList.remove('hidden'); $('#overview-empty-text').textContent = '请选择设备查看概览'; }
      if (body) body.classList.add('hidden');
      return;
    }
    try {
      const data = await API.getOverview(imei);
      if (empty) empty.classList.add('hidden');
      if (body) body.classList.remove('hidden');
      renderOverview(data);
    } catch (err) {
      if (empty) { empty.classList.remove('hidden'); $('#overview-empty-text').textContent = '加载失败：' + err.message; }
      if (body) body.classList.add('hidden');
    }
  }

  function renderOverview(data) {
    const dev = data.device || {};
    const lat = data.latest;
    const bat = data.battery || {};
    const pow = data.power || {};

    // 信号
    const rssi = lat ? (lat.rssi ?? '—') : '—';
    const rsrp = lat ? (lat.rsrp ?? '—') : '—';
    $('#ov-rssi').textContent = rssi === '—' ? '—' : rssi + ' dBm';
    $('#ov-rsrp').textContent = 'RSRP ' + (rsrp === '—' ? '—' : rsrp + ' dBm');
    const csqBadge = $('#ov-csq-badge');
    if (lat && lat.csq !== undefined) {
      csqBadge.textContent = lat.csq + ' 格';
      csqBadge.className = lat.csq >= 12 ? 'badge-online' : (lat.csq >= 8 ? 'badge-online' : 'badge-offline');
    } else {
      csqBadge.textContent = '—';
      csqBadge.className = 'badge-online';
    }

    // 电池
    $('#ov-battery-pct').textContent = bat.percent !== undefined ? bat.percent + '%' : '—';
    $('#ov-voltage').textContent = '电压 ' + (bat.voltage ? (bat.voltage / 1000).toFixed(2) + ' V' : '—');
    $('#ov-charge-badge').classList.toggle('hidden', !bat.charging);

    // 温度/网络
    $('#ov-temp').textContent = lat && lat.temperature !== undefined ? lat.temperature + ' ℃' : '—';
    $('#ov-net').textContent = '网络 ' + (lat && lat.netMode ? lat.netMode : '—');

    // 在线/开机
    $('#ov-online').textContent = fmtDur(data.onlineSeconds);
    $('#ov-uptime').textContent = '开机 ' + fmtDur(lat ? lat.workTime : null);

    // 电流/续航
    $('#ov-current-note').textContent = (pow.avgCurrentMa > 0) ? '已配置实测值覆盖' : '基于功耗模型估算';
    $('#ov-esthours').textContent = (pow.estHours > 0) ? pow.estHours.toFixed(1) + ' 小时' : '—';
    $('#ov-esthours-note').textContent = (bat.percent > 0) ? `按剩余 ${(bat.mah * bat.percent / 100).toFixed(0)} mAh 估算` : '电量未知，暂无法估算';

    // 设备状态
    $('#ov-status').textContent = dev.connected ? '在线' : '离线';
    const stNote = $('#ov-status-note');
    if (stNote) {
      stNote.textContent = dev.connected
        ? '最近活跃 ' + fmtTime(dev.lastSeen)
        : '最后在线 ' + fmtTime(dev.lastSeen);
    }

    // 设备信息网格
    const info = [
      ['IMEI', dev.imei || '—'],
      ['备注', dev.name || '—'],
      ['手机号', dev.phone || '—'],
      ['运营商', lat && lat.operator || '—'],
      ['本机号码', lat && lat.number || '—'],
      ['SIM 卡槽', lat && lat.simSlot || '—'],
      ['IMSI', lat && lat.imsi || '—'],
      ['ICCID', lat && lat.iccid || '—'],
      ['网络制式', lat && lat.netMode || '—'],
      ['固件版本', lat && lat.version || '—'],
      ['模块型号', lat && lat.model || '—'],
      ['SN', lat && lat.sn || '—'],
      ['首次接入', fmtTime(dev.firstSeen)],
      ['本次上线', fmtTime(data.connectedAt)],
      ['最后上报', fmtTime(lat && lat.createdAt)],
      ['上报间隔', '—'],
    ];
    $('#ov-info-grid').innerHTML = info.map(([k, v]) =>
      `<div><div class="k">${esc(k)}</div><div class="v">${esc(v)}</div></div>`).join('');

    // 配置回填
    $('#ov-battery-mah').value = bat.mah || 1800;
    $('#ov-current-ma').value = pow.avgCurrentMa || 0;

    renderOverviewChart(data.history);
  }

  function renderOverviewChart(history) {
    const el = $('#overview-chart');
    if (!el) return;
    if (!history || history.length < 2) {
      el.innerHTML = '<div class="ov-empty">暂无足够的遥测数据，等待设备上报</div>';
      return;
    }
    const W = 720, H = 210, pad = 12;
    const n = history.length;
    const xs = (i) => pad + (n === 1 ? 0 : i / (n - 1)) * (W - pad * 2);
    const rMin = -120, rMax = -40;
    const yr = (v) => pad + (1 - (v - rMin) / (rMax - rMin)) * (H - pad * 2);
    const vMin = 3.3, vMax = 4.3;
    const yv = (v) => pad + (1 - (v - vMin) / (vMax - vMin)) * (H - pad * 2);
    const temps = history.map(h => h.temperature).filter(t => t !== null && t !== undefined);
    let tMin = temps.length ? Math.min(...temps) : 20;
    let tMax = temps.length ? Math.max(...temps) : 60;
    if (tMax - tMin < 2) { tMax = tMin + 2; }
    const yt = (v) => pad + (1 - (v - tMin) / (tMax - tMin)) * (H - pad * 2);

    const line = (arr, ymap) => arr.map((v, i) => {
      const x = xs(i); const y = ymap(v);
      return (i === 0 ? 'M' : 'L') + x.toFixed(1) + ',' + y.toFixed(1);
    }).join(' ');
    const poly = (arr, ymap) => line(arr, ymap) + ' L' + xs(n - 1).toFixed(1) + ',' + (H - pad) + ' L' + xs(0).toFixed(1) + ',' + (H - pad) + ' Z';

    const rssiArr = history.map(h => h.rssi ?? 0);
    const voltArr = history.map(h => (h.voltage ?? 0) / 1000);
    const tempArr = history.map(h => h.temperature ?? 0);

    el.innerHTML = `<svg viewBox="0 0 ${W} ${H}" style="width:100%;height:auto" preserveAspectRatio="none">
      ${[0.25, 0.5, 0.75].map(t => `<line x1="${pad}" y1="${(pad + t * (H - 2 * pad)).toFixed(1)}" x2="${W - pad}" y2="${(pad + t * (H - 2 * pad)).toFixed(1)}" stroke="var(--hair)" stroke-width="1"/>`).join('')}
      <path d="${poly(rssiArr, yr)}" fill="var(--accent)" fill-opacity="0.08"/>
      <path d="${line(rssiArr, yr)}" fill="none" stroke="var(--accent)" stroke-width="2"/>
      <path d="${line(voltArr, yv)}" fill="none" stroke="var(--green)" stroke-width="2"/>
      <path d="${line(tempArr, yt)}" fill="none" stroke="var(--orange)" stroke-width="2"/>
    </svg>`;
  }

  async function saveOverviewConfig() {
    const batteryMah = parseInt($('#ov-battery-mah').value, 10) || 1800;
    const avgCurrentMa = parseInt($('#ov-current-ma').value, 10) || 0;
    try {
      const data = await API.saveOverviewConfig({ batteryMah, avgCurrentMa });
      toast(data.message || '保存成功');
      loadOverview();
    } catch (err) { toast(err.message); }
  }

  // ---------------- 设备列表 ----------------

  async function loadDevices() {
    const btn = $('#refresh-devices');
    const timeEl = $('#refresh-devices-time');
    if (btn) { btn.disabled = true; btn.textContent = '刷新中...'; }
    try {
      devices = await API.userPool();
      renderDevices();
      renderDeviceSelect();
      if (timeEl) {
        const d = new Date();
        const p = (n) => String(n).padStart(2, '0');
        timeEl.textContent = '上次刷新 ' + `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
      }
    } catch (err) {
      const dl = $('#devList');
      if (dl) dl.innerHTML = `<div style="padding:24px 12px;text-align:center;font-size:11px;color:var(--red)">${esc(err.message)}</div>`;
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = '刷新'; }
    }
  }

  // 设备页：左侧设备列表（搜索/过滤）+ 右侧详情（原型 devices-layout）
  function renderDevices() {
    const q = ((($('#devSearch') || {}).value) || '').trim().toLowerCase();
    const fbtn = $('#devFilter .on');
    const f = fbtn ? fbtn.dataset.f : 'all';
    const list = devices.filter((d) => {
      if (f === 'online' && !d.connected) return false;
      if (f === 'offline' && d.connected) return false;
      if (q && !((d.name || '') + d.imei + (d.phone || '')).toLowerCase().includes(q)) return false;
      return true;
    });
    if (!currentDevice && devices.length) currentDevice = devices[0].imei;
    if (currentDevice && !devices.some((d) => d.imei === currentDevice)) currentDevice = null;
    const box = $('#devList');
    if (!box) return;
    box.innerHTML = list.length ? list.map((d) => `
      <div class="dev-row ${d.imei === currentDevice ? 'on' : ''}" data-dev="${esc(d.imei)}">
        <div class="dev-avatar ${d.connected ? '' : 'off'}"><i class="ic" data-i="cpu"></i></div>
        <div style="min-width:0">
          <div class="dev-name">${esc(d.name || d.imei)}</div>
          <div class="dev-meta">${esc(d.imei)} · ${d.connected ? (d.phone || '在线') : '设备离线'}</div>
        </div>
        <span class="badge ${d.connected ? 'green' : 'gray'}">${d.connected ? '在线' : '离线'}</span>
      </div>`).join('')
      : '<div style="padding:22px 10px;text-align:center;font-size:11px;color:var(--ink3)">没有匹配的设备</div>';
    paintIcons(box);
    renderDeviceDetail();
  }

  function renderDeviceDetail() {
    const box = $('#devDetail');
    if (!box) return;
    const d = devices.find((x) => x.imei === currentDevice);
    if (!d) {
      box.innerHTML = '<div style="padding:40px 16px;text-align:center;font-size:11px;color:var(--ink3)">选择左侧设备查看详情</div>';
      return;
    }
    box.innerHTML = `
    <div class="detail-head">
      <div class="dev-avatar big ${d.connected ? '' : 'off'}"><i class="ic" data-i="cpu"></i></div>
      <div style="min-width:0">
        <h2>${esc(d.name || d.imei)}</h2>
        <div class="sub">IMEI ${esc(d.imei)} · ${esc(d.phone || '无号码')}</div>
      </div>
      <div class="detail-actions">
        <button class="btn sm" data-goto="tasks"><i class="ic" data-i="bolt"></i>下发任务</button>
        <button class="btn sm ghost" data-goto="logcenter"><i class="ic" data-i="list"></i>日志</button>
      </div>
    </div>
    <div class="detail-grid">
      <div class="cell"><div class="k">在线状态</div><div class="v">${d.connected ? '在线' : '离线'}</div></div>
      <div class="cell"><div class="k">设备号码</div><div class="v">${esc(d.phone || '—')}</div></div>
      <div class="cell"><div class="k">首次接入</div><div class="v">${fmtTime(d.firstSeen)}</div></div>
      <div class="cell"><div class="k">最后在线</div><div class="v">${fmtTime(d.lastSeen)}</div></div>
      <div class="cell"><div class="k">备注</div><div class="v">${esc(d.name || '—')}</div></div>
      <div class="cell"><div class="k">IMEI</div><div class="v">${esc(d.imei)}</div></div>
    </div>
    <div style="margin-top:14px;padding-top:14px;border-top:.5px solid var(--hair)">
      <div class="label">快捷操作</div>
      <div class="quick-grid" style="margin-top:7px">
        <button class="quick" data-task-jump="get_temperature"><span class="tile" style="--qt:rgba(255,159,10,.14);--qf:#FF9F0A"><i class="ic" data-i="temp"></i></span>查询温度</button>
        <button class="quick" data-task-jump="get_config"><span class="tile" style="--qt:rgba(90,200,250,.16);--qf:#32ADE6"><i class="ic" data-i="doc"></i></span>读取配置</button>
        <button class="quick" data-task-jump="set_led"><span class="tile" style="--qt:rgba(175,82,222,.14);--qf:#AF52DE"><i class="ic" data-i="lightbulb"></i></span>灯光控制</button>
        <button class="quick" data-task-jump="reboot"><span class="tile" style="--qt:rgba(255,59,48,.13);--qf:#FF3B30"><i class="ic" data-i="refresh"></i></span>重启设备</button>
      </div>
    </div>
    <div style="display:flex;gap:6px;margin-top:14px;padding-top:12px;border-top:.5px solid var(--hair)">
      <button class="btn sm ghost" data-remark="${esc(d.imei)}"><i class="ic" data-i="pencil"></i>设置备注</button>
      <button class="btn sm ghost" data-del="${esc(d.imei)}"><i class="ic" data-i="trash"></i>删除设备</button>
    </div>`;
    paintIcons(box);
  }

  function jumpToTask(task) {
    switchPage('tasks');
    renderDeviceSelect(currentDevice);
    const imeiSel = $('#task-imei');
    if (imeiSel && currentDevice) imeiSel.value = currentDevice;
    const tsel = $('#task-type');
    if (tsel) { tsel.value = task; onTaskTypeChange(); }
  }

  async function editRemark(imei) {
    const dev = devices.find((x) => x.imei === imei);
    const cur = dev && dev.name ? dev.name : '';
    const nn = prompt('设置设备备注', cur);
    if (nn === null) return;
    try { await API.updateDeviceRemark({ imei, name: nn }); toast('备注已更新'); loadDevices(); }
    catch (err) { toast('更新失败：' + err.message, false); }
  }

  // 删除设备（在线设备会先被断开连接；若设备仍在运行，重连后会重新出现在列表）
  async function deleteDevice(imei) {
    const dev = devices.find((d) => d.imei === imei);
    const label = dev && dev.name ? `${dev.name}（${imei}）` : imei;
    const tip = dev && dev.connected
      ? '该设备当前在线，删除后若设备仍在运行会自动重新接入。'
      : '删除后不可恢复。';
    const ok = await showConfirm(`确定删除设备 ${label} 吗？${tip}`);
    if (!ok) return;
    try {
      await API.deleteDevice({ imei });
      toast('设备已删除');
      loadDevices();
    } catch (err) {
      toast(err.message, false);
    }
  }

  // 内联编辑设备备注
  function startEditRemark(imei) {
    const dev = devices.find((d) => d.imei === imei);
    const td = document.querySelector(`[data-remark="${CSS.escape(imei)}"]`)?.closest('td');
    if (!td) return;
    td.innerHTML = `
      <div class="rowflex" style="gap:5px">
        <input type="text" class="input" style="height:30px;width:180px" maxlength="30" value="${esc(dev ? dev.name : '')}" placeholder="备注">
        <button class="icon-btn" style="width:28px;height:28px;color:#1f9d45" title="保存" data-remark-save="1"><i class="ic" data-i="check"></i></button>
        <button class="icon-btn" style="width:28px;height:28px;color:var(--ink3)" title="取消" data-remark-cancel="1"><i class="ic" data-i="x"></i></button>
      </div>`;
    paintIcons(td);
    const input = td.querySelector('input');
    input.focus();
    input.select();

    const finish = async (save) => {
      if (save) {
        const name = input.value.trim();
        try {
          await API.updateDeviceRemark({ imei, name });
          if (dev) dev.name = name;
          renderDevices();
          toast(name ? '备注已保存' : '备注已清除');
        } catch (err) {
          renderDevices();
          toast(err.message, false);
        }
      } else {
        renderDevices();
      }
    };
    td.querySelector('[data-remark-save]').addEventListener('click', () => finish(true));
    td.querySelector('[data-remark-cancel]').addEventListener('click', () => finish(false));
    input.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter') finish(true);
      if (ev.key === 'Escape') finish(false);
    });
  }

  // ---------------- 任务执行 ----------------

  function renderDeviceSelect(selected) {
    const sel = $('#task-imei');
    const count = $('#task-device-count');
    if (!sel) return;
    if (!devices.length) {
      sel.innerHTML = '<option value="">暂无设备</option>';
      if (count) count.textContent = '0 台设备';
      return;
    }
    const online = devices.filter((d) => d.connected).length;
    sel.innerHTML = '<option value="">请选择设备</option>' + devices.map((d) =>
      `<option value="${esc(d.imei)}" ${d.imei === selected ? 'selected' : ''}>${d.name ? esc(d.name) + ' · ' : ''}${esc(d.imei)}（${esc(d.phone || '未知号码')}）${d.connected ? '' : ' [离线]'}</option>`).join('');
    if (selected) sel.value = selected;
    if (count) count.textContent = `${devices.length} 台设备 · ${online} 台在线`;
  }

  const TASK_LABELS = {
    get_temperature: '查询温度',
    send_sms: '发送短信',
    dial_call: '拨打电话',
    get_config: '读取配置',
    set_config: '写入配置',
    edit_config: '编辑配置',
    set_led: '灯光控制',
  };

  // 命令详细说明（任务说明弹窗内容）
  const TASK_HELP = {
    get_temperature: {
      title: '查询温度',
      desc: '读取设备（Air724UG 模组）当前的芯片温度，用于远程监控设备运行状态。',
      params: [],
      result: '返回温度数值（摄氏度），如 <code class="font-mono">38.28</code>。温度异常偏高可能意味着供电或散热问题。',
      note: '无需任何参数，点击下方"下发任务"即可执行。设备必须在线。',
    },
    send_sms: {
      title: '发送短信',
      desc: '通过设备内置的 SIM 卡向外发送一条短信，收件方看到的是设备本机号码。',
      params: [
        ['rcv_phone', '接收手机号，如 13800138000'],
        ['content', '短信内容。中文每 70 字一条，超出自动拆分为长短信（计多条费用）'],
      ],
      result: '成功返回 <code class="font-mono">"短信发送成功"</code>；失败返回具体原因（如 AT 指令错误、短信中心未配置）。',
      note: '需设备 SIM 卡已注册网络且信号正常；短信费用由 SIM 卡套餐承担。',
    },
    get_config: {
      title: '读取配置',
      desc: '读取设备上的运行时配置文件 <code class="font-mono">/nvm_para.lua</code> 全文。该文件存放可远程修改的参数（通知渠道、MQTT 地址等），优先级高于编译进固件的 config.lua。',
      params: [],
      result: '返回 nvm_para.lua 的完整 Lua 源码文本。',
      note: '如需修改，先读取当前配置作为底稿，改好后用"写入配置"写回，避免覆盖丢失其他参数。',
    },
    set_config: {
      title: '写入配置',
      desc: '用提交的 Lua 配置文本<b>整体覆盖</b>设备的 <code class="font-mono">/nvm_para.lua</code>，并立即生效（无需重启）。',
      params: [
        ['configText', '完整的 Lua 配置源码，必须以 <code class="font-mono">module(..., package.seeall)</code> 开头的合法 Lua 文件'],
      ],
      result: '成功返回 <code class="font-mono">{"success": true}</code>；语法错误时返回解析失败原因（此时不会写入文件）。',
      note: '覆盖式写入！建议先执行"读取配置"拿到当前内容再修改提交，避免遗漏参数。写入失败（如断电）可能导致文件丢失，需重刷脚本恢复。',
    },
    edit_config: {
      title: '编辑配置',
      desc: '一键读取设备当前 <code class="font-mono">/nvm_para.lua</code> 配置到右侧编辑器，在"当前内容"基础上修改后保存。相比"读取配置 + 写入配置"两步操作更便捷，避免覆盖遗漏。',
      params: [],
      result: '读取时返回 nvm_para.lua 全文；保存时返回 <code class="font-mono">{"success": true}</code>，立即生效。',
      note: '选择本类型后自动读取最新配置到编辑器，修改完成后点击右侧"保存配置"即可写回设备。设备离线时无法读取/保存。',
    },
    set_led: {
      title: '灯光控制',
      desc: '远程控制设备的 RGB 三色氛围灯（GPIO24/25/26）。可开关灯、循环切换 6 种灯效模式、指定模式或指定颜色。',
      params: [
        ['action', '动作：toggle(开关)/on(开灯)/off(关灯)/next(下一灯效)/prev(上一灯效)/set_mode(指定模式)/color(指定颜色)/status(查询状态)'],
        ['mode', '当 action=set_mode 时必填，1~6 对应 6 种灯效模式'],
        ['color', '当 action=color 时必填：off/red/green/blue/yellow/purple/cyan/white'],
      ],
      result: '成功返回灯效状态对象（含 mode/on/temp）；未知 action 返回错误。',
      note: '设备需在线（MQTT 已连接）才能收到指令；灯效模式带断电记忆，重启后保持。',
    },
    get_status: {
      title: '查询状态',
      desc: '一次性汇总设备的运行状态：电压、温度、信号强度（RSSI/RSRP）、运营商、本机号码、当前 SIM 卡槽、网络注册状态。',
      params: [],
      result: '返回 JSON，如 <code class="font-mono">{"voltage":3856,"temperature":38.28,"rssi":25,"operator":"中国电信",...}</code>。电压单位 mV；RSSI 范围 0-31，越大信号越好。',
      note: '无需参数。适合放在首页定期轮询，作为设备健康巡检。',
    },
    dial_call: {
      title: '拨打电话',
      desc: '通过设备 SIM 卡向外拨打电话。可用于触发目标手机的来电提醒（免打通话的变相通知方式）。',
      params: [
        ['phone', '被叫号码，如 13800138000'],
      ],
      result: '返回 <code class="font-mono">"拨打指令已执行: xxx"</code>。通话最长 300 秒自动挂断，可配合"挂断通话"提前结束。',
      note: '按运营商通话资费计费。通话期间设备会暂停音频播放。',
    },
    hang_up: {
      title: '挂断通话',
      desc: '挂断设备当前正在进行中的通话。',
      params: [],
      result: '有通话时返回 <code class="font-mono">"挂断指令已执行"</code>；无通话时返回 <code class="font-mono">"当前无通话"</code>。',
      note: '无需参数。常与"拨打电话"配合使用：拨通对方接听后（或响铃数秒后）挂断。',
    },
    tts_speak: {
      title: '语音播报',
      desc: '让设备扬声器用 TTS 朗读一段中文文本，适合远程寻人、现场提醒等场景。',
      params: [
        ['text', '要朗读的文本，如 "快递已到，请下楼取件"'],
      ],
      result: '返回 <code class="font-mono">"TTS 播报已执行"</code>。播报音量跟随设备当前音量设置。',
      note: '通话进行中不会播放；设备音量为 0 时静音。可用"设置音量"命令先调高音量。',
    },
    set_volume: {
      title: '设置音量',
      desc: '同时设置设备的扬声器音量与通话音量（写入 nvm_para.lua 持久保存）。',
      params: [
        ['vol', '音量值，0-10 的整数。0 为静音'],
      ],
      result: '返回 <code class="font-mono">"音量已设置为 N"</code>。设置即时生效且重启后保留。',
      note: '音量为 0 会同时静音扬声器与通话（通话录音无声）。通话中调节会即时生效。',
    },
    query_traffic: {
      title: '查询流量',
      desc: '按当前 SIM 卡运营商自动发送流量查询短信（移动发 10086、联通发 10010、电信发 10001）。运营商回复短信后，会自动触发通知推送。',
      params: [],
      result: '返回 <code class="font-mono">"流量查询短信已发送，运营商回复将推送通知"</code>，实际流量数据在回复短信里。',
      note: '消耗一条普通短信费用。广电卡不支持自动查询代码。',
    },
    set_ccfc: {
      title: '设置呼转',
      desc: '设置无条件呼叫转移：所有来电转接到指定号码。传 <code class="font-mono">phone=0</code> 则取消所有呼转。',
      params: [
        ['phone', '呼转目标号码（5 位以上）；传 0 取消呼转'],
      ],
      result: '返回 <code class="font-mono">"呼转指令已下发: xxx"</code>。指令为异步下发，运营商生效结果以通知推送为准。',
      note: '呼转生效后设备不再振铃，来电全部转接。取消时传 phone=0。',
    },
    switch_sim: {
      title: '切换SIM',
      desc: '在主/副卡槽之间切换 SIM 卡，设备将在 10 秒后自动重启使切换生效（与短信指令 SIMSWITCH 行为一致）。',
      params: [],
      result: '返回 <code class="font-mono">"切换SIM: 主卡槽 -> 副卡槽, 10秒后重启生效"</code>（方向视当前卡槽而定）。',
      note: '设备会重启，期间 MQTT 短暂离线属正常现象。重启后约 1-2 分钟恢复在线。',
    },
    reboot: {
      title: '重启设备',
      desc: '远程重启设备（软重启），用于排除运行异常、恢复网络注册等。设备将在 10 秒后执行重启。',
      params: [],
      result: '返回 <code class="font-mono">"重启指令已接收, 10秒后重启"</code>，之后设备离线再自动恢复上线。',
      note: '重启期间设备约 1-2 分钟离线。频繁重启请先排查供电稳定性（劣质充电器会导致反复重启）。',
    },
    get_device_info: {
      title: '设备信息',
      desc: '读取设备硬件标识：IMEI（模块串号）、SN、ICCID（SIM 卡序列号）、固件版本、模块型号。',
      params: [],
      result: '返回 JSON，如 <code class="font-mono">{"imei":"8681...","sn":"...","iccid":"8986...","version":"...","model":"..."}</code>',
      note: '无需参数。设备首次接入面板后可通过此命令核对硬件身份。',
    },
    ussd_query: {
      title: 'USSD 查询',
      desc: '发送 USSD 交互码查询话费/流量余额（如电信 <code class="font-mono">*108#</code>）。运营商回复后，结果通过通知渠道（如 message-pusher）推送给你。',
      params: [
        ['code', 'USSD 查询码，如 *108#（各运营商不同，请自行确认）'],
      ],
      result: '返回 <code class="font-mono">"USSD 查询已发送: *108#，运营商回复将通过通知推送"</code>，实际余额在推送的通知里。',
      note: 'USSD 会话会占用话音通道，查询后几秒内不要拨打/接听电话。物联网卡可能不支持 USSD。',
    },
    send_dtmf: {
      title: '发送按键',
      desc: '通话过程中向对端发送 DTMF 按键音。典型场景：自动拨打客服后输入分机号、语音信箱选单。',
      params: [
        ['dtmf', '按键字符串，仅支持数字和 ABCD*#，如 "123"'],
      ],
      result: '通话中返回 <code class="font-mono">"DTMF 已发送: xxx"</code>；无通话时报错"当前无通话"。',
      note: '必须先"拨打电话"且通话建立后使用，每个按键默认播放 100ms。常与拨打电话配合实现自动语音流程。',
    },
    set_gpio: {
      title: 'GPIO 控制',
      desc: '设置指定 GPIO 引脚的输出电平（高/低）。外接继电器或 MOS 管即可实现远程控制电器开关、门禁等。',
      params: [
        ['pin', 'GPIO 引脚编号（数字），参考开发板引脚图'],
        ['level', '输出电平：1 高电平（通常闭合继电器），0 低电平（断开）'],
      ],
      result: '返回 <code class="font-mono">"GPIOn 已输出 1"</code>。输出状态保持到下次修改或重启（重启后恢复默认）。',
      note: 'GPIO 带载能力有限（毫安级），控制大电流设备务必经继电器隔离。引脚接错可能损坏模块，接线前核对引脚图。',
    },
  };

  // 命令大全分组（"任务说明"弹窗与命令大全共用 TASK_HELP 数据）
  const TASK_GROUPS = [
    { name: '查询类', icon: '🔍', tasks: ['get_temperature', 'get_status', 'get_device_info', 'get_config', 'query_traffic'] },
    { name: '通信类', icon: '💬', tasks: ['send_sms', 'dial_call', 'hang_up', 'send_dtmf', 'tts_speak', 'set_ccfc', 'ussd_query'] },
    { name: '配置与系统', icon: '⚙️', tasks: ['set_config', 'set_volume', 'set_gpio', 'switch_sim', 'reboot'] },
  ];

  // 命令大全：手风琴模式，始终只展开一个分组
  let libOpenGroup = 0;

  function renderTaskLibrary() {
    const body = $('#task-library-body');
    body.innerHTML = TASK_GROUPS.map((g, gi) => {
      const open = gi === libOpenGroup;
      return `
      <div style="margin-bottom:8px">
        <button type="button" class="task-lib-group" data-group="${gi}">
          <span class="rowflex" style="gap:8px">${g.icon} ${g.name}</span>
          <i class="ic" data-i="${open ? 'chevD' : 'chevR'}" style="width:14px;height:14px;color:var(--ink3)"></i>
        </button>
        ${open ? `<div style="margin-top:4px;border:.5px solid var(--hair);border-radius:12px;overflow:hidden">
          ${g.tasks.map((t) => {
            const h = TASK_HELP[t];
            return h ? `<a href="javascript:void(0)" class="task-lib-item" data-task="${t}">
              <span class="rowflex" style="gap:8px"><span>${h.title}</span><code>${t}</code></span>
              <i class="ic" data-i="chevR" style="width:14px;height:14px;color:var(--ink3)"></i>
            </a>` : '';
          }).join('')}
        </div>` : ''}
      </div>`;
    }).join('');
    paintIcons(body);
  }

  function showTaskLibrary() {
    renderTaskLibrary();
    $('#task-library-modal').classList.remove('hidden');
  }
  function closeTaskLibrary() {
    $('#task-library-modal').classList.add('hidden');
  }

  function showTaskHelp(task) {
    const h = TASK_HELP[task];
    if (!h) return;
    $('#task-help-title').textContent = h.title;
    $('#task-help-cmd').textContent = task;
    let html = `<p>${h.desc}</p>`;
    if (h.params.length) {
      html += '<div><div class="label" style="margin:12px 0 6px">请求参数</div><ul style="display:flex;flex-direction:column;gap:6px;padding:0;margin:0;list-style:none">'
        + h.params.map((p) => `<li><code style="font-family:var(--mono);font-size:11px;background:var(--fill2);border-radius:6px;padding:2px 7px">${p[0]}</code> — ${p[1]}</li>`).join('')
        + '</ul></div>';
    }
    html += `<div><div class="label" style="margin:12px 0 6px">返回结果</div><p>${h.result}</p></div>`;
    html += `<div style="border-radius:12px;background:rgba(255,159,10,.1);border:.5px solid rgba(255,159,10,.22);padding:10px 12px;font-size:11.5px;color:#b56a00;margin-top:12px">⚠️ ${h.note}</div>`;
    $('#task-help-body').innerHTML = html;
    $('#task-help-modal').classList.remove('hidden');
  }
  function closeTaskHelp() {
    $('#task-help-modal').classList.add('hidden');
  }

  function onTaskTypeChange() {
    const checked = document.querySelector('input[name="task-type"]:checked');
    if (!checked) return;
    const type = checked.value;
    ['params-send_sms', 'params-dial_call', 'params-set_config', 'params-set_led', 'params-__custom__'].forEach((id) => {
      const el = $('#' + id);
      if (el) el.classList.toggle('hidden', id !== 'params-' + type);
    });
    // 灯光动作联动：仅 set_led 时调用一次（按当前动作显示/隐藏模式与颜色）
    if (type === 'set_led') onLedActionChange();
    // 配置编辑器：仅"编辑配置"任务类型时显示，并自动读取最新配置
    const editor = $('#config-editor');
    if (editor) {
      if (type === 'edit_config') {
        editor.classList.remove('hidden');
        loadConfigForEdit();
      } else {
        editor.classList.add('hidden');
      }
    }
  }

  // 读取设备最新配置到编辑器（"编辑配置"任务类型专用）
  async function loadConfigForEdit() {
    const imei = $('#task-imei').value;
    const st = $('#config-editor-status');
    const ta = $('#config-edit-text');
    if (!st || !ta) return;
    if (!imei) { st.textContent = '请先在左侧选择设备'; return; }
    st.textContent = '⏳ 正在读取设备配置...';
    try {
      const data = await API.executeTask({ imei, task: 'get_config' });
      const result = data.result;
      let text = '';
      if (typeof result === 'string') text = result;
      else if (result && result.content) text = result.content;
      else if (result && result.config) text = result.config;
      else if (result) text = JSON.stringify(result, null, 2);
      ta.value = text;
      st.textContent = `✔ 已读取当前配置（${(text.length / 1024).toFixed(1)} KB）`;
      const box = $('#task-result');
      consoleLine(box, `▶ 已读取配置 → ${imei}`, 'c-sky');
    } catch (err) {
      ta.value = '';
      st.textContent = '✘ 读取失败：' + err.message;
    }
  }

  // 保存编辑后的配置（写入设备）
  async function saveConfig() {
    const imei = $('#task-imei').value;
    const ta = $('#config-edit-text');
    const st = $('#config-editor-status');
    const text = ta ? ta.value : '';
    if (!st || !ta) return;
    if (!imei) { st.textContent = '请先在左侧选择设备'; return; }
    if (!text.trim()) { st.textContent = '配置内容为空，无法保存'; return; }
    st.textContent = '⏳ 正在保存配置...';
    try {
      const data = await API.executeTask({ imei, task: 'set_config', configText: text });
      const result = data.result;
      const pretty = typeof result === 'string' ? result : JSON.stringify(result, null, 2);
      st.textContent = '✔ 保存成功：' + (pretty.length > 60 ? pretty.slice(0, 60) + '…' : pretty);
      const box = $('#task-result');
      consoleLine(box, `▶ 保存配置 → ${imei}`, 'c-sky');
      consoleLine(box, pretty, 'c-ok whitespace-pre-wrap break-all');
      toast('配置已保存');
    } catch (err) {
      st.textContent = '✘ 保存失败：' + err.message;
      toast('配置保存失败', false);
    }
  }

  // 灯光动作联动：set_mode 显示模式选择，color 显示颜色选择，其余隐藏
  function onLedActionChange() {
    const action = $('#task-led-action').value;
    const modeWrap = $('#led-mode-wrap');
    const colorWrap = $('#led-color-wrap');
    if (modeWrap) modeWrap.classList.toggle('hidden', action !== 'set_mode');
    if (colorWrap) colorWrap.classList.toggle('hidden', action !== 'color');
  }

  // 终端控制台输出
  function consoleLine(box, text, cls) {
    const div = document.createElement('div');
    div.className = cls || '';
    div.textContent = text;
    box.appendChild(div);
    box.scrollTop = box.scrollHeight;
  }
  function resetConsole() {
    const box = $('#task-result');
    box.innerHTML = '<p class="c-dim">// 等待下发任务...</p>';
  }

  async function handleTaskSubmit(e) {
    e.preventDefault();
    const imei = $('#task-imei').value;
    if (!imei) { toast('请选择目标设备', false); return; }
    const checked = document.querySelector('input[name="task-type"]:checked');
    let type = checked ? checked.value : '';
    const payload = { imei, task: type };

    if (type === '__custom__') {
      const cmd = $('#task-custom-cmd').value.trim();
      if (!cmd) { toast('请输入命令名称', false); return; }
      const params = $('#task-custom-params').value.trim();
      let extraObj = {};
      if (params) {
        try { extraObj = JSON.parse(params); }
        catch (_) { toast('命令参数不是合法 JSON', false); return; }
      }
      type = cmd;
      payload.task = cmd;
      Object.assign(payload, extraObj);
    } else if (type === 'send_sms') {
      const phone = $('#task-rcv-phone').value.trim();
      const content = $('#task-content').value.trim();
      if (!phone || !content) { toast('请填写手机号和短信内容', false); return; }
      payload.rcv_phone = phone;
      payload.content = content;
    } else if (type === 'dial_call') {
      const phone = $('#task-call-phone').value.trim();
      if (!phone) { toast('请填写被叫号码', false); return; }
      payload.phone = phone;
    } else if (type === 'set_config') {
      const text = $('#task-config-text').value;
      if (!text.trim()) { toast('请填写配置内容', false); return; }
      payload.configText = text;
    } else if (type === 'edit_config') {
      const text = $('#config-edit-text').value;
      if (!text.trim()) { toast('请先读取或填写配置内容', false); return; }
      payload.task = 'set_config';
      payload.configText = text;
    } else if (type === 'set_led') {
      const action = $('#task-led-action').value;
      payload.action = action;
      if (action === 'set_mode') payload.mode = $('#task-led-mode').value;
      else if (action === 'color') payload.color = $('#task-led-color').value;
    }

    const extra = $('#task-extra').value.trim();
    if (extra) {
      try { Object.assign(payload, JSON.parse(extra)); }
      catch (_) { toast('附加参数不是合法 JSON', false); return; }
    }

    const btn = $('#task-btn');
    btn.disabled = true;
    btn.textContent = '下发中...';
    const box = $('#task-result');
    resetConsole();
    consoleLine(box, `▶ 下发任务 → ${imei}（${TASK_LABELS[type] || type}）`, 'c-sky');
    consoleLine(box, '⏳ 等待设备回报（最长 30 秒）...', 'c-dim');
    try {
      const data = await API.executeTask(payload);
      const result = data.result;
      if (result && typeof result === 'object' && result.error) {
        throw new Error(result.error);
      }
      const pretty = typeof result === 'string' ? result : JSON.stringify(result, null, 2);
      consoleLine(box, '✔ 设备已回报：', 'c-ok');
      consoleLine(box, pretty, 'c-ok whitespace-pre-wrap break-all');
      toast('任务执行成功');
    } catch (err) {
      consoleLine(box, `✘ 执行失败：${err.message}`, 'c-err');
      toast('任务执行失败', false);
    } finally {
      btn.disabled = false;
      btn.textContent = '⚡ 下发任务';
    }
  }

  // ---------------- 任务记录 ----------------

  let tasksPage = 1;

  async function loadTasks(page) {
    if (typeof page === 'number') tasksPage = page;
    try {
      const data = await API.tasks(tasksPage);
      tasksPage = data.page || tasksPage;
      const tasks = data.tasks || [];
      const tbody = $('#tasks-tbody');
      if (!tasks.length) {
        tbody.innerHTML = '<tr><td colspan="5" class="empty">暂无任务记录</td></tr>';
        renderTaskPagination(0, 1);
        return;
      }
      tbody.innerHTML = tasks.map((t) => {
        let result = t.result || t.error || '';
        if (result.length > 120) result = result.slice(0, 120) + '…';
        const ok = t.status === 'done' && !t.error;
        const deviceLabel = t.deviceName || t.imei;
        const isName = !!t.deviceName;
        return `
        <tr>
          <td class="faint">${fmtTime(t.createdAt)}</td>
          <td >${esc(deviceLabel)}${isName ? `<span class="sub">${esc(t.imei)}</span>` : ''}</td>
          <td class="dim">${esc(t.task)}</td>
          <td class="px-4 py-3">${ok ? '<span class="badge-online">成功</span>' : '<span class="badge-offline">失败</span>'}</td>
          <td class="dim"><pre style="font-size:10.5px;font-family:var(--mono);white-space:pre-wrap;word-break:break-all">${esc(result)}</pre></td>
        </tr>`;
      }).join('');
      renderTaskPagination(data.total || 0, tasksPage);
    } catch (err) {
      $('#tasks-tbody').innerHTML = `<tr><td colspan="5" class="empty" style="color:var(--red)">${esc(err.message)}</td></tr>`;
      renderTaskPagination(0, 1);
    }
  }

  // 渲染任务记录分页控件（每页 10 条）
  function renderTaskPagination(total, page) {
    const wrap = $('#tasks-pagination');
    const info = $('#tasks-page-info');
    const btns = $('#tasks-page-btns');
    const totalPages = Math.max(1, Math.ceil(total / 10));

    if (total <= 0) {
      wrap.classList.add('hidden');
      return;
    }
    wrap.classList.remove('hidden');
    info.textContent = `共 ${total} 条记录 · 第 ${page} / ${totalPages} 页`;

    // 页码列表：首末页 + 当前页相邻页，中间以省略号折叠
    const list = [];
    for (let i = 1; i <= totalPages; i++) {
      if (i === 1 || i === totalPages || Math.abs(i - page) <= 1) list.push(i);
      else if (list[list.length - 1] !== '…') list.push('…');
    }

    // 按钮样式以已有 Tailwind 类为主，缺失的工具类用内联样式补充
    const btnCls = '';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `
      <button type="button" data-page="${page - 1}" class="${btnCls}" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="faint" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-page="${p}" class="${btnCls} ${p === page ? 'on' : ''}" style="min-width:2rem">${p}</button>`
    ).join('');
    html += `
      <button type="button" data-page="${page + 1}" class="${btnCls}" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
    btns.innerHTML = html;
  }

  // ---------------- 通话记录 / 短信记录 ----------------

  // 方向 / 状态中文映射
  const CALL_DIR_LABEL = { incoming: '来电', outgoing: '去电' };
  const CALL_STATUS_LABEL = {
    connected: '已接通', missed: '未接', rejected: '已拒接',
    no_answer: '未应答', cancelled: '已取消', unknown: '未知',
  };

  let callsPage = 1;
  let smsPage = 1;
  let logPage = 1;

  // 把 YYYY-MM-DD 转换为当天 0 点 / 23:59:59 的 Unix 秒
  function dateToTs(value, endOfDay) {
    if (!value) return 0;
    const d = new Date(value + (endOfDay ? 'T23:59:59' : 'T00:00:00'));
    if (isNaN(d.getTime())) return 0;
    return Math.floor(d.getTime() / 1000);
  }

  // 填充记录筛选页面的设备下拉（复用 devices 列表）
  function fillRecordImeiFilter(selId) {
    const sel = $(selId);
    if (!sel) return;
    const cur = sel.value;
    sel.innerHTML = '<option value="">全部设备</option>' + devices.map((d) =>
      `<option value="${esc(d.imei)}">${d.name ? esc(d.name) + ' · ' : ''}${esc(d.imei)}</option>`).join('');
    if (cur) sel.value = cur;
  }

  // ------- 通知状态徽章 -------
  function notifyBadge(status) {
    const map = {
      '': ['notify-none', '未通知'],
      'queued': ['notify-queued', '排队中'],
      'sent': ['notify-sent', '已发送'],
      'failed': ['notify-failed', '失败'],
      'blocked': ['notify-blocked', '已屏蔽'],
    };
    const [cls, label] = map[status] || map[''];
    return `<span class="notify-badge ${cls}" title="设备端通知发送状态">${label}</span>`;
  }

  // ------- 通话记录 -------
  async function loadCalls(page) {
    if (typeof page === 'number') callsPage = page;
    const filter = {
      from: dateToTs($('#calls-filter-from').value, false),
      to: dateToTs($('#calls-filter-to').value, true),
      imei: $('#calls-filter-imei').value,
    };
    try {
      const data = await API.calls(callsPage, filter);
      callsPage = data.page || callsPage;
      const calls = data.calls || [];
      const tbody = $('#calls-tbody');
      if (!calls.length) {
        tbody.innerHTML = '<tr><td colspan="9" class="empty">暂无通话记录</td></tr>';
        renderCallPagination(0, 1);
        return;
      }
      tbody.innerHTML = calls.map((c) => {
        const status = CALL_STATUS_LABEL[c.status] || '未知';
        const dur = c.duration > 0 ? formatDuration(c.duration) : '—';
        const dirBadge = c.direction === 'outgoing'
          ? '<span class="badge-offline">去电</span>'
          : '<span class="badge-online">来电</span>';
        const deviceLabel = c.deviceName || c.imei;
        return `
        <tr>
          <td class="faint">${fmtTime(c.startedAt)}</td>
          <td class="px-4 py-3">${dirBadge}</td>
          <td class="mono">${esc(c.number || '—')}</td>
          <td class="dim">${esc(status)}</td>
          <td class="dim">${dur}</td>
          <td class="px-4 py-3">${notifyBadge(c.notifyStatus)}</td>
          <td class="px-4 py-3">${c.spam ? `<span class="spam-badge">垃圾电话</span>${c.spamRule ? `<div class="text-xs c-err mt-0.5 break-all">命中：${esc(c.spamRule)}</div>` : ''}` : '<span class="c-em">—</span>'}</td>
          <td class="dim">${esc(deviceLabel)}${c.deviceName ? `<span class="sub">${esc(c.imei)}</span>` : ''}</td>
          <td class="right">
            <button type="button" data-call-del="${c.id}" class="mini-btn danger">删除</button>
          </td>
        </tr>`;
      }).join('');
      renderCallPagination(data.total || 0, callsPage);
    } catch (err) {
      $('#calls-tbody').innerHTML = `<tr><td colspan="9" class="empty" style="color:var(--red)">${esc(err.message)}</td></tr>`;
      renderCallPagination(0, 1);
    }
  }

  function renderCallPagination(total, page) {
    const wrap = $('#calls-pagination');
    const info = $('#calls-page-info');
    const btns = $('#calls-page-btns');
    const pageSize = 10;
    const totalPages = Math.max(1, Math.ceil(total / pageSize));
    if (total <= 0) { wrap.classList.add('hidden'); return; }
    wrap.classList.remove('hidden');
    info.textContent = `共 ${total} 条记录 · 第 ${page} / ${totalPages} 页`;
    const list = [];
    for (let i = 1; i <= totalPages; i++) {
      if (i === 1 || i === totalPages || Math.abs(i - page) <= 1) list.push(i);
      else if (list[list.length - 1] !== '…') list.push('…');
    }
    const btnCls = '';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `<button type="button" data-calls-page="${page - 1}" class="${btnCls}" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="faint" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-calls-page="${p}" class="${btnCls} ${p === page ? 'on' : ''}" style="min-width:2rem">${p}</button>`).join('');
    html += `<button type="button" data-calls-page="${page + 1}" class="${btnCls}" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
    btns.innerHTML = html;
  }

  // ------- 短信记录 -------
  async function loadSms(page) {
    if (typeof page === 'number') smsPage = page;
    const filter = {
      from: dateToTs($('#sms-filter-from').value, false),
      to: dateToTs($('#sms-filter-to').value, true),
      imei: $('#sms-filter-imei').value,
    };
    try {
      const data = await API.sms(smsPage, filter);
      smsPage = data.page || smsPage;
      const list = data.sms || [];
      const tbody = $('#sms-tbody');
      if (!list.length) {
        tbody.innerHTML = '<tr><td colspan="8" class="empty">暂无短信记录</td></tr>';
        renderSmsPagination(0, 1);
        return;
      }
      tbody.innerHTML = list.map((m) => {
        const dirBadge = m.direction === 'out'
          ? '<span class="badge-offline">发送</span>'
          : '<span class="badge-online">接收</span>';
        const deviceLabel = m.deviceName || m.imei;
        return `
        <tr>
          <td class="faint">${fmtTime(m.createdAt)}</td>
          <td class="px-4 py-3">${dirBadge}</td>
          <td class="mono">${esc(m.number || '—')}</td>
          <td class="dim"><span style="word-break:break-all">${esc(m.content || '')}</span></td>
          <td class="px-4 py-3">${notifyBadge(m.notifyStatus)}</td>
          <td class="px-4 py-3">${m.spam ? `<span class="spam-badge">垃圾短信</span>${m.spamRule ? `<div class="text-xs c-err mt-0.5 break-all">命中：${esc(m.spamRule)}</div>` : ''}` : '<span class="c-em">—</span>'}</td>
          <td class="dim">${esc(deviceLabel)}${m.deviceName ? `<span class="sub">${esc(m.imei)}</span>` : ''}</td>
          <td class="right">
            <button type="button" data-sms-del="${m.id}" class="mini-btn danger">删除</button>
          </td>
        </tr>`;
      }).join('');
      renderSmsPagination(data.total || 0, smsPage);
    } catch (err) {
      $('#sms-tbody').innerHTML = `<tr><td colspan="8" class="empty" style="color:var(--red)">${esc(err.message)}</td></tr>`;
      renderSmsPagination(0, 1);
    }
  }

  function renderSmsPagination(total, page) {
    const wrap = $('#sms-pagination');
    const info = $('#sms-page-info');
    const btns = $('#sms-page-btns');
    const pageSize = 10;
    const totalPages = Math.max(1, Math.ceil(total / pageSize));
    if (total <= 0) { wrap.classList.add('hidden'); return; }
    wrap.classList.remove('hidden');
    info.textContent = `共 ${total} 条记录 · 第 ${page} / ${totalPages} 页`;
    const list = [];
    for (let i = 1; i <= totalPages; i++) {
      if (i === 1 || i === totalPages || Math.abs(i - page) <= 1) list.push(i);
      else if (list[list.length - 1] !== '…') list.push('…');
    }
    const btnCls = '';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `<button type="button" data-sms-page="${page - 1}" class="${btnCls}" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="faint" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-sms-page="${p}" class="${btnCls} ${p === page ? 'on' : ''}" style="min-width:2rem">${p}</button>`).join('');
    html += `<button type="button" data-sms-page="${page + 1}" class="${btnCls}" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
    btns.innerHTML = html;
  }

  // ------- 日志中心 -------
  const LOG_TYPE_LABEL = {
    online: '上线 / 心跳',
    telemetry: '遥测',
    call_record: '通话记录',
    sms_record: '短信记录',
    result: '任务结果',
    powersave: '省电状态',
    notify_result: '通知结果',
  };

  async function loadLogs(page) {
    if (typeof page === 'number') logPage = page;
    const filter = {
      from: dateToTs($('#log-filter-from').value, false),
      to: dateToTs($('#log-filter-to').value, true),
      imei: $('#log-filter-imei').value,
      type: $('#log-filter-type').value,
      keyword: $('#log-filter-keyword').value.trim(),
    };
    try {
      const data = await API.logs(logPage, filter);
      logPage = data.page || logPage;
      const list = data.logs || [];
      const tbody = $('#log-tbody');
      if (!list.length) {
        tbody.innerHTML = '<tr><td colspan="4" class="empty">暂无日志</td></tr>';
        renderLogPagination(0, 1);
        return;
      }
      tbody.innerHTML = list.map((l) => {
        const typeLabel = LOG_TYPE_LABEL[l.logType] || l.logType || '—';
        const deviceLabel = l.deviceName || l.imei;
        let payload = l.payload || '';
        try { payload = JSON.stringify(JSON.parse(payload), null, 2); } catch (e) { /* 保留原文 */ }
        const oneLine = payload.replace(/\s+/g, ' ').trim();
        return `
        <tr>
          <td class="faint">${fmtTime(l.createdAt)}</td>
          <td class="px-4 py-3 whitespace-nowrap"><span class="badge-online">${esc(typeLabel)}</span></td>
          <td class="faint">${esc(deviceLabel)}${l.deviceName ? `<span class="sub"> ${esc(l.imei)}</span>` : ''}</td>
          <td class="px-4 py-3">
            <div class="log-cell" data-log-json="${esc(payload)}" data-log-topic="${esc(l.topic)}">
              <span class="log-topic">${esc(l.topic)}</span>
              <span class="log-preview">${esc(oneLine)}</span>
              <button type="button" class="log-copy-btn" data-log-copy="${esc(payload)}" title="复制日志信息">📋</button>
            </div>
          </td>
        </tr>`;
      }).join('');
      renderLogPagination(data.total || 0, logPage);
    } catch (err) {
      $('#log-tbody').innerHTML = `<tr><td colspan="4" class="empty" style="color:var(--red)">${esc(err.message)}</td></tr>`;
      renderLogPagination(0, 1);
    }
  }

  function renderLogPagination(total, page) {
    const wrap = $('#log-pagination');
    const info = $('#log-page-info');
    const btns = $('#log-page-btns');
    const pageSize = 10;
    const totalPages = Math.max(1, Math.ceil(total / pageSize));
    if (total <= 0) { wrap.classList.add('hidden'); return; }
    wrap.classList.remove('hidden');
    info.textContent = `共 ${total} 条记录 · 第 ${page} / ${totalPages} 页`;
    const list = [];
    for (let i = 1; i <= totalPages; i++) {
      if (i === 1 || i === totalPages || Math.abs(i - page) <= 1) list.push(i);
      else if (list[list.length - 1] !== '…') list.push('…');
    }
    const btnCls = '';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `<button type="button" data-log-page="${page - 1}" class="${btnCls}" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="faint" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-log-page="${p}" class="${btnCls} ${p === page ? 'on' : ''}" style="min-width:2rem">${p}</button>`).join('');
    html += `<button type="button" data-log-page="${page + 1}" class="${btnCls}" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
    btns.innerHTML = html;
  }

  // ------- 日志中心：悬浮预览完整 JSON + 复制 -------
  let logTipEl = null;
  function ensureLogTip() {
    if (logTipEl) return logTipEl;
    logTipEl = document.createElement('div');
    logTipEl.id = 'log-tooltip';
    logTipEl.classList.add('hidden');
    document.body.appendChild(logTipEl);
    return logTipEl;
  }

  // 绑定日志中心悬浮预览（事件委托，避免每次渲染重复绑定）
  function bindLogTooltip() {
    const tbody = $('#log-tbody');
    const tip = ensureLogTip();
    if (!tbody || tbody.dataset.tipBound) return;
    tbody.dataset.tipBound = '1';

    tbody.addEventListener('mouseover', (ev) => {
      const cell = ev.target.closest('[data-log-json]');
      if (!cell) { tip.classList.add('hidden'); return; }
      const raw = cell.dataset.logJson || '';
      let pretty = raw;
      try { pretty = JSON.stringify(JSON.parse(raw), null, 2); } catch (e) { /* 保留原文 */ }
      tip.innerHTML = `<div class="lt-head">${esc(cell.dataset.logTopic || '')}</div><pre class="lt-body">${esc(pretty)}</pre>`;
      tip.classList.remove('hidden');
    });

    tbody.addEventListener('mousemove', (ev) => {
      if (tip.classList.contains('hidden')) return;
      const pad = 14;
      let x = ev.clientX + pad, y = ev.clientY + pad;
      const tw = tip.offsetWidth, th = tip.offsetHeight;
      if (x + tw > window.innerWidth - 8) x = ev.clientX - tw - pad;
      if (y + th > window.innerHeight - 8) y = Math.max(8, ev.clientY - th - pad);
      tip.style.left = x + 'px';
      tip.style.top = y + 'px';
    });

    tbody.addEventListener('mouseleave', () => tip.classList.add('hidden'));

    // 复制日志信息
    tbody.addEventListener('click', (ev) => {
      const btn = ev.target.closest('[data-log-copy]');
      if (!btn) return;
      const text = btn.dataset.logCopy || '';
      copyTextToClipboard(text, '已复制日志信息');
    });
  }

  // 复制文本到剪贴板（优先异步 Clipboard API，降级 execCommand）
  function copyTextToClipboard(text, okMsg) {
    const done = () => toast(okMsg || '已复制');
    const fail = (e) => toast('复制失败', false);
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(done).catch(() => fallbackCopy(text, done, fail));
    } else {
      fallbackCopy(text, done, fail);
    }
  }
  function fallbackCopy(text, done, fail) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); done(); } catch (e) { fail(e); }
    document.body.removeChild(ta);
  }

  // ------- 删除单条记录 -------
  async function deleteCallRecord(id) {
    const ok = await showConfirm('确定删除这条通话记录吗？此操作不可恢复。');
    if (!ok) return;
    try {
      const data = await API.deleteCall(id);
      toast(data.message || '删除成功');
      loadCalls(callsPage);
    } catch (err) { toast(err.message); }
  }

  async function deleteSmsRecord(id) {
    const ok = await showConfirm('确定删除这条短信记录吗？此操作不可恢复。');
    if (!ok) return;
    try {
      const data = await API.deleteSms(id);
      toast(data.message || '删除成功');
      loadSms(smsPage);
    } catch (err) { toast(err.message); }
  }

  // ------- 屏蔽配置 -------

  let blockTab = 'keyword';
  let blockRulesCache = [];
  let blockRulesPage = [];   // 当前页规则
  let blockPage = 1;
  let blockTotal = 0;
  const blockPageSize = 10;

  // 加载屏蔽规则列表（按当前 tab 分页；全量仅用于统计与操作查找）
  async function loadBlockRules(page) {
    if (typeof page === 'number') blockPage = page;
    try {
      const [pageData, all] = await Promise.all([
        API.blockRules({ type: blockTab, page: blockPage, size: blockPageSize }),
        API.blockRules(),
      ]);
      blockRulesPage = pageData.rules || [];
      blockTotal = pageData.total || 0;
      blockRulesCache = all.rules || [];
      renderBlockRules();
      renderBlockPagination(blockTotal, blockPage);
      updateBlockTip();
    } catch (err) {
      $('#block-tbody').innerHTML = `<tr><td colspan="5" class="empty" style="color:var(--red)">${esc(err.message)}</td></tr>`;
      renderBlockPagination(0, 1);
    }
  }

  // 渲染当前 tab 的规则
  function renderBlockRules() {
    const tbody = $('#block-tbody');
    const list = blockRulesPage;
    if (!list.length) {
      tbody.innerHTML = `<tr><td colspan="5" class="empty">暂无${blockTab === 'keyword' ? '关键字' : '号码'}规则，可在上方添加</td></tr>`;
      return;
    }
    tbody.innerHTML = list.map((r) => {
      const srcLabel = r.source === 'builtin' ? '<span class="badge-offline">内置</span>' : '<span class="badge-online">自定义</span>';
      const modeLabel = r.ruleType === 'number'
        ? ({ prefix: '前缀', exact: '精确', contains: '包含' }[r.matchMode] || r.matchMode)
        : '包含';
      const valueLabel = r.ruleType === 'number'
        ? `<span class="font-mono">${esc(r.value)}</span> <span class="text-xs c-dim">（${modeLabel}）</span>`
        : `<span class="font-medium text-slate-700">${esc(r.value)}</span>`;
      const enabled = r.enabled === 1;
      return `
      <tr>
        <td class="px-4 py-3">${valueLabel}</td>
        <td class="px-4 py-3">${srcLabel}</td>
        <td class="px-4 py-3">${enabled ? '<span class="notify-badge notify-sent">生效中</span>' : '<span class="notify-badge notify-none">已停用</span>'}</td>
        <td class="dim">${esc(r.note || '—')}</td>
        <td class="right">
          <button type="button" data-block-toggle="${r.id}" class="mini-btn ${enabled ? '' : 'success'}">${enabled ? '停用' : '启用'}</button>
          <button type="button" data-block-del="${r.id}" class="mini-btn danger">删除</button>
        </td>
      </tr>`;
    }).join('');
  }

  function updateBlockTip() {
    const kw = blockRulesCache.filter((r) => r.ruleType === 'keyword' && r.enabled === 1).length;
    const num = blockRulesCache.filter((r) => r.ruleType === 'number' && r.enabled === 1).length;
    $('#block-tip').textContent = `当前生效：${kw} 条关键字规则、${num} 条号码规则。命中规则的短信/来电由设备本地拦截，不再发送通知；记录仍上报并标记垃圾。`;
  }

  // 屏蔽规则分页控件
  function renderBlockPagination(total, page) {
    const wrap = $('#block-pagination');
    const info = $('#block-page-info');
    const btns = $('#block-page-btns');
    const pageSize = blockPageSize;
    const totalPages = Math.max(1, Math.ceil(total / pageSize));
    if (total <= 0) { wrap.classList.add('hidden'); return; }
    wrap.classList.remove('hidden');
    info.textContent = `共 ${total} 条规则 · 第 ${page} / ${totalPages} 页`;
    const list = [];
    for (let i = 1; i <= totalPages; i++) {
      if (i === 1 || i === totalPages || Math.abs(i - page) <= 1) list.push(i);
      else if (list[list.length - 1] !== '…') list.push('…');
    }
    const btnCls = '';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `<button type="button" data-block-page="${page - 1}" class="${btnCls}" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="faint" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-block-page="${p}" class="${btnCls} ${p === page ? 'on' : ''}" style="min-width:2rem">${p}</button>`).join('');
    html += `<button type="button" data-block-page="${page + 1}" class="${btnCls}" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
    btns.innerHTML = html;
  }

  // 切换关键字 / 号码 tab
  function switchBlockTab(tab) {
    blockTab = tab;
    $$('.block-tab-btn').forEach((b) => b.classList.toggle('on', b.dataset.blockTab === tab));
    $('#block-mode-wrap').style.display = tab === 'number' ? '' : 'none';
    $('#block-value-label').textContent = tab === 'number'
      ? '号码（支持前缀，如 1068 / 95 / 400）'
      : '关键字（短信内容包含即命中）';
    $('#block-value').placeholder = tab === 'number' ? '例如：1068 或 13800138000' : '例如：退订、贷款、中奖';
    blockPage = 1;
    loadBlockRules(1);
  }

  // 添加规则
  async function addBlockRule() {
    const value = $('#block-value').value.trim();
    if (!value) { toast('请输入规则内容'); return; }
    const payload = {
      ruleType: blockTab,
      value,
      matchMode: blockTab === 'number' ? $('#block-mode').value : 'contains',
      note: $('#block-note').value.trim(),
    };
    try {
      const data = await API.addBlockRule(payload);
      toast(data.message || '添加成功');
      $('#block-value').value = '';
      $('#block-note').value = '';
      loadBlockRules();
    } catch (err) {
      toast(err.message);
    }
  }

  // 启停规则
  async function toggleBlockRule(id) {
    const r = blockRulesCache.find((x) => x.id === id);
    if (!r) return;
    try {
      const data = await API.updateBlockRule({ id, value: r.value, matchMode: r.matchMode, enabled: r.enabled === 1 ? 0 : 1, note: r.note || '' });
      toast(data.message || '已更新');
      loadBlockRules();
    } catch (err) {
      toast(err.message);
    }
  }

  // 删除规则
  async function deleteBlockRule(id) {
    const r = blockRulesCache.find((x) => x.id === id);
    const ok = await showConfirm(`确定删除规则「${r ? r.value : id}」吗？`);
    if (!ok) return;
    try {
      const data = await API.deleteBlockRule({ id });
      toast(data.message || '删除成功');
      loadBlockRules();
    } catch (err) {
      toast(err.message);
    }
  }

  // 恢复内置默认库
  async function resetBlockRules() {
    const ok = await showConfirm('确定恢复内置默认屏蔽库吗？将删除全部内置规则并重新写入默认数据（自定义规则保留）。', '恢复默认库', '确认恢复');
    if (!ok) return;
    try {
      const data = await API.resetBlockRules();
      toast(data.message || '已恢复内置默认库');
      loadBlockRules();
    } catch (err) {
      toast(err.message);
    }
  }

  // 格式化通话时长（秒 -> X分X秒）
  function formatDuration(sec) {
    sec = Math.max(0, Math.floor(sec));
    if (sec < 60) return sec + ' 秒';
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return s > 0 ? `${m} 分 ${s} 秒` : `${m} 分钟`;
  }

  // ---------------- 定时任务（计划任务） ----------------

  const WEEKDAY_NAMES = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

  let schedules = [];
  let schEditingId = 0;
  let schedulesPage = 1;

  function renderSchDeviceSelect(selected) {
    const sel = $('#sch-imei');
    if (!sel) return;
    if (!devices.length) {
      sel.innerHTML = '<option value="">暂无设备</option>';
      return;
    }
    sel.innerHTML = '<option value="">请选择设备</option>' + devices.map((d) =>
      `<option value="${esc(d.imei)}" ${d.imei === selected ? 'selected' : ''}>${d.name ? esc(d.name) + ' · ' : ''}${esc(d.imei)}${d.connected ? '' : ' [离线]'}</option>`).join('');
  }

  function renderSchTaskSelect(selected) {
    const sel = $('#sch-task');
    if (!sel) return;
    let html = TASK_GROUPS.map((g) =>
      `<optgroup label="${g.name}">` + g.tasks.map((t) => {
        const h = TASK_HELP[t];
        return h ? `<option value="${t}">${h.title}</option>` : '';
      }).join('') + '</optgroup>').join('');
    html += '<optgroup label="其他"><option value="__custom__">自定义命令</option></optgroup>';
    sel.innerHTML = html;
    if (selected && sel.querySelector(`option[value="${CSS.escape(selected)}"]`)) sel.value = selected;
  }

  // 周期类型变化：渲染对应参数控件（宝塔面板风格，参数下拉框统一固定宽度保持一行紧凑）
  function onSchCycleChange() {
    const type = $('#sch-cycle').value;
    const box = $('#sch-cycle-detail');
    const numSel = (id, from, to, def, w) => {
      let opts = '';
      for (let i = from; i <= to; i++) {
        opts += `<option value="${i}" ${i === def ? 'selected' : ''}>${String(i).padStart(2, '0')}</option>`;
      }
      return `<select id="${id}" class="input" style="width:${w || '4.2rem'}">${opts}</select>`;
    };
    const selCls = 'input';
    if (type === 'weekly') {
      box.innerHTML = `<span class="c-dim">每</span>` +
        `<select id="sch-c-weekday" class="${selCls}" style="width:4rem">` + WEEKDAY_NAMES.map((w, i) => `<option value="${i}">${w}</option>`).join('') + `</select>` +
        `<span class="c-dim">的</span>` + numSel('sch-c-hour', 0, 23, 8, '4.2rem') + `<span class="c-dim">点</span>` + numSel('sch-c-minute', 0, 59, 0, '4.2rem') + `<span class="c-dim">分</span>`;
    } else if (type === 'monthly') {
      box.innerHTML = `<span class="c-dim">每月</span>` + numSel('sch-c-day', 1, 31, 1, '4.2rem') + `<span class="c-dim">日</span>` + numSel('sch-c-hour', 0, 23, 8, '4.2rem') + `<span class="c-dim">点</span>` + numSel('sch-c-minute', 0, 59, 0, '4.2rem') + `<span class="c-dim">分</span>`;
    } else if (type === 'daily') {
      box.innerHTML = numSel('sch-c-hour', 0, 23, 8, '4.2rem') + `<span class="c-dim">点</span>` + numSel('sch-c-minute', 0, 59, 0, '4.2rem') + `<span class="c-dim">分</span>`;
    } else if (type === 'hourly') {
      box.innerHTML = `<span class="c-dim">每小时的</span>` + numSel('sch-c-minute', 0, 59, 0, '4.2rem') + `<span class="c-dim">分</span>`;
    } else if (type === 'interval_min') {
      box.innerHTML = `<span class="c-dim">每</span>` + numSel('sch-c-n', 1, 59, 5, '4.2rem') + `<span class="c-dim">分钟执行一次</span>`;
    } else if (type === 'interval_hour') {
      box.innerHTML = `<span class="c-dim">每</span>` + numSel('sch-c-n', 1, 23, 2, '4.2rem') + `<span class="c-dim">小时执行一次</span>`;
    } else {
      box.innerHTML = '';
    }
  }

  // 收集表单中的执行周期
  function getSchCycleSpec() {
    const type = $('#sch-cycle').value;
    const val = (id) => {
      const el = $('#' + id);
      return el ? parseInt(el.value, 10) : 0;
    };
    if (type === 'weekly') return { type: 'weekly', weekday: val('sch-c-weekday'), hour: val('sch-c-hour'), minute: val('sch-c-minute') };
    if (type === 'monthly') return { type: 'monthly', day: val('sch-c-day'), hour: val('sch-c-hour'), minute: val('sch-c-minute') };
    if (type === 'daily') return { type: 'daily', hour: val('sch-c-hour'), minute: val('sch-c-minute') };
    if (type === 'hourly') return { type: 'hourly', minute: val('sch-c-minute') };
    if (type === 'interval_min') return { type: 'interval', n: val('sch-c-n'), unit: 'minute' };
    if (type === 'interval_hour') return { type: 'interval', n: val('sch-c-n'), unit: 'hour' };
    return null;
  }

  // 编辑时把 spec 回填到表单
  function specToForm(spec) {
    if (!spec || !spec.type) return;
    $('#sch-cycle').value = spec.type === 'interval'
      ? (spec.unit === 'hour' ? 'interval_hour' : 'interval_min')
      : spec.type;
    onSchCycleChange();
    const set = (id, v) => {
      const el = $('#' + id);
      if (el && v != null) el.value = String(v);
    };
    set('sch-c-weekday', spec.weekday);
    set('sch-c-day', spec.day);
    set('sch-c-hour', spec.hour);
    set('sch-c-minute', spec.minute);
    set('sch-c-n', spec.n);
  }

  // 任务类型变化：渲染参数表单（基于 TASK_HELP 参数定义）
  function onSchTaskChange() {
    const task = $('#sch-task').value;
    const box = $('#sch-params');
    if (task === '__custom__') {
      box.innerHTML = `
        <div class="grid2" style="border-top:.5px solid var(--hair);padding-top:12px">
          <div>
            <label class="label" for="sch-custom-cmd">命令名称</label>
            <input id="sch-custom-cmd" type="text" class="input mono" placeholder="如 ussd_query、get_status、set_gpio">
          </div>
          <div>
            <label class="label" for="sch-custom-params">命令参数 <span class="dim" style="font-weight:400">（可选 JSON 对象）</span></label>
            <textarea id="sch-custom-params" rows="2" class="input mono" placeholder='{"pin": 15, "level": 1}'></textarea>
          </div>
        </div>`;
      return;
    }
    const h = TASK_HELP[task];
    if (!h || !h.params.length) {
      box.innerHTML = '<p class="dim" style="border-top:.5px solid var(--hair);padding-top:10px;font-size:11px">该任务无需参数</p>';
      return;
    }
    box.innerHTML = '<div class="grid2" style="border-top:.5px solid var(--hair);padding-top:12px">' + h.params.map((p) => {
      const isLong = p[0] === 'configText' || p[0] === 'content';
      return `<div>
        <label class="label" for="sch-p-${esc(p[0])}">${esc(p[0])}</label>
        ${isLong
          ? `<textarea id="sch-p-${esc(p[0])}" rows="3" class="textarea mono" style="font-size:11px"></textarea>`
          : `<input id="sch-p-${esc(p[0])}" type="text" class="input">`}
        <p class="dim" style="font-size:10px;margin-top:4px">${p[1]}</p>
      </div>`;
    }).join('') + '</div>';
  }

  // 收集表单中的任务参数
  function getSchParams() {
    const task = $('#sch-task').value;
    if (task === '__custom__') {
      const raw = $('#sch-custom-params') ? $('#sch-custom-params').value.trim() : '';
      let obj = {};
      if (raw) {
        try { obj = JSON.parse(raw); }
        catch (_) { throw new Error('命令参数不是合法 JSON'); }
      }
      return obj;
    }
    const h = TASK_HELP[task];
    const obj = {};
    if (h && h.params.length) {
      h.params.forEach((p) => {
        const el = $('#sch-p-' + p[0]);
        if (el) obj[p[0]] = el.value.trim();
      });
    }
    return obj;
  }

  function specDescribe(spec) {
    if (!spec || !spec.type) return '—';
    const p2 = (n) => String(n).padStart(2, '0');
    switch (spec.type) {
      case 'weekly': return '每周' + (WEEKDAY_NAMES[spec.weekday] || '') + ' ' + p2(spec.hour) + ':' + p2(spec.minute);
      case 'monthly': return '每月 ' + spec.day + ' 日 ' + p2(spec.hour) + ':' + p2(spec.minute);
      case 'daily': return '每天 ' + p2(spec.hour) + ':' + p2(spec.minute);
      case 'hourly': return '每小时 ' + p2(spec.minute) + ' 分';
      case 'interval': return spec.unit === 'hour' ? '每 ' + spec.n + ' 小时' : '每 ' + spec.n + ' 分钟';
    }
    return '—';
  }

  async function loadSchedules(page) {
    if (typeof page === 'number') schedulesPage = page;
    try {
      const data = await API.schedules(schedulesPage);
      schedulesPage = data.page || schedulesPage;
      schedules = data.schedules || [];
      // 当前页被删空时自动回退一页
      if (!schedules.length && schedulesPage > 1) {
        schedulesPage -= 1;
        return loadSchedules(schedulesPage);
      }
      renderSchedules();
      renderSchedulePagination(data.total || 0, schedulesPage);
    } catch (err) {
      $('#schedules-tbody').innerHTML = `<tr><td colspan="7" class="empty" style="color:var(--red)">${esc(err.message)}</td></tr>`;
      renderSchedulePagination(0, 1);
    }
  }

  // 渲染定时任务分页控件（每页 5 条）
  function renderSchedulePagination(total, page) {
    const wrap = $('#schedules-pagination');
    const info = $('#schedules-page-info');
    const btns = $('#schedules-page-btns');
    const pageSize = 5;
    const totalPages = Math.max(1, Math.ceil(total / pageSize));

    if (total <= 0) {
      wrap.classList.add('hidden');
      return;
    }
    wrap.classList.remove('hidden');
    info.textContent = `共 ${total} 条 · 第 ${page} / ${totalPages} 页`;

    const list = [];
    for (let i = 1; i <= totalPages; i++) {
      if (i === 1 || i === totalPages || Math.abs(i - page) <= 1) list.push(i);
      else if (list[list.length - 1] !== '…') list.push('…');
    }
    const btnCls = '';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `
      <button type="button" data-page="${page - 1}" class="${btnCls}" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="faint" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-page="${p}" class="${btnCls} ${p === page ? 'on' : ''}" style="min-width:2rem">${p}</button>`
    ).join('');
    html += `
      <button type="button" data-page="${page + 1}" class="${btnCls}" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
    btns.innerHTML = html;
  }

  function renderSchedules() {
    const tbody = $('#schedules-tbody');
    if (!schedules.length) {
      tbody.innerHTML = '<tr><td colspan="7" class="empty">暂无定时任务</td></tr>';
      return;
    }
    tbody.innerHTML = schedules.map((s) => {
      const taskLabel = TASK_HELP[s.task] ? TASK_HELP[s.task].title : s.task;
      const deviceLabel = s.deviceName || s.imei;
      const name = s.name || ('任务 #' + s.id);
      return `
      <tr>
        <td >${esc(name)}</td>
        <td class="dim">${esc(deviceLabel)}${s.deviceName ? `<span class="sub">${esc(s.imei)}</span>` : ''}</td>
        <td class="dim"><span class="font-medium">${esc(taskLabel)}</span><span class="sub">${esc(s.task)}</span></td>
        <td class="dim">${esc(specDescribe(s.spec))}</td>
        <td class="faint">${fmtTime(s.lastExecuted)}</td>
        <td class="px-4 py-3">${s.enabled ? '<span class="badge-online">已启用</span>' : '<span class="badge-offline">已停用</span>'}</td>
        <td class="right">
          <button class="mini-btn" data-sch-run="${s.id}">执行</button>
          <button class="mini-btn" data-sch-toggle="${s.id}" data-next="${s.enabled ? 0 : 1}">${s.enabled ? '停用' : '启用'}</button>
          <button class="mini-btn" data-sch-edit="${s.id}">编辑</button>
          <button class="mini-btn danger" data-sch-del="${s.id}">删除</button>
        </td>
      </tr>`;
    }).join('');
  }

  async function handleScheduleSubmit(e) {
    e.preventDefault();
    const imei = $('#sch-imei').value;
    if (!imei) { toast('请选择目标设备', false); return; }
    let params;
    try { params = getSchParams(); }
    catch (err) { toast(err.message, false); return; }
    const taskSel = $('#sch-task').value;
    let task = taskSel;
    if (taskSel === '__custom__') {
      const cmd = $('#sch-custom-cmd') ? $('#sch-custom-cmd').value.trim() : '';
      if (!cmd) { toast('请输入命令名称', false); return; }
      task = cmd;
    }
    const spec = getSchCycleSpec();
    if (!spec) { toast('请选择执行周期', false); return; }

    const payload = {
      name: $('#sch-name').value.trim(),
      imei, task, params, spec,
      enabled: $('#sch-enabled').checked,
    };
    const btn = $('#sch-btn');
    const wasEditing = !!schEditingId;
    btn.disabled = true;
    try {
      const data = wasEditing
        ? await API.updateSchedule(Object.assign({ id: schEditingId }, payload))
        : await API.addSchedule(payload);
      toast(data.message);
      cancelScheduleEdit();
      loadSchedules(wasEditing ? schedulesPage : 1);
    } catch (err) {
      toast(err.message, false);
    } finally {
      btn.disabled = false;
    }
  }

  function editSchedule(id) {
    const s = schedules.find((x) => x.id === id);
    if (!s) return;
    schEditingId = s.id;
    $('#sch-edit-id').value = String(s.id);
    $('#sch-name').value = s.name || '';
    renderSchDeviceSelect(s.imei);
    let params = {};
    try { params = JSON.parse(s.params || '{}'); } catch (_) { /* 忽略 */ }
    if (TASK_HELP[s.task]) {
      renderSchTaskSelect(s.task);
      onSchTaskChange();
      Object.keys(params).forEach((k) => {
        const el = $('#sch-p-' + k);
        if (el) el.value = params[k] != null ? String(params[k]) : '';
      });
    } else {
      renderSchTaskSelect('__custom__');
      onSchTaskChange();
      if ($('#sch-custom-cmd')) $('#sch-custom-cmd').value = s.task;
      if ($('#sch-custom-params')) $('#sch-custom-params').value = s.params && s.params !== '{}' ? s.params : '';
    }
    specToForm(s.spec);
    $('#sch-enabled').checked = s.enabled;
    $('#sch-btn').textContent = '保存修改';
    $('#sch-cancel').classList.remove('hidden');
    toast('正在编辑任务 #' + s.id);
    $('#schedule-form').scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function cancelScheduleEdit() {
    schEditingId = 0;
    $('#sch-edit-id').value = '';
    $('#sch-name').value = '';
    renderSchDeviceSelect();
    renderSchTaskSelect();
    $('#sch-task').selectedIndex = 0;
    onSchTaskChange();
    $('#sch-cycle').value = 'daily';
    onSchCycleChange();
    $('#sch-enabled').checked = true;
    $('#sch-btn').textContent = '添加任务';
    $('#sch-cancel').classList.add('hidden');
  }

  async function runScheduleNow(id) {
    toast('正在下发任务，等待设备回报...');
    try {
      const data = await API.runSchedule({ id });
      const result = data.result;
      if (result && typeof result === 'object' && result.error) throw new Error(result.error);
      toast('执行成功，结果见任务记录');
      loadSchedules();
    } catch (err) {
      toast(err.message, false);
    }
  }

  async function toggleScheduleRow(id, next) {
    try {
      const data = await API.toggleSchedule({ id, enabled: !!next });
      toast(data.message);
      loadSchedules();
    } catch (err) {
      toast(err.message, false);
    }
  }

  async function deleteScheduleRow(id) {
    const s = schedules.find((x) => x.id === id);
    const ok = await showConfirm(`确定删除定时任务「${s ? (s.name || '#' + s.id) : '#' + id}」吗？删除后不可恢复。`);
    if (!ok) return;
    try {
      const data = await API.deleteSchedule({ id });
      toast(data.message);
      loadSchedules();
    } catch (err) {
      toast(err.message, false);
    }
  }

  // ---------------- 自定义确认弹窗 ----------------

  let confirmResolver = null;

  // 打开确认弹窗，返回 Promise<boolean>（确认=true / 取消=false）
  function showConfirm(message, title = '确认操作', okText = '确认删除') {
    $('#confirm-title').textContent = title;
    $('#confirm-message').textContent = message;
    $('#confirm-ok').textContent = okText;
    $('#confirm-modal').classList.remove('hidden');
    $('#confirm-ok').focus();
    return new Promise((resolve) => { confirmResolver = resolve; });
  }

  function closeConfirm(result) {
    $('#confirm-modal').classList.add('hidden');
    if (confirmResolver) {
      confirmResolver(result);
      confirmResolver = null;
    }
  }

  // 清理任务日志（days > 0 删除 days 天前旧日志，days <= 0 删除全部）
  async function clearTasks(days) {
    const ok = await showConfirm(
      days > 0 ? '确定删除 7 天前的旧日志吗？删除后不可恢复。' : '确定删除全部任务记录吗？删除后不可恢复。'
    );
    if (!ok) return;
    try {
      const data = await API.clearTasks({ days });
      toast(`已删除 ${data.deleted} 条记录`);
      loadTasks(1);
    } catch (err) {
      toast(err.message, false);
    }
  }

  // ---------------- 设置 ----------------

  async function handleSettings(e) {
    e.preventDefault();
    const oldPassword = $('#set-old-password').value;
    const newUsername = $('#set-new-username').value.trim();
    const newPassword = $('#set-new-password').value;
    if (!oldPassword) { toast('请填写原密码', false); return; }
    const msg = $('#settings-msg');
    msg.className = 'hidden';
    try {
      const data = await API.changeUserInfo({ oldPassword, newUsername, newPassword });
      msg.textContent = data.message;
      msg.className = 'text-sm ' + (data.needRelogin ? 'c-warn' : 'text-emerald-600');
      if (data.needRelogin) {
        if (newUsername) localStorage.setItem('panel_username', newUsername);
        toast('信息已修改，请重新登录');
        setTimeout(handleLogout, 1200);
      } else {
        toast('保存成功');
      }
      $('#set-old-password').value = '';
      $('#set-new-password').value = '';
    } catch (err) {
      msg.textContent = err.message;
      msg.className = 'text-sm text-red-600';
    }
  }

  // ---------------- 离线通知设置 ----------------

  let notifyChannelDefs = []; // /api/notify/channels 返回的渠道定义
  let notifySettings = null;  // /api/settings 返回的设置

  // 加载设置与渠道定义，渲染离线通知表单
  async function loadNotifySettings() {
    const list = $('#notify-channels-list');
    if (!list) return;
    try {
      const [defs, settings] = await Promise.all([API.notifyChannels(), API.getSettings()]);
      notifyChannelDefs = defs;
      notifySettings = settings;
      $('#set-notify-enabled').checked = !!settings.notifyEnabled;
      renderNotifyChannels();
    } catch (err) {
      toast(err.message, false);
    }
  }

  // 渲染渠道勾选列表 + 各渠道配置表单
  function renderNotifyChannels() {
    const list = $('#notify-channels-list');
    const cfgWrap = $('#notify-channel-configs');
    const selected = notifySettings.notifyChannels || [];
    const config = notifySettings.notifyConfig || {};
    list.innerHTML = '';
    cfgWrap.innerHTML = '';
    notifyChannelDefs.forEach((ch) => {
      const checked = selected.includes(ch.name);
      const label = document.createElement('label');
      label.className = checked ? 'chip on' : 'chip';
      label.innerHTML = '<input type="checkbox" data-channel="' + esc(ch.name) + '" ' + (checked ? 'checked' : '') + '> <span>' + esc(ch.label) + '</span>';
      list.appendChild(label);

      // 各渠道配置表单
      const box = document.createElement('div');
      box.id = 'nch-cfg-' + ch.name;
      box.dataset.channel = ch.name;
      box.className = 'rounded-lg border border-slate-200 p-4';
      box.style.display = checked ? '' : 'none';
      const fields = ch.fields.map((f) => {
        const val = (config[ch.name] || {})[f.key] || '';
        let input;
        if (f.type === 'textarea') {
          input = '<textarea data-key="' + esc(f.key) + '" rows="2" class="input" placeholder="' + esc(f.placeholder || '') + '">' + esc(val) + '</textarea>';
        } else {
          const t = f.type === 'password' ? 'password' : f.type === 'number' ? 'number' : 'text';
          input = '<input type="' + t + '" data-key="' + esc(f.key) + '" class="input" placeholder="' + esc(f.placeholder || '') + '" value="' + esc(val) + '">';
        }
        return '<div class="' + (f.type === 'textarea' ? 'sm:col-span-2' : '') + '">' +
          '<label class="label">' + esc(f.label) + (f.required ? ' <span class="c-err">*</span>' : '') + '</label>' +
          input + '</div>';
      }).join('');
      box.innerHTML = '<h4 class="text-sm font-semibold text-slate-700">' + esc(ch.label) + ' 配置</h4>' +
        '<div class="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-3">' + fields + '</div>';
      cfgWrap.appendChild(box);
    });
  }

  // 勾选渠道时显示/隐藏对应配置表单
  function onNotifyChannelChange(ev) {
    const cb = ev.target.closest('input[type="checkbox"][data-channel]');
    if (!cb) return;
    const box = $('#nch-cfg-' + cb.dataset.channel);
    const label = cb.closest('label');
    if (box) box.style.display = cb.checked ? '' : 'none';
    if (label) {
      label.className = cb.checked ? 'chip on' : 'chip';
    }
  }

  // 保存离线通知设置
  async function handleNotifySettings(e) {
    e.preventDefault();
    const msg = $('#notify-settings-msg');
    msg.className = 'hidden';
    const enabled = $('#set-notify-enabled').checked;
    const channels = collectNotifyChannels();
    const config = collectNotifyConfig(channels);
    try {
      await API.saveSettings({ notifyEnabled: enabled, notifyChannels: channels, notifyConfig: config });
      notifySettings.notifyChannels = channels;
      notifySettings.notifyConfig = config;
      notifySettings.notifyEnabled = enabled;
      msg.textContent = '设置已保存';
      msg.className = 'text-sm text-emerald-600';
      toast('设置已保存');
    } catch (err) {
      msg.textContent = err.message;
      msg.className = 'text-sm text-red-600';
    }
  }

  // 收集当前勾选的渠道列表
  function collectNotifyChannels() {
    return $$('#notify-channels-list input[data-channel]')
      .filter((cb) => cb.checked)
      .map((cb) => cb.dataset.channel);
  }

  // ---------------- 灯光控制设置 ----------------

  // 加载灯光控制设置（来短信/来电话灯光）
  async function loadLedSettings() {
    const wrap = $('#led-settings-form');
    if (!wrap) return;
    try {
      if (!notifySettings) notifySettings = await API.getSettings();
      const sms = notifySettings.smsLed || {};
      const call = notifySettings.callLed || {};
      $('#led-sms-enabled').checked = !!sms.enabled;
      $('#led-sms-color').value = sms.color || 'blue';
      $('#led-sms-blink').checked = !!sms.blink;
      $('#led-sms-duration').value = sms.duration || 5000;
      $('#led-call-enabled').checked = !!call.enabled;
      $('#led-call-color').value = call.color || 'red';
      $('#led-call-blink').checked = !!call.blink;
      $('#led-call-duration').value = call.duration || 5000;
    } catch (err) {
      toast(err.message, false);
    }
  }

  // 保存灯光控制设置
  async function handleLedSettings(e) {
    e.preventDefault();
    const msg = $('#led-settings-msg');
    msg.className = 'hidden';
    const smsLed = {
      enabled: $('#led-sms-enabled').checked,
      color: $('#led-sms-color').value,
      blink: $('#led-sms-blink').checked,
      duration: parseInt($('#led-sms-duration').value, 10) || 5000,
    };
    const callLed = {
      enabled: $('#led-call-enabled').checked,
      color: $('#led-call-color').value,
      blink: $('#led-call-blink').checked,
      duration: parseInt($('#led-call-duration').value, 10) || 5000,
    };
    try {
      // 保存时带上现有通知设置，避免被覆盖
      const payload = {
        notifyEnabled: notifySettings ? !!notifySettings.notifyEnabled : false,
        notifyChannels: notifySettings && notifySettings.notifyChannels ? notifySettings.notifyChannels : [],
        notifyConfig: notifySettings && notifySettings.notifyConfig ? notifySettings.notifyConfig : {},
        smsLed: smsLed,
        callLed: callLed,
      };
      await API.saveSettings(payload);
      notifySettings = Object.assign({}, notifySettings, { smsLed: smsLed, callLed: callLed });
      msg.textContent = '设置已保存';
      msg.className = 'text-sm text-emerald-600';
      toast('灯光设置已保存');
    } catch (err) {
      msg.textContent = err.message;
      msg.className = 'text-sm text-red-600';
    }
  }

  // ---------------- 省电模式设置 ----------------

  // 解析 Lua 配置文本中的顶层键值
  function parseLuaConfig(text) {
    const out = {};
    const re = /^(\w+)\s*=\s*(.+?)\s*$/gm;
    let m;
    while ((m = re.exec(text))) {
      let v = m[2].trim();
      if (v.startsWith('"')) { out[m[1]] = v.replace(/^"|"$/g, ''); }
      else if (v === 'true' || v === 'false') { out[m[1]] = v === 'true'; }
      else if (!isNaN(Number(v))) { out[m[1]] = Number(v); }
      else { out[m[1]] = v; }
    }
    return out;
  }

  // 把键值写回 Lua 配置文本；键不存在则追加到文件末尾
  function patchLuaConfig(text, kv) {
    let out = text;
    for (const k in kv) {
      const v = kv[k];
      let valStr;
      if (typeof v === 'number') valStr = String(v);
      else if (typeof v === 'boolean') valStr = v ? 'true' : 'false';
      else valStr = '"' + v + '"';
      const re = new RegExp('^(\\s*)(' + k + '\\s*=\\s*)[^\\n]*', 'm');
      const before = out;
      out = out.replace(re, (_, lead, pre) => lead + pre + valStr);
      if (out === before) {
        out = out.replace(/\s*$/, '\n') + k + ' = ' + valStr + '\n';
      }
    }
    return out;
  }

  // 填充省电设备下拉
  function fillPowersaveDevice() {
    const sel = $('#powersave-device');
    if (!sel) return;
    const prev = sel.value;
    sel.innerHTML = devices.map((d) =>
      `<option value="${esc(d.imei)}">${d.name ? esc(d.name) + ' · ' : ''}${esc(d.imei)}</option>`).join('');
    if (prev) sel.value = prev;
    else if (devices.length === 1) sel.value = devices[0].imei;
  }

  // 填充开始/结束小时下拉（0-23）
  function fillHourSelects() {
    const s = $('#powersave-start');
    const e = $('#powersave-end');
    if (!s || !e) return;
    const opts = [];
    for (let h = 0; h < 24; h++) opts.push(`<option value="${h}">${h} 点</option>`);
    if (s.options.length === 0) s.innerHTML = opts.join('');
    if (e.options.length === 0) e.innerHTML = opts.join('');
  }

  // 设置"省电模式"开关按钮状态（绿=关闭，黄=开启），data-state: off/on
  // 设置"省电模式"开关按钮状态（关闭=绿，开启=黄），data-state: off/on
  function setPowerSaveToggle(en) {
    const btn = $('#powersave-toggle-btn');
    if (!btn) return;
    btn.dataset.state = en ? 'on' : 'off';
    btn.style.background = en ? '#f59e0b' : '#16a34a';
    btn.style.color = en ? '#1f2937' : '#fff';
  }

  // 读取设备省电配置
  async function loadPowersaveSettings() {
    fillHourSelects();
    const sel = $('#powersave-device');
    if (!sel) return;
    fillPowersaveDevice();
    const imei = sel.value;
    if (!imei) { toast('请先添加设备', false); return; }
    try {
      const data = await API.executeTask({ imei, task: 'get_config' });
      const result = data.result;
      let text = '';
      if (typeof result === 'string') text = result;
      else if (result && result.content) text = result.content;
      else if (result && result.config) text = result.config;
      else if (result) text = JSON.stringify(result);
      const cfg = parseLuaConfig(text);
      // 仅在设备配置显式 POWERSAVE_ENABLE=true 时置为开启；未配置/默认 false 显示关闭，与实际一致
      setPowerSaveToggle(cfg.POWERSAVE_ENABLE === true);
      $('#powersave-start').value = cfg.POWERSAVE_START_HOUR || 1;
      $('#powersave-end').value = cfg.POWERSAVE_END_HOUR || 8;
      const deep = cfg.POWERSAVE_DEEP === true;
      $$('input[name="powersave-deep"]').forEach((r) => { r.checked = (r.value === 'true') === deep; });
      $('#powersave-heartbeat').value = cfg.POWERSAVE_HEARTBEAT || 600000;
      $('#powersave-telemetry').value = cfg.POWERSAVE_TELEMETRY || 0;
      $('#powersave-msg').className = 'hidden';
    } catch (err) { toast(err.message, false); }
  }

  // 保存省电配置
  async function handlePowersaveSettings(e) {
    e.preventDefault();
    const msg = $('#powersave-msg');
    msg.className = 'hidden';
    const imei = $('#powersave-device').value;
    if (!imei) { msg.textContent = '请选择目标设备'; msg.className = 'text-sm text-red-600'; return; }
    const deepRadio = $$('input[name="powersave-deep"]:checked')[0];
    const kv = collectPowersaveKv();
    try {
      const data = await API.executeTask({ imei, task: 'get_config' });
      const result = data.result;
      let text = '';
      if (typeof result === 'string') text = result;
      else if (result && result.content) text = result.content;
      else if (result && result.config) text = result.config;
      else if (result) text = JSON.stringify(result);
      const patched = patchLuaConfig(text, kv);
      await API.executeTask({ imei, task: 'set_config', configText: patched });
      msg.textContent = '省电配置已保存并下发设备';
      msg.className = 'text-sm text-emerald-600';
      toast('省电配置已保存');
    } catch (err) {
      msg.textContent = err.message;
      msg.className = 'text-sm text-red-600';
    }
  }

  // 收集省电表单的配置键值
  function collectPowersaveKv() {
    const deepRadio = $$('input[name="powersave-deep"]:checked')[0];
    const toggle = $('#powersave-toggle-btn');
    return {
      POWERSAVE_ENABLE: toggle ? toggle.dataset.state === 'on' : false,
      POWERSAVE_START_HOUR: parseInt($('#powersave-start').value, 10) || 1,
      POWERSAVE_END_HOUR: parseInt($('#powersave-end').value, 10) || 8,
      POWERSAVE_DEEP: deepRadio ? deepRadio.value === 'true' : false,
      POWERSAVE_HEARTBEAT: parseInt($('#powersave-heartbeat').value, 10) || 600000,
      POWERSAVE_TELEMETRY: parseInt($('#powersave-telemetry').value, 10) || 0,
    };
  }

  // 读取 get_config 结果中的配置文本
  function powersaveCfgText(data) {
    const result = data.result;
    if (typeof result === 'string') return result;
    if (result && result.content) return result.content;
    if (result && result.config) return result.config;
    if (result) return JSON.stringify(result);
    return '';
  }

  // ---------------- 通话录音设置 ----------------

  // 填充通话录音设备下拉
  function fillRecordDevice() {
    const sel = $('#record-device');
    if (!sel) return;
    const prev = sel.value;
    sel.innerHTML = devices.map((d) =>
      `<option value="${esc(d.imei)}">${d.name ? esc(d.name) + ' · ' : ''}${esc(d.imei)}</option>`).join('');
    if (prev) sel.value = prev;
    else if (devices.length === 1) sel.value = devices[0].imei;
  }

  // 读取设备通话录音配置
  async function loadRecordSettings() {
    fillRecordDevice();
    const sel = $('#record-device');
    if (!sel) return;
    const imei = sel.value;
    if (!imei) { toast('请先添加设备', false); return; }
    try {
      const data = await API.executeTask({ imei, task: 'get_config' });
      const text = powersaveCfgText(data);
      const cfg = parseLuaConfig(text);
      // 勾选状态：仅当设备配置显式 false 时取消勾选；未配置默认开启
      $('#record-enable').checked = cfg.RECORD_ENABLE !== false;
      $('#record-tts-before').checked = cfg.TTS_BEFORE_ENABLE !== false;
      const msg = $('#record-msg');
      if (msg) msg.className = 'hidden';
    } catch (err) { toast(err.message, false); }
  }

  // 保存通话录音配置
  async function handleRecordSettings(e) {
    e.preventDefault();
    const msg = $('#record-msg');
    msg.className = 'hidden';
    const imei = $('#record-device').value;
    if (!imei) { msg.textContent = '请选择目标设备'; msg.className = 'text-sm text-red-600'; return; }
    const toggle = $('#record-enable');
    const kv = {
      RECORD_ENABLE: $('#record-enable').checked,
      TTS_BEFORE_ENABLE: $('#record-tts-before').checked,
    };
    try {
      const data = await API.executeTask({ imei, task: 'get_config' });
      const patched = patchLuaConfig(powersaveCfgText(data), kv);
      await API.executeTask({ imei, task: 'set_config', configText: patched });
      msg.textContent = '通话录音配置已保存并下发设备';
      msg.className = 'text-sm text-emerald-600';
      toast('通话录音配置已保存');
    } catch (err) {
      msg.textContent = err.message;
      msg.className = 'text-sm text-red-600';
    }
  }

  // 立即进入省电：先保存当前表单配置（含档位），再下发立即进入
  async function powersaveEnterNow() {
    const msg = $('#powersave-msg');
    const imei = $('#powersave-device').value;
    if (!imei) { toast('请先选择目标设备', false); return; }
    const btn = $('#powersave-enter-btn');
    const oldText = btn.textContent;
    btn.disabled = true; btn.textContent = '进入中...';
    try {
      const kv = collectPowersaveKv();
      kv.POWERSAVE_ENABLE = true; // 立即进入即视为启用省电
      const data = await API.executeTask({ imei, task: 'get_config' });
      const patched = patchLuaConfig(powersaveCfgText(data), kv);
      await API.executeTask({ imei, task: 'set_config', configText: patched });
      const res = await API.executeTask({ imei, task: 'powersave', action: 'enter' });
      const info = res && res.result && res.result.message ? res.result.message : '已立即进入省电';
      setPowerSaveToggle(true); // 立即进入即视为启用省电，同步开关状态
      if (msg) { msg.textContent = info; msg.className = 'text-sm text-emerald-600'; }
      toast(info);
    } catch (err) {
      if (msg) { msg.textContent = err.message; msg.className = 'text-sm text-red-600'; }
      toast(err.message, false);
    } finally {
      btn.disabled = false; btn.textContent = oldText;
    }
  }

  // 立即退出省电
  async function powersaveExitNow() {
    const msg = $('#powersave-msg');
    const imei = $('#powersave-device').value;
    if (!imei) { toast('请先选择目标设备', false); return; }
    const btn = $('#powersave-exit-btn');
    const oldText = btn.textContent;
    btn.disabled = true; btn.textContent = '退出中...';
    try {
      const res = await API.executeTask({ imei, task: 'powersave', action: 'exit' });
      const info = res && res.result && res.result.message ? res.result.message : '已立即退出省电';
      if (msg) { msg.textContent = info; msg.className = 'text-sm text-emerald-600'; }
      toast(info);
    } catch (err) {
      if (msg) { msg.textContent = err.message; msg.className = 'text-sm text-red-600'; }
      toast(err.message, false);
    } finally {
      btn.disabled = false; btn.textContent = oldText;
    }
  }

  // 收集当前勾选渠道的配置表单值
  function collectNotifyConfig(channels) {
    const config = {};
    notifyChannelDefs.forEach((ch) => {
      const box = $('#nch-cfg-' + ch.name);
      if (!box || !channels.includes(ch.name)) return;
      const values = {};
      box.querySelectorAll('[data-key]').forEach((el) => { values[el.dataset.key] = el.value.trim(); });
      config[ch.name] = values;
    });
    return config;
  }

  // 发送测试通知：用当前表单填写的渠道与配置立即推送一条测试消息
  async function sendTestNotify() {
    const channels = collectNotifyChannels();
    if (channels.length === 0) { toast('请先勾选至少一个通知渠道', false); return; }
    const config = collectNotifyConfig(channels);
    const btn = $('#notify-test-btn');
    const oldText = btn.textContent;
    btn.disabled = true;
    btn.textContent = '发送中...';
    try {
      const res = await API.testNotify({ channels, config });
      toast(res.message || '测试通知已发送', res.success !== false);
    } catch (err) {
      toast(err.message, false);
    } finally {
      btn.disabled = false;
      btn.textContent = oldText;
    }
  }

  // ---------------- 通话录音（WebDAV）列表 ----------------

  async function loadRecordings() {
    const tbody = $('#recordings-tbody');
    const empty = $('#recordings-empty');
    if (!tbody) return;
    tbody.innerHTML = '<tr><td colspan="4" class="empty">加载中...</td></tr>';
    try {
      const data = await API.recordings();
      if (!data.success) throw new Error(data.error || '获取录音失败');
      const files = data.files || [];
      if (empty) empty.classList.toggle('hidden', files.length > 0);
      if (files.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4" class="empty">暂无录音文件</td></tr>';
        return;
      }
      tbody.innerHTML = files.map((f, i) => {
        const aid = 'rec-audio-' + i;
        return `<tr>
          <td class="mono" title="${esc(f.name)}">${esc(f.name)}</td>
          <td class="dim">${fmtSize(f.size)}</td>
          <td class="dim">${esc(f.modTime || '')}</td>
          <td class="px-4 py-3">
            <div class="flex items-center gap-2">
              <button type="button" class="mini-btn primary" data-play="${esc(f.url)}" data-audio="${aid}">播放</button>
              <audio id="${aid}" controls preload="none" class="hidden" style="width:13rem;height:2rem"></audio>
            </div>
          </td>
        </tr>`;
      }).join('');
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="4" class="empty" style="color:var(--red)">${esc(err.message)}</td></tr>`;
    }
  }

  function fmtSize(n) {
    if (!n) return '0 B';
    if (n < 1024) return n + ' B';
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + ' KB';
    return (n / 1024 / 1024).toFixed(1) + ' MB';
  }

  // ---------------- 存储配置（WebDAV） ----------------

  function fillStoreDevice() {
    const sel = $('#store-device');
    if (!sel) return;
    const prev = sel.value;
    sel.innerHTML = devices.map((d) =>
      `<option value="${esc(d.imei)}">${d.name ? esc(d.name) + ' · ' : ''}${esc(d.imei)}</option>`).join('');
    if (prev) sel.value = prev;
    else if (devices.length === 1) sel.value = devices[0].imei;
  }

  async function loadStoreSettings() {
    fillStoreDevice();
    try {
      const settings = await API.getSettings();
      const wd = settings.webdav || {};
      $('#store-url').value = wd.url || '';
      $('#store-user').value = wd.username || '';
      $('#store-pass').value = wd.password || '';
      $('#store-dir').value = wd.dir || '通话录音';
      const msg = $('#store-msg');
      if (msg) msg.className = 'hidden';
    } catch (err) { toast(err.message, false); }
  }

  // 保存存储配置到服务端（回传全量 settings，避免覆盖通知 / 灯光配置）
  async function handleStoreSettings(e) {
    e.preventDefault();
    const msg = $('#store-msg');
    msg.className = 'hidden';
    try {
      const settings = await API.getSettings();
      const payload = {
        notifyEnabled: settings.notifyEnabled,
        notifyChannels: settings.notifyChannels || [],
        notifyConfig: settings.notifyConfig || {},
        smsLed: settings.smsLed,
        callLed: settings.callLed,
        webdav: {
          url: $('#store-url').value.trim(),
          username: $('#store-user').value.trim(),
          password: $('#store-pass').value.trim(),
          dir: $('#store-dir').value.trim() || '通话录音',
        },
      };
      await API.saveSettings(payload);
      msg.textContent = '存储配置已保存';
      msg.className = 'text-sm text-emerald-600';
      toast('存储配置已保存');
    } catch (err) {
      msg.textContent = err.message;
      msg.className = 'text-sm text-red-600';
    }
  }

  // 下发 WebDAV 配置到设备（nvm: WEBDAV_URL / USER / PASS / RECORD_DIR）
  async function pushStoreToDevice() {
    const msg = $('#store-msg');
    const imei = $('#store-device').value;
    if (!imei) { toast('请先选择目标设备', false); return; }
    const btn = $('#store-push-btn');
    const oldText = btn.textContent;
    btn.disabled = true; btn.textContent = '下发中...';
    try {
      const kv = {
        WEBDAV_URL: $('#store-url').value.trim(),
        WEBDAV_USER: $('#store-user').value.trim(),
        WEBDAV_PASS: $('#store-pass').value.trim(),
        RECORD_DIR: $('#store-dir').value.trim() || '通话录音',
      };
      const data = await API.executeTask({ imei, task: 'get_config' });
      const patched = patchLuaConfig(powersaveCfgText(data), kv);
      await API.executeTask({ imei, task: 'set_config', configText: patched });
      msg.textContent = 'WebDAV 配置已下发到设备';
      msg.className = 'text-sm text-emerald-600';
      toast('已下发到设备');
    } catch (err) {
      msg.textContent = err.message;
      msg.className = 'text-sm text-red-600';
      toast(err.message, false);
    } finally {
      btn.disabled = false; btn.textContent = oldText;
    }
  }

  // ---------------- 初始化 ----------------

  function cycleAppearance() {
    const b = document.body;
    if (b.dataset.theme === 'dark') { delete b.dataset.theme; localStorage.removeItem('panel_theme'); }
    else { b.dataset.theme = 'dark'; localStorage.setItem('panel_theme', 'dark'); }
  }

  function bindEvents() {
    paintIcons(document);
    $('#login-form').addEventListener('submit', handleLogin);
    $('#logout-btn').addEventListener('click', handleLogout);
    $('#restart-btn').addEventListener('click', handleServerRestart);
    bindBrandUptime(); // 顶部 Logo hover 显示已运行时长
    $('#ui-logo').addEventListener('input', updateUiPreview);
    $('#ui-save-btn').addEventListener('click', saveUiSettings);
    $('#ui-reset-btn').addEventListener('click', resetUiSettings);
    $('#refresh-devices').addEventListener('click', loadDevices);
    $('#task-form').addEventListener('submit', handleTaskSubmit);
    $$('input[name="task-type"]').forEach((r) => r.addEventListener('change', onTaskTypeChange));
    $('#console-clear').addEventListener('click', resetConsole);
    $('#settings-form').addEventListener('submit', handleSettings);
    $('#notify-settings-form').addEventListener('submit', handleNotifySettings);
    $('#recordings-refresh').addEventListener('click', loadRecordings);
    // 播放录音：点击带认证拉取音频为 Blob 后播放
    $('#recordings-tbody').addEventListener('click', async (e) => {
      const btn = e.target.closest('[data-play]');
      if (!btn) return;
      const audio = document.getElementById(btn.dataset.audio);
      if (!audio) return;
      try {
        const url = await API.fetchAudio(btn.dataset.play);
        audio.src = url;
        audio.classList.remove('hidden');
        audio.play().catch(() => {});
      } catch (err) { toast(err.message, false); }
    });
    $('#store-form').addEventListener('submit', handleStoreSettings);
    $('#store-push-btn').addEventListener('click', pushStoreToDevice);
    $('#notify-test-btn').addEventListener('click', sendTestNotify);
    $('#notify-channels-list').addEventListener('change', onNotifyChannelChange);
    $('#led-settings-form').addEventListener('submit', handleLedSettings);
    $('#powersave-form').addEventListener('submit', handlePowersaveSettings);
    $('#powersave-enter-btn').addEventListener('click', powersaveEnterNow);
    $('#powersave-exit-btn').addEventListener('click', powersaveExitNow);
    // "省电模式"开关按钮：点击切换启用/停用并变色（保存由"保存设置"提交）
    $('#powersave-toggle-btn').addEventListener('click', () => {
      const cur = $('#powersave-toggle-btn').dataset.state === 'on';
      setPowerSaveToggle(!cur);
    });
    // 设置页 Tab 切换（原型：左侧竖向 set-nav + 右侧 set-panel）
    $$('.set-item').forEach((btn) => {
      btn.addEventListener('click', () => {
        const tab = btn.dataset.set;
        $$('.set-item').forEach((b) => b.classList.toggle('on', b.dataset.set === tab));
        $$('.set-panel').forEach((p) => p.classList.toggle('on', p.dataset.panel === tab));
        if (tab === 'led') loadLedSettings();
        if (tab === 'powersave') loadPowersaveSettings();
        if (tab === 'record') loadRecordSettings();
      });
    });
    // 通话录音设置保存（勾选开关无需额外点击逻辑，随表单提交）
    $('#record-form').addEventListener('submit', handleRecordSettings);
    $('#clear-tasks-7d').addEventListener('click', () => clearTasks(7));
    $('#clear-tasks-all').addEventListener('click', () => clearTasks(0));
    // 定时任务
    $('#schedule-form').addEventListener('submit', handleScheduleSubmit);
    $('#sch-cycle').addEventListener('change', onSchCycleChange);
    $('#sch-task').addEventListener('change', onSchTaskChange);
    $('#sch-cancel').addEventListener('click', cancelScheduleEdit);
    $('#schedules-tbody').addEventListener('click', (ev) => {
      const run = ev.target.closest('[data-sch-run]');
      if (run) { runScheduleNow(parseInt(run.dataset.schRun, 10)); return; }
      const toggle = ev.target.closest('[data-sch-toggle]');
      if (toggle) { toggleScheduleRow(parseInt(toggle.dataset.schToggle, 10), parseInt(toggle.dataset.next, 10)); return; }
      const edit = ev.target.closest('[data-sch-edit]');
      if (edit) { editSchedule(parseInt(edit.dataset.schEdit, 10)); return; }
      const del = ev.target.closest('[data-sch-del]');
      if (del) { deleteScheduleRow(parseInt(del.dataset.schDel, 10)); return; }
    });
    // 定时任务分页（事件委托）
    $('#schedules-page-btns').addEventListener('click', (ev) => {
      const btn = ev.target.closest('button[data-page]');
      if (!btn || btn.disabled) return;
      const p = parseInt(btn.dataset.page, 10);
      if (p >= 1) loadSchedules(p);
    });
    // 任务记录分页（事件委托）
    $('#tasks-page-btns').addEventListener('click', (ev) => {
      const btn = ev.target.closest('button[data-page]');
      if (!btn || btn.disabled) return;
      const p = parseInt(btn.dataset.page, 10);
      if (p >= 1) loadTasks(p);
    });

    // 通话记录筛选
    $('#calls-filter-apply').addEventListener('click', () => { callsPage = 1; loadCalls(1); });
    $('#calls-filter-reset').addEventListener('click', () => {
      $('#calls-filter-from').value = '';
      $('#calls-filter-to').value = '';
      $('#calls-filter-imei').value = '';
      callsPage = 1;
      loadCalls(1);
    });
    // 通话记录分页（事件委托）
    $('#calls-page-btns').addEventListener('click', (ev) => {
      const btn = ev.target.closest('button[data-calls-page]');
      if (!btn || btn.disabled) return;
      const p = parseInt(btn.dataset.callsPage, 10);
      if (p >= 1) loadCalls(p);
    });
    // 删除单条通话记录（事件委托）
    $('#calls-tbody').addEventListener('click', (ev) => {
      const btn = ev.target.closest('[data-call-del]');
      if (!btn) return;
      deleteCallRecord(parseInt(btn.dataset.callDel, 10));
    });
    // 通话记录清理
    $('#clear-calls-7d').addEventListener('click', async () => {
      const ok = await showConfirm('确定清理 7 天前的通话记录吗？');
      if (!ok) return;
      const data = await API.clearCalls({ days: 7 });
      toast(data.message || '清理成功');
      callsPage = 1;
      loadCalls(1);
    });
    $('#clear-calls-all').addEventListener('click', async () => {
      const ok = await showConfirm('确定删除全部通话记录吗？此操作不可恢复。');
      if (!ok) return;
      const data = await API.clearCalls({ days: 0 });
      toast(data.message || '删除成功');
      callsPage = 1;
      loadCalls(1);
    });

    // 短信记录筛选
    $('#sms-filter-apply').addEventListener('click', () => { smsPage = 1; loadSms(1); });
    $('#sms-filter-reset').addEventListener('click', () => {
      $('#sms-filter-from').value = '';
      $('#sms-filter-to').value = '';
      $('#sms-filter-imei').value = '';
      smsPage = 1;
      loadSms(1);
    });
    // 短信记录分页（事件委托）
    $('#sms-page-btns').addEventListener('click', (ev) => {
      const btn = ev.target.closest('button[data-sms-page]');
      if (!btn || btn.disabled) return;
      const p = parseInt(btn.dataset.smsPage, 10);
      if (p >= 1) loadSms(p);
    });
    // 删除单条短信记录（事件委托）
    $('#sms-tbody').addEventListener('click', (ev) => {
      const btn = ev.target.closest('[data-sms-del]');
      if (!btn) return;
      deleteSmsRecord(parseInt(btn.dataset.smsDel, 10));
    });
    // 短信记录清理
    $('#clear-sms-7d').addEventListener('click', async () => {
      const ok = await showConfirm('确定清理 7 天前的短信记录吗？');
      if (!ok) return;
      const data = await API.clearSms({ days: 7 });
      toast(data.message || '清理成功');
      smsPage = 1;
      loadSms(1);
    });
    $('#clear-sms-all').addEventListener('click', async () => {
      const ok = await showConfirm('确定删除全部短信记录吗？此操作不可恢复。');
      if (!ok) return;
      const data = await API.clearSms({ days: 0 });
      toast(data.message || '删除成功');
      smsPage = 1;
      loadSms(1);
    });

    // 日志中心筛选
    $('#log-filter-apply').addEventListener('click', () => { logPage = 1; loadLogs(1); });
    $('#log-filter-reset').addEventListener('click', () => {
      $('#log-filter-from').value = '';
      $('#log-filter-to').value = '';
      $('#log-filter-imei').value = '';
      $('#log-filter-type').value = '';
      $('#log-filter-keyword').value = '';
      logPage = 1;
      loadLogs(1);
    });
    // 日志中心分页（事件委托）
    $('#log-page-btns').addEventListener('click', (ev) => {
      const btn = ev.target.closest('button[data-log-page]');
      if (!btn || btn.disabled) return;
      const p = parseInt(btn.dataset.logPage, 10);
      if (p >= 1) loadLogs(p);
    });
    // 日志中心悬浮预览 + 复制
    bindLogTooltip();
    // 日志中心清理
    $('#clear-logs-7d').addEventListener('click', async () => {
      const ok = await showConfirm('确定清理 7 天前的设备日志吗？');
      if (!ok) return;
      const data = await API.clearLogs({ days: 7 });
      toast(data.message || '清理成功');
      logPage = 1;
      loadLogs(1);
    });
    $('#clear-logs-all').addEventListener('click', async () => {
      const ok = await showConfirm('确定删除全部设备日志吗？此操作不可恢复。');
      if (!ok) return;
      const data = await API.clearLogs({ days: 0 });
      toast(data.message || '删除成功');
      logPage = 1;
      loadLogs(1);
    });

    // 屏蔽配置：tab 切换 / 添加 / 列表操作 / 恢复默认
    $$('.block-tab-btn').forEach((b) =>
      b.addEventListener('click', () => switchBlockTab(b.dataset.blockTab)));
    $('#block-add-btn').addEventListener('click', addBlockRule);
    $('#block-value').addEventListener('keydown', (ev) => { if (ev.key === 'Enter') addBlockRule(); });
    $('#block-reset-builtin').addEventListener('click', resetBlockRules);
    $('#block-tbody').addEventListener('click', (ev) => {
      const tBtn = ev.target.closest('[data-block-toggle]');
      if (tBtn) { toggleBlockRule(parseInt(tBtn.dataset.blockToggle, 10)); return; }
      const dBtn = ev.target.closest('[data-block-del]');
      if (dBtn) deleteBlockRule(parseInt(dBtn.dataset.blockDel, 10));
    });
    $('#block-pagination').addEventListener('click', (ev) => {
      const pBtn = ev.target.closest('[data-block-page]');
      if (pBtn && !pBtn.disabled) loadBlockRules(parseInt(pBtn.dataset.blockPage, 10));
    });

    $('#confirm-cancel').addEventListener('click', () => closeConfirm(false));
    $('#confirm-cancel2').addEventListener('click', () => closeConfirm(false));
    $('#confirm-ok').addEventListener('click', () => closeConfirm(true));
    $('#confirm-overlay').addEventListener('click', () => closeConfirm(false));

    // 命令大全弹窗
    $('#task-library-link').addEventListener('click', showTaskLibrary);
    $('#task-custom-help').addEventListener('click', showTaskLibrary);
    $('#task-library-close').addEventListener('click', closeTaskLibrary);
    $('#task-library-ok').addEventListener('click', closeTaskLibrary);
    $('#task-library-overlay').addEventListener('click', closeTaskLibrary);
    $('#config-save').addEventListener('click', saveConfig);
    $('#config-reload').addEventListener('click', loadConfigForEdit);
    $('#task-led-action').addEventListener('change', onLedActionChange);
    // 命令大全内点击分组标题 -> 切换手风琴展开（关闭其他组）
    $('#task-library-body').addEventListener('click', (ev) => {
      const group = ev.target.closest('.task-lib-group');
      if (group) {
        const gi = parseInt(group.dataset.group, 10);
        libOpenGroup = (libOpenGroup === gi) ? -1 : gi; // 再点一次收起
        renderTaskLibrary();
        return;
      }
      const item = ev.target.closest('.task-lib-item');
      if (!item) return;
      closeTaskLibrary();
      showTaskHelp(item.dataset.task);
    });
    $('#task-help-close').addEventListener('click', closeTaskHelp);
    $('#task-help-ok').addEventListener('click', closeTaskHelp);
    $('#task-help-overlay').addEventListener('click', closeTaskHelp);
    document.addEventListener('keydown', (ev) => {
      if (ev.key === 'Escape') {
        if (!$('#confirm-modal').classList.contains('hidden')) closeConfirm(false);
        else if (!$('#task-help-modal').classList.contains('hidden')) closeTaskHelp();
        else if (!$('#task-library-modal').classList.contains('hidden')) closeTaskLibrary();
      }
    });
    $('#menu-btn').addEventListener('click', () => toggleSidebar(true));
    $('#sidebar-overlay').addEventListener('click', () => toggleSidebar(false));
    $('#appearance-btn').addEventListener('click', cycleAppearance);
    $('#top-refresh').addEventListener('click', () => switchPage(currentPage));

    $$('.nav-item').forEach((a) =>
      a.addEventListener('click', (e) => { e.preventDefault(); switchPage(a.dataset.nav); toggleSidebar(false); }));

    // 概览：设备选择 / 刷新 / 配置保存
    $('#overview-device').addEventListener('change', loadOverview);
    $('#overview-refresh').addEventListener('click', loadOverview);
    $('#ov-save-config').addEventListener('click', saveOverviewConfig);

    // 设备页：左列表选中 + 右详情操作 + 搜索/过滤
    $('#devList').addEventListener('click', (e) => {
      const row = e.target.closest('.dev-row');
      if (row) { currentDevice = row.dataset.dev; renderDevices(); }
    });
    $('#devDetail').addEventListener('click', (e) => {
      const goto = e.target.closest('[data-goto]');
      if (goto) {
        if (goto.dataset.goto === 'tasks' && currentDevice) {
          switchPage('tasks'); renderDeviceSelect(currentDevice);
          const isel = $('#task-imei'); if (isel) isel.value = currentDevice;
        } else switchPage(goto.dataset.goto);
        return;
      }
      const jump = e.target.closest('[data-task-jump]');
      if (jump) { jumpToTask(jump.dataset.taskJump); return; }
      const delBtn = e.target.closest('[data-del]');
      if (delBtn) { deleteDevice(delBtn.dataset.del); return; }
      const remarkBtn = e.target.closest('[data-remark]');
      if (remarkBtn) editRemark(remarkBtn.dataset.remark);
    });
    $('#devSearch').addEventListener('input', renderDevices);
    $('#devFilter').addEventListener('click', (e) => {
      const b = e.target.closest('[data-f]');
      if (!b) return;
      $$('#devFilter [data-f]').forEach((x) => x.classList.toggle('on', x === b));
      renderDevices();
    });
  }

  function init() {
    if (localStorage.getItem('panel_theme') === 'dark') document.body.dataset.theme = 'dark';
    bindEvents();
    onTaskTypeChange();
    if (API.token) {
      enterMain();
    } else {
      showLogin();
    }
  }

  init();
})();
