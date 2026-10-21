/* 基本设置：账号安全 / 通知推送 / 灯光指示 / 省电模式 / 通话录音 / 存储配置 / 界面设置 */

import { api } from '../api.js';
import { state, loadSettings } from '../store.js';
import { $, $$, esc, toast, withBusy, confirmDialog } from '../ui.js';
import { icon, paintIcons } from '../icons.js';

export const meta = { crumb: '系统', name: '基本设置' };

const UI_KEY = 'airpanel.v2.ui';

const LED_COLORS = [
  ['off', '关闭', '#8e8e93'], ['red', '红', '#FF3B30'], ['green', '绿', '#34C759'],
  ['blue', '蓝', '#0A84FF'], ['yellow', '黄', '#FFD60A'], ['purple', '紫', '#AF52DE'],
  ['cyan', '青', '#5AC8FA'], ['white', '白', '#ffffff']
];

const ACCENTS = ['#0A84FF', '#34C759', '#AF52DE', '#FF9F0A', '#FF2D55', '#5856D6'];

/* 设备端 set_led 支持的动作（util_mqtt.lua） */
const LED_ACTIONS = [
  ['on', '开灯'], ['off', '关灯'], ['toggle', '切换开关'],
  ['color', '指定颜色'], ['set_mode', '切换灯效'],
  ['next', '下一个灯效'], ['prev', '上一个灯效'], ['status', '查询当前状态']
];

const SECTIONS = [
  { k: 'account', label: '账号与安全', ic: 'key' },
  { k: 'notify', label: '通知推送', ic: 'bell' },
  { k: 'led', label: '灯光指示', ic: 'lightbulb' },
  { k: 'power', label: '省电模式', ic: 'battery' },
  { k: 'record', label: '通话录音', ic: 'mic' },
  { k: 'storage', label: '存储配置', ic: 'server' },
  { k: 'ui', label: '界面设置', ic: 'palette' }
];

let tab = 'account';
let s = null;
let channels = [];
let draftUI = null;

/* 品牌标识（标题 / Logo URL / 头像 URL），随「保存设置」一起提交到服务端 */
const DEFAULT_TITLE = 'AirPanel';
let brandLogo = '';
let brandAvatar = '';

/* 灯光控制（随「保存设置」一起下发） */
const ledCtl = { imei: '', action: 'on', color: 'blue', mode: '1' };
let ledDirty = false;
let ledMsg = '尚未下发；选择动作后点右上角「保存设置」生效';

export async function render(root, opts) {
  if (opts && opts.section && SECTIONS.some((x) => x.k === opts.section)) tab = opts.section;
  root.innerHTML = '<div class="skeleton" style="height:360px"></div>';
  try {
    s = JSON.parse(JSON.stringify(await loadSettings(true)));
    channels = await api.notifyChannels() || [];
  } catch (err) {
    root.innerHTML = `<div class="card"><div class="empty">设置加载失败：${esc(err.message)}</div></div>`;
    return;
  }
  if (!s.notifyConfig) s.notifyConfig = {};
  if (!s.notifyChannels) s.notifyChannels = [];
  if (!s.smsLed) s.smsLed = { enabled: true, color: 'blue', blink: true, duration: 5000 };
  if (!s.callLed) s.callLed = { enabled: true, color: 'green', blink: true, duration: 5000 };
  if (!s.webdav) s.webdav = { url: '', username: '', password: '', dir: '通话录音' };
  draftUI = JSON.parse(localStorage.getItem(UI_KEY) || '{}');
  if (!s.brand) s.brand = { title: '', logo: '', avatar: '' };
  brandLogo = s.brand.logo || '';
  brandAvatar = s.brand.avatar || '';
  if (!ledCtl.imei) ledCtl.imei = state.imei || '';

  root.innerHTML = shell();
  paintIcons(root);
  bind(root);
  renderAccount();
  renderNotify();
  renderLED();
  renderPower();
  renderRecord();
  renderStorage();
  renderUI();
  showSection(tab);
}

function shell() {
  return `
  <div class="hero">
    <div><h1>基本设置</h1><p>账号、通知渠道、设备灯效与存储 · 修改后即时生效</p></div>
    <div class="hero-actions">
      <button class="btn primary" id="setSave">${icon('check')}保存设置</button>
    </div>
  </div>
  <div class="settings-layout">
    <div class="card set-nav" id="setNav">
      ${SECTIONS.map((x) => `<button class="set-item${x.k === tab ? ' on' : ''}" data-s="${x.k}">${icon(x.ic)}${x.label}</button>`).join('')}
    </div>
    <div id="setPanels">
      <div class="set-panel" data-p="account"></div>
      <div class="set-panel" data-p="notify"></div>
      <div class="set-panel" data-p="led"></div>
      <div class="set-panel" data-p="power"></div>
      <div class="set-panel" data-p="record"></div>
      <div class="set-panel" data-p="storage"></div>
      <div class="set-panel" data-p="ui"></div>
    </div>
  </div>`;
}

function bind(root) {
  $$('#setNav .set-item', root).forEach((b) => b.addEventListener('click', () => showSection(b.dataset.s)));
  $('#setSave', root).addEventListener('click', (e) => saveAll(e.currentTarget));
}

