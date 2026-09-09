// Layout compartido: sidebar + helpers de formato + carga de datos
// Cada página debe:
//   1. Incluir <link rel="stylesheet" href="assets/style.css">
//   2. Incluir <script src="assets/layout.js"></script>
//   3. Definir data-page="inicio"|"proveedores"|"cheques-propios" en el <body>
//   4. Llamar renderSidebar() + fetchPageData(cb)

const PAGES = [
  { key: 'inicio',          href: 'index.html',           label: 'Inicio',              icon: '◉' },
  { key: 'consolidado',     href: 'consolidado.html',     label: 'Ingresos vs egresos', icon: '≡' },
  { key: 'deuda-global',    href: 'deuda-global.html',    label: 'Deuda global',        icon: '●' },
  { key: 'ingresos',        href: 'ingresos.html',        label: 'Ingresos',            icon: '▲', group: 'Ingresos' },
  { key: 'cobranzas',       href: 'cobranzas.html',       label: 'Facturas a cobrar',   icon: '▲', group: 'Ingresos' },
  { key: 'proveedores',     href: 'proveedores.html',     label: 'Proveedores',         icon: '▤', group: 'Egresos' },
  { key: 'cheques-propios', href: 'cheques-propios.html', label: 'Cheques por pagar',   icon: '▤', group: 'Egresos' },
  { key: 'prestamos',       href: 'prestamos.html',       label: 'Préstamos',           icon: '▤', group: 'Egresos' },
  { key: 'planes',          href: 'planes.html',          label: 'Planes ARCA',         icon: '▤', group: 'Egresos' },
  { key: 'impositivo',      href: 'impositivo.html',      label: 'Impositivo',          icon: '▤', group: 'Egresos' },
];

const JSON_BY_PAGE = {
  'inicio':          'data-inicio.json',
  'consolidado':     'data-consolidado.json',
  'deuda-global':    'data-deuda-global.json',
  'ingresos':        'data-ingresos.json',
  'cobranzas':       'data-cobranzas.json',
  'proveedores':     'data-proveedores.json',
  'cheques-propios': 'data-cheques-propios.json',
  'prestamos':       'data-prestamos.json',
  'planes':          'data-planes.json',
  'impositivo':      'data-impositivo.json',
};

// -------- Formato ----------
const fmt   = n => n == null ? '-' : new Intl.NumberFormat('es-AR', {maximumFractionDigits:0}).format(n);

// fmtNum: 1234567 -> "1,23 M"; 987654321 -> "987,65 MM"; 950 -> "950". Sin símbolo.
function fmtNum(n) {
  if (n == null) return '-';
  const abs = Math.abs(n);
  const sign = n < 0 ? '-' : '';
  if (abs >= 1e9) return sign + (abs/1e9).toLocaleString('es-AR', {minimumFractionDigits:2, maximumFractionDigits:2}) + ' MM';
  if (abs >= 1e6) return sign + (abs/1e6).toLocaleString('es-AR', {minimumFractionDigits:2, maximumFractionDigits:2}) + ' M';
  if (abs >= 1e3) return sign + (abs/1e3).toLocaleString('es-AR', {minimumFractionDigits:1, maximumFractionDigits:1}) + ' K';
  return sign + Math.round(abs).toLocaleString('es-AR');
}

// fmtSg: valores en pesos con abreviatura auto (K/M/MM). "$ 12,91 MM"
const fmtSg = n => n == null ? '-' : '$ ' + fmtNum(n);

// fmtSgFull: monto exacto en pesos sin abreviatura. Para tooltips y celdas de detalle.
const fmtSgFull = n => (n == null ? '-' : (n < 0 ? '-' : '') + '$ ' + fmt(Math.abs(n)));

const fmtDate = s => { if (!s) return '-'; const d = new Date(s); if (isNaN(d)) return s; return d.toLocaleDateString('es-AR'); };
const fmtDateTime = s => { if (!s) return '-'; const d = new Date(s); if (isNaN(d)) return s; return d.toLocaleDateString('es-AR') + ' ' + d.toLocaleTimeString('es-AR', {hour:'2-digit', minute:'2-digit'}); };
const cls  = n => n == null ? '' : n < 0 ? 'neg' : n > 0 ? 'pos' : '';

// -------- Sidebar ----------
// counters: acepta el objeto DATA.counters completo tal como viene del backend.
// Las páginas pasan sus keys tal cual (ver COUNTER_KEY_MAP).
const COUNTER_KEY_MAP = {
  'proveedores':     'proveedores',
  'cheques-propios': 'chequesPropios',
  'prestamos':       'prestamos',
  'planes':          'planes',
  'ingresos':        'ingresos',
  'cobranzas':       'cobranzas',
  'impositivo':      'impositivo',
};

