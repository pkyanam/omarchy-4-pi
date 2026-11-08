from pathlib import Path
import re,subprocess,sys
r=Path(__file__).resolve().parents[1];u=r/'progress-unit';s=r/sys.argv[1];out=u/sys.argv[2];out.mkdir(exist_ok=False)
t=(s/'drivers/platform/raspberrypi/vchiq-interface/vchiq_core.c').read_text()
def body(name):
 m=re.search(r'(?m)^(?:[a-zA-Z_][a-zA-Z_ *]*[ *])?'+name+r'\(',t);i=m.start();a=t.index('{',i);n=1;b=a+1
 while n:n+=(t[b]=='{')-(t[b]=='}');b+=1
 return t[t.rfind('\n\n',0,i)+2:b]+'\n'
shim=(r/'smio-unit/shim.c').read_text().split('struct task_struct {')[0]
code=shim+(u/'boundary.c').read_text()
for n in ['memcpy_copy_callback','copy_message_data','queue_message','request_poll','requeue_owned_removal','vchiq_free_service_internal','close_service_complete','vchiq_close_service_internal','poll_services_of_group','vchiq_open_service_internal','parse_message','sync_func','vchiq_remove_service_sync']:
 if n=='requeue_owned_removal' and n+'(' not in t:continue
 code+=body(n).replace("inline void\nrequest_poll", "static inline void\nrequest_poll")
code+=(u/'cases.c').read_text();
if '--mutant-close-state' in sys.argv:
 code=code.replace('if (service && (type == VCHIQ_MSG_CLOSE))', 'if (0 && service && (type == VCHIQ_MSG_CLOSE))')
(out/'generated.c').write_text(code)
subprocess.run(['cc','-std=gnu11','-pthread','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-unused-function','-Wno-sign-compare','-Wno-unused-but-set-variable','-fsanitize=address,undefined','-fno-sanitize-recover=all','-g',str(out/'generated.c'),'-o',str(out/'test')],check=True)
subprocess.run([str(out/'test')],check=True,timeout=20)
