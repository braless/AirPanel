// 应用逻辑：登录、导航、设备列表、任务执行、任务记录、设置
(function () {
  'use strict';

  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));

  let currentPage = 'devices';
  let devices = [];

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
    el.textContent = msg;
    el.className = 'fixed top-5 left-1/2 -translate-x-1/2 z-50 rounded-lg px-4 py-2.5 text-sm text-white shadow-lg ' +
      (ok ? 'bg-slate-800' : 'bg-red-600');
    el.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.add('hidden'), 3000);
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

  function showLogin() {
    toggleSidebar(false);
    $('#main-view').classList.add('hidden');
    $('#login-view').classList.remove('hidden');
    $('#login-password').value = '';
  }

  function enterMain() {
    $('#login-view').classList.add('hidden');
    $('#main-view').classList.remove('hidden');
    const uname = localStorage.getItem('panel_username') || 'admin';
    $('#user-name').textContent = uname;
    $('#user-avatar').textContent = (uname.charAt(0) || 'U').toUpperCase();
    $('#m-user-name').textContent = uname;
    loadDevices();
    switchPage('devices');
  }

  // ---------------- 导航 ----------------

  // 移动端抽屉开关（内联样式避免依赖 Tailwind 未生成的工具类）
  function toggleSidebar(open) {
    const sb = $('#sidebar');
    sb.style.transform = open ? 'translateX(0)' : '';
    $('#sidebar-overlay').classList.toggle('hidden', !open);
  }

  function switchPage(name) {
    currentPage = name;
    $$('.page').forEach((s) => s.classList.toggle('hidden', s.id !== 'page-' + name));
    $$('.nav-item').forEach((a) => {
      const active = a.dataset.nav === name;
      a.classList.toggle('bg-slate-800', active);
      a.classList.toggle('text-white', active);
      a.classList.toggle('text-slate-300', !active);
    });
    if (name === 'devices') loadDevices();
    if (name === 'overview') { fillOverviewDevice(); loadOverview(); }
    if (name === 'tasks') renderDeviceSelect();
    if (name === 'schedules') { renderSchDeviceSelect(); renderSchTaskSelect(); onSchCycleChange(); onSchTaskChange(); loadSchedules(); }
    if (name === 'calls') { fillRecordImeiFilter('#calls-filter-imei'); loadCalls(); }
    if (name === 'sms') { fillRecordImeiFilter('#sms-filter-imei'); loadSms(); }
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
    $('#ov-current').textContent = pow.currentMa !== undefined ? pow.currentMa + ' mA' : '—';
    $('#ov-current-note').textContent = (pow.avgCurrentMa > 0) ? '已配置实测值覆盖' : '基于功耗模型估算';
    $('#ov-esthours').textContent = (pow.estHours > 0) ? pow.estHours.toFixed(1) + ' 小时' : '—';
    $('#ov-esthours-note').textContent = (bat.percent > 0) ? `按剩余 ${(bat.mah * bat.percent / 100).toFixed(0)} mAh 估算` : '电量未知，暂无法估算';
    $('#ov-mah').textContent = bat.mah ? bat.mah + ' mAh' : '—';

    // 设备状态
    $('#ov-status').textContent = dev.connected ? '在线' : '离线';
    $('#ov-status-note').textContent = dev.connected
      ? '最近活跃 ' + fmtTime(dev.lastSeen)
      : '最后在线 ' + fmtTime(dev.lastSeen);

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
      `<div><p class="text-xs text-slate-400">${esc(k)}</p><p class="mt-0.5 font-medium text-slate-700 break-all">${esc(v)}</p></div>`).join('');

    // 配置回填
    $('#ov-battery-mah').value = bat.mah || 1800;
    $('#ov-current-ma').value = pow.avgCurrentMa || 0;

    renderOverviewChart(data.history);
  }

  function renderOverviewChart(history) {
    const el = $('#overview-chart');
    if (!el) return;
    if (!history || history.length < 2) {
      el.innerHTML = '<p class="text-center text-sm text-slate-400 py-6">暂无足够的遥测数据，等待设备上报</p>';
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

    el.innerHTML = `<svg viewBox="0 0 ${W} ${H}" class="w-full h-auto" preserveAspectRatio="none">
      ${[0.25, 0.5, 0.75].map(t => `<line x1="${pad}" y1="${(pad + t * (H - 2 * pad)).toFixed(1)}" x2="${W - pad}" y2="${(pad + t * (H - 2 * pad)).toFixed(1)}" stroke="#f1f5f9" stroke-width="1"/>`).join('')}
      <path d="${poly(rssiArr, yr)}" fill="#3b82f6" fill-opacity="0.06"/>
      <path d="${line(rssiArr, yr)}" fill="none" stroke="#3b82f6" stroke-width="2"/>
      <path d="${line(voltArr, yv)}" fill="none" stroke="#22c55e" stroke-width="2"/>
      <path d="${line(tempArr, yt)}" fill="none" stroke="#f97316" stroke-width="2"/>
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
      $('#devices-tbody').innerHTML = `<tr><td colspan="7" class="px-4 py-10 text-center text-red-500">${esc(err.message)}</td></tr>`;
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = '刷新'; }
    }
  }

  function renderDevices() {
    const tbody = $('#devices-tbody');
    if (!devices.length) {
      tbody.innerHTML = '<tr><td colspan="7" class="px-4 py-10 text-center text-slate-400">暂无设备接入</td></tr>';
      return;
    }
    tbody.innerHTML = devices.map((d) => `
      <tr class="hover:bg-slate-50">
        <td class="px-4 py-3 font-mono text-slate-700">${esc(d.imei)}</td>
        <td class="px-4 py-3 text-slate-600">
          <div class="flex items-center gap-1.5 min-w-32">
            <span class="remark-name truncate max-w-28">${esc(d.name || '—')}</span>
            <button class="shrink-0 text-slate-400 hover:text-blue-600 transition-colors" data-remark="${esc(d.imei)}" title="设置备注">
              <svg xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/></svg>
            </button>
          </div>
        </td>
        <td class="px-4 py-3 text-slate-600">${esc(d.phone || '—')}</td>
        <td class="px-4 py-3">${d.connected ? '<span class="badge-online">● 在线</span>' : '<span class="badge-offline">○ 离线</span>'}</td>
        <td class="px-4 py-3 text-slate-500">${fmtTime(d.firstSeen)}</td>
        <td class="px-4 py-3 text-slate-500">${fmtTime(d.lastSeen)}</td>
        <td class="px-4 py-3 text-right">
          <button class="btn btn-ghost !px-3 !py-1.5 text-xs" data-run="${esc(d.imei)}">执行任务</button>
          <button class="btn btn-ghost !px-3 !py-1.5 text-xs text-red-600 hover:text-red-700" data-del="${esc(d.imei)}">删除</button>
        </td>
      </tr>`).join('');
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
      <div class="flex items-center gap-1">
        <input type="text" class="input !py-1 !px-2 text-xs min-w-32" maxlength="30" value="${esc(dev ? dev.name : '')}" placeholder="备注">
        <button class="shrink-0 text-emerald-600 hover:scale-110 transition" title="保存" data-remark-save="1">✓</button>
        <button class="shrink-0 text-slate-400 hover:text-red-500 transition" title="取消" data-remark-cancel="1">✕</button>
      </div>`;
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
      <div>
        <button type="button" class="task-lib-group w-full flex items-center justify-between gap-3 px-4 py-3 rounded-xl bg-slate-50 hover:bg-slate-100 transition-colors" data-group="${gi}">
          <span class="flex items-center gap-2 text-sm font-semibold text-slate-800">${g.icon} ${g.name}</span>
          <svg class="w-4 h-4 text-slate-400 shrink-0" style="transform: ${open ? 'rotate(90deg)' : 'none'}; transition: transform .2s" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/></svg>
        </button>
        ${open ? `<ul class="mt-2 rounded-xl border border-slate-100 divide-y divide-slate-100 overflow-hidden">
          ${g.tasks.map((t) => {
            const h = TASK_HELP[t];
            return h ? `<li>
              <a href="javascript:void(0)" class="task-lib-item flex items-center justify-between gap-3 px-4 py-3 hover:bg-blue-50/60 transition-colors" data-task="${t}">
                <span class="flex items-center gap-2.5 min-w-0">
                  <span class="font-medium text-sm text-slate-800">${h.title}</span>
                  <code class="font-mono text-xs text-blue-600 bg-blue-50 rounded px-1.5 py-0.5 shrink-0">${t}</code>
                </span>
                <svg class="w-4 h-4 text-slate-300 shrink-0" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/></svg>
              </a>
            </li>` : '';
          }).join('')}
        </ul>` : ''}
      </div>`;
    }).join('');
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
      html += '<div><p class="font-semibold text-slate-800 text-xs mb-1.5">请求参数</p><ul class="space-y-1 list-disc pl-5">'
        + h.params.map((p) => `<li><code class="font-mono text-xs bg-slate-100 rounded px-1.5 py-0.5">${p[0]}</code> — ${p[1]}</li>`).join('')
        + '</ul></div>';
    }
    html += `<div><p class="font-semibold text-slate-800 text-xs mb-1.5">返回结果</p><p>${h.result}</p></div>`;
    html += `<div class="rounded-lg bg-amber-50 border border-amber-100 px-3.5 py-2.5 text-xs text-amber-700">⚠️ ${h.note}</div>`;
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
      consoleLine(box, `▶ 已读取配置 → ${imei}`, 'text-sky-400');
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
      consoleLine(box, `▶ 保存配置 → ${imei}`, 'text-sky-400');
      consoleLine(box, pretty, 'text-emerald-200 whitespace-pre-wrap break-all');
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
    box.innerHTML = '<p class="text-slate-500">// 等待下发任务...</p>';
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
    consoleLine(box, `▶ 下发任务 → ${imei}（${TASK_LABELS[type] || type}）`, 'text-sky-400');
    consoleLine(box, '⏳ 等待设备回报（最长 30 秒）...', 'text-slate-400');
    try {
      const data = await API.executeTask(payload);
      const result = data.result;
      if (result && typeof result === 'object' && result.error) {
        throw new Error(result.error);
      }
      const pretty = typeof result === 'string' ? result : JSON.stringify(result, null, 2);
      consoleLine(box, '✔ 设备已回报：', 'text-emerald-400');
      consoleLine(box, pretty, 'text-emerald-200 whitespace-pre-wrap break-all');
      toast('任务执行成功');
    } catch (err) {
      consoleLine(box, `✘ 执行失败：${err.message}`, 'text-red-400');
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
        tbody.innerHTML = '<tr><td colspan="5" class="px-4 py-10 text-center text-slate-400">暂无任务记录</td></tr>';
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
        <tr class="hover:bg-slate-50 align-top">
          <td class="px-4 py-3 text-slate-500 whitespace-nowrap">${fmtTime(t.createdAt)}</td>
          <td class="px-4 py-3 text-slate-700">${esc(deviceLabel)}${isName ? `<span class="block text-xs font-mono text-slate-400 mt-0.5">${esc(t.imei)}</span>` : ''}</td>
          <td class="px-4 py-3 text-slate-600">${esc(t.task)}</td>
          <td class="px-4 py-3">${ok ? '<span class="badge-online">成功</span>' : '<span class="badge-offline">失败</span>'}</td>
          <td class="px-4 py-3 text-slate-500 max-w-xs"><pre class="text-xs font-mono whitespace-pre-wrap break-all">${esc(result)}</pre></td>
        </tr>`;
      }).join('');
      renderTaskPagination(data.total || 0, tasksPage);
    } catch (err) {
      $('#tasks-tbody').innerHTML = `<tr><td colspan="5" class="px-4 py-10 text-center text-red-500">${esc(err.message)}</td></tr>`;
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
    const btnCls = 'h-8 px-2 rounded-lg text-sm transition-colors';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `
      <button type="button" data-page="${page - 1}" class="${btnCls} text-slate-600" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="text-slate-300" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-page="${p}" class="${btnCls} ${p === page ? 'bg-blue-600 text-white' : 'text-slate-600'}" style="min-width:2rem">${p}</button>`
    ).join('');
    html += `
      <button type="button" data-page="${page + 1}" class="${btnCls} text-slate-600" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
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
        tbody.innerHTML = '<tr><td colspan="9" class="px-4 py-10 text-center text-slate-400">暂无通话记录</td></tr>';
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
        <tr class="hover:bg-slate-50 align-top">
          <td class="px-4 py-3 text-slate-500 whitespace-nowrap">${fmtTime(c.startedAt)}</td>
          <td class="px-4 py-3">${dirBadge}</td>
          <td class="px-4 py-3 text-slate-700 font-mono">${esc(c.number || '—')}</td>
          <td class="px-4 py-3 text-slate-600">${esc(status)}</td>
          <td class="px-4 py-3 text-slate-600 whitespace-nowrap">${dur}</td>
          <td class="px-4 py-3">${notifyBadge(c.notifyStatus)}</td>
          <td class="px-4 py-3">${c.spam ? `<span class="spam-badge">垃圾电话</span>${c.spamRule ? `<div class="text-xs text-red-500 mt-0.5 break-all">命中：${esc(c.spamRule)}</div>` : ''}` : '<span class="text-slate-300">—</span>'}</td>
          <td class="px-4 py-3 text-slate-500">${esc(deviceLabel)}${c.deviceName ? `<span class="block text-xs font-mono text-slate-400 mt-0.5">${esc(c.imei)}</span>` : ''}</td>
          <td class="px-4 py-3 text-right whitespace-nowrap">
            <button type="button" data-call-del="${c.id}" class="h-7 px-2.5 rounded-lg text-xs font-medium text-red-600 bg-white border border-slate-200 hover:bg-red-50 hover:border-red-300 transition-colors">删除</button>
          </td>
        </tr>`;
      }).join('');
      renderCallPagination(data.total || 0, callsPage);
    } catch (err) {
      $('#calls-tbody').innerHTML = `<tr><td colspan="9" class="px-4 py-10 text-center text-red-500">${esc(err.message)}</td></tr>`;
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
    const btnCls = 'h-8 px-2 rounded-lg text-sm transition-colors';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `<button type="button" data-calls-page="${page - 1}" class="${btnCls} text-slate-600" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="text-slate-300" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-calls-page="${p}" class="${btnCls} ${p === page ? 'bg-blue-600 text-white' : 'text-slate-600'}" style="min-width:2rem">${p}</button>`).join('');
    html += `<button type="button" data-calls-page="${page + 1}" class="${btnCls} text-slate-600" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
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
        tbody.innerHTML = '<tr><td colspan="8" class="px-4 py-10 text-center text-slate-400">暂无短信记录</td></tr>';
        renderSmsPagination(0, 1);
        return;
      }
      tbody.innerHTML = list.map((m) => {
        const dirBadge = m.direction === 'out'
          ? '<span class="badge-offline">发送</span>'
          : '<span class="badge-online">接收</span>';
        const deviceLabel = m.deviceName || m.imei;
        return `
        <tr class="hover:bg-slate-50 align-top">
          <td class="px-4 py-3 text-slate-500 whitespace-nowrap">${fmtTime(m.createdAt)}</td>
          <td class="px-4 py-3">${dirBadge}</td>
          <td class="px-4 py-3 text-slate-700 font-mono">${esc(m.number || '—')}</td>
          <td class="px-4 py-3 text-slate-600 max-w-md"><span class="break-all">${esc(m.content || '')}</span></td>
          <td class="px-4 py-3">${notifyBadge(m.notifyStatus)}</td>
          <td class="px-4 py-3">${m.spam ? `<span class="spam-badge">垃圾短信</span>${m.spamRule ? `<div class="text-xs text-red-500 mt-0.5 break-all">命中：${esc(m.spamRule)}</div>` : ''}` : '<span class="text-slate-300">—</span>'}</td>
          <td class="px-4 py-3 text-slate-500">${esc(deviceLabel)}${m.deviceName ? `<span class="block text-xs font-mono text-slate-400 mt-0.5">${esc(m.imei)}</span>` : ''}</td>
          <td class="px-4 py-3 text-right whitespace-nowrap">
            <button type="button" data-sms-del="${m.id}" class="h-7 px-2.5 rounded-lg text-xs font-medium text-red-600 bg-white border border-slate-200 hover:bg-red-50 hover:border-red-300 transition-colors">删除</button>
          </td>
        </tr>`;
      }).join('');
      renderSmsPagination(data.total || 0, smsPage);
    } catch (err) {
      $('#sms-tbody').innerHTML = `<tr><td colspan="8" class="px-4 py-10 text-center text-red-500">${esc(err.message)}</td></tr>`;
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
    const btnCls = 'h-8 px-2 rounded-lg text-sm transition-colors';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `<button type="button" data-sms-page="${page - 1}" class="${btnCls} text-slate-600" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="text-slate-300" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-sms-page="${p}" class="${btnCls} ${p === page ? 'bg-blue-600 text-white' : 'text-slate-600'}" style="min-width:2rem">${p}</button>`).join('');
    html += `<button type="button" data-sms-page="${page + 1}" class="${btnCls} text-slate-600" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
    btns.innerHTML = html;
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
      $('#block-tbody').innerHTML = `<tr><td colspan="5" class="px-4 py-10 text-center text-red-500">${esc(err.message)}</td></tr>`;
      renderBlockPagination(0, 1);
    }
  }

  // 渲染当前 tab 的规则
  function renderBlockRules() {
    const tbody = $('#block-tbody');
    const list = blockRulesPage;
    if (!list.length) {
      tbody.innerHTML = `<tr><td colspan="5" class="px-4 py-10 text-center text-slate-400">暂无${blockTab === 'keyword' ? '关键字' : '号码'}规则，可在上方添加</td></tr>`;
      return;
    }
    tbody.innerHTML = list.map((r) => {
      const srcLabel = r.source === 'builtin' ? '<span class="badge-offline">内置</span>' : '<span class="badge-online">自定义</span>';
      const modeLabel = r.ruleType === 'number'
        ? ({ prefix: '前缀', exact: '精确', contains: '包含' }[r.matchMode] || r.matchMode)
        : '包含';
      const valueLabel = r.ruleType === 'number'
        ? `<span class="font-mono">${esc(r.value)}</span> <span class="text-xs text-slate-400">（${modeLabel}）</span>`
        : `<span class="font-medium text-slate-700">${esc(r.value)}</span>`;
      const enabled = r.enabled === 1;
      return `
      <tr class="hover:bg-slate-50 align-top">
        <td class="px-4 py-3">${valueLabel}</td>
        <td class="px-4 py-3">${srcLabel}</td>
        <td class="px-4 py-3">${enabled ? '<span class="notify-badge notify-sent">生效中</span>' : '<span class="notify-badge notify-none">已停用</span>'}</td>
        <td class="px-4 py-3 text-slate-500">${esc(r.note || '—')}</td>
        <td class="px-4 py-3 text-right whitespace-nowrap">
          <button type="button" data-block-toggle="${r.id}" class="h-7 px-2.5 rounded-lg text-xs font-medium ${enabled ? 'text-slate-600 bg-white border border-slate-200 hover:bg-slate-50' : 'text-emerald-600 bg-emerald-50 border border-emerald-200 hover:bg-emerald-100'} transition-colors">${enabled ? '停用' : '启用'}</button>
          <button type="button" data-block-del="${r.id}" class="h-7 px-2.5 rounded-lg text-xs font-medium text-red-600 bg-white border border-slate-200 hover:bg-red-50 hover:border-red-300 transition-colors ml-1">删除</button>
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
    const btnCls = 'h-8 px-2 rounded-lg text-sm transition-colors';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `<button type="button" data-block-page="${page - 1}" class="${btnCls} text-slate-600" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="text-slate-300" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-block-page="${p}" class="${btnCls} ${p === page ? 'bg-blue-600 text-white' : 'text-slate-600'}" style="min-width:2rem">${p}</button>`).join('');
    html += `<button type="button" data-block-page="${page + 1}" class="${btnCls} text-slate-600" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
    btns.innerHTML = html;
  }

  // 切换关键字 / 号码 tab
  function switchBlockTab(tab) {
    blockTab = tab;
    $$('.block-tab-btn').forEach((b) => {
      const active = b.dataset.blockTab === tab;
      b.style.color = active ? '#2563eb' : '#64748b';
      b.style.borderBottom = active ? '2px solid #2563eb' : '2px solid transparent';
      b.style.fontWeight = active ? '600' : '400';
    });
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
      return `<select id="${id}" class="input !py-1.5 !px-3 text-sm" style="width:${w || '4.2rem'}">${opts}</select>`;
    };
    const selCls = 'input !py-1.5 !px-3 text-sm';
    if (type === 'weekly') {
      box.innerHTML = `<span class="text-slate-500">每</span>` +
        `<select id="sch-c-weekday" class="${selCls}" style="width:4rem">` + WEEKDAY_NAMES.map((w, i) => `<option value="${i}">${w}</option>`).join('') + `</select>` +
        `<span class="text-slate-500">的</span>` + numSel('sch-c-hour', 0, 23, 8, '4.2rem') + `<span class="text-slate-500">点</span>` + numSel('sch-c-minute', 0, 59, 0, '4.2rem') + `<span class="text-slate-500">分</span>`;
    } else if (type === 'monthly') {
      box.innerHTML = `<span class="text-slate-500">每月</span>` + numSel('sch-c-day', 1, 31, 1, '4.2rem') + `<span class="text-slate-500">日</span>` + numSel('sch-c-hour', 0, 23, 8, '4.2rem') + `<span class="text-slate-500">点</span>` + numSel('sch-c-minute', 0, 59, 0, '4.2rem') + `<span class="text-slate-500">分</span>`;
    } else if (type === 'daily') {
      box.innerHTML = numSel('sch-c-hour', 0, 23, 8, '4.2rem') + `<span class="text-slate-500">点</span>` + numSel('sch-c-minute', 0, 59, 0, '4.2rem') + `<span class="text-slate-500">分</span>`;
    } else if (type === 'hourly') {
      box.innerHTML = `<span class="text-slate-500">每小时的</span>` + numSel('sch-c-minute', 0, 59, 0, '4.2rem') + `<span class="text-slate-500">分</span>`;
    } else if (type === 'interval_min') {
      box.innerHTML = `<span class="text-slate-500">每</span>` + numSel('sch-c-n', 1, 59, 5, '4.2rem') + `<span class="text-slate-500">分钟执行一次</span>`;
    } else if (type === 'interval_hour') {
      box.innerHTML = `<span class="text-slate-500">每</span>` + numSel('sch-c-n', 1, 23, 2, '4.2rem') + `<span class="text-slate-500">小时执行一次</span>`;
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
        <div class="border-t border-slate-100 pt-4 grid gap-4 grid-cols-2">
          <div>
            <label class="label" for="sch-custom-cmd">命令名称</label>
            <input id="sch-custom-cmd" type="text" class="input font-mono text-xs" placeholder="如 ussd_query、get_status、set_gpio">
          </div>
          <div>
            <label class="label" for="sch-custom-params">命令参数 <span class="text-slate-400 font-normal">（可选 JSON 对象）</span></label>
            <textarea id="sch-custom-params" rows="2" class="input font-mono text-xs" placeholder='{"pin": 15, "level": 1}'></textarea>
          </div>
        </div>`;
      return;
    }
    const h = TASK_HELP[task];
    if (!h || !h.params.length) {
      box.innerHTML = '<p class="text-xs text-slate-400 border-t border-slate-100 pt-3">该任务无需参数</p>';
      return;
    }
    box.innerHTML = '<div class="border-t border-slate-100 pt-4 grid gap-4 grid-cols-2">' + h.params.map((p) => {
      const isLong = p[0] === 'configText' || p[0] === 'content';
      return `<div>
        <label class="label" for="sch-p-${esc(p[0])}">${esc(p[0])}</label>
        ${isLong
          ? `<textarea id="sch-p-${esc(p[0])}" rows="3" class="input font-mono text-xs"></textarea>`
          : `<input id="sch-p-${esc(p[0])}" type="text" class="input">`}
        <p class="text-xs text-slate-400 mt-1">${p[1]}</p>
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
      $('#schedules-tbody').innerHTML = `<tr><td colspan="7" class="px-4 py-10 text-center text-red-500">${esc(err.message)}</td></tr>`;
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
    const btnCls = 'h-8 px-2 rounded-lg text-sm transition-colors';
    const btnStyle = (dis) => `style="min-width:2rem${dis ? ';opacity:.4;cursor:not-allowed' : ''}"`;
    let html = `
      <button type="button" data-page="${page - 1}" class="${btnCls} text-slate-600" ${btnStyle(page <= 1)} ${page <= 1 ? 'disabled' : ''}>‹</button>`;
    html += list.map((p) => p === '…'
      ? '<span class="text-slate-300" style="width:1.5rem;text-align:center;line-height:2rem">…</span>'
      : `<button type="button" data-page="${p}" class="${btnCls} ${p === page ? 'bg-blue-600 text-white' : 'text-slate-600'}" style="min-width:2rem">${p}</button>`
    ).join('');
    html += `
      <button type="button" data-page="${page + 1}" class="${btnCls} text-slate-600" ${btnStyle(page >= totalPages)} ${page >= totalPages ? 'disabled' : ''}>›</button>`;
    btns.innerHTML = html;
  }

  function renderSchedules() {
    const tbody = $('#schedules-tbody');
    if (!schedules.length) {
      tbody.innerHTML = '<tr><td colspan="7" class="px-4 py-10 text-center text-slate-400">暂无定时任务</td></tr>';
      return;
    }
    tbody.innerHTML = schedules.map((s) => {
      const taskLabel = TASK_HELP[s.task] ? TASK_HELP[s.task].title : s.task;
      const deviceLabel = s.deviceName || s.imei;
      const name = s.name || ('任务 #' + s.id);
      return `
      <tr class="hover:bg-slate-50 align-top">
        <td class="px-4 py-3 text-slate-700">${esc(name)}</td>
        <td class="px-4 py-3 text-slate-600">${esc(deviceLabel)}${s.deviceName ? `<span class="block text-xs font-mono text-slate-400 mt-0.5">${esc(s.imei)}</span>` : ''}</td>
        <td class="px-4 py-3 text-slate-600"><span class="font-medium">${esc(taskLabel)}</span><span class="block text-xs font-mono text-slate-400 mt-0.5">${esc(s.task)}</span></td>
        <td class="px-4 py-3 text-slate-600 whitespace-nowrap">${esc(specDescribe(s.spec))}</td>
        <td class="px-4 py-3 text-slate-500 whitespace-nowrap">${fmtTime(s.lastExecuted)}</td>
        <td class="px-4 py-3">${s.enabled ? '<span class="badge-online">已启用</span>' : '<span class="badge-offline">已停用</span>'}</td>
        <td class="px-4 py-3 text-right whitespace-nowrap">
          <button class="btn btn-ghost !px-3 !py-1.5 text-xs" data-sch-run="${s.id}">执行</button>
          <button class="btn btn-ghost !px-3 !py-1.5 text-xs" data-sch-toggle="${s.id}" data-next="${s.enabled ? 0 : 1}">${s.enabled ? '停用' : '启用'}</button>
          <button class="btn btn-ghost !px-3 !py-1.5 text-xs" data-sch-edit="${s.id}">编辑</button>
          <button class="btn btn-ghost !px-3 !py-1.5 text-xs text-red-600 hover:text-red-700" data-sch-del="${s.id}">删除</button>
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
      msg.className = 'text-sm ' + (data.needRelogin ? 'text-amber-600' : 'text-emerald-600');
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
      label.className = 'inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm cursor-pointer transition-colors';
      label.style.borderColor = checked ? '#3b82f6' : '#e2e8f0';
      label.style.backgroundColor = checked ? '#eff6ff' : '#ffffff';
      label.style.color = checked ? '#1d4ed8' : '#475569';
      label.innerHTML = '<input type="checkbox" data-channel="' + esc(ch.name) + '" class="w-4 h-4" style="accent-color:#2563eb" ' + (checked ? 'checked' : '') + '> <span>' + esc(ch.label) + '</span>';
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
          '<label class="label">' + esc(f.label) + (f.required ? ' <span class="text-red-500">*</span>' : '') + '</label>' +
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
      label.className = cb.checked
        ? 'inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm cursor-pointer border-blue-500 bg-blue-50 text-blue-700 transition-colors'
        : 'inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm cursor-pointer border-slate-200 bg-white text-slate-600 hover:border-slate-300 transition-colors';
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

  // ---------------- 初始化 ----------------

  function bindEvents() {
    $('#login-form').addEventListener('submit', handleLogin);
    $('#logout-btn').addEventListener('click', handleLogout);
    $('#refresh-devices').addEventListener('click', loadDevices);
    $('#task-form').addEventListener('submit', handleTaskSubmit);
    $$('input[name="task-type"]').forEach((r) => r.addEventListener('change', onTaskTypeChange));
    $('#console-clear').addEventListener('click', resetConsole);
    $('#settings-form').addEventListener('submit', handleSettings);
    $('#notify-settings-form').addEventListener('submit', handleNotifySettings);
    $('#notify-test-btn').addEventListener('click', sendTestNotify);
    $('#notify-channels-list').addEventListener('change', onNotifyChannelChange);
    $('#led-settings-form').addEventListener('submit', handleLedSettings);
    // 设置页 Tab 切换
    $$('.set-tab-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        const tab = btn.dataset.setTab;
        $$('.set-tab-btn').forEach((b) => {
          const active = b.dataset.setTab === tab;
          b.style.color = active ? '#2563eb' : '#64748b';
          b.style.borderBottom = active ? '2px solid #2563eb' : '2px solid transparent';
          b.style.fontWeight = active ? '600' : 'normal';
        });
        $$('[id^="set-tab-"]').forEach((el) => {
          el.classList.toggle('hidden', !el.id.endsWith(tab));
        });
        if (tab === 'led') loadLedSettings();
      });
    });
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

    $$('.nav-item').forEach((a) =>
      a.addEventListener('click', (e) => { e.preventDefault(); switchPage(a.dataset.nav); toggleSidebar(false); }));

    // 概览：设备选择 / 刷新 / 配置保存
    $('#overview-device').addEventListener('change', loadOverview);
    $('#overview-refresh').addEventListener('click', loadOverview);
    $('#ov-save-config').addEventListener('click', saveOverviewConfig);

    // 设备表格里"执行任务"/"删除"按钮 / 备注编辑
    $('#devices-tbody').addEventListener('click', (e) => {
      const runBtn = e.target.closest('[data-run]');
      if (runBtn) {
        renderDeviceSelect(runBtn.dataset.run);
        switchPage('tasks');
        return;
      }
      const delBtn = e.target.closest('[data-del]');
      if (delBtn) {
        deleteDevice(delBtn.dataset.del);
        return;
      }
      const remarkBtn = e.target.closest('[data-remark]');
      if (remarkBtn) startEditRemark(remarkBtn.dataset.remark);
    });
  }

  function init() {
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
