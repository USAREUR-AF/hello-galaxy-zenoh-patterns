#!/usr/bin/env python3
"""Prove one transport works: a self-contained mTLS pub->sub round-trip.

Used by this pattern's run.sh, once per transport (TLS, then QUIC). It uses YOUR
operator context cert (the same identity `goat pub/sub` uses) and publishes +
subscribes under YOUR anchor, so a PASS means real end-to-end delivery through
the router + ACL over that transport.

Transport is chosen entirely by the endpoint scheme in $EP (tls/…:7447 vs
quic/…:7448) — nothing else differs. Name verification is turned off only when
the endpoint is a bare IP (the operator profile's router_endpoint is often the
router's mesh IP, which can't match a cert DNS SAN); against a DNS endpoint it
stays on.

Env:
  GOAT_CTX   path to the goat context dir (mtls.cert.pem / mtls.key.pem / ca-roots.pem)
  ANCHOR     your producer anchor (key prefix you may write+read)
  EP         the endpoint to dial, e.g. quic/router.example.lan:7448

Deps: pip install eclipse-zenoh==1.9.0   (the fleet-pinned version)
"""

import ipaddress
import json
import os
import sys
import time

import zenoh


def main() -> int:
    ctx = os.environ["GOAT_CTX"]
    anchor = os.environ["ANCHOR"]
    ep = os.environ["EP"]
    scheme = ep.split("/", 1)[0]
    host = ep.split("/", 1)[1].rsplit(":", 1)[0]
    try:
        ipaddress.ip_address(host)
        verify_name = False  # bare IP can't match a cert DNS SAN
    except ValueError:
        verify_name = True

    conf = zenoh.Config()
    conf.insert_json5("mode", json.dumps("client"))
    conf.insert_json5("connect/endpoints", json.dumps([ep]))
    # Insert the mTLS block whole — the same block serves TLS and QUIC (QUIC
    # reuses the TLS 1.3 handshake). Per-sub-key inserts do NOT enable the
    # client-cert send path on eclipse-zenoh-python 1.x.
    conf.insert_json5("transport/link/tls", json.dumps({
        "root_ca_certificate": os.path.join(ctx, "ca-roots.pem"),
        "connect_certificate": os.path.join(ctx, "mtls.cert.pem"),
        "connect_private_key": os.path.join(ctx, "mtls.key.pem"),
        "enable_mtls": True,
        "verify_name_on_connect": verify_name,
    }))

    t0 = time.time()
    session = zenoh.open(conf)
    open_ms = int((time.time() - t0) * 1000)

    got = []
    key = f"{anchor}/hello/transport-demo"
    session.declare_subscriber(key + "/**", lambda smp: got.append(smp.payload.to_bytes()))
    time.sleep(1.0)  # let the subscription reach the router
    msg = f"{scheme}-check-{int(time.time())}".encode()
    session.declare_publisher(key + f"/{scheme}").put(msg)
    time.sleep(2.0)
    session.close()

    ok = any(msg in p for p in got)
    verdict = "PASS (round-trip received)" if ok else "FAIL (no delivery)"
    print(f"{scheme.upper():4} via {ep}: connect={open_ms} ms  {verdict}", flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
