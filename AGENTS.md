# AGENTS.md

Instructions for AI coding agents, and a short version for anyone working here. [CONTRIBUTING.md](CONTRIBUTING.md) is the full process.

## What this repository is

hello-galaxy-zenoh-patterns shows how to shape Zenoh keys, choose storage, and decide whether one topic is the right answer, on a running goat fabric. Each pattern is a runbook and one script that drives the `goat` CLI.

It is one of the Hello Galaxy demonstrations: small, runnable examples, each showing one part of [goat](https://github.com/USAREUR-AF/goatcore). It holds no goat source code.

## Layout

| Path | What |
|---|---|
| `patterns/` | one directory per pattern: `README.md` and `run.sh` |
| `patterns/control-priority/test_probe.py` | a probe that runs on local loopback, with no fabric |
| `bin/hello-zenoh` | the runner: `list`, one pattern, or `all` |
| `lib/hello-zenoh.sh` | shared shell functions |
| `docs/` | background |

## Before you push

CI (`.github/workflows/ci.yml`) runs these:

```bash
shellcheck -x -S warning lib/hello-zenoh.sh bin/hello-zenoh patterns/*/run.sh
python -m pip install eclipse-zenoh==1.9.0
(cd patterns/control-priority && python test_probe.py)
```

CI does not run the narrated patterns, because they need a fabric. To run them, use a goatnet that your `goat` CLI has a context for: `bin/hello-zenoh all`.

## Rules

1. **Nothing from a real deployment.** No hostname, domain, address, key or person of a real goatnet goes into a file or a commit message. Use made-up names, documentation addresses (RFC 5737) and `example.org` mail.
2. **Commits.** Conventional Commits subject of 100 characters or fewer, with a scope (`fix(<component>): …`). Every commit is signed off (`git commit -s`, the DCO) and signed with a key GitHub verifies. The organization's required check `verified-commits` refuses a pull request that holds an unverified commit.
3. **One logical change per pull request.**
4. **Vulnerabilities** go through [SECURITY.md](SECURITY.md), never a public issue.

The contribution guide for goat as a whole is [goatcore CONTRIBUTING.md](https://github.com/USAREUR-AF/goatcore/blob/main/CONTRIBUTING.md).