function showSection(k) {
  tab = k;
  $$('#setNav .set-item').forEach((b) => b.classList.toggle('on', b.dataset.s === k));
  $$('#setPanels .set-panel').forEach((p) => p.classList.toggle('on', p.dataset.p === k));
}

function panel(key) {
  return $(`#setPanels .set-panel[data-p="${key}"]`);
}

function card(title, sub, body, extra) {
  return `<div class="card" style="margin-bottom:12px">
    <div class="card-head">
      <div><div class="card-title">${esc(title)}</div><div class="card-sub">${esc(sub)}</div></div>
      ${extra || ''}
    </div>
    ${body}
  </div>`;
}

/* ---------------- 账号与安全 ---------------- */
function renderAccount() {
  panel('account').innerHTML = card(
    '账号与安全', '修改后当前登录会失效，需要用新账号重新登录',
    `<div class="form-grid">
      <div class="field full"><label class="label">当前用户名</label>
        <input class="input" id="acUser" value="${esc(s.username || 'admin')}" autocomplete="username"></div>
      <div class="field full"><label class="label">原密码（必填）</label>
        <input class="input" id="acOld" type="password" autocomplete="current-password" placeholder="用于验证身份"></div>
      <div class="field"><label class="label">新密码（留空不修改）</label>
        <input class="input" id="acNew" type="password" autocomplete="new-password" placeholder="至少 6 位"></div>
      <div class="field"><label class="label">确认新密码</label>
        <input class="input" id="acNew2" type="password" autocomplete="new-password" placeholder="再次输入"></div>
      <div class="full">
        <button class="btn primary" id="acSave">${icon('lock')}保存账号信息</button>
        <span style="font-size:9.5px;color:var(--ink3);margin-left:8px">修改成功后所有已登录设备需重新登录</span>
      </div>
    </div>`
  );
  paintIcons(panel('account'));

  $('#acSave').addEventListener('click', async (e) => {
    const oldPassword = $('#acOld').value;
    const newUsername = $('#acUser').value.trim();
    const newPassword = $('#acNew').value;
    const new2 = $('#acNew2').value;
    if (!oldPassword) { toast('请输入原密码', true); return; }
    if (newPassword && newPassword !== new2) { toast('两次输入的新密码不一致', true); return; }
    if (newPassword && newPassword.length < 6) { toast('新密码至少 6 位', true); return; }

    await withBusy(e.currentTarget, async () => {
      try {
        const res = await api.changeUserInfo(oldPassword, newUsername, newPassword);
        if (!res || res.success === false) { toast((res && res.message) || '修改失败', true); return; }
        toast(res.message || '已保存');
        if (res.needRelogin) {
          const ok = await confirmDialog('需要重新登录', '账号信息已更新，请使用新账号密码重新登录。', { okText: '去登录' });
          if (ok) { localStorage.removeItem('airpanel.v2.token'); location.reload(); }
        }
      } catch (err) { toast(err.message, true); }
    });
  });
}

/* ---------------- 通知推送 ---------------- */
function renderNotify() {
  panel('notify').innerHTML =
    card('通知推送', '设备离线、来电、短信等事件推送到所选渠道',
      `<div class="switch-row">
        <div class="grow"><div class="t">启用通知推送</div><div class="s">关闭后所有渠道都不再发送消息</div></div>
        <label class="switch"><input type="checkbox" id="ntEnable"${s.notifyEnabled ? ' checked' : ''}><i></i></label>
      </div>
      <div class="label" style="margin-top:14px">通知渠道（可多选）</div>
      <div class="channel-grid" id="ntChannels"></div>
      <div id="ntForms"></div>`,
      `<button class="btn sm" id="ntTest">${icon('bell')}发送测试</button>`
    );
  paintIcons(panel('notify'));
  renderChannelGrid();
  renderChannelForms();

  $('#ntTest').addEventListener('click', async (e) => {
    if (!s.notifyChannels.length) { toast('请先选择至少一个渠道', true); return; }
    collectNotify();
    await withBusy(e.currentTarget, async () => {
      try {
        const res = await api.testNotify(s.notifyChannels, s.notifyConfig);
        toast((res && res.message) || '测试通知已发送', !(res && res.success));
      } catch (err) { toast(err.message, true); }
    });
  });
}

function renderChannelGrid() {
  const box = $('#ntChannels');
  if (!box) return;
  box.innerHTML = channels.map((c) => {
    const on = s.notifyChannels.includes(c.name);
    return `<button class="channel ${on ? 'on' : ''}" data-ch="${esc(c.name)}">
      <span class="ck">${icon('check')}</span>${esc(c.label)}</button>`;
  }).join('');
  paintIcons(box);
  $$('.channel', box).forEach((b) => b.addEventListener('click', () => {
    const name = b.dataset.ch;
    if (s.notifyChannels.includes(name)) s.notifyChannels = s.notifyChannels.filter((x) => x !== name);
    else s.notifyChannels.push(name);
    renderChannelGrid();
    renderChannelForms();
  }));
}

