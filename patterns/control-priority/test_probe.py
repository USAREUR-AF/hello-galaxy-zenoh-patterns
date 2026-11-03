#!/usr/bin/env python3
"""Offline stdlib runner; also verifies the actual pinned SDK's priority enums."""

import contextlib
import io
import json
import pathlib
import queue
import socket
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import Mock, patch

import probe
import zenoh


class ProbeTests(unittest.TestCase):
    def test_sdk_delivers_each_priority_over_local_transport(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        receiver = zenoh.Config()
        receiver.insert_json5("listen/endpoints", f'["tcp/127.0.0.1:{port}"]')
        receiver.insert_json5("scouting/multicast/enabled", "false")
        sender = zenoh.Config()
        sender.insert_json5("mode", '"client"')
        sender.insert_json5("connect/endpoints", f'["tcp/127.0.0.1:{port}"]')
        sender.insert_json5("scouting/multicast/enabled", "false")
        got = queue.Queue()
        with zenoh.open(receiver) as rx, zenoh.open(sender) as tx:
            with rx.declare_subscriber("example/priority", got.put):
                time.sleep(0.5)
                for traffic in ["data", "control", "abort"]:
                    with probe.publisher(tx, zenoh, "example/priority", traffic) as pub:
                        pub.put(traffic)
                        sample = got.get(timeout=3)
                        self.assertEqual(sample.payload.to_string(), traffic)
                        self.assertEqual(
                            sample.priority, probe.priority_for(zenoh, traffic)
                        )

    def test_cli_runs_through_two_clients(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        router = zenoh.Config()
        router.insert_json5("listen/endpoints", json.dumps([f"tcp/127.0.0.1:{port}"]))
        router.insert_json5("scouting/multicast/enabled", "false")
        with tempfile.TemporaryDirectory() as tmp, zenoh.open(router):
            path = pathlib.Path(tmp) / "client.json"
            path.write_text(
                json.dumps({"connect": {"endpoints": [f"tcp/127.0.0.1:{port}"]}})
            )
            for traffic in ["data", "control", "abort"]:
                run = subprocess.run(
                    [
                        sys.executable,
                        str(pathlib.Path(probe.__file__)),
                        "--config",
                        str(path),
                        "--key",
                        "example/cli-probe",
                        "--traffic",
                        traffic,
                        "--seconds",
                        "1",
                        "--drain-seconds",
                        "0.1",
                        "--cell",
                        "local-fixture",
                    ],
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                self.assertEqual(run.returncode, 0, run.stderr + run.stdout)
                report = json.loads(run.stdout)
                self.assertEqual(report["received"], 12)
                self.assertEqual(report["lost"], 0)
                self.assertEqual(report["missed_send_slots"], 0)
                self.assertTrue(report["passed"])

    def test_cli_refuses_delayed_publish_and_invalid_callback(self):
        self._assert_cli_failure(True, None)
        for malformed in ["null", "[]", "bad-json", "seq", "sent_ns", "future"]:
            with self.subTest(malformed=malformed):
                self._assert_cli_failure(False, malformed)
        self._assert_cli_failure(False, "different-run")

    def _assert_cli_failure(self, delayed, invalid):
        clock = [0.0]
        callback = [None]
        sent_at = []

        class Resource:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

            def put(self, payload):
                sent_at.append(clock[0])
                if delayed and len(sent_at) == 1:
                    clock[0] += 0.8
                if invalid:
                    msg = json.loads(payload)
                    if invalid in ("null", "[]", "bad-json"):
                        raw = invalid.encode()
                    else:
                        if invalid in ("seq", "sent_ns"):
                            msg[invalid] = "not-an-integer"
                        elif invalid == "future":
                            msg["sent_ns"] += 1_000_000_000
                        else:
                            msg["run"] = "another-run"
                        raw = json.dumps(msg).encode()
                    callback[0](
                        types.SimpleNamespace(
                            payload=types.SimpleNamespace(to_bytes=lambda: raw)
                        )
                    )
                callback[0](
                    types.SimpleNamespace(
                        payload=types.SimpleNamespace(to_bytes=lambda: payload.encode())
                    )
                )

            def declare_subscriber(self, key, receiver):
                callback[0] = receiver
                return Resource()

            def declare_publisher(self, *args, **kwargs):
                return Resource()

        cfg = Mock()
        cfg.get_json.return_value = '["tcp/127.0.0.1:1"]'
        fake = types.SimpleNamespace(
            Config=types.SimpleNamespace(from_file=lambda _: cfg),
            Priority=zenoh.Priority,
            open=lambda _: Resource(),
        )
        output = io.StringIO()
        with (
            patch.dict(sys.modules, {"zenoh": fake}),
            patch.object(
                sys,
                "argv",
                [
                    "probe",
                    "--config",
                    "fixture",
                    "--key",
                    "example/test",
                    "--cell",
                    "fixture",
                    "--hz",
                    "4",
                    "--seconds",
                    "1",
                    "--drain-seconds",
                    "0.1",
                ],
            ),
            patch.object(
                probe.time,
                "sleep",
                side_effect=lambda n: clock.__setitem__(0, clock[0] + n),
            ),
            patch.object(probe.time, "monotonic", side_effect=lambda: clock[0]),
            patch.object(
                probe.time, "monotonic_ns", side_effect=lambda: int(clock[0] * 1e9)
            ),
            contextlib.redirect_stdout(output),
        ):
            code = probe.main()
        report = json.loads(output.getvalue())
        if invalid == "different-run":
            self.assertEqual(code, 0)
            self.assertTrue(report["passed"])
            self.assertEqual(report["invalid_samples"], 0)
            return
        self.assertEqual(code, 1)
        self.assertFalse(report["passed"])
        if delayed:
            self.assertGreater(report["missed_send_slots"], 0)
            self.assertEqual(len(sent_at), 2)
        else:
            self.assertEqual(report["lost"], 0)
            self.assertGreater(report["invalid_samples"], 0)

    def test_publishers_use_selected_sdk_priority(self):
        for traffic, priority in [
            ("data", zenoh.Priority.DATA),
            ("control", zenoh.Priority.INTERACTIVE_HIGH),
            ("abort", zenoh.Priority.REAL_TIME),
        ]:
            session = Mock()
            probe.publisher(session, zenoh, "example/disposable", traffic)
            session.declare_publisher.assert_called_once_with(
                "example/disposable", priority=priority
            )

    def test_empty_delivery_cannot_look_healthy(self):
        result = probe.summarize(1800, [], 0, 150_000_000_000)
        self.assertEqual(result["lost"], 1800)
        self.assertIsNone(result["median_latency_ms"])
        self.assertEqual(result["max_gap_s"], 150)

    def test_loss_duplicates_and_trailing_silence(self):
        rows = [
            (0, 0, 10_000_000),
            (0, 0, 20_000_000),
            (2, 2_000_000_000, 2_020_000_000),
        ]
        result = probe.summarize(3, rows, 0, 5_000_000_000)
        self.assertEqual(result["received"], 2)
        self.assertEqual(result["lost"], 1)
        self.assertEqual(result["median_latency_ms"], 15)
        self.assertAlmostEqual(result["max_gap_s"], 2.98)
        self.assertEqual(result["gaps_over_1s"], 2)

    def test_normal_delivery(self):
        result = probe.summarize(
            2, [(0, 0, 5_000_000), (1, 80_000_000, 85_000_000)], 0, 100_000_000
        )
        self.assertEqual(result["lost"], 0)
        self.assertEqual(result["median_latency_ms"], 5)
        self.assertLess(result["max_gap_s"], 1)


if __name__ == "__main__":
    unittest.main()
