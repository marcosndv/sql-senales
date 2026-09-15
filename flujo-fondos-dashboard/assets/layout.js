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

// -------- Filtro global por empresa ----------
// Guarda la selección en localStorage. "" = todas.
const EMPRESA_STORAGE_KEY = 'ff.selectedEmpresa';

function getSelectedEmpresa() {
  return localStorage.getItem(EMPRESA_STORAGE_KEY) || '';
}

function setSelectedEmpresa(id) {
  if (id) localStorage.setItem(EMPRESA_STORAGE_KEY, id);
  else localStorage.removeItem(EMPRESA_STORAGE_KEY);
  document.dispatchEvent(new CustomEvent('empresa-changed', {detail: {empresa: id}}));
}

// Filtra un array de rows dejando solo los que matchean con la empresa seleccionada.
// key: nombre de la propiedad que contiene el EmpresaId (default 'EmpresaId').
// Comparación case-insensitive porque el ERP tiene mix (EMPR0001 vs Empr0002).
// Si no hay selección, devuelve rows tal cual.
function filterByEmpresa(rows, key) {
  const sel = getSelectedEmpresa();
  if (!sel || !rows) return rows;
  const k = key || 'EmpresaId';
  const selL = sel.toLowerCase();
  return rows.filter(r => {
    const v = r[k] || r.Empresa || '';
    return String(v).toLowerCase() === selL;
  });
}

function sameEmpresa(a, b) {
  return String(a || '').toLowerCase() === String(b || '').toLowerCase();
}

function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

// Dropdown propio (no <select> nativo, que en Windows abre la lista del sistema fuera de estilo).
// Los listeners van por delegación sobre el contenedor, que se crea una sola vez.
function wireEmpresaFilter(box) {
  const panel = () => box.querySelector('.empresa-panel');
  const trigger = () => box.querySelector('.empresa-trigger');
  const close = () => {
    if (panel()) panel().hidden = true;
    if (trigger()) trigger().setAttribute('aria-expanded', 'false');
  };
  const filterOptions = q => {
    const n = q.trim().toLowerCase();
    panel().querySelectorAll('li[data-id]').forEach(li => {
      li.hidden = n !== '' && li.dataset.id !== '' && !li.textContent.toLowerCase().includes(n);
    });
  };
  box.addEventListener('click', e => {
    if (e.target.closest('.empresa-trigger')) {
      const opening = panel().hidden;
      panel().hidden = !opening;
      trigger().setAttribute('aria-expanded', String(opening));
      if (opening) {
        const search = panel().querySelector('.empresa-search');
        search.value = '';
        filterOptions('');
        search.focus();
        panel().querySelector('li.selected')?.scrollIntoView({block: 'nearest'});
      }
      return;
    }
    const li = e.target.closest('li[data-id]');
    if (li) { close(); setSelectedEmpresa(li.dataset.id); }
  });
  box.addEventListener('input', e => {
    if (e.target.matches('.empresa-search')) filterOptions(e.target.value);
  });
  box.addEventListener('keydown', e => {
    if (e.key === 'Escape') { close(); trigger()?.focus(); }
    if (e.key === 'Enter' && e.target.matches('.empresa-search')) {
      const first = panel().querySelector('li[data-id]:not([hidden])');
      if (first) { close(); setSelectedEmpresa(first.dataset.id); }
    }
  });
  document.addEventListener('click', e => { if (!box.contains(e.target)) close(); });
}

// Chip "Filtrando: X" bajo el título de la página, con botón para quitar el filtro.
function renderFilterChip(label) {
  const host = document.querySelector('header.page-header > div');
  let chip = document.querySelector('.filter-chip');
  if (!label || !host) { if (chip) chip.remove(); return; }
  if (!chip) {
    chip = document.createElement('div');
    chip.className = 'filter-chip';
    chip.addEventListener('click', e => { if (e.target.closest('button')) setSelectedEmpresa(''); });
    host.appendChild(chip);
  }
  chip.innerHTML = `Filtrando <b>${escapeHtml(label)}</b><button type="button" aria-label="Quitar filtro de empresa">×</button>`;
}

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

