#!/usr/bin/env python3
"""Execute production VCHIQ callback functions, with pthread mutex primitives.
No replacement lifecycle state machine; function bytes come from kernel source.
This is a transport callback test, NOT a VCSM teardown/firmware test.
"""
from pathlib import Path
import subprocess, sys
r=Path(__file__).resolve().parents[2]
source=r/(sys.argv[1] if len(sys.argv)>1 else 'source')/'drivers/platform/raspberrypi/vchiq-interface/vchiq_arm.c'
b=source.read_text()
names=['vchiq_call_connected_callbacks','vchiq_add_connected_callback_sync','vchiq_remove_connected_callback']
functions=[]
for name in names:
 pos=b.index(name+'('); start=b.rfind('\n',0,pos)+1
 # include static void line or int/void on same line
 if name!='vchiq_call_connected_callbacks': start=b.rfind('\n',0,pos)+1
 begin=b.index('{',pos); level=1; end=begin+1
 while level:
  level+=(b[end]=='{')-(b[end]=='}');end+=1
 functions.append(b[start:end])
mutant = '--mutant-unlocked-dispatch' in sys.argv
if mutant:
 functions[0]=functions[0].replace('drv_mgmt->deferred_callback[i]();', '({ mutex_unlock(&drv_mgmt->connected_mutex); drv_mgmt->deferred_callback[i](); mutex_lock(&drv_mgmt->connected_mutex); });')
out=r/('lifecycle-unit/tests/generated-callback-mutant.c' if mutant else 'lifecycle-unit/tests/generated-callback-test.c')
harness=(r/'lifecycle-unit/tests/harness.c').read_text()
out.write_text(harness.replace('/* PRODUCTION_FUNCTIONS */','\n\n'.join(functions)))
exe=out.with_suffix('')
subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-pthread','-fsanitize=address,undefined','-g',str(out),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True,timeout=30)
