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
  { key: 'ingresos',        href: 'ingresos.html',        label: 'Ingresos',            icon: '▲' },
  { key: 'cobranzas',       href: 'cobranzas.html',       label: 'Facturas a cobrar',   icon: '▲' },
  { key: 'proveedores',     href: 'proveedores.html',     label: 'Proveedores',         icon: '▤' },
  { key: 'cheques-propios', href: 'cheques-propios.html', label: 'Cheques por pagar',   icon: '▤' },
  { key: 'prestamos',       href: 'prestamos.html',       label: 'Préstamos',           icon: '▤' },
  { key: 'planes',          href: 'planes.html',          label: 'Planes ARCA',         icon: '▤' },
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
};

// -------- Formato ----------
const fmt   = n => n == null ? '-' : new Intl.NumberFormat('es-AR', {maximumFractionDigits:0}).format(n);
const fmtSg = n => (n == null ? '-' : (n < 0 ? '-' : '') + '$ ' + fmt(Math.abs(n)));
const fmtDate = s => { if (!s) return '-'; const d = new Date(s); if (isNaN(d)) return s; return d.toLocaleDateString('es-AR'); };
const fmtDateTime = s => { if (!s) return '-'; const d = new Date(s); if (isNaN(d)) return s; return d.toLocaleDateString('es-AR') + ' ' + d.toLocaleTimeString('es-AR', {hour:'2-digit', minute:'2-digit'}); };
const cls  = n => n == null ? '' : n < 0 ? 'neg' : n > 0 ? 'pos' : '';

// -------- Sidebar ----------
function renderSidebar(counters) {
  const active = document.body.dataset.page || '';
  const nav = PAGES.map(p => {
    const badge = counters && counters[p.key] != null
      ? `<span class="badge-count">${counters[p.key]}</span>` : '';
    return `<a href="${p.href}" class="${p.key===active?'active':''}"><span>${p.icon}</span> ${p.label}${badge}</a>`;
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

// -------- Sort de tabla genérico ----------
// Usage: sortableTable(tbodyElem, colClickIdx, {getVal:(row,col)=>..., isNumeric:true})
function attachTableSort(tableEl) {
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
