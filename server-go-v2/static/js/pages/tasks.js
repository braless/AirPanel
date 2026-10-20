/* 任务执行：设备指令下发、参数表单、控制台、配置编辑器、命令库 */

import { api } from '../api.js';
import { state, activeDevice, deviceName } from '../store.js';
import { $, $$, esc, toast, openModal, closeModal, withBusy, fmtClock } from '../ui.js';
import { icon, paintIcons } from '../icons.js';

export const meta = { crumb: '自动化', name: '任务执行' };

/* ---------------- 命令目录（与设备脚本 util_mqtt.lua 一一对应） ---------------- */
export const TASKS = {
  get_temperature: {
    label: '查询温度', icon: 'temp', group: '查询类',
    desc: '读取模组芯片温度', hint: '无需参数，返回摄氏度数值。',
    fields: []
  },
  get_status: {
    label: '查询状态', icon: 'signal', group: '查询类',
    desc: '电压/温度/信号/运营商', hint: '一次性汇总运行状态，返回 JSON。',
    fields: []
  },
  get_device_info: {
    label: '设备信息', icon: 'info', group: '查询类',
    desc: 'IMEI / SN / ICCID / 版本', hint: '读取硬件标识，用于核对设备身份。',
    fields: []
  },
  get_config: {
    label: '读取配置', icon: 'doc', group: '查询类', config: true,
    desc: '返回 /nvm_para.lua 全文',
    hint: '读取设备的运行时配置，结果会填入下方配置编辑器。',
    fields: []
  },
  query_traffic: {
    label: '查询流量', icon: 'globe', group: '查询类',
    desc: '向运营商发查询短信', hint: '按运营商自动发送查询短信，回复会触发通知推送。',
    fields: []
  },
  send_sms: {
    label: '发送短信', icon: 'msg', group: '通信类',
    desc: '通过设备 SIM 卡发短信',
    hint: '运营商按条计费；中文每 70 字一条，超出自动拆分。',
    fields: [
      { k: 'rcv_phone', label: '接收号码', ph: '13800138000', required: true },
      { k: 'content', label: '短信内容', type: 'textarea', ph: '最多 70 个字，超出按多条计费', required: true }
    ]
  },
  dial_call: {
    label: '拨打电话', icon: 'phone', group: '通信类',
    desc: '设备拨打指定号码', hint: '通话最长 300 秒自动挂断，可用「挂断通话」提前结束。',
    fields: [{ k: 'phone', label: '被叫号码', ph: '13912345678', required: true }]
  },
  hang_up: {
    label: '挂断通话', icon: 'x', group: '通信类',
    desc: '结束当前通话', hint: '无通话时设备返回「当前无通话」。',
    fields: []
  },
  send_dtmf: {
    label: '发送按键', icon: 'sliders', group: '通信类',
    desc: '通话中发送 DTMF 按键',
    hint: '需先拨通电话；仅支持数字与 ABCD*#。',
    fields: [{ k: 'dtmf', label: '按键串', ph: '123', required: true }]
  },
  tts_speak: {
    label: '语音播报', icon: 'volume', group: '通信类',
    desc: '扬声器 TTS 朗读',
    hint: '通话进行中不会播放；音量为 0 时静音。',
    fields: [{ k: 'text', label: '朗读文本', type: 'textarea', ph: '快递已到，请下楼取件', required: true }]
  },
  set_ccfc: {
    label: '设置呼转', icon: 'arrowUR', group: '通信类',
    desc: '无条件呼叫转移', hint: '填 0 表示取消全部呼转。',
    fields: [{ k: 'phone', label: '呼转号码（0=取消）', ph: '13800138000', required: true }]
  },
  ussd_query: {
    label: 'USSD 查询', icon: 'terminal', group: '通信类',
    desc: '查话费 / 余额',
    hint: '如电信 *108#；运营商回复通过通知渠道推送。',
    fields: [{ k: 'code', label: 'USSD 查询码', ph: '*108#', required: true }]
  },
  set_config: {
    label: '写入配置', icon: 'pencil', group: '配置与系统', config: true,
    desc: '整体覆盖 nvm_para.lua',
    hint: '覆盖式写入，建议先「读取配置」再修改，避免遗漏参数。',
    fields: []
  },
  edit_config: {
    label: '编辑配置', icon: 'edit', group: '配置与系统', config: true,
    desc: '读取后在线修改保存',
    hint: '选择后自动读取最新配置到编辑器，改完点「保存配置」写回设备。',
    fields: []
  },
  set_volume: {
    label: '设置音量', icon: 'volume', group: '配置与系统',
    desc: '扬声器与通话音量',
    hint: '0-10 的整数，写入 nvm_para.lua 持久保存。',
    fields: [{ k: 'vol', label: '音量 (0-10)', ph: '6', value: '6', required: true }]
  },
  set_gpio: {
    label: 'GPIO 控制', icon: 'sliders', group: '配置与系统',
    desc: '设置引脚输出电平',
    hint: '带载能力有限，控制大电流设备务必经继电器隔离。',
    fields: [
      { k: 'pin', label: 'GPIO 引脚编号', ph: '1', required: true },
      { k: 'level', label: '电平', type: 'select', options: [{ v: '1', label: '1 · 高电平' }, { v: '0', label: '0 · 低电平' }], value: '1' }
    ]
  },
  switch_sim: {
    label: '切换 SIM', icon: 'sim', group: '配置与系统',
    desc: '主副卡槽切换并重启', hint: '设备 10 秒后重启，期间离线属正常现象。',
    fields: []
  },
  reboot: {
    label: '重启设备', icon: 'restart', group: '配置与系统',
    desc: '软重启设备', hint: '重启后约 1-2 分钟恢复在线。',
    fields: []
  },
  set_led: {
    label: '灯光控制', icon: 'lightbulb', group: '配置与系统',
    desc: 'RGB 氛围灯远程控制',
    hint: '灯光控制会覆盖短信 / 来电事件灯，直到下一次事件触发。',
    fields: [
      {
        k: 'action', label: '动作', type: 'select', value: 'on',
        options: [
          { v: 'on', label: '开灯' }, { v: 'off', label: '关灯' },
          { v: 'toggle', label: '切换开关' }, { v: 'color', label: '指定颜色' },
          { v: 'set_mode', label: '切换灯效' }, { v: 'next', label: '下一个灯效' },
          { v: 'prev', label: '上一个灯效' }, { v: 'status', label: '查询状态' }
        ]
      },
      {
        k: 'color', label: '颜色', type: 'select', value: 'blue', showIf: (v) => v.action === 'color',
        options: ['red', 'green', 'blue', 'yellow', 'purple', 'cyan', 'white', 'off'].map((c) => ({ v: c, label: c }))
      },
      {
        k: 'mode', label: '灯效编号', type: 'select', value: '1', showIf: (v) => v.action === 'set_mode',
        options: [1, 2, 3, 4, 5, 6].map((n) => ({ v: String(n), label: '灯效 ' + n }))
      }
    ]
  }
};