function renderChannelForms() {
  const box = $('#ntForms');
  if (!box) return;
  const selected = channels.filter((c) => s.notifyChannels.includes(c.name));
  if (!selected.length) {
    box.innerHTML = `<div style="margin-top:12px;font-size:10.5px;color:var(--ink3);line-height:1.6">尚未选择渠道。选择后会出现对应的配置表单。</div>`;
    return;
  }
  box.innerHTML = selected.map((c) => {
    const conf = s.notifyConfig[c.name] || {};
    return `<div class="channel-form">
      <div style="display:flex;align-items:center;gap:7px;margin-bottom:10px">
        ${icon('bell')}<span style="font-size:11.5px;font-weight:650">${esc(c.label)}</span>
        <span class="badge" style="margin-left:auto">${esc(c.name)}</span>
      </div>
      <div class="form-grid">
        ${c.fields.map((f) => `<div class="field${f.type === 'textarea' ? ' full' : ''}">
          <label class="label">${esc(f.label)}${f.required ? ' *' : ''}</label>
          <input class="input" data-ch="${esc(c.name)}" data-k="${esc(f.key)}"
            type="${f.type === 'password' ? 'password' : 'text'}"
            value="${esc(conf[f.key] || '')}" placeholder="${esc(f.placeholder || '')}">
        </div>`).join('')}
      </div>
    </div>`;
  }).join('');
  paintIcons(box);
  $$('input[data-ch]', box).forEach((el) => el.addEventListener('input', () => {
    const ch = el.dataset.ch;
    s.notifyConfig[ch] = s.notifyConfig[ch] || {};
    s.notifyConfig[ch][el.dataset.k] = el.value;
  }));
}

function collectNotify() {
  s.notifyEnabled = $('#ntEnable').checked;
  $$('#ntForms input[data-ch]').forEach((el) => {
    const ch = el.dataset.ch;
    s.notifyConfig[ch] = s.notifyConfig[ch] || {};
    s.notifyConfig[ch][el.dataset.k] = el.value;
  });
}

/* ---------------- 灯光指示 ---------------- */
function ledBlock(key, title, sub) {
  const v = s[key] || {};
  return `<div class="channel-form" style="margin-top:0">
    <div style="display:flex;align-items:center;gap:8px;margin-bottom:10px">
      <div class="grow"><div class="t" style="font-size:11.5px;font-weight:650">${esc(title)}</div>
        <div class="s" style="font-size:9.5px;color:var(--ink3);margin-top:2px">${esc(sub)}</div></div>
      <label class="switch"><input type="checkbox" data-led="${key}" data-f="enabled"${v.enabled ? ' checked' : ''}><i></i></label>
    </div>
    <div class="label">颜色</div>
    <div class="color-row" data-led-colors="${key}">
      ${LED_COLORS.map(([c, label, hex]) => `<button class="swatch ${v.color === c ? 'on' : ''}" data-color="${c}"
        title="${label}" style="background:${hex}"></button>`).join('')}
    </div>
    <div class="form-grid" style="margin-top:12px">
      <div class="field"><label class="label">持续时长 (ms)</label>
        <input class="input" type="number" min="500" step="500" data-led="${key}" data-f="duration" value="${v.duration || 5000}"></div>
      <div class="field"><label class="label">闪烁</label>
        <label class="switch" style="margin-top:6px"><input type="checkbox" data-led="${key}" data-f="blink"${v.blink ? ' checked' : ''}><i></i></label></div>
    </div>
  </div>`;
}

function renderLED() {
  panel('led').innerHTML =
    card('灯光控制', '远程控制设备 RGB 氛围灯 · 与右上角「保存设置」一起下发',
      `<div class="form-grid">
        <div class="field"><label class="label">目标设备</label>
          <div class="select-wrap"><select class="select" id="ledDevice">${deviceOptions(ledCtl.imei || state.imei)}</select></div></div>
        <div class="field"><label class="label">动作</label>
          <div class="select-wrap"><select class="select" id="ledAction">
            ${LED_ACTIONS.map(([v, l]) => `<option value="${v}"${ledCtl.action === v ? ' selected' : ''}>${l}</option>`).join('')}
          </select></div></div>
      </div>

      <div id="ledColorBox" style="margin-top:12px">
        <div class="label">颜色</div>
        <div class="color-row" id="ledColors">
          ${LED_COLORS.map(([c, label, hex]) => `<button class="swatch ${ledCtl.color === c ? 'on' : ''}" data-color="${c}"
            title="${label}" style="background:${hex}"></button>`).join('')}
        </div>
      </div>

      <div id="ledModeBox" style="margin-top:12px">
        <div class="label">灯效</div>
        <div class="seg" id="ledModes">
          ${[1, 2, 3, 4, 5, 6].map((n) => `<button data-mode="${n}" class="${ledCtl.mode === String(n) ? 'on' : ''}">灯效 ${n}</button>`).join('')}
        </div>
      </div>

      <div style="display:flex;gap:7px;margin-top:12px;font-size:9.5px;color:var(--ink3);line-height:1.6">
        ${icon('info')}<span>修改后点右上角「保存设置」下发；设备离线时只保存配置，指令不会送达。</span>
      </div>
      <div id="ledMsg" style="font-size:10px;color:var(--ink3);margin-top:8px">${esc(ledMsg)}</div>`)
    + card('事件灯效', '收到短信 / 来电时设备 RGB 灯的反馈效果',
      `${ledBlock('smsLed', '来短信', '收到短信时点亮指定颜色')}
       ${ledBlock('callLed', '来电话', '来电振铃时点亮指定颜色')}
       <div style="display:flex;gap:7px;margin-top:10px;font-size:9.5px;color:var(--ink3);line-height:1.6">
         ${icon('info')}<span>事件灯效由服务端通过 set_led feedback 下发，触发后到期自动恢复原有灯效。</span>
       </div>`);
  paintIcons(panel('led'));

  // 事件灯效
  $$('[data-led-colors]').forEach((box) => {
    const key = box.dataset.ledColors;
    $$('.swatch', box).forEach((b) => b.addEventListener('click', () => {
      s[key].color = b.dataset.color;
      $$('.swatch', box).forEach((x) => x.classList.toggle('on', x === b));
    }));
  });
  $$('[data-led]').forEach((el) => el.addEventListener('change', () => {
    const key = el.dataset.led;
    const f = el.dataset.f;
    s[key][f] = el.type === 'checkbox' ? el.checked : Number(el.value) || 5000;
  }));

  // 灯光控制
  const syncCtl = () => {
    const colorBox = $('#ledColorBox');
    const modeBox = $('#ledModeBox');
    if (colorBox) colorBox.style.display = ledCtl.action === 'color' ? '' : 'none';
    if (modeBox) modeBox.style.display = ledCtl.action === 'set_mode' ? '' : 'none';
  };
  const markDirty = () => { ledDirty = true; ledMsg = '有未下发的改动，点右上角「保存设置」生效'; };

  $('#ledDevice').addEventListener('change', (e) => { ledCtl.imei = e.target.value; markDirty(); renderLedMsg(); });
  $('#ledAction').addEventListener('change', (e) => {
    ledCtl.action = e.target.value;
    markDirty();
    syncCtl();
    renderLedMsg();
  });
  $$('#ledColors .swatch').forEach((b) => b.addEventListener('click', () => {
    ledCtl.color = b.dataset.color;
    $$('#ledColors .swatch').forEach((x) => x.classList.toggle('on', x === b));
    markDirty();
    renderLedMsg();
  }));
  $$('#ledModes button').forEach((b) => b.addEventListener('click', () => {
    ledCtl.mode = b.dataset.mode;
    $$('#ledModes button').forEach((x) => x.classList.toggle('on', x === b));
    markDirty();
    renderLedMsg();
  }));
  syncCtl();
}

