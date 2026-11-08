# Diagnostic CTS builds rejected before packaging

Both original and patched AUX sources compiled against matching32.1 UART ABI and imported CRCs, with BTF/debug. These are external-module diagnostics, unsigned and uninstalled. They omit normal intree metadata and would add out-of-tree taint. Complete extracted-header audit also found eight case-collapsed paths on the Mac filesystem. No archive was produced and those extracted headers must not be repackaged.

Read plans/omarchy-pi-cts-incremental-candidate.md for actual scope, retained failures and storage accounting. Diagnostic evidence is conservatively charged250MB; global charge now1,344,543,872bytes before further work. A new independent lane investigates genuine in-tree Kbuild/MODPOST on case-sensitive Linux storage, with4GB ceiling inside the overall15GB limit, not an unrestricted full-kernel build. No physical radio or deployment qualification follows.