// Deriva la lista de empresas desde cualquier tabla de detalle si el backend no la mandó.
// Toma NombreEmpresa del row si existe.
function deriveEmpresasFromData(data) {
  if (!data) return [];
  const buckets = [data.facturas, data.cheques, data.cuotas, data.movs, data.detalle,
                   data.posicionCuentas, data.porEmpresa, data.posicionPorEmpresa];
  const m = new Map();
  buckets.forEach(rows => (rows || []).forEach(r => {
    const id = r.EmpresaId || r.Empresa;
    if (!id) return;
    if (!m.has(id)) m.set(id, {EmpresaId: id, NombreEmpresa: r.NombreEmpresa || id});
  }));
  return Array.from(m.values());
}

// Las páginas llaman a renderSidebar() en cada cambio de empresa: el sidebar y el layout
// se crean una sola vez y después solo se actualizan filtro, badges y chip del header.
function renderSidebar(counters, empresas) {
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
  // Filtro global de empresa. "Todas" = sin filtro.
  // `empresas` puede ser: un array (lista explícita), o el DATA completo (deriva de las tablas).
  const sel = getSelectedEmpresa();
  let empSource;
  if (Array.isArray(empresas)) empSource = empresas;
  else if (empresas && typeof empresas === 'object') empSource = deriveEmpresasFromData(empresas);
  else empSource = [];
  if (!empSource || empSource.length === 0) empSource = deriveEmpresasFromData(window.DATA);
  const empList = (empSource || []).slice().sort((a,b) =>
    (a.NombreEmpresa||a.EmpresaId||'').localeCompare(b.NombreEmpresa||b.EmpresaId||'', 'es-AR'));
  const selEmp = empList.find(e => sameEmpresa(e.EmpresaId, sel));
  const selLabel = sel ? (selEmp ? (selEmp.NombreEmpresa || selEmp.EmpresaId) : sel) : 'Todas las empresas';
  const options = [{EmpresaId: '', NombreEmpresa: 'Todas las empresas'}].concat(empList).map(e => {
    const isSel = sel ? sameEmpresa(e.EmpresaId, sel) : e.EmpresaId === '';
    return `<li role="option" data-id="${escapeHtml(e.EmpresaId)}" aria-selected="${isSel}" class="${isSel ? 'selected' : ''}">${escapeHtml(e.NombreEmpresa || e.EmpresaId)}</li>`;
  }).join('');
  const filterHtml = `
    <span class="empresa-filter-label" id="empresaFilterLabel">Empresa</span>
    <button type="button" class="empresa-trigger${sel ? ' filtered' : ''}" aria-haspopup="listbox" aria-expanded="false" aria-labelledby="empresaFilterLabel">
      <span class="empresa-trigger-text">${escapeHtml(selLabel)}</span>
      <svg class="chev" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
    </button>
    <div class="empresa-panel" hidden>
      <input type="search" class="empresa-search" placeholder="Buscar empresa…" aria-label="Buscar empresa" autocomplete="off">
      <ul role="listbox">${options}</ul>
    </div>`;

  let sidebar = document.querySelector('aside.sidebar');
  if (!sidebar) {
    sidebar = document.createElement('aside');
    sidebar.className = 'sidebar';
    sidebar.innerHTML = `
      <div class="brand">
        <h2>Flujo Fondos</h2>
        <div class="sub">Señales · Grupo</div>
      </div>
      <div class="empresa-filter"></div>
      <nav></nav>
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
    wireEmpresaFilter(sidebar.querySelector('.empresa-filter'));
  }
  sidebar.querySelector('.empresa-filter').innerHTML = filterHtml;
  sidebar.querySelector('nav').innerHTML = nav;
  renderFilterChip(sel ? selLabel : '');
  // Leyenda de unidades bajo el header (una vez)
  const updated = document.querySelector('.updated');
  if (updated && !document.querySelector('.unit-legend')) {
    const legend = document.createElement('div');
    legend.className = 'unit-legend';
    legend.innerHTML = 'Expresados en pesos · <b>K</b> = miles · <b>M</b> = millones · <b>MM</b> = mil millones';
    updated.after(legend);
  }
}

// -------- Sesión embebida (intranet) ----------
// server.js redirige /embed a index.html#s=<token>. Se guarda por pestaña y se manda
// como Bearer en los JSON. Entrando directo por flujo.ripaconsultora.net no hay token (Access).
const SESSION_STORAGE_KEY = 'ff.session';
(function captureEmbedSession() {
  const m = /^#s=(.+)$/.exec(location.hash);
  if (!m) return;
  try { sessionStorage.setItem(SESSION_STORAGE_KEY, m[1]); } catch (e) {}
  history.replaceState(null, '', location.pathname + location.search);
})();

function getEmbedSession() {
  try { return sessionStorage.getItem(SESSION_STORAGE_KEY); } catch (e) { return null; }
}

// -------- Fetch data.json ----------
function fetchPageData(cb) {
  const page = document.body.dataset.page || 'inicio';
  const url = JSON_BY_PAGE[page] || 'data-inicio.json';
  const session = getEmbedSession();
  fetch(url + '?_=' + Date.now(), session ? { headers: { Authorization: 'Bearer ' + session } } : undefined)
    .then(r => {
      if (r.status === 401) throw new Error('la sesión venció. Volvé a abrir el dashboard desde la intranet.');
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    })
    .then(cb)
    .catch(err => {
      console.error('fetchPageData:', err);
      alert('Error al cargar ' + url + ': ' + err.message);
    });
}

// -------- Filtro por empresa: recomputa agregados desde raw rows ----------
// Recibe el data ORIGINAL de la página y aplica el filtro de sidebar.
// Devuelve un objeto con el mismo shape pero:
//   - raw rows filtrados (facturas, cheques, cuotas, movs, detalle, posicionCuentas, ...)
//   - agregados (totales, porEmpresa, topN, ...) recomputados desde esos raw rows
// Si no hay empresa seleccionada devuelve el original tal cual.
// Recomputa agregados desde raw rows para el filtro por empresa del sidebar.
// Agregados que la página usa sin dimensión Empresa (proyección del inicio, porMes de deuda
// global, mensual del consolidado) se recalculan desde las versiones con Empresa que manda
// export_data.ps1 (proyeccionPorDia con EmpresaId, porMesEmpresa, mensualPorEmpresa).
// Con un JSON viejo que no las trae, esos agregados quedan globales.
function buildFilteredData(raw) {
  const sel = getSelectedEmpresa();
  if (!sel || !raw) return raw;
  const page = document.body.dataset.page || '';
  const out = Object.assign({}, raw);
  const selL = sel.toLowerCase();
  const same = v => String(v || '').toLowerCase() === selL;

  // Helper: suma o cuenta agrupado por una key desde rows
  const sumBy = (rows, keyFn, valFn) => {
    const m = new Map();
    (rows || []).forEach(r => {
      const k = keyFn(r);
      m.set(k, (m.get(k)||0) + (+valFn(r)||0));
    });
    return m;
  };
  const filt = (rows, key) => filterByEmpresa(rows, key || 'EmpresaId');

  if (page === 'proveedores' || page === 'cobranzas') {
    const facturas = filt(raw.facturas);
    out.facturas = facturas;
    // Recomputar agregados
    const isCob = page === 'cobranzas';
    const totalKey = isCob ? 'TotalACobrar' : 'TotalPendiente';
    const notaKeyPre = isCob ? 'TotalACobrar' : 'TotalPendiente';
    // Solo cuentan facturas no antiguas (misma regla que SQL)
    const activas = facturas.filter(f => (+f.EsAntigua || 0) !== 1);
    const totPend = activas.filter(f => +f.SaldoPendiente > 0).reduce((s,f)=>s+(+f.SaldoPendiente||0),0);
    const totAFavor = activas.filter(f => +f.SaldoPendiente < 0).reduce((s,f)=>s+(+f.SaldoPendiente||0),0);
    const totVenc = activas.filter(f => f.DiasAtraso > 0 && +f.SaldoPendiente > 0).reduce((s,f)=>s+(+f.SaldoPendiente||0),0);
    const cantVenc = activas.filter(f => f.DiasAtraso > 0 && +f.SaldoPendiente > 0).length;
    // Contadores por CUIT
    const porCuit = new Map();
    activas.forEach(f => {
      const s = porCuit.get(f.CUIT) || 0;
      porCuit.set(f.CUIT, s + (+f.SaldoPendiente||0));
    });
    let cantDeuda = 0, cantAFavor = 0;
    porCuit.forEach(v => { if (v > 0) cantDeuda++; else if (v < 0) cantAFavor++; });
    out.totales = Object.assign({}, raw.totales, {
      [totalKey]: totPend,
      TotalAFavor: isCob ? undefined : totAFavor,
      TotalAFavorCliente: isCob ? totAFavor : undefined,
      CantProveedoresDeuda: isCob ? undefined : cantDeuda,
      CantClientesDeuda:    isCob ? cantDeuda : undefined,
      CantProveedoresAFavor: isCob ? undefined : cantAFavor,
      CantClientesAFavor:    isCob ? cantAFavor : undefined,
      CantFacturas: activas.filter(f => +f.SaldoPendiente > 0).length,
      CantEmpresas: 1,
      TotalVencido: totVenc,
      CantVencidas: cantVenc,
    });
    // porEmpresa queda con 1 sola fila
    out.porEmpresa = (raw.porEmpresa || []).filter(e => same(e.EmpresaId));
    // porAntiguedad recomputado
    const tramos = new Map();
    activas.filter(f => +f.SaldoPendiente > 0).forEach(f => {
      const d = +f.DiasAtraso || 0;
      let t = 'Cancelado';
      if (d <= 0) t = 'A vencer';
      else if (d <= 30) t = '1-30 días';
      else if (d <= 60) t = '31-60 días';
      else if (d <= 90) t = '61-90 días';
      else t = '> 90 días';
      const cur = tramos.get(t) || {Tramo:t, CantFacturas:0, [totalKey]:0, TotalPendiente:0};
      cur.CantFacturas++;
      cur[totalKey] += (+f.SaldoPendiente||0);
      cur.TotalPendiente += (+f.SaldoPendiente||0);
      tramos.set(t, cur);
    });
    out.porAntiguedad = Array.from(tramos.values());
    // Top proveedores/clientes recomputado
    const porC = new Map();
    activas.forEach(f => {
      const cur = porC.get(f.CUIT) || {CUIT:f.CUIT, NombreProveedor:f.NombreProveedor, NombreCliente:f.NombreCliente, CantEmpresas:1, CantMovs:0, TotalPendiente:0, TotalACobrar:0, SaldoAFavor:0, TotalVencido:0};
      cur.CantMovs++;
      cur.TotalPendiente += (+f.SaldoPendiente||0);
      cur.TotalACobrar += (+f.SaldoPendiente||0);
      if (+f.SaldoPendiente < 0) cur.SaldoAFavor += (+f.SaldoPendiente||0);
      if (f.DiasAtraso > 0 && +f.SaldoPendiente > 0) cur.TotalVencido += (+f.SaldoPendiente||0);
      porC.set(f.CUIT, cur);
    });
    const topKey = isCob ? 'topClientes' : 'topProveedores';
    out[topKey] = Array.from(porC.values()).filter(r => r.TotalPendiente > 0).sort((a,b)=>b.TotalPendiente - a.TotalPendiente).slice(0, 50);
    // resumenAntiguas: filas antigua para esta empresa
    const antiguas = facturas.filter(f => (+f.EsAntigua||0) === 1 && +f.SaldoPendiente > 0);
    out.resumenAntiguas = {
      CantFacturas: antiguas.length,
      TotalPendiente: antiguas.reduce((s,f)=>s+(+f.SaldoPendiente||0), 0),
      TotalACobrar:   antiguas.reduce((s,f)=>s+(+f.SaldoPendiente||0), 0),
    };
  } else if (page === 'cheques-propios') {
    const cheques = filt(raw.cheques);
    out.cheques = cheques;
    const tot = cheques.reduce((s,c)=>s+(+c.Importe||0), 0);
    const in30 = cheques.filter(c => c.DiasAlPago >= 0 && c.DiasAlPago <= 30);
    out.totales = Object.assign({}, raw.totales, {
      CantCheques: cheques.length,
      TotalImporte: tot,
      CantEmpresas: 1,
      Importe30d: in30.reduce((s,c)=>s+(+c.Importe||0),0),
      Cant30d: in30.length,
    });
    out.porEmpresa = (raw.porEmpresa || []).filter(e => same(e.EmpresaId));
    const banco = new Map();
    cheques.forEach(c => {
      const k = `${c.LibroFondo}|${c.CuentaBancaria}`;
      const cur = banco.get(k) || {LibroFondo:c.LibroFondo, CuentaBancaria:c.CuentaBancaria, CantCheques:0, TotalImporte:0};
      cur.CantCheques++; cur.TotalImporte += (+c.Importe||0);
      banco.set(k, cur);
    });
    out.porBanco = Array.from(banco.values()).sort((a,b)=>b.TotalImporte-a.TotalImporte);
    const benef = new Map();
    cheques.filter(c => c.Beneficiario).forEach(c => {
      const cur = benef.get(c.Beneficiario) || {Beneficiario:c.Beneficiario, CantCheques:0, TotalImporte:0};
      cur.CantCheques++; cur.TotalImporte += (+c.Importe||0);
      benef.set(c.Beneficiario, cur);
    });
    out.topBenefic = Array.from(benef.values()).sort((a,b)=>b.TotalImporte-a.TotalImporte).slice(0, 50);
  } else if (page === 'prestamos' || page === 'planes') {
    const cuotas = filt(raw.cuotas);
    out.cuotas = cuotas;
    const tot = cuotas.reduce((s,c)=>s+(+c.ImporteCuota||0),0);
    const in30 = cuotas.filter(c => c.DiasAlPago >= 0 && c.DiasAlPago <= 30);
    const alerta = cuotas.filter(c => (c.EstadoPlan||'').includes('IMPAGA'));
    out.totales = Object.assign({}, raw.totales, {
      CantCuotas: cuotas.length,
      TotalImporte: tot,
      CantEmpresas: 1,
      CantEntidades: new Set(cuotas.map(c=>c.EntidadFinanciera)).size,
      Importe30d: in30.reduce((s,c)=>s+(+c.ImporteCuota||0),0),
      Cant30d: in30.length,
      CantEnAlerta: alerta.length,
      ImporteEnAlerta: alerta.reduce((s,c)=>s+(+c.ImporteCuota||0),0),
    });
    out.porEmpresa = (raw.porEmpresa || []).filter(e => same(e.EmpresaId));
    const ent = new Map();
    cuotas.forEach(c => {
      const cur = ent.get(c.EntidadFinanciera) || {EntidadFinanciera:c.EntidadFinanciera, CantCuotas:0, TotalImporte:0, CantEmpresas:1};
      cur.CantCuotas++; cur.TotalImporte += (+c.ImporteCuota||0);
      ent.set(c.EntidadFinanciera, cur);
    });
    out.porEntidad = Array.from(ent.values()).sort((a,b)=>b.TotalImporte-a.TotalImporte);
  } else if (page === 'ingresos') {
    const movs = filt(raw.movs);
    out.movs = movs;
    const tot = movs.reduce((s,m)=>s+(+m.Importe||0),0);
    const today = new Date().toISOString().slice(0,10);
    const in30 = movs.filter(m => m.Fecha >= today && m.DiasACobrar <= 30);
    const in7  = movs.filter(m => m.Fecha >= today && m.DiasACobrar <= 7);
    out.totales = Object.assign({}, raw.totales, {
      TotalImporte: tot,
      CantMovs: movs.length,
      CantEmpresas: 1,
      CantOrigenes: new Set(movs.map(m=>m.Origen)).size,
      Importe30d: in30.reduce((s,m)=>s+(+m.Importe||0),0),
      Cant30d: in30.length,
      Importe7d: in7.reduce((s,m)=>s+(+m.Importe||0),0),
    });
    out.porEmpresa = (raw.porEmpresa || []).filter(e => same(e.EmpresaId));
    const orig = new Map();
    movs.forEach(m => {
      const cur = orig.get(m.Origen) || {Origen:m.Origen, CantMovs:0, TotalImporte:0, CantEmpresas:1};
      cur.CantMovs++; cur.TotalImporte += (+m.Importe||0);
      orig.set(m.Origen, cur);
    });
    out.porOrigen = Array.from(orig.values()).sort((a,b)=>b.TotalImporte-a.TotalImporte);
  } else if (page === 'impositivo') {
    const detalle = filt(raw.detalle);
    out.detalle = detalle;
    const today = new Date().toISOString().slice(0,10);
    const venc = detalle.filter(d => d.FechaVencimiento < today);
    const avenc = detalle.filter(d => d.FechaVencimiento >= today);
    out.totales = Object.assign({}, raw.totales, {
      CantItems: detalle.length,
      TotalPendiente: detalle.reduce((s,d)=>s+(+d.Importe||0),0),
      TotalVencido: venc.reduce((s,d)=>s+(+d.Importe||0),0),
      TotalAVencer: avenc.reduce((s,d)=>s+(+d.Importe||0),0),
      CantEmpresas: 1,
      CantGrupos: new Set(detalle.map(d=>d.Grupo)).size,
    });
    out.porEmpresa = (raw.porEmpresa || []).filter(e => same(e.EmpresaId));
    const grp = new Map();
    detalle.forEach(d => {
      const cur = grp.get(d.Grupo) || {Grupo:d.Grupo, Cant:0, Total:0, Vencido:0};
      cur.Cant++; cur.Total += (+d.Importe||0);
      if (d.FechaVencimiento < today) cur.Vencido += (+d.Importe||0);
      grp.set(d.Grupo, cur);
    });
    out.porGrupo = Array.from(grp.values()).sort((a,b)=>b.Total-a.Total);
  } else if (page === 'deuda-global') {
    // deuda-global no trae raw rows completo, solo agregados. Filtramos porEmpresa a 1 fila.
    const emp = (raw.porEmpresa || []).filter(e => same(e.EmpresaId));
    out.porEmpresa = emp;
    const one = emp[0];
    out.totales = Object.assign({}, raw.totales, one ? {
      TotalDeuda: one.TotalDeuda, TotalVencido: one.Vencido,
      TotalProx30: one.Prox30, CantItems: one.CantItems, CantEmpresas: 1,
    } : {TotalDeuda:0, TotalVencido:0, TotalProx30:0, CantItems:0, CantEmpresas:0});
    // porOrigen recomputado desde la sola empresa
    out.porOrigen = one ? [
      {Origen:'Proveedores', Cant:0, Total: one.Proveedores || 0, Vencido:0, Prox30:0},
      {Origen:'Cheques propios', Cant:0, Total: one.ChequesPropios || 0, Vencido:0, Prox30:0},
      {Origen:'Préstamos', Cant:0, Total: one.Prestamos || 0, Vencido:0, Prox30:0},
      {Origen:'Planes ARCA', Cant:0, Total: one.PlanesArca || 0, Vencido:0, Prox30:0},
    ].filter(x => x.Total > 0) : [];
    if (raw.porMesEmpresa) {
      const meses = new Map();
      filt(raw.porMesEmpresa).forEach(r => {
        const k = r.Periodo + '|' + r.Origen;
        const cur = meses.get(k) || {Periodo: r.Periodo, Origen: r.Origen, Total: 0};
        cur.Total += (+r.Total || 0);
        meses.set(k, cur);
      });
      out.porMes = Array.from(meses.values());
    }
  } else if (page === 'consolidado') {
    out.porEmpresa = (raw.porEmpresa || []).filter(e => same(e.EmpresaId));
    const one = out.porEmpresa[0];
    out.totalesAno = Object.assign({}, raw.totalesAno, {
      IngresosAno: one ? one.Ingresos : 0,
      EgresosAno:  one ? one.Egresos  : 0,
    });
    if (raw.mensualPorEmpresa) {
      const meses = new Map();
      filt(raw.mensualPorEmpresa).forEach(r => {
        const k = r.Periodo + '|' + r.EsProyectado;
        const cur = meses.get(k) || {Periodo: r.Periodo, Ingresos: 0, Egresos: 0, Neto: 0, EsProyectado: r.EsProyectado};
        cur.Ingresos += (+r.Ingresos || 0);
        cur.Egresos  += (+r.Egresos  || 0);
        cur.Neto = cur.Ingresos - cur.Egresos;
        meses.set(k, cur);
      });
      out.mensual = Array.from(meses.values())
        .sort((a, b) => a.Periodo.localeCompare(b.Periodo) || (+a.EsProyectado) - (+b.EsProyectado));
      const hoy = new Date();
      const mesActual = hoy.getFullYear() + '-' + String(hoy.getMonth() + 1).padStart(2, '0');
      const actual = out.mensual.find(r => r.Periodo === mesActual && !+r.EsProyectado);
      out.totalesAno.IngresosMes = actual ? actual.Ingresos : 0;
      out.totalesAno.EgresosMes  = actual ? actual.Egresos  : 0;
    }
  } else if (page === 'inicio') {
    const cuentas = filt(raw.posicionCuentas);
    out.posicionCuentas = cuentas;
    const sum = (fld) => cuentas.reduce((s,c)=>s+(+c[fld]||0),0);
    out.posicionTotales = Object.assign({}, raw.posicionTotales, {
      CantCuentas: cuentas.length,
      CantEmpresas: 1,
      Saldo: sum('Saldo'),
      FCI: sum('FCI'), MPago: sum('MPago'), Pix: sum('Pix'),
      DescubiertoAutorizado: sum('DescubiertoAutorizado'),
      Disponible: sum('Disponible'),
      SaldoNegativo: cuentas.filter(c => +c.Saldo < 0).reduce((s,c)=>s+(+c.Saldo||0),0),
      SaldoPositivo: cuentas.filter(c => +c.Saldo > 0).reduce((s,c)=>s+(+c.Saldo||0),0),
    });
    out.posicionPorEmpresa = (raw.posicionPorEmpresa || []).filter(e => same(e.Empresa));
    // posicionPorBanco recomputado
    const banco = new Map();
    cuentas.forEach(c => {
      const cur = banco.get(c.Banco) || {Banco:c.Banco, CantCuentas:0, Saldo:0, Disponible:0};
      cur.CantCuentas++; cur.Saldo += (+c.Saldo||0); cur.Disponible += (+c.Disponible||0);
      banco.set(c.Banco, cur);
    });
    out.posicionPorBanco = Array.from(banco.values()).sort((a,b)=>b.Disponible-a.Disponible);
    // Proyección semanal y KPIs de 30 días: desde proyeccionPorDia con EmpresaId (mismo criterio
    // que el SQL de proyeccion30d: no vencidos con fecha hasta hoy + 30 días).
    if ((raw.proyeccionPorDia || []).some(p => p.EmpresaId !== undefined)) {
      const proy = filt(raw.proyeccionPorDia);
      out.proyeccionPorDia = proy;
      const lim = new Date(); lim.setDate(lim.getDate() + 30);
      const limite = lim.getFullYear() + '-' + String(lim.getMonth() + 1).padStart(2, '0') + '-' + String(lim.getDate()).padStart(2, '0');
      const futuros = proy.filter(p => !+p.EsVencido && p.Fecha <= limite);
      const suma = (tipo, campo) => futuros.filter(p => p.Tipo === tipo).reduce((s, p) => s + (+p[campo] || 0), 0);
      const entradas = suma('ENTRADA', 'Importe');
      const salidas  = suma('SALIDA', 'Importe');
      out.proyeccion30d = Object.assign({}, raw.proyeccion30d, {
        entradas, salidas,
        movEnt: suma('ENTRADA', 'Movimientos'),
        movSal: suma('SALIDA', 'Movimientos'),
        neto: entradas - salidas,
      });
    }
    // Las cuentas sin mapear no pertenecen a ninguna empresa: no aplican con filtro.
    out.sinEmpresa = [];
  }

  return out;
}

// Envuelve el render de una página con el filtro por empresa. La página guarda su DATA raw
// y llama a esta función pasando su callback de render.
function installEmpresaFilter(rawData, renderFn) {
  const state = {raw: rawData};
  const cycle = () => {
    const filtered = buildFilteredData(state.raw);
    renderFn(filtered);
  };
  document.addEventListener('empresa-changed', cycle);
  cycle();
  return {
    updateRaw: (d) => { state.raw = d; cycle(); }
  };
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
