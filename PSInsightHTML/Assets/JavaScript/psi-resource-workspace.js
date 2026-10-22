(function () {
  'use strict';
  var shell = document.querySelector('.psi-app-shell');
  var explorer = document.querySelector('[data-psi-resource-explorer]');
  if (!shell || !explorer) { return; }
  var nodes = Array.prototype.slice.call(explorer.querySelectorAll('[data-psi-resource-node]'));
  var byId = {};
  nodes.forEach(function (node) { byId[node.getAttribute('data-psi-resource-node')] = node; });
  var search = explorer.querySelector('[data-psi-resource-search]');
  var empty = explorer.querySelector('[data-psi-resource-empty]');
  var header = document.querySelector('[data-psi-resource-header]');
  var inspector = document.querySelector('[data-psi-context-inspector]');
  var dataElement = document.getElementById('psi-resource-data');
  var details = dataElement ? JSON.parse(dataElement.textContent) : {};
  var tabs = inspector ? inspector.querySelector('[data-psi-inspector-tabs]') : null;
  var body = inspector ? inspector.querySelector('[data-psi-inspector-body]') : null;
  var selected = nodes.filter(function (node) { return node.getAttribute('aria-selected') === 'true'; })[0];
  var activeTab = 'Properties';
  var explorerButton = document.querySelector('[data-psi-resource-restore]');
  var inspectorButton = document.querySelector('[data-psi-inspector-restore]');
  var closeExplorer = explorer.querySelector('[data-psi-resource-collapse]');
  var closeInspector = inspector ? inspector.querySelector('[data-psi-inspector-collapse]') : null;

  function addText(parent, tag, value, className) {
    var element = document.createElement(tag);
    if (className) { element.className = className; }
    element.textContent = value == null || value === '' ? '\u2014' : String(value);
    parent.appendChild(element);
    return element;
  }
  function statusClass(value) { return 'psi-status-' + String(value || 'Unknown').toLowerCase(); }
  function decorateStatus(element, value, className) {
    var key = String(value || 'Unknown').toLowerCase();
    var tone = ['healthy', 'ready'].indexOf(key) >= 0 ? 'healthy' :
      ['warning', 'review'].indexOf(key) >= 0 ? 'warning' :
      ['critical', 'blocked'].indexOf(key) >= 0 ? 'critical' : 'info';
    var template = document.querySelector('[data-psi-resource-status-icon="' + tone + '"]');
    element.className = className + ' ' + statusClass(value);
    element.replaceChildren();
    if (template) { element.appendChild(template.content.firstElementChild.cloneNode(true)); }
    element.appendChild(document.createTextNode(String(value || 'Unknown')));
  }
  function isMobileExplorer() { return window.matchMedia('(max-width: 900px)').matches; }
  function setExplorerOpen(open) {
    if (isMobileExplorer()) {
      shell.classList.toggle('psi-resource-open', open);
      shell.classList.remove('psi-resource-hidden');
    } else {
      shell.classList.toggle('psi-resource-hidden', !open);
      shell.classList.remove('psi-resource-open');
    }
    explorerButton.setAttribute('aria-expanded', String(open));
    closeExplorer.setAttribute('aria-expanded', String(open));
    if (open && isMobileExplorer()) { search.focus(); }
    if (!open && isMobileExplorer()) { explorerButton.focus(); }
  }
  function setInspectorOpen(open) {
    if (!inspector) { return; }
    shell.classList.toggle('psi-inspector-hidden', !open);
    inspectorButton.setAttribute('aria-expanded', String(open));
    closeInspector.setAttribute('aria-expanded', String(open));
    if (!open) { inspectorButton.focus(); }
  }
  function ancestors(node) {
    var result = [], parentId = node.getAttribute('data-psi-resource-parent');
    while (parentId && byId[parentId]) {
      result.push(byId[parentId]);
      parentId = byId[parentId].getAttribute('data-psi-resource-parent');
    }
    return result;
  }
  function updateTree() {
    var query = search.value.trim().toLowerCase(), visible = {}, count = 0;
    if (query) {
      nodes.forEach(function (node) {
        if (node.querySelector('.psi-resource-label').textContent.toLowerCase().indexOf(query) < 0) { return; }
        visible[node.getAttribute('data-psi-resource-node')] = true;
        ancestors(node).forEach(function (parent) {
          visible[parent.getAttribute('data-psi-resource-node')] = true;
          if (parent.hasAttribute('aria-expanded')) { parent.setAttribute('aria-expanded', 'true'); }
        });
      });
    }
    nodes.forEach(function (node) {
      var permitted = query ? !!visible[node.getAttribute('data-psi-resource-node')] :
        ancestors(node).every(function (parent) { return parent.getAttribute('aria-expanded') === 'true'; });
      node.hidden = !permitted;
      if (permitted) { count++; }
    });
    empty.hidden = count > 0;
  }
  function renderHeader(node, record) {
    if (!header) { return; }
    var icon = header.querySelector('[data-psi-resource-header-icon]');
    var selectedIcon = node.querySelector('.psi-resource-icon .psi-icon-filled') || node.querySelector('.psi-resource-icon .psi-icon-regular');
    icon.replaceChildren(selectedIcon.cloneNode(true));
    var breadcrumb = record && record.Breadcrumb && record.Breadcrumb.length ? record.Breadcrumb.join(' / ') : (node.getAttribute('data-psi-resource-type') || 'Resource');
    header.querySelector('[data-psi-resource-header-breadcrumb]').textContent = breadcrumb;
    header.querySelector('[data-psi-resource-header-title]').textContent = record && record.Title ? record.Title : node.querySelector('.psi-resource-label').textContent;
    header.querySelector('[data-psi-resource-header-subtitle]').textContent = record && record.Subtitle ? record.Subtitle : '';
    var status = record && record.Status ? record.Status : node.getAttribute('data-psi-resource-status');
    var statusElement = header.querySelector('[data-psi-resource-header-status]');
    decorateStatus(statusElement, status, 'psi-resource-header-status');
    var actions = header.querySelector('[data-psi-resource-header-actions]');
    actions.replaceChildren();
    (record && record.Actions || []).forEach(function (action) {
      var button = addText(actions, 'button', action.Label);
      button.type = 'button';
      button.addEventListener('click', function () {
        if (action.ResourceId && byId[action.ResourceId]) { select(byId[action.ResourceId], true); }
        if (action.TargetView) { openView(action.TargetView); }
      });
    });
    var tags = header.querySelector('[data-psi-resource-header-tags]');
    tags.replaceChildren();
    (record && record.Metadata || []).forEach(function (entry) {
      addText(tags, 'span', entry.Label + ': ' + entry.Value);
    });
  }
  function renderPanel(record, section) {
    body.replaceChildren();
    var panel = document.createElement('div');
    panel.id = 'psi-inspector-panel';
    panel.setAttribute('role', 'tabpanel');
    panel.setAttribute('aria-labelledby', 'psi-inspector-tab-' + record.Id + '-' + section.Id);
    if (section.Id === 'Properties') {
      if (!record.Properties.length) { addText(panel, 'p', 'No properties available.', 'psi-inspector-empty'); }
      else {
        var list = document.createElement('dl');
        list.className = 'psi-inspector-fields';
        record.Properties.forEach(function (field) {
          var row = document.createElement('div');
          addText(row, 'dt', field.Label);
          addText(row, 'dd', field.Value);
          list.appendChild(row);
        });
        panel.appendChild(list);
      }
    } else if (!section.Blocks.length) {
      addText(panel, 'p', 'No ' + section.Title.toLowerCase() + ' listed.', 'psi-inspector-empty');
    } else {
      section.Blocks.forEach(function (block) {
        var card = document.createElement('article');
        card.className = 'psi-inspector-block';
        if (block.Title) { addText(card, 'strong', block.Title); }
        if (block.Text) { addText(card, 'p', block.Text); }
        if (block.Status) { addText(card, 'small', 'Status: ' + block.Status); }
        if (block.ActionLabel && (block.ResourceId || block.TargetView)) {
          var action = addText(card, 'button', block.ActionLabel);
          action.type = 'button';
          action.addEventListener('click', function () {
            if (block.ResourceId && byId[block.ResourceId]) { select(byId[block.ResourceId], true); }
            if (block.TargetView) { openView(block.TargetView); }
          });
        }
        panel.appendChild(card);
      });
    }
    body.appendChild(panel);
  }
  function renderInspector(node, record) {
    if (!inspector) { return; }
    var title = record && record.Title ? record.Title : node.querySelector('.psi-resource-label').textContent;
    inspector.querySelector('[data-psi-inspector-title]').textContent = title;
    inspector.querySelector('[data-psi-inspector-subtitle]').textContent = record && record.Subtitle ? record.Subtitle : node.getAttribute('data-psi-resource-type');
    var status = record && record.Status ? record.Status : node.getAttribute('data-psi-resource-status');
    var statusElement = inspector.querySelector('[data-psi-inspector-status]');
    decorateStatus(statusElement, status, 'psi-inspector-status');
    tabs.replaceChildren();
    body.replaceChildren();
    if (!record) { addText(body, 'p', 'No inspector details are available for this resource.', 'psi-inspector-empty'); return; }
    var sections = [{ Id: 'Properties', Title: 'Properties', Blocks: [] }].concat(record.Sections || []);
    if (!sections.some(function (section) { return section.Id === activeTab; })) { activeTab = 'Properties'; }
    sections.forEach(function (section) {
      var tab = addText(tabs, 'button', section.Title);
      tab.id = 'psi-inspector-tab-' + record.Id + '-' + section.Id;
      tab.type = 'button';
      tab.setAttribute('role', 'tab');
      tab.setAttribute('aria-controls', 'psi-inspector-panel');
      tab.setAttribute('aria-selected', String(section.Id === activeTab));
      tab.tabIndex = section.Id === activeTab ? 0 : -1;
      tab.addEventListener('click', function () {
        activeTab = section.Id;
        Array.prototype.forEach.call(tabs.children, function (other) {
          var current = other === tab;
          other.setAttribute('aria-selected', String(current));
          other.tabIndex = current ? 0 : -1;
        });
        renderPanel(record, section);
      });
    });
    renderPanel(record, sections.filter(function (section) { return section.Id === activeTab; })[0]);
  }
  function openView(id) {
    var target = Array.prototype.slice.call(shell.querySelectorAll('[data-psi-app-view-target]')).filter(function (item) {
      return item.getAttribute('data-psi-app-view-target') === id;
    })[0];
    if (target) { target.click(); }
  }
  function select(node, moveFocus, openTarget) {
    if (!node || node.getAttribute('aria-disabled') === 'true') { return; }
    if (selected) { selected.setAttribute('aria-selected', 'false'); selected.tabIndex = -1; }
    selected = node;
    node.setAttribute('aria-selected', 'true');
    node.tabIndex = 0;
    if (moveFocus) { node.focus(); }
    var id = node.getAttribute('data-psi-resource-node');
    var record = details[id] || null;
    renderHeader(node, record);
    renderInspector(node, record);
    var view = node.getAttribute('data-psi-resource-target');
    if (view && openTarget !== false) { openView(view); }
    if (isMobileExplorer() && shell.classList.contains('psi-resource-open')) { setExplorerOpen(false); }
  }
  nodes.forEach(function (node) {
    node.addEventListener('click', function (event) {
      if (event.target.closest('.psi-resource-chevron') && node.hasAttribute('aria-expanded')) {
        node.setAttribute('aria-expanded', String(node.getAttribute('aria-expanded') !== 'true'));
        updateTree();
      } else { select(node, false); }
    });
    node.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowRight' && node.hasAttribute('aria-expanded')) { node.setAttribute('aria-expanded', 'true'); updateTree(); event.preventDefault(); return; }
      if (event.key === 'ArrowLeft') {
        if (node.getAttribute('aria-expanded') === 'true') { node.setAttribute('aria-expanded', 'false'); updateTree(); }
        else { var parent = byId[node.getAttribute('data-psi-resource-parent')]; if (parent) { parent.focus(); } }
        event.preventDefault(); return;
      }
      if (['ArrowDown', 'ArrowUp', 'Home', 'End'].indexOf(event.key) < 0) { return; }
      var visible = nodes.filter(function (entry) { return !entry.hidden; });
      var index = visible.indexOf(node), next = index;
      if (event.key === 'ArrowDown') { next = Math.min(index + 1, visible.length - 1); }
      if (event.key === 'ArrowUp') { next = Math.max(index - 1, 0); }
      if (event.key === 'Home') { next = 0; }
      if (event.key === 'End') { next = visible.length - 1; }
      if (visible[next]) { visible[next].focus(); }
      event.preventDefault();
    });
  });
  document.addEventListener('psi:relationship-select', function (event) {
    var resourceId = event.detail && event.detail.resourceId;
    if (resourceId && byId[resourceId]) { select(byId[resourceId], false, false); }
  });
  search.addEventListener('input', updateTree);
  explorerButton.addEventListener('click', function () {
    setExplorerOpen(isMobileExplorer() ? !shell.classList.contains('psi-resource-open') : shell.classList.contains('psi-resource-hidden'));
  });
  closeExplorer.addEventListener('click', function () { setExplorerOpen(false); });
  if (inspector) {
    inspectorButton.addEventListener('click', function () {
      if (window.matchMedia('(max-width: 1180px)').matches && !shell.classList.contains('psi-inspector-hidden')) {
        inspector.scrollIntoView({ block: 'start' });
      } else {
        setInspectorOpen(shell.classList.contains('psi-inspector-hidden'));
        if (window.matchMedia('(max-width: 1180px)').matches) { inspector.scrollIntoView({ block: 'start' }); }
      }
    });
    closeInspector.addEventListener('click', function () { setInspectorOpen(false); });
    tabs.addEventListener('keydown', function (event) {
      if (['ArrowRight', 'ArrowLeft', 'Home', 'End'].indexOf(event.key) < 0) { return; }
      var all = Array.prototype.slice.call(tabs.querySelectorAll('[role=tab]'));
      var current = all.indexOf(document.activeElement), next = current;
      if (event.key === 'ArrowRight') { next = (current + 1) % all.length; }
      if (event.key === 'ArrowLeft') { next = (current - 1 + all.length) % all.length; }
      if (event.key === 'Home') { next = 0; }
      if (event.key === 'End') { next = all.length - 1; }
      if (all[next]) { all[next].click(); all[next].focus(); }
      event.preventDefault();
    });
  }
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && shell.classList.contains('psi-resource-open')) { setExplorerOpen(false); }
  });
  document.addEventListener('click', function (event) {
    if (shell.classList.contains('psi-resource-open') && !explorer.contains(event.target) && !explorerButton.contains(event.target)) { setExplorerOpen(false); }
  });
  window.addEventListener('resize', function () {
    if (!isMobileExplorer()) { shell.classList.remove('psi-resource-open'); }
  });
  updateTree();
  if (selected) { select(selected, false); }
}());
