(function () {
  'use strict';

  var root = document.documentElement;
  var themeButtons = Array.prototype.slice.call(document.querySelectorAll('[data-psi-theme]'));
  var themeLabel = document.querySelector('[data-psi-theme-value]');
  var footerThemeLabel = document.querySelector('[data-psi-theme-footer]');
  var validThemes = ['Light', 'Dark', 'Auto'];

  function setTheme(theme, persist) {
    if (validThemes.indexOf(theme) === -1) { return; }
    root.setAttribute('data-theme', theme);
    themeButtons.forEach(function (button) {
      button.setAttribute('aria-pressed', button.getAttribute('data-psi-theme') === theme ? 'true' : 'false');
    });
    if (themeLabel) { themeLabel.textContent = theme; }
    if (footerThemeLabel) { footerThemeLabel.textContent = theme; }
    if (persist) { try { window.localStorage.setItem('psi-report-theme', theme); } catch (ignore) { } }
  }

  var initialTheme = root.getAttribute('data-theme') || 'Auto';
  try {
    var savedTheme = window.localStorage.getItem('psi-report-theme');
    if (validThemes.indexOf(savedTheme) !== -1) { initialTheme = savedTheme; }
  } catch (ignore) { }
  setTheme(initialTheme, false);
  themeButtons.forEach(function (button) {
    button.addEventListener('click', function () { setTheme(button.getAttribute('data-psi-theme'), true); });
  });

  var navigationStack = document.querySelector('[data-psi-navigation-stack]');
  function navigationThreshold() {
    var height = navigationStack ? Math.ceil(navigationStack.getBoundingClientRect().height) : 0;
    var offset = height + 12;
    root.style.setProperty('--psi-navigation-offset', offset + 'px');
    return offset;
  }

  function revealNavigationLink(navigation, link) {
    if (!navigation || !link) { return; }
    var left = link.offsetLeft;
    var right = left + link.offsetWidth;
    if (left < navigation.scrollLeft) { navigation.scrollLeft = left; }
    else if (right > navigation.scrollLeft + navigation.clientWidth) {
      navigation.scrollLeft = right - navigation.clientWidth;
    }
  }

  var reportNav = document.querySelector('.psi-report-nav');
  if (reportNav) {
    var reportLinks = Array.prototype.slice.call(reportNav.querySelectorAll('[data-psi-nav-section]'));
    var reportSections = reportLinks.map(function (link) {
      return document.getElementById(link.getAttribute('data-psi-nav-section'));
    }).filter(function (section) { return !!section; });
    var sectionNavUpdatePending = false;
    function setActiveReportSection(sectionId) {
      reportLinks.forEach(function (link) {
        if (link.getAttribute('data-psi-nav-section') === sectionId) {
          link.setAttribute('aria-current', 'location');
          revealNavigationLink(reportNav, link);
        } else { link.removeAttribute('aria-current'); }
      });
    }
    function updateReportNavigation() {
      sectionNavUpdatePending = false;
      var current = reportSections.length ? reportSections[0] : null;
      var threshold = navigationThreshold();
      reportSections.forEach(function (section) {
        if (section.getBoundingClientRect().top <= threshold) { current = section; }
      });
      if (reportSections.length && window.innerHeight + window.pageYOffset >= document.documentElement.scrollHeight - 2) {
        current = reportSections[reportSections.length - 1];
      }
      if (current) { setActiveReportSection(current.id); }
    }
    function scheduleReportNavigation() {
      if (sectionNavUpdatePending) { return; }
      sectionNavUpdatePending = true;
      window.requestAnimationFrame(updateReportNavigation);
    }
    reportLinks.forEach(function (link) {
      link.addEventListener('click', function () {
        setActiveReportSection(link.getAttribute('data-psi-nav-section'));
        scheduleReportNavigation();
      });
    });
    window.addEventListener('scroll', scheduleReportNavigation, { passive: true });
    window.addEventListener('resize', scheduleReportNavigation);
    window.addEventListener('hashchange', scheduleReportNavigation);
    window.addEventListener('psi:layout-change', scheduleReportNavigation);
    if (navigationStack) {
      navigationStack.querySelectorAll('details').forEach(function (details) {
        details.addEventListener('toggle', scheduleReportNavigation);
      });
    }
    updateReportNavigation();
  }

  var assessmentNav = document.querySelector('.psi-assessment-nav');
  if (assessmentNav) {
    var assessmentLinks = Array.prototype.slice.call(assessmentNav.querySelectorAll('[data-psi-nav-assessment]'));
    var assessmentSections = Array.prototype.slice.call(document.querySelectorAll('.psi-section[data-psi-assessment-key], .psi-section[data-psi-overview]'));
    var navUpdatePending = false;
    function updateAssessmentNavigation() {
      navUpdatePending = false;
      var current = assessmentSections.length ? assessmentSections[0] : null;
      var threshold = navigationThreshold();
      assessmentSections.forEach(function (section) {
        if (section.getBoundingClientRect().top <= threshold) { current = section; }
      });
      var currentId = current && current.hasAttribute('data-psi-overview') ? 'overview' :
        (current ? current.getAttribute('data-psi-assessment-key') : null);
      assessmentLinks.forEach(function (link) {
        if (link.getAttribute('data-psi-nav-assessment') === currentId) {
          link.setAttribute('aria-current', 'location');
          revealNavigationLink(assessmentNav, link);
        } else { link.removeAttribute('aria-current'); }
      });
    }
    function scheduleAssessmentNavigation() {
      if (navUpdatePending) { return; }
      navUpdatePending = true;
      window.requestAnimationFrame(updateAssessmentNavigation);
    }
    window.addEventListener('scroll', scheduleAssessmentNavigation, { passive: true });
    window.addEventListener('resize', scheduleAssessmentNavigation);
    window.addEventListener('hashchange', scheduleAssessmentNavigation);
    window.addEventListener('psi:layout-change', scheduleAssessmentNavigation);
    if (navigationStack) {
      navigationStack.querySelectorAll('details').forEach(function (details) {
        details.addEventListener('toggle', scheduleAssessmentNavigation);
      });
    }
    updateAssessmentNavigation();
  }

  var findingStatusOrder = ['Critical', 'Warning', 'Unknown', 'NotChecked', 'Informational', 'Healthy', 'Neutral'];

  function findingStatusRank(status) {
    var rank = findingStatusOrder.indexOf(status);
    return rank === -1 ? findingStatusOrder.indexOf('Unknown') : rank;
  }

  function findingStatusClass(status) {
    return status === 'NotChecked' ? 'not-checked' : String(status || 'Unknown').toLowerCase();
  }

  function updateFindingRows(section) {
    Array.prototype.slice.call(section.querySelectorAll('.psi-row')).forEach(function (row) {
      var components = Array.prototype.slice.call(row.children);
      var findingCards = components.filter(function (component) { return component.hasAttribute('data-psi-finding-card'); });
      if (!findingCards.length) { return; }
      var hasUnrelatedContent = components.some(function (component) { return !component.hasAttribute('data-psi-finding-card'); });
      var hideRow = !hasUnrelatedContent && findingCards.every(function (card) { return card.hidden; });
      if (hideRow) {
        row.hidden = true;
        row.setAttribute('data-psi-finding-row-hidden', 'true');
      } else if (row.hasAttribute('data-psi-finding-row-hidden')) {
        row.hidden = false;
        row.removeAttribute('data-psi-finding-row-hidden');
      }
    });
  }

  function initializeFindingsExplorer(section, sectionIndex) {
    var cards = Array.prototype.slice.call(section.querySelectorAll('[data-psi-finding-card]'));
    if (cards.length < 2) { return; }
    var groups = [];
    cards.forEach(function (card) {
      var rawValue = card.getAttribute('data-psi-affected-object') || '';
      var value = rawValue.trim() ? rawValue : '';
      var group = groups.filter(function (item) { return item.value === value; })[0];
      if (!group) {
        group = { value: value, label: value || 'Unspecified', cards: [], priority: findingStatusOrder.length };
        groups.push(group);
      }
      group.cards.push(card);
      group.priority = Math.min(group.priority, findingStatusRank(card.getAttribute('data-psi-finding-status')));
    });
    var distinctNonEmpty = groups.filter(function (group) { return group.value !== ''; });
    if (distinctNonEmpty.length < 2) { return; }
    groups.sort(function (left, right) {
      if (left.priority !== right.priority) { return left.priority - right.priority; }
      if (left.cards.length !== right.cards.length) { return right.cards.length - left.cards.length; }
      return left.label.localeCompare(right.label, undefined, { numeric: true, sensitivity: 'base' });
    });

    var explorer = document.createElement('div');
    explorer.className = 'psi-findings-explorer';
    explorer.setAttribute('data-psi-findings-explorer', 'true');
    explorer.setAttribute('role', 'group');
    explorer.setAttribute('aria-label', 'Findings explorer');
    var control = document.createElement('label');
    control.className = 'psi-findings-explorer-control';
    var caption = document.createElement('span');
    caption.textContent = 'Affected object';
    var select = document.createElement('select');
    select.setAttribute('data-psi-finding-select', 'true');
    groups.forEach(function (group, groupIndex) {
      var option = document.createElement('option');
      option.value = String(groupIndex);
      option.textContent = group.label + ' (' + group.cards.length + ')';
      select.appendChild(option);
    });
    var allOption = document.createElement('option');
    allOption.value = 'all';
    allOption.textContent = 'All findings (' + cards.length + ')';
    select.appendChild(allOption);
    control.appendChild(caption);
    control.appendChild(select);

    var summaryId = (section.id || 'psi-section-' + sectionIndex) + '-findings-summary';
    var summary = document.createElement('div');
    summary.className = 'psi-findings-explorer-summary';
    summary.id = summaryId;
    summary.setAttribute('data-psi-finding-summary', 'true');
    summary.setAttribute('aria-live', 'polite');
    summary.setAttribute('aria-atomic', 'true');
    select.setAttribute('aria-describedby', summaryId);
    var countSummary = document.createElement('span');
    countSummary.setAttribute('data-psi-finding-count', 'true');
    var statusSummary = document.createElement('span');
    statusSummary.className = 'psi-findings-status-summary';
    statusSummary.setAttribute('data-psi-finding-status-summary', 'true');
    summary.appendChild(countSummary);
    summary.appendChild(statusSummary);
    explorer.appendChild(control);
    explorer.appendChild(summary);

    var firstRow = cards[0].closest('.psi-row');
    section.insertBefore(explorer, firstRow || cards[0]);

    function updateSummary(visibleCards, showAll) {
      countSummary.textContent = showAll ? 'Showing all ' + cards.length + ' findings' :
        'Showing ' + visibleCards.length + ' of ' + cards.length + ' findings';
      var counts = {};
      visibleCards.forEach(function (card) {
        var status = card.getAttribute('data-psi-finding-status') || 'Unknown';
        counts[status] = (counts[status] || 0) + 1;
      });
      statusSummary.textContent = '';
      var represented = findingStatusOrder.filter(function (status) { return counts[status]; });
      represented.forEach(function (status, statusIndex) {
        if (statusIndex) {
          var separator = document.createElement('span');
          separator.className = 'psi-findings-status-separator';
          separator.textContent = '\u00b7';
          separator.setAttribute('aria-hidden', 'true');
          statusSummary.appendChild(separator);
        }
        var statusCount = document.createElement('span');
        statusCount.className = 'psi-findings-status-count psi-status-' + findingStatusClass(status);
        statusCount.textContent = counts[status] + ' ' + status;
        statusSummary.appendChild(statusCount);
      });
    }

    function applyFindingSelection() {
      var showAll = select.value === 'all';
      var selectedGroup = showAll ? null : groups[Number(select.value)];
      var visibleCards = [];
      cards.forEach(function (card) {
        var rawValue = card.getAttribute('data-psi-affected-object') || '';
        var value = rawValue.trim() ? rawValue : '';
        var show = showAll || (selectedGroup && value === selectedGroup.value);
        card.hidden = !show;
        if (show) { visibleCards.push(card); }
      });
      updateFindingRows(section);
      updateSummary(visibleCards, showAll);
      window.dispatchEvent(new CustomEvent('psi:layout-change'));
    }

    select.addEventListener('change', applyFindingSelection);
    applyFindingSelection();
  }

  Array.prototype.slice.call(document.querySelectorAll('.psi-section')).forEach(function (section, sectionIndex) {
    initializeFindingsExplorer(section, sectionIndex);
  });

  document.querySelectorAll('[data-psi-filter-action]').forEach(function (trigger) {
    trigger.addEventListener('click', function () {
      var action;
      try { action = JSON.parse(trigger.getAttribute('data-psi-filter-action') || '{}'); } catch (ignore) { return; }
      if (!action.tableId && !action.Table) { return; }
      document.dispatchEvent(new CustomEvent('psi:apply-filter', { detail: {
        tableId: action.tableId || action.Table, property: action.property || action.Property,
        value: typeof action.value !== 'undefined' ? action.value : action.Value,
        values: action.values || action.Values, source: 'kpi'
      } }));
    });
  });

  document.querySelectorAll('button.psi-kpi-card[data-action]').forEach(function (trigger) {
    if (trigger.hasAttribute('data-psi-filter-action') || trigger.hasAttribute('data-psi-drilldown')) { return; }
    trigger.addEventListener('click', function () {
      var action;
      try { action = JSON.parse(trigger.getAttribute('data-action') || '{}'); } catch (ignore) { return; }
      if (!action || typeof action !== 'object' || typeof action.Target !== 'string' || typeof action.Type !== 'string') { return; }
      var actionType = action.Type.toLowerCase();
      if (actionType === 'scrollto') {
        var target = document.getElementById(action.Target);
        if (target) { target.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
      } else if (actionType === 'filtertable' && typeof action.Property === 'string' &&
                 action.Property.trim() && (typeof action.Value === 'string' || typeof action.Value === 'number' || typeof action.Value === 'boolean')) {
        var table = document.getElementById(action.Target);
        if (!table || table.getAttribute('data-psi-table') !== 'true') { return; }
        document.dispatchEvent(new CustomEvent('psi:apply-filter', { detail: {
          tableId: action.Target, property: action.Property, value: action.Value, source: 'kpi-action'
        } }));
      }
    });
  });

  document.addEventListener('click', function (event) {
    var point = event.target.closest ? event.target.closest('[data-psi-chart-filter]') : null;
    if (point) { applyChartFilter(point); return; }
    var insight = event.target.closest ? event.target.closest('[data-psi-insight]') : null;
    if (insight) { openInsight(insight); }
  });
  document.addEventListener('keydown', function (event) {
    var point = event.target.closest ? event.target.closest('[data-psi-chart-filter]') : null;
    if (point && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); applyChartFilter(point); }
  });

  function applyChartFilter(point) {
    var action;
    try { action = JSON.parse(point.getAttribute('data-psi-chart-filter') || '{}'); } catch (ignore) { return; }
    if (!action.tableId || !action.property || typeof action.value === 'undefined') { return; }
    document.dispatchEvent(new CustomEvent('psi:apply-filter', { detail: {
      tableId: action.tableId, property: action.property, value: action.value, source: 'chart'
    } }));
  }

  var backdrop = document.querySelector('[data-psi-dialog-backdrop]');
  if (!backdrop) { return; }
  var dialog = backdrop.querySelector('[role="dialog"]');
  var title = backdrop.querySelector('[data-psi-dialog-title]');
  var description = backdrop.querySelector('[data-psi-dialog-description]');
  var summary = backdrop.querySelector('[data-psi-dialog-summary]');
  var search = backdrop.querySelector('[data-psi-dialog-search]');
  var filterHost = backdrop.querySelector('[data-psi-dialog-filters]');
  var filterDisclosure = backdrop.querySelector('[data-psi-dialog-filter-disclosure]');
  var filterSummary = backdrop.querySelector('[data-psi-dialog-filter-summary]');
  var head = backdrop.querySelector('[data-psi-dialog-head]');
  var body = backdrop.querySelector('[data-psi-dialog-body]');
  var empty = backdrop.querySelector('[data-psi-dialog-empty]');
  var pagination = backdrop.querySelector('[data-psi-dialog-pagination]');
  var pageLabel = backdrop.querySelector('[data-psi-dialog-page]');
  var previous = backdrop.querySelector('[data-psi-dialog-previous]');
  var next = backdrop.querySelector('[data-psi-dialog-next]');
  var applyButton = backdrop.querySelector('[data-psi-dialog-apply]');
  var exportToolbar = backdrop.querySelector('[data-psi-export-toolbar]');
  var activeTrigger = null;
  var currentDefinition = null;
  var currentContextConditions = [];
  var records = [];
  var filteredRecords = [];
  var columns = [];
  var exportColumns = [];
  var pageSize = 25;
  var page = 1;
  var sortColumn = '';
  var sortDirection = 1;
  var legacyMode = false;
  var filterControls = [];

  function displayValue(value) {
    if (value === null || typeof value === 'undefined' || value === '') { return '\u2014'; }
    if (typeof value === 'object') { try { return JSON.stringify(value); } catch (ignore) { return String(value); } }
    return String(value);
  }
  function recordValue(record, column) {
    if (record && record.values) { return record.values[column]; }
    return record && typeof record === 'object' ? record[column] : record;
  }
  function createCell(value) {
    var cell = document.createElement('td');
    var text = displayValue(value);
    var status = window.PSIStatus.normalize(text);
    if (status) {
      var badge = document.createElement('span');
      badge.className = 'psi-status-badge psi-status-' + window.PSIStatus.classSuffix(status);
      badge.textContent = status;
      cell.appendChild(badge);
    } else { cell.textContent = text; }
    return cell;
  }
  function currentConditions() {
    var conditions = (currentDefinition && currentDefinition.conditions ? currentDefinition.conditions : []).concat(currentContextConditions);
    filterControls.forEach(function (control) {
      if (control.value) { conditions.push({ Property: control.getAttribute('data-property'), Operator: 'Equals', Value: control.value }); }
    });
    return conditions;
  }
  function buildFilters() {
    filterHost.textContent = '';
    filterControls = [];
    if (filterDisclosure) { filterDisclosure.open = false; }
    if (legacyMode || !records.length) {
      if (filterDisclosure) { filterDisclosure.hidden = true; }
      return;
    }
    columns.forEach(function (column) {
      var values = [];
      records.forEach(function (record) {
        var value = recordValue(record, column);
        if (value !== null && typeof value !== 'undefined' && String(value).trim() !== '' && values.indexOf(String(value)) === -1) { values.push(String(value)); }
      });
      if (values.length < 2 || values.length > 24) { return; }
      values.sort(function (a, b) { return a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }); });
      var label = document.createElement('label');
      label.className = 'psi-dialog-filter';
      var caption = document.createElement('span');
      caption.textContent = currentDefinition.labels && currentDefinition.labels[column] ? currentDefinition.labels[column] : column;
      var select = document.createElement('select');
      select.setAttribute('data-property', column);
      var all = document.createElement('option'); all.value = ''; all.textContent = 'All'; select.appendChild(all);
      values.forEach(function (value) { var option = document.createElement('option'); option.value = value; option.textContent = value; select.appendChild(option); });
      select.addEventListener('change', function () { page = 1; update(); });
      label.appendChild(caption); label.appendChild(select); filterHost.appendChild(label); filterControls.push(select);
    });
    if (filterDisclosure) { filterDisclosure.hidden = filterControls.length === 0; }
    if (filterSummary) { filterSummary.textContent = 'Filters (' + filterControls.length + ')'; }
  }
  function matchesAll(record, conditions) {
    return !window.PSIDataEngine || !window.PSIDataEngine.matches || window.PSIDataEngine.matches(record, conditions);
  }
  function update() {
    var query = search.value.trim().toLocaleLowerCase();
    filteredRecords = records.filter(function (record) {
      if (!matchesAll(record, currentConditions())) { return false; }
      if (query) {
        var searchable = columns.map(function (column) { return displayValue(recordValue(record, column)); }).join(' ').toLocaleLowerCase();
        if (searchable.indexOf(query) === -1) { return false; }
      }
      return true;
    });
    if (sortColumn) {
      filteredRecords.sort(function (left, right) {
        var a = displayValue(recordValue(left, sortColumn)); var b = displayValue(recordValue(right, sortColumn));
        var na = Number(a); var nb = Number(b);
        var compare = a !== '' && b !== '' && Number.isFinite(na) && Number.isFinite(nb) ? na - nb : a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });
        return compare * sortDirection;
      });
    }
    var pages = Math.max(1, Math.ceil(filteredRecords.length / pageSize));
    page = Math.min(page, pages);
    var start = (page - 1) * pageSize;
    var pageRecords = filteredRecords.slice(start, start + pageSize);
    renderRows(pageRecords);
    summary.textContent = filteredRecords.length + ' matching records \u00b7 showing ' + (filteredRecords.length ? (start + 1) + '\u2013' + Math.min(start + pageSize, filteredRecords.length) : '0') + ' of ' + filteredRecords.length;
    empty.hidden = filteredRecords.length > 0;
    pagination.hidden = filteredRecords.length <= pageSize;
    pageLabel.textContent = 'Page ' + page + ' of ' + pages;
    previous.disabled = page <= 1; next.disabled = page >= pages;
  }
  function renderRows(selectedRecords) {
    body.textContent = '';
    selectedRecords.forEach(function (record) {
      var row = document.createElement('tr');
      columns.forEach(function (column) { row.appendChild(createCell(recordValue(record, column))); });
      body.appendChild(row);
    });
  }
  function buildHeader() {
    head.textContent = '';
    var row = document.createElement('tr');
    columns.forEach(function (column) {
      var cell = document.createElement('th'); cell.scope = 'col';
      var label = currentDefinition && currentDefinition.labels && currentDefinition.labels[column] ? currentDefinition.labels[column] : column;
      var button = document.createElement('button'); button.type = 'button'; button.textContent = label + (sortColumn === column ? (sortDirection > 0 ? ' \u25b2' : ' \u25bc') : '');
      button.addEventListener('click', function () { if (sortColumn === column) { sortDirection *= -1; } else { sortColumn = column; sortDirection = 1; } buildHeader(); update(); });
      cell.appendChild(button); row.appendChild(cell);
    });
    head.appendChild(row);
  }
  function openInsight(trigger) {
    var definition;
    try { definition = JSON.parse(trigger.getAttribute('data-psi-insight') || '{}'); } catch (ignore) { return; }
    if (!definition.tableId || !window.PSIDataEngine || !window.PSIDataEngine.getRecords) { return; }
    var dataset = window.PSIDataEngine.getRecords(definition.tableId);
    var context = window.PSIDataEngine.getContext ? window.PSIDataEngine.getContext(definition.tableId) : { conditions: [], searchText: '' };
    currentDefinition = definition;
    currentContextConditions = context.conditions || [];
    var combinedConditions = (definition.conditions || []).concat(currentContextConditions, context.controlConditions || []);
    records = dataset.filter(function (record) {
      if (!matchesAll(record, combinedConditions)) { return false; }
      return !context.searchText || record.element.textContent.toLocaleLowerCase().indexOf(context.searchText) !== -1;
    });
    var visibleColumns = [];
    if (definition.useVisibleColumns) {
      var tableWidget = document.getElementById(definition.tableId);
      if (tableWidget) {
        visibleColumns = Array.prototype.slice.call(tableWidget.querySelectorAll('thead th[data-psi-column]')).map(function (header) {
          return header.getAttribute('data-psi-column');
        });
      }
    }
    var requestedColumns = (definition.evidenceColumns || []).length ? definition.evidenceColumns : visibleColumns;
    var requestedExportColumns = (definition.exportColumns || []).length ? definition.exportColumns : (definition.useVisibleColumns ? requestedColumns : []);
    columns = requestedColumns.filter(function (column) { return dataset.length === 0 || Object.prototype.hasOwnProperty.call(dataset[0].values, column); });
    exportColumns = requestedExportColumns.filter(function (column) { return dataset.length === 0 || Object.prototype.hasOwnProperty.call(dataset[0].values, column); });
    legacyMode = false; activeTrigger = trigger; sortColumn = ''; sortDirection = 1; page = 1;
    title.textContent = trigger.getAttribute('data-psi-detail-title') || 'Evidence';
    var descriptionText = trigger.getAttribute('data-psi-evidence-description') || (trigger.querySelector('.psi-insight-description') ? trigger.querySelector('.psi-insight-description').textContent : '');
    if ((combinedConditions.length > (definition.conditions || []).length || context.searchText) && descriptionText) {
      descriptionText += ' Evidence also reflects the inventory filters and search already in use.';
    }
    description.textContent = descriptionText;
    applyButton.hidden = !(definition.conditions && definition.conditions.length);
    if (exportToolbar) { exportToolbar.hidden = exportColumns.length === 0; }
    buildFilters(); buildHeader(); backdrop.hidden = false; document.body.classList.add('psi-dialog-open'); search.value = ''; update(); dialog.focus();
  }
  function openLegacy(trigger) {
    try { records = JSON.parse(trigger.getAttribute('data-psi-records') || '[]'); } catch (ignore) { records = []; }
    if (!Array.isArray(records)) { records = records == null ? [] : [records]; }
    legacyMode = true; currentDefinition = null; currentContextConditions = []; activeTrigger = trigger; columns = [];
    records.forEach(function (record) { if (record && typeof record === 'object') { Object.keys(record).forEach(function (key) { if (columns.indexOf(key) === -1) { columns.push(key); } }); } });
    if (!columns.length && records.length) { columns = ['Value']; }
    exportColumns = []; title.textContent = trigger.getAttribute('data-psi-detail-title') || 'Details'; description.textContent = '';
    applyButton.hidden = true; if (exportToolbar) { exportToolbar.hidden = true; } buildHeader(); backdrop.hidden = false; document.body.classList.add('psi-dialog-open'); search.value = ''; update(); dialog.focus();
  }
  function closeDialog() {
    if (backdrop.hidden) { return; }
    backdrop.hidden = true; document.body.classList.remove('psi-dialog-open');
    if (activeTrigger) { activeTrigger.focus(); }
  }
  if (exportToolbar && window.PSIExport) {
    window.PSIExport.attachToolbar(exportToolbar, function () {
      return {
        records: filteredRecords,
        columns: exportColumns,
        labels: currentDefinition ? currentDefinition.labels || {} : {},
        reportTitle: document.querySelector('h1') ? document.querySelector('h1').textContent : 'Report',
        contextTitle: title.textContent || 'Evidence',
        print: function () {
          renderRows(filteredRecords);
          document.body.classList.add('psi-print-evidence');
          var restore = function () {
            document.body.classList.remove('psi-print-evidence');
            window.removeEventListener('afterprint', restore);
            update();
            };
            window.addEventListener('afterprint', restore);
            try { window.print(); } catch (error) { restore(); throw error; }
        },
        valueReader: recordValue
      };
    });
  }

  document.querySelectorAll('[data-psi-drilldown]').forEach(function (trigger) { trigger.addEventListener('click', function () { openLegacy(trigger); }); });
  backdrop.querySelectorAll('[data-psi-dialog-close]').forEach(function (button) { button.addEventListener('click', closeDialog); });
  backdrop.addEventListener('click', function (event) { if (event.target === backdrop) { closeDialog(); } });
  search.addEventListener('input', function () { page = 1; update(); });
  previous.addEventListener('click', function () { page = Math.max(1, page - 1); update(); });
  next.addEventListener('click', function () { page += 1; update(); });
  applyButton.addEventListener('click', function () {
    if (!currentDefinition) { return; }
    document.dispatchEvent(new CustomEvent('psi:apply-filter', { detail: { tableId: currentDefinition.tableId, conditions: currentConditions(), source: 'insight' } }));
  });
  document.addEventListener('keydown', function (event) {
    if (backdrop.hidden) { return; }
    if (event.key === 'Escape') { event.preventDefault(); closeDialog(); return; }
    if (event.key === 'Tab') {
      var focusable = Array.prototype.slice.call(dialog.querySelectorAll('button:not([disabled]):not([hidden]), input:not([disabled]), select:not([disabled]), [tabindex="0"]')).filter(function (element) { return !element.closest('[hidden]'); });
      if (!focusable.length) { return; }
      var first = focusable[0], last = focusable[focusable.length - 1];
      if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog)) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });
}());