/* 卡片网格默认展示的常用任务 */
const PRIMARY = ['send_sms', 'dial_call', 'get_config', 'set_config', 'edit_config', 'set_led', '__custom__'];

const TONES = {
  send_sms: ['rgba(10,132,255,.14)', '#0A84FF'],
  dial_call: ['rgba(52,199,89,.14)', '#34C759'],
  get_config: ['rgba(90,200,250,.16)', '#32ADE6'],
  set_config: ['rgba(175,82,222,.14)', '#AF52DE'],
  edit_config: ['rgba(175,82,222,.14)', '#AF52DE'],
  set_led: ['rgba(255,159,10,.14)', '#FF9F0A'],
  __custom__: ['rgba(120,120,128,.18)', 'var(--ink2)']
};

let current = 'send_sms';
let imei = '';
let consoleLines = [];
let configText = '';

export async function render(root, opts) {
  imei = (opts && opts.imei) || state.imei || (activeDevice() || {}).imei || '';
  if (opts && opts.task) current = opts.task;

  root.innerHTML = shell();
  paintIcons(root);
  bind(root);
  renderDeviceSelect();
  renderTypes();
  renderParams();
  renderConsole();
  renderLibShortcut();
  if (current === 'edit_config') autoReadConfig();
}

function shell() {
  return `
  <div class="hero">
    <div><h1>任务执行</h1><p>选择设备与指令，实时查看下发结果 · 命令库覆盖设备全部 19 条远程命令</p></div>
    <div class="hero-actions">
      <button class="btn ghost" id="taskLib">${icon('doc')}命令库</button>
      <button class="btn" id="taskClear">${icon('trash')}清空控制台</button>
    </div>
  </div>
  <div class="tasks-layout">
    <div class="card">
      <div class="card-head">
        <div><div class="card-title">新建任务</div><div class="card-sub">选择目标设备与任务类型，填写参数后下发</div></div>
        <span class="badge" id="taskDevBadge">—</span>
      </div>

      <div class="field">
        <label class="label" for="taskDevice">目标设备</label>
        <div class="select-wrap"><select class="select" id="taskDevice"></select></div>
      </div>

      <label class="label" style="margin-top:14px">任务类型</label>
      <div class="task-types" id="taskTypes"></div>

      <div class="params" id="taskParams"></div>

      <div class="field" style="margin-top:12px">
        <label class="label" for="taskExtra">附加参数（可选 JSON）</label>
        <input class="input" id="taskExtra" placeholder='{"key":"value"}' style="font-family:var(--mono);font-size:10.5px">
      </div>

      <button class="btn primary lg block" id="taskSubmit" style="margin-top:14px">${icon('bolt')}下发任务</button>
    </div>

    <div style="display:flex;flex-direction:column;gap:12px;min-width:0">
      <div class="card" style="padding:12px">
        <div class="card-head" style="margin-bottom:8px">
          <div><div class="card-title">任务控制台</div><div class="card-sub">实时输出与设备应答 · 超时 30 秒</div></div>
          <button class="btn sm ghost" id="taskClear2">清空</button>
        </div>
        <div class="console" id="console"></div>
      </div>

      <div class="card">
        <div class="card-head" style="margin-bottom:4px">
          <div><div class="card-title">常用命令</div><div class="card-sub">点击直接填入</div></div>
          <button class="btn sm" id="taskLib2">查看全部</button>
        </div>
        <div class="lib-list" id="libList"></div>
      </div>

      <div class="card config-editor hidden" id="configEditor">
        <div class="card-head">
          <div><div class="card-title">配置编辑器</div><div class="card-sub">编辑 /nvm_para.lua，保存后立即生效</div></div>
          <div style="display:flex;gap:5px">
            <button class="btn sm ghost" id="configRead">${icon('refresh')}读取</button>
            <button class="btn sm primary" id="configSave">${icon('check')}保存</button>
          </div>
        </div>
        <textarea class="textarea" id="configText" spellcheck="false" placeholder="点击「读取」从设备拉取当前配置…"></textarea>
        <div style="display:flex;align-items:center;gap:6px;margin-top:8px;font-size:9.5px;color:var(--ink3)">
          ${icon('info')}<span>覆盖式写入，请保留完整的 module(...) 头部，否则设备可能无法加载配置。</span>
        </div>
      </div>
    </div>
  </div>`;
}