function renderSidebar(counters) {
  const active = document.body.dataset.page || '';
  let currentGroup = null;
  const nav = PAGES.map(p => {
    const ckey = COUNTER_KEY_MAP[p.key];
    const cval = counters && ckey ? counters[ckey] : (counters && counters[p.key]);
    const badge = cval != null && cval !== '' ? `<span class="badge-count">${cval}</span>` : '';
    const link = `<a href="${p.href}" class="${p.key===active?'active':''}"><span>${p.icon}</span> ${p.label}${badge}</a>`;
    if (p.group && p.group !== currentGroup) {
      currentGroup = p.group;
      return `<div class="nav-section">${p.group}</div>${link}`;
    }
    return link;
  }).join('');
  const sidebar = document.createElement('aside');
  sidebar.className = 'sidebar';
  sidebar.innerHTML = `
    <div class="brand">
      <h2>Flujo Fondos</h2>
      <div class="sub">Señales · Grupo</div>
    </div>
    <nav>${nav}</nav>
  `;
  document.body.prepend(sidebar);
  // Envolver el resto en .app
  const rest = document.querySelector('main.content');
  if (rest) {
    const wrap = document.createElement('div');
    wrap.className = 'app';
    document.body.insertBefore(wrap, sidebar);
    wrap.appendChild(sidebar);
    wrap.appendChild(rest);
  }
  // Leyenda de unidades bajo el header (una vez)
  const updated = document.querySelector('.updated');
  if (updated && !document.querySelector('.unit-legend')) {
    const legend = document.createElement('div');
    legend.className = 'unit-legend';
    legend.innerHTML = 'Expresados en pesos · <b>K</b> = miles · <b>M</b> = millones · <b>MM</b> = mil millones';
    updated.after(legend);
  }
}

// -------- Fetch data.json ----------
function fetchPageData(cb) {
  const page = document.body.dataset.page || 'inicio';
  const url = JSON_BY_PAGE[page] || 'data-inicio.json';
  fetch(url + '?_=' + Date.now())
    .then(r => {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    })
    .then(cb)
    .catch(err => {
      console.error('fetchPageData:', err);
      alert('Error al cargar ' + url + ': ' + err.message);
    });
}

// -------- Tooltips en celdas truncadas ----------
// Cuando una celda tiene text-overflow:ellipsis, seteamos title=textContent para
// que se vea completa al pasar el mouse. Se llama automáticamente desde attachTableSort.
function attachEllipsisTooltips(tableEl) {
  tableEl.querySelectorAll('tbody td:not(.num)').forEach(td => {
    if (td.hasAttribute('title')) return;
    const txt = td.innerText.trim();
    if (txt) td.setAttribute('title', txt);
  });
}

// -------- Sort de tabla genérico ----------
// Usage: sortableTable(tbodyElem, colClickIdx, {getVal:(row,col)=>..., isNumeric:true})
function attachTableSort(tableEl) {
  attachEllipsisTooltips(tableEl);
  const ths = tableEl.querySelectorAll('thead th');
  ths.forEach((th, idx) => {
    if (th.classList.contains('no-sort')) return;
    if (!th.querySelector('.sort-arrow')) {
      const a = document.createElement('span');
      a.className = 'sort-arrow';
      a.textContent = '↕';
      th.appendChild(a);
    }
    th.onclick = () => {
      const tbody = tableEl.querySelector('tbody');
      const rows = Array.from(tbody.querySelectorAll('tr:not(.total):not(.group-header)'));
      const dir = th.dataset.sortDir === 'asc' ? 'desc' : 'asc';
      ths.forEach(t => { t.dataset.sortDir=''; t.classList.remove('sorted'); const s=t.querySelector('.sort-arrow'); if(s)s.textContent='↕'; });
      th.dataset.sortDir = dir;
      th.classList.add('sorted');
      th.querySelector('.sort-arrow').textContent = dir === 'asc' ? '↑' : '↓';
      rows.sort((a,b) => {
        const av = a.children[idx]?.dataset.sortVal ?? a.children[idx]?.textContent ?? '';
        const bv = b.children[idx]?.dataset.sortVal ?? b.children[idx]?.textContent ?? '';
        const an = parseFloat(av.replace(/[^\d\.\-]/g,''));
        const bn = parseFloat(bv.replace(/[^\d\.\-]/g,''));
        let cmp;
        if (!isNaN(an) && !isNaN(bn)) cmp = an - bn;
        else cmp = av.localeCompare(bv, 'es-AR');
        return dir === 'asc' ? cmp : -cmp;
      });
      rows.forEach(r => tbody.appendChild(r));
    };
  });
}

// -------- Debounce ----------
function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}
