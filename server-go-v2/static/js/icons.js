/* SF Symbols 风格的线性 SVG 图标库 */

export const ICONS = {
  grid: '<rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/>',
  cpu: '<rect x="6.5" y="6.5" width="11" height="11" rx="2.5"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/>',
  bolt: '<path d="M13 2.5 5.5 13.5h5l-1 8 8-11.5h-5z"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5.5l3.5 2"/>',
  phone: '<path d="M6.2 3.8h3l1.4 3.6-1.8 1.4a12.5 12.5 0 0 0 5.4 5.4l1.4-1.8 3.6 1.4v3c0 1-.8 1.8-1.8 1.8C10.6 18.6 5.4 13.4 4.4 5.6c0-1 .8-1.8 1.8-1.8Z"/>',
  msg: '<path d="M4 5.5h16v11H9l-5 4z"/><path d="M8 9.5h8M8 12.5h5"/>',
  mic: '<rect x="9" y="3" width="6" height="10" rx="3"/><path d="M6 11a6 6 0 0 0 12 0M12 17v3M9 20h6"/>',
  list: '<path d="M8 6h12M8 12h12M8 18h12"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>',
  checkSquare: '<rect x="3.5" y="3.5" width="17" height="17" rx="4"/><path d="m8 12 2.5 2.5L16 9"/>',
  shield: '<path d="M12 3 5 6v6c0 4.2 3 7.2 7 9 4-1.8 7-4.8 7-9V6z"/><path d="m9 12 2 2 4-4"/>',
  gear: '<circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v3M12 18.2v3M2.8 12h3M18.2 12h3M5.5 5.5l2.1 2.1M16.4 16.4l2.1 2.1M18.5 5.5l-2.1 2.1M7.6 16.4l-2.1 2.1"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 4 4"/>',
  refresh: '<path d="M20 12a8 8 0 1 1-2.4-5.7"/><path d="M20 4v4h-4"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  chevD: '<path d="m5 9 7 7 7-7"/>',
  chevR: '<path d="m9 5 7 7-7 7"/>',
  chevL: '<path d="m15 5-7 7 7 7"/>',
  more: '<circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/>',
  play: '<path d="M8 5.5v13l11-6.5z"/>',
  pause: '<path d="M8 5v14M16 5v14"/>',
  trash: '<path d="M4.5 7h15M9 7V5h6v2M6.5 7l1 13h9l1-13M10 11v5M14 11v5"/>',
  pencil: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4M4 20v-4"/>',
  external: '<path d="M14 4h6v6M20 4l-9 9M18 14v5H5V6h5"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  wifi: '<path d="M4 9a12 12 0 0 1 16 0M7 12.5a8 8 0 0 1 10 0M10 16a4 4 0 0 1 4 0"/><circle cx="12" cy="19" r="1"/>',
  battery: '<rect x="2.5" y="7.5" width="17" height="9" rx="3"/><path d="M21 11v2"/><path d="M6 10.5v3"/>',
  signal: '<path d="M4 20v-4M9 20v-8M14 20V7M19 20V4"/>',
  temp: '<path d="M10 14.5V5a2 2 0 1 1 4 0v9.5a4 4 0 1 1-4 0Z"/><path d="M12 9v6"/>',
  power: '<path d="M12 3v9"/><path d="M7.5 6.5a8 8 0 1 0 9 0"/>',
  sim: '<path d="M6 3.5h8l4 4v13H6z"/><rect x="9" y="11" width="6" height="5" rx="1"/>',
  server: '<rect x="3.5" y="4.5" width="17" height="6" rx="2"/><rect x="3.5" y="13.5" width="17" height="6" rx="2"/><path d="M7 7.5h.01M7 16.5h.01M11 7.5h5M11 16.5h5"/>',
  key: '<circle cx="8" cy="12" r="4"/><path d="M12 12h8M17 12v3M20 12v2"/>',
  person: '<circle cx="12" cy="8" r="3.5"/><path d="M5 20c0-3.5 3-6 7-6s7 2.5 7 6"/>',
  bell: '<path d="M6 9a6 6 0 0 1 12 0c0 4 1.5 5.5 1.5 5.5h-15S6 13 6 9Z"/><path d="M10 18a2 2 0 0 0 4 0"/>',
  globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.3 2.5 14.7 0 17M12 3.5c-2.5 2.3-2.5 14.7 0 17"/>',
  terminal: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="m7.5 9 3 3-3 3M13 15h4"/>',
  doc: '<path d="M7 3.5h6.5L18 8v12.5H7z"/><path d="M13.5 3.5V8H18M9.5 12h6M9.5 15.5h6"/>',
  sliders: '<path d="M4 7h6M14 7h6M4 17h10M18 17h2"/><circle cx="12" cy="7" r="2"/><circle cx="16" cy="17" r="2"/>',
  lightbulb: '<path d="M9 18h6M10 21h4"/><path d="M8.5 14.5a6 6 0 1 1 7 0c-.8.6-1 1.4-1 2.5h-5c0-1.1-.2-1.9-1-2.5Z"/>',
  edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/>',
  download: '<path d="M12 3v12M7 10l5 5 5-5M4 20h16"/>',
  upload: '<path d="M12 16V4M7 9l5-5 5 5M4 20h16"/>',
  filter: '<path d="M4 6h16M7 12h10M10 18h4"/>',
  cal: '<rect x="3.5" y="5.5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3.5v4M16 3.5v4"/>',
  arrowDL: '<path d="M17 7 7 17M15 17H7V9"/>',
  arrowUR: '<path d="M7 17 17 7M9 7h8v8"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/>',
  moon: '<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z"/>',
  palette: '<path d="M12 3a9 9 0 1 0 0 18h1.5a2 2 0 0 0 0-4H13a2 2 0 0 1 0-4h4a4 4 0 0 0 4-4c0-3.3-4-6-9-6Z"/><circle cx="7.5" cy="10" r="1"/><circle cx="10" cy="6.5" r="1"/><circle cx="14" cy="6.5" r="1"/>',
  lock: '<rect x="5.5" y="10.5" width="13" height="9.5" rx="2.5"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>',
  logout: '<path d="M10 4H5v16h5M15 8l4 4-4 4M19 12H9"/>',
  restart: '<path d="M20 12a8 8 0 1 1-2.4-5.7"/><path d="M20 4v4h-4"/>',
  info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.01"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="3"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
  volume: '<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M16 9a4 4 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11"/>',
  wave: '<path d="M3 12h2l2-6 3 12 3-9 2 5 2-3h4"/>',
  inbox: '<path d="M4 13h4l1.5 3h5L16 13h4"/><path d="M4 13 6 5h12l2 8v6H4z"/>'
};

const FILLED = new Set(['bolt', 'play', 'pause', 'signal']);

/** 把 <i class="ic" data-i="xxx"> 渲染为 SVG */
export function paintIcons(root) {
  (root || document).querySelectorAll('.ic[data-i]').forEach((el) => {
    const key = el.dataset.i;
    const body = ICONS[key];
    if (!body) return;
    const fill = FILLED.has(key);
    el.innerHTML = '<svg viewBox="0 0 24 24" fill="' + (fill ? 'currentColor' : 'none') +
      '" stroke="' + (fill ? 'none' : 'currentColor') +
      '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>';
  });
}

/** 生成图标 HTML 片段 */
export function icon(key, cls) {
  return '<i class="ic ' + (cls || '') + '" data-i="' + key + '"></i>';
}
