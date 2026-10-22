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
    parser.add_argument('--palette-query', default=None)
    parser.add_argument('--palette-mode', choices=['Search', 'Commands'], default='Search')
    parser.add_argument('--palette-shortcut', choices=['click', 'ctrl', 'meta'], default='click')
    parser.add_argument('--palette-keys', default='')
    parser.add_argument('--relationship-exercise', choices=['Tree', 'Topology', 'Explorer'], default='')
    parser.add_argument('--relationship-node-id', default='')
    parser.add_argument('--relationship-edge-id', default='')
    parser.add_argument('--relationship-detail-filter', default='', help='Filter label=value, such as Site=West')
    parser.add_argument('--resource', default='', help='Select a synthetic Resource Explorer node ID')
    parser.add_argument('--inspector-tab', default='', help='Select a Context Inspector tab by visible label')
    parser.add_argument('--topology-workspace', action='store_true', help='Exercise the Fluent topology and Resource Workspace integration')
    args = parser.parse_args()
    chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    report_dir = Path(__file__).resolve().parents[1] / 'Reports'
    with tempfile.TemporaryDirectory(prefix='psi-browser-', dir=report_dir, ignore_cleanup_errors=True) as profile:
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
            runtime_errors = []

            def call(method, params=None):
                nonlocal sequence
                sequence += 1
                send(sock, {'id': sequence, 'method': method, 'params': params or {}})
                while True:
                    message = receive(sock)
                    if message.get('method') == 'Runtime.exceptionThrown':
                        runtime_errors.append(message.get('params', {}).get('exceptionDetails', {}).get('text', 'Uncaught JavaScript exception'))
                    if message.get('method') == 'Runtime.consoleAPICalled' and message.get('params', {}).get('type') == 'error':
                        runtime_errors.append('console.error')
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
            if args.resource:
                evaluate("(()=>{let b=document.querySelector('[data-psi-resource-restore]');if(innerWidth<=900)b.click();document.querySelector('[data-psi-resource-node=' + %s + ']').click()})()" % json.dumps('"' + args.resource + '"'))
            if args.inspector_tab:
                evaluate("[...document.querySelectorAll('[data-psi-inspector-tabs] [role=tab]')].find(x=>x.textContent.trim()===%s).click()" % json.dumps(args.inspector_tab))
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
            relationship_metrics = None
            if args.relationship_exercise:
                relationship_metrics = evaluate("JSON.stringify((()=>{"
                    "let view=document.querySelector('[data-psi-app-view]:not([hidden])'),root=view.querySelector('[data-psi-rel-component]'),"
                    "mode=%s,output={mode:mode},data=JSON.parse(root.querySelector('[data-psi-rel-data]').textContent),"
                    "search=root.querySelector('[data-psi-rel-search]'),detail=root.querySelector('[data-psi-rel-detail]');"
                    "output.nodes=data.Nodes.length;output.edges=data.Edges.length;"
                    "output.domReadyMs=Math.round(performance.getEntriesByType('navigation')[0].domContentLoadedEventEnd);"
                    "if(mode==='Tree'){let first=root.querySelector('[data-psi-rel-node][aria-expanded]');"
                    "first.focus();first.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowLeft',bubbles:true}));output.collapsed=first.getAttribute('aria-expanded')==='false';"
                    "first.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}));output.expanded=first.getAttribute('aria-expanded')==='true';"
                    "first.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true}));output.keyboardSelection=root.querySelector('[data-psi-rel-node][aria-selected=true]')?.getAttribute('data-psi-rel-node');"
                    "search.value='does-not-exist';search.dispatchEvent(new Event('input',{bubbles:true}));output.emptyVisible=!root.querySelector('[data-psi-rel-filter-empty]').hidden;"
                    "search.value='';search.dispatchEvent(new Event('input',{bubbles:true}));}"
                    "if(mode==='Topology'){let node=root.querySelectorAll('.psi-rel-graph-node')[1],edge=root.querySelector('.psi-rel-edge-group');"
                    "let selectionStart=performance.now();node.dispatchEvent(new MouseEvent('click',{bubbles:true}));"
                    "output.selectionMs=Math.round((performance.now()-selectionStart)*100)/100;"
                    "output.nodeSelected=node.getAttribute('aria-pressed')==='true';"
                    "edge.dispatchEvent(new MouseEvent('click',{bubbles:true}));output.edgeSelected=edge.getAttribute('aria-pressed')==='true';"
                    "let f=root.querySelector('[data-psi-rel-filter=status]');f.value='Warning';"
                    "let filterStart=performance.now();f.dispatchEvent(new Event('change',{bubbles:true}));"
                    "output.filterMs=Math.round((performance.now()-filterStart)*100)/100;"
                    "output.filteredCount=root.querySelector('[data-psi-rel-count]').textContent;"
                    "f.value='';f.dispatchEvent(new Event('change',{bubbles:true}));"
                    "let zoom=root.querySelector('[data-psi-rel-zoom=in]');zoom.click();output.zoomed=root.querySelector('[data-psi-rel-svg]').style.width!=='';}"
                    "if(mode==='Explorer'){let edge=root.querySelectorAll('.psi-rel-edge-item')[1];edge.click();"
                    "output.edgeSelected=edge.getAttribute('aria-pressed')==='true';output.hasEndpoints=detail.textContent.includes('Endpoints');}"
                    "output.detail=detail.textContent.slice(0,100);output.overflow=document.documentElement.scrollWidth>innerWidth;"
                    "output.themeBefore=document.documentElement.getAttribute('data-theme');"
                    "let other=output.themeBefore==='Dark'?'Light':'Dark';document.querySelector('[data-psi-theme=\"'+other+'\"]').click();"
                    "output.themeSwitched=document.documentElement.getAttribute('data-theme')===other;"
                    "document.querySelector('[data-psi-theme=\"'+output.themeBefore+'\"]').click();"
                    "if(mode==='Tree'){let action=detail.querySelector('.psi-rel-detail-link');"
                    "let target=[...detail.querySelectorAll('.psi-rel-detail-link')].find(x=>x.textContent.includes('Open resource'));"
                    "if(target){target.click();output.crossView=document.querySelector('[data-psi-app-view]:not([hidden])')?.getAttribute('data-psi-app-view');"
                    "document.querySelector('#psi-app-item-'+%s).click();}}"
                    "return output})())" % (json.dumps(args.relationship_exercise), json.dumps(args.view)))
            if args.relationship_node_id:
                evaluate("document.querySelector('.psi-rel-graph-node[data-psi-rel-id=' + %s + ']').dispatchEvent(new MouseEvent('click',{bubbles:true}))" % json.dumps('"' + args.relationship_node_id + '"'))
            if args.relationship_edge_id:
                evaluate("document.querySelector('.psi-rel-edge-group[data-psi-rel-id=' + %s + ']').dispatchEvent(new MouseEvent('click',{bubbles:true}))" % json.dumps('"' + args.relationship_edge_id + '"'))
            topology_metrics = None
            if args.topology_workspace:
                topology_metrics = evaluate("JSON.stringify((()=>{let root=document.querySelector('#infrastructure-topology'),"
                    "svg=root.querySelector('[data-psi-rel-svg]'),viewport=root.querySelector('.psi-rel-viewport'),"
                    "dc=root.querySelector('.psi-rel-graph-node[data-psi-rel-id=dc01]'),"
                    "initial=svg.style.width,rect=viewport.getBoundingClientRect(),"
                    "visible=getComputedStyle(viewport).display!=='none'&&rect.width>0&&rect.height>0,"
                    "nodeCount=root.querySelectorAll('.psi-rel-graph-node').length,edgeCount=root.querySelectorAll('.psi-rel-edge-group').length,"
                    "iconCount=root.querySelectorAll('.psi-rel-graph-node svg').length;"
                    "root.querySelector('[data-psi-rel-zoom=in]').click();let zoomed=svg.style.width!==initial;"
                    "root.querySelector('[data-psi-rel-zoom=fit]').click();let fitted=svg.style.width!=='';"
                    "root.querySelector('[data-psi-rel-zoom=reset]').click();"
                    "viewport.scrollLeft=Math.min(400,viewport.scrollWidth-viewport.clientWidth);let panned=viewport.scrollLeft>0;"
                    "viewport.scrollIntoView({block:'center'});let scrollBefore=scrollY;"
                    "dc.dispatchEvent(new MouseEvent('click',{bubbles:true}));"
                    "let pagePreserved=Math.abs(scrollY-scrollBefore)<5;"
                    "let selected=document.querySelector('[data-psi-resource-node=dc01]').getAttribute('aria-selected')==='true',"
                    "header=document.querySelector('[data-psi-resource-header-title]').textContent,"
                    "inspector=document.querySelector('[data-psi-inspector-title]').textContent,"
                    "viewBefore=document.querySelector('[data-psi-app-view]:not([hidden])').getAttribute('data-psi-app-view');"
                    "document.querySelector('#psi-app-item-overview').click();document.querySelector('#psi-app-item-topology').click();"
                    "return {visible:visible,width:Math.round(rect.width),height:Math.round(rect.height),nodes:nodeCount,"
                    "edges:edgeCount,icons:iconCount,zoomed:zoomed,fitted:fitted,panned:panned,pagePreserved:pagePreserved,selected:selected,"
                    "header:header,inspector:inspector,viewBefore:viewBefore,viewAfter:document.querySelector('[data-psi-app-view]:not([hidden])').getAttribute('data-psi-app-view'),"
                    "sameNode:dc===root.querySelector('.psi-rel-graph-node[data-psi-rel-id=dc01]'),"
                    "nodeCountAfter:root.querySelectorAll('.psi-rel-graph-node').length,edgeCountAfter:root.querySelectorAll('.psi-rel-edge-group').length,"
                    "overflow:document.documentElement.scrollWidth>innerWidth}})())")
                evaluate("document.querySelector('#infrastructure-topology .psi-rel-viewport').scrollIntoView({block:'center'})")
            detail_filter_metrics = None
            if args.relationship_detail_filter:
                label, value = args.relationship_detail_filter.split('=', 1)
                detail_filter_metrics = evaluate("JSON.stringify((()=>{let root=document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-rel-component]'),f=[...root.querySelectorAll('[data-psi-rel-filter-detail]')].find(x=>x.getAttribute('data-psi-rel-filter-detail')===%s);if(!f)return {error:'filter missing'};f.value=%s;f.dispatchEvent(new Event('change',{bubbles:true}));return {label:%s,value:f.value,count:root.querySelector('[data-psi-rel-count]').textContent,visible:[...root.querySelectorAll('.psi-rel-graph-node')].map(x=>x.getAttribute('aria-label'))}})())" % (json.dumps(label), json.dumps(value), json.dumps(label)))
            palette_timing = None
            if args.palette_query is not None:
                if args.palette_shortcut == 'click':
                    evaluate("document.querySelector('[data-psi-global-search-trigger]').click()")
                else:
                    modifier = 'ctrlKey' if args.palette_shortcut == 'ctrl' else 'metaKey'
                    evaluate("document.dispatchEvent(new KeyboardEvent('keydown',{key:'k',%s:true,bubbles:true}))" % modifier)
                if args.palette_mode == 'Commands':
                    evaluate("document.querySelector('[data-psi-global-mode=\"Commands\"]').click()")
                palette_timing = evaluate("(()=>{let i=document.querySelector('[data-psi-global-search-input]'),t=performance.now();i.value=%s;i.dispatchEvent(new Event('input',{bubbles:true}));return performance.now()-t})()" % json.dumps(args.palette_query))
                for key in filter(None, args.palette_keys.split(',')):
                    evaluate("document.querySelector('[data-psi-global-search-input]').dispatchEvent(new KeyboardEvent('keydown',{key:%s,bubbles:true}))" % json.dumps(key))
            time.sleep(.25)
            metrics = evaluate("JSON.stringify((()=>{let v=[...document.querySelectorAll('[data-psi-app-view]')],n=[...document.querySelectorAll('[data-psi-app-item]')],a=n.filter(x=>x.hasAttribute('aria-current'))[0],s=a&&a.querySelector('.psi-icon-filled'),r=a&&a.querySelector('.psi-icon-regular'),x=document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-app-explorer]');return {view:v.filter(x=>!x.hidden).map(x=>x.getAttribute('data-psi-app-view')),viewCount:v.length,heading:document.querySelector('[data-psi-app-view-title]').textContent,selected:a&&a.id,filled:s&&getComputedStyle(s).display!=='none'&&s.getBBox().width>0,regularHidden:r&&getComputedStyle(r).display==='none',navigationIcons:n.filter(x=>{let i=x.querySelector('.psi-icon-regular');return i&&i.querySelector('path')}).length,navOpen:document.querySelector('.psi-app-shell').classList.contains('psi-app-nav-open'),focus:document.activeElement.getAttribute('aria-label')||document.activeElement.id,scrollWidth:document.documentElement.scrollWidth,innerWidth:innerWidth,theme:document.documentElement.getAttribute('data-theme'),selectedRecord:document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-explorer-item][aria-selected=true]')?.textContent.trim()||null,visibleItems:x?[...x.querySelectorAll('[data-psi-explorer-item]')].filter(i=>!i.hidden).length:null}})())")
            assessment_metrics = evaluate("JSON.stringify((()=>{let c=document.querySelector('[data-psi-app-view]:not([hidden]) [data-psi-entity-type=\"Check\"]');return {decision:document.querySelector('.psi-assessment-decision')?.textContent.trim()||null,score:document.querySelector('.psi-assessment-gauge strong')?.textContent.trim()||null,checkVisible:c?[...c.querySelectorAll('[data-psi-explorer-item]')].filter(i=>!i.hidden).length:null,checkCategory:c?.querySelector('[data-psi-explorer-filter=\"CategoryId\"]')?.value||null}})())")
            palette_metrics = evaluate("JSON.stringify((()=>{let p=document.querySelector('[data-psi-global-search-backdrop]'),r=document.querySelector('[data-psi-global-search-results]'),i=document.querySelector('[data-psi-global-search-input]'),e=document.querySelector('[data-psi-export-scope=report] [data-psi-export-menu]'),v=document.querySelector('[data-psi-app-view]:not([hidden])'),s=v?.querySelector('[data-psi-explorer-search], [data-psi-search]');return p?{open:!p.hidden,indexCount:window.PSIGlobalSearch?.count,indexBytes:window.PSIGlobalSearch?.indexBytes,queryMs:%s,options:[...r.querySelectorAll('[role=option]')].map(x=>x.textContent.trim()),selected:i.getAttribute('aria-activedescendant'),focus:document.activeElement.id||document.activeElement.getAttribute('aria-label'),record:v?.querySelector('[data-psi-explorer-item][aria-selected=true]')?.getAttribute('data-psi-entity-id')||null,localSearch:s?.value||'',visibleRecords:v?[...v.querySelectorAll('[data-psi-explorer-item]')].filter(x=>!x.hidden).length:null,exportOpen:e?!e.hidden:false,theme:document.documentElement.getAttribute('data-theme')}:null})())" % ('null' if palette_timing is None else str(palette_timing)))
            resource_metrics = evaluate("JSON.stringify((()=>{let n=document.querySelector('[data-psi-resource-node][aria-selected=true]'),h=document.querySelector('[data-psi-resource-header]'),i=document.querySelector('[data-psi-context-inspector]');return n?{selected:n.getAttribute('data-psi-resource-node'),header:h?.querySelector('[data-psi-resource-header-title]')?.textContent,status:h?.querySelector('[data-psi-resource-header-status]')?.textContent,tags:h?.querySelector('[data-psi-resource-header-tags]')?.textContent,inspector:i?.querySelector('[data-psi-inspector-title]')?.textContent,inspectorStatus:i?.querySelector('[data-psi-inspector-status]')?.textContent,tabs:i?[...i.querySelectorAll('[role=tab]')].map(x=>x.textContent):[],activeTab:i?.querySelector('[role=tab][aria-selected=true]')?.textContent,panel:i?.querySelector('[role=tabpanel]')?.textContent.slice(0,200),overflow:document.documentElement.scrollWidth>innerWidth}:null})())")
            screenshot = call('Page.captureScreenshot', {'format': 'png', 'captureBeyondViewport': False})['data']
            args.output.write_bytes(base64.b64decode(screenshot))
            print(metrics)
            print(assessment_metrics)
            print(palette_metrics)
            if resource_metrics is not None:
                print(resource_metrics)
            if relationship_metrics is not None:
                print(relationship_metrics)
            if detail_filter_metrics is not None:
                print(detail_filter_metrics)
            if topology_metrics is not None:
                print(topology_metrics)
            print(json.dumps({'javascriptErrors': runtime_errors}))
            print(args.output)
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
            time.sleep(.2)


if __name__ == '__main__':
    main()
