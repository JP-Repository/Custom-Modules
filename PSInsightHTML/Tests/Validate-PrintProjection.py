"""Development-only Chrome print-to-PDF validation for a standalone report."""
import argparse
import base64
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from urllib.parse import urlparse


sys.dont_write_bytecode = True
helper_spec = importlib.util.spec_from_file_location('psi_capture', Path(__file__).with_name('Capture-ApplicationView.py'))
helper = importlib.util.module_from_spec(helper_spec)
helper_spec.loader.exec_module(helper)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('html', type=Path)
    parser.add_argument('out_dir', type=Path)
    parser.add_argument('name')
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    with tempfile.TemporaryDirectory(prefix='psi-print-browser-', dir=args.out_dir) as profile:
        process = subprocess.Popen([chrome, '--headless=new', '--disable-gpu', '--disable-dev-shm-usage',
            '--no-sandbox', '--remote-allow-origins=*', '--remote-debugging-port=0',
            '--user-data-dir=' + profile, 'about:blank'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            port_file = Path(profile) / 'DevToolsActivePort'
            for _ in range(100):
                if port_file.exists():
                    break
                if process.poll() is not None:
                    raise RuntimeError('Chrome exited before opening DevTools')
                time.sleep(.1)
            port = int(port_file.read_text().splitlines()[0])
            with urllib.request.urlopen('http://127.0.0.1:%d/json/list' % port) as response:
                target = next(item for item in json.load(response) if item['type'] == 'page')
            sock = socket.create_connection(('127.0.0.1', port), timeout=10)
            key = base64.b64encode(os.urandom(16)).decode('ascii')
            request = ('GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\n'
                       'Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n'
                       'Origin: http://localhost\r\n\r\n') % (urlparse(target['webSocketDebuggerUrl']).path, port, key)
            sock.sendall(request.encode('ascii'))
            handshake = b''
            while b'\r\n\r\n' not in handshake:
                handshake += sock.recv(4096)
            if b'HTTP/1.1 101' not in handshake:
                raise RuntimeError('DevTools upgrade failed')
            sequence = 0

            def call(method, params=None):
                nonlocal sequence
                sequence += 1
                helper.send(sock, {'id': sequence, 'method': method, 'params': params or {}})
                while True:
                    message = helper.receive(sock)
                    if message.get('id') == sequence:
                        if 'error' in message:
                            raise RuntimeError(message['error'])
                        return message.get('result', {})

            def evaluate(expression):
                result = call('Runtime.evaluate', {'expression': expression, 'returnByValue': True})
                if result.get('exceptionDetails'):
                    raise RuntimeError(result['exceptionDetails'])
                return result['result'].get('value')

            call('Page.enable')
            call('Runtime.enable')
            call('Page.navigate', {'url': args.html.resolve().as_uri()})
            time.sleep(1.2)
            evaluate("document.querySelector('[data-psi-theme=Dark]').click()")
            if evaluate("typeof window.PSIPrint !== 'object'"):
                raise RuntimeError('Print action missing')
            action = evaluate("(()=>{window.__psiPrintCalls=0;window.print=function(){window.__psiPrintCalls++};document.querySelector('[data-psi-export-scope=report] [data-psi-export-trigger]').click();document.querySelector('[data-psi-export-scope=report] [data-psi-export-format=print]').click();return JSON.stringify({calls:window.__psiPrintCalls,active:document.body.classList.contains('psi-print-projection-active')})})()")
            print('Export action', action)
            evaluate('window.PSIPrint.restore()')
            activation_ms = evaluate("(()=>{var start=performance.now();window.PSIPrint.activate();return performance.now()-start})()")
            call('Emulation.setEmulatedMedia', {'media': 'print'})
            state = evaluate("JSON.stringify({document:getComputedStyle(document.getElementById('psi-print-document')).display,shell:getComputedStyle(document.querySelector('.psi-app-shell')).display,theme:getComputedStyle(document.documentElement).colorScheme,sections:document.querySelectorAll('.psi-print-section').length})")
            load_ms = evaluate("performance.getEntriesByType('navigation')[0]?.domContentLoadedEventEnd || null")
            print(args.name, state, 'dom_content_loaded_ms', load_ms, 'activation_ms', activation_ms)
            for name, width, height in [('A4', 8.27, 11.69), ('Letter', 8.5, 11.0)]:
                result = call('Page.printToPDF', {'printBackground': False, 'preferCSSPageSize': False,
                    'paperWidth': width, 'paperHeight': height, 'marginTop': .59, 'marginBottom': .67,
                    'marginLeft': .55, 'marginRight': .55, 'displayHeaderFooter': False})
                destination = args.out_dir / (args.name + '-' + name + '.pdf')
                destination.write_bytes(base64.b64decode(result['data']))
                print(destination, destination.stat().st_size)
            call('Emulation.setEmulatedMedia', {'media': 'screen'})
            evaluate('window.PSIPrint.restore()')
            print('Restored', evaluate("JSON.stringify({hidden:document.getElementById('psi-print-document').hidden,shell:getComputedStyle(document.querySelector('.psi-app-shell')).display})"))
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


if __name__ == '__main__':
    main()
