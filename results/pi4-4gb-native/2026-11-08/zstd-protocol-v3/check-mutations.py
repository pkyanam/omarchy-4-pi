from pathlib import Path
import sys, types, unittest
source=Path('tools/pi-experiments/zstd-package-benchmark.py').read_text()
mutations={
 'wrong-corpus': ("unit = workload(self.args.corpus, self.args.level)", "unit = workload('source.tar', self.args.level)"),
 'wrong-level': ("unit = workload(self.args.corpus, self.args.level)", "unit = workload(self.args.corpus, 9)"),
 'whole-matrix': ("levels = (unit['level'],)", "levels = LEVELS"),
 'both-corpora': ("corpora = [self.bundle / 'corpus' / unit['corpus']]", "corpora = sorted((self.bundle/'corpus').iterdir())"),
 'level9-calibration': ("calibrations = calibration_jobs(corpora, levels)", "calibrations = calibration_jobs(corpora, (9,))"),
 'unbalanced': ("return [(a, b), (b, a)] * 3", "return [(a,b)] * 4 + [(b,a)] * 2"),
 'old-projection': ("return max(costs) * len(schedule) * 1.15", "return max(costs) * 72 * 1.15"),
 'reuse-calibration': ("return max(costs) * len(schedule) * 1.15", "return max(costs) * (len(schedule)-len(costs)) * 1.15"),
 'no-headroom': ("return max(costs) * len(schedule) * 1.15", "return max(costs) * len(schedule)"),
 'stock-timing': ("raw = self.z(name, ['--single-thread'", "raw = self.z('stock', ['--single-thread'"),
 'accept-session-mismatch': ("require(context['locked'] == expected_lock and context['outputs'] and context['policies'],", "require(True,"),
}
for name,(old,new) in mutations.items():
 assert source.count(old)==1, name
 module=types.ModuleType('mutant');sys.modules['mutant']=module
 exec(compile(source.replace(old,new),str(Path('tools/pi-experiments/zstd-package-benchmark.py').resolve()),'exec'),module.__dict__)
 print('\nMUTANT', name, flush=True)
 suite=unittest.defaultTestLoader.loadTestsFromTestCase(module.Tests)
 result=unittest.TextTestRunner(stream=sys.stdout,verbosity=2).run(suite)
 assert not result.wasSuccessful(), f'survived: {name}'
 print('REJECTED', name, flush=True)
