"""Run as root ONLY in the private bounded container. Real helper/filesystem I/O.
findmnt facts are mocked: this is not FAT or crash/power-loss qualification.
"""
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import sys
import unittest
from unittest.mock import patch

SOURCE = Path(sys.argv.pop(1))
PAYLOAD = Path('/usr/share/omarchy/pi4-cts')
CONF = Path('/etc/omarchy/pi4-cts-media.json')
STATE = Path('/var/lib/omarchy/pi4-cts')
MEDIA = Path('/tmp/cts-media')
OLD = (SOURCE / 'config.txt.baseline').read_bytes()
NEW = (SOURCE / 'config.txt.candidate').read_bytes()
OVERLAY = 'omarchy-pi4-aux-rtscts.dtbo'

class Transactions(unittest.TestCase):
  def setUp(self):
    for p in (PAYLOAD, STATE, MEDIA, CONF.parent):
      if p.exists(): shutil.rmtree(p)
      p.mkdir(parents=True)
    STATE.rmdir()
    shutil.copytree(SOURCE, PAYLOAD, dirs_exist_ok=True)
    # Synthetic non-executable overlay bytes: helper verifies opaque ownership bytes.
    (PAYLOAD / OVERLAY).write_bytes(b'fixture-overlay-payload')
    baseline = {}
    for name in json.loads((SOURCE / 'baseline-media.json').read_text()):
      p = MEDIA / name
      p.parent.mkdir(parents=True, exist_ok=True)
      data = OLD if name == 'config.txt' else (Path('/inputs/stable-4.5/optimization/current-RPI_EFI.fd').read_bytes() if name == 'RPI_EFI.fd' else ('fixture:' + name).encode())
      p.write_bytes(data)
      baseline[name] = hashlib.sha256(data).hexdigest()
    (PAYLOAD / 'baseline-media.json').write_text(json.dumps(baseline))
    CONF.write_text(json.dumps({'mount': str(MEDIA), 'uuid': '1234-ABCD'}))
    CONF.chmod(0o644)
    self.facts = {'filesystems': [{'target': str(MEDIA), 'fstype': 'vfat', 'uuid': '1234-ABCD'}]}
    self.before = self.snapshot()

  def snapshot(self):
    return {str(p.relative_to(MEDIA)): p.read_bytes() for p in MEDIA.rglob('*') if p.is_file()}

  def run_helper(self, mode='check', fault=None, observe=None):
    real_replace, real_fsync = os.replace, os.fsync
    def replace(src, dst):
      if observe: observe('rename', Path(dst))
      if fault == ('rename', Path(dst).name): raise OSError('injected rename')
      result = real_replace(src, dst)
      if fault == ('corrupt', Path(dst).name): Path(dst).write_bytes(b'corrupted after publish')
      return result
    def fsync(fd):
      st = os.fstat(fd)
      p = next(p for root in (MEDIA, STATE) for p in (root, *root.rglob('*')) if p.exists() and (p.stat().st_dev,p.stat().st_ino)==(st.st_dev,st.st_ino))
      if observe: observe('fsync', p)
      if fault == ('fsync', p.name): raise OSError('injected fsync')
      return real_fsync(fd)
    # Inject write failure at the real opened file; no fake updater implementation.
    real_open = Path.open
    def opened(p, *args, **kwargs):
      f = real_open(p, *args, **kwargs)
      if fault == ('write', p.name) and 'x' in (args[0] if args else kwargs.get('mode', 'r')):
        class FailedWrite:
          def __enter__(self): return self
          def __exit__(self, *exc): f.close()
          def write(self, data):
            f.write(data[:3]); f.flush()
            raise OSError('injected partial write')
        return FailedWrite()
      return f
    def findmnt(args, **kwargs):
      self.assertEqual(args, ['/usr/bin/findmnt', '--json', '--mountpoint', str(MEDIA), '-o', 'TARGET,FSTYPE,UUID'])
      return json.dumps(self.facts)
    with patch.object(sys, 'argv', [str(SOURCE / 'media-sync.py'), mode]), patch('subprocess.check_output', findmnt), patch('os.replace', replace), patch('os.fsync', fsync), patch.object(Path, 'open', opened):
      runpy.run_path(str(SOURCE / 'media-sync.py'), run_name='__main__')

  def rejected(self):
    before = self.snapshot()
    with self.assertRaises((SystemExit, OSError, ValueError)): self.run_helper('apply')
    self.assertEqual(self.snapshot(), before)

  def test_baseline_check_no_write(self):
    self.run_helper()
    self.assertEqual(self.snapshot(), self.before)
    self.assertFalse(STATE.exists())

  def test_wrong_uuid(self):
    self.facts['filesystems'][0]['uuid'] = 'wrong'
    self.rejected()

  def test_wrong_filesystem(self):
    self.facts['filesystems'][0]['fstype'] = 'ext4'
    self.rejected()

  def test_unmounted(self):
    self.facts['filesystems'] = []
    self.rejected()

  def test_config_permissions(self):
    CONF.chmod(0o666)
    self.rejected()

  def test_config_owner(self):
    os.chown(CONF, 1234, 1234)
    self.rejected()

  def test_config_symlink(self):
    other = CONF.with_name('other'); CONF.rename(other); CONF.symlink_to(other)
    self.rejected()

  def test_config_parent_symlink(self):
    other = CONF.parent.with_name('cts-other')
    if other.exists(): shutil.rmtree(other)
    CONF.parent.rename(other); CONF.parent.symlink_to(other)
    try: self.rejected()
    finally:
      CONF.parent.unlink(); other.rename(CONF.parent)

  def test_overlay_parent_symlink_inside_mount(self):
    p = MEDIA / 'overlays'; p.rename(MEDIA / 'actual-overlays'); p.symlink_to(MEDIA / 'actual-overlays')
    self.rejected()

  def test_overlay_symlink(self):
    (MEDIA / 'overlays' / OVERLAY).symlink_to(MEDIA / 'config.txt')
    self.rejected()

  def test_baseline_drift(self):
    (MEDIA / 'RPI_EFI.fd').write_bytes(b'changed-NVRAM')
    self.rejected()

  def test_config_drift(self):
    (MEDIA / 'config.txt').write_bytes(OLD + b'custom=1\n')
    self.rejected()

  def test_backup_symlink(self):
    STATE.mkdir(exist_ok=True)
    (STATE / 'config.txt.before').symlink_to(MEDIA / 'config.txt')
    self.rejected()

  def test_publish_order(self):
    events = []
    def observe(op, p):
      events.append((op, str(p)))
      if op == 'rename' and p == MEDIA / 'config.txt':
        self.assertEqual((MEDIA / 'overlays' / OVERLAY).read_bytes(), (PAYLOAD / OVERLAY).read_bytes())
        self.assertIn(('fsync', str(MEDIA / 'overlays')), events)
    self.run_helper('apply', observe=observe)
    self.assertEqual((MEDIA / 'config.txt').read_bytes(), NEW)

  def test_failures_preserve_config_and_retry(self):
    for kind in ('write', 'fsync', 'rename'):
      for target in (OVERLAY, 'config.txt'):
        with self.subTest(kind=kind, target=target):
          self.setUp()
          name = target if kind == 'rename' else target + '.omarchy-new'
          with self.assertRaises(OSError): self.run_helper('apply', fault=(kind, name))
          self.assertEqual((MEDIA / 'config.txt').read_bytes(), OLD)
          self.run_helper('apply')
          self.assertEqual((MEDIA / 'config.txt').read_bytes(), NEW)

  def test_directory_sync_failure_before_config(self):
    with self.assertRaises(OSError): self.run_helper('apply', fault=('fsync', 'overlays'))
    self.assertEqual((MEDIA / 'config.txt').read_bytes(), OLD)
    self.run_helper('apply')

  def test_directory_sync_failure_after_config_is_not_rollback(self):
    with self.assertRaises(OSError): self.run_helper('apply', fault=('fsync', MEDIA.name))
    self.assertEqual((MEDIA / 'config.txt').read_bytes(), NEW)
    self.assertEqual((MEDIA / 'overlays' / OVERLAY).read_bytes(), (PAYLOAD / OVERLAY).read_bytes())
    self.run_helper('restore')
    self.assertEqual(self.snapshot(), self.before)

  def test_overlay_readback_before_config(self):
    with self.assertRaises(SystemExit): self.run_helper('apply', fault=('corrupt', OVERLAY))
    self.assertEqual((MEDIA / 'config.txt').read_bytes(), OLD)

  def test_restore_failures_keep_active_pair(self):
    for kind in ('write', 'fsync', 'rename'):
      with self.subTest(kind=kind):
        self.setUp(); self.run_helper('apply')
        name = 'config.txt' if kind == 'rename' else 'config.txt.omarchy-new'
        with self.assertRaises(OSError): self.run_helper('restore', fault=(kind, name))
        self.assertEqual((MEDIA / 'config.txt').read_bytes(), NEW)
        self.assertTrue((MEDIA / 'overlays' / OVERLAY).exists())
        self.run_helper('restore'); self.assertEqual(self.snapshot(), self.before)

  def test_stale_temporary_not_deleted(self):
    temp = MEDIA / 'config.txt.omarchy-new'
    temp.write_bytes(b'operator review')
    with self.assertRaises(SystemExit): self.run_helper('apply')
    self.assertEqual((MEDIA / 'config.txt').read_bytes(), OLD)
    self.assertEqual(temp.read_bytes(), b'operator review')

  def test_opt_in_without_overlay(self):
    (MEDIA / 'config.txt').write_bytes(NEW)
    self.rejected()

  def test_mount_symlink(self):
    link = MEDIA.with_name('cts-link')
    if link.is_symlink(): link.unlink()
    link.symlink_to(MEDIA)
    CONF.write_text(json.dumps({'mount': str(link), 'uuid': '1234-ABCD'}))
    try: self.rejected()
    finally: link.unlink()

  def test_repeat_restore_owned_only(self):
    self.run_helper('apply'); applied = self.snapshot()
    self.run_helper('apply'); self.assertEqual(self.snapshot(), applied)
    self.run_helper('restore'); self.assertEqual(self.snapshot(), self.before)
    self.run_helper('restore'); self.assertEqual(self.snapshot(), self.before)

  def test_remove_guard(self):
    self.run_helper('remove-check')
    self.run_helper('apply')
    with self.assertRaises(SystemExit): self.run_helper('remove-check')
    self.run_helper('restore'); self.run_helper('remove-check')

  def test_foreign_overlay_restore_rejected(self):
    self.run_helper('apply')
    (MEDIA / 'overlays' / OVERLAY).write_bytes(b'foreign')
    before = self.snapshot()
    with self.assertRaises(SystemExit): self.run_helper('restore')
    self.assertEqual(self.snapshot(), before)


  def test_nv_old_current_and_store_mutation_preserved(self):
    for path in ('current-RPI_EFI.fd','cts3211-current-RPI_EFI.fd'):
      data=Path('/inputs/stable-4.5/optimization',path).read_bytes()
      for mutated in (False,True):
        with self.subTest(path=path,mutated=mutated):
          self.setUp()
          b=bytearray(data)
          if mutated: b[0x3b1000]^=1
          efi=MEDIA/'RPI_EFI.fd';efi.write_bytes(b)
          for mode in ('check','apply','check','restore','remove-check'):
            self.run_helper(mode);self.assertEqual(efi.read_bytes(),bytes(b))

  def test_nv_change_after_apply_allows_restore(self):
    self.run_helper('apply')
    efi=MEDIA/'RPI_EFI.fd';b=bytearray(efi.read_bytes());b[0x3b2000]^=1;efi.write_bytes(b)
    self.run_helper('restore');self.run_helper('remove-check');self.assertEqual(efi.read_bytes(),bytes(b))

  def test_fixed_regions_and_headers_rejected_even_with_nv_change(self):
    for offset in (0,0x20000,0x3b0000,0x3b0030,0x3b0048,0x3b0058,0x3b0063,0x3be000,0x3bf000,0x3c0000):
      with self.subTest(offset=hex(offset)):
        self.setUp();efi=MEDIA/'RPI_EFI.fd';b=bytearray(efi.read_bytes());b[offset]^=1;b[0x3b1000]^=1;efi.write_bytes(b)
        for mode in ('check','apply','restore','remove-check'):
          before=self.snapshot()
          with self.assertRaises(SystemExit):self.run_helper(mode)
          self.assertEqual(self.snapshot(),before)

  def test_size_and_efi_symlink_rejected(self):
    for data in (b'', b'x'*0x3cffff, b'x'*0x3d0001):
      self.setUp();(MEDIA/'RPI_EFI.fd').write_bytes(data);self.rejected()
    self.setUp();p=MEDIA/'RPI_EFI.fd';p.rename(MEDIA/'saved.fd');p.symlink_to(MEDIA/'saved.fd');self.rejected()

  def test_manifest_permissions_and_symlink_rejected(self):
    p=PAYLOAD/'firmware-identity.json';p.chmod(0o666);self.rejected()
    p.chmod(0o644);p.rename(PAYLOAD/'saved.json');p.symlink_to(PAYLOAD/'saved.json');self.rejected()

  def test_old_helper_rejects_actual_current_nv(self):
    (MEDIA/'RPI_EFI.fd').write_bytes(Path('/inputs/stable-4.5/optimization/cts3211-current-RPI_EFI.fd').read_bytes())
    with patch.object(sys,'argv',['old','check']), patch('subprocess.check_output',return_value=json.dumps(self.facts)):
      with self.assertRaisesRegex(SystemExit,'Firmware baseline drift: RPI_EFI.fd'):
        runpy.run_path('/candidate/before/firmware/media-sync.py',run_name='__main__')

if __name__ == '__main__': unittest.main(verbosity=2)
