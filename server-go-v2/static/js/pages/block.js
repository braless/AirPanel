/* 屏蔽配置：短信关键字屏蔽 + 来电号码屏蔽 */

import { api } from '../api.js';
import { $, $$, esc, fmtTime, emptyState, loadingState, toast, openModal, closeModal, confirmDialog, withBusy } from '../ui.js';
import { icon, paintIcons } from '../icons.js';

export const meta = { crumb: '系统', name: '屏蔽配置' };

const MODES = {
  keyword: [['contains', '包含关键字']],
  number: [['prefix', '号码前缀匹配'], ['exact', '完全一致'], ['contains', '包含']]
};

let type = 'keyword';
let rules = [];
let keyword = '';
let page = 1;
const PER_PAGE = 20;

export async function render(root) {
  root.innerHTML = shell();
  paintIcons(root);
  bind(root);
  await load();
}

function shell() {
  return `
  <div class="hero">
    <div><h1>屏蔽配置</h1><p>命中规则的短信 / 来电会被标记为疑似垃圾并跳过通知推送</p></div>
    <div class="hero-actions">
      <button class="btn" id="blkReset">${icon('refresh')}恢复内置库</button>
      <button class="btn" id="blkRefresh">${icon('refresh')}刷新</button>
    </div>
  </div>

  <div class="card" style="margin-bottom:12px;padding:14px">
    <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
      <div class="seg-tabs" id="blkTabs">
        <button data-t="keyword" class="on">短信关键字</button>
        <button data-t="number">来电号码</button>
      </div>
      <span class="badge" id="blkCount">—</span>
      <div style="margin-left:auto;display:flex;gap:6px;align-items:center">
        <input class="input" id="blkSearch" placeholder="搜索规则内容" style="width:180px;height:32px;font-size:11px">
        <button class="btn primary sm" id="blkAdd">${icon('plus')}新增规则</button>
      </div>
    </div>
    <div style="display:flex;gap:7px;margin-top:10px;font-size:9.5px;color:var(--ink3);line-height:1.6" id="blkHint">
      ${icon('info')}<span></span>
    </div>
  </div>

  <div class="card data-card">
    <div class="data-scroll">
      <div class="rule-row" style="background:var(--fill2);font-size:8.5px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--ink3)">
        <span>规则内容</span><span>匹配方式</span><span>来源</span><span>备注</span><span style="text-align:right">命中 / 操作</span>
      </div>
      <div id="blkBody">${loadingState(4)}</div>
    </div>
    <div class="pager">
      <span id="blkPageInfo">—</span>
      <div class="pager-btns" id="blkPager"></div>
    </div>
  </div>`;
}

function bind(root) {
  $$('#blkTabs button', root).forEach((b) => b.addEventListener('click', () => {
    type = b.dataset.t;
    page = 1;
    $$('#blkTabs button', root).forEach((x) => x.classList.toggle('on', x === b));
    updateHint();
    load();
  }));
  $('#blkSearch', root).addEventListener('input', (e) => {
    keyword = e.target.value.trim().toLowerCase();
    page = 1;
    renderList();
  });
  $('#blkAdd', root).addEventListener('click', () => openEditor(null));
  $('#blkRefresh', root).addEventListener('click', async (e) => {
    await withBusy(e.currentTarget, async () => { await load(); toast('已刷新'); });
  });
  $('#blkReset', root).addEventListener('click', async () => {
    const ok = await confirmDialog('恢复内置屏蔽库', '会重新写入内置的垃圾短信关键字与骚扰号码，已删除的内置规则将恢复；自定义规则不受影响。', { okText: '恢复内置库' });
    if (!ok) return;
    try {
      await api.resetBlockRules();
      toast('已恢复内置默认库');
      await load();
    } catch (err) { toast(err.message, true); }
  });
  updateHint();
}

function updateHint() {
  const el = $('#blkHint span');
  if (!el) return;
  el.textContent = type === 'keyword'
    ? '短信正文包含任一关键字即判定为垃圾短信，命中后不推送通知，记录中标记 spam。'
    : '来电号码按匹配方式命中即判定为骚扰电话，命中后不推送通知，通话记录中标记 spam。';
}

async function load() {
  const box = $('#blkBody');
  if (!box) return;
  box.innerHTML = loadingState(4);
  try {
    const res = await api.blockRules({ type });
    rules = res.rules || [];
    renderList();
  } catch (err) {
    box.innerHTML = emptyState('加载失败：' + err.message, 'info');
    paintIcons(box);
  }
}

function modeLabel(m) {
  for (const list of Object.values(MODES)) {
    const hit = list.find(([v]) => v === m);
    if (hit) return hit[1];
  }
  return m || '—';
}

