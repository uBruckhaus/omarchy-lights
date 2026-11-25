"""Regression tests for the Lights 1.0.0 review fixes and the Hue Lights folder migration."""
import importlib.util
import json
import os
import shutil
import stat
import tempfile
import threading
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, "..", "scripts", rel))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


prov = _load("lights_review_prov", "hue_providers.py")
hue = _load("lights_review_hue", "hue-lights.py")


class LanGuardTests(unittest.TestCase):
    def test_only_rfc1918_and_link_local(self):
        for ok in ("10.1.2.3", "172.16.0.9", "172.31.255.1", "192.168.178.20", "169.254.10.10"):
            self.assertTrue(prov._is_allowed_ipv4(ok), ok)
        for bad in ("198.18.0.1", "100.64.0.1", "192.0.0.8", "192.0.2.1", "0.1.2.3", "8.8.8.8",
                    "169.254.169.254", "172.32.0.1", "224.0.0.1", "255.255.255.255", "127.0.0.1", None, 42):
            self.assertFalse(prov._is_allowed_ipv4(bad), bad)
        self.assertTrue(prov._is_allowed_ipv4("127.0.0.1", allow_loopback=True))
        self.assertFalse(prov.valid_local_host("198.18.0.1"))

    def test_resolved_name_outside_lan_is_blocked(self):
        fake = [(2, 1, 6, "", ("198.18.0.1", 80))]
        with mock.patch.object(prov.socket, "getaddrinfo", return_value=fake):
            with self.assertRaises(prov.ProviderError):
                prov.resolve_local_ipv4("lamp.local", 80)


class ProvidersFileTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        os.chmod(self.dir, 0o700)
        self.path = os.path.join(self.dir, "providers.json")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def _write(self, data):
        with open(self.path, "w") as fh:
            fh.write(data)
        os.chmod(self.path, 0o600)

    def test_fifo_does_not_block_and_blocks_overwrite(self):
        os.mkfifo(self.path, 0o600)
        done = []
        t = threading.Thread(target=lambda: done.append(prov.ProviderManager(self.dir).load()), daemon=True)
        t.start()
        t.join(3)
        self.assertTrue(done, "load() blocked on a FIFO")
        mgr = prov.ProviderManager(self.dir)
        mgr.load()
        self.assertTrue(mgr._load_blocked)

    def test_wrong_container_types_do_not_raise(self):
        for payload in ('{"providers": null}', '{"providers": 5}', '{"providers": {"a": 1}}', '"text"', '7',
                        '{"providers": [null, 3, "x", [], {"kind": 5}]}', "[" * 5000 + "]" * 5000):
            self._write(payload)
            mgr = prov.ProviderManager(self.dir)
            mgr.load()  # must never raise
            self.assertEqual(mgr.connections, [])

    def test_oversized_file_is_refused(self):
        self._write('{"providers": []}' + " " * 300000)
        mgr = prov.ProviderManager(self.dir)
        mgr.load()
        self.assertTrue(mgr._load_blocked)


class BridgeIpTests(unittest.TestCase):
    def test_bridge_ip_only_home_lan(self):
        for ok in ("192.168.178.106", "10.0.0.2", "172.20.1.1", "169.254.3.4"):
            self.assertTrue(hue.valid_bridge_ip(ok), ok)
        for bad in ("198.18.0.1", "100.64.1.1", "192.0.0.9", "192.0.2.5", "0.0.0.1", "169.254.169.254"):
            self.assertFalse(hue.valid_bridge_ip(bad), bad)


class PendingCommandTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        os.chmod(self.dir, 0o700)
        self.mgr = prov.ProviderManager(self.dir)
        self.mgr.connections = [{"id": "c1", "kind": "wled", "host": "192.168.1.20", "port": 80,
                                 "name": "Strip", "room_name": "", "token": "", "use_https": False,
                                 "enabled": True, "cert_fingerprint": ""}]
        self.mgr.conn_generations = {"c1": 1}
        self.sent = []
        real_set_light = self.mgr.set_light

        def spy(rid, body, gen=None):
            with self.mgr.lock:
                conn = self.mgr._conn_for(self.mgr._rid_conn_id(rid), gen)
            if conn:
                self.sent.append((rid, body))
        self.mgr.set_light = spy
        self._real_set_light = real_set_light

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_commands_dropped_on_edit_toggle_remove_and_generation_change(self):
        for action in ("toggle", "remove", "bump"):
            self.mgr.conn_generations = {"c1": 1}
            self.mgr.queue_command("light", "wled:c1:0", {"on": {"on": True}})
            with self.mgr.lock:
                if action == "toggle":
                    self.mgr.conn_generations["c1"] += 1
                    self.mgr._drop_pending_for("c1")
                elif action == "remove":
                    self.mgr._drop_pending_for("c1")
                else:
                    self.mgr.conn_generations["c1"] += 1  # edited between queue and drain
            while self.mgr._drain_pending():
                pass
            self.assertEqual(self.sent, [], action)

    def test_current_generation_is_sent(self):
        self.mgr.queue_command("light", "wled:c1:0", {"on": {"on": True}})
        self.mgr.queue_command("light", "wled:c1:0", {"dimming": {"brightness": 50}})
        self.assertTrue(self.mgr._drain_pending())
        self.assertEqual(self.sent, [("wled:c1:0", {"on": {"on": True}, "dimming": {"brightness": 50}})])

    def test_edit_after_dequeue_is_dropped_inside_set_light(self):
        self.mgr.queue_command("light", "wled:c1:0", {"on": {"on": True}})
        sent_http = []
        with self.mgr.lock:
            key, (gen, body) = next(iter(self.mgr._pending_cmds.items()))
            del self.mgr._pending_cmds[key]
            self.mgr.conn_generations["c1"] += 1  # host edited after the command left the queue
        with mock.patch.object(prov, "_http_request", side_effect=lambda *a, **k: sent_http.append(a) or (200, b"{}")):
            self._real_set_light("wled:c1:0", body, gen=gen)
        self.assertEqual(sent_http, [])

    def test_remove_connection_drops_queue(self):
        self.mgr.queue_command("light", "wled:c1:0", {"on": {"on": False}})
        self.mgr.remove_connection("c1")
        self.assertFalse(self.mgr._drain_pending())
        self.assertEqual(self.sent, [])


