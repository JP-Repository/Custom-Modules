/* PSInsightHTML Fluent application renderer.
   Renders the JSON model produced by ConvertTo-PSIFluentModel. Vanilla JS, no dependencies,
   no network access. Untrusted text is always HTML-escaped before insertion. */
(function () {
  'use strict';

  // ------------------------------------------------------------------ data & helpers
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var D = JSON.parse($('#pf-data').textContent);
  var ICONS = {};
  try { ICONS = JSON.parse($('#pf-icons').textContent || '{}'); } catch (e) { ICONS = {}; }
  // Windows PowerShell 5.1 can collapse one-element arrays to scalars on the way to JSON;
  // normalise every field the renderer treats as a list.
  function arr(x) { return x === null || x === undefined ? [] : Array.isArray(x) ? x : [x]; }
  (function normalise() {
    D.nav = arr(D.nav); D.pages = arr(D.pages); D.sections = arr(D.sections); D.findings = arr(D.findings); D.assessments = arr(D.assessments);
    D.nav.forEach(function (g) { g.items = arr(g.items); });
    D.pages.forEach(function (p) { p.sections = arr(p.sections); p.commands = arr(p.commands); });
    D.sections.forEach(function (s) {
      s.rows = arr(s.rows);
      s.rows.forEach(function (r) {
        r.items = arr(r.items);
        r.items.forEach(function (c) {
          if (c.t === 'Table') {
            c.columns = arr(c.columns); c.numeric = arr(c.numeric); c.rows = arr(c.rows).map(arr); c.filters = arr(c.filters);
            c.filters.forEach(function (f) { f.values = arr(f.values); });
            c.export.columns = arr(c.export.columns); c.export.formats = arr(c.export.formats);
            c.rowStatus = c.rowStatus || {}; c.cellStatus = c.cellStatus || {};
          }
          if (c.t === 'Chart') { c.categories = arr(c.categories); c.series = arr(c.series); c.series.forEach(function (s2) { s2.values = arr(s2.values); }); c.status = arr(c.status); if (c.filter) { c.filter.values = arr(c.filter.values); } }
          if (c.t === 'KeyValue') { c.rows = arr(c.rows); }
          if (c.t === 'Sparkline') { c.values = arr(c.values); }
          if (c.t === 'KPI' && c.filter) { c.filter.values = arr(c.filter.values); }
          if (c.t === 'KPI' && c.drill) { c.drill.records = arr(c.drill.records); }
          if (c.evidence) { c.evidence.conditions = arr(c.evidence.conditions); c.evidence.columns = arr(c.evidence.columns); c.evidence['export'] = arr(c.evidence['export']); c.evidence.conditions.forEach(function (k) { if (k.values) { k.values = arr(k.values); } }); }
        });
      });
    });
  })();
  var META = D.meta;
  var ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  function esc(s) { return s === null || s === undefined ? '' : String(s).replace(/[&<>"']/g, function (c) { return ESC[c]; }); }
  function fmt(n) { return n === null || n === undefined || n === '' ? '\u2014' : (typeof n === 'number' ? n.toLocaleString('en-US', { maximumFractionDigits: 2 }) : String(n)); }
  function plural(n, one, many) { return fmt(n) + ' ' + (n === 1 ? one : (many || one + 's')); }
  function tipAttr(html) { return ' data-tip="' + esc(html) + '"'; }
  function tipText(t) { return tipAttr(esc(t)); }

  // PSInsightHTML icon names (Fluent roles + legacy stroke names) -> Fluent icon roles
  var ICON_ALIAS = {
    navigationhome: 'home', navigationsearch: 'search', menu: 'menu', appsettings: 'settings', themelight: 'sun', themedark: 'moon',
    document: 'document', appchevron: 'chevronD', appclose: 'close', severitywarning: 'warning', severityerror: 'critical',
    severitysuccess: 'healthy', severityinfo: 'info', resourceserver: 'server', securityshield: 'shield', relationship: 'relationship',
    rules: 'rules', 'export': 'download', dashboard: 'grid', server: 'server', domain: 'domain', replication: 'sync', security: 'shield',
    certificate: 'certificate', users: 'people', cloud: 'cloud', database: 'database', network: 'network', warning: 'warning',
    critical: 'critical', info: 'info', healthy: 'healthy', settings: 'settings', search: 'search', arrow: 'arrowRight', close: 'close',
    'theme/light': 'sun', 'theme/dark': 'moon', file: 'document', print: 'print', chevron: 'chevronD'
  };
  function role(name, fallback) {
    if (!name) { return fallback || 'document'; }
    if (ICONS[name]) { return name; }
    var r = ICON_ALIAS[String(name).toLowerCase()];
    return r && ICONS[r] ? r : (fallback || 'document');
  }
  function ic(name, cls) { return '<span class="pf-ico' + (cls ? ' ' + cls : '') + '" aria-hidden="true">' + (ICONS[name] || ICONS.document || '') + '</span>'; }

  var STATUSES = ['Healthy', 'Warning', 'Critical', 'Informational', 'Neutral', 'Unknown', 'NotChecked'];
  var STATUS_SET = {}; STATUSES.forEach(function (s) { STATUS_SET[s.toLowerCase()] = s; }); STATUS_SET.info = 'Informational';
  var RANK = { Critical: 0, Warning: 1, Unknown: 2, NotChecked: 3, Informational: 4, Healthy: 5, Neutral: 6 };
  var ST_ICON = { Healthy: 'healthy', Warning: 'warning', Critical: 'critical', Informational: 'info', Neutral: 'info', Unknown: 'unknown', NotChecked: 'clock' };
  var ST_LABEL = { NotChecked: 'Not checked', Informational: 'Informational' };
  function normStatus(v) { if (v === null || v === undefined) { return null; } return STATUS_SET[String(v).trim().toLowerCase()] || null; }
  function stLabel(s) { return ST_LABEL[s] || s; }
  function stChip(s, text) { s = normStatus(s) || 'Unknown'; return '<span class="pf-status pf-st-' + s + '">' + ic(ST_ICON[s]) + esc(text || stLabel(s)) + '</span>'; }
  function worst(list) { var w = null; list.forEach(function (s) { if (s && (w === null || RANK[s] < RANK[w])) { w = s; } }); return w; }

  var app = $('#pf-app');
  var toastTimer;
  function toast(msg) { var t = $('#pf-toast'); t.innerHTML = ic('healthy') + esc(msg); t.classList.add('show'); clearTimeout(toastTimer); toastTimer = setTimeout(function () { t.classList.remove('show'); }, 2000); }
  function copy(text) {
    var done = function () { toast('Copied to clipboard'); };
    if (navigator.clipboard && window.isSecureContext) { navigator.clipboard.writeText(text).then(done, function () { fallbackCopy(text, done); }); }
    else { fallbackCopy(text, done); }
  }
  function fallbackCopy(text, done) {
    var ta = document.createElement('textarea'); ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); done(); } catch (e) { toast('Copy failed'); }
    ta.remove();
  }

  // ------------------------------------------------------------------ indexes
  var sectionPage = {};            // section index -> page id
  var pageById = {};
  D.pages.forEach(function (p) { pageById[p.id] = p; p.sections.forEach(function (i) { if (!(i in sectionPage)) { sectionPage[i] = p.id; } }); });
  var tables = {};                 // table id (lower) -> { comp, section }
  var findingById = {};
  var kpis = [];
  D.sections.forEach(function (s, si) {
    s.rows.forEach(function (r) {
      r.items.forEach(function (c) {
        if (c.t === 'Table') { tables[c.id.toLowerCase()] = { comp: c, section: si }; }
        if (c.t === 'Finding') { findingById[c.id] = c; c._section = si; }
        if (c.t === 'KPI') { kpis.push({ c: c, section: si }); }
      });
    });
  });
  var pageStatus = {};
  D.pages.forEach(function (p) {
    var st = [];
    p.sections.forEach(function (i) { D.findings.forEach(function (f) { if (f.section === 'psi-section-' + i) { st.push(f.status); } }); });
    pageStatus[p.id] = { status: worst(st), count: st.length };
  });

  // Synthetic "All findings" page: one master/detail place for every finding in the report.
  var FINDINGS_PAGE = 'pf-findings';
  if (D.findings.length > 0) {
    var fp = { id: FINDINGS_PAGE, title: 'All findings', subtitle: 'Every finding in this report, ordered by severity', icon: 'shieldAlert', sections: [], synthetic: true, commands: [] };
    D.pages.push(fp); pageById[fp.id] = fp;
    D.nav.push({ label: 'Insights', items: [fp.id] });
    pageStatus[fp.id] = { status: worst(D.findings.map(function (f) { return f.status; })), count: D.findings.length };
  }

  // ------------------------------------------------------------------ state
  var state = { page: null, grids: {}, pane: null, paneHistory: [], findFilter: { st: {}, cat: {}, obj: '' }, findSel: null };

  // ------------------------------------------------------------------ theme
  function storedTheme() { try { return localStorage.getItem('psi-report-theme'); } catch (e) { return null; } }
  function setTheme(t) {
    document.documentElement.setAttribute('data-theme', t);
    try { localStorage.setItem('psi-report-theme', t); } catch (e) { /* storage may be blocked for file:// */ }
    $$('[data-theme-btn]').forEach(function (b) { b.setAttribute('aria-pressed', b.getAttribute('data-theme-btn') === t ? 'true' : 'false'); });
  }
  var initialTheme = storedTheme();
  if (['Light', 'Dark', 'Auto'].indexOf(initialTheme) >= 0) { document.documentElement.setAttribute('data-theme', initialTheme); }

  // ------------------------------------------------------------------ shell
  function renderTitlebar() {
    var gen = META.generated ? META.generated.replace('T', ' ').slice(0, 16) : '';
    var theme = document.documentElement.getAttribute('data-theme') || 'Light';
    $('#pf-titlebar').innerHTML =
      '<button class="pf-btn subtle icon pf-menu-btn" data-act="rail" aria-label="Open navigation">' + ic('menu', 's20') + '</button>' +
      '<div class="pf-brand"><span class="pf-brand-mark">' + ic('chart', 's20') + '</span>' +
      '<span class="pf-brand-name"' + tipText(META.title) + '>' + esc(META.title) + '</span>' +
      (META.subtitle ? '<span class="pf-brand-sep">/</span><span class="pf-brand-sub"' + tipText(META.subtitle) + '>' + esc(META.subtitle) + '</span>' : '') + '</div>' +
      '<button class="pf-search" data-act="palette" aria-label="Search the report">' + ic('search') + '<span class="lbl">Search pages, findings, KPIs and rows</span><kbd>Ctrl K</kbd></button>' +
      '<div class="pf-tb-actions">' +
      (gen ? '<span class="pf-tb-meta"' + tipText('Generated ' + META.generated) + '>' + ic('clock', 's12') + esc(gen) + '</span>' : '') +
      ['Light', 'Dark', 'Auto'].map(function (t) {
        return '<button class="pf-btn subtle icon" data-theme-btn="' + t + '" data-act="theme" aria-pressed="' + (theme === t) + '"' + tipText(t + ' theme') + ' aria-label="' + t + ' theme">' + ic(t === 'Light' ? 'sun' : t === 'Dark' ? 'moon' : 'computer', 's20') + '</button>';
      }).join('') +
      (META.print ? '<button class="pf-btn subtle icon" data-act="print"' + tipText('Print / save as PDF (all pages)') + ' aria-label="Print">' + ic('print', 's20') + '</button>' : '') +
      '</div>';
  }
  // Long navigations (composed reports) collapse to one expanded group at a time.
  var totalNavItems = D.nav.reduce(function (n, g) { return n + g.items.length; }, 0);
  var collapsible = totalNavItems > 18 && D.nav.length > 1;
  state.railOpen = {};
  function renderRail() {
    var html = '';
    D.nav.forEach(function (g, gi) {
      var hasActive = g.items.indexOf(state.page) >= 0;
      var open = !collapsible || g.items.length === 1 || hasActive || state.railOpen[gi];
      if (collapsible && g.items.length > 1) {
        var gst = worst(g.items.map(function (id) { return (pageStatus[id] || {}).status; }));
        html += '<button class="pf-rail-group toggle" data-act="railGroup" data-gi="' + gi + '" aria-expanded="' + !!open + '">' +
          '<span class="pf-ico s12 chev">' + ICONS.chevronR + '</span><span class="txt">' + esc(g.label) + '</span>' +
          (gst && RANK[gst] <= 1 ? '<span class="pf-st-ico pf-st-' + gst + '"' + tipText('Worst finding: ' + stLabel(gst)) + '>' + ic(ST_ICON[gst], 's12') + '</span>' : '') +
          '<span class="n">' + g.items.length + '</span></button>';
      } else if (D.nav.length > 1 || g.label !== 'Report') { html += '<div class="pf-rail-group">' + esc(g.label) + '</div>'; }
      if (!open) { return; }
      g.items.forEach(function (id) {
        var p = pageById[id]; if (!p) { return; }
        var ps = pageStatus[id] || {};
        var right = p.badge ? '<span class="count">' + esc(p.badge) + '</span>'
          : (ps.count ? '<span class="count"' + tipText(plural(ps.count, 'finding') + (ps.status ? ', worst ' + stLabel(ps.status) : '')) + '>' + (ps.status && RANK[ps.status] <= 1 ? '<span class="pf-st-ico pf-st-' + ps.status + '">' + ic(ST_ICON[ps.status], 's12') + '</span> ' : '') + fmt(ps.count) + '</span>' : '');
        if (p.disabled) {
          html += '<span class="pf-rail-item" aria-disabled="true" style="opacity:.5">' + ic(role(p.icon)) + '<span class="txt">' + esc(p.title) + '</span></span>';
        } else {
          html += '<a class="pf-rail-item' + (state.page === id ? ' active' : '') + '" href="#/' + encodeURIComponent(id) + '"' + (state.page === id ? ' aria-current="page"' : '') + '>' + ic(role(p.icon)) + '<span class="txt"' + tipText(p.title) + '>' + esc(p.title) + '</span>' + right + '</a>';
        }
      });
    });
    html += renderWorkspaceRail();
    html += '<div class="pf-rail-foot">PSInsightHTML v' + esc(META.version) + '<br>Standalone report &middot; works offline</div>';
    $('#pf-rail').innerHTML = html;
  }

  // ------------------------------------------------------------------ components
  function spanStyle(n) { return ' style="--span:' + Math.max(1, Math.min(12, n || 12)) + '"'; }
  var R = {};
  R.Text = function (c) { return '<div class="pf-text ' + esc(String(c.size || 'Normal').toLowerCase()) + '">' + esc(c.text) + '</div>'; };
  R.KeyValue = function (c) {
    return '<section class="pf-card pf-kv"' + spanStyle(c.span) + '><div class="pf-card-h"><h3>' + esc(c.title) + '</h3></div><div class="pf-card-b"><dl>' +
      (c.rows || []).map(function (r) { return '<dt>' + esc(r[0]) + '</dt><dd>' + (r[1] === null ? '<span class="muted">\u2014</span>' : esc(r[1])) + '</dd>'; }).join('') + '</dl></div></section>';
  };
  R.KPI = function (c, ctx) {
    var key = ctx.register(c);
    var clickable = !!(c.filter || c.action || c.drill);
    var st = c.tone === 'Informational' ? 'Informational' : c.status;
    var hint = c.drill ? 'View details' : c.filter ? 'Filter ' + tableTitle(c.filter.table) : c.action ? (c.action.type === 'FilterTable' ? 'Filter table' : 'Go to section') : '';
    return '<div class="pf-card pf-kpi pf-st-' + esc(st) + (st === 'Unknown' || st === 'Neutral' ? ' st-none' : '') + (clickable ? ' clickable" role="button" tabindex="0" data-cmp="' + key + '"' + tipText(hint) : '"') + spanStyle(c.span) + '>' +
      '<div class="lbl">' + ic(role(c.icon, ST_ICON[c.status] || 'grid')) + '<span>' + esc(c.title) + '</span></div>' +
      '<div class="val"' + tipText(c.value === null ? '' : c.value) + '>' + (c.value === null ? '\u2014' : esc(c.value)) + '</div>' +
      (c.subtitle ? '<div class="sub">' + esc(c.subtitle) + '</div>' : '') +
      (c.trend ? '<div class="sub">' + ic('chart', 's12') + ' ' + esc(c.trend) + '</div>' : '') +
      (clickable ? '<span class="go">' + ic('arrowRight') + '</span>' : '') + '</div>';
  };
  R.Sparkline = function (c) {
    var v = c.values || [], lo = c.min !== null && c.min !== undefined ? c.min : Math.min.apply(null, v), hi = c.max !== null && c.max !== undefined ? c.max : Math.max.apply(null, v);
    if (!(hi > lo)) { hi = lo + 1; }
    var pts = v.map(function (x, i) { return (100 * i / Math.max(1, v.length - 1)).toFixed(2) + ',' + (30 - 26 * (Math.min(hi, Math.max(lo, x)) - lo) / (hi - lo)).toFixed(2); });
    var current = c.current !== null && c.current !== undefined ? c.current : fmt(v[v.length - 1]);
    return '<div class="pf-card pf-spark pf-st-' + esc(c.status) + '"' + spanStyle(c.span) + tipText((c.label || 'Values') + ': ' + v.map(fmt).join(', ') + ' (range ' + fmt(lo) + ' to ' + fmt(hi) + ')') + '>' +
      '<span class="lbl">' + esc(c.label) + '</span><svg viewBox="0 0 100 34" preserveAspectRatio="none" role="img" aria-label="' + esc((c.label || 'Trend') + ' trend') + '"><path d="M' + pts.join(' L') + '"/></svg>' +
      '<span class="val">' + esc(current) + '</span></div>';
  };
  R.EmptyState = function (c) {
    return '<div class="pf-card pf-empty"><span class="pf-ico">' + (ICONS[role(c.icon)] || '') + '</span><div class="t">' + esc(c.title) + '</div><div>' + esc(c.explanation) + '</div>' +
      (c.actionLabel && c.targetView ? '<a class="pf-btn" href="#/' + encodeURIComponent(c.targetView) + '">' + esc(c.actionLabel) + '</a>' : '') + '</div>';
  };
  R.Insight = function (c, ctx) {
    var key = ctx.register(c);
    return '<div class="pf-card pf-insight pf-st-' + esc(c.status) + (c.evidence ? ' clickable" role="button" tabindex="0" data-cmp="' + key + '"' + tipText('View evidence') : '"') + spanStyle(c.span) + '>' +
      '<div class="t">' + ic(role(c.icon, ST_ICON[c.status])) + ' ' + esc(c.title) + '</div><div class="v">' + (c.value === null ? '\u2014' : esc(c.value)) + '</div>' +
      (c.description ? '<div class="d">' + esc(c.description) + '</div>' : '') + '</div>';
  };
  R.Status = function (c) {
    return '<div class="pf-banner pf-st-' + c.status + '">' + ic(ST_ICON[c.status]) + '<div><div class="t">' + esc(stLabel(c.status)) + (c.label ? ' &middot; ' + esc(c.label) : '') + '</div>' + (c.message ? '<div class="m">' + esc(c.message) + '</div>' : '') + '</div></div>';
  };
  R.Alert = function (c) {
    return '<div class="pf-banner pf-st-' + c.status + '" role="' + (c.status === 'Critical' ? 'alert' : 'note') + '">' + ic(ST_ICON[c.status]) + '<div style="flex:1;min-width:0">' +
      '<div class="t">' + esc(c.title) + (c.timestamp ? ' <span class="muted" style="font-weight:400;font-size:12px">' + esc(c.timestamp) + '</span>' : '') + '</div>' +
      '<div class="m">' + esc(c.message) + '</div>' +
      (c.action ? '<div class="a">' + ic('lightbulb') + '<span><b>Suggested action:</b> ' + esc(c.action) + '</span></div>' : '') +
      (c.details ? '<details style="margin-top:6px;font-size:12px"><summary>Details</summary><pre class="pf-mono" style="white-space:pre-wrap;margin:6px 0 0">' + esc(c.details) + '</pre></details>' : '') +
      '</div></div>';
  };
  R.Recommendation = function (c) {
    return '<div class="pf-card pf-rec pf-st-' + c.status + '"><h4>' + ic('lightbulb') + esc(c.title) + ' ' + stChip(c.status) + '</h4><p>' + esc(c.description) + '</p>' +
      (c.action ? '<div class="act">' + ic('arrowRight') + '<span>' + esc(c.action) + '</span></div>' : '') + '</div>';
  };
  R.Finding = function (c, ctx) {
    var key = ctx.register(c);
    return '<article class="pf-card pf-finding pf-st-' + c.status + '" id="' + esc(c.id) + '" data-affected="' + esc(c.affected) + '" data-status="' + c.status + '">' + ic(ST_ICON[c.status]) +
      '<div class="t">' + esc(c.title) + '</div><div>' + stChip(c.status) + '</div>' +
      '<div class="meta">' + [c.category ? '<span>' + ic('tag', 's12') + ' ' + esc(c.category) + '</span>' : '', c.affected ? '<span>' + ic('server', 's12') + ' ' + esc(c.affected) + '</span>' : '', c.ruleId ? '<span>Rule ' + esc(c.ruleId) + '</span>' : '', c.source ? '<span>Source: ' + esc(c.source) + '</span>' : ''].filter(Boolean).join('') + '</div>' +
      '<div class="body">' + (c.description ? '<p>' + esc(c.description) + '</p>' : '') +
      ((c.impact || c.recommendation) ? '<div class="pf-callouts">' +
        (c.impact ? '<div class="pf-callout risk"><h5>' + ic('warning') + 'Impact</h5><p>' + esc(c.impact) + '</p></div>' : '') +
        (c.recommendation ? '<div class="pf-callout fix"><h5>' + ic('healthy') + 'Recommendation</h5><p>' + esc(c.recommendation) + '</p></div>' : '') + '</div>' : '') + '</div>' +
      (c.evidence ? '<div class="acts"><button class="pf-btn sm" data-cmp="' + key + '">' + ic('view') + 'View evidence (' + fmt(evidenceRows(c.evidence).length) + ')</button></div>' : '') +
      '</article>';
  };
  R.Unsupported = function (c) {
    return '<div class="pf-card pf-empty"><span class="pf-ico">' + (ICONS.info || '') + '</span><div class="t">' + esc(c.title) + '</div><div>The ' + esc(c.type) + ' component is not available in the Fluent renderer yet. Export with <code>-Renderer Classic</code> to view it.</div></div>';
  };
  R.Table = function (c, ctx) {
    var key = ctx.register(c);
    return '<section class="pf-card pf-grid-host" id="' + esc(c.id) + '"' + spanStyle(c.span) + ' data-grid="' + key + '"></section>';
  };
  R.Chart = function (c, ctx) {
    var key = ctx.register(c);
    var body = chartBody(c, key);
    var table = '<table class="pf-dt"><thead><tr><th>Category</th>' + c.series.map(function (s) { return '<th class="num">' + esc(s.name) + '</th>'; }).join('') + '</tr></thead><tbody>' +
      c.categories.map(function (cat, i) { return '<tr><td>' + esc(cat) + '</td>' + c.series.map(function (s) { return '<td class="num">' + fmt(s.values[i]) + '</td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table>';
    return '<section class="pf-card pf-chart" data-cmp="' + key + '"><div class="pf-card-h"><h3>' + esc(c.title) + '</h3><span class="grow"></span>' +
      (c.filter ? '<span class="hint">' + ic('filter', 's12') + ' Select to filter</span>' : '') +
      '<button class="pf-btn subtle sm view-toggle" data-act="chartTable">' + ic('list', 's12') + 'Table</button></div>' +
      '<div class="pf-card-b chart-v">' + body + (c.nullCount ? '<div class="pf-note" style="margin-top:8px">' + ic('info', 's12') + '<span>' + plural(c.nullCount, 'null value') + ' omitted</span></div>' : '') + '</div>' +
      '<div class="table-v">' + table + '</div></section>';
  };

  // ------------------------------------------------------------------ charts
  var SERIES = ['--pf-s1', '--pf-s2', '--pf-s3', '--pf-s4', '--pf-s5', '--pf-s6', '--pf-s7', '--pf-s8'];
  function niceMax(v) {
    if (v <= 4) { return 4; }
    var p = Math.pow(10, Math.floor(Math.log10(v))), n = v / p;
    var steps = [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
    for (var i = 0; i < steps.length; i++) { if (n <= steps[i]) { return steps[i] * p; } }
    return 10 * p;
  }
  function compact(n) { var a = Math.abs(n); return a >= 1e6 ? (n / 1e6).toFixed(1).replace(/\.0$/, '') + 'M' : a >= 1e4 ? (n / 1e3).toFixed(1).replace(/\.0$/, '') + 'K' : fmt(Math.round(n * 100) / 100); }
  function pointColor(c, i, si) {
    // A category that is itself a status keeps its reserved status colour; otherwise series order.
    var st = c.status && c.status[i];
    if (st) { return 'var(--pf-' + st.toLowerCase() + '-mark)'; }
    return 'var(' + SERIES[(si || 0) % SERIES.length] + ')';
  }
  function chartAttrs(c, key, i, tip, base) {
    var fv = c.filter && c.filter.values ? c.filter.values[i] : null;
    var on = fv !== null && fv !== undefined;
    var cls = [base, on ? 'clickable' : ''].filter(Boolean).join(' ');
    return (cls ? ' class="' + cls + '"' : '') + (on ? ' role="button" tabindex="0" data-chart="' + key + '" data-ci="' + i + '"' : '') + tipAttr(tip);
  }
  function chartBody(c, key) {
    var cats = c.categories, series = c.series;
    var total = 0; series.forEach(function (s) { s.values.forEach(function (v) { if (v) { total += v; } }); });
    if (!cats.length || (!total && c.chartType !== 'Line')) { return '<div class="pf-empty">' + ic('chart') + '<div>' + esc(c.empty) + '</div></div>'; }
    var type = c.chartType;
    var legend = series.length > 1 ? '<div class="pf-legend">' + series.map(function (s, si) { return '<span style="--c:var(' + SERIES[si % 8] + ')">' + esc(s.name) + '</span>'; }).join('') + '</div>' : '';
    if (type === 'Doughnut' || type === 'Pie') {
      var vals = cats.map(function (cat, i) { var t = 0; series.forEach(function (s) { t += s.values[i] || 0; }); return Math.max(0, t); });
      var order = vals.map(function (v, i) { return i; });
      var sum = vals.reduce(function (a, b) { return a + b; }, 0) || 1;
      var R0 = 70, Ri = type === 'Doughnut' ? 41 : 0, a0 = -Math.PI / 2, paths = '';
      order.forEach(function (i) {
        if (!vals[i]) { return; }
        var a1 = a0 + 2 * Math.PI * vals[i] / sum, large = a1 - a0 > Math.PI ? 1 : 0;
        var p = function (r, a) { return (75 + r * Math.cos(a)).toFixed(2) + ' ' + (75 + r * Math.sin(a)).toFixed(2); };
        var d = vals[i] >= sum ? (Ri ? 'M' + p(R0, 0) + ' A70 70 0 1 1 ' + p(R0, Math.PI) + ' A70 70 0 1 1 ' + p(R0, 2 * Math.PI) + ' M' + p(Ri, 0) + ' A41 41 0 1 0 ' + p(Ri, Math.PI) + ' A41 41 0 1 0 ' + p(Ri, 2 * Math.PI) + 'Z' : 'M75 5 A70 70 0 1 1 74.99 5Z')
          : 'M' + p(R0, a0) + ' A' + R0 + ' ' + R0 + ' 0 ' + large + ' 1 ' + p(R0, a1) + (Ri ? ' L' + p(Ri, a1) + ' A' + Ri + ' ' + Ri + ' 0 ' + large + ' 0 ' + p(Ri, a0) + 'Z' : ' L75 75Z');
        paths += '<path d="' + d + '" fill="' + pointColor(c, i, i) + '" stroke="var(--pf-surface)" stroke-width="2"' + chartAttrs(c, key, i, '<b>' + esc(cats[i]) + '</b><br>' + fmt(vals[i]) + ' (' + (100 * vals[i] / sum).toFixed(1) + '%)') + '/>';
        a0 = a1;
      });
      var center = Ri ? '<text class="total" x="75" y="78" text-anchor="middle">' + compact(sum) + '</text><text class="total-l" x="75" y="94" text-anchor="middle">total</text>' : '';
      return '<div class="pf-donut"><svg viewBox="0 0 150 150" role="img" aria-label="' + esc(c.title) + '">' + paths + center + '</svg><div class="pf-legend">' +
        cats.map(function (cat, i) { return '<span style="--c:' + pointColor(c, i, i) + '"' + chartAttrs(c, key, i, esc(cat)) + '>' + esc(cat) + ' <b>' + fmt(vals[i]) + (c.labels ? ' &middot; ' + (100 * vals[i] / sum).toFixed(1) + '%' : '') + '</b></span>'; }).join('') + '</div></div>';
    }
    if (type === 'Line') {
      var all = []; series.forEach(function (s) { s.values.forEach(function (v) { if (v !== null) { all.push(v); } }); });
      var mx = niceMax(Math.max.apply(null, all.concat([0]))), mn = Math.min(0, Math.min.apply(null, all.concat([0])));
      var W = 600, H = 200, L = 40, B = 24, x = function (i) { return L + (W - L - 10) * (cats.length === 1 ? 0.5 : i / (cats.length - 1)); }, y = function (v) { return 8 + (H - B - 8) * (1 - (v - mn) / (mx - mn || 1)); };
      var grid = [0, 0.25, 0.5, 0.75, 1].map(function (f) { var v = mn + (mx - mn) * f; return '<line class="gl" x1="' + L + '" x2="' + W + '" y1="' + y(v) + '" y2="' + y(v) + '"/><text x="' + (L - 6) + '" y="' + (y(v) + 4) + '" text-anchor="end">' + compact(v) + '</text>'; }).join('');
      var step = Math.ceil(cats.length / 8);
      var xl = cats.map(function (cat, i) { return i % step ? '' : '<text x="' + x(i) + '" y="' + (H - 6) + '" text-anchor="middle">' + esc(String(cat).slice(0, 14)) + '</text>'; }).join('');
      var lines = series.map(function (s, si) {
        var pts = s.values.map(function (v, i) { return v === null ? null : x(i).toFixed(1) + ',' + y(v).toFixed(1); }).filter(Boolean);
        var color = 'var(' + SERIES[si % 8] + ')';
        return '<polyline class="ln" points="' + pts.join(' ') + '" stroke="' + color + '"/>' + s.values.map(function (v, i) {
          return v === null ? '' : '<circle cx="' + x(i).toFixed(1) + '" cy="' + y(v).toFixed(1) + '" r="4" fill="' + color + '"' + chartAttrs(c, key, i, '<b>' + esc(cats[i]) + '</b><br>' + esc(s.name) + ': ' + fmt(v), 'pt') + '/>';
        }).join('');
      }).join('');
      return '<div class="pf-line"><svg viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="' + esc(c.title) + '">' + grid + xl + lines + '</svg></div>' + legend;
    }
    // Bar: columns for a few short categories, horizontal bars otherwise
    var maxLabel = Math.max.apply(null, cats.map(function (s) { return String(s).length; }));
    var single = series.length === 1;
    if (single && cats.length <= 10 && maxLabel <= 14) {
      var mxv = niceMax(Math.max.apply(null, series[0].values.map(function (v) { return v || 0; }).concat([0])));
      return '<div class="pf-cols">' + [0, 0.5, 1].map(function (f) { return '<div class="gl" style="bottom:' + (f * 100) + '%"><span>' + compact(mxv * f) + '</span></div>'; }).join('') +
        cats.map(function (cat, i) {
          var v = series[0].values[i] || 0;
          return '<div' + chartAttrs(c, key, i, '<b>' + esc(cat) + '</b><br>' + fmt(v), 'col') + '><b>' + compact(v) + '</b><i style="height:' + (100 * v / mxv).toFixed(2) + '%;--c:' + pointColor(c, i, 0) + '"></i></div>';
        }).join('') + '</div><div class="pf-cols-x">' + cats.map(function (cat) { return '<span' + tipText(cat) + '>' + esc(cat) + '</span>'; }).join('') + '</div>';
    }
    var mxh = Math.max.apply(null, [].concat.apply([], series.map(function (s) { return s.values.map(function (v) { return v || 0; }); })).concat([1]));
    return '<div class="pf-hbar">' + cats.map(function (cat, i) {
      return series.map(function (s, si) {
        var v = s.values[i] || 0, col = single ? pointColor(c, i, 0) : 'var(' + SERIES[si % 8] + ')';
        var tip = '<b>' + esc(cat) + '</b><br>' + (single ? '' : esc(s.name) + ': ') + fmt(v);
        return '<span' + chartAttrs(c, key, i, tip, 'lbl') + '>' + (si === 0 ? esc(cat) : '') + '</span><span' + chartAttrs(c, key, i, tip, 'track') + '><i style="width:' + (100 * v / mxh).toFixed(2) + '%;--c:' + col + '"></i></span><span class="v">' + fmt(v) + '</span>';
      }).join('');
    }).join('') + '</div>' + legend;
  }

  // ------------------------------------------------------------------ evidence (client-side operator set, rendered text)
  function equalValue(a, b) {
    var sa = normStatus(a), sb = normStatus(b);
    if (sa && sb) { return sa === sb; }
    return String(a === null || a === undefined ? '' : a).toLocaleLowerCase() === String(b === null || b === undefined ? 'null' : b).toLocaleLowerCase();
  }
  function testCondition(text, cond) {
    var t = text === null || text === undefined ? '' : String(text);
    var op = cond.operator || 'Equals';
    if (op === 'NotEquals') { return !equalValue(text, cond.value); }
    if (op === 'In') { return (cond.values || []).some(function (v) { return equalValue(text, v); }); }
    if (op === 'IsEmpty') { return t.trim() === ''; }
    if (op === 'IsNotEmpty') { return t.trim() !== ''; }
    if (op === 'GreaterThanOrEqual' || op === 'LessThan') {
      var n = Number(t), e = Number(cond.value);
      if (t === '' || !isFinite(n) || !isFinite(e)) { return false; }
      return op === 'LessThan' ? n < e : n >= e;
    }
    if (op === 'Contains') { return t.toLocaleLowerCase().indexOf(String(cond.value).toLocaleLowerCase()) >= 0; }
    return equalValue(text, cond.value);
  }
  function colIndex(tbl, name) {
    var i = tbl.columns.indexOf(name); if (i >= 0) { return i; }
    var l = String(name).toLowerCase();
    for (var k = 0; k < tbl.columns.length; k++) { if (tbl.columns[k].toLowerCase() === l) { return k; } }
    return -1;
  }
  function evidenceRows(ev) {
    var t = tables[String(ev.table).toLowerCase()]; if (!t) { return []; }
    var tbl = t.comp;
    if (ev._rows) { return ev._rows; }
    var conds = (ev.conditions || []).map(function (c) { return { c: c, i: colIndex(tbl, c.property) }; });
    var out = [];
    for (var r = 0; r < tbl.rows.length; r++) {
      var ok = true;
      for (var k = 0; k < conds.length; k++) { var ci = conds[k].i; if (!testCondition(ci >= 0 ? tbl.rows[r][ci] : null, conds[k].c)) { ok = false; break; } }
      if (ok) { out.push(r); }
    }
    ev._rows = out;
    return out;
  }
  function condText(c) {
    var v = c.operator === 'In' ? (c.values || []).join(', ') : c.operator === 'IsEmpty' || c.operator === 'IsNotEmpty' ? '' : c.value;
    var op = { Equals: '=', NotEquals: '\u2260', GreaterThanOrEqual: '\u2265', LessThan: '<', In: 'in', Contains: 'contains', IsEmpty: 'is empty', IsNotEmpty: 'is not empty' }[c.operator] || c.operator;
    return c.property + ' ' + op + (v === '' || v === undefined ? '' : ' ' + v);
  }

  // ------------------------------------------------------------------ data grid
  function tableTitle(id) { var t = tables[String(id || '').toLowerCase()]; return t ? t.comp.title : 'table'; }
  function gridState(tbl) {
    var st = state.grids[tbl.id];
    if (!st) { st = state.grids[tbl.id] = { q: '', filters: {}, ext: [], sort: null, page: 1, size: tbl.paging ? tbl.pageSize : 100000 }; }
    return st;
  }
  function cellHtml(tbl, r, ci) {
    var v = tbl.rows[r][ci];
    if (v === null || v === undefined) { return '<span class="null">' + esc(tbl.nullText) + '</span>'; }
    var cs = tbl.cellStatus[r] && tbl.cellStatus[r][ci];
    if (cs) { return '<span>' + '<span class="pf-st-ico pf-st-' + cs + '">' + ic(ST_ICON[cs], 's12') + '</span>' + esc(v) + '</span>'; }
    var s = normStatus(v);
    if (s && v.length < 15) { return stChip(s, v); }
    return esc(v);
  }
  function sortKey(v) {
    if (v === null || v === undefined) { return null; }
    var t = String(v).replace(/[\s,%$\u00a3\u20ac]/g, '');
    var n = Number(t);
    return t !== '' && isFinite(n) ? n : String(v).toLowerCase();
  }
  function filteredRows(tbl, st, base) {
    var rows = base || null, q = st.q ? st.q.toLowerCase().split(/\s+/).filter(Boolean) : [];
    var filterIdx = Object.keys(st.filters).filter(function (p) { return st.filters[p] && st.filters[p].length; }).map(function (p) { return { i: colIndex(tbl, p), v: st.filters[p].map(function (x) { return String(x).toLowerCase(); }) }; });
    var ext = st.ext.map(function (c) { return { c: c, i: colIndex(tbl, c.property) }; });
    var out = [];
    var n = rows ? rows.length : tbl.rows.length;
    for (var k = 0; k < n; k++) {
      var r = rows ? rows[k] : k, row = tbl.rows[r], ok = true, j;
      for (j = 0; j < filterIdx.length && ok; j++) { var cv = filterIdx[j].i >= 0 ? row[filterIdx[j].i] : null; ok = cv !== null && filterIdx[j].v.indexOf(String(cv).toLowerCase()) >= 0; }
      for (j = 0; j < ext.length && ok; j++) { ok = testCondition(ext[j].i >= 0 ? row[ext[j].i] : null, ext[j].c); }
      if (ok && q.length) { var text = row.join(' ').toLowerCase(); for (j = 0; j < q.length && ok; j++) { ok = text.indexOf(q[j]) >= 0; } }
      if (ok) { out.push(r); }
    }
    if (st.sort) {
      var ci = st.sort.i, dir = st.sort.dir;
      out = out.map(function (r) { return [sortKey(tbl.rows[r][ci]), r]; }).sort(function (a, b) {
        if (a[0] === null && b[0] === null) { return a[1] - b[1]; }
        if (a[0] === null) { return 1; } if (b[0] === null) { return -1; }
        if (typeof a[0] === 'number' && typeof b[0] === 'number') { return (a[0] - b[0]) * dir || a[1] - b[1]; }
        return String(a[0]).localeCompare(String(b[0]), undefined, { numeric: true, sensitivity: 'base' }) * dir || a[1] - b[1];
      }).map(function (p) { return p[1]; });
    }
    return out;
  }
  // opts: { title, columns (names), base (row index subset), compact, onRow, maxHeight }
  function mountGrid(host, tbl, opts) {
    opts = opts || {};
    var st = opts.state || gridState(tbl);
    var cols = (opts.columns && opts.columns.length ? opts.columns : tbl.columns).map(function (n) { return colIndex(tbl, n); }).filter(function (i) { return i >= 0; });
    // Prose-like columns (long text with spaces) wrap; identifiers stay on one line with a tooltip.
    if (!tbl._wrap) {
      tbl._wrap = tbl.columns.map(function (n, ci) {
        var total = 0, spaced = 0, seen = 0;
        for (var r = 0; r < tbl.rows.length && seen < 200; r++) { var v = tbl.rows[r][ci]; if (v === null) { continue; } seen++; total += v.length; if (v.indexOf(' ') > 0) { spaced++; } }
        return seen > 0 && total / seen > 48 && spaced / seen > 0.5;
      });
    }
    var filters = opts.noFilters ? [] : tbl.filters.filter(function (f) { return colIndex(tbl, f.property) >= 0; });
    var formats = tbl.export.enabled ? tbl.export.formats : [];
    var current = [];
    function build() {
    host.innerHTML =
      (opts.noHeader ? '' : '<div class="pf-card-h"><h3>' + esc(opts.title || tbl.title) + '</h3></div>') +
      '<div class="pf-toolbar">' +
      (tbl.search ? '<label class="pf-input">' + ic('search') + '<input type="search" data-g="q" placeholder="Search ' + esc(tbl.title) + '" value="' + esc(st.q) + '" aria-label="Search rows"></label>' : '') +
      filters.map(function (f) {
        var sel = st.filters[f.property] || [];
        if (f.type === 'MultiSelect' || f.values.length > 12) {
          return '<span class="pf-fgroup"><select class="pf-select" data-g="msel" data-p="' + esc(f.property) + '" aria-label="' + esc(f.label) + '"><option value="">' + esc(f.label) + (sel.length ? ' (' + sel.length + ')' : ': all') + '</option>' +
            f.values.map(function (v) { return '<option value="' + esc(v) + '">' + (sel.indexOf(v) >= 0 ? '\u2713 ' : '') + esc(v) + '</option>'; }).join('') + '</select></span>';
        }
        return '<span class="pf-fgroup"><span class="gl">' + esc(f.label) + '</span>' + f.values.map(function (v) {
          return '<button class="pf-fchip' + (sel.indexOf(v) >= 0 ? ' on' : '') + '" data-g="chip" data-p="' + esc(f.property) + '" data-v="' + esc(v) + '">' + (normStatus(v) ? '<span class="pf-st-ico pf-st-' + normStatus(v) + '">' + ic(ST_ICON[normStatus(v)], 's12') + '</span>' : '') + esc(v) + '</button>';
        }).join('') + '</span>';
      }).join('') +
      '<span class="grow"></span><span class="count" data-g="count"></span>' +
      (formats.length ? '<details class="pf-export-menu"><summary class="pf-btn sm" aria-label="Export filtered rows">' + ic('download', 's12') + 'Export' + ic('chevronD', 's12') + '</summary><div class="pf-export-options">' + formats.map(function (f) { return '<button type="button" class="pf-btn sm" data-g="export" data-f="' + esc(f) + '"' + tipText('Export the filtered rows (all pages)') + '>' + ic(f === 'Print' ? 'print' : 'download', 's12') + esc(f === 'Csv' ? 'CSV' : f === 'Xlsx' ? 'Excel' : 'Print / PDF') + '</button>'; }).join('') + '</div></details>' : '') +
      '</div><div class="pf-active-filters" data-g="tags"></div>' +
      '<div class="pf-table-wrap"' + (opts.maxHeight ? ' style="max-height:' + opts.maxHeight + '"' : '') + '><table class="pf-dt"><thead><tr>' +
      cols.map(function (ci) { return '<th class="' + (tbl.sort ? 'sortable ' : '') + (tbl.numeric[ci] ? 'num' : '') + '" data-ci="' + ci + '" scope="col">' + esc(tbl.labels[tbl.columns[ci]] || tbl.columns[ci]) + '<span class="ind"></span></th>'; }).join('') +
      '</tr></thead><tbody></tbody></table></div><div class="pf-pager" data-g="pager"></div>';
    }
    function paint() {
      current = filteredRows(tbl, st, opts.base);
      var pages = Math.max(1, Math.ceil(current.length / st.size));
      if (st.page > pages) { st.page = pages; }
      var start = (st.page - 1) * st.size, shown = current.slice(start, start + st.size);
      $('tbody', host).innerHTML = shown.length ? shown.map(function (r) {
        var rs = tbl.rowStatus[r];
        return '<tr class="clickable' + (rs ? ' row-st pf-st-' + rs : '') + '" data-r="' + r + '">' + cols.map(function (ci) {
          var cs = tbl.cellStatus[r] && tbl.cellStatus[r][ci], v = tbl.rows[r][ci];
          var long = v !== null && !tbl._wrap[ci] && v.length > 36;
          return '<td class="' + (tbl.numeric[ci] ? 'num ' : '') + (tbl._wrap[ci] ? 'wrap ' : '') + (cs ? 'cell-st pf-st-' + cs : '') + '"' + (long ? tipText(v) : '') + '>' + cellHtml(tbl, r, ci) + '</td>';
        }).join('') + '</tr>';
      }).join('') : '<tr><td colspan="' + cols.length + '"><div class="pf-empty">' + ic('search') + '<div>' + esc(current.length === 0 && (opts.base ? opts.base.length : tbl.rows.length) === 0 ? tbl.empty : 'No records match your filters.') + '</div></div></td></tr>';
      var total = opts.base ? opts.base.length : tbl.rows.length;
      var countText = current.length === total ? plural(total, 'row') : fmt(current.length) + ' of ' + plural(total, 'row');
      $$('[data-g="count"]', host).forEach(function (e) { e.textContent = countText; });
      var pager = $('[data-g="pager"]', host);
      if (tbl.paging && current.length > st.size) {
        pager.innerHTML = '<span>Showing ' + fmt(start + 1) + '\u2013' + fmt(Math.min(current.length, start + st.size)) + ' of ' + fmt(current.length) + '</span><span class="pg">' +
          '<select class="pf-select" data-g="size" aria-label="Rows per page">' + [10, 25, 50, 100, 250].concat(st.size > 250 ? [] : []).map(function (n) { return '<option value="' + n + '"' + (n === st.size ? ' selected' : '') + '>' + n + ' per page</option>'; }).join('') + (st.size !== 10 && st.size !== 25 && st.size !== 50 && st.size !== 100 && st.size !== 250 ? '<option selected value="' + st.size + '">' + st.size + ' per page</option>' : '') + '</select>' +
          '<button class="pf-btn sm icon" data-g="prev"' + (st.page <= 1 ? ' disabled' : '') + ' aria-label="Previous page"><span class="pf-ico s12" style="transform:rotate(180deg)">' + ICONS.chevronR + '</span></button>' +
          '<span>Page ' + st.page + ' of ' + pages + '</span>' +
          '<button class="pf-btn sm icon" data-g="next"' + (st.page >= pages ? ' disabled' : '') + ' aria-label="Next page">' + ic('chevronR', 's12') + '</button></span>';
        pager.style.display = '';
      } else { pager.innerHTML = ''; pager.style.display = 'none'; }
      $$('th', host).forEach(function (th) {
        var on = st.sort && st.sort.i === +th.getAttribute('data-ci');
        $('.ind', th).innerHTML = on ? ic(st.sort.dir > 0 ? 'chevronU' : 'chevronD', 's12') : '';
        th.setAttribute('aria-sort', on ? (st.sort.dir > 0 ? 'ascending' : 'descending') : 'none');
      });
      var tags = [];
      Object.keys(st.filters).forEach(function (p) { (st.filters[p] || []).forEach(function (v) { tags.push('<span class="pf-tag">' + esc((tbl.labels[p] || p) + ': ' + v) + '<button data-g="untag" data-p="' + esc(p) + '" data-v="' + esc(v) + '" aria-label="Remove filter">' + ic('close', 's12') + '</button></span>'); }); });
      st.ext.forEach(function (c, i) { tags.push('<span class="pf-tag">' + ic('filter', 's12') + esc(condText(c)) + '<button data-g="unext" data-i="' + i + '" aria-label="Remove filter">' + ic('close', 's12') + '</button></span>'); });
      if (tags.length > 1) { tags.push('<button class="pf-btn subtle sm" data-g="clear">Clear all</button>'); }
      $('[data-g="tags"]', host).innerHTML = tags.join('');
    }
    var deb;
    host.addEventListener('input', function (e) {
      if (e.target.getAttribute('data-g') === 'q') { clearTimeout(deb); var v = e.target.value; deb = setTimeout(function () { st.q = v; st.page = 1; paint(); }, 120); }
    });
    host.addEventListener('change', function (e) {
      var g = e.target.getAttribute('data-g');
      if (g === 'size') { st.size = +e.target.value; st.page = 1; paint(); }
      if (g === 'msel') {
        var p = e.target.getAttribute('data-p'), v = e.target.value; if (!v) { return; }
        var list = st.filters[p] = st.filters[p] || []; var at = list.indexOf(v);
        if (at >= 0) { list.splice(at, 1); } else { list.push(v); }
        st.page = 1; build(); paint();
      }
    });
    host.addEventListener('click', function (e) {
      var th = e.target.closest('th.sortable');
      if (th && host.contains(th)) { var ci = +th.getAttribute('data-ci'); st.sort = st.sort && st.sort.i === ci ? { i: ci, dir: -st.sort.dir } : { i: ci, dir: tbl.numeric[ci] ? -1 : 1 }; paint(); return; }
      var b = e.target.closest('[data-g]'); var row = e.target.closest('tr[data-r]');
      if (b && host.contains(b)) {
        var g = b.getAttribute('data-g');
        if (g === 'chip') { var p = b.getAttribute('data-p'), v = b.getAttribute('data-v'), list = st.filters[p] = st.filters[p] || [], at = list.indexOf(v); if (at >= 0) { list.splice(at, 1); } else { list.push(v); } b.classList.toggle('on'); st.page = 1; paint(); return; }
        if (g === 'untag') { var pp = b.getAttribute('data-p'), vv = b.getAttribute('data-v'); st.filters[pp] = (st.filters[pp] || []).filter(function (x) { return x !== vv; }); st.page = 1; build(); paint(); return; }
        if (g === 'unext') { st.ext.splice(+b.getAttribute('data-i'), 1); st.page = 1; paint(); return; }
        if (g === 'clear') { st.filters = {}; st.ext = []; st.q = ''; st.page = 1; build(); paint(); return; }
        if (g === 'prev') { st.page--; paint(); return; }
        if (g === 'next') { st.page++; paint(); return; }
        if (g === 'export') { var menu = b.closest('.pf-export-menu'); if (menu) { menu.open = false; } exportRows(tbl, current, b.getAttribute('data-f'), opts); return; }
      }
      if (row && host.contains(row) && !e.target.closest('a,button')) { (opts.onRow || openRow)(tbl, +row.getAttribute('data-r')); }
    });
    build();
    paint();
    return { repaint: paint, state: st };
  }
  function exportRows(tbl, rows, format, opts) {
    var names = (opts && opts.exportColumns && opts.exportColumns.length ? opts.exportColumns : tbl.export.columns).filter(function (n) { return colIndex(tbl, n) >= 0; });
    var idx = names.map(function (n) { return colIndex(tbl, n); });
    var labels = {}; names.forEach(function (n, k) { labels[n] = tbl.labels[tbl.columns[idx[k]]] || n; });
    if (format === 'Print') { printTable(tbl, rows, names, idx, labels, opts); return; }
    if (!rows.length) { toast('No matching rows to export'); return; }
    var records = rows.map(function (r) { var o = {}; names.forEach(function (n, k) { var v = tbl.rows[r][idx[k]]; o[n] = v === null ? '' : v; }); return o; });
    var ctx = (opts && opts.title) || tbl.title;
    var X = window.PSIExport;
    var name = X.fileName(META.title, ctx, format === 'Csv' ? 'csv' : 'xlsx', tbl.export.fileName);
    var blob = format === 'Csv' ? new Blob([X.toCsv(records, names, labels)], { type: 'text/csv;charset=utf-8' })
      : new Blob([X.toXlsx(records, names, labels, tbl.export.worksheet || ctx)], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
    var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 60000);
    toast('Exported ' + plural(records.length, 'row') + ' to ' + name);
  }
  function printTable(tbl, rows, names, idx, labels, opts) {
    var w = window.open('', '_blank');
    if (!w) { toast('Allow pop-ups to print this table'); return; }
    var html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>' + esc((opts && opts.title) || tbl.title) + '</title><style>body{font:12px "Segoe UI",sans-serif;margin:24px}h1{font-size:18px}table{border-collapse:collapse;width:100%}th,td{border-bottom:1px solid #ddd;padding:4px 8px;text-align:left}th{background:#f5f5f5}</style></head><body>' +
      '<h1>' + esc(META.title) + ' &middot; ' + esc((opts && opts.title) || tbl.title) + '</h1><p>' + plural(rows.length, 'row') + ' &middot; generated ' + esc(META.generated) + '</p><table><thead><tr>' +
      names.map(function (n) { return '<th>' + esc(labels[n]) + '</th>'; }).join('') + '</tr></thead><tbody>' +
      rows.map(function (r) { return '<tr>' + idx.map(function (ci) { var v = tbl.rows[r][ci]; return '<td>' + esc(v === null ? tbl.nullText : v) + '</td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table></body></html>';
    w.document.open(); w.document.write(html); w.document.close(); w.focus(); setTimeout(function () { w.print(); }, 250);
  }

  // ------------------------------------------------------------------ detail pane
  function openPane(html, wide) {
    var pane = $('#pf-pane');
    pane.innerHTML = html;
    pane.classList.toggle('wide', !!wide);
    app.classList.add('pane-open');
    pane.setAttribute('aria-hidden', 'false');
    var first = $('[data-act="paneClose"]', pane); if (first) { first.focus({ preventScroll: true }); }
  }
  function closePane() { app.classList.remove('pane-open'); $('#pf-pane').setAttribute('aria-hidden', 'true'); state.pane = null; $$('tr.sel').forEach(function (t) { t.classList.remove('sel'); }); }
  function paneHead(title, sub, st, iconName, chips) {
    return '<div class="pf-pane-h"><span class="big' + (st ? ' pf-st-' + st : '') + '">' + ic(iconName || 'document') + '</span><div class="ttl"><h2>' + esc(title) + '</h2>' + (sub ? '<div class="s">' + esc(sub) + '</div>' : '') +
      (chips ? '<div class="pf-chips">' + chips + '</div>' : '') + '</div><div class="pf-pane-nav"><button class="pf-btn subtle icon" data-act="paneClose"' + tipText('Close (Esc)') + ' aria-label="Close">' + ic('close') + '</button></div></div>';
  }
  function openRow(tbl, r) {
    var titleCol = 0;
    var title = tbl.rows[r][titleCol] === null ? '(no value)' : tbl.rows[r][titleCol];
    var rs = tbl.rowStatus[r];
    var related = D.findings.filter(function (f) { var c = findingById[f.id]; return c && c.evidence && String(c.evidence.table).toLowerCase() === tbl.id.toLowerCase() && evidenceRows(c.evidence).indexOf(r) >= 0; });
    var props = tbl.columns.map(function (n, ci) {
      var v = tbl.rows[r][ci];
      return '<dt>' + esc(tbl.labels[n] || n) + '</dt><dd><span class="v">' + cellHtml(tbl, r, ci) + '</span>' + (v !== null ? '<button class="pf-btn subtle sm icon pf-copy" data-copy="' + esc(v) + '"' + tipText('Copy') + ' aria-label="Copy value">' + ic('copy', 's12') + '</button>' : '') + '</dd>';
    }).join('');
    openPane(paneHead(title, tbl.title + ' \u00b7 row ' + (r + 1) + ' of ' + tbl.rows.length, rs, 'list', rs ? stChip(rs) : '') +
      '<div class="pf-tabs" role="tablist"><button class="pf-tab on" data-tab="p">Properties</button>' + (related.length ? '<button class="pf-tab" data-tab="f">Findings <span class="n">' + related.length + '</span></button>' : '') + '</div>' +
      '<div class="pf-pane-body"><div data-tabp="p"><dl class="pf-props">' + props + '</dl></div>' +
      (related.length ? '<div data-tabp="f" hidden>' + related.map(function (f) { return '<div class="pf-block"><h4>' + stChip(f.status) + ' <a href="#/' + FINDINGS_PAGE + '/' + encodeURIComponent(f.id) + '">' + esc(f.title) + '</a></h4>' + (f.category ? '<p class="muted">' + esc(f.category) + '</p>' : '') + '</div>'; }).join('') + '</div>' : '') + '</div>');
    $$('tr[data-r]').forEach(function (t) { t.classList.toggle('sel', +t.getAttribute('data-r') === r && t.closest('[data-grid]') && t.closest('[data-grid]').id === tbl.id); });
  }
  function openEvidence(source) {
    var ev = source.evidence; if (!ev) { return; }
    var t = tables[String(ev.table).toLowerCase()];
    if (!t) { toast('Evidence table not found'); return; }
    var tbl = t.comp, rows = evidenceRows(ev);
    var cols = ev.columns && ev.columns.length ? ev.columns : (ev.visible ? tbl.columns : tbl.columns);
    var st = source.status || 'Informational';
    openPane(paneHead(source.title, 'Evidence from ' + tbl.title + ' \u00b7 ' + plural(rows.length, 'matching row'), st, 'view',
      stChip(st) + (ev.conditions || []).map(function (c) { return '<span class="pf-chip brand">' + ic('filter') + esc(condText(c)) + '</span>'; }).join('')) +
      '<div class="pf-pane-body">' + (source.description ? '<div class="pf-block"><p>' + esc(source.description) + '</p></div>' : '') +
      '<div class="pf-block" style="display:flex;gap:8px;flex-wrap:wrap"><button class="pf-btn primary" data-act="evApply">' + ic('filter') + 'Open in ' + esc(tbl.title) + '</button><span class="pf-note">' + ic('info', 's12') + '<span>Evidence uses only this finding\'s conditions; table filters you set elsewhere are not applied.</span></span></div>' +
      '<div data-evgrid></div></div>', true);
    var host = $('[data-evgrid]', $('#pf-pane'));
    mountGrid(host, tbl, { title: 'Evidence', columns: cols, exportColumns: ev['export'] && ev['export'].length ? ev['export'] : cols, base: rows, noFilters: true, state: { q: '', filters: {}, ext: [], sort: null, page: 1, size: 25 }, noHeader: true });
    state.pane = { kind: 'evidence', ev: ev };
  }
  function openDrill(c) {
    var recs = c.drill.records || [];
    var cols = []; recs.forEach(function (r) { if (r && typeof r === 'object') { Object.keys(r).forEach(function (k) { if (cols.indexOf(k) < 0) { cols.push(k); } }); } });
    if (!cols.length) { cols = ['Value']; }
    var tbl = { id: 'pf-drill', title: c.title, columns: cols, labels: {}, numeric: cols.map(function () { return false; }), rows: recs.map(function (r) { return cols.map(function (k) { var v = r && typeof r === 'object' ? r[k] : (k === 'Value' ? r : null); return v === null || v === undefined ? null : (typeof v === 'object' ? JSON.stringify(v) : String(v)); }); }),
      rowStatus: {}, cellStatus: {}, filters: [], pageSize: 25, search: true, sort: true, paging: true, empty: 'No records.', nullText: '\u2014', export: { enabled: true, columns: cols, formats: ['Csv', 'Xlsx'], fileName: '', worksheet: '' } };
    cols.forEach(function (k) { tbl.labels[k] = k; });
    openPane(paneHead(c.title, plural(recs.length, 'record'), c.status, 'list') + '<div class="pf-pane-body"><div data-evgrid></div></div>', true);
    mountGrid($('[data-evgrid]', $('#pf-pane')), tbl, { noHeader: true, state: { q: '', filters: {}, ext: [], sort: null, page: 1, size: 25 }, onRow: function () {} });
  }

  // ------------------------------------------------------------------ navigation actions
  function applyTableFilter(tableId, property, values) {
    var t = tables[String(tableId || '').toLowerCase()];
    if (!t) { toast('Table "' + tableId + '" is not in this report'); return; }
    var tbl = t.comp, st = gridState(tbl);
    var control = tbl.filters.filter(function (f) { return f.property === property; })[0];
    st.q = ''; st.page = 1; st.ext = [];
    if (control) { st.filters = {}; st.filters[property] = values.filter(function (v) { return control.values.indexOf(v) >= 0; }); if (!st.filters[property].length) { st.ext = [{ property: property, operator: 'In', values: values }]; } }
    else { st.filters = {}; st.ext = [{ property: property, operator: values.length === 1 ? 'Equals' : 'In', value: values[0], values: values }]; }
    goToElement(sectionPage[t.section], tbl.id);
  }
  function applyConditions(tableId, conditions) {
    var t = tables[String(tableId || '').toLowerCase()]; if (!t) { return; }
    var st = gridState(t.comp); st.q = ''; st.page = 1; st.filters = {}; st.ext = (conditions || []).slice();
    closePane();
    goToElement(sectionPage[t.section], t.comp.id);
  }
  function goTarget(target) {
    var m = /^psi-section-(\d+)$/.exec(target || '');
    if (m) { goToElement(sectionPage[+m[1]], target); return; }
    if (findingById[target]) { goToElement(sectionPage[findingById[target]._section], target); return; }
    var t = tables[String(target || '').toLowerCase()];
    if (t) { goToElement(sectionPage[t.section], t.comp.id); return; }
    if (pageById[target]) { location.hash = '#/' + encodeURIComponent(target); }
  }
  function goToElement(pageId, elementId) {
    var want = '#/' + encodeURIComponent(pageId) + (elementId ? '/' + encodeURIComponent(elementId) : '');
    if (location.hash === want) { route(); } else { location.hash = want; }
  }

  // ------------------------------------------------------------------ application model (explorers, posture, relationships)
  var APP = D.app || null, AS = D.assessment || null, WS = D.workspace || null;
  var ENT = { Finding: {}, Resource: {}, Evidence: {}, Check: {}, Category: {}, Exception: {}, Relationship: {} };
  if (APP) {
    arr(APP.findings).forEach(function (x) { ENT.Finding[x.Id] = x; });
    arr(APP.resources).forEach(function (x) { ENT.Resource[x.Id] = x; });
    arr(APP.evidence).forEach(function (x) { ENT.Evidence[x.Id] = x; });
    arr(APP.relationships).forEach(function (x) { ENT.Relationship[x.Id] = x; });
  }
  if (AS) {
    arr(AS.Checks).forEach(function (x) { ENT.Check[x.Id] = x; });
    arr(AS.Categories).forEach(function (x) { ENT.Category[x.Id] = x; });
    arr(AS.Exceptions).forEach(function (x) { ENT.Exception[x.Id] = x; });
  }
  var entityPages = {}, explorerCount = 0;
  D.sections.forEach(function (s, si) {
    s.rows.forEach(function (r) { r.items.forEach(function (c) {
      if (c.t === 'Explorer') { explorerCount++; c.items = arr(c.items); c.filterProps = arr(c.filterProps); c.detailProps = arr(c.detailProps); if (c.entity) { (entityPages[c.entity] = entityPages[c.entity] || []).push(sectionPage[si]); } }
      if (c.t === 'Tree' || c.t === 'Topology' || c.t === 'RelationshipExplorer') { c.presentation = c.presentation || {}; c.presentation.Nodes = arr(c.presentation.Nodes); c.presentation.Edges = arr(c.presentation.Edges); c.presentation.Diagnostics = arr(c.presentation.Diagnostics); }
    }); });
  });
  state.explorers = {};

  var KIND_ICON = { Finding: 'shieldAlert', Resource: 'server', Evidence: 'document', Check: 'checklist', Category: 'layers', Exception: 'flag', Relationship: 'relationship' };
  var ASSESS_STATUS = { ready: 'Healthy', review: 'Warning', blocked: 'Critical', nottested: 'NotChecked', notapplicable: 'Neutral', unknown: 'Unknown' };
  var EXC_STATUS = { approved: 'Informational', pending: 'Warning', expired: 'Critical', revoked: 'Neutral' };
  var DECISION = { ready: 'Healthy', readywithreview: 'Warning', reviewrequired: 'Warning', notready: 'Critical', incomplete: 'NotChecked' };
  function human(s) { return s === null || s === undefined ? '' : String(s).replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^./, function (x) { return x.toUpperCase(); }); }
  function kindStatus(kind, v) {
    if (v === null || v === undefined || v === '') { return null; }
    var k = String(v).replace(/\s+/g, '').toLowerCase();
    if (kind === 'Check' || kind === 'Category') { return ASSESS_STATUS[k] || normStatus(v) || 'Unknown'; }
    if (kind === 'Exception') { return EXC_STATUS[k] || normStatus(v) || 'Unknown'; }
    if (kind === 'Decision') { return DECISION[k] || 'Unknown'; }
    return normStatus(v) || null;
  }
  function kindChip(kind, v) { var s = kindStatus(kind, v); if (!s) { return v ? '<span class="pf-chip">' + esc(human(v)) + '</span>' : ''; } return '<span class="pf-status pf-st-' + s + '">' + ic(ST_ICON[s]) + esc(human(v)) + '</span>'; }
  function entityTitle(kind, rec) { return rec ? (rec.Title || rec.Name || rec.Id) : ''; }
  function pageHasExplorer(pageId, kind) {
    var p = pageById[pageId]; if (!p) { return false; }
    return p.sections.some(function (si) { return D.sections[si].rows.some(function (r) { return r.items.some(function (c) { return c.t === 'Explorer' && c.entity === kind; }); }); });
  }
  function entityHref(kind, id, lv) {
    var page = lv && lv[kind] && pageHasExplorer(lv[kind], kind) ? lv[kind] : (entityPages[kind] || [])[0];
    return page ? '#/' + encodeURIComponent(page) + '/' + encodeURIComponent('@' + kind + ':' + id) : null;
  }
  function entityLink(kind, id, lv) {
    var rec = ENT[kind] && ENT[kind][id], href = entityHref(kind, id, lv), label = rec ? entityTitle(kind, rec) : id;
    var st = rec ? kindStatus(kind, kind === 'Finding' ? rec.Severity : rec.Status) : null;
    var inner = (st ? '<span class="pf-st-ico pf-st-' + st + '">' + ic(ST_ICON[st], 's12') + '</span>' : ic(KIND_ICON[kind] || 'document', 's12')) + '<span>' + esc(label) + '</span>';
    return href ? '<a class="pf-elink" href="' + href + '"' + tipText(kind + ': ' + label) + '>' + inner + '</a>' : '<span class="pf-elink off">' + inner + '</span>';
  }
  function linkList(kind, ids, lv) { ids = arr(ids); return ids.length ? '<div class="pf-elinks">' + ids.map(function (id) { return entityLink(kind, id, lv); }).join('') + '</div>' : '<span class="muted">None</span>'; }
  function valueHtml(v) {
    if (v === null || v === undefined || v === '') { return '<span class="muted">\u2014</span>'; }
    if (typeof v === 'boolean') { return v ? 'Yes' : 'No'; }
    if (Array.isArray(v)) { return v.length ? v.map(function (x) { return typeof x === 'object' ? '<code>' + esc(JSON.stringify(x)) + '</code>' : '<span class="pf-chip">' + esc(x) + '</span>'; }).join(' ') : '<span class="muted">None</span>'; }
    if (typeof v === 'object') { return '<code>' + esc(JSON.stringify(v)) + '</code>'; }
    var s = normStatus(v); if (s && String(v).length < 15) { return stChip(s, String(v)); }
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(String(v))) { return esc(String(v).replace('T', ' ').slice(0, 16)); }
    return esc(v);
  }
  function props(rows) {
    rows = rows.filter(function (r) { return r && r[1] !== undefined; });
    return rows.length ? '<dl class="pf-props">' + rows.map(function (r) { return '<dt>' + esc(r[0]) + '</dt><dd><span class="v">' + (r[2] ? r[1] : valueHtml(r[1])) + '</span></dd>'; }).join('') + '</dl>' : '';
  }
  function block(title, iconName, body, cls) { return body ? '<div class="pf-dblock ' + (cls || '') + '"><h4>' + ic(iconName) + esc(title) + '</h4>' + body + '</div>' : ''; }
  function codeBlock(text) { return '<div class="pf-code"><pre>' + esc(text) + '</pre><button class="pf-btn subtle sm icon" data-copy="' + esc(text) + '"' + tipText('Copy') + ' aria-label="Copy">' + ic('copy', 's12') + '</button></div>'; }
  function recommendationHtml(r) {
    if (!r || typeof r !== 'object') { return ''; }
    var rows = [['Action', r.Action], ['Rationale', r.Rationale], ['Expected state', r.ExpectedState], ['Priority', r.Priority], ['Change impact', r.ChangeImpact],
      r.RequiresRestart !== undefined ? ['Requires restart', r.RequiresRestart] : null, r.RequiresReboot !== undefined ? ['Requires reboot', r.RequiresReboot] : null,
      r.References ? ['References', r.References] : null].filter(function (x) { return x && x[1] !== undefined && x[1] !== null && x[1] !== ''; });
    return (r.Summary ? '<p>' + esc(r.Summary) + '</p>' : '') + props(rows) + (r.AutomationHint ? '<div class="pf-note" style="margin:8px 0 4px">' + ic('info', 's12') + '<span>Automation hint (descriptive only, never executed)</span></div>' + codeBlock(r.AutomationHint) : '');
  }
  function validationHtml(v) {
    if (!v || typeof v !== 'object') { return ''; }
    var rows = [['Method', v.Method], ['Description', v.Description], ['Expected result', v.ExpectedResult], ['Evidence required', v.EvidenceRequired], ['Status', v.Status]]
      .filter(function (x) { return x[1] !== undefined && x[1] !== null && x[1] !== ''; });
    return props(rows) + (v.Command ? codeBlock(v.Command) : '');
  }
  function relatedResources(resourceId) {
    var out = [];
    Object.keys(ENT.Relationship).forEach(function (k) {
      var r = ENT.Relationship[k];
      if (r.SourceResourceId === resourceId && r.TargetResourceId) { out.push({ id: r.TargetResourceId, rel: r, dir: 'to' }); }
      else if (r.TargetResourceId === resourceId && r.SourceResourceId) { out.push({ id: r.SourceResourceId, rel: r, dir: 'from' }); }
    });
    return out;
  }
  function entityDetail(kind, rec, lv, detailProps) {
    if (!rec) { return '<div class="pf-empty">' + ic('unknown') + '<div>Record not found in the model.</div></div>'; }
    var head = function (title, chips, sub) { return '<div class="pf-dhead"><span class="big pf-st-' + (chips.st || 'Neutral') + '">' + ic(KIND_ICON[kind]) + '</span><div><div class="eyebrow">' + esc(kind) + ' &middot; <code>' + esc(rec.Id) + '</code></div><h2>' + esc(title) + '</h2>' + (sub ? '<div class="sub">' + esc(sub) + '</div>' : '') + '<div class="pf-chips">' + chips.html + '</div></div></div>'; };
    var h = '';
    if (kind === 'Finding') {
      var fs = kindStatus('Finding', rec.Severity);
      h = head(rec.Title, { st: fs, html: kindChip('Finding', rec.Severity) + (rec.Status ? '<span class="pf-chip">' + esc(human(rec.Status)) + '</span>' : '') + (rec.Category ? '<span class="pf-chip">' + ic('tag') + esc(rec.Category) + (rec.Subcategory ? ' / ' + esc(rec.Subcategory) : '') + '</span>' : '') + arr(rec.Frameworks).map(function (f) { return '<span class="pf-chip brand">' + esc(typeof f === 'object' ? JSON.stringify(f) : f) + '</span>'; }).join('') }, rec.Summary) +
        block('Observed impact', 'warning', rec.ReadinessImpact ? '<p>' + esc(rec.ReadinessImpact) + '</p>' : '', 'risk') +
        block('Recommendation', 'lightbulb', recommendationHtml(rec.Recommendation), 'fix') +
        block('Validation', 'checklist', validationHtml(rec.Validation)) +
        block('Affected resources', 'server', linkList('Resource', rec.AffectedResourceIds, lv)) +
        block('Evidence', 'document', linkList('Evidence', rec.EvidenceIds, lv)) +
        (arr(rec.Relationships).length ? block('Relationships', 'relationship', '<ul class="pf-ul">' + arr(rec.Relationships).map(function (id) { var r = ENT.Relationship[id]; return '<li>' + (r ? esc(human(r.Type)) + ': ' + entityLink('Resource', r.SourceResourceId, lv) + ' ' + ic('arrowRight', 's12') + ' ' + entityLink('Resource', r.TargetResourceId, lv) : esc(id)) + '</li>'; }).join('') + '</ul>') : '') +
        props([rec.Owner ? ['Owner', rec.Owner] : null, rec.RemediationState ? ['Remediation state', rec.RemediationState] : null, arr(rec.Tags).length ? ['Tags', rec.Tags] : null].filter(Boolean));
    }
    else if (kind === 'Resource') {
      var rs = kindStatus('Resource', rec.Status);
      var bag = rec.Properties || {}, keys = Object.keys(bag);
      var ordered = arr(detailProps).filter(function (k) { return keys.indexOf(k) >= 0; }).concat(keys.filter(function (k) { return arr(detailProps).indexOf(k) < 0; }).sort());
      var rel = relatedResources(rec.Id);
      h = head(rec.Name, { st: rs, html: stChip(rs || 'Unknown', rec.Status) + '<span class="pf-chip">' + esc(rec.Type) + '</span>' + arr(rec.Tags).map(function (t) { return '<span class="pf-chip">' + esc(t) + '</span>'; }).join('') }, rec.Description) +
        block('Properties', 'list', ordered.length ? props(ordered.map(function (k) { return [human(k), bag[k]]; })) : '<span class="muted">No properties</span>') +
        block('Findings', 'shieldAlert', linkList('Finding', rec.FindingIds, lv)) +
        block('Evidence', 'document', linkList('Evidence', rec.EvidenceIds, lv)) +
        (rel.length ? block('Related resources', 'relationship', '<ul class="pf-ul">' + rel.map(function (x) { return '<li>' + esc(human(x.rel.Type)) + ' ' + (x.dir === 'to' ? ic('arrowRight', 's12') : '<span class="pf-ico s12" style="transform:rotate(180deg)">' + ICONS.arrowRight + '</span>') + ' ' + entityLink('Resource', x.id, lv) + (x.rel.Status ? ' ' + stChip(normStatus(x.rel.Status) || 'Unknown', x.rel.Status) : '') + '</li>'; }).join('') + '</ul>') : '');
    }
    else if (kind === 'Evidence') {
      var data = rec.Data, dataHtml;
      if (data === null || data === undefined) { dataHtml = '<span class="muted">No data</span>'; }
      else if (typeof data === 'string') { dataHtml = '<pre class="pf-pre">' + esc(data) + '</pre>'; }
      else if (Array.isArray(data) && data.length && typeof data[0] === 'object' && data[0] !== null) {
        var cols = []; data.forEach(function (r) { Object.keys(r || {}).forEach(function (k) { if (cols.indexOf(k) < 0) { cols.push(k); } }); });
        dataHtml = '<div class="pf-table-wrap" style="max-height:360px"><table class="pf-dt"><thead><tr>' + cols.map(function (k) { return '<th>' + esc(human(k)) + '</th>'; }).join('') + '</tr></thead><tbody>' + data.slice(0, 500).map(function (r) { return '<tr>' + cols.map(function (k) { return '<td>' + valueHtml(r ? r[k] : null) + '</td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table></div>' + (data.length > 500 ? '<div class="pf-note">' + ic('info', 's12') + '<span>First 500 of ' + data.length + ' rows</span></div>' : '');
      }
      else if (typeof data === 'object' && !Array.isArray(data)) { dataHtml = props(Object.keys(data).map(function (k) { return [human(k), data[k]]; })); }
      else { dataHtml = valueHtml(data); }
      h = head(rec.Title, { st: 'Informational', html: '<span class="pf-chip">' + esc(rec.Type) + '</span><span class="pf-chip">' + ic('globe') + esc(rec.Source) + '</span>' + (rec.CollectedAt ? '<span class="pf-chip">' + ic('clock') + esc(String(rec.CollectedAt).replace('T', ' ').slice(0, 16)) + '</span>' : '') }, rec.Summary) +
        block('Observed data', 'grid', dataHtml) +
        block('Findings', 'shieldAlert', linkList('Finding', rec.FindingIds, lv)) +
        block('Resources', 'server', linkList('Resource', rec.ResourceIds, lv));
    }
    else if (kind === 'Check') {
      var cs = kindStatus('Check', rec.Status), cat = ENT.Category[rec.CategoryId];
      h = head(rec.Name, { st: cs, html: kindChip('Check', rec.Status) + (rec.IsBlocking ? '<span class="pf-chip"' + tipText('A blocking check prevents a Ready decision while it is in Review or Blocked') + '>' + ic('blocked') + 'Blocking</span>' : '') + (rec.Severity ? kindChip('Finding', rec.Severity) : '') + '<span class="pf-chip"' + tipText('Weight within its category') + '>Weight ' + fmt(rec.Weight) + '</span>' + (cat ? entityLink('Category', cat.Id, lv) : '') }, rec.Description) +
        '<div class="pf-callouts" style="margin:12px 0">' + '<div class="pf-callout"><h5>' + ic('view') + 'Observed</h5><p>' + valueHtml(rec.ObservedState) + '</p></div><div class="pf-callout fix"><h5>' + ic('healthy') + 'Expected</h5><p>' + valueHtml(rec.ExpectedState) + '</p></div></div>' +
        block('Recommendation', 'lightbulb', recommendationHtml(rec.Recommendation), 'fix') +
        block('Validation', 'checklist', validationHtml(rec.Validation)) +
        block('Findings', 'shieldAlert', linkList('Finding', rec.FindingIds, lv)) +
        block('Resources', 'server', linkList('Resource', rec.ResourceIds, lv)) +
        block('Evidence', 'document', linkList('Evidence', rec.EvidenceIds, lv)) +
        (arr(rec.Frameworks).length ? block('Framework references', 'tag', valueHtml(arr(rec.Frameworks).map(function (f) { return typeof f === 'object' ? (f.Framework || f.Name || '') + ' ' + (f.Control || f.Id || '') : f; }))) : '');
    }
    else if (kind === 'Category') {
      var gs = kindStatus('Category', rec.Status);
      var checks = Object.keys(ENT.Check).map(function (k) { return ENT.Check[k]; }).filter(function (c) { return c.CategoryId === rec.Id; });
      h = head(rec.Name, { st: gs, html: kindChip('Category', rec.Status) + '<span class="pf-chip">Weight ' + fmt(rec.Weight) + '</span>' }, rec.Description) +
        (rec.Score !== null && rec.Score !== undefined ? '<div class="pf-dblock"><h4>' + ic('chart') + 'Score ' + fmt(rec.Score) + '</h4><div class="pf-meter pf-st-' + gs + '"><i style="width:' + Math.max(0, Math.min(100, rec.Score)) + '%"></i></div></div>' : '') +
        block('Checks (' + checks.length + ')', 'checklist', '<ul class="pf-ul">' + checks.sort(function (a, b) { return RANK[kindStatus('Check', a.Status)] - RANK[kindStatus('Check', b.Status)]; }).map(function (c) { return '<li>' + entityLink('Check', c.Id, lv) + ' ' + kindChip('Check', c.Status) + '</li>'; }).join('') + '</ul>');
    }
    else if (kind === 'Exception') {
      var xs = kindStatus('Exception', rec.Status), soon = '';
      if (rec.ExpiresAt && /approved/i.test(rec.Status)) { var dExp = Date.parse(rec.ExpiresAt), gen = Date.parse(AS && AS.GeneratedAt || META.generated); if (dExp > gen && dExp <= gen + 7 * 864e5) { soon = '<span class="pf-status pf-st-Warning">' + ic('clock') + 'Expires within seven days</span>'; } }
      h = head(rec.Title, { st: xs, html: kindChip('Exception', rec.Status) + soon }, rec.Description) +
        props([['Reason', rec.Reason], ['Owner', rec.Owner], ['Approved by', rec.ApprovedBy], ['Approved at', rec.ApprovedAt], ['Expires at', rec.ExpiresAt]]) +
        (rec.CheckId ? block('Check', 'checklist', entityLink('Check', rec.CheckId, lv)) : '') +
        (rec.FindingId ? block('Finding', 'shieldAlert', entityLink('Finding', rec.FindingId, lv)) : '') +
        block('Resources', 'server', linkList('Resource', rec.ResourceIds, lv)) +
        '<div class="pf-note" style="margin-top:8px">' + ic('info', 's12') + '<span>Exceptions are recorded for review; they never change the assessment score or decision.</span></div>';
    }
    return '<div class="pf-detail">' + h + '</div>';
  }

  R.Explorer = function (c, ctx) { var key = ctx.register(c); return '<section class="pf-explorer" data-mount="explorer" data-key="' + key + '" id="' + esc(c.id) + '"></section>'; };
  function mountExplorer(host, c) {
    var st = state.explorers[c.id] = state.explorers[c.id] || { q: '', f: {}, sel: null, limit: 300 };
    var focus = state.focus || '';
    var fm = /^@([A-Za-z]+):(.+)$/.exec(focus);
    if (fm && fm[1] === c.entity) { st.sel = fm[2]; st.q = ''; st.f = {}; }
    if (fm && fm[1] === 'cat' && c.entity === 'Check') { st.f = { CategoryId: fm[2] }; st.q = ''; st.sel = null; }
    if (fm && fm[1] === 'status' && (c.entity === 'Check' || c.entity === 'Finding')) { st.f = {}; st.f[c.entity === 'Check' ? 'Status' : 'Severity'] = fm[2]; st.q = ''; st.sel = null; }
    var catName = function (v) { return c.entity === 'Check' && ENT.Category[v] ? ENT.Category[v].Name : v; };
    var valueOf = function (it, p) {
      if (it.filters && p in it.filters) { return it.filters[p]; }
      var rec = c.entity && ENT[c.entity] ? ENT[c.entity][it.id] : null;
      return rec ? (rec[p] !== undefined ? rec[p] : rec.Properties ? rec.Properties[p] : null) : null;
    };
    var fprops = c.filterProps.slice();
    if (c.entity === 'Check' && !fprops.some(function (f) { return f.property === 'CategoryId'; }) && st.f.CategoryId) { fprops.push({ property: 'CategoryId', label: 'Category' }); }
    if (c.entity === 'Check' && !fprops.some(function (f) { return f.property === 'Status'; }) && st.f.Status) { fprops.push({ property: 'Status', label: 'Status' }); }
    if (c.entity === 'Finding' && !fprops.some(function (f) { return f.property === 'Severity'; }) && st.f.Severity) { fprops.push({ property: 'Severity', label: 'Severity' }); }
    host.innerHTML = '<div class="pf-md"><div class="pf-card"><div class="pf-card-h"><h3>' + esc(c.title) + '</h3><span class="grow"></span><span class="hint" data-x="count"></span></div>' +
      '<div class="pf-toolbar"><label class="pf-input" style="min-width:0;flex:1">' + ic('search') + '<input type="search" data-x="q" placeholder="Filter ' + esc(c.title) + '" value="' + esc(st.q) + '" aria-label="Filter list"></label>' +
      fprops.map(function (f) {
        var vals = {}; c.items.forEach(function (it) { var v = valueOf(it, f.property); if (v !== null && v !== undefined && v !== '') { vals[v] = (vals[v] || 0) + 1; } });
        return '<select class="pf-select" data-x="f" data-p="' + esc(f.property) + '" aria-label="' + esc(f.label) + '"><option value="">' + esc(f.label === 'Category Id' ? 'Category' : f.label) + ': all</option>' + Object.keys(vals).sort().map(function (v) { return '<option value="' + esc(v) + '"' + (st.f[f.property] === v ? ' selected' : '') + '>' + esc(human(f.property === 'CategoryId' ? catName(v) : v)) + ' (' + vals[v] + ')</option>'; }).join('') + '</select>';
      }).join('') + '</div><div class="pf-list" data-x="list"></div></div><div class="pf-card" data-x="detail"></div></div>';
    function list() {
      var q = st.q.toLowerCase();
      return c.items.filter(function (it) {
        if (q && ((it.title || '') + ' ' + (it.subtitle || '') + ' ' + (it.status || '') + ' ' + (it.id || '')).toLowerCase().indexOf(q) < 0) { return false; }
        return Object.keys(st.f).every(function (p) { return !st.f[p] || String(valueOf(it, p)) === st.f[p]; });
      });
    }
    function paint() {
      var L = list();
      if (st.sel === null || !L.some(function (it, i) { return (it.id || String(i)) === st.sel; })) { st.sel = L.length ? (L[0].id || '0') : null; }
      $('[data-x="count"]', host).textContent = L.length === c.items.length ? plural(c.items.length, 'record') : fmt(L.length) + ' of ' + plural(c.items.length, 'record');
      $('[data-x="list"]', host).innerHTML = L.length ? L.slice(0, st.limit).map(function (it, i) {
        var key = it.id || String(c.items.indexOf(it)), s = kindStatus(c.entity || 'Generic', it.status);
        return '<div class="pf-li' + (key === st.sel ? ' sel' : '') + '" data-xk="' + esc(key) + '" role="button" tabindex="0">' + (s ? '<span class="pf-st-ico pf-st-' + s + '">' + ic(ST_ICON[s]) + '</span>' : ic(KIND_ICON[c.entity] || 'document')) +
          '<span class="t"' + tipText(it.title) + '>' + esc(it.title) + '</span><span class="c">' + (it.status ? '<span class="muted" style="font-weight:400;font-size:11px">' + esc(human(it.status)) + '</span>' : '') + '</span>' +
          '<span class="m">' + esc(it.subtitle !== null && it.subtitle !== undefined ? human(catName(it.subtitle)) : '') + '</span></div>';
      }).join('') + (L.length > st.limit ? '<div class="grid-more" style="padding:8px"><button class="pf-btn sm" data-x="more">Show ' + (L.length - st.limit) + ' more</button></div>' : '') : '<div class="pf-empty">' + ic('filter') + '<div>' + esc(c.items.length ? 'No records match the filters.' : c.empty) + '</div></div>';
      var det = $('[data-x="detail"]', host), sel = null;
      L.forEach(function (it) { if ((it.id || String(c.items.indexOf(it))) === st.sel) { sel = it; } });
      if (!sel) { det.innerHTML = '<div class="pf-empty">' + ic(KIND_ICON[c.entity] || 'document') + '<div>Select a record</div></div>'; return; }
      if (c.entity) { det.innerHTML = entityDetail(c.entity, ENT[c.entity] ? ENT[c.entity][sel.id] : null, c.linkViews, c.detailProps); }
      else {
        var s2 = normStatus(sel.status);
        det.innerHTML = '<div class="pf-detail"><div class="pf-dhead"><span class="big pf-st-' + (s2 || 'Neutral') + '">' + ic('document') + '</span><div><h2>' + esc(sel.title) + '</h2>' + (sel.subtitle ? '<div class="sub">' + esc(sel.subtitle) + '</div>' : '') + (s2 ? '<div class="pf-chips">' + stChip(s2, sel.status) + '</div>' : '') + '</div></div>' +
          props(arr(sel.details).map(function (d) { return [d[0], d[1]]; })) + '</div>';
      }
    }
    host.addEventListener('input', function (e) { if (e.target.getAttribute('data-x') === 'q') { st.q = e.target.value; st.sel = null; paint(); } });
    host.addEventListener('change', function (e) { if (e.target.getAttribute('data-x') === 'f') { st.f[e.target.getAttribute('data-p')] = e.target.value; st.sel = null; paint(); } });
    host.addEventListener('click', function (e) {
      var li = e.target.closest('[data-xk]');
      if (li && host.contains(li)) { st.sel = li.getAttribute('data-xk'); paint(); if (c.entity) { history.replaceState(null, '', '#/' + encodeURIComponent(state.page) + '/' + encodeURIComponent('@' + c.entity + ':' + st.sel)); } return; }
      if (e.target.closest('[data-x="more"]')) { st.limit += 300; paint(); }
    });
    host.addEventListener('keydown', function (e) {
      var li = e.target.closest && e.target.closest('[data-xk]'); if (!li) { return; }
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); li.click(); }
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); var sib = e.key === 'ArrowDown' ? li.nextElementSibling : li.previousElementSibling; if (sib && sib.hasAttribute('data-xk')) { sib.click(); var n = $('[data-xk="' + sib.getAttribute('data-xk').replace(/"/g, '\\"') + '"]', host); if (n) { n.focus(); } } }
    });
    paint();
    if (fm && fm[1] === c.entity) { host.scrollIntoView({ block: 'start' }); }
  }

  // Assessment posture (AssessmentOverview)
  R.AssessmentOverview = function (c) {
    if (!AS) { return R.Unsupported({ type: 'AssessmentOverview', title: 'Assessment overview' }); }
    var exp = AS.ScoreExplanation || {}, counts = exp.Counts || {}, th = AS.Thresholds || {};
    var dst = kindStatus('Decision', AS.Decision) || 'Unknown', score = AS.Score;
    var Cc = 2 * Math.PI * 48;
    var ring = '<svg viewBox="0 0 112 112" aria-hidden="true"><circle cx="56" cy="56" r="48" fill="none" stroke="var(--pf-surface-3)" stroke-width="10"/>' +
      (score !== null && score !== undefined ? '<circle cx="56" cy="56" r="48" fill="none" stroke="var(--pf-' + dst.toLowerCase() + '-mark)" stroke-width="10" stroke-linecap="round" stroke-dasharray="' + (Cc * Math.max(0, Math.min(100, score)) / 100).toFixed(1) + ' ' + Cc.toFixed(1) + '"/>' : '') + '</svg>';
    var md = AS.Metadata || {}, cov = md.EvidenceCoveragePercent;
    var cv = c.checkView, fv = c.findingView;
    var tile = function (label, n, st, filter, tip) {
      return '<a class="pf-card pf-sevtile pf-st-' + st + '" style="--span:2" href="#/' + encodeURIComponent(cv) + (filter ? '/' + encodeURIComponent(filter) : '') + '"' + tipText(tip) + '>' + ic(ST_ICON[st]) + '<div><div class="v">' + fmt(n || 0) + '</div><div class="l"><b>' + esc(label) + '</b></div></div></a>';
    };
    var blockers = Object.keys(ENT.Check).map(function (k) { return ENT.Check[k]; }).filter(function (ch) { return /^blocked$/i.test(ch.Status) || (ch.IsBlocking && /^review$/i.test(ch.Status)); }).slice(0, 6);
    var prio = arr(AS.FindingIds).map(function (id) { return ENT.Finding[id]; }).filter(function (f) { return f && ['Resolved', 'AcceptedRisk', 'NotApplicable'].indexOf(f.Status) < 0; })
      .sort(function (a, b) { return RANK[kindStatus('Finding', a.Severity) || 'Unknown'] - RANK[kindStatus('Finding', b.Severity) || 'Unknown']; }).slice(0, 6);
    var lv = { Check: cv, Finding: fv };
    var cats = arr(exp.CategoryScores);
    return '<div class="pf-posture">' +
      '<div class="pf-row"><div class="pf-card pf-hero" style="--span:7"><div class="pf-ring">' + ring + '<div class="num"><div><b>' + (score === null || score === undefined ? 'N/A' : fmt(score)) + '</b><small>score</small></div></div></div>' +
        '<div style="min-width:0"><h3>' + esc(AS.AssessmentType || 'Assessment') + '</h3><div class="rating"><span class="pf-st-ico pf-st-' + dst + '">' + ic(ST_ICON[dst], 's24') + '</span>' + esc(human(AS.Decision)) + '</div>' +
        '<div class="desc" style="font-size:13px;color:var(--pf-text-2)">' + esc(AS.Name) + '</div>' + (AS.Description ? '<div class="desc">' + esc(AS.Description) + '</div>' : '') +
        '<div class="pf-chips" style="margin-top:8px">' + (AS.Target ? '<span class="pf-chip brand">' + ic('server') + 'Target: ' + esc(AS.Target) + '</span>' : '') + (AS.Profile ? '<span class="pf-chip">' + ic('rules') + esc(AS.Profile) + '</span>' : '') +
        '<span class="pf-chip"' + tipText('Ready requires a score at or above the Ready threshold and no Review checks') + '>Ready \u2265 ' + fmt(th.Ready) + ' &middot; Review \u2265 ' + fmt(th.Review) + '</span></div></div></div>' +
      '<div class="pf-card" style="--span:5"><div class="pf-card-h"><h3>Why this decision</h3></div><div class="pf-card-b"><ul class="pf-ul">' + arr(exp.Reasons).map(function (r) { return '<li>' + esc(r) + '</li>'; }).join('') + '</ul>' +
        (cov !== undefined && cov !== null ? '<div style="margin-top:12px"><div class="pf-note" style="justify-content:space-between"><span><b>Evidence coverage</b></span><span>' + fmt(cov) + '%</span></div><div class="pf-meter" style="margin-top:4px"><i style="width:' + Math.max(0, Math.min(100, cov)) + '%"></i></div><div class="pf-note" style="margin-top:4px">' + ic('info', 's12') + '<span>Coverage and readiness are separate measures.</span></div></div>' : '') +
        (exp.CategoryFormula ? '<div class="pf-note" style="margin-top:10px">' + ic('info', 's12') + '<span>' + esc(exp.CategoryFormula) + '</span></div>' : '') + '</div></div></div>' +
      '<div class="pf-row">' + tile('Blockers', (counts.Blockers || 0) + (counts.CriticalFindings || 0), 'Critical', '@status:Blocked', 'Blocking checks in Review or Blocked, plus open critical findings') +
        tile('Blocked', counts.Blocked, 'Critical', '@status:Blocked', 'Checks with status Blocked') + tile('Review', counts.Review, 'Warning', '@status:Review', 'Checks needing review') +
        tile('Ready', counts.Ready, 'Healthy', '@status:Ready', 'Checks that are ready') + tile('Not tested', counts.NotTested, 'NotChecked', '@status:NotTested', 'Checks not tested (score zero until assessed)') +
        tile('Not applicable', counts.NotApplicable, 'Neutral', '@status:NotApplicable', 'Excluded from the score') + '</div>' +
      '<div class="pf-section"><h2>' + ic('layers') + 'Category posture</h2><div class="pf-row">' + cats.map(function (cs) {
        var s = kindStatus('Category', cs.Status) || 'Unknown', k = cs.Counts || {};
        return '<a class="pf-card pf-catcard pf-st-' + s + '" style="--span:3" href="#/' + encodeURIComponent(cv) + '/' + encodeURIComponent('@cat:' + cs.Id) + '"' + tipText('Weight ' + fmt(cs.Weight) + (cs.WeightedContribution !== null && cs.WeightedContribution !== undefined ? ' &middot; contribution ' + fmt(cs.WeightedContribution) : '')) + '>' +
          '<div class="top">' + ic(role((ENT.Category[cs.Id] || {}).Icon, 'layers')) + '<span class="nm">' + esc(cs.Name) + '</span><b>' + (cs.Score === null || cs.Score === undefined ? 'N/A' : fmt(cs.Score)) + '</b></div>' +
          '<div class="pf-meter"><i style="width:' + Math.max(0, Math.min(100, cs.Score || 0)) + '%"></i></div>' +
          '<div class="cnt">' + kindChip('Category', cs.Status) + ' <span>' + [k.Ready ? k.Ready + ' ready' : '', k.Review ? k.Review + ' review' : '', k.Blocked ? k.Blocked + ' blocked' : '', k.NotTested ? k.NotTested + ' not tested' : '', k.NotApplicable ? k.NotApplicable + ' n/a' : ''].filter(Boolean).join(' &middot; ') + '</span></div></a>';
      }).join('') + '</div></div>' +
      '<div class="pf-row"><div class="pf-card" style="--span:6"><div class="pf-card-h"><h3>' + ic('blocked') + ' Top blockers</h3></div><div class="pf-card-b">' + (blockers.length ? '<ul class="pf-ul">' + blockers.map(function (ch) { return '<li>' + entityLink('Check', ch.Id, lv) + ' ' + kindChip('Check', ch.Status) + '</li>'; }).join('') + '</ul>' : '<div class="pf-empty good">' + ic('healthy') + '<div>No blocking checks</div></div>') + '</div></div>' +
        '<div class="pf-card" style="--span:6"><div class="pf-card-h"><h3>' + ic('shieldAlert') + ' Priority findings</h3></div><div class="pf-card-b">' + (prio.length ? '<ul class="pf-ul">' + prio.map(function (f) { return '<li>' + entityLink('Finding', f.Id, lv) + ' ' + kindChip('Finding', f.Severity) + '</li>'; }).join('') + '</ul>' : '<div class="pf-empty good">' + ic('healthy') + '<div>No open findings</div></div>') + '</div></div></div>' +
      (arr(AS.Recommendations).length ? '<div class="pf-card"><div class="pf-card-h"><h3>' + ic('lightbulb') + ' Recommendations</h3></div><div class="pf-card-b"><ul class="pf-ul">' + arr(AS.Recommendations).map(function (r) { return '<li>' + esc(r) + '</li>'; }).join('') + '</ul></div></div>' : '') +
      '</div>';
  };

  // Relationships: Tree, Topology, RelationshipExplorer
  R.Tree = R.Topology = R.RelationshipExplorer = function (c, ctx) { var key = ctx.register(c); return '<section class="pf-card pf-rel" data-mount="rel" data-key="' + key + '" id="' + esc(c.id) + '"></section>'; };
  function relTable(c, nodeById) {
    var E = c.presentation.Edges;
    var rows = E.map(function (e) { return [nodeById[e.SourceId] ? nodeById[e.SourceId].Name : e.SourceId, human(e.Label || e.Type), nodeById[e.TargetId] ? nodeById[e.TargetId].Name : e.TargetId, normStatus(e.Status) || e.Status || null, e.Category || null, e.Direction || null, e.Description || null]; });
    var uniq = function (i) { var s = {}; rows.forEach(function (r) { if (r[i]) { s[r[i]] = 1; } }); return Object.keys(s).sort(); };
    return { id: c.id + '-rel', title: 'Relationships', columns: ['Source', 'Relationship', 'Target', 'Status', 'Category', 'Direction', 'Description'], labels: { Source: 'Source', Relationship: 'Relationship', Target: 'Target', Status: 'Status', Category: 'Category', Direction: 'Direction', Description: 'Description' },
      numeric: [false, false, false, false, false, false, false], rows: rows, rowStatus: {}, cellStatus: {},
      filters: [{ property: 'Status', label: 'Status', type: 'Select', values: uniq(3) }, { property: 'Relationship', label: 'Type', type: 'Select', values: uniq(1) }].concat(uniq(4).length > 1 ? [{ property: 'Category', label: 'Category', type: 'Select', values: uniq(4) }] : []).filter(function (f) { return f.values.length > 1; }),
      pageSize: 10, search: true, sort: true, paging: true, empty: 'No relationships.', nullText: '\u2014', export: { enabled: true, columns: ['Source', 'Relationship', 'Target', 'Status', 'Category', 'Direction', 'Description'], formats: ['Csv', 'Xlsx'], fileName: '', worksheet: 'Relationships' } };
  }
  function openNode(n, c, nodeById) {
    var lv = c.linkViews || {};
    var E = c.presentation.Edges.filter(function (e) { return e.SourceId === n.Id || e.TargetId === n.Id; });
    var s = normStatus(n.Status) || 'Unknown';
    openPane(paneHead(n.Name, n.Type + (n.External ? ' \u00b7 external' : ''), s, role(n.Icon, 'server'), stChip(s, n.Status) + (n.EvidenceOnly ? '<span class="pf-chip">Evidence only</span>' : '')) +
      '<div class="pf-pane-body">' + (n.Description ? '<div class="pf-block"><p>' + esc(n.Description) + '</p></div>' : '') +
      (arr(n.Details).length ? '<dl class="pf-props">' + arr(n.Details).map(function (d) { return '<dt>' + esc(d.Label) + '</dt><dd><span class="v">' + valueHtml(d.Value) + '</span></dd>'; }).join('') + '</dl>' : '') +
      (n.ResourceId && ENT.Resource[n.ResourceId] ? '<div class="pf-block"><h4>' + ic('server') + 'Resource</h4>' + entityLink('Resource', n.ResourceId, lv) + '</div>' : '') +
      (arr(n.Findings).length ? '<div class="pf-block"><h4>' + ic('shieldAlert') + 'Findings</h4>' + linkList('Finding', arr(n.Findings).map(function (x) { return x.Id; }), lv) + '</div>' : '') +
      (arr(n.Evidence).length ? '<div class="pf-block"><h4>' + ic('document') + 'Evidence</h4>' + linkList('Evidence', arr(n.Evidence).map(function (x) { return x.Id; }), lv) + '</div>' : '') +
      (E.length ? '<div class="pf-block"><h4>' + ic('relationship') + 'Relationships (' + E.length + ')</h4><ul class="pf-ul">' + E.map(function (e) {
        var other = e.SourceId === n.Id ? e.TargetId : e.SourceId, on = nodeById[other];
        return '<li>' + esc(human(e.Label || e.Type)) + ' ' + (e.SourceId === n.Id ? ic('arrowRight', 's12') : '<span class="pf-ico s12" style="transform:rotate(180deg)">' + ICONS.arrowRight + '</span>') + ' <a data-node="' + esc(other) + '" data-rel="' + esc(c.id) + '">' + esc(on ? on.Name : other) + '</a>' + (e.Status ? ' ' + stChip(normStatus(e.Status) || 'Unknown', e.Status) : '') + '</li>';
      }).join('') + '</ul></div>' : '') + '</div>');
  }
  var relRegistry = {};
  function mountRel(host, c) {
    var N = c.presentation.Nodes, E = c.presentation.Edges, nodeById = {};
    N.forEach(function (n) { nodeById[n.Id] = n; });
    relRegistry[c.id] = { c: c, nodeById: nodeById };
    var diag = c.presentation.Diagnostics.length ? '<div class="pf-note" style="padding:0 16px 8px">' + ic('info', 's12') + '<span>' + esc(c.presentation.Diagnostics.join(' ')) + '</span></div>' : '';
    var statusCounts = {}; N.forEach(function (n) { var s = normStatus(n.Status) || 'Unknown'; statusCounts[s] = (statusCounts[s] || 0) + 1; });
    var head = '<div class="pf-card-h"><h3>' + esc(c.title) + '</h3><span class="grow"></span><span class="hint">' + plural(N.length, 'node') + ' &middot; ' + plural(E.length, 'relationship') + '</span></div>';
    var legend = '<div class="pf-chips" style="padding:8px 16px 0">' + STATUSES.filter(function (s) { return statusCounts[s]; }).map(function (s) { return stChip(s, stLabel(s) + ' ' + statusCounts[s]); }).join('') + '</div>';
    if (c.t === 'Tree') {
      var kids = {}; N.forEach(function (n) { var p = n.ParentId && nodeById[n.ParentId] ? n.ParentId : ''; (kids[p] = kids[p] || []).push(n); });
      var branch = function (pid, depth) {
        return (kids[pid] || []).map(function (n) {
          var s = normStatus(n.Status) || 'Unknown', has = (kids[n.Id] || []).length;
          return '<li data-tn="' + esc(n.Id) + '"' + (depth < 2 ? ' class="open"' : '') + '><div class="row" style="padding-left:' + (8 + depth * 18) + 'px">' +
            (has ? '<button class="tw" data-act="tw" aria-label="Expand">' + ic('chevronR', 's12') + '</button>' : '<span class="tw none"></span>') +
            '<a class="pf-tnode" data-node="' + esc(n.Id) + '" data-rel="' + esc(c.id) + '">' + '<span class="pf-st-ico pf-st-' + s + '">' + ic(role(n.Icon, 'server'), 's12') + '</span>' + esc(n.Name) + '</a><span class="muted" style="font-size:11px">' + esc(n.Type) + '</span>' + (RANK[s] <= 1 ? stChip(s, n.Status) : '') + (has ? '<span class="muted" style="font-size:11px">' + has + '</span>' : '') + '</div>' +
            (has ? '<ul>' + branch(n.Id, depth + 1) + '</ul>' : '') + '</li>';
        }).join('');
      };
      host.innerHTML = head + legend + '<div class="pf-toolbar" style="border:0"><label class="pf-input" style="flex:1">' + ic('search') + '<input type="search" data-x="tq" placeholder="Find a node" aria-label="Find a node"></label><button class="pf-btn sm" data-act="treeAll">Expand all</button></div>' + diag +
        '<ul class="pf-tree" role="tree">' + branch('', 0) + '</ul>';
      host.addEventListener('input', function (e) {
        if (e.target.getAttribute('data-x') !== 'tq') { return; }
        var q = e.target.value.toLowerCase();
        $$('li[data-tn]', host).forEach(function (li) { li.hidden = false; if (q) { li.classList.add('open'); } });
        if (q) { $$('li[data-tn]', host).forEach(function (li) { var text = li.textContent.toLowerCase(); li.hidden = text.indexOf(q) < 0; }); }
      });
    }
    else if (c.t === 'Topology') {
      host.innerHTML = head + legend + '<div class="pf-toolbar" style="border:0"><label class="pf-input" style="flex:1">' + ic('search') + '<input type="search" data-x="gq" placeholder="Highlight nodes" aria-label="Highlight nodes"></label>' +
        '<button class="pf-btn sm icon" data-x="zo" aria-label="Zoom out"' + tipText('Zoom out') + '>&minus;</button><button class="pf-btn sm icon" data-x="zi" aria-label="Zoom in"' + tipText('Zoom in') + '>+</button><button class="pf-btn sm" data-x="zf">Fit</button></div>' + diag +
        '<div class="pf-graph" data-x="graph"></div><div data-x="reltable"></div>';
      var graph = $('[data-x="graph"]', host);
      if (N.length > c.maxNodes) { graph.innerHTML = '<div class="pf-empty">' + ic('info') + '<div>' + plural(N.length, 'node') + ' exceed the drawing limit of ' + c.maxNodes + '. Use the relationship list below.</div></div>'; }
      else { graph.innerHTML = topologySvg(c, N, E, nodeById); }
      var zoom = 1, svg = $('svg', graph);
      var setZoom = function (z) { zoom = Math.max(0.4, Math.min(2.5, z)); if (svg) { svg.style.width = (svg.getAttribute('data-w') * zoom) + 'px'; svg.style.height = (svg.getAttribute('data-h') * zoom) + 'px'; } };
      var fit = function () { if (svg) { setZoom(Math.min(1, (graph.clientWidth - 8) / svg.getAttribute('data-w'))); } };
      fit();
      host.addEventListener('click', function (e) { var x = e.target.closest('[data-x]'); if (!x) { return; } var k = x.getAttribute('data-x'); if (k === 'zi') { setZoom(zoom * 1.2); } else if (k === 'zo') { setZoom(zoom / 1.2); } else if (k === 'zf') { fit(); } });
      host.addEventListener('input', function (e) {
        if (e.target.getAttribute('data-x') !== 'gq') { return; }
        var q = e.target.value.toLowerCase();
        $$('g[data-node]', host).forEach(function (g) { var n = nodeById[g.getAttribute('data-node')]; g.classList.toggle('dim', !!q && (n.Name + ' ' + n.Type).toLowerCase().indexOf(q) < 0); });
      });
      if (E.length) { var rt = $('[data-x="reltable"]', host); rt.className = 'pf-card'; rt.style.margin = '0 16px 16px'; rt.style.boxShadow = 'none'; rt.style.border = '1px solid var(--pf-stroke-2)'; mountGrid(rt, relTable(c, nodeById), { title: 'Relationships', onRow: function (t, r) { var e = E[r]; openNode(nodeById[e.SourceId] || { Id: e.SourceId, Name: e.SourceId, Type: '', Status: 'Unknown', Details: [] }, c, nodeById); } }); }
    }
    else {
      host.innerHTML = head + legend + diag + '<div data-x="reltable"></div>';
      var rt2 = $('[data-x="reltable"]', host);
      mountGrid(rt2, relTable(c, nodeById), { noHeader: true, onRow: function (t, r) { var e = E[r]; openNode(nodeById[e.SourceId] || { Id: e.SourceId, Name: e.SourceId, Type: '', Status: 'Unknown', Details: [] }, c, nodeById); } });
    }
  }
  function topologySvg(c, N, E, nodeById) {
    // Layered layout: containment (ParentId, or Category=Containment edges) gives columns by depth;
    // a flat graph (e.g. a replication mesh) is drawn on a circle. Fixed layout, no simulation.
    var parent = {};
    N.forEach(function (n) { if (n.ParentId && nodeById[n.ParentId]) { parent[n.Id] = n.ParentId; } });
    if (!Object.keys(parent).length) { E.forEach(function (e) { if (/containment/i.test(e.Category || '') && nodeById[e.SourceId] && nodeById[e.TargetId]) { parent[e.TargetId] = e.SourceId; } }); }
    var W = 200, H = 44, pos = {}, width, height;
    var depth = function (id, seen) { seen = seen || {}; if (!parent[id] || seen[id]) { return 0; } seen[id] = 1; return 1 + depth(parent[id], seen); };
    if (Object.keys(parent).length) {
      var cols = {}; N.forEach(function (n) { var d = depth(n.Id); (cols[d] = cols[d] || []).push(n); });
      var maxRows = 0;
      Object.keys(cols).forEach(function (d) {
        cols[d].sort(function (a, b) { var pa = parent[a.Id] ? N.indexOf(nodeById[parent[a.Id]]) : -1, pb = parent[b.Id] ? N.indexOf(nodeById[parent[b.Id]]) : -1; return pa - pb || (a.SortOrder - b.SortOrder) || String(a.Name).localeCompare(b.Name); });
        maxRows = Math.max(maxRows, cols[d].length);
      });
      Object.keys(cols).forEach(function (d) { var list = cols[d], off = (maxRows - list.length) * (H + 16) / 2; list.forEach(function (n, i) { pos[n.Id] = { x: 20 + d * (W + 80), y: 20 + off + i * (H + 16) }; }); });
      width = 40 + Object.keys(cols).length * (W + 80) - 80; height = 40 + maxRows * (H + 16);
    }
    else {
      // Ellipse sized so horizontally adjacent boxes (top/bottom) and vertically adjacent boxes (sides) never overlap.
      var rx = Math.max(240, N.length * (W + 30) / (2 * Math.PI)), ry = Math.max(150, N.length * (H + 24) / (2 * Math.PI), rx * 0.42);
      var cx = rx + W / 2 + 20, cy = ry + H / 2 + 20;
      N.forEach(function (n, i) { var a = -Math.PI / 2 + 2 * Math.PI * i / Math.max(1, N.length); pos[n.Id] = { x: cx + rx * Math.cos(a) - W / 2, y: cy + ry * Math.sin(a) - H / 2 }; });
      width = 2 * cx; height = 2 * cy;
    }
    var center = function (id) { var p = pos[id]; return p ? { x: p.x + W / 2, y: p.y + H / 2 } : null; };
    var lines = '';
    Object.keys(parent).forEach(function (id) { var a = pos[parent[id]], b = pos[id]; if (a && b) { lines += '<path class="pf-edge contain" d="M' + (a.x + W) + ' ' + (a.y + H / 2) + ' C' + (a.x + W + 40) + ' ' + (a.y + H / 2) + ' ' + (b.x - 40) + ' ' + (b.y + H / 2) + ' ' + b.x + ' ' + (b.y + H / 2) + '"/>'; } });
    E.forEach(function (e, i) {
      if (/containment/i.test(e.Category || '') && parent[e.TargetId] === e.SourceId) { return; }
      var a = center(e.SourceId), b = center(e.TargetId); if (!a || !b) { return; }
      var s = normStatus(e.Status) || 'Unknown', mx = (a.x + b.x) / 2 + (b.y - a.y) * 0.12, my = (a.y + b.y) / 2 - (b.x - a.x) * 0.12;
      lines += '<path class="pf-edge pf-st-' + s + '" d="M' + a.x + ' ' + a.y + ' Q' + mx + ' ' + my + ' ' + b.x + ' ' + b.y + '"' + (e.Direction !== 'Bidirectional' ? ' marker-end="url(#pf-arrow-' + s + ')"' : '') + tipAttr('<b>' + esc(human(e.Label || e.Type)) + '</b><br>' + esc((nodeById[e.SourceId] || {}).Name) + ' \u2192 ' + esc((nodeById[e.TargetId] || {}).Name) + '<br>' + esc(stLabel(s))) + '/>';
    });
    var defs = '<defs>' + STATUSES.map(function (s) { return '<marker id="pf-arrow-' + s + '" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10z" fill="var(--pf-' + s.toLowerCase() + '-mark)"/></marker>'; }).join('') + '</defs>';
    var nodes = N.map(function (n) {
      var p = pos[n.Id], s = normStatus(n.Status) || 'Unknown', name = String(n.Name); if (!p) { return ''; }
      return '<g class="pf-gnode pf-st-' + s + '" data-node="' + esc(n.Id) + '" data-rel="' + esc(c.id) + '" transform="translate(' + p.x.toFixed(1) + ',' + p.y.toFixed(1) + ')" role="button" tabindex="0"' + tipAttr('<b>' + esc(name) + '</b><br>' + esc(n.Type) + ' &middot; ' + esc(stLabel(s))) + '>' +
        '<rect width="' + W + '" height="' + H + '" rx="6"/><rect class="bar" width="4" height="' + H + '" rx="2"/>' +
        '<text x="14" y="18" class="nm">' + esc(name.length > 26 ? name.slice(0, 25) + '\u2026' : name) + '</text><text x="14" y="34" class="ty">' + esc(String(n.Type || '').slice(0, 30)) + '</text></g>';
    }).join('');
    return '<svg class="pf-topo" data-w="' + Math.ceil(width) + '" data-h="' + Math.ceil(height) + '" viewBox="0 0 ' + Math.ceil(width) + ' ' + Math.ceil(height) + '" role="img" aria-label="' + esc(c.title) + '">' + defs + lines + nodes + '</svg>';
  }

  // Resource workspace (Add-PSIResourceExplorer / Add-PSIInspector): tree in the rail, inspector in the pane
  var wsNodes = WS && WS.explorer ? arr(WS.explorer.Nodes) : [];
  var wsItems = {};
  if (WS && WS.inspector) { arr(WS.inspector.Items).forEach(function (it) { wsItems[it.ResourceId] = it; }); }
  state.wsSel = WS && WS.explorer ? WS.explorer.SelectedId : null;
  function renderWorkspaceRail() {
    if (!wsNodes.length) { return ''; }
    var kids = {}; wsNodes.forEach(function (n) { (kids[n.ParentId || ''] = kids[n.ParentId || ''] || []).push(n); });
    var branch = function (pid, depth) {
      return (kids[pid] || []).map(function (n) {
        var s = normStatus(n.Status), has = (kids[n.Id] || []).length;
        return '<div class="pf-ws-node' + (state.wsSel === n.Id ? ' active' : '') + '" data-ws="' + esc(n.Id) + '" style="padding-left:' + (10 + depth * 14) + 'px" role="button" tabindex="0"' + tipText(n.Label + (n.Type ? ' (' + n.Type + ')' : '')) + '>' + ic(role(n.Icon, 'server')) + '<span class="txt">' + esc(n.Label) + '</span>' +
          (n.Count !== null && n.Count !== undefined ? '<span class="count">' + fmt(n.Count) + '</span>' : '') + (s && RANK[s] <= 1 ? '<span class="pf-st-ico pf-st-' + s + '">' + ic(ST_ICON[s], 's12') + '</span>' : '') + '</div>' + branch(n.Id, depth + 1);
      }).join('');
    };
    return '<div class="pf-rail-group">' + esc(WS.explorer.Title || 'Resources') + '</div><label class="pf-input" style="min-width:0;margin:2px 4px 6px;height:28px">' + ic('search', 's12') + '<input type="search" data-ws-q placeholder="Find a resource" aria-label="Find a resource"></label><div data-ws-tree>' + branch('', 0) + '</div>';
  }
  function openWorkspace(id) {
    var n = wsNodes.filter(function (x) { return x.Id === id; })[0]; if (!n) { return; }
    state.wsSel = id;
    var it = wsItems[id];
    if (n.Target && pageById[n.Target] && state.page !== n.Target) { location.hash = '#/' + encodeURIComponent(n.Target); }
    renderRail();
    if (!it) { return; }
    var s = normStatus(it.Status) || 'Unknown';
    var tabs = [{ id: 'props', title: 'Properties' }].concat(arr(it.Sections).map(function (sec) { return { id: sec.Id, title: sec.Title || sec.Id }; }));
    openPane(paneHead(it.Title, it.Subtitle, s, role(n.Icon, 'server'), stChip(s, it.Status) + arr(it.Metadata).map(function (m) { return '<span class="pf-chip">' + esc(m.Label) + ': ' + esc(m.Value) + '</span>'; }).join('')) +
      (arr(it.Breadcrumb).length ? '<div class="pf-note" style="padding:6px 20px">' + arr(it.Breadcrumb).map(esc).join(' &rsaquo; ') + '</div>' : '') +
      (arr(it.Actions).length ? '<div class="pf-block" style="display:flex;gap:8px;flex-wrap:wrap">' + arr(it.Actions).map(function (a) { return a.TargetView ? '<a class="pf-btn sm" href="#/' + encodeURIComponent(a.TargetView) + '">' + ic('arrowRight', 's12') + esc(a.Label) + '</a>' : a.ResourceId ? '<button class="pf-btn sm" data-ws="' + esc(a.ResourceId) + '">' + ic('arrowRight', 's12') + esc(a.Label) + '</button>' : ''; }).join('') + '</div>' : '') +
      '<div class="pf-tabs" role="tablist">' + tabs.map(function (t, i) { return '<button class="pf-tab' + (i === 0 ? ' on' : '') + '" data-tab="' + esc(t.id) + '">' + esc(t.title) + '</button>'; }).join('') + '</div>' +
      '<div class="pf-pane-body"><div data-tabp="props"><dl class="pf-props">' + arr(it.Properties).map(function (p) { return '<dt>' + esc(p.Label) + '</dt><dd><span class="v">' + valueHtml(p.Value) + '</span></dd>'; }).join('') + '</dl></div>' +
      arr(it.Sections).map(function (sec) {
        return '<div data-tabp="' + esc(sec.Id) + '" hidden>' + arr(sec.Blocks).map(function (b) {
          var bs = normStatus(b.Status);
          return '<div class="pf-block"><h4>' + (bs ? '<span class="pf-st-ico pf-st-' + bs + '">' + ic(ST_ICON[bs], 's12') + '</span>' : '') + esc(b.Title) + (b.Status && !bs ? ' <span class="pf-chip">' + esc(b.Status) + '</span>' : '') + '</h4>' + (b.Text ? '<p>' + esc(b.Text) + '</p>' : '') +
            (b.ActionLabel ? (b.TargetView ? '<a class="pf-btn sm" style="margin-top:6px" href="#/' + encodeURIComponent(b.TargetView) + '">' + esc(b.ActionLabel) + '</a>' : b.ResourceId ? '<button class="pf-btn sm" style="margin-top:6px" data-ws="' + esc(b.ResourceId) + '">' + esc(b.ActionLabel) + '</button>' : '') : '') + '</div>';
        }).join('') + '</div>';
      }).join('') + '</div>');
  }

  // ------------------------------------------------------------------ page rendering
  function renderSections(container, indexes, showTitles) {
    var registry = [];
    var ctx = { register: function (c) { registry.push(c); return registry.length - 1; } };
    var html = indexes.map(function (si) {
      var s = D.sections[si];
      var rowsHtml = s.rows.map(function (r) {
        var items = r.items.filter(function (c) { return c; });
        if (!items.length) { return ''; }
        return '<div class="pf-row" style="--cols:' + r.columns + '">' + items.map(function (c) {
          var h = (R[c.t] || R.Unsupported)(c, ctx);
          // Row-wide components take the row's Columns as their span.
          if (['Text', 'Status', 'Alert', 'Recommendation', 'Finding', 'Chart', 'EmptyState', 'Unsupported', 'Explorer', 'AssessmentOverview', 'Tree', 'Topology', 'RelationshipExplorer'].indexOf(c.t) >= 0) { h = '<div' + spanStyle(r.columns) + '>' + h + '</div>'; }
          return h;
        }).join('') + '</div>';
      }).join('');
      var findingCount = 0, affected = {};
      s.rows.forEach(function (r) { r.items.forEach(function (c) { if (c.t === 'Finding') { findingCount++; affected[c.affected || ''] = (affected[c.affected || ''] || 0) + 1; } }); });
      var objFilter = '';
      var keys = Object.keys(affected).filter(function (k) { return k; });
      if (findingCount > 1 && keys.length > 1) {
        objFilter = '<div class="pf-toolbar" style="border:0;padding:0 0 10px"><span class="gl muted" style="font-size:12px">Affected object</span><select class="pf-select" data-act="findObj" data-sec="' + si + '"><option value="">All findings (' + findingCount + ')</option>' +
          Object.keys(affected).sort().map(function (k) { return '<option value="' + esc(k) + '">' + esc(k || 'Unspecified') + ' (' + affected[k] + ')</option>'; }).join('') + '</select></div>';
      }
      return '<section class="pf-section" id="' + esc(s.id) + '" data-sec="' + si + '">' + (showTitles ? '<h2>' + ic(s.icon) + esc(s.title) + '</h2>' : '') + objFilter + rowsHtml + '</section>';
    }).join('');
    container.insertAdjacentHTML('beforeend', html);
    // wire components needing behaviour
    $$('[data-grid]', container).forEach(function (host) { var c = registry[+host.getAttribute('data-grid')]; host.removeAttribute('data-grid'); host.setAttribute('data-grid', c.id); mountGrid(host, c); });
    $$('[data-mount]', container).forEach(function (host) {
      var c = registry[+host.getAttribute('data-key')], kind = host.getAttribute('data-mount');
      host.removeAttribute('data-mount');
      if (kind === 'explorer') { mountExplorer(host, c); } else if (kind === 'rel') { mountRel(host, c); }
    });
    container.addEventListener('click', function (e) {
      var el = e.target.closest('[data-cmp]');
      if (el && container.contains(el) && !e.target.closest('[data-chart]')) {
        var c = registry[+el.getAttribute('data-cmp')];
        if (!c) { return; }
        if (c.t === 'KPI') {
          if (c.drill) { openDrill(c); }
          if (c.filter) { applyTableFilter(c.filter.table, c.filter.property, c.filter.values); }
          else if (c.action && !c.drill) { if (c.action.type === 'FilterTable') { applyTableFilter(c.action.target, c.action.property, [c.action.value]); } else { goTarget(c.action.target); } }
        }
        if ((c.t === 'Insight' || c.t === 'Finding') && c.evidence) { openEvidence(c); }
        return;
      }
      var mark = e.target.closest('[data-chart]');
      if (mark && container.contains(mark)) {
        var chart = registry[+mark.getAttribute('data-chart')], i = +mark.getAttribute('data-ci');
        applyTableFilter(chart.filter.table, chart.filter.property, [chart.filter.values[i]]);
      }
    });
    container.addEventListener('keydown', function (e) {
      if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('[data-cmp][role="button"], [data-chart]')) { e.preventDefault(); e.target.click(); }
    });
    container.addEventListener('change', function (e) {
      if (e.target.getAttribute('data-act') !== 'findObj') { return; }
      var sec = $('[data-sec="' + e.target.getAttribute('data-sec') + '"]', container), v = e.target.value;
      $$('.pf-finding', sec).forEach(function (f) { f.parentElement.hidden = v !== '' && f.getAttribute('data-affected') !== v; });
    });
  }

  function renderFindingsPage(view, selId) {
    var F = state.findFilter;
    if (selId) { state.findSel = selId; }
    var cats = {}, objs = {};
    D.findings.forEach(function (f) { if (f.category) { cats[f.category] = (cats[f.category] || 0) + 1; } if (f.affected) { objs[f.affected] = (objs[f.affected] || 0) + 1; } });
    var counts = {}; D.findings.forEach(function (f) { counts[f.status] = (counts[f.status] || 0) + 1; });
    var BY_RANK = STATUSES.slice().sort(function (a, b) { return RANK[a] - RANK[b]; });
    view.insertAdjacentHTML('beforeend',
      '<div class="pf-row">' + BY_RANK.filter(function (s) { return counts[s]; }).map(function (s) {
        return '<div class="pf-card pf-sevtile pf-st-' + s + ' clickable" style="--span:' + Math.max(2, Math.floor(12 / Math.max(1, BY_RANK.filter(function (x) { return counts[x]; }).length))) + '" role="button" tabindex="0" data-fs="' + s + '">' + ic(ST_ICON[s]) + '<div><div class="v">' + counts[s] + '</div><div class="l"><b>' + stLabel(s) + '</b> findings</div></div></div>';
      }).join('') + '</div>' +
      '<div class="pf-card" style="margin-bottom:16px"><div class="pf-toolbar" style="border:0">' +
      '<span class="pf-fgroup">' + BY_RANK.filter(function (s) { return counts[s]; }).map(function (s) { return '<button class="pf-fchip' + (F.st[s] ? ' on' : '') + '" data-fs="' + s + '"><span class="pf-st-ico pf-st-' + s + '">' + ic(ST_ICON[s], 's12') + '</span>' + stLabel(s) + ' <span class="n">' + counts[s] + '</span></button>'; }).join('') + '</span>' +
      (Object.keys(cats).length ? '<span class="pf-fgroup">' + Object.keys(cats).sort().map(function (c) { return '<button class="pf-fchip' + (F.cat[c] ? ' on' : '') + '" data-fc="' + esc(c) + '">' + esc(c) + ' <span class="n">' + cats[c] + '</span></button>'; }).join('') + '</span>' : '') +
      (Object.keys(objs).length > 1 ? '<select class="pf-select" data-fo><option value="">All affected objects</option>' + Object.keys(objs).sort().map(function (o) { return '<option value="' + esc(o) + '"' + (F.obj === o ? ' selected' : '') + '>' + esc(o) + ' (' + objs[o] + ')</option>'; }).join('') + '</select>' : '') +
      '</div></div><div class="pf-md"><div class="pf-card"><div class="pf-list" data-flist></div></div><div data-fdetail></div></div>');
    function list() {
      return D.findings.filter(function (f) {
        var anySt = Object.keys(F.st).filter(function (k) { return F.st[k]; }), anyCat = Object.keys(F.cat).filter(function (k) { return F.cat[k]; });
        return (!anySt.length || F.st[f.status]) && (!anyCat.length || F.cat[f.category]) && (!F.obj || f.affected === F.obj);
      }).sort(function (a, b) { return RANK[a.status] - RANK[b.status] || a.title.localeCompare(b.title); });
    }
    function paint() {
      var L = list();
      if (!state.findSel || !L.some(function (f) { return f.id === state.findSel; })) { state.findSel = L.length ? L[0].id : null; }
      $('[data-flist]', view).innerHTML = L.length ? L.map(function (f) {
        var c = findingById[f.id];
        return '<div class="pf-li' + (f.id === state.findSel ? ' sel' : '') + '" data-fid="' + esc(f.id) + '" role="button" tabindex="0"><span class="pf-st-ico pf-st-' + f.status + '">' + ic(ST_ICON[f.status]) + '</span><span class="t"' + tipText(f.title) + '>' + esc(f.title) + '</span>' +
          '<span class="c">' + (c && c.evidence ? fmt(evidenceRows(c.evidence).length) : '') + '</span><span class="m">' + esc([stLabel(f.status), f.category, f.affected].filter(Boolean).join(' \u00b7 ')) + '</span></div>';
      }).join('') : '<div class="pf-empty">' + ic('filter') + '<div>No findings match the filters</div></div>';
      var host = $('[data-fdetail]', view);
      host.innerHTML = '';
      var c = findingById[state.findSel];
      if (!c) { return; }
      var page = pageById[sectionPage[c._section]];
      host.insertAdjacentHTML('beforeend', R.Finding(c, { register: function () { return 0; } }));
      var card = $('.pf-finding', host), acts = $('.acts', card);
      if (!acts) { card.insertAdjacentHTML('beforeend', '<div class="acts"></div>'); acts = $('.acts', card); }
      acts.insertAdjacentHTML('afterbegin', '<a class="pf-btn sm" href="#/' + encodeURIComponent(page.id) + '/' + encodeURIComponent(c.id) + '">' + ic('openNew') + 'Show in ' + esc(page.title) + '</a>');
      if (c.evidence) {
        var t = tables[String(c.evidence.table).toLowerCase()];
        if (t) {
          var g = document.createElement('section'); g.className = 'pf-card'; g.style.marginTop = '16px'; host.appendChild(g);
          mountGrid(g, t.comp, { title: 'Evidence \u00b7 ' + t.comp.title, columns: c.evidence.columns, exportColumns: c.evidence['export'], base: evidenceRows(c.evidence), noFilters: true, state: { q: '', filters: {}, ext: [], sort: null, page: 1, size: 10 }, maxHeight: '520px' });
        }
      }
      var btn = $('.pf-finding [data-cmp]', host); if (btn) { btn.addEventListener('click', function () { openEvidence(c); }); }
    }
    view.addEventListener('click', function (e) {
      var li = e.target.closest('[data-fid]');
      if (li) { state.findSel = li.getAttribute('data-fid'); history.replaceState(null, '', '#/' + FINDINGS_PAGE + '/' + encodeURIComponent(state.findSel)); paint(); return; }
      var fs = e.target.closest('[data-fs]'); if (fs) { var s = fs.getAttribute('data-fs'); F.st[s] = !F.st[s]; $$('[data-fs="' + s + '"].pf-fchip', view).forEach(function (b) { b.classList.toggle('on', !!F.st[s]); }); paint(); return; }
      var fc = e.target.closest('[data-fc]'); if (fc) { var k = fc.getAttribute('data-fc'); F.cat[k] = !F.cat[k]; fc.classList.toggle('on'); paint(); }
    });
    view.addEventListener('change', function (e) { if (e.target.hasAttribute('data-fo')) { F.obj = e.target.value; paint(); } });
    view.addEventListener('keydown', function (e) { if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('[data-fid],[data-fs]')) { e.preventDefault(); e.target.click(); } });
    paint();
  }

  function renderPage(pageId, focusId) {
    var p = pageById[pageId];
    var old = $('#pf-view'), view = old.cloneNode(false);
    old.parentNode.replaceChild(view, old);
    state.page = pageId;
    renderRail();
    var group = ''; D.nav.forEach(function (g) { if (g.items.indexOf(pageId) >= 0) { group = g.label; } });
    var cmds = (p.commands || []).map(function (c) { return '<a class="pf-btn" href="#/' + encodeURIComponent(c.target) + '">' + ic(role(c.icon, 'arrowRight')) + esc(c.label) + '</a>'; }).join('');
    // Previous / next page within the same navigation group
    var siblings = []; D.nav.forEach(function (g) { if (g.items.indexOf(pageId) >= 0) { siblings = g.items.filter(function (id) { return pageById[id] && !pageById[id].disabled; }); } });
    var at = siblings.indexOf(pageId);
    if (siblings.length > 1) {
      var prev = siblings[at - 1], next = siblings[at + 1];
      cmds += '<span class="pf-pager-nav">' +
        (prev ? '<a class="pf-btn subtle" href="#/' + encodeURIComponent(prev) + '"' + tipText('Previous: ' + pageById[prev].title) + '><span class="pf-ico" style="transform:rotate(180deg)">' + ICONS.chevronR + '</span>Previous</a>' : '') +
        '<span class="muted" style="font-size:12px">' + (at + 1) + ' / ' + siblings.length + '</span>' +
        (next ? '<a class="pf-btn subtle" href="#/' + encodeURIComponent(next) + '"' + tipText('Next: ' + pageById[next].title) + '>Next' + ic('chevronR') + '</a>' : '') + '</span>';
    }
    view.insertAdjacentHTML('beforeend', '<div class="pf-page"><div class="pf-head"><div>' + (group && group !== 'Report' ? '<div class="eyebrow">' + esc(group) + '</div>' : '') + '<h1>' + esc(p.title) + '</h1>' +
      (p.subtitle && p.subtitle !== group ? '<div class="sub">' + esc(p.subtitle) + '</div>' : '') + '</div><span class="grow"></span>' + cmds + '</div></div>');
    var body = $('.pf-page', view);
    state.focus = focusId || '';
    if (p.synthetic) { renderFindingsPage(body, focusId); }
    else {
      var showTitles = p.sections.length > 1 || (p.sections.length === 1 && D.sections[p.sections[0]].title !== p.title);
      renderSections(body, p.sections, showTitles);
    }
    document.title = p.title + ' \u00b7 ' + META.title;
    if (focusId && !p.synthetic && focusId.charAt(0) !== '@') {
      var el = document.getElementById(focusId);
      if (el) { el.scrollIntoView({ block: 'start' }); el.animate && el.animate([{ boxShadow: '0 0 0 3px var(--pf-brand)' }, { boxShadow: '0 0 0 0 transparent' }], { duration: 1400 }); }
    } else { view.scrollTop = 0; }
    app.classList.remove('rail-open');
  }
  function route() {
    var parts = location.hash.replace(/^#\/?/, '').split('/').map(function (x) { try { return decodeURIComponent(x); } catch (e) { return x; } });
    var id = parts[0], focus = parts[1] || null;
    if (!pageById[id] || pageById[id].disabled) {
      var init = D.pages.filter(function (p) { return p.initial && !p.disabled; })[0] || D.pages.filter(function (p) { return !p.disabled; })[0];
      id = init.id;
    }
    closePalette();
    renderPage(id, focus);
  }

  // ------------------------------------------------------------------ print: flatten every page
  function printAll() {
    var view = $('#pf-view'), keep = view.innerHTML;
    view.innerHTML = '';
    D.pages.forEach(function (p) {
      if (p.synthetic || p.disabled) { return; }
      var wrap = document.createElement('div'); wrap.className = 'pf-view pf-page';
      wrap.innerHTML = '<div class="pf-head"><div><h1>' + esc(p.title) + '</h1>' + (p.subtitle ? '<div class="sub">' + esc(p.subtitle) + '</div>' : '') + '</div></div>';
      view.appendChild(wrap);
      p.sections.forEach(function (si) { D.sections[si].rows.forEach(function (r) { r.items.forEach(function (c) { if (c.t === 'Table') { var st = gridState(c); st._size = st.size; st.size = Math.min(c.rows.length || 1, 2000); st.page = 1; } }); }); });
      renderSections(wrap, p.sections, true);
    });
    setTimeout(function () {
      window.print();
      Object.keys(state.grids).forEach(function (k) { var st = state.grids[k]; if (st._size) { st.size = st._size; delete st._size; } });
      route();
    }, 50);
    void keep;
  }

  // ------------------------------------------------------------------ search palette
  var index = null;
  function buildIndex() {
    index = [];
    D.pages.forEach(function (p) { index.push({ k: 'Pages', title: p.title, sub: p.subtitle || '', icon: role(p.icon), go: '#/' + encodeURIComponent(p.id), text: (p.title + ' ' + (p.subtitle || '')).toLowerCase() }); });
    D.findings.forEach(function (f) { index.push({ k: 'Findings', title: f.title, sub: [f.category, f.affected].filter(Boolean).join(' \u00b7 '), st: f.status, go: '#/' + FINDINGS_PAGE + '/' + encodeURIComponent(f.id), text: (f.title + ' ' + f.category + ' ' + f.affected + ' ' + f.status).toLowerCase() }); });
    kpis.forEach(function (k) { index.push({ k: 'Metrics', title: k.c.title + ': ' + (k.c.value === null ? '\u2014' : k.c.value), sub: k.c.subtitle, st: k.c.status, go: '#/' + encodeURIComponent(sectionPage[k.section]) + '/psi-section-' + k.section, text: (k.c.title + ' ' + k.c.value + ' ' + k.c.subtitle).toLowerCase() }); });
    [['Finding', 'Findings', 'Title', 'Severity', 'Category'], ['Check', 'Checks', 'Name', 'Status', 'CategoryId'], ['Resource', 'Resources', 'Name', 'Status', 'Type'], ['Evidence', 'Evidence', 'Title', null, 'Source'], ['Exception', 'Exceptions', 'Title', 'Status', 'Reason']].forEach(function (d) {
      Object.keys(ENT[d[0]]).forEach(function (id) {
        var rec = ENT[d[0]][id], href = entityHref(d[0], id); if (!href) { return; }
        var sub = d[4] === 'CategoryId' && ENT.Category[rec.CategoryId] ? ENT.Category[rec.CategoryId].Name : rec[d[4]];
        index.push({ k: d[1], title: rec[d[2]] || id, sub: sub || '', st: d[3] ? kindStatus(d[0], rec[d[3]]) : null, icon: KIND_ICON[d[0]], go: href, text: ((rec[d[2]] || '') + ' ' + id + ' ' + (sub || '') + ' ' + (rec.Summary || rec.Description || '')).toLowerCase() });
      });
    });
    Object.keys(tables).forEach(function (k) { var t = tables[k]; index.push({ k: 'Tables', title: t.comp.title, sub: plural(t.comp.rows.length, 'row'), icon: 'grid', go: '#/' + encodeURIComponent(sectionPage[t.section]) + '/' + encodeURIComponent(t.comp.id), text: t.comp.title.toLowerCase() }); });
  }
  var palItems = [], palSel = 0;
  function openPalette() { if (!index) { buildIndex(); } $('#pf-palette').hidden = false; var i = $('#pf-palette-input'); i.value = ''; paintPalette(''); setTimeout(function () { i.focus(); }, 0); }
  function closePalette() { $('#pf-palette').hidden = true; }
  function paintPalette(q) {
    q = q.trim().toLowerCase();
    var terms = q.split(/\s+/).filter(Boolean);
    var hits = index.filter(function (it) { return !terms.length ? it.k === 'Pages' : terms.every(function (t) { return it.text.indexOf(t) >= 0; }); });
    var groups = {}; hits.forEach(function (h) { (groups[h.k] = groups[h.k] || []).push(h); });
    palItems = [];
    var html = '';
    ['Pages', 'Findings', 'Checks', 'Resources', 'Evidence', 'Exceptions', 'Metrics', 'Tables'].forEach(function (k) {
      if (!groups[k]) { return; }
      html += '<div class="grp">' + k + '</div>';
      groups[k].slice(0, 8).forEach(function (h) {
        html += '<div class="res' + (palItems.length === 0 ? ' on' : '') + '" data-pi="' + palItems.length + '" role="option">' + (h.st ? '<span class="pf-st-ico pf-st-' + h.st + '">' + ic(ST_ICON[h.st]) + '</span>' : ic(h.icon || 'document')) + '<span class="grow">' + esc(h.title) + '</span><span class="side">' + esc(h.sub || '') + '</span></div>';
        palItems.push({ go: h.go });
      });
    });
    if (terms.length) {
      // table rows: first matching rows across all tables
      var rowsFound = 0;
      Object.keys(tables).forEach(function (k) {
        var t = tables[k], tbl = t.comp, shown = 0;
        for (var r = 0; r < tbl.rows.length && shown < 5 && rowsFound < 15; r++) {
          var text = tbl.rows[r].join(' ').toLowerCase();
          if (terms.every(function (x) { return text.indexOf(x) >= 0; })) {
            if (!shown) { html += '<div class="grp">Rows in ' + esc(tbl.title) + '</div>'; }
            html += '<div class="res' + (palItems.length === 0 ? ' on' : '') + '" data-pi="' + palItems.length + '" role="option">' + ic('list') + '<span class="grow">' + esc(tbl.rows[r][0] === null ? '(no value)' : tbl.rows[r][0]) + '</span><span class="side">' + esc(tbl.rows[r].slice(1, 3).filter(function (x) { return x !== null; }).join(' \u00b7 ')) + '</span></div>';
            palItems.push({ row: { t: t, r: r } }); shown++; rowsFound++;
          }
        }
      });
      palItems.push({ cmd: 'theme' });
    }
    palSel = 0;
    $('#pf-palette-res').innerHTML = html || '<div class="pf-empty">' + ic('search') + '<div>No results for "' + esc(q) + '"</div></div>';
  }
  function palGo(i) {
    var it = palItems[i]; if (!it) { return; }
    closePalette();
    if (it.go) { location.hash = it.go; }
    if (it.row) { goToElement(sectionPage[it.row.t.section], it.row.t.comp.id); setTimeout(function () { openRow(it.row.t.comp, it.row.r); }, 30); }
  }
  function palMove(d) {
    var rows = $$('#pf-palette-res .res'); if (!rows.length) { return; }
    palSel = (palSel + d + rows.length) % rows.length;
    rows.forEach(function (r, i) { r.classList.toggle('on', i === palSel); });
    rows[palSel].scrollIntoView({ block: 'nearest' });
  }

  // ------------------------------------------------------------------ tooltip
  var tip = $('#pf-tip'), tipEl = null;
  document.addEventListener('mouseover', function (e) {
    var t = e.target.closest('[data-tip]');
    if (t === tipEl) { return; }
    tipEl = t;
    if (!t || !t.getAttribute('data-tip')) { tip.classList.remove('show'); return; }
    tip.innerHTML = t.getAttribute('data-tip'); tip.classList.add('show'); placeTip(e);
  });
  document.addEventListener('mousemove', function (e) { if (tipEl) { placeTip(e); } });
  document.addEventListener('scroll', function () { tip.classList.remove('show'); tipEl = null; }, true);
  function placeTip(e) {
    var r = tip.getBoundingClientRect(), x = e.clientX + 12, y = e.clientY + 16;
    if (x + r.width > innerWidth - 8) { x = e.clientX - r.width - 12; }
    if (y + r.height > innerHeight - 8) { y = e.clientY - r.height - 12; }
    tip.style.left = x + 'px'; tip.style.top = y + 'px';
  }

  // ------------------------------------------------------------------ global events
  document.addEventListener('click', function (e) {
    var c = e.target.closest('[data-copy]'); if (c) { copy(c.getAttribute('data-copy')); return; }
    var nd = e.target.closest('[data-node][data-rel]');
    if (nd) { var reg = relRegistry[nd.getAttribute('data-rel')]; if (reg && reg.nodeById[nd.getAttribute('data-node')]) { e.preventDefault(); openNode(reg.nodeById[nd.getAttribute('data-node')], reg.c, reg.nodeById); } return; }
    var ws = e.target.closest('[data-ws]'); if (ws) { openWorkspace(ws.getAttribute('data-ws')); return; }
    var tw = e.target.closest('[data-act="tw"]'); if (tw) { tw.closest('li').classList.toggle('open'); return; }
    var ta = e.target.closest('[data-act="treeAll"]'); if (ta) { var tree = ta.closest('.pf-rel'); var all = $$('li[data-tn]', tree), open = all.every(function (li) { return li.classList.contains('open'); }); all.forEach(function (li) { li.classList.toggle('open', !open); }); ta.textContent = open ? 'Expand all' : 'Collapse all'; return; }
    var pi = e.target.closest('[data-pi]'); if (pi) { palGo(+pi.getAttribute('data-pi')); return; }
    var a = e.target.closest('[data-act]'); if (!a) { return; }
    var act = a.getAttribute('data-act');
    if (act === 'palette') { openPalette(); }
    else if (act === 'theme') { setTheme(a.getAttribute('data-theme-btn')); }
    else if (act === 'print') { printAll(); }
    else if (act === 'paneClose') { closePane(); }
    else if (act === 'rail') { app.classList.toggle('rail-open'); }
    else if (act === 'railGroup') { var gi = +a.getAttribute('data-gi'); state.railOpen[gi] = a.getAttribute('aria-expanded') !== 'true'; renderRail(); }
    else if (act === 'chartTable') { var card = a.closest('.pf-chart'); card.classList.toggle('as-table'); a.innerHTML = card.classList.contains('as-table') ? ic('chart', 's12') + 'Chart' : ic('list', 's12') + 'Table'; }
    else if (act === 'evApply' && state.pane && state.pane.ev) { applyConditions(state.pane.ev.table, state.pane.ev.conditions); }
  });
  document.addEventListener('click', function (e) {
    var tab = e.target.closest('.pf-tab[data-tab]'); if (!tab) { return; }
    var pane = tab.closest('.pf-pane'); if (!pane) { return; }
    $$('.pf-tab', pane).forEach(function (t) { t.classList.toggle('on', t === tab); });
    $$('[data-tabp]', pane).forEach(function (p) { p.hidden = p.getAttribute('data-tabp') !== tab.getAttribute('data-tab'); });
  });
  $('#pf-palette').addEventListener('mousedown', function (e) { if (e.target.id === 'pf-palette') { closePalette(); } });
  $('#pf-palette-input').addEventListener('input', function (e) { paintPalette(e.target.value); });
  $('#pf-rail').addEventListener('input', function (e) {
    if (!e.target.hasAttribute('data-ws-q')) { return; }
    var q = e.target.value.toLowerCase();
    $$('.pf-ws-node', $('#pf-rail')).forEach(function (n) { n.hidden = !!q && n.textContent.toLowerCase().indexOf(q) < 0; });
  });
  $('#pf-palette-input').addEventListener('keydown', function (e) {
    if (e.key === 'ArrowDown') { e.preventDefault(); palMove(1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); palMove(-1); }
    else if (e.key === 'Enter') { e.preventDefault(); var on = $('#pf-palette-res .res.on'); if (on) { palGo(+on.getAttribute('data-pi')); } }
  });
  document.addEventListener('keydown', function (e) {
    var typing = /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName);
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openPalette(); return; }
    if ((e.key === 'Enter' || e.key === ' ') && document.activeElement && document.activeElement.matches && document.activeElement.matches('g[data-node], .pf-ws-node')) { e.preventDefault(); document.activeElement.dispatchEvent(new MouseEvent('click', { bubbles: true })); return; }
    if (e.key === '/' && !typing) { e.preventDefault(); openPalette(); return; }
    if (e.key === 'Escape') { if (!$('#pf-palette').hidden) { closePalette(); } else if (app.classList.contains('pane-open')) { closePane(); } else { app.classList.remove('rail-open'); } }
  });
  window.addEventListener('hashchange', route);
  window.addEventListener('beforeprint', function () { /* printAll() handles flattening for the print button */ });

  // ------------------------------------------------------------------ boot
  $$('[data-icon]').forEach(function (s) { s.innerHTML = ICONS[s.getAttribute('data-icon')] || ''; });
  renderTitlebar();
  if (D.pages.length < 2) { app.classList.add('no-rail'); }
  route();
  window.PSIFluent = { model: D, applyTableFilter: applyTableFilter, goTarget: goTarget, openEvidence: openEvidence };
})();