function renderList() {
  const box = $('#blkBody');
  const filtered = rules.filter((r) => !keyword || (r.value + r.note).toLowerCase().includes(keyword));
  $('#blkCount').textContent = `共 ${rules.length} 条 · 启用 ${rules.filter((r) => r.enabled).length} 条`;

  if (!filtered.length) {
    box.innerHTML = emptyState(rules.length ? '没有匹配的规则' : '还没有规则，点击「新增规则」添加。', 'shield');
    paintIcons(box);
    renderPager(0);
    return;
  }

  const maxPage = Math.max(1, Math.ceil(filtered.length / PER_PAGE));
  if (page > maxPage) page = maxPage;
  const list = filtered.slice((page - 1) * PER_PAGE, page * PER_PAGE);

  box.innerHTML = list.map((r) => `
    <div class="rule-row" data-id="${r.id}">
      <div class="cell strong" title="${esc(r.value)}">${esc(r.value)}</div>
      <div class="cell"><span class="badge">${esc(modeLabel(r.matchMode))}</span></div>
      <div class="cell"><span class="badge ${r.source === 'builtin' ? 'gray' : 'blue'}">${r.source === 'builtin' ? '内置' : '自定义'}</span></div>
      <div class="cell" style="color:var(--ink3);font-size:10px" title="${esc(r.note || '')}">${esc(r.note || '—')}</div>
      <div class="cell row-actions">
        <span class="badge ${r.hits ? 'orange' : 'gray'}" style="margin-right:6px">${r.hits || 0} 次</span>
        <label class="switch sm" title="${r.enabled ? '停用' : '启用'}">
          <input type="checkbox" data-act="toggle"${r.enabled ? ' checked' : ''}><i></i>
        </label>
        <button class="mini-btn" data-act="edit" title="编辑">${icon('pencil')}</button>
        <button class="mini-btn" data-act="del" title="删除">${icon('trash')}</button>
      </div>
    </div>`).join('');

  paintIcons(box);
  $$('.rule-row', box).forEach((row) => {
    const id = Number(row.dataset.id);
    const rule = rules.find((x) => x.id === id);
    row.querySelectorAll('[data-act]').forEach((el) => {
      const act = el.dataset.act;
      if (act === 'toggle') {
        el.addEventListener('change', async () => {
          try {
            await api.updateBlockRule({ id, value: rule.value, matchMode: rule.matchMode, enabled: el.checked ? 1 : 0, note: rule.note });
            rule.enabled = el.checked ? 1 : 0;
            toast(el.checked ? '已启用' : '已停用');
            renderList();
          } catch (err) { toast(err.message, true); el.checked = !el.checked; }
        });
        return;
      }
      el.addEventListener('click', async () => {
        if (act === 'edit') openEditor(rule);
        if (act === 'del') await removeRule(rule);
      });
    });
  });
  renderPager(filtered.length);
}

function renderPager(count) {
  const info = $('#blkPageInfo');
  const box = $('#blkPager');
  if (!info || !box) return;
  const maxPage = Math.max(1, Math.ceil(count / PER_PAGE));
  info.textContent = `第 ${page} / ${maxPage} 页 · 每页 ${PER_PAGE} 条`;
  let html = `<button data-p="prev"${page <= 1 ? ' disabled' : ''}>‹</button>`;
  for (let i = 1; i <= maxPage; i++) html += `<button data-p="${i}" class="${i === page ? 'on' : ''}">${i}</button>`;
  html += `<button data-p="next"${page >= maxPage ? ' disabled' : ''}>›</button>`;
  box.innerHTML = html;
  $$('button', box).forEach((b) => b.addEventListener('click', () => {
    const v = b.dataset.p;
    if (v === 'prev') page = Math.max(1, page - 1);
    else if (v === 'next') page = Math.min(maxPage, page + 1);
    else page = Number(v);
    renderList();
  }));
}

function openEditor(rule) {
  const editing = !!rule;
  const ruleType = editing ? rule.ruleType : type;
  const modes = MODES[ruleType] || MODES.keyword;
  const cur = editing ? rule.matchMode : modes[0][0];

  openModal({
    title: editing ? '编辑屏蔽规则' : '新增屏蔽规则',
    sub: ruleType === 'keyword' ? '短信正文命中关键字即屏蔽' : '来电号码命中即屏蔽',
    body: `
      <div class="field" style="margin-bottom:12px">
        <label class="label">${ruleType === 'keyword' ? '关键字' : '号码'}</label>
        <input class="input" id="ruleValue" maxlength="60" value="${esc(editing ? rule.value : '')}"
          placeholder="${ruleType === 'keyword' ? '如：退订、中奖、贷款' : '如：13800138000 或 400'}">
      </div>
      <div class="field" style="margin-bottom:12px">
        <label class="label">匹配方式</label>
        <div class="select-wrap"><select class="select" id="ruleMode">
          ${modes.map(([v, l]) => `<option value="${v}"${v === cur ? ' selected' : ''}>${l}</option>`).join('')}
        </select></div>
      </div>
      <div class="field">
        <label class="label">备注（可选）</label>
        <input class="input" id="ruleNote" maxlength="60" value="${esc(editing ? rule.note || '' : '')}" placeholder="如：营销短信">
      </div>`,
    foot: `<button class="btn ghost" data-close>取消</button>
           <button class="btn primary" id="ruleSave">${editing ? '保存' : '添加'}</button>`
  });
  $('#ruleValue').focus();

  $('#ruleSave').addEventListener('click', async (e) => {
    const value = $('#ruleValue').value.trim();
    const matchMode = $('#ruleMode').value;
    const note = $('#ruleNote').value.trim();
    if (!value) { toast('规则内容不能为空', true); return; }

    await withBusy(e.currentTarget, async () => {
      try {
        if (editing) {
          await api.updateBlockRule({ id: rule.id, value, matchMode, enabled: rule.enabled, note });
        } else {
          const res = await api.addBlockRule({ ruleType, value, matchMode, note });
          if (res && res.success === false) { toast(res.message || '添加失败', true); return; }
        }
        closeModal();
        toast(editing ? '已保存' : '已添加');
        await load();
      } catch (err) { toast(err.message, true); }
    });
  });
}

async function removeRule(rule) {
  const ok = await confirmDialog('删除规则', `确认删除「<b>${esc(rule.value)}</b>」？`, { okText: '删除', danger: true });
  if (!ok) return;
  try {
    await api.deleteBlockRule(rule.id);
    toast('已删除');
    await load();
  } catch (err) { toast(err.message, true); }
}
