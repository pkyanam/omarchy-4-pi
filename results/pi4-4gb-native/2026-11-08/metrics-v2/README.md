# Versioned state observations

The first two samples record differing package/session states and are not a causal before/after pair. Sample 3b290cf2 records installed runtime/settings 2.6 in the locked headless session with benchmarks disabled. The shell has not yet been restarted for graphical acceptance of 2.6, which is recorded explicitly in candidate metadata. Firmware throttle/actual-clock and runtime mitigation unknowns remain unknown under the measurement contract.

These are state observations on one 4GB Pi 4, separate from all six legacy rows. Do not graph their differences as optimization gains or join 8GB/Pi 5 data to this cohort. Source, labels, conditions, transport and schema provenance are persisted in each JSON. A first controller output-redirection attempt failed locally before recorder/SSH execution and persisted no sample; the subsequent framed authorized transport produced the validated 3b290cf2 record.
