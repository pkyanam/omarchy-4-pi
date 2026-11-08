import hashlib,json,os,sys,stat
from pathlib import Path

def digest(p):
  h=hashlib.sha256()
  with p.open('rb') as f:
    for b in iter(lambda:f.read(1048576),b''): h.update(b)
  return h.hexdigest()
def tree(p):
  out={}
  for f in sorted(p.rglob('*')):
    if f.is_symlink(): out[str(f.relative_to(p))]={'symlink':os.readlink(f)}
    elif f.is_file(): out[str(f.relative_to(p))]={'sha256':digest(f),'bytes':f.stat().st_size}
  return out
if __name__=='__main__':
  json.dump(tree(Path(sys.argv[1])),open(sys.argv[2],'w'),indent=2,sort_keys=True)
