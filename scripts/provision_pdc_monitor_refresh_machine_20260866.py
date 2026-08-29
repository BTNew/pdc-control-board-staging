#!/usr/bin/env python3
"""Provision a machine-DPAPI handoff from the existing staging actor store."""
from __future__ import annotations
import ctypes,ctypes.wintypes as wt,hashlib,importlib.util,json,os,subprocess
from pathlib import Path
PROJECT='cdsmnqxtyyoeoznmbidd';URL=f'https://{PROJECT}.supabase.co';ACTOR_ID='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b';ACTOR_EMAIL='sales@broometoyota.com.au';GATEWAY='pdc-monitor-staging-sales-uid509-v1';RELEASE='pdc-monitor-staging-m502-2026.08.44';FLAGS=4
class BLOB(ctypes.Structure): _fields_=[('cbData',wt.DWORD),('pbData',ctypes.POINTER(ctypes.c_byte))]
def unprotect(data):
 s=BLOB(len(data),ctypes.cast(ctypes.create_string_buffer(data),ctypes.POINTER(ctypes.c_byte)));o=BLOB()
 if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(s),None,None,None,None,0,ctypes.byref(o)):raise OSError('user DPAPI decryption failed')
 try:return ctypes.string_at(o.pbData,o.cbData)
 finally:ctypes.windll.kernel32.LocalFree(o.pbData)
def protect(data):
 s=BLOB(len(data),ctypes.cast(ctypes.create_string_buffer(data),ctypes.POINTER(ctypes.c_byte)));o=BLOB()
 if not ctypes.windll.crypt32.CryptProtectData(ctypes.byref(s),'Hermes staging monitor refresh',None,None,None,FLAGS,ctypes.byref(o)):raise OSError('machine DPAPI encryption failed')
 try:return ctypes.string_at(o.pbData,o.cbData)
 finally:ctypes.windll.kernel32.LocalFree(o.pbData)
def main():
 p=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-monitor-refresh.dpapi');a=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi');out=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-monitor-refresh-machine-20260866.dpapi')
 spec=importlib.util.spec_from_file_location('boot',r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py');m=importlib.util.module_from_spec(spec);assert spec and spec.loader;spec.loader.exec_module(m)
 user=json.loads(unprotect(p.read_bytes()).decode());admin=json.loads(unprotect(a.read_bytes()).decode());password=user.get('password');anon=admin.get('PDC_STAGING_SUPABASE_ANON_KEY')
 if user.get('project_ref')!=PROJECT or user.get('auth_user_id')!=ACTOR_ID or str(user.get('actor_email','')).lower()!=ACTOR_EMAIL or not isinstance(password,str) or not password or admin.get('PDC_STAGING_PROJECT_REF')!=PROJECT or not isinstance(anon,str) or not anon or any(x in json.dumps({'anon':anon,'user':{k:user.get(k) for k in ('project_ref','auth_user_id','actor_email','password')}},sort_keys=True).lower() for x in ('service_role','sb_secret_','vjdtsswhroyguxyfjdkt','production')):raise RuntimeError('existing actor/staging store scope mismatch')
 payload={'project_ref':PROJECT,'supabase_url':URL,'anon_key':anon,'password':password,'actor_id':ACTOR_ID,'actor_email':ACTOR_EMAIL,'gateway':GATEWAY,'release_name':RELEASE};blob=protect(json.dumps(payload,sort_keys=True,separators=(',',':')).encode());tmp=out.with_suffix('.tmp');tmp.write_bytes(blob);os.replace(tmp,out)
 q=subprocess.run(['icacls.exe',str(out),'/inheritance:r','/grant:r','*S-1-5-18:(F)','*S-1-5-32-544:(F)','*S-1-5-19:(RX)'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);
 if q.returncode:raise RuntimeError('machine store ACL setup failed')
 print(json.dumps({'ok':True,'path':str(out),'sha256':hashlib.sha256(blob).hexdigest(),'actor_id':ACTOR_ID,'actor_email':ACTOR_EMAIL,'project_ref':PROJECT,'local_machine_dpapi':True,'local_service_read':True,'password_rotated':False,'secrets_printed':False,'production_contacted':False},sort_keys=True))
if __name__=='__main__':
 try:main()
 except Exception as e: print(json.dumps({'ok':False,'error':str(e),'secrets_printed':False,'production_contacted':False},sort_keys=True));raise SystemExit(1)