function bind(root) {
  $('#taskDevice', root).addEventListener('change', (e) => {
    imei = e.target.value;
    updateBadge();
  });
  $('#taskClear', root).addEventListener('click', clearConsole);
  $('#taskClear2', root).addEventListener('click', clearConsole);
  $('#taskLib', root).addEventListener('click', openLibrary);
  $('#taskLib2', root).addEventListener('click', openLibrary);
  $('#taskSubmit', root).addEventListener('click', (e) => submit(e.currentTarget));
  $('#configRead', root).addEventListener('click', () => readConfig(true));
  $('#configSave', root).addEventListener('click', () => saveConfig());

  const ta = $('#configText', root);
  ta.addEventListener('input', () => { configText = ta.value; });
}

function renderDeviceSelect() {
  const sel = $('#taskDevice');
  if (!state.devices.length) {
    sel.innerHTML = '<option value="">暂无设备</option>';
    updateBadge();
    return;
  }
  sel.innerHTML = state.devices.map((d) =>
    `<option value="${esc(d.imei)}"${d.imei === imei ? ' selected' : ''}>${esc(d.name || d.imei)}${d.connected ? '' : '（离线）'}</option>`
  ).join('');
  if (!imei) { imei = state.devices[0].imei; sel.value = imei; }
  updateBadge();
}

function updateBadge() {
  const el = $('#taskDevBadge');
  if (!el) return;
  const d = state.devices.find((x) => x.imei === imei);
  const on = !!(d && d.connected);
  el.className = 'badge ' + (on ? 'green' : 'gray');
  el.textContent = d ? (on ? '设备在线' : '设备离线') : '无设备';
}

