# MMAL invalid VideoCore-handle error path

Inactive follow-up, outside the five-patch series. The parent prepared this independent of the ongoing VCHIQ service-close work; no shared candidate source or package recipe was changed. Do not install the H.264 port: full lifecycle remains NONDEPLOYABLE.

After a successful dma-buf import, a zero VideoCore handle previously released vcsm_handle but returned stale success and kept the released handle. Later normal cleanup could release it again. This patch propagates a free failure while retaining that ownership; after successful free it clears vcsm_handle and returns -EIO. The valid-handle path is unchanged.

The focused harness extracts the actual production submit and cleanup function bodies. Boundary stubs inject VCSM import/handle/free outcomes and count calls; they do not implement the MMAL decision under test. ASan/UBSan with fatal recovery checks invalid handle then cleanup, free failure with retained ownership followed by cleanup, import failure and valid submission. Prior source fails the -EIO assertion; the candidate passes. This checks the narrow error path, not kernel execution, real dma-buf references or complete cleanup/generation safety. Existing cleanup's handling of unrelated free errors and broader caller/port lifetimes remain outside this patch.

The patch passes a zero-fuzz dry run against the tracked five-patch replay. All-module compile/modpost after integrating the subsequent service-close unit remains pending; no module-build pass for this follow-up is claimed. Apply it only after reviewing the independent series integration, then use the normal bounded compiler harness.

```bash
python3 tools/pi-experiments/h264-port/mmal-invalid-handle/check.py /absolute/path/to/patched/mmal-vchiq.c --output /absolute/path/new-test-output
```

The test generates and compiles only in the explicit new output directory. Source hashes and raw pass/red logs are retained in results/pi4-4gb-native/2026-11-08/h264-source-port/. No Pi access or performance claim.
