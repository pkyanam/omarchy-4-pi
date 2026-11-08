# Powered CTS observation with the scoped UART trace

Parent ran one guarded 12-second UART capture and the finite read-only GPIO observer together. The observer armed before capture, completed all 17 scheduled snapshots plus armed/finished records, and both processes exited 0. All reads stayed within the 50 ms budget. Exact shared tracing state/binding were restored, taint 0, no probe misses, per-CPU drops/overruns or truncation. Helpers are tracked; no pin configuration or UART register was changed/read directly.

The same-window samples show BT_ON output readback high with GPIO30 CTS high at 0.4/0.5 seconds. The UART stop entry at approximately 0.51 seconds records hw_stopped=1. By 0.65 seconds GPIO30 reads low while BT_ON remains high, including later samples through 11 seconds. No selected CTS-change or TX-loop callback occurred. The four UART counter samples are during initialization, not final post-command counters. Unknown/unrequested BT_ON at 0.2/0.25 seconds is retained as null, not low.

This supports the source-rooted missing-modem-interrupt recovery explanation: software gates TX while CTS is not ready, then does not observe a later ready level. GPIO controller readback is supportive logical signal evidence, not a continuous electrical trace, measured voltage or proof of transmitted/received HCI bytes. Sequential read intervals and all raw sample values are retained in observations.json; task/boot identifiers and unrelated GPIO labels are omitted.

Current firmware DT was copied/hashed privately. Live shutdown-gpios resolves to offset 0, active-high, on raspberrypi,firmware-gpio with BT_ON as line 0; AUX uart-has-rtscts is absent and skip-init present. All four pads are ALT5 owned by AUX. Existing upstream AUX hardware RTS/CTS implementation is now the preferred inactive backport candidate, paired with reviewed DT opt-in. No kernel/firmware package change or working-radio claim yet.

Earlier isolated after-failure pin snapshots did not independently establish power-down; that wording in historical notes was not measured. This combined powered window supersedes that ambiguity without reclassifying older samples. Full private FDT,GPIO text, identities and controller commands remain ignored under bt-cts-candidate/parent-window-1/.

parent-controller.py preserves the exact bounded parent orchestration used for this capture, with its original fixed paths; existing output refuses before any trace. Review/adapt only fresh paths for reproduction. The observer and tracer remain separate, each with its recorded source and format gates.
