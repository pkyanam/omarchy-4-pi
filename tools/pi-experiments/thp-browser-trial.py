#!/usr/bin/env python3
"""Owner-run Linux Chromium trial. No policy writes or automatic installation.

Requires an already installed python websocket-client module. Outputs are private
until reviewed. A successful run is collected evidence, not an accepted A/B trial.
"""
import argparse
import hashlib
import http.server
import importlib.util
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import threading
import time
import urllib.request

HERE = Path(__file__).resolve().parent
THP = Path('/sys/kernel/mm/transparent_hugepage')
CATEGORIES = 'benchmark,latencyInfo,devtools.timeline,blink.user_timing,toplevel,viz,input'


def digest(path):
  return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
  try:
    return Path(path).read_text().strip()
  except OSError:
    return None


def write(path, data):
  Path(path).write_text(json.dumps(data, indent=2) + '\n')


def policy():
  # Counters are captured separately; this is the invariant control set.
  paths = [p for p in THP.rglob('*') if p.is_file() and 'stats' not in p.parts
           and p.name not in ('pages_collapsed', 'full_scans')]
  return {str(p.relative_to(THP)): read(p) for p in sorted(paths)}


def selected(value):
  return next((v[1:-1] for v in (value or '').split() if v.startswith('[') and v.endswith(']')), None)


def process_tree(root):
  parents = {}
  for path in Path('/proc').glob('[0-9]*/stat'):
    value = read(path)
    if value:
      try:
        rest = value[value.rindex(')') + 2:].split()
        parents[int(path.parent.name)] = int(rest[1])
      except (ValueError, IndexError):
        continue
  found = {root}
  while True:
    more = {pid for pid, parent in parents.items() if parent in found} | found
    if more == found:
      return sorted(found)
    found = more


def rss_sample(root):
  tasks = {}
  for pid in process_tree(root):
    status = read(f'/proc/{pid}/status')
    fields = {}
    if status:
      for line in status.splitlines():
        if line.startswith(('Name:', 'VmRSS:', 'RssAnon:', 'RssFile:', 'VmSwap:')):
          key, value = line.split(':', 1)
          fields[key] = value.strip()
    tasks[str(pid)] = fields or None
  return {'monotonic_ns': time.monotonic_ns(), 'processes': tasks,
          'memory_psi': read('/proc/pressure/memory'), 'vmstat': read('/proc/vmstat'),
          'meminfo': read('/proc/meminfo')}


class CDP:
  def __init__(self, url):
    import websocket
    self.ws = websocket.create_connection(url, timeout=8, suppress_origin=True)
    self.ident = 0
    self.events = []

  def call(self, method, params=None):
    self.ident += 1
    ident = self.ident
    self.ws.send(json.dumps({'id': ident, 'method': method, 'params': params or {}}))
    deadline = time.monotonic() + 8
    while True:
      remaining = deadline - time.monotonic()
      if remaining <= 0:
        raise TimeoutError(f'{method}: CDP deadline')
      self.ws.settimeout(remaining)
      reply = json.loads(self.ws.recv())
      if reply.get('id') == ident:
        if 'error' in reply:
          raise RuntimeError(f'{method}: {reply["error"]}')
        return reply.get('result', {})
      self.events.append(reply)

  def evaluate(self, expression):
    reply = self.call('Runtime.evaluate', {'expression': expression, 'awaitPromise': True, 'returnByValue': True})
    if 'exceptionDetails' in reply:
      raise RuntimeError(str(reply['exceptionDetails']))
    return reply['result'].get('value')

  def close(self):
    self.ws.close()


def fetch(url):
  # No proxy or non-loopback URL is used by the harness.
  with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(url, timeout=3) as response:
    return json.load(response)


def trace_save(browser, output):
  browser.call('Tracing.end')
  deadline = time.monotonic() + 20
  complete = next((e for e in browser.events if e.get('method') == 'Tracing.tracingComplete'), None)
  while complete is None and time.monotonic() < deadline:
    event = json.loads(browser.ws.recv())
    if event.get('method') == 'Tracing.tracingComplete':
      complete = event
  if complete is None or complete['params'].get('dataLossOccurred'):
    raise RuntimeError('trace incomplete or data lost')
  handle = complete['params']['stream']
  size = 0
  with output.open('w') as stream:
    while True:
      part = browser.call('IO.read', {'handle': handle, 'size': 65536})
      if part.get('base64Encoded'):
        raise RuntimeError('unexpected encoded trace')
      size += len(part['data'].encode())
      if size > 256 * 1024 * 1024 or time.monotonic() > deadline:
        raise RuntimeError('trace output bound exceeded')
      stream.write(part['data'])
      if part.get('eof'):
        break
  browser.call('IO.close', {'handle': handle})