function renderLedMsg() {
  const el = $('#ledMsg');
  if (!el) return;
  el.textContent = ledMsg;
  el.style.color = ledDirty ? 'var(--accent)' : 'var(--ink3)';
}

/* ---------------- 省电模式 ---------------- */
function deviceOptions(selected) {
  if (!state.devices.length) return '<option value="">暂无设备</option>';
  return state.devices.map((d) =>
    `<option value="${esc(d.imei)}"${d.imei === selected ? ' selected' : ''}>${esc(d.name || d.imei)}${d.connected ? '' : '（离线）'}</option>`
  ).join('');
}

function renderPower() {
  panel('power').innerHTML =
    card('省电模式', '夜间拉长心跳间隔以降低功耗，配置写入设备 nvm_para.lua',
      `<div class="field" style="margin-bottom:12px"><label class="label">目标设备</label>
        <div class="select-wrap"><select class="select" id="pwDevice">${deviceOptions(state.imei)}</select></div></div>
      <div class="form-grid">
        <div class="field"><label class="label">开始时间</label>
          <div class="select-wrap"><select class="select" id="pwStart">${hours(1)}</select></div></div>
        <div class="field"><label class="label">结束时间</label>
          <div class="select-wrap"><select class="select" id="pwEnd">${hours(8)}</select></div></div>
        <div class="field"><label class="label">省电心跳间隔 (ms)</label>
          <input class="input" id="pwHeartbeat" type="number" min="60000" step="60000" value="600000"></div>
        <div class="field"><label class="label">省电期遥测间隔 (ms，0=关闭)</label>
          <input class="input" id="pwTelemetry" type="number" min="0" step="60000" value="0"></div>
        <div class="full">
          <div class="switch-row">
            <div class="grow"><div class="t">深度省电</div><div class="s">关闭射频的常驻连接，仅在心跳窗口唤醒（更省电，但实时性下降）</div></div>
            <label class="switch"><input type="checkbox" id="pwDeep"><i></i></label>
          </div>
        </div>
      </div>
      <div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:14px">
        <button class="btn" id="pwRead">${icon('refresh')}读取设备配置</button>
        <button class="btn primary" id="pwSave">${icon('check')}保存并下发</button>
        <button class="btn" id="pwEnter">${icon('battery')}立即进入</button>
        <button class="btn ghost" id="pwExit">立即退出</button>
      </div>
      <div style="font-size:9.5px;color:var(--ink3);margin-top:9px" id="pwMsg"></div>`,
      `<span class="badge" id="pwState">未读取</span>`
    );
  paintIcons(panel('power'));

  $('#pwRead').addEventListener('click', (e) => withBusy(e.currentTarget, () => readDeviceConfig('power')));
  $('#pwSave').addEventListener('click', (e) => withBusy(e.currentTarget, () => savePower(true)));
  $('#pwEnter').addEventListener('click', (e) => withBusy(e.currentTarget, () => enterPower()));
  $('#pwExit').addEventListener('click', (e) => withBusy(e.currentTarget, () => exitPower()));
}

function hours(sel) {
  return Array.from({ length: 24 }, (_, h) => `<option value="${h}"${h === sel ? ' selected' : ''}>${h} 点</option>`).join('');
}

