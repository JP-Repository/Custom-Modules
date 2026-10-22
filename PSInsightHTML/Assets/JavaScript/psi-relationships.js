(function () {
  'use strict';
  var svgNS = 'http://www.w3.org/2000/svg';
  var components = Array.prototype.slice.call(document.querySelectorAll('[data-psi-rel-component]'));
  if (!components.length) { return; }
  function element(name, className, text) {
    var node = document.createElement(name);
    if (className) { node.className = className; }
    if (text !== undefined && text !== null) { node.textContent = String(text); }
    return node;
  }
  function svgElement(name, attrs) {
    var node = document.createElementNS(svgNS, name);
    Object.keys(attrs || {}).forEach(function (key) { node.setAttribute(key, String(attrs[key])); });
    return node;
  }
  function key(value) { return String(value || '').toLocaleLowerCase(); }
  function statusLabel(value) { return value === 'NotChecked' ? 'Not Tested' : value; }
  components.forEach(function (root) {
    var source = root.querySelector('[data-psi-rel-data]');
    var data = JSON.parse(source.textContent || '{}');
    var nodes = data.Nodes || [], edges = data.Edges || [];
    var nodeMap = Object.create(null), edgeMap = Object.create(null);
    nodes.forEach(function (node) { nodeMap[node.Id] = node; });
    edges.forEach(function (edge) { edgeMap[edge.Id] = edge; });
    var availableLinks = Object.create(null);
    ['Resource','Finding','Evidence','Check','Replication'].forEach(function (kind) {
      var id = data.LinkViews && data.LinkViews[kind];
      var view = id && document.getElementById('psi-view-' + id);
      availableLinks[kind] = !!(view && (kind === 'Check' || kind === 'Replication' || view.querySelector('[data-psi-app-explorer][data-psi-entity-type="' + kind + '"]')));
    });
    var mode = root.getAttribute('data-psi-rel-mode');
    var maxNodes = Number(root.getAttribute('data-psi-rel-max')) || 100;
    var treeItems = Array.prototype.slice.call(root.querySelectorAll('[data-psi-rel-node]'));
    var treeMap = Object.create(null);
    treeItems.forEach(function (item) { treeMap[item.getAttribute('data-psi-rel-node')] = item; });
    var edgeItems = Array.prototype.slice.call(root.querySelectorAll('.psi-rel-edge-item'));
    var detail = root.querySelector('[data-psi-rel-detail]');
    var count = root.querySelector('[data-psi-rel-count]');
    var search = root.querySelector('[data-psi-rel-search]');
    var filters = Array.prototype.slice.call(root.querySelectorAll('[data-psi-rel-filter]'));
    var detailFilters = Array.prototype.slice.call(root.querySelectorAll('[data-psi-rel-filter-detail]'));
    var empty = root.querySelector('[data-psi-rel-filter-empty]');
    var svg = root.querySelector('[data-psi-rel-svg]');
    var viewport = root.querySelector('.psi-rel-viewport');
    var graphNodes = Object.create(null), graphEdges = Object.create(null);
    var selectedKind = '', selectedId = '', zoom = 1, graphWidth = 0, graphHeight = 0, emphasizeSelection = false;
    var visibleNodeIds = Object.create(null), visibleEdgeIds = Object.create(null);
    function filterValue(name) {
      var input = filters.filter(function (f) { return f.getAttribute('data-psi-rel-filter') === name; })[0];
      return input ? input.value : '';
    }
    function addFact(list, label, value) {
      if (value === undefined || value === null || String(value).trim() === '') { return; }
      var row = element('div'), dt = element('dt', '', label), dd = element('dd', '', value);
      row.appendChild(dt); row.appendChild(dd); list.appendChild(row);
    }
    function addButton(container, label, action) {
      var button = element('button', 'psi-rel-detail-link', label);
      button.type = 'button'; button.addEventListener('click', action); container.appendChild(button);
    }
    function addLinks(title, links, kind) {
      if (!links || !links.length) { return; }
      detail.appendChild(element('h5', '', title));
      var group = element('div');
      links.forEach(function (link) {
        if (availableLinks[kind]) {
          addButton(group, link.Label, function () {
            if (window.PSIApplication && window.PSIApplication.selectEntity) {
              window.PSIApplication.selectEntity(data.LinkViews[kind], kind, link.Id);
            }
          });
        } else { group.appendChild(element('span', 'psi-rel-detail-label', link.Label)); }
      });
      detail.appendChild(group);
    }
    function selectNode(id, focus, broadcast) {
      var node = nodeMap[id]; if (!node) { return; }
      selectedKind = 'node'; selectedId = id;
      if (broadcast) { emphasizeSelection = true; }
      detail.textContent = '';
      detail.appendChild(element('p', 'psi-app-explorer-detail-eyebrow', node.External ? 'External / evidence only' : 'Selected resource'));
      detail.appendChild(element('h4', '', node.Name));
      detail.appendChild(element('p', '', node.Description || node.Type));
      var facts = element('dl');
      addFact(facts, 'Type', node.Type); addFact(facts, 'Status', statusLabel(node.Status));
      (node.Details || []).forEach(function (field) { addFact(facts, field.Label, field.Value); });
      detail.appendChild(facts);
      var outgoing = edges.filter(function (edge) { return edge.SourceId === id; });
      var incoming = edges.filter(function (edge) { return edge.TargetId === id; });
      [['Outgoing', outgoing], ['Incoming', incoming]].forEach(function (entry) {
        if (!entry[1].length) { return; }
        detail.appendChild(element('h5', '', entry[0] + ' relationships'));
        var group = element('div');
        entry[1].forEach(function (edge) {
          var other = nodeMap[edge.SourceId === id ? edge.TargetId : edge.SourceId];
          addButton(group, edge.Label + ' / ' + (other ? other.Name : 'Unknown'), function () { selectEdge(edge.Id, true); });
        });
        detail.appendChild(group);
      });
      var findings = (node.Findings || []).slice(), evidence = (node.Evidence || []).slice();
      outgoing.concat(incoming).forEach(function (edge) {
        (edge.Findings || []).forEach(function (link) { if (!findings.some(function (x) { return x.Id === link.Id; })) { findings.push(link); } });
        (edge.Evidence || []).forEach(function (link) { if (!evidence.some(function (x) { return x.Id === link.Id; })) { evidence.push(link); } });
      });
      addLinks('Related findings', findings, 'Finding');
      addLinks('Supporting evidence', evidence, 'Evidence');
      if (node.ResourceId && availableLinks.Resource) {
        addButton(detail, 'Open resource in workspace', function () {
          if (window.PSIApplication && window.PSIApplication.selectEntity) {
            window.PSIApplication.selectEntity(data.LinkViews.Resource, 'Resource', node.ResourceId);
          }
        });
      }
      ['Check','Replication'].forEach(function (kind) {
        if (!node.ResourceId || !availableLinks[kind]) { return; }
        addButton(detail, kind === 'Check' ? 'Open checks for this resource' : 'Open replication evidence', function () {
          if (!window.PSIApplication || !window.PSIApplication.activateView(data.LinkViews[kind], false)) { return; }
          var view = document.getElementById('psi-view-' + data.LinkViews[kind]);
          var searchField = view && view.querySelector('[data-psi-explorer-search], [data-psi-search]');
          if (searchField) { searchField.value = node.Name; searchField.dispatchEvent(new Event('input', { bubbles: true })); }
        });
      });
      updateSelection();
      if (focus && treeMap[id]) { treeMap[id].focus(); }
      if (broadcast) {
        document.dispatchEvent(new CustomEvent('psi:relationship-select', { detail: { origin: root.id, nodeId: id, resourceId: node.ResourceId || '' } }));
      }
    }
    function selectEdge(id, focus) {
      var edge = edgeMap[id]; if (!edge) { return; }
      selectedKind = 'edge'; selectedId = id;
      emphasizeSelection = true;
      detail.textContent = '';
      detail.appendChild(element('p', 'psi-app-explorer-detail-eyebrow', 'Selected relationship'));
      detail.appendChild(element('h4', '', edge.Label));
      detail.appendChild(element('p', '', edge.Description || edge.Type));
      var facts = element('dl');
      addFact(facts, 'Type', edge.Type); addFact(facts, 'Direction', edge.Direction);
      addFact(facts, 'Status', statusLabel(edge.Status)); addFact(facts, 'Category', edge.Category);
      if (edge.External) { addFact(facts, 'Scope', 'External / evidence only'); }
      detail.appendChild(facts);
      detail.appendChild(element('h5', '', 'Endpoints'));
      var group = element('div');
      [edge.SourceId, edge.TargetId].forEach(function (nodeId) {
        var node = nodeMap[nodeId];
        if (node) { addButton(group, node.Name, function () { selectNode(nodeId, true, true); }); }
      });
      detail.appendChild(group);
      addLinks('Related findings', edge.Findings, 'Finding');
      addLinks('Supporting evidence', edge.Evidence, 'Evidence');
      updateSelection();
      if (focus) { detail.scrollIntoView({ block: 'nearest' }); }
    }
    function updateSelection() {
      treeItems.forEach(function (item) {
        var on = selectedKind === 'node' && item.getAttribute('data-psi-rel-node') === selectedId;
        item.setAttribute('aria-selected', String(on)); item.tabIndex = on ? 0 : -1;
      });
      edgeItems.forEach(function (item) {
        item.setAttribute('aria-pressed', String(selectedKind === 'edge' && item.getAttribute('data-psi-rel-edge') === selectedId));
      });
      Object.keys(graphNodes).forEach(function (id) {
        var current = graphNodes[id], linked = selectedKind === 'node' && id === selectedId;
        current.setAttribute('aria-pressed', String(linked));
        current.classList.toggle('psi-rel-dim', emphasizeSelection && selectedKind === 'node' && !linked && !edges.some(function (edge) { return (edge.SourceId === selectedId && edge.TargetId === id) || (edge.TargetId === selectedId && edge.SourceId === id); }));
      });
      Object.keys(graphEdges).forEach(function (id) {
        var edge = edgeMap[id], on = selectedKind === 'edge' && id === selectedId;
        graphEdges[id].setAttribute('aria-pressed', String(on));
        graphEdges[id].classList.toggle('psi-rel-dim', emphasizeSelection && selectedKind === 'node' && edge.SourceId !== selectedId && edge.TargetId !== selectedId);
      });
    }
    function applyZoom() {
      if (!svg) { return; }
      svg.style.width = Math.round(graphWidth * zoom) + 'px';
      svg.style.height = Math.round(graphHeight * zoom) + 'px';
    }
    function renderGraph(visibleNodes, visibleEdges) {
      if (!svg) { return; }
      svg.textContent = ''; graphNodes = Object.create(null); graphEdges = Object.create(null);
      if (!visibleNodes.length || visibleNodes.length > maxNodes) { return; }
      var compact = document.documentElement.getAttribute('data-psi-navigation') === 'FluentExplorer';
      var nodeWidth = compact ? 138 : 172, nodeHeight = compact ? 56 : 62;
      var columnStep = compact ? 156 : 215, rowStep = compact ? 80 : 92;
      var sorted = visibleNodes.slice().sort(function (a,b) { return a.SortOrder - b.SortOrder || a.Name.localeCompare(b.Name); });
      var indegree = Object.create(null), depth = Object.create(null), adjacency = Object.create(null);
      sorted.forEach(function (node) { indegree[node.Id] = 0; depth[node.Id] = 0; adjacency[node.Id] = []; });
      var containment = visibleEdges.filter(function (edge) { return edge.Category === 'Containment'; });
      var layoutEdges = containment.length ? containment : visibleEdges;
      layoutEdges.forEach(function (edge) {
        if (edge.SourceId === edge.TargetId) { return; }
        indegree[edge.TargetId] += 1;
        adjacency[edge.SourceId].push(edge.TargetId);
      });
      var queue = sorted.filter(function (node) { return indegree[node.Id] === 0; }).map(function (node) { return node.Id; });
      for (var q = 0; q < queue.length; q++) {
        var id = queue[q];
        adjacency[id].forEach(function (next) {
          depth[next] = Math.max(depth[next], depth[id] + 1);
          indegree[next] -= 1; if (indegree[next] === 0) { queue.push(next); }
        });
      }
      var layers = Object.create(null), positions = Object.create(null), widthUnits = 0, maxRows = 0;
      sorted.forEach(function (node) {
        var layer = Math.min(depth[node.Id], 20);
        if (!layers[layer]) { layers[layer] = []; }
        layers[layer].push(node);
      });
      Object.keys(layers).sort(function (a,b) { return Number(a)-Number(b); }).forEach(function (layer) {
        maxRows = Math.max(maxRows, Math.min(5, layers[layer].length));
        layers[layer].forEach(function (node, index) { positions[node.Id] = { x: 20 + (widthUnits + Math.floor(index / 5)) * columnStep, y: 20 + (index % 5) * rowStep }; });
        widthUnits += Math.ceil(layers[layer].length / 5);
      });
      graphWidth = Math.max(400, 20 + widthUnits * columnStep); graphHeight = Math.max(190, 50 + maxRows * rowStep);
      svg.setAttribute('viewBox', '0 0 ' + graphWidth + ' ' + graphHeight);
      var defs = svgElement('defs');
      var marker = svgElement('marker', { id: root.id + '-arrow', viewBox: '0 0 10 10', refX: 9, refY: 5, markerWidth: 6, markerHeight: 6, orient: 'auto-start-reverse' });
      marker.appendChild(svgElement('path', { d: 'M 0 0 L 10 5 L 0 10 z', fill: 'currentColor' })); defs.appendChild(marker); svg.appendChild(defs);
      visibleEdges.forEach(function (edge) {
        var from = positions[edge.SourceId], to = positions[edge.TargetId]; if (!from || !to) { return; }
        var group = svgElement('g', { 'class': 'psi-rel-edge-group', 'role': 'button', 'tabindex': '0', 'aria-pressed': 'false', 'data-psi-rel-id': edge.Id, 'aria-label': edge.Label + ': ' + nodeMap[edge.SourceId].Name + ' to ' + nodeMap[edge.TargetId].Name + ', ' + statusLabel(edge.Status) });
        var x1 = from.x + nodeWidth, y1 = from.y + nodeHeight / 2, x2 = to.x, y2 = to.y + nodeHeight / 2;
        var path = svgElement('path', { 'class': 'psi-rel-edge-path', d: 'M ' + x1 + ' ' + y1 + ' C ' + (x1+45) + ' ' + y1 + ', ' + (x2-45) + ' ' + y2 + ', ' + x2 + ' ' + y2, 'marker-end': 'url(#' + root.id + '-arrow)', 'data-psi-rel-edge-status': edge.Status, 'data-psi-rel-edge-category': edge.Category || '' });
        if (edge.Direction === 'Bidirectional') { path.setAttribute('marker-start', 'url(#' + root.id + '-arrow)'); }
        group.appendChild(path); group.appendChild(svgElement('path', { d: path.getAttribute('d'), fill: 'none', stroke: 'transparent', 'stroke-width': 15 }));
        group.addEventListener('click', function () { selectEdge(edge.Id, false); });
        group.addEventListener('keydown', function (event) { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); selectEdge(edge.Id, false); } });
        svg.appendChild(group); graphEdges[edge.Id] = group;
      });
      sorted.forEach(function (node) {
        var pos = positions[node.Id];
        var contextLabel = detailFilters.length ? detailFilters[0].getAttribute('data-psi-rel-filter-detail') : '';
        var contextDetail = (node.Details || []).filter(function (item) { return item.Label === contextLabel; })[0];
        var group = svgElement('g', { 'class': 'psi-rel-graph-node', 'role': 'button', 'tabindex': '0', 'aria-pressed': 'false', 'data-psi-rel-id': node.Id, 'aria-label': node.Name + ', ' + node.Type + (contextDetail ? ', ' + contextLabel + ' ' + contextDetail.Value : '') + ', ' + statusLabel(node.Status), 'data-psi-rel-status': node.Status, 'data-psi-rel-external': String(node.External) });
        group.appendChild(svgElement('rect', { x: pos.x, y: pos.y, width: nodeWidth, height: nodeHeight, rx: 8 }));
        var iconTemplate = root.querySelector('[data-psi-rel-icon="' + String(node.Icon).replace(/[^A-Za-z0-9_-]/g, '') + '"]');
        if (iconTemplate) {
          var icon = iconTemplate.content.querySelector('svg').cloneNode(true);
          icon.setAttribute('x', pos.x + 8); icon.setAttribute('y', pos.y + 8);
          icon.setAttribute('width', 18); icon.setAttribute('height', 18); group.appendChild(icon);
        }
        var name = svgElement('text', { x: pos.x + 32, y: pos.y + 23, 'font-size': 11, 'font-weight': 700 });
        var nameLimit = compact ? 17 : 23;
        name.textContent = node.Name.length > nameLimit ? node.Name.slice(0, nameLimit - 1) + '...' : node.Name; group.appendChild(name);
        var subtitle = svgElement('text', { x: pos.x + 9, y: pos.y + 43, 'font-size': 10, 'class': 'psi-rel-node-subtitle' });
        var summary = contextDetail ? contextDetail.Value + ' / ' + statusLabel(node.Status) : statusLabel(node.Status) + ' / ' + node.Type;
        var summaryLimit = compact ? 20 : 26;
        subtitle.textContent = summary.length > summaryLimit ? summary.slice(0, summaryLimit - 1) + '...' : summary; group.appendChild(subtitle);
        group.appendChild(svgElement('circle', { cx: pos.x + nodeWidth - 14, cy: pos.y + nodeHeight - 19, r: 5, 'class': 'psi-rel-node-status' }));
        group.addEventListener('click', function () { selectNode(node.Id, false, true); });
        group.addEventListener('keydown', function (event) { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); selectNode(node.Id, false, true); } });
        svg.appendChild(group); graphNodes[node.Id] = group;
      });
      applyZoom(); updateSelection();
    }
    function applyFilters() {
      var query = key(search.value.trim()), type = filterValue('type'), status = filterValue('status');
      var edgeType = filterValue('edge-type'), category = filterValue('category');
      var matched = nodes.filter(function (node) {
        var detailsMatch = detailFilters.every(function (filter) {
          if (!filter.value) { return true; }
          return (node.Details || []).some(function (item) { return item.Label === filter.getAttribute('data-psi-rel-filter-detail') && item.Value === filter.value; });
        });
        return (!query || key(node.Name + ' ' + node.Type + ' ' + node.Description).indexOf(query) !== -1) &&
          (!type || node.Type === type) && (!status || node.Status === status) && detailsMatch;
      });
      visibleNodeIds = Object.create(null);
      matched.forEach(function (node) {
        visibleNodeIds[node.Id] = true;
        if (mode === 'Tree') {
          var parent = node.ParentId, seen = Object.create(null);
          while (parent && nodeMap[parent] && !seen[parent]) { visibleNodeIds[parent] = true; seen[parent] = true; parent = nodeMap[parent].ParentId; }
        }
      });
      var visibleEdges = edges.filter(function (edge) {
        return visibleNodeIds[edge.SourceId] && visibleNodeIds[edge.TargetId] && (!edgeType || edge.Type === edgeType) && (!category || edge.Category === category);
      });
      visibleEdgeIds = Object.create(null);
      visibleEdges.forEach(function (edge) { visibleEdgeIds[edge.Id] = true; });
      edgeItems.forEach(function (item) { item.hidden = !visibleEdgeIds[item.getAttribute('data-psi-rel-edge')]; });
      treeItems.forEach(function (item) {
        var id = item.getAttribute('data-psi-rel-node'); item.hidden = !visibleNodeIds[id];
        if ((query || type || status || detailFilters.some(function (filter) { return !!filter.value; })) && visibleNodeIds[id] && item.hasAttribute('aria-expanded')) {
          item.setAttribute('aria-expanded', 'true');
          var group = item.querySelector(':scope > ul[role="group"]'); if (group) { group.hidden = false; }
        }
      });
      var overLimit = mode === 'Topology' && matched.length > maxNodes;
      empty.hidden = !!(matched.length && !overLimit && (mode === 'Tree' || visibleEdges.length || mode === 'Topology'));
      if (overLimit) { empty.textContent = matched.length + ' nodes exceed the ' + maxNodes + '-node display limit. Narrow the filters to show the graph; the relationship list remains available.'; }
      else { empty.textContent = 'No nodes or relationships match these filters.'; }
      count.textContent = matched.length + ' nodes / ' + visibleEdges.length + ' relationships';
      renderGraph(matched, visibleEdges);
      if (selectedKind === 'node' && !visibleNodeIds[selectedId] && matched.length) { selectNode(matched[0].Id, false, false); }
      if (selectedKind === 'edge' && !visibleEdgeIds[selectedId] && matched.length) { selectNode(matched[0].Id, false, false); }
    }
    function visibleTreeItems() {
      return treeItems.filter(function (item) { return !item.hidden && !item.closest('ul[hidden]'); });
    }
    treeItems.forEach(function (item) {
      item.addEventListener('click', function (event) {
        if (event.target.closest('[role="treeitem"]') !== item) { return; }
        var id = item.getAttribute('data-psi-rel-node');
        if (event.target.closest('.psi-rel-twisty') && item.hasAttribute('aria-expanded')) {
          var expanded = item.getAttribute('aria-expanded') !== 'true';
          item.setAttribute('aria-expanded', String(expanded));
          var group = item.querySelector(':scope > ul[role="group"]'); if (group) { group.hidden = !expanded; }
        }
        selectNode(id, true, true);
      });
      item.addEventListener('keydown', function (event) {
        if (event.target !== item) { return; }
        var list = visibleTreeItems(), position = list.indexOf(item), next = null;
        if (event.key === 'ArrowDown') { next = list[Math.min(position + 1, list.length - 1)]; }
        else if (event.key === 'ArrowUp') { next = list[Math.max(position - 1, 0)]; }
        else if (event.key === 'Home') { next = list[0]; }
        else if (event.key === 'End') { next = list[list.length - 1]; }
        else if (event.key === 'ArrowRight') {
          if (item.getAttribute('aria-expanded') === 'false') {
            item.setAttribute('aria-expanded', 'true'); item.querySelector(':scope > ul[role="group"]').hidden = false;
          } else { next = item.querySelector(':scope > ul[role="group"] > [role="treeitem"]:not([hidden])'); }
        }
        else if (event.key === 'ArrowLeft') {
          if (item.getAttribute('aria-expanded') === 'true') {
            item.setAttribute('aria-expanded', 'false'); item.querySelector(':scope > ul[role="group"]').hidden = true;
          } else { next = item.parentElement.closest('[role="treeitem"]'); }
        }
        else if (event.key === 'Enter' || event.key === ' ') { selectNode(item.getAttribute('data-psi-rel-node'), false, true); }
        else { return; }
        event.preventDefault();
        if (next) { selectNode(next.getAttribute('data-psi-rel-node'), true, true); }
      });
    });
    edgeItems.forEach(function (item) {
      item.addEventListener('click', function () { selectEdge(item.getAttribute('data-psi-rel-edge'), true); });
    });
    search.addEventListener('input', applyFilters);
    filters.forEach(function (filter) { filter.addEventListener('change', applyFilters); });
    detailFilters.forEach(function (filter) { filter.addEventListener('change', applyFilters); });
    Array.prototype.forEach.call(root.querySelectorAll('[data-psi-rel-zoom]'), function (button) {
      button.addEventListener('click', function () {
        var action = button.getAttribute('data-psi-rel-zoom');
        if (action === 'in') { zoom = Math.min(2.5, zoom + .2); }
        else if (action === 'out') { zoom = Math.max(.4, zoom - .2); }
        else if (action === 'fit') { zoom = Math.max(.4, Math.min(1, (viewport.clientWidth - 10) / graphWidth)); }
        else { zoom = 1; viewport.scrollLeft = 0; viewport.scrollTop = 0; }
        applyZoom();
      });
    });
    document.addEventListener('psi:relationship-select', function (event) {
      if (event.detail && event.detail.origin !== root.id && nodeMap[event.detail.nodeId]) { selectNode(event.detail.nodeId, false, false); }
    });
    applyFilters();
    if (nodes.length) { selectNode(nodes[0].Id, false, false); }
    else if (edges.length) { selectEdge(edges[0].Id, false); }
  });
}());
