(function (root) {
  'use strict';

  function safeName(value) {
    var name = String(value || 'Report').normalize('NFKD').replace(/[\u0300-\u036f]/g, '')
      .replace(/[^A-Za-z0-9_-]+/g, '-').replace(/[-_]{2,}/g, '-').replace(/^[-_]+|[-_]+$/g, '');
    return (name || 'Report').slice(0, 80);
  }
  function fileName(report, context, extension, configured) {
    var stamp = new Date();
    var date = String(stamp.getFullYear()) + ('0' + (stamp.getMonth() + 1)).slice(-2) + ('0' + stamp.getDate()).slice(-2);
    var time = ('0' + stamp.getHours()).slice(-2) + ('0' + stamp.getMinutes()).slice(-2);
    var base = configured ? safeName(configured) : safeName(report) + '_' + safeName(context);
    return base + '_' + date + '-' + time + '.' + extension;
  }
  function rawValue(record, column) {
    var values = record && record.values ? record.values : record;
    return values && Object.prototype.hasOwnProperty.call(values, column) ? values[column] : null;
  }
  function safeCsvValue(value) {
    var text = value === null || typeof value === 'undefined' ? '' : String(value);
    if (/^[\s\uFEFF]*[=+\-@]/.test(text) || /^[\t\r\n]/.test(text)) { text = "'" + text; }
    return text;
  }
  function escapeCsv(value) { return '"' + safeCsvValue(value).replace(/"/g, '""') + '"'; }
  function toCsv(records, columns, labels, valueReader) {
    var read = valueReader || rawValue;
    var rows = [(columns || []).map(function (column) { return escapeCsv(labels && labels[column] ? labels[column] : column); }).join(',')];
    (records || []).forEach(function (record) {
      rows.push((columns || []).map(function (column) { return escapeCsv(read(record, column)); }).join(','));
    });
    return '\ufeff' + rows.join('\r\n');
  }
  function xml(value) {
    return String(value === null || typeof value === 'undefined' ? '' : value)
      .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/g, '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
  }
  function cellAddress(index) {
    var name = '';
    for (var number = index + 1; number > 0; number = Math.floor((number - 1) / 26)) {
      name = String.fromCharCode(65 + ((number - 1) % 26)) + name;
    }
    return name;
  }
  function xlsxCell(value, address) {
    if (value === null || typeof value === 'undefined' || value === '') { return '<c r="' + address + '"/>'; }
    if (typeof value === 'boolean') { return '<c r="' + address + '" t="b"><v>' + (value ? '1' : '0') + '</v></c>'; }
    var text = String(value);
    if ((typeof value === 'number' || (/^-?(?:0|[1-9]\d*)(?:\.\d+)?$/.test(text) && text.replace(/\D/g, '').length <= 15)) && Number.isFinite(Number(text))) {
      return '<c r="' + address + '"><v>' + Number(text) + '</v></c>';
    }
    return '<c r="' + address + '" t="inlineStr"><is><t xml:space="preserve">' + xml(text) + '</t></is></c>';
  }
  function sheetName(value) {
    return String(value || 'Evidence').replace(/[\[\]:*?\\/]/g, ' ').replace(/^[\s']+|[\s']+$/g, '').slice(0, 31) || 'Evidence';
  }
  function worksheet(records, columns, labels, valueReader) {
    var read = valueReader || rawValue;
    var rows = [];
    rows.push('<row r="1">' + columns.map(function (column, index) {
      return xlsxCell(labels && labels[column] ? labels[column] : column, cellAddress(index) + '1');
    }).join('') + '</row>');
    records.forEach(function (record, index) {
      var rowNumber = index + 2;
      rows.push('<row r="' + rowNumber + '">' + columns.map(function (column, columnIndex) {
        return xlsxCell(read(record, column), cellAddress(columnIndex) + rowNumber);
      }).join('') + '</row>');
    });
    var width = columns.map(function (column, index) {
      var label = labels && labels[column] ? labels[column] : column;
      return '<col min="' + (index + 1) + '" max="' + (index + 1) + '" width="' + Math.min(36, Math.max(14, String(label).length + 3)) + '" customWidth="1"/>';
    }).join('');
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' +
      '<cols>' + width + '</cols><sheetData>' + rows.join('') + '</sheetData>' +
      '<autoFilter ref="A1:' + cellAddress(columns.length - 1) + (records.length + 1) + '"/></worksheet>';
  }
  function crc32(bytes) {
    var crc = -1;
    for (var i = 0; i < bytes.length; i++) {
      crc ^= bytes[i];
      for (var bit = 0; bit < 8; bit++) { crc = (crc >>> 1) ^ (crc & 1 ? 0xEDB88320 : 0); }
    }
    return (crc ^ -1) >>> 0;
  }
  function write16(view, offset, value) { view.setUint16(offset, value, true); }
  function write32(view, offset, value) { view.setUint32(offset, value >>> 0, true); }
  function zip(files) {
    var encoder = new TextEncoder();
    var parts = [], directory = [], offset = 0;
    files.forEach(function (file) {
      var name = encoder.encode(file.name), data = encoder.encode(file.data), crc = crc32(data);
      var local = new Uint8Array(30 + name.length), localView = new DataView(local.buffer);
      write32(localView, 0, 0x04034b50); write16(localView, 4, 20); write32(localView, 14, crc);
      write32(localView, 18, data.length); write32(localView, 22, data.length); write16(localView, 26, name.length);
      local.set(name, 30); parts.push(local, data);
      var central = new Uint8Array(46 + name.length), centralView = new DataView(central.buffer);
      write32(centralView, 0, 0x02014b50); write16(centralView, 4, 20); write16(centralView, 6, 20);
      write32(centralView, 16, crc); write32(centralView, 20, data.length); write32(centralView, 24, data.length);
      write16(centralView, 28, name.length); write32(centralView, 42, offset);
      central.set(name, 46); directory.push(central); offset += local.length + data.length;
    });
    var directorySize = directory.reduce(function (sum, part) { return sum + part.length; }, 0);
    var end = new Uint8Array(22), endView = new DataView(end.buffer);
    write32(endView, 0, 0x06054b50); write16(endView, 8, files.length); write16(endView, 10, files.length);
    write32(endView, 12, directorySize); write32(endView, 16, offset);
    var result = new Uint8Array(offset + directorySize + end.length), cursor = 0;
    parts.concat(directory, [end]).forEach(function (part) { result.set(part, cursor); cursor += part.length; });
    return result;
  }
  function toXlsx(records, columns, labels, worksheetName, valueReader) {
    if (!columns || !columns.length) { throw new Error('Select at least one export column.'); }
    var workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
      '<sheets><sheet name="' + xml(sheetName(worksheetName)) + '" sheetId="1" r:id="rId1"/></sheets></workbook>';
    return zip([
      { name: '[Content_Types].xml', data: '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>' },
      { name: '_rels/.rels', data: '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>' },
      { name: 'xl/workbook.xml', data: workbook },
      { name: 'xl/_rels/workbook.xml.rels', data: '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>' },
      { name: 'xl/worksheets/sheet1.xml', data: worksheet(records || [], columns, labels || {}, valueReader) }
    ]);
  }
  function download(data, file, mime) {
    var blob = new Blob([data], { type: mime });
    var url = URL.createObjectURL(blob), link = document.createElement('a');
    link.href = url; link.download = file; document.body.appendChild(link); link.click(); link.remove();
    root.setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
  }
  function attachToolbar(toolbar, provider) {
    if (!toolbar) { return; }
    var trigger = toolbar.querySelector('[data-psi-export-trigger]');
    var menu = toolbar.querySelector('[data-psi-export-menu]');
    var feedback = toolbar.querySelector('[data-psi-export-feedback]');
    var items = Array.prototype.slice.call(menu.querySelectorAll('[data-psi-export-format]'));
    var timer;
    function close(restoreFocus) { menu.hidden = true; trigger.setAttribute('aria-expanded', 'false'); if (restoreFocus) { trigger.focus(); } }
    function open(focusIndex) { menu.hidden = false; trigger.setAttribute('aria-expanded', 'true'); if (typeof focusIndex === 'number') { items[focusIndex].focus(); } }
    function message(value) { root.clearTimeout(timer); feedback.textContent = value; timer = root.setTimeout(function () { feedback.textContent = ''; }, 4000); }
    trigger.addEventListener('click', function () { menu.hidden ? open() : close(false); });
    trigger.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowDown' || event.key === 'Enter' || event.key === ' ') { event.preventDefault(); open(0); }
    });
    menu.addEventListener('keydown', function (event) {
      var index = items.indexOf(document.activeElement);
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(true); }
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); items[(index + (event.key === 'ArrowDown' ? 1 : items.length - 1)) % items.length].focus(); }
      if (event.key === 'Home') { event.preventDefault(); items[0].focus(); }
      if (event.key === 'End') { event.preventDefault(); items[items.length - 1].focus(); }
    });
    document.addEventListener('click', function (event) { if (!toolbar.contains(event.target)) { close(false); } });
    toolbar.addEventListener('focusout', function () {
      root.setTimeout(function () { if (!toolbar.contains(document.activeElement)) { close(false); } }, 0);
    });
    items.forEach(function (item) {
      item.addEventListener('click', function () {
        close(true);
        var format = item.getAttribute('data-psi-export-format'), context = provider();
        if (format === 'print') { try { context.print(); message('Print dialog opened. Save as PDF from your browser.'); } catch (error) { message('Could not open the print dialog.'); } return; }
        if (!context.columns || !context.columns.length) { message('No export fields are configured.'); return; }
        if (!context.records || !context.records.length) { message('No matching records to export.'); return; }
        message('Exporting ' + context.records.length + ' records\u2026');
        try {
          var name = fileName(context.reportTitle, context.contextTitle, format === 'csv' ? 'csv' : 'xlsx', context.fileName);
          if (format === 'csv') { download(toCsv(context.records, context.columns, context.labels, context.valueReader), name, 'text/csv;charset=utf-8'); }
          else if (format === 'xlsx') { download(toXlsx(context.records, context.columns, context.labels, context.worksheetName || context.contextTitle, context.valueReader), name, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'); }
          else { throw new Error('Unsupported export format.'); }
          message('Prepared ' + context.records.length + ' records for download.');
        } catch (error) { message('Export failed: ' + (error && error.message ? error.message : 'Unknown error')); }
      });
    });
  }
  root.PSIExport = { escapeCsv: escapeCsv, toCsv: toCsv, toXlsx: toXlsx, safeName: safeName, fileName: fileName,
    attachToolbar: attachToolbar, downloadCsv: function (contents, name) { download(contents, name, 'text/csv;charset=utf-8'); } };
  document.querySelectorAll('[data-psi-export-scope="report"]').forEach(function (toolbar) {
    attachToolbar(toolbar, function () { return { print: function () { root.print(); } }; });
  });
}(window));
