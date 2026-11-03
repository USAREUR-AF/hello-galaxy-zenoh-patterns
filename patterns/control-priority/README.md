# Control and abort priority

Set priority in the publishing application. Tenant commands use
`zenoh.Priority.INTERACTIVE_HIGH`; abort or stop messages use
`zenoh.Priority.REAL_TIME`. Ordinary data retains `zenoh.Priority.DATA`.
GOAT health currently publishes at `INTERACTIVE_HIGH`, so the default data band
places a command below that health traffic.

```python
control = session.declare_publisher(
    control_key, priority=zenoh.Priority.INTERACTIVE_HIGH)
abort = session.declare_publisher(
    abort_key, priority=zenoh.Priority.REAL_TIME)
control.put(command_payload)
abort.put(stop_payload)
```

These calls change priority only. Keep your application's reliability and
congestion-control policy. Priority is cooperative scheduling, not an access
permission, reserved capacity, or a latency guarantee. Do not promote a bulk
stream to the abort band. Receivers still need freshness checks and an
application-specific response to a missing command.

## Measure the three bands

The probe uses synthetic messages and two separate client sessions through an
existing router. It does not send control commands or create competing load.
Use `eclipse-zenoh==1.9.0`, matching this repository's transport example.

1. Prepare a Zenoh client config with the router endpoint and your mTLS file paths.
2. Choose a disposable exact key under your authorized producer anchor.
3. Arrange a repeatable competing load with the goatnet operator.
4. Record the topology, SDK/router versions, load configuration, and router metrics.
5. Run each cell three times under the same load.

```sh
python3 probe.py --config /path/to/client.json5 \
  --key YOUR_ANCHOR/hello/priority-probe --traffic data \
  --hz 12 --seconds 150 --cell baseline-data > baseline-data.json
python3 probe.py --config /path/to/client.json5 \
  --key YOUR_ANCHOR/hello/priority-probe --traffic control \
  --hz 12 --seconds 150 --cell tenant-control > tenant-control.json
python3 probe.py --config /path/to/client.json5 \
  --key YOUR_ANCHOR/hello/priority-probe --traffic abort \
  --hz 12 --seconds 150 --cell tenant-abort > tenant-abort.json
```

Run from this directory. Both sessions use the supplied config with multicast
discovery disabled. The config must point at the intended router, not a local
peer. Keep credentials out of captured output. Use separate files for repeats.
The single-process timestamps avoid cross-host clock skew; these are loopback
round trips through the router, not one-way latency measurements.

Each JSON result records planned/sent/received counts, loss, median and maximum
latency, maximum receive gap (including edge silence), and gaps over one second.
Reports also retain the configured gap threshold and drain duration.
A nonzero exit indicates malformed samples, lost messages, missed send slots,
or a gap above the configured limit (5.1 seconds by default); retain failed cells as evidence. No received messages is a failure.
A local control cannot establish live contention performance; only the measured
cells on the intended goatnet show whether control traffic meets its bound.

Offline checks:

```sh
python3 test_probe.py
```
