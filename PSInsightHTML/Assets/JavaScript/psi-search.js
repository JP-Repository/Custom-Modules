(function () {
  'use strict';
  var shell = document.querySelector('.psi-app-shell');
  var trigger = document.querySelector('[data-psi-global-search-trigger]');
  var backdrop = document.querySelector('[data-psi-global-search-backdrop]');
  var source = document.getElementById('psi-global-search-index');
  if (!shell || !trigger || !backdrop || !source || !window.PSIApplication) { return; }
  var input = backdrop.querySelector('[data-psi-global-search-input]');
  var results = backdrop.querySelector('[data-psi-global-search-results]');
  var summary = backdrop.querySelector('[data-psi-global-search-summary]');
  var closeButton = backdrop.querySelector('[data-psi-global-search-close]');
  var modeButtons = Array.prototype.slice.call(backdrop.querySelectorAll('[data-psi-global-mode]'));
  var index = JSON.parse(source.textContent);
  var mode = 'Search', active = 0, shown = [], opener = null, previousOverflow = '';
  var typeOrder = ['View', 'Check', 'Finding', 'Resource', 'Evidence', 'Exception'];
  var iconTemplates = {};
  Array.prototype.forEach.call(document.querySelectorAll('[data-psi-search-icon]'), function (template) {
    iconTemplates[template.getAttribute('data-psi-search-icon')] = template;
  });
  index.forEach(function (item) {
    item._title = item.Title.toLocaleLowerCase();
    item._id = item.Id.toLocaleLowerCase();
    item._keywords = (item.Keywords || '').toLocaleLowerCase();
    item._other = [item.Subtitle, item.Category, item.Status, item.Severity, item.EntityType].join(' ').toLocaleLowerCase();
    item._text = [item._title, item._id, item._keywords, item._other].join(' ');
  });
  function activeScope() { return shell.querySelector('[data-psi-app-view]:not([hidden])'); }
  function activeSearch() {
    var scope = activeScope();
    return scope && scope.querySelector('[data-psi-explorer-search], [data-psi-search]');
  }
  function filtersActive() {
    var scope = activeScope();
    if (!scope) { return false; }
    return Array.prototype.some.call(scope.querySelectorAll('[data-psi-explorer-search], [data-psi-search], [data-psi-explorer-filter], [data-psi-filter-property]'), function (control) {
      if (control.tagName === 'SELECT' && control.multiple) { return Array.prototype.some.call(control.selectedOptions, function (option) { return !!option.value; }); }
      return !!control.value;
    });
  }
  var commands = index.filter(function (item) { return item.EntityType === 'View'; }).map(function (view) {
    return { Id: 'view-' + view.Id, Title: 'Go to ' + view.Title, Keywords: view.Id + ' ' + view.Title,
      Description: view.Subtitle, Icon: 'View', ActionType: 'OpenView', Target: view.ViewId,
      Available: function () { return true; } };
  });
  ['Light', 'Dark', 'Auto'].forEach(function (theme) {
    commands.push({ Id: 'theme-' + theme.toLowerCase(), Title: 'Theme: ' + theme,
      Keywords: 'toggle use theme ' + theme, Description: 'Switch report color theme', Icon: 'View',
      ActionType: 'Theme', Target: theme, Available: function () { return true; } });
  });
  commands.push({ Id: 'open-export', Title: 'Open Export', Keywords: 'print download report',
    Description: 'Open report export options', Icon: 'Evidence', ActionType: 'OpenExport', Target: '',
    Available: function () { return !!shell.querySelector('[data-psi-export-scope="report"] [data-psi-export-trigger]'); } });
  commands.push({ Id: 'find-current', Title: 'Find in Current View', Keywords: 'local table collection search',
    Description: 'Focus the active view search', Icon: 'View', ActionType: 'FocusActiveTable', Target: '',
    Available: function () { return !!activeSearch(); } });
  commands.push({ Id: 'clear-filters', Title: 'Clear Current Filters', Keywords: 'reset table collection filters',
    Description: 'Reset search and filters in this view', Icon: 'View', ActionType: 'ClearFilters', Target: '',
    Available: filtersActive });
  function score(item, query) {
    var words = query.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
    if (!words.length) { return item.EntityType === 'View' ? 10 : -1; }
    if (!words.every(function (word) { return item._text.indexOf(word) !== -1; })) { return -1; }
    var q = words.join(' '), value = 0;
    if (item._title === q) { value = 120; }
    else if (item._title.indexOf(q) === 0) { value = 95; }
    else if (item._id === q) { value = 90; }
    else if (item._title.indexOf(q) !== -1) { value = 75; }
    else if (words.every(function (word) { return item._title.indexOf(word) !== -1; })) { value = 65; }
    else if (item._keywords.indexOf(q) !== -1) { value = 55; }
    else { value = 35; }
    if (/critical|blocked/i.test(item.Severity + ' ' + item.Status)) { value += 3; }
    else if (/warning|review/i.test(item.Severity + ' ' + item.Status)) { value += 2; }
    return value;
  }
  function rank(items, query) {
    return items.map(function (item, position) { return { item: item, score: score(item, query), position: position }; })
      .filter(function (entry) { return entry.score >= 0; })
      .sort(function (a, b) { return b.score - a.score || a.position - b.position; })
      .map(function (entry) { return entry.item; });
  }
  function commandResults(query) {
    var available = commands.filter(function (command) { return command.Available(); });
    var searchable = available.map(function (command) {
      return { record: command, EntityType: 'Command', Title: command.Title,
        _title: command.Title.toLocaleLowerCase(), _id: command.Id.toLocaleLowerCase(),
        _keywords: command.Keywords.toLocaleLowerCase(), _text: (command.Title + ' ' + command.Id + ' ' + command.Keywords + ' ' + command.Description).toLocaleLowerCase(),
        Status: '', Severity: '' };
    });
    return rank(searchable, query).map(function (item) { return item.record; });
  }
  function setMode(next) {
    mode = next;
    modeButtons.forEach(function (button) { button.setAttribute('aria-pressed', String(button.getAttribute('data-psi-global-mode') === mode)); });
    input.placeholder = mode === 'Commands' ? 'Type a command, such as dark or findings...' : 'Find a view, check, finding, resource...';
  }
  function appendText(parent, tag, className, value) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    node.textContent = value || '';
    parent.appendChild(node);
    return node;
  }
  function badgeClass(value) {
    if (/critical|blocked/i.test(value)) { return 'critical'; }
    if (/warning|review|pending/i.test(value)) { return 'warning'; }
    if (/ready|healthy|resolved|approved/i.test(value)) { return 'healthy'; }
    if (/not.?tested|unknown|not.?checked/i.test(value)) { return 'not-checked'; }
    return 'info';
  }
  function setActive(position) {
    if (!shown.length) { input.removeAttribute('aria-activedescendant'); return; }
    active = (position + shown.length) % shown.length;
    Array.prototype.forEach.call(results.querySelectorAll('[role="option"]'), function (option, number) {
      option.setAttribute('aria-selected', String(number === active));
      if (number === active) { option.scrollIntoView({ block: 'nearest' }); }
    });
    input.setAttribute('aria-activedescendant', 'psi-global-result-' + active);
  }
  function render() {
    var raw = input.value.trim(), commandMode = mode === 'Commands' || raw.charAt(0) === '>';
    var query = commandMode && raw.charAt(0) === '>' ? raw.slice(1).trim() : raw;
    setMode(commandMode ? 'Commands' : 'Search');
    var matches = commandMode ? commandResults(query) : rank(index, query);
    shown = matches.slice(0, 20);
    active = 0;
    results.replaceChildren();
    if (!shown.length) {
      appendText(results, 'p', 'psi-global-search-empty', query ? 'No results for "' + query + '". Try fewer words or search a view, check, finding, or resource.' : 'No commands are available here.');
      summary.textContent = 'No results';
      input.removeAttribute('aria-activedescendant');
      return;
    }
    var groups = {};
    shown.forEach(function (item, position) {
      var type = commandMode ? 'Command' : item.EntityType;
      if (!groups[type]) {
        var group = document.createElement('div'); group.className = 'psi-global-search-group'; group.setAttribute('role', 'group');
        group.setAttribute('aria-label', type === 'Command' ? 'Commands' : type + 's');
        appendText(group, 'h3', '', type === 'Command' ? 'Commands' : type + 's');
        results.appendChild(group); groups[type] = group;
      }
      var option = document.createElement('div'); option.id = 'psi-global-result-' + position;
      option.className = 'psi-global-search-result'; option.setAttribute('role', 'option');
      option.setAttribute('aria-selected', String(position === active)); option.setAttribute('data-psi-global-result', String(position));
      var icon = document.createElement('span'); icon.className = 'psi-global-search-icon'; icon.setAttribute('aria-hidden', 'true');
      var template = iconTemplates[type] || iconTemplates.View;
      if (template) { icon.appendChild(template.content.cloneNode(true)); }
      option.appendChild(icon);
      var copy = document.createElement('span'); copy.className = 'psi-global-search-copy';
      appendText(copy, 'strong', '', item.Title);
      var context = commandMode ? item.Description : [type, item.Category, item.Subtitle].filter(Boolean).join(' \u00b7 ');
      appendText(copy, 'small', '', context);
      option.appendChild(copy);
      var status = commandMode ? '' : (item.Severity || item.Status);
      if (status) { appendText(option, 'span', 'psi-status-badge psi-status-' + badgeClass(status), status); }
      groups[type].appendChild(option);
    });
    summary.textContent = shown.length + (matches.length > shown.length ? ' of ' + matches.length + ' matches. More matches available.' : ' results.');
    input.setAttribute('aria-activedescendant', 'psi-global-result-0');
  }
  function close(restoreFocus) {
    backdrop.hidden = true;
    document.body.style.overflow = previousOverflow;
    input.setAttribute('aria-expanded', 'false');
    if (restoreFocus && opener && opener.isConnected) { opener.focus(); }
  }
  function open(invoker, nextMode) {
    opener = invoker || document.activeElement || trigger;
    previousOverflow = document.body.style.overflow;
    backdrop.hidden = false;
    document.body.style.overflow = 'hidden';
    input.value = '';
    input.setAttribute('aria-expanded', 'true');
    setMode(nextMode || 'Search');
    render();
    input.focus();
  }
  function clearFilters() {
    var scope = activeScope();
    if (!scope) { return; }
    Array.prototype.forEach.call(scope.querySelectorAll('[data-psi-clear-filters]'), function (button) { button.click(); });
    Array.prototype.forEach.call(scope.querySelectorAll('[data-psi-explorer-search], [data-psi-search]'), function (control) {
      if (control.value) { control.value = ''; control.dispatchEvent(new Event('input', { bubbles: true })); }
    });
    Array.prototype.forEach.call(scope.querySelectorAll('[data-psi-explorer-filter], [data-psi-filter-property]'), function (control) {
      if (control.multiple) { Array.prototype.forEach.call(control.options, function (option) { option.selected = false; }); }
      else { control.value = ''; }
      control.dispatchEvent(new Event('change', { bubbles: true }));
    });
  }
  function choose(position) {
    var item = shown[position];
    if (!item) { return; }
    close(false);
    if (mode === 'Commands') {
      if (item.ActionType === 'OpenView') { window.PSIApplication.activateView(item.Target, true); }
      else if (item.ActionType === 'Theme') {
        var themeButton = shell.querySelector('[data-psi-theme="' + item.Target + '"]');
        themeButton.click(); themeButton.focus();
      }
      else if (item.ActionType === 'OpenExport') {
        var exportButton = shell.querySelector('[data-psi-export-scope="report"] [data-psi-export-trigger]');
        if (exportButton) { exportButton.click(); exportButton.focus(); }
      }
      else if (item.ActionType === 'FocusActiveTable') {
        var search = activeSearch(); if (search) { search.scrollIntoView({ block: 'center' }); search.focus(); }
      }
      else if (item.ActionType === 'ClearFilters') { clearFilters(); trigger.focus(); }
      return;
    }
    if (item.EntityType === 'View') { window.PSIApplication.activateView(item.ViewId, true); return; }
    if (!window.PSIApplication.selectEntity(item.ViewId, item.EntityType, item.TargetId)) { trigger.focus(); }
  }
  trigger.addEventListener('click', function () { open(trigger, 'Search'); });
  closeButton.addEventListener('click', function () { close(true); });
  backdrop.addEventListener('click', function (event) { if (event.target === backdrop) { close(true); } });
  results.addEventListener('click', function (event) {
    var option = event.target.closest('[data-psi-global-result]');
    if (option) { choose(Number(option.getAttribute('data-psi-global-result'))); }
  });
  modeButtons.forEach(function (button) {
    button.addEventListener('click', function () { setMode(button.getAttribute('data-psi-global-mode')); input.value = ''; render(); input.focus(); });
  });
  input.addEventListener('input', render);
  document.addEventListener('keydown', function (event) {
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === 'k') {
      event.preventDefault(); if (backdrop.hidden) { open(document.activeElement, 'Search'); } else { input.focus(); } return;
    }
    if (backdrop.hidden) { return; }
    if (event.key === 'Escape') { event.preventDefault(); close(true); return; }
    if (document.activeElement === input && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
      event.preventDefault(); setActive(active + (event.key === 'ArrowDown' ? 1 : -1)); return;
    }
    if (document.activeElement === input && event.key === 'Enter') { event.preventDefault(); choose(active); return; }
    if (event.key !== 'Tab') { return; }
    var focusable = [closeButton].concat(modeButtons, [input]);
    var first = focusable[0], last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  });
  window.PSIGlobalSearch = { count: index.length, indexBytes: source.textContent.length,
    search: function (query) { return rank(index, query); }, commands: function () { return commands.filter(function (item) { return item.Available(); }); }, open: open };
}());