function renderTypes() {
  const box = $('#taskTypes');
  const list = PRIMARY.slice();
  if (!list.includes(current) && TASKS[current]) list.push(current);

  box.innerHTML = list.map((key) => {
    if (key === '__custom__') {
      const [bg, fg] = TONES.__custom__;
      return `<button class="task-type ${current === key ? 'on' : ''}" data-task="${key}" style="--tb:${bg};--tf:${fg}">
        <span class="tile">${icon('terminal')}</span><span class="t">自定义命令</span><span class="d">任意命令与参数</span></button>`;
    }
    const def = TASKS[key];
    const [bg, fg] = TONES[key] || TONES.__custom__;
    return `<button class="task-type ${current === key ? 'on' : ''}" data-task="${key}" style="--tb:${bg};--tf:${fg}">
      <span class="tile">${icon(def.icon)}</span><span class="t">${esc(def.label)}</span><span class="d">${esc(def.desc)}</span></button>`;
  }).join('');

  paintIcons(box);
  $$('.task-type', box).forEach((b) => b.addEventListener('click', () => {
    current = b.dataset.task;
    $$('.task-type', box).forEach((x) => x.classList.toggle('on', x === b));
    renderParams();
    if (current === 'edit_config') autoReadConfig();
  }));
}

function fieldValues() {
  const vals = {};
  $$('#taskParams [data-k]').forEach((el) => { vals[el.dataset.k] = el.value; });
  return vals;
}

function renderParams() {
  const wrap = $('#taskParams');
  const editor = $('#configEditor');

  if (current === '__custom__') {
    wrap.innerHTML = `<label class="label">任务参数</label>
      <div class="grid2" style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
        <div class="field"><label class="label">命令名</label>
          <input class="input" data-k="cmd" placeholder="get_status"></div>
        <div class="field"><label class="label">参数 JSON（可选）</label>
          <input class="input" data-k="args" placeholder='{"pin":1,"level":1}' style="font-family:var(--mono);font-size:10.5px"></div>
      </div>
      <div style="display:flex;gap:7px;margin-top:10px;font-size:9.5px;color:var(--ink3);line-height:1.55">
        ${icon('info')}<span>参数会与 task 一起透传给设备脚本，必须是合法 JSON 对象。</span></div>`;
    paintIcons(wrap);
    editor.classList.add('hidden');
    return;
  }

  const def = TASKS[current];
  if (!def) { wrap.innerHTML = ''; editor.classList.add('hidden'); return; }

  let html = '<label class="label">任务参数</label>';
  if (!def.fields.length) {
    html += '<div style="padding:14px;border-radius:12px;background:var(--fill2);font-size:10.5px;color:var(--ink3);line-height:1.6">该任务无需额外参数，直接下发即可。</div>';
  } else {
    html += '<div class="grid2" style="display:grid;grid-template-columns:1fr 1fr;gap:10px">' +
      def.fields.map((f) => {
        const style = f.type === 'textarea' ? 'grid-column:1/-1' : '';
        if (f.type === 'textarea') {
          return `<div class="field" style="${style}"><label class="label">${esc(f.label)}</label>
            <textarea class="textarea" data-k="${f.k}" placeholder="${esc(f.ph || '')}">${esc(f.value || '')}</textarea></div>`;
        }
        if (f.type === 'select') {
          return `<div class="field" data-wrap="${f.k}" style="${style}"><label class="label">${esc(f.label)}</label>
            <div class="select-wrap"><select class="select" data-k="${f.k}">
              ${f.options.map((o) => `<option value="${esc(o.v)}"${o.v === f.value ? ' selected' : ''}>${esc(o.label)}</option>`).join('')}
            </select></div></div>`;
        }
        return `<div class="field" data-wrap="${f.k}" style="${style}"><label class="label">${esc(f.label)}</label>
          <input class="input" data-k="${f.k}" placeholder="${esc(f.ph || '')}" value="${esc(f.value || '')}"></div>`;
      }).join('') + '</div>';
  }
  if (def.hint) {
    html += `<div style="display:flex;gap:7px;margin-top:10px;font-size:9.5px;color:var(--ink3);line-height:1.55">
      ${icon('info')}<span>${esc(def.hint)}</span></div>`;
  }
  wrap.innerHTML = html;
  paintIcons(wrap);

  // 条件字段显隐（如 set_led 的 color / mode）
  const applyCond = () => {
    const vals = fieldValues();
    def.fields.filter((f) => f.showIf).forEach((f) => {
      const el = wrap.querySelector(`[data-wrap="${f.k}"]`);
      if (el) el.style.display = f.showIf(vals) ? '' : 'none';
    });
  };
  $$('select[data-k], input[data-k]', wrap).forEach((el) => el.addEventListener('change', applyCond));
  applyCond();

  editor.classList.toggle('hidden', !def.config);
}

