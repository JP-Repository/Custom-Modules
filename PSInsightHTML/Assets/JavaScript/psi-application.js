(function () {
  'use strict';
  var shell = document.querySelector('.psi-app-shell');
  if (!shell) { return; }
  var sidebar = shell.querySelector('.psi-app-sidebar');
  var toggle = shell.querySelector('[data-psi-app-toggle]');
  var closeButton = shell.querySelector('[data-psi-app-close]');
  var scrim = shell.querySelector('[data-psi-app-scrim]');
  var command = shell.querySelector('.psi-app-command');
  var links = Array.prototype.slice.call(sidebar.querySelectorAll('[data-psi-app-item]'));
  var mobile = window.matchMedia('(max-width: 900px)');
  var findTable = shell.querySelector('[data-psi-app-find-table]');
  var navigationUntil = 0;
  var multiView = document.documentElement.getAttribute('data-psi-workspace') === 'Views';
  var views = multiView ? Array.prototype.slice.call(shell.querySelectorAll('[data-psi-app-view]')) : [];
  var viewTitle = shell.querySelector('[data-psi-app-view-title]');
  var viewSubtitle = shell.querySelector('[data-psi-app-view-subtitle]');
  var contextTitle = shell.querySelector('[data-psi-app-context-title]');
  var viewCommands = Array.prototype.slice.call(shell.querySelectorAll('[data-psi-app-command-target]'));
  function activeSearch() {
    var scope = multiView ? shell.querySelector('[data-psi-app-view]:not([hidden])') : shell;
    return scope ? scope.querySelector('[data-psi-explorer-search], [data-psi-search]') : null;
  }
  function updateSearchAction() {
    if (!findTable || !multiView) { return; }
    findTable.disabled = !activeSearch();
    findTable.title = findTable.disabled ? 'Search is available in collection and table views' : 'Find in the active view';
  }

  if (findTable) {
    findTable.addEventListener('click', function () {
      var search = activeSearch();
      if (search) { search.scrollIntoView({ block: 'center' }); search.focus(); }
    });
  }
  function isOpen() { return shell.classList.contains('psi-app-nav-open'); }
  function closeNavigation(restoreFocus) {
    if (!isOpen()) { return; }
    shell.classList.remove('psi-app-nav-open');
    scrim.hidden = true;
    toggle.setAttribute('aria-expanded', 'false');
    toggle.setAttribute('aria-label', 'Open navigation');
    sidebar.removeAttribute('role');
    sidebar.removeAttribute('aria-modal');
    document.body.style.overflow = '';
    if (restoreFocus && mobile.matches) { toggle.focus(); }
  }
  function openNavigation() {
    if (!mobile.matches) { return; }
    shell.classList.add('psi-app-nav-open');
    scrim.hidden = false;
    toggle.setAttribute('aria-expanded', 'true');
    toggle.setAttribute('aria-label', 'Close navigation');
    sidebar.setAttribute('role', 'dialog');
    sidebar.setAttribute('aria-modal', 'true');
    document.body.style.overflow = 'hidden';
    window.requestAnimationFrame(function () { closeButton.focus(); });
  }
  function selectLink(target) {
    links.forEach(function (link) {
      var matches = multiView ? link.getAttribute('data-psi-app-view-target') === target : link.getAttribute('href') === '#' + target;
      if (matches) { link.setAttribute('aria-current', multiView ? 'page' : 'location'); }
      else { link.removeAttribute('aria-current'); }
    });
  }
  function activateView(id, moveFocus) {
    if (!multiView) { return false; }
    var active = views.filter(function (view) { return view.getAttribute('data-psi-app-view') === id; })[0];
    if (!active) { return false; }
    views.forEach(function (view) { view.hidden = view !== active; });
    selectLink(id);
    if (viewTitle) { viewTitle.textContent = active.getAttribute('data-psi-view-label') || ''; }
    if (viewSubtitle) { viewSubtitle.textContent = active.getAttribute('data-psi-view-description') || ''; }
    if (contextTitle) { contextTitle.textContent = active.getAttribute('data-psi-view-label') || ''; }
    viewCommands.forEach(function (button) { button.hidden = button.getAttribute('data-psi-app-command-view') !== id; });
    updateSearchAction();
    closeNavigation(false);
    window.scrollTo({ top: 0, behavior: 'auto' });
    if (moveFocus) { active.focus({ preventScroll: true }); }
    return true;
  }
  toggle.addEventListener('click', function () { if (isOpen()) { closeNavigation(true); } else { openNavigation(); } });
  closeButton.addEventListener('click', function () { closeNavigation(true); });
  scrim.addEventListener('click', function () { closeNavigation(true); });
  links.forEach(function (link) {
    link.addEventListener('click', function (event) {
      if (multiView) {
        event.preventDefault();
        activateView(link.getAttribute('data-psi-app-view-target'), true);
        return;
      }
      selectLink(link.getAttribute('href').slice(1));
      navigationUntil = Date.now() + 800;
      window.setTimeout(updateCurrent, 820);
      closeNavigation(false);
    });
  });
  if (multiView) {
    updateSearchAction();
    viewCommands.forEach(function (button) {
      button.addEventListener('click', function () { activateView(button.getAttribute('data-psi-app-command-target'), true); });
    });
    document.addEventListener('psi:apply-filter', function (event) {
      var target = event.detail && event.detail.tableId ? document.getElementById(event.detail.tableId) : null;
      var targetView = target && target.closest('[data-psi-app-view]');
      if (targetView && activateView(targetView.getAttribute('data-psi-app-view'), false)) {
        window.requestAnimationFrame(function () { target.scrollIntoView({ block: 'start', behavior: 'auto' }); });
      }
    });
    window.PSIApplication = {
      activateView: activateView,
      selectEntity: function (viewId, entityType, entityId) {
        if (!activateView(viewId, false)) { return false; }
        var view = views.filter(function (candidate) { return candidate.getAttribute('data-psi-app-view') === viewId; })[0];
        var explorer = view && Array.prototype.filter.call(view.querySelectorAll('[data-psi-app-explorer]'), function (candidate) {
          return candidate.getAttribute('data-psi-entity-type') === entityType;
        })[0];
        if (!explorer || !explorer.psiSelectEntity || !explorer.psiSelectEntity(entityId)) { return false; }
        explorer.scrollIntoView({ block: 'start', behavior: 'auto' });
        return true;
      }
    };
  }
  Array.prototype.forEach.call(shell.querySelectorAll('[data-psi-app-explorer]'), function (explorer) {
    var items = Array.prototype.slice.call(explorer.querySelectorAll('[data-psi-explorer-item]'));
    var details = Array.prototype.slice.call(explorer.querySelectorAll('[data-psi-explorer-detail]'));
    var search = explorer.querySelector('[data-psi-explorer-search]');
    var filters = Array.prototype.slice.call(explorer.querySelectorAll('[data-psi-explorer-filter]'));
    var count = explorer.querySelector('[data-psi-explorer-count]');
    var empty = explorer.querySelector('[data-psi-explorer-empty]');
    function selectItem(item, scrollDetail) {
      items.forEach(function (candidate) {
        candidate.setAttribute('aria-selected', candidate === item ? 'true' : 'false');
        candidate.tabIndex = candidate === item ? 0 : -1;
      });
      details.forEach(function (detail) { detail.hidden = !item || detail.getAttribute('data-psi-explorer-detail') !== item.getAttribute('data-psi-explorer-item'); });
      if (scrollDetail && item && window.matchMedia('(max-width: 640px)').matches) {
        explorer.querySelector('.psi-app-explorer-details').scrollIntoView({ block: 'start' });
      }
    }
    function applyFilters() {
      var query = search ? search.value.trim().toLocaleLowerCase() : '';
      items.forEach(function (item) {
        var matchesSearch = !query || item.textContent.toLocaleLowerCase().indexOf(query) !== -1;
        var matchesFields = filters.every(function (filter) {
          var value = filter.value;
          return !value || item.getAttribute('data-psi-filter-' + filter.getAttribute('data-psi-explorer-filter').toLowerCase()) === value;
        });
        item.hidden = !(matchesSearch && matchesFields);
      });
      var visible = items.filter(function (item) { return !item.hidden; });
      count.textContent = visible.length + (visible.length === 1 ? ' record' : ' records');
      empty.hidden = visible.length !== 0;
      if (!visible.length) { empty.textContent = 'No records match these filters.'; }
      var selected = visible.filter(function (item) { return item.getAttribute('aria-selected') === 'true'; })[0];
      selectItem(selected || visible[0] || null, false);
    }
    explorer.psiSelectEntity = function (id) {
      var item = items.filter(function (candidate) { return candidate.getAttribute('data-psi-entity-id') === id; })[0];
      if (!item) { return false; }
      if (search) { search.value = ''; }
      filters.forEach(function (filter) { filter.value = ''; });
      applyFilters();
      selectItem(item, false);
      item.focus({ preventScroll: true });
      return true;
    };
    explorer.psiFilterCategory = function (id) {
      var filter = filters.filter(function (candidate) { return candidate.getAttribute('data-psi-explorer-filter') === 'CategoryId'; })[0];
      if (!filter) { return false; }
      filter.value = id;
      if (search) { search.value = ''; }
      applyFilters();
      filter.focus({ preventScroll: true });
      return true;
    };
    items.forEach(function (item) {
      item.addEventListener('click', function () { selectItem(item, true); });
      item.addEventListener('keydown', function (event) {
        if (['ArrowDown', 'ArrowUp', 'Home', 'End'].indexOf(event.key) === -1) { return; }
        var visible = items.filter(function (candidate) { return !candidate.hidden; });
        if (!visible.length) { return; }
        var position = visible.indexOf(item), next = position;
        if (event.key === 'ArrowDown') { next = (position + 1) % visible.length; }
        if (event.key === 'ArrowUp') { next = (position - 1 + visible.length) % visible.length; }
        if (event.key === 'Home') { next = 0; }
        if (event.key === 'End') { next = visible.length - 1; }
        event.preventDefault();
        selectItem(visible[next], false);
        visible[next].focus();
      });
    });
    if (search) { search.addEventListener('input', applyFilters); }
    filters.forEach(function (filter) { filter.addEventListener('change', applyFilters); });
  });
  shell.addEventListener('click', function (event) {
    var category = event.target.closest('[data-psi-category-target][data-psi-category-id]');
    if (!category || !multiView) { return; }
    var viewId = category.getAttribute('data-psi-category-target');
    if (!activateView(viewId, false)) { return; }
    var view = views.filter(function (candidate) { return candidate.getAttribute('data-psi-app-view') === viewId; })[0];
    var explorer = view && view.querySelector('[data-psi-app-explorer][data-psi-entity-type="Check"]');
    if (explorer && explorer.psiFilterCategory && explorer.psiFilterCategory(category.getAttribute('data-psi-category-id'))) {
      explorer.scrollIntoView({ block: 'start', behavior: 'auto' });
    }
  });
  shell.addEventListener('click', function (event) {
    var link = event.target.closest('[data-psi-cross-view][data-psi-cross-id]');
    if (!link || !multiView) { return; }
    var viewId = link.getAttribute('data-psi-cross-view');
    var entityId = link.getAttribute('data-psi-cross-id');
    if (!activateView(viewId, false)) { return; }
    var view = views.filter(function (candidate) { return candidate.getAttribute('data-psi-app-view') === viewId; })[0];
    var explorer = view && view.querySelector('[data-psi-app-explorer][data-psi-entity-type]');
    if (explorer && explorer.psiSelectEntity && explorer.psiSelectEntity(entityId)) {
      explorer.scrollIntoView({ block: 'start', behavior: 'auto' });
    }
  });
  document.addEventListener('keydown', function (event) {
    if (!isOpen()) { return; }
    if (event.key === 'Escape') { event.preventDefault(); closeNavigation(true); return; }
    if (event.key !== 'Tab') { return; }
    var focusable = [closeButton].concat(links);
    var first = focusable[0], last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  });
  function onResize() { if (!mobile.matches) { closeNavigation(false); } }
  if (mobile.addEventListener) { mobile.addEventListener('change', onResize); }
  else { mobile.addListener(onResize); }
  var pending = false;
  function updateCurrent() {
    pending = false;
    if (Date.now() < navigationUntil) { return; }
    var selected = null;
    // Mark the section occupying the upper part of the workspace as current.
    // A small fixed threshold left the previous item selected when a target
    // section could not scroll all the way under the sticky command bar.
    var threshold = command.getBoundingClientRect().height + Math.min(320, window.innerHeight * 0.38);
    links.forEach(function (link) {
      var section = document.getElementById(link.getAttribute('href').slice(1));
      if (section && section.getBoundingClientRect().top <= threshold) { selected = section.id; }
    });
    if (selected) { selectLink(selected); }
  }
  if (!multiView) {
    window.addEventListener('scroll', function () {
      if (pending) { return; }
      pending = true;
      window.requestAnimationFrame(updateCurrent);
    }, { passive: true });
    window.addEventListener('hashchange', updateCurrent);
  }
}());
