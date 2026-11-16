"""Loopback-only TCP relay to the two configured MyProxy transports .

Payloads are opaque. We never resolve/connect a destination from an HTTP request,
terminate TLS, or replay data after an upstream connection has been selected.
"""
import copy
import ipaddress
import json
import select
import socket
import socketserver
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from urllib.parse import urlsplit
from pathlib import Path


PRIVATE_LAN = tuple(ipaddress.ip_network(n) for n in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'))
HALF_CLOSE_IDLE_TIMEOUT = 15


def endpoint(url):
    parts = urlsplit(url)
    address = ipaddress.ip_address(parts.hostname)
    if parts.scheme != 'http' or not parts.port or parts.username or parts.password or parts.path not in ('', '/') or parts.query or parts.fragment:
        raise ValueError('Endpoint MyProxy inválido.')
    return str(address), parts.port


def validate_fallback(config):
    value = config.get('proxyFallback')
    if value is None:
        return None
    try:
        listen = endpoint(config['proxy'])
        usb, wifi = endpoint(value['usb']), endpoint(value['wifi'])
        if listen != ('127.0.0.1', 8890) or usb[0] != '127.0.0.1' or usb == listen:
            raise ValueError()
        address = ipaddress.ip_address(wifi[0])
        if address.version != 4 or not any(address in network for network in PRIVATE_LAN):
            raise ValueError()
        return {'listen': listen, 'endpoints': {'usb': value['usb'], 'wifi': value['wifi']}}
    except (ValueError, TypeError, KeyError, AttributeError) as error:
        raise ValueError('Fallback exige relay local 8890, USB local separado e Wi-Fi privado explícito, sem credenciais.') from error


def probe_endpoint(url, phone_port):
    """Status alone is insufficient: also perform a verified TLS request via CONNECT."""
    deadline = time.monotonic() + 8

    def get(target, proxy):
        remaining = deadline - time.monotonic()
        if remaining <= 0: raise TimeoutError()
        # curl's connection phase includes CONNECT and TLS over the mobile link.
        connect_timeout = remaining if proxy else min(1, remaining)
        command = ['/usr/bin/curl', '-q', '--silent', '--show-error', '--fail',
                   '--connect-timeout', str(connect_timeout), '--max-time', str(remaining),
                   '--max-filesize', '8192', '--proxy', proxy or '',
                   '--noproxy', '' if proxy else '*', '--write-out', '\n%{http_code}', target]
        result = subprocess.run(command, capture_output=True, timeout=remaining + .2, check=True)
        body, status = result.stdout.rsplit(b'\n', 1)
        if status != b'200' or len(body) > 8192: raise ValueError('Resposta de saúde inválida.')
        return json.loads(body)

    data = get(url.rstrip('/') + '/__status', None)
    if data.get('isRunning') is not True or data.get('port') != phone_port or not data.get('build'):
        raise ValueError('MyProxy não confirmou serviço ativo.')
    response = get('https://api.ipify.org?format=json', url)
    return {'exitIp': str(ipaddress.ip_address(response['ip'])), 'wifiIP': data.get('wifiIP'), 'build': str(data['build'])}


class _Handler(socketserver.BaseRequestHandler):
    def handle(self):
        self.server.relay.handle(self.request)


class _Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    block_on_close = False

    def process_request(self, request, client_address):
        if not self.relay.slots.acquire(blocking=False):
            self.relay.unavailable(request)
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.relay.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.relay.slots.release()

    def handle_error(self, request, client_address):
        # No payload, destinations or raw transport exceptions in logs.
        pass


class MyProxyRelay:
    def __init__(self, listen, endpoints, *, probe=probe_endpoint, interval=5, ttl=25, pin_state_path=None):
        if listen[0] != '127.0.0.1':
            raise ValueError('O relay deve escutar apenas em loopback.')
        self.endpoints = dict(endpoints)
        self.targets = {key: endpoint(value) for key, value in endpoints.items()}
        self.expected_wifi_ip = self.targets['wifi'][0]
        self.pin_state_path = Path(pin_state_path) if pin_state_path else None
        self.wifi_blocked = False
        if self.pin_state_path and self.pin_state_path.exists():
            pin = json.loads(self.pin_state_path.read_text())
            self.wifi_blocked = pin.get('wifi') == endpoints['wifi'] and pin.get('blocked') is True
        self.probe, self.interval, self.ttl = probe, interval, ttl
        self.lock, self.refresh_lock = threading.RLock(), threading.Lock()
        self.stopped, self.wakeup, self.first_check = threading.Event(), threading.Event(), threading.Event()
        self.slots = threading.BoundedSemaphore(128)
        self.sockets = set()
        self.paths = {key: {'healthy': False, 'reason': 'Aguardando verificação HTTPS.', 'checkedAt': None, 'checkedMono': 0} for key in ('usb', 'wifi')}
        self.last_used = None
        self.selected, self.last_switch_at = None, None
        self.server = _Server(listen, _Handler, bind_and_activate=False)
        self.server.relay = self
        self.threads = []

    @property
    def address(self):
        return self.server.server_address

    def start(self):
        # Bind synchronously: port conflicts fail before the API advertises readiness.
        try:
            self.server.server_bind(); self.server.server_activate()
        except Exception:
            self.server.server_close()
            raise
        self.threads = [threading.Thread(target=lambda: self.server.serve_forever(poll_interval=.1), daemon=True), threading.Thread(target=self._monitor, daemon=True)]
        for thread in self.threads: thread.start()

    def stop(self):
        self.stopped.set(); self.wakeup.set()
        if self.threads: self.server.shutdown()
        self.server.server_close()
        with self.lock:
            sockets = list(self.sockets)
        for connection in sockets:
            try: connection.shutdown(socket.SHUT_RDWR)
            except OSError: pass
            connection.close()
        for thread in self.threads: thread.join(10)

    def _monitor(self):
        while not self.stopped.is_set():
            self.refresh()
            self.wakeup.wait(self.interval); self.wakeup.clear()

    def refresh(self):
        with self.refresh_lock:
            def check(key):
                started = time.monotonic()
                result = {'healthy': False, 'reason': 'MyProxy ou HTTPS indisponível.'}
                try:
                    result.update(self.probe(self.endpoints[key], self.targets['wifi'][1]), healthy=True, reason='MyProxy e HTTPS confirmados.')
                except Exception:
                    pass
                result.update(checkedAt=datetime.now(timezone.utc).isoformat(), checkedMono=started)
                return key, result
            with ThreadPoolExecutor(max_workers=2) as pool:
                observed = dict(pool.map(check, ('usb', 'wifi')))
            # This is an operational pin, not cryptographic device attestation.
            announced = observed['usb'].get('wifiIP')
            if observed['usb']['healthy'] and announced not in (None, '', '—', self.expected_wifi_ip):
                self.wifi_blocked = True
                if self.pin_state_path:
                    self.pin_state_path.write_text(json.dumps({'wifi': self.endpoints['wifi'], 'blocked': True}))
            if self.wifi_blocked:
                observed['wifi'].update(healthy=False, reason='USB informou outro endereço Wi-Fi; confira a configuração.')
            with self.lock:
                self.paths = observed
                self._selection()
            self.first_check.set()

    def _eligible(self):
        now = time.monotonic()
        return [key for key in ('usb', 'wifi') if not self.stopped.is_set() and not (key == 'wifi' and self.wifi_blocked) and self.paths[key]['healthy'] and now - self.paths[key]['checkedMono'] <= self.ttl]

    def snapshot(self):
        with self.lock:
            selected = self._selection()
            paths = copy.deepcopy(self.paths)
            for path in paths.values():
                age = max(0, time.monotonic() - path.pop('checkedMono'))
                path['ageSeconds'] = round(age, 1) if path['checkedAt'] else None
                fresh = age <= self.ttl
                if path['healthy'] and not fresh:
                    path.update(healthy=False, reason='Verificação expirada.')
            return {'enabled': True, 'selected': selected, 'lastUsed': self.last_used, 'lastSwitchAt': self.last_switch_at, 'paths': paths,
                    'reason': 'USB prioritário disponível.' if selected == 'usb' else 'Usando Wi-Fi; USB indisponível.' if selected == 'wifi' else 'Sem caminho MyProxy confirmado; tráfego bloqueado.',
                    'cellularEgress': 'not_guaranteed', 'deviceIdentity': 'operator_configured_endpoints'}

    def _selection(self):
        available = self._eligible()
        selected = available[0] if available else None
        if selected != self.selected:
            self.last_switch_at = datetime.now(timezone.utc).isoformat()
            self.selected = selected
        return selected

    @staticmethod
    def unavailable(client):
        try:
            client.settimeout(1)
            client.sendall(b'HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\nContent-Length: 0\r\n\r\n')
        except OSError: pass

    def handle(self, client):
        self.first_check.wait(9)
        with self.lock:
            eligible = self._eligible()
        upstream = None
        for key in eligible:
            with self.lock:
                if key not in self._eligible(): continue
            try:
                # The only remote sockets created here terminate at configured MyProxy.
                upstream = socket.create_connection(self.targets[key], timeout=2)
                upstream.settimeout(15)
                break
            except OSError:
                with self.lock:
                    self.paths[key].update(healthy=False, reason='Transporte interrompido; nova verificação solicitada.')
                self.wakeup.set()
        if upstream is None:
            self.unavailable(client)
            return
        # From this point, never try a second upstream or replay bytes.
        with self.lock:
            self.last_used = key
            self.sockets.update((client, upstream))
        try:
            client.settimeout(15)
            idle_since = time.monotonic()
            reading = {client, upstream}
            while reading and not self.stopped.is_set():
                readable, _, _ = select.select(tuple(reading), (), (), 1)
                if not readable:
                    idle_timeout = HALF_CLOSE_IDLE_TIMEOUT if len(reading) < 2 else 300
                    if time.monotonic() - idle_since > idle_timeout: break
                    continue
                for source in readable:
                    data = source.recv(65536)
                    destination = upstream if source is client else client
                    if not data:
                        reading.remove(source)
                        # Drain a legitimate response after FIN, but do not keep an
                        # abandoned half-closed stream occupying a slot for minutes.
                        idle_since = time.monotonic()
                        try: destination.shutdown(socket.SHUT_WR)
                        except OSError: pass
                        continue
                    destination.sendall(data)
                    idle_since = time.monotonic()
        except (OSError, ValueError):
            self.wakeup.set()
        finally:
            upstream.close()
            with self.lock:
                self.sockets.discard(client); self.sockets.discard(upstream)
