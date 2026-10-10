(function () {
  'use strict';

  function valueOf(record, property) {
    var values = record && record.values ? record.values : record;
    return values && Object.prototype.hasOwnProperty.call(values, property) ? values[property] : null;
  }

  function equalValue(left, right) {
    var leftStatus = window.PSIStatus.normalize(String(left));
    var rightStatus = window.PSIStatus.normalize(String(right));
    if (leftStatus && rightStatus) { return leftStatus === rightStatus; }
    return String(left).toLocaleLowerCase() === String(right).toLocaleLowerCase();
  }

  function matches(record, conditions) {
    return (conditions || []).every(function (condition) {
      var value = valueOf(record, condition.Property || condition.property);
      var expected = typeof condition.Value !== 'undefined' ? condition.Value : condition.value;
      var operator = condition.Operator || condition.operator || 'Equals';
      var text = value === null || typeof value === 'undefined' ? '' : String(value);
      var leftNumber = Number(text);
      var rightNumber = Number(expected);
      switch (operator) {
        case 'In':
          return (condition.Values || condition.values || []).some(function (candidate) {
            return equalValue(text, candidate);
          });
        case 'IsEmpty': return text.trim() === '';
        case 'IsNotEmpty': return text.trim() !== '';
        case 'NotEquals': return !equalValue(text, expected);
        case 'GreaterThanOrEqual': return text !== '' && Number.isFinite(leftNumber) && Number.isFinite(rightNumber) && leftNumber >= rightNumber;
        case 'LessThan': return text !== '' && Number.isFinite(leftNumber) && Number.isFinite(rightNumber) && leftNumber < rightNumber;
        case 'Contains': return text.toLocaleLowerCase().indexOf(String(expected).toLocaleLowerCase()) !== -1;
        default: return equalValue(text, expected);
      }
    });
  }

  window.PSIDataEngine = window.PSIDataEngine || {};
  window.PSIDataEngine.datasets = window.PSIDataEngine.datasets || Object.create(null);
  window.PSIDataEngine.matches = matches;
  window.PSIDataEngine.valueOf = valueOf;
  window.PSIDataEngine.getRecords = function (tableId) {
    return window.PSIDataEngine.datasets[tableId] || [];
  };
  window.PSIDataEngine.getContext = function (tableId) {
    var selected = document.getElementById(tableId);
    return selected && selected.__psiContext ? selected.__psiContext() : { conditions: [], searchText: '' };
  };

  document.querySelectorAll('[data-psi-table="true"]').forEach(function (widget) {
    var table = widget.querySelector('[data-psi-table-element]');
    var body = widget.querySelector('[data-psi-table-body]');
    if (!table || !body) {
      return;
    }

    var rows = Array.prototype.slice.call(body.querySelectorAll('[data-psi-data-row]'));
    var columnNames = Array.prototype.slice.call(table.querySelectorAll('thead th[data-psi-column]')).map(function (header) {
      return header.getAttribute('data-psi-column');
    });
    var records = rows.map(function (row) {
      var values = Object.create(null);
      columnNames.forEach(function (name, index) {
        var cell = row.cells[index];
        Object.defineProperty(values, name, {
          enumerable: true,
          get: function () { return !cell || cell.classList.contains('psi-null-value') ? null : cell.textContent.trim(); }
        });
      });
      return { values: values, element: row };
    });
    window.PSIDataEngine.datasets[widget.id] = records;
    widget.__psiRecords = records;
    widget.__psiResults = records;
    var emptyRow = body.querySelector('[data-psi-empty]');
    var searchInput = widget.querySelector('[data-psi-search]');
    var resultCount = widget.querySelector('[data-psi-result-count]');
    var pageInfo = widget.querySelector('[data-psi-page-info]');
    var previousButton = widget.querySelector('[data-psi-previous]');
    var nextButton = widget.querySelector('[data-psi-next]');
    var pagination = widget.querySelector('[data-psi-pagination]');
    var filterControls = Array.prototype.slice.call(widget.querySelectorAll('[data-psi-filter-property]'));
    var activeFilterList = widget.querySelector('[data-psi-active-filters]');
    var activeFilterRow = widget.querySelector('.psi-active-filter-row');
    var clearFiltersButton = widget.querySelector('[data-psi-clear-filters]');
    var pageSize = Math.max(1, parseInt(widget.getAttribute('data-page-size'), 10) || 10);
    var searchEnabled = widget.getAttribute('data-search-enabled') === 'true';
    var sortingEnabled = widget.getAttribute('data-sort-enabled') === 'true';
    var paginationEnabled = widget.getAttribute('data-pagination-enabled') === 'true';
    var currentPage = 1;
    var sortColumn = -1;
    var sortDirection = 1;
    var searchText = '';
    var externalConditions = [];
    var columnIndexByName = Object.create(null);
    Array.prototype.slice.call(table.querySelectorAll('thead th[data-psi-column]')).forEach(function (header) {
      columnIndexByName[header.getAttribute('data-psi-column').toLocaleLowerCase()] = Array.prototype.indexOf.call(header.parentNode.children, header);
    });

    widget.__psiContext = function () {
      var controlConditions = [];
      filterControls.forEach(function (control) {
        var values = selectedValues(control);
        if (values.length > 0) {
          controlConditions.push({
            Property: control.getAttribute('data-psi-filter-property'),
            Operator: 'In',
            Values: values
          });
        }
      });
      return { conditions: externalConditions.slice(), controlConditions: controlConditions, searchText: searchText };
    };

    function selectedValues(control) {
      if (control.multiple) {
        return Array.prototype.slice.call(control.selectedOptions).map(function (option) { return option.value; }).filter(Boolean);
      }
      return control.value ? [control.value] : [];
    }

    function renderActiveFilters() {
      if (!activeFilterList) { return; }
      activeFilterList.textContent = '';
      var activeCount = 0;
      filterControls.forEach(function (control) {
        selectedValues(control).forEach(function (value) {
          activeCount += 1;
          var chip = document.createElement('button');
          chip.type = 'button';
          chip.className = 'psi-filter-chip';
          chip.setAttribute('aria-label', 'Remove ' + control.getAttribute('data-psi-filter-label') + ' filter ' + value);
          chip.textContent = control.getAttribute('data-psi-filter-label') + ': ' + value + ' \u00d7';
          chip.addEventListener('click', function () {
            Array.prototype.slice.call(control.options).forEach(function (option) {
              if (option.value === value) { option.selected = false; }
            });
            if (!control.multiple) { control.value = ''; }
            currentPage = 1;
            update();
          });
          activeFilterList.appendChild(chip);
        });
      });
      externalConditions.forEach(function (condition, index) {
        activeCount += 1;
        var property = condition.Property || condition.property;
        var operator = condition.Operator || condition.operator || 'Equals';
        var expected = typeof condition.Value !== 'undefined' ? condition.Value : condition.value;
        var chip = document.createElement('button');
        chip.type = 'button';
        chip.className = 'psi-filter-chip';
        chip.setAttribute('aria-label', 'Remove ' + property + ' evidence filter');
        chip.textContent = property + ' ' + operator + (typeof expected !== 'undefined' ? ' ' + expected : '') + ' \u00d7';
        chip.addEventListener('click', function () {
          externalConditions.splice(index, 1);
          currentPage = 1;
          update();
        });
        activeFilterList.appendChild(chip);
      });
      if (searchText) {
        activeCount += 1;
        var searchChip = document.createElement('button');
        searchChip.type = 'button';
        searchChip.className = 'psi-filter-chip';
        searchChip.setAttribute('aria-label', 'Clear search filter');
        searchChip.textContent = 'Search: ' + searchText + ' \u00d7';
        searchChip.addEventListener('click', function () {
          if (searchInput) { searchInput.value = ''; }
          searchText = '';
          currentPage = 1;
          update();
        });
        activeFilterList.appendChild(searchChip);
      }
      if (activeCount === 0) {
        var none = document.createElement('span');
        none.className = 'psi-active-filter-none';
        none.textContent = 'None';
        activeFilterList.appendChild(none);
      }
      if (clearFiltersButton) { clearFiltersButton.hidden = activeCount === 0; }
      if (activeFilterRow) { activeFilterRow.hidden = activeCount === 0; }
    }

    function sortableNumber(value) {
      var cleaned = value.trim().replace(/[\s,%$\u00a3\u20ac]/g, '');
      if (!cleaned) {
        return null;
      }
      var parsed = Number(cleaned);
      return Number.isFinite(parsed) ? parsed : null;
    }

    function update() {
      var activeFilterSets = filterControls.map(function (control) {
        var selected = selectedValues(control);
        return {
          values: selected.map(function (value) { return value.toLocaleLowerCase(); }),
          columnIndex: columnIndexByName[control.getAttribute('data-psi-filter-property').toLocaleLowerCase()]
        };
      }).filter(function (filter) { return filter.values.length > 0; });

      var uiConditions = [];
      activeFilterSets.forEach(function (filter) {
        var property = columnNames[filter.columnIndex];
        if (property) { uiConditions.push({ Property: property, Values: filter.values }); }
      });
      var filteredRecords = records.filter(function (record) {
        if (searchEnabled && record.element.textContent.toLocaleLowerCase().indexOf(searchText) === -1) { return false; }
        if (!matches(record, externalConditions)) { return false; }
        return uiConditions.every(function (condition) {
          var actual = valueOf(record, condition.Property);
          return actual !== null && condition.Values.indexOf(String(actual).toLocaleLowerCase()) !== -1;
        });
      });
      if (sortingEnabled && sortColumn >= 0) {
        filteredRecords.sort(function (leftRecord, rightRecord) {
          var left = leftRecord.element, right = rightRecord.element;
          var leftText = left.cells[sortColumn] ? left.cells[sortColumn].textContent.trim() : '';
          var rightText = right.cells[sortColumn] ? right.cells[sortColumn].textContent.trim() : '';
          var leftNumber = sortableNumber(leftText);
          var rightNumber = sortableNumber(rightText);
          var comparison;
          if (leftNumber !== null && rightNumber !== null) {
            comparison = leftNumber - rightNumber;
          } else {
            comparison = leftText.localeCompare(rightText, undefined, { numeric: true, sensitivity: 'base' });
          }
          return comparison * sortDirection;
        });
      }
      widget.__psiResults = filteredRecords;
      var filteredRows = filteredRecords.map(function (record) { return record.element; });

      var total = filteredRows.length;
      var pageCount = paginationEnabled ? Math.max(1, Math.ceil(total / pageSize)) : 1;
      currentPage = Math.min(currentPage, pageCount);
      var start = paginationEnabled ? (currentPage - 1) * pageSize : 0;
      var end = paginationEnabled ? Math.min(start + pageSize, total) : total;
      rows.forEach(function (row) { row.hidden = true; });
      filteredRows.slice(start, end).forEach(function (row) {
        row.hidden = false;
        body.appendChild(row);
      });

      if (emptyRow) {
        emptyRow.hidden = total > 0;
      }
      if (resultCount) {
        resultCount.textContent = total === 0 ? '0 results' : 'Showing ' + (start + 1) + '\u2013' + end + ' of ' + total + ' results';
      }
      if (pageInfo) {
        pageInfo.textContent = 'Page ' + currentPage + ' of ' + pageCount;
      }
      if (previousButton) {
        previousButton.disabled = currentPage <= 1;
      }
      if (nextButton) {
        nextButton.disabled = currentPage >= pageCount;
      }
      if (pagination) {
        pagination.hidden = !paginationEnabled || pageCount <= 1;
      }
      renderActiveFilters();
    }

    if (searchInput) {
      searchInput.addEventListener('input', function () {
        searchText = searchInput.value.trim().toLocaleLowerCase();
        currentPage = 1;
        update();
      });
    }

    filterControls.forEach(function (control) {
      control.addEventListener('change', function () {
        currentPage = 1;
        update();
      });
    });
    if (clearFiltersButton) {
      clearFiltersButton.addEventListener('click', function () {
        filterControls.forEach(function (control) {
          Array.prototype.slice.call(control.options).forEach(function (option) { option.selected = false; });
          if (!control.multiple) { control.value = ''; }
        });
        if (searchInput) { searchInput.value = ''; }
        searchText = '';
        externalConditions = [];
        currentPage = 1;
        update();
      });
    }

    document.addEventListener('psi:apply-filter', function (event) {
      var detail = event.detail || {};
      if (detail.tableId && detail.tableId !== widget.id) { return; }
      if (Array.isArray(detail.conditions)) {
        externalConditions = detail.conditions.slice();
        currentPage = 1;
        update();
        widget.scrollIntoView({ behavior: 'smooth', block: 'start' });
        return;
      }
      var control = filterControls.filter(function (candidate) {
        return candidate.getAttribute('data-psi-filter-property') === detail.property;
      })[0];
      if (!control) {
        var columnIndex = typeof detail.property === 'string' ? columnIndexByName[detail.property.toLocaleLowerCase()] : undefined;
        if (typeof columnIndex === 'undefined' || typeof detail.value === 'undefined') { return; }
        externalConditions = [{ Property: columnNames[columnIndex], Operator: 'Equals', Value: detail.value }];
        currentPage = 1;
        update();
        widget.scrollIntoView({ behavior: 'smooth', block: 'start' });
        return;
      }
      externalConditions = [];
      var values = Array.isArray(detail.values) ? detail.values.map(String) : (typeof detail.value !== 'undefined' ? [String(detail.value)] : []);
      Array.prototype.slice.call(control.options).forEach(function (option) {
        option.selected = control.multiple ? values.indexOf(option.value) !== -1 : false;
      });
      if (!control.multiple) { control.value = values.length > 0 ? values[0] : ''; }
      currentPage = 1;
      update();
      widget.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });

    if (sortingEnabled) {
      widget.querySelectorAll('[data-psi-sort]').forEach(function (button) {
        button.addEventListener('click', function () {
          var selectedColumn = parseInt(button.getAttribute('data-psi-sort'), 10);
          if (sortColumn === selectedColumn) {
            sortDirection *= -1;
          } else {
            sortColumn = selectedColumn;
            sortDirection = 1;
          }
          widget.querySelectorAll('[data-psi-sort-cell]').forEach(function (header) {
            header.setAttribute('aria-sort', 'none');
            var indicator = header.querySelector('.psi-sort-indicator');
            if (indicator) { indicator.textContent = ''; }
          });
          var activeHeader = button.closest('[data-psi-sort-cell]');
          if (activeHeader) {
            activeHeader.setAttribute('aria-sort', sortDirection === 1 ? 'ascending' : 'descending');
            var activeIndicator = activeHeader.querySelector('.psi-sort-indicator');
            if (activeIndicator) { activeIndicator.textContent = sortDirection === 1 ? '\u25b2' : '\u25bc'; }
          }
          currentPage = 1;
          update();
        });
      });
    }

    if (previousButton) {
      previousButton.addEventListener('click', function () {
        currentPage = Math.max(1, currentPage - 1);
        update();
      });
    }
    if (nextButton) {
      nextButton.addEventListener('click', function () {
        currentPage += 1;
        update();
      });
    }

    var exportToolbar = widget.querySelector('[data-psi-export-toolbar]');
    if (exportToolbar && window.PSIExport) {
      var exportConfig = {};
      try { exportConfig = JSON.parse(widget.getAttribute('data-psi-export-config') || '{}'); } catch (ignore) { }
      window.PSIExport.attachToolbar(exportToolbar, function () {
        return {
          records: widget.__psiResults,
          columns: exportConfig.columns || [],
          labels: exportConfig.labels || {},
          reportTitle: document.querySelector('h1') ? document.querySelector('h1').textContent : 'Report',
          contextTitle: widget.querySelector('h3') ? widget.querySelector('h3').textContent : 'Table',
          fileName: exportConfig.fileName,
          worksheetName: exportConfig.worksheetName,
          print: function () {
            var section = widget.closest('.psi-section');
            var originalOrder = Array.prototype.slice.call(body.children);
            document.body.classList.add('psi-print-table');
            widget.classList.add('psi-print-target');
            if (section) { section.classList.add('psi-print-section'); }
            widget.__psiResults.forEach(function (record) {
              record.element.setAttribute('data-psi-print-match', '');
              body.appendChild(record.element);
            });
            var restore = function () {
              document.body.classList.remove('psi-print-table'); widget.classList.remove('psi-print-target');
              if (section) { section.classList.remove('psi-print-section'); }
              widget.__psiResults.forEach(function (record) { record.element.removeAttribute('data-psi-print-match'); });
              originalOrder.forEach(function (row) { body.appendChild(row); });
              window.removeEventListener('afterprint', restore);
            };
            window.addEventListener('afterprint', restore);
            try { window.print(); } catch (error) { restore(); throw error; }
          }
        };
      });
    }

    update();
  });
}());
