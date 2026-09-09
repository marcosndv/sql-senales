// Script compartido para páginas de cuotas (prestamos.html / planes.html)
// Espera markup con IDs: kpis, chartTramos, tblEntidad, tblEmpresas, tblCuotas,
// fEntidad, fEmpresa, fTramo, fBusqueda, fResumen, lastUpdated,
// tabsVista (contenedor de tabs), viewCuotas, viewMatriz, tblMatriz
// El HTML debe llamar renderPageCuotas({ tituloSingular, ... }) al final.

let DATA = null;
let chartT = null;
let VISTA_CUOTAS = 'cuotas'; // 'cuotas' | 'matriz'

function renderPageCuotas(opts) {
  fetchPageData(d => {
    DATA = d;
    renderSidebar({
      proveedores: DATA.counters?.proveedores ?? '',
      'cheques-propios': DATA.counters?.chequesPropios ?? '',
      prestamos: DATA.counters?.prestamos ?? '',
      planes: DATA.counters?.planes ?? '',
      ingresos: DATA.counters?.ingresos ?? '',
      cobranzas: DATA.counters?.cobranzas ?? ''
    });
    render();
  });

  function render() {
    document.getElementById('lastUpdated').textContent = fmtDateTime(DATA.lastUpdated);
    renderKpis();
    renderChartTramos();
    renderTablaEntidad();
    renderTablaEmpresas();
    initFiltros();
    initTabs();
    redrawVista();
  }

  function renderKpis() {
    const t = DATA.totales;
    const kpis = [
      {label:'Total por pagar', value:t.TotalImporte, type:'warn', sub:`${fmt(t.CantCuotas)} cuotas`},
      {label:'Próximos 30 días',value:t.Importe30d,   type:'info', sub:`${fmt(t.Cant30d)} cuotas`},
      {label:'Empresas',        value:null, type:'info', sub:`${fmt(t.CantEmpresas)} empresas`},
      {label:'En alerta',       value:t.ImporteEnAlerta, type:'neg', sub:`${fmt(t.CantEnAlerta)} cuotas · con impagas`},
    ];
    document.getElementById('kpis').innerHTML = kpis.map(k => `
      <div class="kpi ${k.type}">
        <div class="label">${k.label}</div>
        <div class="value">${k.value!=null ? fmtSg(k.value) : (k.sub.split(' ')[0])}</div>
        <div class="sub">${k.value!=null ? k.sub : ''}</div>
      </div>`).join('');
  }

  function renderChartTramos() {
    const cuotas = DATA.cuotas || [];
    const buckets = {
      '0-7 días': 0, '8-15 días': 0, '16-30 días': 0,
      '31-60 días': 0, '61-90 días': 0, '> 90 días': 0
    };
    cuotas.forEach(c => {
      const d = c.DiasAlPago;
      if (d == null || d < 0) return;
      if      (d <= 7)   buckets['0-7 días']   += (+c.ImporteCuota||0);
      else if (d <= 15)  buckets['8-15 días']  += (+c.ImporteCuota||0);
      else if (d <= 30)  buckets['16-30 días'] += (+c.ImporteCuota||0);
      else if (d <= 60)  buckets['31-60 días'] += (+c.ImporteCuota||0);
      else if (d <= 90)  buckets['61-90 días'] += (+c.ImporteCuota||0);
      else               buckets['> 90 días']  += (+c.ImporteCuota||0);
    });
    const labels = Object.keys(buckets);
    const data = Object.values(buckets);
    const colors = ['#8f2a2a','#a67c11','#a67c11','#2c5c78','#197a4b','#0f5c3a'];
    if (chartT) chartT.destroy();
    chartT = new Chart(document.getElementById('chartTramos'), {
      type:'bar',
      data:{labels, datasets:[{data, backgroundColor:colors, borderRadius:6}]},
      options:{responsive:true, maintainAspectRatio:false,
        plugins:{legend:{display:false}, tooltip:{callbacks:{label:c=>fmtSg(c.parsed.y)}}},
        scales:{y:{ticks:{callback:v=>fmt(v/1e6)+' M'}}, x:{ticks:{font:{size:10}}}}
      }
    });
  }

  function renderTablaEntidad() {
    const rows = DATA.porEntidad || [];
    document.getElementById('tblEntidad').innerHTML = `
      <thead><tr><th>Entidad</th><th class="num">Cuotas</th><th class="num">Empresas</th><th class="num">Importe</th></tr></thead>
      <tbody>
        ${rows.map(r=>`<tr onclick="window._filtEnt('${(r.EntidadFinanciera||'').replace(/'/g,'&#39;')}')" style="cursor:pointer">
          <td>${r.EntidadFinanciera}</td>
          <td class="num">${r.CantCuotas}</td>
          <td class="num muted">${r.CantEmpresas}</td>
          <td class="num"><b>${fmtSg(+r.TotalImporte)}</b></td>
        </tr>`).join('')}
      </tbody>`;
    attachTableSort(document.getElementById('tblEntidad'));
  }

  function renderTablaEmpresas() {
    const rows = DATA.porEmpresa || [];
    const tot = rows.reduce((a,r)=>({C:a.C+(+r.CantCuotas||0), T:a.T+(+r.TotalImporte||0), A:a.A+(+r.ImporteEnAlerta||0)}),{C:0,T:0,A:0});
    document.getElementById('tblEmpresas').innerHTML = `
      <thead><tr><th>Empresa</th><th class="num">Cuotas</th><th class="num">Importe</th><th class="num">En alerta</th></tr></thead>
      <tbody>
        ${rows.map(r=>`<tr onclick="window._filtEmp('${(r.NombreEmpresa||r.EmpresaId).replace(/'/g,'&#39;')}')" style="cursor:pointer">
          <td>${r.NombreEmpresa||r.EmpresaId}</td>
          <td class="num">${r.CantCuotas}</td>
          <td class="num"><b>${fmtSg(+r.TotalImporte)}</b></td>
          <td class="num ${(+r.ImporteEnAlerta>0)?'neg':'muted'}">${fmtSg(+r.ImporteEnAlerta)}</td>
        </tr>`).join('')}
        <tr class="total"><td>TOTAL</td><td class="num">${tot.C}</td><td class="num">${fmtSg(tot.T)}</td><td class="num">${fmtSg(tot.A)}</td></tr>
      </tbody>`;
    attachTableSort(document.getElementById('tblEmpresas'));
  }

  function initFiltros() {
    const entidades = [...new Set(DATA.cuotas.map(c => c.EntidadFinanciera).filter(Boolean))].sort();
    const empresas = [...new Set(DATA.cuotas.map(c => c.NombreEmpresa || c.EmpresaId).filter(Boolean))].sort();
    document.getElementById('dlEntidad').innerHTML = entidades.map(e=>`<option value="${e}">`).join('');
    document.getElementById('dlEmpresa').innerHTML = empresas.map(e=>`<option value="${e}">`).join('');
    ['fEntidad','fEmpresa','fTramo','fBusqueda'].forEach(id => {
      document.getElementById(id).oninput = redrawVista;
    });
    window._filtEnt = e => { document.getElementById('fEntidad').value = e; redrawVista(); scrollToTabla(); };
    window._filtEmp = n => { document.getElementById('fEmpresa').value = n; redrawVista(); scrollToTabla(); };
  }

  function initTabs() {
    const tabsEl = document.getElementById('tabsVista');
    if (!tabsEl) return;
    tabsEl.querySelectorAll('button').forEach(b => {
      b.onclick = () => {
        VISTA_CUOTAS = b.dataset.view;
        tabsEl.querySelectorAll('button').forEach(x => x.classList.toggle('active', x === b));
        document.getElementById('viewCuotas').classList.toggle('hidden', VISTA_CUOTAS !== 'cuotas');
        document.getElementById('viewMatriz').classList.toggle('hidden', VISTA_CUOTAS !== 'matriz');
        redrawVista();
      };
    });
  }

  function scrollToTabla() {
    const el = document.getElementById(VISTA_CUOTAS === 'matriz' ? 'viewMatriz' : 'viewCuotas');
    if (el) el.scrollIntoView({behavior:'smooth', block:'start'});
  }

  function filtrarCuotas() {
    const fe = document.getElementById('fEntidad').value.trim();
    const fm = document.getElementById('fEmpresa').value.trim();
    const ft = document.getElementById('fTramo').value;
    const fq = document.getElementById('fBusqueda').value.trim().toLowerCase();
    return DATA.cuotas.filter(c => {
      if (fe && (c.EntidadFinanciera||'').toLowerCase().indexOf(fe.toLowerCase()) < 0) return false;
      if (fm && ((c.NombreEmpresa||c.EmpresaId)||'').toLowerCase().indexOf(fm.toLowerCase()) < 0) return false;
      if (ft === '7'      && !(c.DiasAlPago <= 7))  return false;
      if (ft === '30'     && !(c.DiasAlPago <= 30)) return false;
      if (ft === '60'     && !(c.DiasAlPago <= 60)) return false;
      if (ft === 'futuro' && !(c.DiasAlPago > 60))  return false;
      if (fq) {
        const t = ((c.Concepto||'')+' '+(c.NumeroOrigen||'')+' '+(c.EntidadFinanciera||'')+' '+(c.NombreEmpresa||'')+' '+(c.Nota||'')).toLowerCase();
        if (t.indexOf(fq) < 0) return false;
      }
      return true;
    });
  }

  function redrawVista() {
    const filtrados = filtrarCuotas();
    const total = filtrados.reduce((s,c)=>s+(+c.ImporteCuota||0),0);
    document.getElementById('fResumen').innerHTML = `<b>${filtrados.length}</b> cuotas · Total <b>${fmtSg(total)}</b>`;
    if (VISTA_CUOTAS === 'matriz') renderMatriz(filtrados);
    else                            renderTablaCuotas(filtrados);
  }

  function renderTablaCuotas(filtrados) {
    document.getElementById('tblCuotas').innerHTML = `
      <thead><tr>
        <th>Entidad</th><th>Empresa</th><th>Concepto</th><th>Nro</th>
        <th class="num">Cuota</th><th>Vencimiento</th><th class="num">Días</th>
        <th class="num">Importe</th><th>Estado</th>
      </tr></thead>
      <tbody>
        ${filtrados.slice(0, 2000).map(c=>{
          const alertaBadge = c.EstadoPlan && c.EstadoPlan.trim() && c.EstadoPlan.toUpperCase().includes('IMPAGA')
            ? `<span class="badge warn">${c.EstadoPlan}</span>` : '';
          return `<tr>
            <td>${c.EntidadFinanciera||''}</td>
            <td>${c.NombreEmpresa||c.EmpresaId||''}</td>
            <td class="muted">${c.Concepto||''}</td>
            <td class="muted">${c.NumeroOrigen||''}</td>
            <td class="num muted">${c.NroCuota||''}</td>
            <td>${fmtDate(c.FechaVto)}</td>
            <td class="num ${c.DiasAlPago<=7?'warn':'muted'}" data-sort-val="${c.DiasAlPago}">${c.DiasAlPago}</td>
            <td class="num" data-sort-val="${+c.ImporteCuota||0}"><b>${fmtSgFull(+c.ImporteCuota)}</b></td>
            <td>${alertaBadge}</td>
          </tr>`;
        }).join('')}
        ${filtrados.length > 2000 ? `<tr><td colspan="9" class="muted" style="text-align:center;padding:12px">(mostrando primeras 2000 de ${filtrados.length} — filtrá para acotar)</td></tr>` : ''}
      </tbody>`;
    attachTableSort(document.getElementById('tblCuotas'));
  }

  // Matriz: filas = préstamo (Empresa + Entidad + NroOrigen), columnas = mes YYYY-MM
  function renderMatriz(filtrados) {
    const key = c => `${c.NombreEmpresa||c.EmpresaId||''}||${c.EntidadFinanciera||''}||${c.NumeroOrigen||''}||${c.Concepto||''}`;
    const rowMap = new Map();
    const mesSet = new Set();
    filtrados.forEach(c => {
      const k = key(c);
      const mes = (c.FechaVto || '').substring(0, 7); // YYYY-MM
      if (!mes) return;
      mesSet.add(mes);
      if (!rowMap.has(k)) {
        rowMap.set(k, {
          Empresa: c.NombreEmpresa||c.EmpresaId||'',
          Entidad: c.EntidadFinanciera||'',
          NroOrigen: c.NumeroOrigen||'',
          Concepto: c.Concepto||'',
          alerta: false,
          cells: {},
          total: 0,
          cuotasCant: 0
        });
      }
      const r = rowMap.get(k);
      const imp = (+c.ImporteCuota||0);
      r.cells[mes] = (r.cells[mes] || 0) + imp;
      r.total += imp;
      r.cuotasCant++;
      if (c.EstadoPlan && c.EstadoPlan.toUpperCase().includes('IMPAGA')) r.alerta = true;
    });
    const meses = [...mesSet].sort();
    const rows = [...rowMap.values()].sort((a,b) => b.total - a.total);

    // Totales por mes
    const totMes = {};
    meses.forEach(m => { totMes[m] = rows.reduce((s,r) => s + (r.cells[m]||0), 0); });
    const totGeneral = rows.reduce((s,r) => s + r.total, 0);

    const mesHeader = meses.map(m => `<th class="num mes">${fmtMes(m)}</th>`).join('');
    const filas = rows.slice(0, 500).map(r => {
      const celdas = meses.map(m => {
        const v = r.cells[m] || 0;
        return v > 0
          ? `<td class="num" data-sort-val="${v}">${fmtSgCompact(v)}</td>`
          : `<td class="num muted">·</td>`;
      }).join('');
      return `<tr>
        <td class="sticky-col emp">${r.Empresa}</td>
        <td class="sticky-col ent">${r.Entidad}</td>
        <td class="sticky-col nro">${r.NroOrigen}${r.alerta?' <span class="badge warn" title="Tiene cuotas impagas">!</span>':''}</td>
        <td class="num sticky-col cnt">${r.cuotasCant}</td>
        ${celdas}
        <td class="num sticky-col total"><b>${fmtSg(r.total)}</b></td>
      </tr>`;
    }).join('');

    const filaTotales = `<tr class="total">
      <td class="sticky-col emp" colspan="3">TOTAL (${rows.length} préstamos)</td>
      <td class="num sticky-col cnt">${filtrados.length}</td>
      ${meses.map(m => `<td class="num">${fmtSgCompact(totMes[m])}</td>`).join('')}
      <td class="num sticky-col total"><b>${fmtSg(totGeneral)}</b></td>
    </tr>`;

    document.getElementById('tblMatriz').innerHTML = `
      <thead><tr class="no-sort">
        <th class="sticky-col emp">Empresa</th>
        <th class="sticky-col ent">Entidad</th>
        <th class="sticky-col nro">Nº operación</th>
        <th class="num sticky-col cnt">Ctas</th>
        ${mesHeader}
        <th class="num sticky-col total">Total</th>
      </tr></thead>
      <tbody>
        ${filas}
        ${rows.length > 500 ? `<tr><td colspan="${meses.length+5}" class="muted" style="text-align:center;padding:12px">(mostrando primeras 500 de ${rows.length} — filtrá para acotar)</td></tr>` : ''}
        ${filaTotales}
      </tbody>`;
  }
}

// Helpers de formato para la matriz
function fmtMes(yyyymm) {
  if (!yyyymm) return '';
  const [y, m] = yyyymm.split('-');
  const meses = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
  const idx = (parseInt(m,10)||1) - 1;
  return `${meses[idx]} ${y.substring(2)}`;
}
function fmtSgCompact(v) {
  const n = +v || 0;
  const abs = Math.abs(n);
  if (abs >= 1e9) return (n/1e9).toFixed(2)+'B';
  if (abs >= 1e6) return (n/1e6).toFixed(1)+'M';
  if (abs >= 1e3) return (n/1e3).toFixed(0)+'K';
  return n.toFixed(0);
}
