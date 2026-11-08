# Local validation, 2026-11-08

Implementation status: **locally tested**. No target measurements have been collected with v2. Nothing in this directory establishes installed, rebooted, physically verified, performance-improved or release-qualified status.

Environment: macOS controller, Python 3.15.0, Homebrew OpenSSL 3.5.9. The first integration run exposed the system LibreSSL incompatibility; the integration test now explicitly selects installed OpenSSL 3 on this Mac. The production target uses its system OpenSSL and reports unsupported/failed invocations as null/error.

Final focused command:

```bash
python3 -m unittest discover -s tools/pi-metrics/tests -v >/tmp/pi-metrics-tests.log 2>&1
cat /tmp/pi-metrics-tests.log
```

Result: **12 tests passed**. The complete local log is `/tmp/pi-metrics-tests.log`. Both SHA-256 and AES-256-CBC parser integration cases ran against actual OpenSSL 3 with one-second, 8192-byte elapsed-time workloads. These rates were used only to validate the protocol and are not Pi samples. The controller persistence test mocks subprocess transport and exercises the real validation/file-writing path; it does not invoke SSH. The stdin/quoting test launches a local Python process. The unavailable-host collection test substitutes platform/euid checks and exercises actual absent-file behavior on the Mac; it does not establish Linux root execution.

Regression coverage includes endian and RAM decoding, missing/permission/invalid values, malformed and historical throttle values, decimal byte-rate conversion, non-finite rates, matching-release config selection and live config precedence, root rejection, transport option and argument injection rejection, metadata persistence, private file permissions, rejection without persistence on transport failure/extra output, and schema errors. Each tests a parsing, transport or persistence failure mode in the legacy implementation; the six-row count check is solely preservation of the explicitly requested fixed evidence set.

Additional checks: CLI help succeeds; `git diff --check` succeeds. The preserved legacy file's SHA-256 matches the original (`5ee8e0fa6bac40c9cf23842bdb8a99f829f7c1898ad8487c98df212eb0178322`). No Apple build or toolchain was needed.

Coordinator acceptance still required: independently verify host key; verify existing authorized sudo policy and effective-root execution; validate Python/OpenSSL/vcgencmd availability on the actual Pi; inspect board/RAM/cohort agreement and matching config provenance; compare firmware throttle reads with independent known-good telemetry; establish repeatable conditions and collect matched repeated trials. Missing instrumentation, config or permission remains unknown. No SSH, Pi access, service changes, module insertion, old build-script edits, plan-ledger edits, pushes, PRs or external messages were used for this work.
