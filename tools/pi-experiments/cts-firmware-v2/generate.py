from pathlib import Path
import hashlib,json,re,struct
n=Path(__file__).resolve().parent;r=n.parent
fdf=(n/'reference/RPi4.fdf').read_text(); block=fdf.split('# NV_VARIABLE_STORE\n')[1].split('# NV_EVENT_LOG')[0];block=re.sub(r'#.*','',block);data=block.split('DATA = {')[1].split('}')[0];header=bytes(int(x,16) for x in re.findall(r'0x[0-9a-fA-F]+',data));assert len(header)==100
b=(r/'optimization/current-RPI_EFI.fd').read_bytes();assert hashlib.sha256(b).hexdigest()=='9d7e2b14292e9275f1bc00ebcb07fc879a629c343cedea6381776d1696d77067';assert b[0x3b0000:0x3b0064]==header
fvlen=struct.unpack_from('<H',header,48)[0];storesize=struct.calcsize('<16sIBBHI');assert fvlen==72 and storesize==28
(n/'reference/header.bin').write_bytes(header)
manifest=dict(schema=1,route='private-reviewed-PFTF-RPi4-1.53',size=0x3d0000,baseline_sha256=hashlib.sha256(b).hexdigest(),mutable=dict(start=0x3b0000+fvlen+storesize,end=0x3be000,contract='NV variable data only; never written by this helper'),sources=dict(pftf='v1.53',edk2='2970e5699ba6267f3384ffab20f96647578aebc8',edk2_platforms='c8295e076affae5cf04fd4234db13a0e025f44e1',definitions='RPi4.fdf DATA explicitly serializes EFI_FIRMWARE_VOLUME_HEADER and VARIABLE_STORE_HEADER fields; header length 0x48 plus GUID/UINT32/UINT8/UINT8/UINT16/UINT32 = 28 bytes',files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (n/'reference').iterdir()}),regions=[])
for name,a,z in [('ATF',0,0x20000),('UEFI',0x20000,0x3b0000),('FV-and-variable-store-headers',0x3b0000,0x3b0064),('NV-event',0x3be000,0x3bf000),('FTW-working',0x3bf000,0x3c0000),('FTW-spare',0x3c0000,0x3d0000)]:manifest['regions'].append(dict(name=name,start=a,end=z,sha256=hashlib.sha256(b[a:z]).hexdigest()))
(n/'firmware/firmware-identity.json').write_text(json.dumps(manifest,indent=2)+'\n')
p=n/'firmware/media-sync.py';s=(n/'before/firmware/media-sync.py').read_text();needle="  if name!='config.txt': require(digest(p)==expected,'Firmware baseline drift: '+name)";assert needle in s
s=s.replace(needle,"""  if name=='RPI_EFI.fd':
    identity=payload/'firmware-identity.json'
    require(identity.resolve()==identity and identity.is_file() and identity.stat().st_uid==0 and identity.stat().st_mode & 0o022==0, 'Unsafe firmware identity manifest')
    ident=json.loads(identity.read_text())
    require(ident['schema']==1 and ident['route']=='private-reviewed-PFTF-RPi4-1.53', 'Unknown firmware identity route')
    data=p.read_bytes()
    require(len(data)==ident['size']==0x3d0000, 'Firmware identity length mismatch')
    spans=[(0,0x20000),(0x20000,0x3b0000),(0x3b0000,0x3b0064),(0x3be000,0x3bf000),(0x3bf000,0x3c0000),(0x3c0000,0x3d0000)]
    require([(r['start'],r['end']) for r in ident['regions']]==spans and ident['mutable']['start']==0x3b0064 and ident['mutable']['end']==0x3be000, 'Invalid firmware identity coverage')
    for r in ident['regions']:
      require(hashlib.sha256(data[r['start']:r['end']]).hexdigest()==r['sha256'], 'Firmware fixed-region drift: '+r['name'])
    # Fixed hashes authenticate FV checksum/block map and the complete store
    # GUID/size/format/health/reserved fields before interpreting any lengths.
    import struct
    fv=0x3b0000
    hlen=struct.unpack_from('<H',data,fv+48)[0]
    require(hlen==0x48 and hlen+struct.calcsize('<16sIBBHI')==ident['mutable']['start']-fv, 'Malformed firmware header boundary')
    require(sum(struct.unpack_from('<'+str(hlen//2)+'H',data,fv)) & 0xffff==0, 'Malformed FV checksum')
    require(struct.unpack_from('<I',data,fv+hlen+16)[0]==0xe000-hlen, 'Malformed variable store size')
  elif name!='config.txt': require(digest(p)==expected,'Firmware baseline drift: '+name)""")
p.write_text(s)
recipe=(r/'cts-private-package-set-3211/recipes/firmware.PKGBUILD').read_text().replace('pkgrel=1.1','pkgrel=2').replace("'09-omarchy-pi4-cts-remove.hook')","'09-omarchy-pi4-cts-remove.hook' 'firmware-identity.json')").replace('omarchy-pi4-aux-rtscts.dtbo baseline-media.json','omarchy-pi4-aux-rtscts.dtbo firmware-identity.json baseline-media.json')
source=re.search(r'source=\((.*?)\)',recipe).group(1);files=re.findall("'([^']+)'",source);hashes=[hashlib.sha256((n/'firmware'/f).read_bytes()).hexdigest() for f in files];recipe=re.sub(r'sha256sums=\(.*?\)',"sha256sums=("+' '.join("'"+h+"'" for h in hashes)+')',recipe);(n/'firmware/PKGBUILD').write_text(recipe)
import shutil
shutil.copy2(r/'cts-private-package-set-3211/media-inputs.json',n/'media-inputs.json')
(n/'logs/input-pins.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [r/'optimization/current-RPI_EFI.fd',r/'optimization/cts3211-current-RPI_EFI.fd',r/'optimization/cts3211-firmware-region-comparison.json',n/'before/transactions.py',*list((n/'before/firmware').iterdir())] if p.is_file()},indent=2))
print('Derived and authenticated boundary',hex(manifest['mutable']['start']))