def run(args):
  if platform.system() != 'Linux' or os.geteuid() == 0:
    raise RuntimeError('run as the desktop user on Linux; never root')
  import websocket  # Explicit dependency check before any browser launch.
  del websocket
  if not (os.environ.get('WAYLAND_DISPLAY') or os.environ.get('DISPLAY')):
    raise RuntimeError('requires the existing graphical desktop')
  chromium = Path(args.chromium).resolve(strict=True)
  if not chromium.is_file() or not os.access(chromium, os.X_OK):
    raise RuntimeError('chromium must be an installed executable')
  before_policy = policy()
  if selected(before_policy.get('enabled')) != args.policy:
    raise RuntimeError('top-level THP does not match declared policy; no write attempted')
  if any(selected(v) == 'always' for k, v in before_policy.items() if k.startswith('hugepages-') and k.endswith('/enabled')):
    raise RuntimeError('explicit per-size always defeats inherited-policy comparison; parent review required')
  alarms = sorted(Path('/sys/class/hwmon').glob('*/in0_lcrit_alarm'))
  temp = Path('/sys/class/thermal/thermal_zone0/temp')
  if not alarms:
    raise RuntimeError('native voltage alarm unavailable')
  def health():
    value = read(temp)
    voltage = [read(p) for p in alarms]
    if value is None or any(v != '0' for v in voltage):
      raise RuntimeError('missing health telemetry or voltage alarm')
    temperature = int(value) / 1000
    if temperature >= 75:
      raise RuntimeError('75 C health stop')
    return {'temperature_c': temperature, 'voltage': voltage}
  def interrupted(signum, _frame):
    raise RuntimeError(f'interrupted by signal {signum}')
  signal.signal(signal.SIGTERM, interrupted)
  initial_health = health()
  if not args.start_min <= initial_health['temperature_c'] <= args.start_max:
    raise RuntimeError('start temperature outside predeclared window')
  out = Path(args.output).resolve()
  out.mkdir(mode=0o700, parents=False, exist_ok=False)
  profile = out / 'profile'
  profile.mkdir(mode=0o700)
  page = (HERE / 'thp-browser-page.html').read_bytes()
  class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
      if self.path.split('?')[0] != '/corpus':
        self.send_error(404)
        return
      self.send_response(200)
      self.send_header('Content-Type', 'text/html; charset=utf-8')
      self.send_header('Content-Length', str(len(page)))
      self.send_header('Cache-Control', 'no-store')
      self.end_headers()
      self.wfile.write(page)
    def log_message(self, *_):
      pass
  server = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
  threading.Thread(target=server.serve_forever, daemon=True).start()
  spec = importlib.util.spec_from_file_location('low_level_snapshot', HERE / 'low-level-snapshot.py')
  snapshot = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(snapshot)
  # Ordinary headed multiprocess Chromium; no sandbox, GPU, site-isolation,
  # renderer-count, memory-pressure or security switches are overridden.
  command = [str(chromium), f'--user-data-dir={profile}', '--no-first-run',
             '--no-default-browser-check', '--remote-debugging-address=127.0.0.1',
             '--remote-debugging-port=0', '--new-window', 'about:blank']
  manifest = {'schema': 'thp-browser-v1', 'label': args.label, 'declared_policy': args.policy,
              'utc_ns': time.time_ns(), 'monotonic_ns': time.monotonic_ns(),
              'boot_id': read('/proc/sys/kernel/random/boot_id'), 'kernel': platform.release(),
              'command': command, 'parameters': vars(args), 'profile_seed': 'new empty directory, no user data copied',
              'profile_seed_sha256': hashlib.sha256(b'').hexdigest(),
              'hashes': {name: digest(HERE / name) for name in ('thp-browser-trial.py', 'thp-browser-page.html', 'low-level-snapshot.py')},
              'chromium_launcher_sha256': digest(chromium), 'policy_before': before_policy,
              'initial_health': initial_health, 'owner_context': json.loads(Path(args.context).read_text()),
              'context_sha256': digest(args.context),
              'trace_categories': CATEGORIES, 'latency_status': 'pending trace correlation; RAF proxy is not presentation latency'}
  write(out / 'manifest.json', manifest)
  proc = None
  browser = None
  clients = []
  stop = threading.Event()
  errors = []
  actions = []
  success = False
  tracing = False
  active_deadline = None
  def monitor():
    baseline_oom = None
    try:
      with (out / 'samples.jsonl').open('w') as stream:
        for _ in range(180):
          if stop.is_set():
            return
          if active_deadline is not None and time.monotonic() > active_deadline:
            raise RuntimeError('120-second active replay bound')
          sample = rss_sample(proc.pid)
          sample['health'] = health()
          counters = dict(line.split() for line in sample['vmstat'].splitlines())
          oom = int(counters['oom_kill'])
          if baseline_oom is None:
            baseline_oom = oom
          if oom != baseline_oom:
            raise RuntimeError('new system OOM kill')
          stream.write(json.dumps(sample) + '\n')
          stream.flush()
          stop.wait(1)
        raise RuntimeError('180-second whole-trial bound')
    except Exception as error:
      errors.append(str(error))
      # Signal only our private browser process group; no desktop services.
      if proc and proc.poll() is None:
        os.killpg(proc.pid, signal.SIGTERM)
  worker = None
  try:
    with (out / 'chromium.log').open('w') as log:
      proc = subprocess.Popen(command, stdout=log, stderr=log, start_new_session=True)
    worker = threading.Thread(target=monitor, daemon=True)
    worker.start()
    deadline = time.monotonic() + 15
    port_file = profile / 'DevToolsActivePort'
    while not port_file.exists():
      if proc.poll() is not None or time.monotonic() > deadline:
        raise RuntimeError('browser startup failure/timeout')
      time.sleep(.1)
    port, endpoint = port_file.read_text().splitlines()[:2]
    base = f'http://127.0.0.1:{int(port)}'
    browser = CDP(f'ws://127.0.0.1:{int(port)}{endpoint}')
    manifest['browser_version'] = browser.call('Browser.getVersion')
    for tab in range(12):
      target = browser.call('Target.createTarget', {'url': f'http://127.0.0.1:{args.port}/corpus?tab={tab}'})['targetId']
      info = next(t for t in fetch(base + '/json/list') if t['id'] == target)
      client = CDP(info['webSocketDebuggerUrl'])
      clients.append((target, client))
      ready_end = time.monotonic() + 8
      while not client.evaluate('Boolean(window.fixtureReady)'):
        if time.monotonic() > ready_end:
          raise RuntimeError('corpus readiness timeout')
        time.sleep(.1)
    # Remove only the private startup blank tab, leaving exactly twelve tabs.
    for target in browser.call('Target.getTargets')['targetInfos']:
      if target['type'] == 'page' and target['url'] == 'about:blank':
        browser.call('Target.closeTarget', {'targetId': target['targetId']})
    browser.call('Target.activateTarget', {'targetId': clients[0][0]})
    def boundary(name):
      at = time.monotonic_ns()
      data = snapshot.capture(process_tree(proc.pid) + args.pid)
      data.update({'label': args.label + '-' + name, 'monotonic_start_ns': at,
                   'monotonic_end_ns': time.monotonic_ns()})
      write(out / (name + '.json'), data)
    boundary('before')
    browser.call('Tracing.start', {'categories': CATEGORIES, 'transferMode': 'ReturnAsStream'})
    tracing = True
    start = time.monotonic()
    active_deadline = start + 120
    def action(tab, name, method, params):
      if time.monotonic() - start > 120 or errors:
        raise RuntimeError('active replay bound or health stop')
      target, client = clients[tab]
      tag = f'thp:{len(actions):03d}:{tab}:{name}'
      client.evaluate(f'performance.mark({json.dumps(tag)})')
      at = time.monotonic_ns()
      result = (browser if method == 'Target.activateTarget' else client).call(method, params)
      # Double RAF measures a page scheduling proxy, never physical presentation.
      proxy = client.evaluate('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve({now: performance.now(), visible: document.visibilityState}))))')
      if proxy['visible'] != 'visible':
        raise RuntimeError('target not foreground')
      actions.append({'tag': tag, 'tab': tab, 'action': name, 'dispatch_ns': at,
                      'proxy_done_ns': time.monotonic_ns(), 'page': proxy, 'cdp': result})
    # Ten foreground switches, fixed scrolling and real CDP key/text input.
    for tab in range(1, 11):
      action(tab, 'activate', 'Target.activateTarget', {'targetId': clients[tab][0]})
      for key in ('PageDown', 'PageDown', 'PageUp', 'PageUp'):
        action(tab, key, 'Input.dispatchKeyEvent', {'type': 'keyDown', 'key': key, 'code': key, 'windowsVirtualKeyCode': 34 if key == 'PageDown' else 33})
        clients[tab][1].call('Input.dispatchKeyEvent', {'type': 'keyUp', 'key': key, 'code': key})
      clients[tab][1].evaluate("scrollTo(0,0); document.querySelector('#note').focus()")
      action(tab, 'text', 'Input.insertText', {'text': ' Review complete.'})
    action(0, 'revisit-first', 'Target.activateTarget', {'targetId': clients[0][0]})
    manifest['active_seconds'] = time.monotonic() - start
    if manifest['active_seconds'] > 120:
      raise RuntimeError('active replay exceeded 120 seconds')
    active_deadline = None
    trace_save(browser, out / 'trace.json')
    tracing = False
    boundary('after')
    for tab, (_, client) in enumerate(clients):
      write(out / f'page-{tab:02d}.json', client.evaluate('window.fixture'))
    if errors or proc.poll() is not None:
      raise RuntimeError('health/browser failure')
    success = True
  except BaseException as error:
    errors.append(type(error).__name__ + ': ' + str(error))
    raise
  finally:
    # Preserve partial evidence on all failures. Parent independently restores THP.
    if tracing and browser:
      try:
        trace_save(browser, out / 'trace-partial.json')
      except Exception as error:
        errors.append('partial trace: ' + str(error))
    for client in [c for _, c in clients] + ([browser] if browser else []):
      try:
        client.close()
      except Exception as error:
        errors.append('CDP cleanup: ' + str(error))
    if proc:
      try:
        os.killpg(proc.pid, signal.SIGTERM)
      except ProcessLookupError:
        pass
      try:
        proc.wait(timeout=5)
      except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait(timeout=5)
    stop.set()
    if worker:
      worker.join(timeout=3)
    server.shutdown()
    server.server_close()
    write(out / 'actions.json', actions)
    manifest.update({'collection_complete': success and not errors, 'errors': errors,
                     'policy_after': policy(), 'policy_unchanged': before_policy == policy(),
                     'browser_returncode': proc.returncode if proc else None,
                     'cleanup': 'private main process reaped; profile retained for evidence; verify no orphan descendants',
                     'trial_acceptance': 'pending owner validation'})
    write(out / 'manifest.json', manifest)
  if not success or errors or not manifest['policy_unchanged']:
    raise RuntimeError('trial invalid; retain all artifacts')


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--chromium', required=True, help='absolute path to installed Chromium launcher')
  parser.add_argument('--output', required=True, help='new private directory; parent must exist')
  parser.add_argument('--context', required=True, help='immutable owner provenance JSON; see runbook')
  parser.add_argument('--label', required=True, help='e.g. block1-A1')
  parser.add_argument('--policy', required=True, choices=('always', 'madvise'))
  parser.add_argument('--pid', type=int, action='append', default=[], help='shell/compositor PID, repeated')
  parser.add_argument('--port', type=int, default=8765, help='fixed loopback corpus port, identical every trial')
  parser.add_argument('--start-min', type=float, default=40)
  parser.add_argument('--start-max', type=float, default=48)
  args = parser.parse_args()
  if not Path(args.chromium).is_absolute() or any(pid <= 0 for pid in args.pid):
    parser.error('absolute Chromium path and positive PIDs required')
  if not 1024 <= args.port <= 65535 or not 0 <= args.start_min <= args.start_max < 75:
    parser.error('invalid port or temperature window')
  if args.start_max - args.start_min > 8:
    parser.error('start temperature window must be at most 8 C')
  run(args)


if __name__ == '__main__':
  main()