/* ---------------- 控制台 ---------------- */
function pushLine(text, cls) {
  const mark = cls === 'ok' ? '✓' : cls === 'err' ? '✕' : cls === 'warn' ? '…' : '›';
  consoleLines.push({ t: fmtClock(Math.floor(Date.now() / 1000)), mark, cls: cls || 'muted', text });
  if (consoleLines.length > 200) consoleLines = consoleLines.slice(-200);
  renderConsole();
}

function renderConsole() {
  const box = $('#console');
  if (!box) return;
  if (!consoleLines.length) {
    box.innerHTML = '<div class="ln"><span class="tm">' + fmtClock(Math.floor(Date.now() / 1000)) +
      '</span><span class="muted">›</span><span>控制台就绪，选择任务后点击「下发任务」。</span></div>';
    return;
  }
  box.innerHTML = consoleLines.map((l) =>
    `<div class="ln"><span class="tm">${esc(l.t)}</span><span class="${l.cls}">${l.mark}</span><span>${esc(l.text)}</span></div>`
  ).join('');
  box.scrollTop = box.scrollHeight;
}

function clearConsole() {
  consoleLines = [];
  renderConsole();
}

/* ---------------- 下发 ---------------- */
async function submit(btn) {
  if (!imei) { toast('请先选择设备', true); return; }
  const dev = state.devices.find((d) => d.imei === imei);
  const name = dev ? (dev.name || dev.imei) : imei;

  let task = current;
  const payload = { imei, task };
  const vals = fieldValues();

  if (current === '__custom__') {
    const cmd = (vals.cmd || '').trim();
    if (!cmd) { toast('请输入命令名称', true); return; }
    const raw = (vals.args || '').trim();
    if (raw) {
      try {
        const obj = JSON.parse(raw);
        if (typeof obj !== 'object' || Array.isArray(obj)) throw new Error('必须是对象');
        Object.assign(payload, obj);
      } catch { toast('参数不是合法的 JSON 对象', true); return; }
    }
    task = cmd;
    payload.task = cmd;
  } else {
    const def = TASKS[current];
    if (!def) return;
    const missing = def.fields.filter((f) => f.required && !(vals[f.k] || '').trim() && (!f.showIf || f.showIf(vals)));
    if (missing.length) { toast('请填写：' + missing.map((f) => f.label).join('、'), true); return; }
    def.fields.forEach((f) => {
      if (f.showIf && !f.showIf(vals)) return;
      if (vals[f.k] !== undefined && vals[f.k] !== '') payload[f.k] = vals[f.k];
    });
  }

  const extra = ($('#taskExtra').value || '').trim();
  if (extra) {
    try {
      const obj = JSON.parse(extra);
      if (typeof obj !== 'object' || Array.isArray(obj)) throw new Error('必须是对象');
      Object.assign(payload, obj);
    } catch { toast('附加参数不是合法的 JSON 对象', true); return; }
  }

  const label = current === '__custom__' ? task : (TASKS[current] ? TASKS[current].label : task);
  pushLine(`▶ 下发 ${task}（${label}）→ ${name}`, 'muted');

  await withBusy(btn, async () => {
    try {
      const res = await api.executeTask(payload);
      if (!res || res.success === false) {
        const msg = (res && res.message) || '下发失败';
        pushLine(msg, 'err');
        toast(msg, true);
        return;
      }
      const result = res.result;
      if (result && typeof result === 'object' && result.error) {
        pushLine('设备返回错误：' + result.error, 'err');
        toast(result.error, true);
        return;
      }
      const pretty = typeof result === 'string' ? result : JSON.stringify(result);
      pushLine('← 设备回报：' + pretty, 'ok');

      if (current === 'get_config' || current === 'edit_config') {
        const text = typeof result === 'string' ? result : (result && result.configText) || '';
        if (text) {
          configText = text;
          const ta = $('#configText');
          if (ta) ta.value = text;
          toast('配置已读取到编辑器');
        }
      } else {
        toast('任务执行成功');
      }
    } catch (err) {
      pushLine(err.message, 'err');
      toast(err.message, true);
    }
  });
}