/* ---------------- 通话录音 ---------------- */
function renderRecord() {
  panel('record').innerHTML =
    card('通话录音', '设备侧通话自动录音并上传到 WebDAV',
      `<div class="field" style="margin-bottom:12px"><label class="label">目标设备</label>
        <div class="select-wrap"><select class="select" id="rcDevice">${deviceOptions(state.imei)}</select></div></div>
      <div class="switch-row" style="margin-bottom:8px">
        <div class="grow"><div class="t">启用通话录音</div><div class="s">通话接通后自动录制并上传</div></div>
        <label class="switch"><input type="checkbox" id="rcEnable" checked><i></i></label>
      </div>
      <div class="switch-row">
        <div class="grow"><div class="t">录音前语音提示</div><div class="s">播放「本次通话将被录音」提示音</div></div>
        <label class="switch"><input type="checkbox" id="rcTts" checked><i></i></label>
      </div>
      <div style="display:flex;gap:6px;margin-top:14px">
        <button class="btn" id="rcRead">${icon('refresh')}读取设备配置</button>
        <button class="btn primary" id="rcSave">${icon('check')}保存并下发</button>
      </div>
      <div style="font-size:9.5px;color:var(--ink3);margin-top:9px" id="rcMsg"></div>`);
  paintIcons(panel('record'));

  $('#rcRead').addEventListener('click', (e) => withBusy(e.currentTarget, () => readDeviceConfig('record')));
  $('#rcSave').addEventListener('click', (e) => withBusy(e.currentTarget, () => saveRecord()));
}

/* ---------------- 存储配置 ---------------- */
function renderStorage() {
  const w = s.webdav;
  panel('storage').innerHTML =
    card('存储配置', '通话录音上传与浏览使用 WebDAV',
      `<div class="form-grid">
        <div class="field full"><label class="label">WebDAV 地址</label>
          <input class="input" id="wdUrl" value="${esc(w.url || '')}" placeholder="https://web.example.com"></div>
        <div class="field"><label class="label">账号</label>
          <input class="input" id="wdUser" value="${esc(w.username || '')}" autocomplete="off"></div>
        <div class="field"><label class="label">密码 / 应用密码</label>
          <input class="input" id="wdPass" type="password" value="${esc(w.password || '')}" autocomplete="new-password"></div>
        <div class="field full"><label class="label">录音目录</label>
          <input class="input" id="wdDir" value="${esc(w.dir || '通话录音')}" placeholder="通话录音"></div>
      </div>
      <div style="display:flex;gap:7px;margin-top:10px;font-size:9.5px;color:var(--ink3);line-height:1.6">
        ${icon('info')}<span>设备会把录音文件上传到该目录；面板通过 WebDAV 读取列表、播放与下载。</span>
      </div>`,
      `<button class="btn sm" id="wdTest">${icon('external')}打开目录</button>`
    );
  paintIcons(panel('storage'));

  $('#wdUrl').addEventListener('input', () => { s.webdav.url = $('#wdUrl').value.trim(); });
  $('#wdUser').addEventListener('input', () => { s.webdav.username = $('#wdUser').value.trim(); });
  $('#wdPass').addEventListener('input', () => { s.webdav.password = $('#wdPass').value; });
  $('#wdDir').addEventListener('input', () => { s.webdav.dir = $('#wdDir').value.trim(); });
  $('#wdTest').addEventListener('click', () => {
    if (!s.webdav.url) { toast('请先填写 WebDAV 地址', true); return; }
    window.open(s.webdav.url.replace(/\/$/, '') + '/' + encodeURIComponent(s.webdav.dir || ''), '_blank', 'noopener');
  });
}

