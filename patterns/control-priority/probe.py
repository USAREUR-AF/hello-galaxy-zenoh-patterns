#!/usr/bin/env python3
"""Measure one explicit priority through two sessions on an existing router.

Credentials remain in the supplied Zenoh config. Use a disposable key under
an authorized anchor; the payload is synthetic sequence/timing data, never a
real command. This probe creates no competing load and changes no router config.
"""

import argparse
import importlib.metadata
import json
import math
import statistics
import threading
import time
import uuid


def priority_for(zenoh, traffic):
    return {
        "data": zenoh.Priority.DATA,
        "control": zenoh.Priority.INTERACTIVE_HIGH,
        "abort": zenoh.Priority.REAL_TIME,
    }[traffic]


def publisher(session, zenoh, key, traffic):
    # Only priority differs between cells. Keep the SDK's default reliability
    # and congestion control, as in the existing tenant examples.
    return session.declare_publisher(key, priority=priority_for(zenoh, traffic))


def summarize(sent, received, started, ended):
    # received is [(sequence, send_monotonic_ns, receive_monotonic_ns)]. Both
    # sessions run in this process, so clocks cannot skew the latency result.
    unique = {}
    for seq, tx, rx in received:
        if 0 <= seq < sent and seq not in unique:
            unique[seq] = (tx, rx)
    arrivals = sorted(rx for _, rx in unique.values())
    latencies = [(rx - tx) / 1e6 for tx, rx in unique.values()]
    gaps = [
        (b - a) / 1e9
        for a, b in zip([started] + arrivals, arrivals + [ended], strict=True)
    ]
    return {
        "sent": sent,
        "received": len(unique),
        "lost": sent - len(unique),
        "median_latency_ms": statistics.median(latencies) if latencies else None,
        "max_latency_ms": max(latencies) if latencies else None,
        "max_gap_s": max(gaps),
        "gaps_over_1s": sum(g > 1 for g in gaps),
    }


def positive(value):
    n = float(value)
    if not math.isfinite(n) or n <= 0:
        raise argparse.ArgumentTypeError("must be a finite positive number")
    return n


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--config",
        required=True,
        help="Zenoh client config with router endpoint and mTLS file paths",
    )
    ap.add_argument(
        "--key", required=True, help="disposable exact topic under your writable anchor"
    )
    ap.add_argument(
        "--traffic", choices=("data", "control", "abort"), default="control"
    )
    ap.add_argument("--hz", type=positive, default=12)
    ap.add_argument("--seconds", type=positive, default=150)
    ap.add_argument("--drain-seconds", type=positive, default=10)
    ap.add_argument("--max-gap-seconds", type=positive, default=5.1)
    ap.add_argument(
        "--cell",
        required=True,
        help="operator label for the topology and competing-load configuration",
    )
    args = ap.parse_args()
    if any(c in args.key for c in "*?#$") or not args.key.strip("/"):
        ap.error("--key must be an exact disposable topic")
    import zenoh

    nonce = uuid.uuid4().hex
    received = []
    invalid_samples = []
    lock = threading.Lock()

    def receive(sample):
        try:
            msg = json.loads(sample.payload.to_bytes())
            if not isinstance(msg, dict):
                raise ValueError("not an object")
            if msg.get("run") != nonce:
                return
            now = time.monotonic_ns()
            if type(msg["seq"]) is not int or msg["seq"] < 0:
                raise ValueError("invalid sequence")
            if type(msg["sent_ns"]) is not int or not 0 <= msg["sent_ns"] <= now:
                raise ValueError("invalid timestamp")
        except (ValueError, KeyError, TypeError):
            with lock:
                invalid_samples.append(1)
            return
        with lock:
            received.append((msg["seq"], msg["sent_ns"], now))

    # Distinct client sessions avoid the publishing session's local subscriber
    # fast path. Multicast discovery is off; both must traverse the given router.
    def config():
        cfg = zenoh.Config.from_file(args.config)
        if not json.loads(cfg.get_json("connect/endpoints")):
            raise ValueError("config requires an explicit router endpoint")
        cfg.insert_json5("mode", '"client"')
        cfg.insert_json5("scouting/multicast/enabled", "false")
        return cfg

    with zenoh.open(config()) as rx, zenoh.open(config()) as tx:
        with (
            rx.declare_subscriber(args.key, receive),
            publisher(tx, zenoh, args.key, args.traffic) as pub,
        ):
            time.sleep(2)
            start = time.monotonic_ns()
            planned = math.ceil(args.hz * args.seconds)
            sent = 0
            slot = 0
            while slot < planned:
                due = start / 1e9 + slot / args.hz
                time.sleep(max(0, due - time.monotonic()))
                elapsed = (time.monotonic_ns() - start) / 1e9
                if elapsed >= args.seconds:
                    break
                # Skip overdue slots instead of generating a catch-up burst.
                slot = max(slot, int(elapsed * args.hz))
                pub.put(
                    json.dumps(
                        {"run": nonce, "seq": sent, "sent_ns": time.monotonic_ns()}
                    )
                )
                sent += 1
                slot += 1
            # Include the whole requested window and allow delayed samples to
            # arrive. The drain is excluded from the silence-gap observation.
            end = start + int(args.seconds * 1e9)
            time.sleep(max(0, end / 1e9 - time.monotonic()) + args.drain_seconds)
            with lock:
                rows = list(received)
    # Latency/loss include drained samples; gaps measure the requested window.
    report = summarize(
        sent, rows, start, max(end, max((r[2] for r in rows), default=end))
    )
    report.update(
        cell=args.cell,
        traffic=args.traffic,
        priority=str(priority_for(zenoh, args.traffic)),
        planned=planned,
        missed_send_slots=planned - sent,
        invalid_samples=len(invalid_samples),
        requested_hz=args.hz,
        seconds=args.seconds,
        drain_seconds=args.drain_seconds,
        max_gap_seconds=args.max_gap_seconds,
        run=nonce,
        sdk=importlib.metadata.version("eclipse-zenoh"),
    )
    passed = (
        sent == planned
        and sent > 0
        and not invalid_samples
        and report["lost"] == 0
        and report["max_gap_s"] <= args.max_gap_seconds
    )
    report["passed"] = passed
    print(json.dumps(report, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