/* ---------------- 配置读写 ---------------- */
function autoReadConfig() {
  if (!configText) readConfig(false);
}

async function readConfig(notify) {
  if (!imei) { toast('请先选择设备', true); return; }
  pushLine('读取 /nvm_para.lua …', 'muted');
  try {
    const res = await api.executeTask({ imei, task: 'get_config' });
    if (!res || res.success === false) {
      const msg = (res && res.message) || '读取失败';
      pushLine(msg, 'err');
      if (notify) toast(msg, true);
      return;
    }
    const text = typeof res.result === 'string' ? res.result : (res.result && res.result.configText) || '';
    if (!text) { pushLine('设备未返回配置内容', 'err'); return; }
    configText = text;
    $('#configText').value = text;
    pushLine(`配置已读取（${text.length} 字符）`, 'ok');
    if (notify) toast('配置已读取');
  } catch (err) {
    pushLine(err.message, 'err');
    if (notify) toast(err.message, true);
  }
}

async function saveConfig() {
  const text = ($('#configText').value || '').trim();
  if (!text) { toast('配置内容为空', true); return; }
  if (!imei) { toast('请先选择设备', true); return; }
  pushLine('写入配置 → set_config', 'muted');
  try {
    const res = await api.executeTask({ imei, task: 'set_config', configText: text });
    if (!res || res.success === false) {
      const msg = (res && res.message) || '保存失败';
      pushLine(msg, 'err');
      toast(msg, true);
      return;
    }
    if (res.result && res.result.error) {
      pushLine('设备返回错误：' + res.result.error, 'err');
      toast(res.result.error, true);
      return;
    }
    pushLine('配置已写入并生效', 'ok');
    toast('配置已保存');
  } catch (err) {
    pushLine(err.message, 'err');
    toast(err.message, true);
  }
}

/* ---------------- 命令库 ---------------- */
function openLibrary() {
  const groups = {};
  Object.entries(TASKS).forEach(([k, v]) => {
    (groups[v.group] = groups[v.group] || []).push([k, v]);
  });

  const body = Object.entries(groups).map(([g, items]) => `
    <div style="margin-bottom:12px">
      <div class="label" style="margin-bottom:5px">${esc(g)} · ${items.length}</div>
      <div class="lib-list" style="margin-top:0">
        ${items.map(([k, v]) => `
          <div class="lib-item" data-cmd="${k}">
            ${icon(v.icon)}<span>${esc(v.label)}</span>
            <span style="color:var(--ink3);font-size:9px;margin-left:6px">${esc(v.desc)}</span>
            <span class="code">${k}</span>
          </div>`).join('')}
      </div>
    </div>`).join('');

  openModal({
    title: '命令库',
    sub: '设备脚本支持的全部远程命令，点击直接填入任务面板',
    body,
    wide: true,
    foot: `<button class="btn ghost" data-close>关闭</button>`
  });
  paintIcons($('#modal'));
  $$('#modalBody [data-cmd]').forEach((el) => el.addEventListener('click', () => {
    current = el.dataset.cmd;
    closeModal();
    renderTypes();
    renderParams();
    if (current === 'edit_config') autoReadConfig();
    toast('已选择：' + TASKS[current].label);
  }));
}

/* 常用命令快捷条 */
function renderLibShortcut() {
  const box = $('#libList');
  if (!box) return;
  const keys = ['get_temperature', 'get_status', 'get_device_info', 'set_gpio', 'reboot'];
  box.innerHTML = keys.map((k) => {
    const v = TASKS[k];
    return `<div class="lib-item" data-cmd="${k}">${icon(v.icon)}${esc(v.label)}<span class="code">${k}</span></div>`;
  }).join('');
  paintIcons(box);
  $$('[data-cmd]', box).forEach((el) => el.addEventListener('click', () => {
    current = el.dataset.cmd;
    renderTypes();
    renderParams();
    toast('已选择：' + TASKS[current].label);
  }));
}