/* ---------------- 界面设置 ---------------- */
function renderUI() {
  const theme = draftUI.theme || 'light';
  const glass = draftUI.glass != null ? draftUI.glass : 58;
  const density = draftUI.density || 'standard';
  const accent = draftUI.accent || '#0A84FF';
  const title = (s.brand && s.brand.title) || '';

  panel('ui').innerHTML =
    card('品牌标识', '站点标题、Logo 与管理员头像 · 保存后同步到所有设备',
      `<div class="brand-previews">
        <div class="brand-preview">
          <div class="brand-logo" id="brandLogoBox"></div>
          <span>Logo</span>
        </div>
        <div class="brand-preview">
          <div class="brand-avatar" id="brandAvatarBox"></div>
          <span>头像</span>
        </div>
      </div>

      <div class="field" style="margin-top:14px">
        <label class="label">站点标题</label>
        <input class="input" id="brandTitle" maxlength="24" value="${esc(title)}" placeholder="${DEFAULT_TITLE}">
      </div>

      <div class="field" style="margin-top:12px">
        <label class="label">Logo 图片 URL</label>
        <input class="input" id="brandLogoUrl" value="${esc(brandLogo)}" placeholder="https://example.com/logo.png" spellcheck="false">
      </div>
      <div class="brand-hint">侧栏左上角、登录页 Logo 与浏览器标签页图标共用这一个地址；留空则使用内置图标。</div>

      <div class="field" style="margin-top:14px">
        <label class="label">管理员头像 URL</label>
        <input class="input" id="brandAvatarUrl" value="${esc(brandAvatar)}" placeholder="https://example.com/avatar.png" spellcheck="false">
      </div>
      <div class="brand-hint">右上角与左下角头像共用这一个地址；留空则显示用户名首字母。</div>

      <div style="display:flex;gap:6px;margin-top:14px;flex-wrap:wrap">
        <button class="btn sm ghost" id="brandClear">${icon('refresh')}恢复默认</button>
      </div>
      <div style="display:flex;gap:7px;margin-top:10px;font-size:9.5px;color:var(--ink3);line-height:1.6">
        ${icon('info')}<span>建议使用正方形图片；支持 http(s) 链接、站内绝对路径（如 /icons/logo.png）与 data URL。</span>
      </div>`)
    + card('界面设置', '仅影响当前浏览器，不会同步到其他设备',
      `<div class="label">主题</div>
       <div class="seg" id="uiTheme">
         <button data-v="light" class="${theme === 'light' ? 'on' : ''}">浅色</button>
         <button data-v="dark" class="${theme === 'dark' ? 'on' : ''}">深色</button>
       </div>

       <div class="pop-label" style="margin-top:16px">玻璃通透度 <span id="uiGlassOut">${glass}%</span></div>
       <input type="range" id="uiGlass" min="0" max="100" value="${glass}">

       <div class="label" style="margin-top:16px">信息密度</div>
       <div class="seg" id="uiDensity">
         <button data-v="cozy" class="${density === 'cozy' ? 'on' : ''}">宽松</button>
         <button data-v="standard" class="${density === 'standard' ? 'on' : ''}">标准</button>
         <button data-v="compact" class="${density === 'compact' ? 'on' : ''}">紧凑</button>
       </div>

       <div class="label" style="margin-top:16px">强调色</div>
       <div class="color-row" id="uiAccent">
         ${ACCENTS.map((c) => `<button class="swatch ${c.toLowerCase() === accent.toLowerCase() ? 'on' : ''}" data-v="${c}" style="background:${c}"></button>`).join('')}
       </div>

       <div style="display:flex;gap:7px;margin-top:16px;font-size:9.5px;color:var(--ink3);line-height:1.6">
         ${icon('info')}<span>外观修改会立即生效，并保存在当前浏览器的本地存储中。</span>
       </div>`);
  paintIcons(panel('ui'));

  bindBrand();

  const push = (patch) => {
    Object.assign(draftUI, patch);
    localStorage.setItem(UI_KEY, JSON.stringify(draftUI));
    window.dispatchEvent(new CustomEvent('app:ui', { detail: patch }));
  };

  $$('#uiTheme button').forEach((b) => b.addEventListener('click', () => {
    $$('#uiTheme button').forEach((x) => x.classList.toggle('on', x === b));
    push({ theme: b.dataset.v });
  }));
  $$('#uiDensity button').forEach((b) => b.addEventListener('click', () => {
    $$('#uiDensity button').forEach((x) => x.classList.toggle('on', x === b));
    push({ density: b.dataset.v });
  }));
  $('#uiGlass').addEventListener('input', (e) => {
    $('#uiGlassOut').textContent = e.target.value + '%';
    push({ glass: Number(e.target.value) });
  });
  $$('#uiAccent .swatch').forEach((b) => b.addEventListener('click', () => {
    $$('#uiAccent .swatch').forEach((x) => x.classList.toggle('on', x === b));
    push({ accent: b.dataset.v });
  }));
}