class HomeAssistantPinTests(unittest.TestCase):
    def test_area_request_uses_fingerprint_captured_by_first_request(self):
        mgr = prov.ProviderManager(tempfile.mkdtemp())
        conn = {"id": "h1", "kind": "home_assistant", "host": "192.168.1.5", "port": 8123, "token": "t0k",
                "use_https": True, "cert_fingerprint": "", "name": "HA", "room_name": "", "enabled": True}
        calls = []

        def fake_http(host, port, method, path, **kw):
            calls.append((path, kw.get("expected_fp")))
            if path == "/api/states":
                if isinstance(kw.get("capture_fp"), list):
                    kw["capture_fp"][:] = ["a" * 64]
                return 200, b"[]"
            return 200, b"[]"

        with mock.patch.object(prov, "_http_request", side_effect=fake_http):
            mgr.fetch_single(conn, gen=None)
        self.assertEqual(calls[0], ("/api/states", ""))
        self.assertEqual(calls[1], ("/api/template", "a" * 64))


class LegacyMigrationTests(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.old = os.path.join(self.home, "omarchy", "hue-lights")
        self.new = os.path.join(self.home, "omarchy", "lights")
        self.saved = (hue.CONFIG_DIR, hue.CONFIG_PATH, hue.DEFAULT_CONFIG_DIR, hue.LEGACY_CONFIG_DIR)
        hue.CONFIG_DIR = hue.DEFAULT_CONFIG_DIR = self.new
        hue.CONFIG_PATH = os.path.join(self.new, "config.json")
        hue.LEGACY_CONFIG_DIR = self.old

    def tearDown(self):
        hue.CONFIG_DIR, hue.CONFIG_PATH, hue.DEFAULT_CONFIG_DIR, hue.LEGACY_CONFIG_DIR = self.saved
        shutil.rmtree(self.home, ignore_errors=True)

    def _old_file(self, name, data, mode=0o600):
        os.makedirs(self.old, mode=0o700, exist_ok=True)
        p = os.path.join(self.old, name)
        with open(p, "w") as fh:
            fh.write(data if isinstance(data, str) else json.dumps(data))
        os.chmod(p, mode)
        return p

    GOOD = {"ip": "192.168.178.106", "app_key": "abcDEF123_-", "fingerprint": "b" * 64,
            "bridge_id": "c42996fffec9b46d".upper(), "name": "Hue Bridge"}

    def test_copies_valid_pairing_and_leaves_old_untouched(self):
        p = self._old_file("config.json", self.GOOD)
        before = open(p).read()
        self.assertTrue(hue.migrate_legacy_config())
        self.assertEqual(hue.load_config()["bridge_id"].lower(), "c42996fffec9b46d")
        self.assertEqual(stat.S_IMODE(os.stat(os.path.join(self.new, "config.json")).st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(self.new).st_mode), 0o700)
        self.assertEqual(open(p).read(), before)
        self.assertFalse(hue.migrate_legacy_config())  # one time only

    def test_other_plugins_format_is_ignored(self):
        self._old_file("config.json", {"bridge_ip": "192.168.1.2", "username": "x"})
        self._old_file("local_schedules.json", {"mode": "local", "schedules": []})
        self.assertFalse(hue.migrate_legacy_config())
        self.assertEqual(hue.load_config(), {})
        self.assertFalse(os.path.lexists(self.new))  # no valid pairing: nothing imported, later import still possible

    def test_symlinked_files_and_dir_are_not_followed(self):
        secret = os.path.join(self.home, "elsewhere.json")
        with open(secret, "w") as fh:
            json.dump(self.GOOD, fh)
        os.makedirs(self.old, mode=0o700)
        os.symlink(secret, os.path.join(self.old, "config.json"))
        hue.migrate_legacy_config()
        self.assertEqual(hue.load_config(), {})
        shutil.rmtree(self.new, ignore_errors=True)
        shutil.rmtree(self.old)
        real = os.path.join(self.home, "real")
        os.makedirs(real, mode=0o700)
        with open(os.path.join(real, "config.json"), "w") as fh:
            json.dump(self.GOOD, fh)
        os.symlink(real, self.old)
        self.assertFalse(hue.migrate_legacy_config())
        self.assertFalse(os.path.lexists(self.new))

    def test_fifo_in_old_folder_does_not_block(self):
        os.makedirs(self.old, mode=0o700)
        os.mkfifo(os.path.join(self.old, "config.json"), 0o600)
        done = []
        t = threading.Thread(target=lambda: done.append(hue.migrate_legacy_config()), daemon=True)
        t.start()
        t.join(3)
        self.assertTrue(done)

    def test_skipped_when_new_folder_exists_or_dir_overridden(self):
        self._old_file("config.json", self.GOOD)
        os.makedirs(self.new, mode=0o700)
        self.assertFalse(hue.migrate_legacy_config())
        self.assertEqual(hue.load_config(), {})
        shutil.rmtree(self.new)
        hue.CONFIG_DIR = os.path.join(self.home, "custom")
        try:
            self.assertFalse(hue.migrate_legacy_config())
        finally:
            hue.CONFIG_DIR = self.new


if __name__ == "__main__":
    unittest.main()
