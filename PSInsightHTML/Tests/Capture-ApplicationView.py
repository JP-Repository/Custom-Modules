"""Capture and inspect a standalone adaptive report with local Chrome.

Development-only visual aid. No Python packages or network assets required.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import time
import urllib.request
from urllib.parse import urlparse


def exact(sock, size):
    chunks = []
    while size:
        chunk = sock.recv(size)
        if not chunk:
            raise RuntimeError('Chrome disconnected')
        chunks.append(chunk)
        size -= len(chunk)
    return b''.join(chunks)


def send(sock, message):
    payload = json.dumps(message).encode('utf-8')
    mask = os.urandom(4)
    header = bytearray([0x81])
    if len(payload) < 126:
        header.append(0x80 | len(payload))
    elif len(payload) < 65536:
        header.extend([0x80 | 126])
        header.extend(struct.pack('!H', len(payload)))
    else:
        header.extend([0x80 | 127])
        header.extend(struct.pack('!Q', len(payload)))
    sock.sendall(bytes(header) + mask + bytes(value ^ mask[index % 4] for index, value in enumerate(payload)))


def receive(sock):
    first, second = exact(sock, 2)
    size = second & 0x7f
    if size == 126:
        size = struct.unpack('!H', exact(sock, 2))[0]
    elif size == 127:
        size = struct.unpack('!Q', exact(sock, 8))[0]
    mask = exact(sock, 4) if second & 0x80 else None
    payload = exact(sock, size)
    if mask:
        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    return json.loads(payload) if first & 0x0f == 1 else {}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('html', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--width', type=int, default=1440)
    parser.add_argument('--height', type=int, default=900)
    parser.add_argument('--view', default='overview')
    parser.add_argument('--theme', default='', choices=['', 'Light', 'Dark', 'Auto'])
    parser.add_argument('--drawer', action='store_true')
    parser.add_argument('--second-item', action='store_true')
    parser.add_argument('--item-index', type=int, default=-1)
    parser.add_argument('--view-command', action='store_true')
    parser.add_argument('--kpi-filter', action='store_true')
    parser.add_argument('--chart-filter', action='store_true')
    parser.add_argument('--search', default='')
    parser.add_argument('--cross-view', default='', choices=['', 'checks', 'findings', 'resources', 'evidence', 'exceptions'])
    parser.add_argument('--category', default='')
    parser.add_argument('--status', default='')
    args = parser.parse_args()
    chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    report_dir = Path(__file__).resolve().parents[1] / 'Reports'
    with tempfile.TemporaryDirectory(prefix='psi-browser-', dir=report_dir) as profile:
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
            path = urlparse(target['webSocketDebuggerUrl']).path
            sock = socket.create_connection(('127.0.0.1', port), timeout=10)
            key = base64.b64encode(os.urandom(16)).decode('ascii')
            request = ('GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\n'
                       'Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n'
                       'Origin: http://localhost\r\n\r\n') % (path, port, key)
            sock.sendall(request.encode('ascii'))
            handshake = b''
            while b'\r\n\r\n' not in handshake:
                handshake += sock.recv(4096)
            if b'HTTP/1.1 101' not in handshake:
                raise RuntimeError('DevTools WebSocket upgrade failed')
            sequence = 0

            def call(method, params=None):
                nonlocal sequence
                sequence += 1
                send(sock, {'id': sequence, 'method': method, 'params': params or {}})
                while True:
                    message = receive(sock)
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
            call('Page.bringToFront')
            call('Emulation.setDeviceMetricsOverride', {'width': args.width, 'height': args.height,
                'deviceScaleFactor': 1, 'mobile': args.width < 600})
            call('Page.navigate', {'url': args.html.resolve().as_uri()})
            time.sleep(1.2)
            if args.theme:
                evaluate("document.querySelector('[data-psi-theme=' + %s + ']').click()" % json.dumps('"' + args.theme + '"'))
            if args.drawer or (args.width < 600 and args.view != 'overview'):
                evaluate("document.querySelector('[data-psi-app-toggle]').click()")
            if args.view != 'overview':
                evaluate("document.querySelector('#psi-app-item-' + %s).click()" % json.dumps(args.view))
            if args.second_item:
                evaluate("document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-explorer-item=\"1\"]').click()")
            if args.item_index >= 0:
                evaluate("document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-entity-type=\"Check\"] [data-psi-explorer-item=' + %s + ']').click()" % json.dumps('"' + str(args.item_index) + '"'))
            if args.view_command:
                evaluate("document.querySelector('[data-psi-app-command-target]:not([hidden])').click()")
            if args.kpi_filter:
                evaluate("document.querySelector('[data-psi-filter-action]').click()")
            if args.chart_filter:
                evaluate("document.querySelector('[data-psi-chart-filter]').dispatchEvent(new MouseEvent('click',{bubbles:true}))")
            if args.search:
                evaluate("(()=>{let i=document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-explorer-search]');i.value=%s;i.dispatchEvent(new Event('input',{bubbles:true}))})()" % json.dumps(args.search))
            if args.cross_view:
                evaluate("document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-explorer-detail]:not([hidden]) [data-psi-cross-view=' + %s + ']').click()" % json.dumps('"' + args.cross_view + '"'))
            if args.category:
                evaluate("document.querySelector('[data-psi-category-id=' + %s + ']').click()" % json.dumps('"' + args.category + '"'))
            if args.status:
                evaluate("(()=>{let f=document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-entity-type=\"Check\"] [data-psi-explorer-filter=\"Status\"]');f.value=%s;f.dispatchEvent(new Event('change',{bubbles:true}))})()" % json.dumps(args.status))
            time.sleep(.25)
            metrics = evaluate("JSON.stringify((()=>{let v=[...document.querySelectorAll('[data-psi-app-view]')],n=[...document.querySelectorAll('[data-psi-app-item]')],a=n.filter(x=>x.hasAttribute('aria-current'))[0],s=a&&a.querySelector('.psi-icon-filled'),r=a&&a.querySelector('.psi-icon-regular'),x=document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-app-explorer]');return {view:v.filter(x=>!x.hidden).map(x=>x.getAttribute('data-psi-app-view')),viewCount:v.length,heading:document.querySelector('[data-psi-app-view-title]').textContent,selected:a&&a.id,filled:s&&getComputedStyle(s).display!=='none'&&s.getBBox().width>0,regularHidden:r&&getComputedStyle(r).display==='none',navigationIcons:n.filter(x=>{let i=x.querySelector('.psi-icon-regular');return i&&i.querySelector('path')}).length,navOpen:document.querySelector('.psi-app-shell').classList.contains('psi-app-nav-open'),focus:document.activeElement.getAttribute('aria-label')||document.activeElement.id,scrollWidth:document.documentElement.scrollWidth,innerWidth:innerWidth,theme:document.documentElement.getAttribute('data-theme'),selectedRecord:document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-explorer-item][aria-selected=true]')?.textContent.trim()||null,visibleItems:x?[...x.querySelectorAll('[data-psi-explorer-item]')].filter(i=>!i.hidden).length:null}})())")
            assessment_metrics = evaluate("JSON.stringify((()=>{let c=document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-entity-type=\"Check\"]');return {decision:document.querySelector('.psi-assessment-decision')?.textContent.trim()||null,score:document.querySelector('.psi-assessment-gauge strong')?.textContent.trim()||null,checkVisible:c?[...c.querySelectorAll('[data-psi-explorer-item]')].filter(i=>!i.hidden).length:null,checkCategory:c?.querySelector('[data-psi-explorer-filter=\"CategoryId\"]')?.value||null}})())")
            screenshot = call('Page.captureScreenshot', {'format': 'png', 'captureBeyondViewport': False})['data']
            args.output.write_bytes(base64.b64decode(screenshot))
            print(metrics)
            print(assessment_metrics)
            print(args.output)
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


if __name__ == '__main__':
    main()