/* ---------------- 品牌：标题 / Logo / 头像 ---------------- */
/** 去掉会破坏 CSS url("…") 的字符 */
function safeUrl(u) {
  return String(u || '').trim().replace(/["'\\\n\r\t]/g, '');
}

/** 刷新两张预览：Logo 方形（空则标题首字母）、头像圆形（空则用户名首字母） */
function paintBrandPreview() {
  const titleEl = $('#brandTitle');
  const title = (titleEl ? titleEl.value : (s.brand && s.brand.title)) || DEFAULT_TITLE;
  const initial = String(title).trim().slice(0, 1).toUpperCase() || 'A';
  const userInitial = String((s && s.username) || 'admin').slice(0, 1).toUpperCase();

  const lb = $('#brandLogoBox');
  if (lb) {
    const u = safeUrl(brandLogo);
    if (u) {
      lb.classList.add('has-img');
      lb.style.backgroundImage = `url("${u}")`;
      lb.textContent = '';
    } else {
      lb.classList.remove('has-img');
      lb.style.backgroundImage = '';
      lb.textContent = initial;
    }
  }

  const ab = $('#brandAvatarBox');
  if (ab) {
    const u = safeUrl(brandAvatar);
    if (u) {
      ab.classList.add('has-img');
      ab.style.backgroundImage = `url("${u}")`;
      ab.textContent = '';
    } else {
      ab.classList.remove('has-img');
      ab.style.backgroundImage = '';
      ab.textContent = userInitial;
    }
  }
}

function bindBrand() {
  const logoInput = $('#brandLogoUrl');
  if (!logoInput) return;

  paintBrandPreview();

  logoInput.addEventListener('input', (e) => {
    brandLogo = e.target.value.trim();
    paintBrandPreview();
  });

  $('#brandAvatarUrl').addEventListener('input', (e) => {
    brandAvatar = e.target.value.trim();
    paintBrandPreview();
  });

  // 标题即时预览（不必等保存）
  $('#brandTitle').addEventListener('input', () => paintBrandPreview());

  $('#brandClear').addEventListener('click', () => {
    brandLogo = '';
    brandAvatar = '';
    $('#brandLogoUrl').value = '';
    $('#brandAvatarUrl').value = '';
    $('#brandTitle').value = '';
    paintBrandPreview();
    toast('已恢复默认，点右上角「保存设置」生效');
  });
}

/* ---------------- 设备配置读写（Lua 键值） ---------------- */
function parseLuaConfig(text) {
  const out = {};
  const re = /^(\w+)\s*=\s*(.+?)\s*$/gm;
  let m;
  while ((m = re.exec(text || ''))) {
    const v = m[2].trim();
    if (v.startsWith('"')) out[m[1]] = v.replace(/^"|"$/g, '');
    else if (v === 'true' || v === 'false') out[m[1]] = v === 'true';
    else if (!isNaN(Number(v))) out[m[1]] = Number(v);
    else out[m[1]] = v;
  }
  return out;
}

function patchLuaConfig(text, kv) {
  let out = text;
  Object.keys(kv).forEach((k) => {
    const v = kv[k];
    const valStr = typeof v === 'number' ? String(v) : typeof v === 'boolean' ? (v ? 'true' : 'false') : '"' + v + '"';
    const re = new RegExp('^(\\s*)(' + k + '\\s*=\\s*)[^\\n]*', 'm');
    const before = out;
    out = out.replace(re, (_, lead, pre) => lead + pre + valStr);
    if (out === before) out = out.replace(/\s*$/, '\n') + k + ' = ' + valStr + '\n';
  });
  return out;
}

function cfgText(res) {
  const r = res && res.result;
  if (typeof r === 'string') return r;
  if (r && r.content) return r.content;
  if (r && r.config) return r.config;
  return '';
}

function msgOf(res) {
  if (!res) return '';
  if (typeof res === 'string') return res;
  if (res.result) {
    if (typeof res.result === 'string') return res.result;
    if (res.result.message) return res.result.message;
  }
  return res.message || '完成';
}

async function readDeviceConfig(which) {
  const devSel = which === 'power' ? '#pwDevice' : '#rcDevice';
  const msgSel = which === 'power' ? '#pwMsg' : '#rcMsg';
  const imei = $(devSel).value;
  if (!imei) { toast('请先选择设备', true); return; }
  try {
    const res = await api.executeTask({ imei, task: 'get_config' });
    if (!res || res.success === false) { toast((res && res.message) || '读取失败', true); return; }
    const text = cfgText(res);
    if (!text) { toast('设备未返回配置内容', true); return; }
    const cfg = parseLuaConfig(text);

    if (which === 'power') {
      $('#pwStart').value = String(cfg.POWERSAVE_START_HOUR != null ? cfg.POWERSAVE_START_HOUR : 1);
      $('#pwEnd').value = String(cfg.POWERSAVE_END_HOUR != null ? cfg.POWERSAVE_END_HOUR : 8);
      $('#pwDeep').checked = cfg.POWERSAVE_DEEP === true;
      $('#pwHeartbeat').value = cfg.POWERSAVE_HEARTBEAT != null ? cfg.POWERSAVE_HEARTBEAT : 600000;
      $('#pwTelemetry').value = cfg.POWERSAVE_TELEMETRY != null ? cfg.POWERSAVE_TELEMETRY : 0;
      $('#pwState').textContent = cfg.POWERSAVE_ENABLE === true ? '省电已启用' : '省电未启用';
      $('#pwState').className = 'badge ' + (cfg.POWERSAVE_ENABLE === true ? 'green' : 'gray');
    } else {
      $('#rcEnable').checked = cfg.RECORD_ENABLE !== false;
      $('#rcTts').checked = cfg.TTS_BEFORE_ENABLE !== false;
    }
    $(msgSel).textContent = '已读取设备当前配置';
    toast('配置已读取');
  } catch (err) {
    toast(err.message, true);
  }
}

async function savePower(withEnable) {
  const imei = $('#pwDevice').value;
  if (!imei) { toast('请先选择设备', true); return; }
  const kv = {
    POWERSAVE_ENABLE: withEnable ? true : false,
    POWERSAVE_START_HOUR: Number($('#pwStart').value),
    POWERSAVE_END_HOUR: Number($('#pwEnd').value),
    POWERSAVE_DEEP: $('#pwDeep').checked,
    POWERSAVE_HEARTBEAT: Number($('#pwHeartbeat').value) || 600000,
    POWERSAVE_TELEMETRY: Number($('#pwTelemetry').value) || 0
  };
  try {
    const res = await api.executeTask({ imei, task: 'get_config' });
    if (!res || res.success === false) { toast((res && res.message) || '读取配置失败', true); return; }
    const patched = patchLuaConfig(cfgText(res), kv);
    const w = await api.executeTask({ imei, task: 'set_config', configText: patched });
    if (!w || w.success === false) { toast((w && w.message) || '写入失败', true); return; }
    if (w.result && w.result.error) { toast(w.result.error, true); return; }
    $('#pwMsg').textContent = '省电配置已写入设备并生效';
    $('#pwState').textContent = '省电已启用';
    $('#pwState').className = 'badge green';
    toast('省电配置已保存');
  } catch (err) { toast(err.message, true); }
}

async function enterPower() {
  const imei = $('#pwDevice').value;
  if (!imei) { toast('请先选择设备', true); return; }
  try {
    await savePower(true);
    const res = await api.executeTask({ imei, task: 'powersave', action: 'enter' });
    if (!res || res.success === false) { toast((res && res.message) || '进入失败', true); return; }
    const msg = msgOf(res) || '已进入省电模式';
    $('#pwMsg').textContent = msg;
    toast(msg);
  } catch (err) { toast(err.message, true); }
}

async function exitPower() {
  const imei = $('#pwDevice').value;
  if (!imei) { toast('请先选择设备', true); return; }
  try {
    const res = await api.executeTask({ imei, task: 'powersave', action: 'exit' });
    if (!res || res.success === false) { toast((res && res.message) || '退出失败', true); return; }
    const msg = msgOf(res) || '已退出省电模式';
    $('#pwMsg').textContent = msg;
    $('#pwState').textContent = '省电未启用';
    $('#pwState').className = 'badge gray';
    toast(msg);
  } catch (err) { toast(err.message, true); }
}

async function saveRecord() {
  const imei = $('#rcDevice').value;
  if (!imei) { toast('请先选择设备', true); return; }
  const kv = {
    RECORD_ENABLE: $('#rcEnable').checked,
    TTS_BEFORE_ENABLE: $('#rcTts').checked
  };
  try {
    const res = await api.executeTask({ imei, task: 'get_config' });
    if (!res || res.success === false) { toast((res && res.message) || '读取配置失败', true); return; }
    const patched = patchLuaConfig(cfgText(res), kv);
    const w = await api.executeTask({ imei, task: 'set_config', configText: patched });
    if (!w || w.success === false) { toast((w && w.message) || '写入失败', true); return; }
    if (w.result && w.result.error) { toast(w.result.error, true); return; }
    $('#rcMsg').textContent = '通话录音配置已保存并下发设备';
    toast('通话录音配置已保存');
  } catch (err) { toast(err.message, true); }
}

/* ---------------- 统一保存（面板级设置） ---------------- */
async function saveAll(btn) {
  collectNotify();
  $$('[data-led]').forEach((el) => {
    const key = el.dataset.led;
    const f = el.dataset.f;
    if (!s[key]) return;
    s[key][f] = el.type === 'checkbox' ? el.checked : Number(el.value) || 5000;
  });
  if ($('#wdUrl')) {
    s.webdav = {
      url: $('#wdUrl').value.trim(),
      username: $('#wdUser').value.trim(),
      password: $('#wdPass').value,
      dir: $('#wdDir').value.trim() || '通话录音'
    };
  }
  if ($('#brandTitle')) {
    s.brand = {
      title: $('#brandTitle').value.trim(),
      logo: safeUrl(brandLogo),
      avatar: safeUrl(brandAvatar)
    };
  }

  await withBusy(btn, async () => {
    try {
      await api.saveSettings({
        notifyEnabled: s.notifyEnabled,
        notifyChannels: s.notifyChannels,
        notifyConfig: s.notifyConfig,
        smsLed: s.smsLed,
        callLed: s.callLed,
        webdav: s.webdav,
        brand: s.brand
      });
      await loadSettings(true);
      // 品牌立即生效（网页标题 / 标签页图标 / 侧栏 Logo）
      window.dispatchEvent(new CustomEvent('app:brand', { detail: s.brand }));
      await applyLedControl();
    } catch (err) { toast(err.message, true); }
  });
}

/** 保存设置后，把灯光控制指令下发到设备（仅在用户改过灯光控制时） */
async function applyLedControl() {
  if (!ledDirty) { toast('设置已保存'); return; }
  const imei = ledCtl.imei || state.imei;
  if (!imei) {
    ledMsg = '设置已保存，但没有可下发的设备';
    renderLedMsg();
    toast(ledMsg, true);
    return;
  }
  const dev = state.devices.find((d) => d.imei === imei);
  if (!dev || !dev.connected) {
    ledMsg = '设置已保存；设备离线，灯光指令未下发';
    renderLedMsg();
    toast('设置已保存，设备离线未下发灯光指令', true);
    return;
  }

  const payload = { imei, task: 'set_led', action: ledCtl.action };
  if (ledCtl.action === 'color') payload.color = ledCtl.color;
  if (ledCtl.action === 'set_mode') payload.mode = Number(ledCtl.mode);

  try {
    const res = await api.executeTask(payload);
    if (!res || res.success === false) {
      ledMsg = '设置已保存，灯光指令下发失败：' + ((res && res.message) || '未知错误');
      renderLedMsg();
      toast(ledMsg, true);
      return;
    }
    if (res.result && res.result.error) {
      ledMsg = '设置已保存，设备返回错误：' + res.result.error;
      renderLedMsg();
      toast(ledMsg, true);
      return;
    }
    ledDirty = false;
    const detail = typeof res.result === 'string' ? res.result : JSON.stringify(res.result || {});
    ledMsg = '已下发到 ' + (dev.name || imei) + ' · ' + detail;
    renderLedMsg();
    toast('设置与灯光指令均已生效');
  } catch (err) {
    ledMsg = '设置已保存，灯光指令下发失败：' + err.message;
    renderLedMsg();
    toast(ledMsg, true);
  }
}
