(function (root) {
  'use strict';
  var documentView = document.getElementById('psi-print-document');
  if (!documentView) { return; }
  var restoreTimer = null;
  function activate() {
    root.clearTimeout(restoreTimer);
    documentView.hidden = false;
    document.body.classList.add('psi-print-projection-active');
  }
  function restore() {
    document.body.classList.remove('psi-print-projection-active');
    documentView.hidden = true;
    root.clearTimeout(restoreTimer);
  }
  root.addEventListener('beforeprint', activate);
  root.addEventListener('afterprint', restore);
  root.PSIPrint = {
    print: function () {
      activate();
      try { root.print(); }
      catch (error) { restore(); throw error; }
      // Some browsers never fire afterprint when a print dialog is cancelled.
      restoreTimer = root.setTimeout(restore, 60000);
    },
    activate: activate,
    restore: restore
  };
}(window));
