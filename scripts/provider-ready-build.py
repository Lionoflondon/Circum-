#!/usr/bin/env python3
"""Build-only provider configuration gate. Never deploys or uploads."""
import argparse,base64,json,os,re,subprocess,tempfile
from pathlib import Path

def validate_config(env,sender):
 key=env.get('GOOGLE_MAPS_API_KEY','').strip()
 if not re.fullmatch(r'AIza[A-Za-z0-9_-]{20,}',key):raise ValueError('A native platform-restricted Maps API key is required')
 defines={}
 if sender:
  mode=env.get('PAYMENT_ENVIRONMENT','').strip();pk=env.get('STRIPE_PUBLISHABLE_KEY','').strip()
  if mode not in ['test','live'] or not pk.startswith('pk_'+mode+'_') or len(pk)<30:raise ValueError('Explicit Stripe environment and matching publishable key are required')
  defines={'STRIPE_PUBLISHABLE_KEY':pk,'PAYMENT_ENVIRONMENT':mode}
 return key,defines

def main():
 parser=argparse.ArgumentParser();parser.add_argument('platform',choices=['android','ios']);parser.add_argument('--validation-build',action='store_true');parser.add_argument('--testflight-build',action='store_true');args=parser.parse_args()
 root=Path(__file__).resolve().parents[1];sender='name: circum\n' in (root/'pubspec.yaml').read_text()
 try:key,defines=validate_config(os.environ,sender)
 except ValueError as e:parser.error(str(e))
 name=os.getenv('BUILD_NAME','');number=os.getenv('BUILD_NUMBER','')
 if args.testflight_build and args.platform!='ios':parser.error('TestFlight export is iOS-only')
 if args.validation_build and args.testflight_build:parser.error('Choose one build mode')
 if not args.validation_build and (not name or not number):parser.error('Explicit BUILD_NAME and BUILD_NUMBER are required for release preparation')
 if name and not re.fullmatch(r'\d+\.\d+\.\d+',name):parser.error('Invalid BUILD_NAME')
 if number and not number.isdigit():parser.error('Invalid BUILD_NUMBER')
 xconfig=root/'ios/Flutter/ProviderKeys.xcconfig';old=xconfig.read_bytes() if xconfig.exists() else None
 sensitive=[key,*[v for k,v in defines.items() if k.endswith('_KEY')]]
 sensitive += [base64.b64encode((k+'='+v).encode()).decode() for k,v in defines.items()]
 try:
  if args.platform=='ios':
   configured=('GOOGLE_MAPS_API_KEY='+key+'\n').encode()
   if old!=configured:xconfig.write_bytes(configured)
   xconfig.chmod(0o600)
  with tempfile.TemporaryDirectory(prefix='.provider-build-',dir=root) as directory:
   config=Path(directory)/'defines.json';config.write_text(json.dumps(defines));config.chmod(0o600)
   command=['flutter','build','appbundle' if args.platform=='android' else 'ipa','--release','--no-pub','--dart-define-from-file='+str(config)]
   if args.platform=='ios' and not args.testflight_build:command.append('--no-codesign')
   if args.testflight_build:command+=['--export-method=app-store']
   if name:command+=['--build-name='+name]
   if number:command+=['--build-number='+number]
   print('Native Maps configuration present; '+('Stripe '+defines['PAYMENT_ENVIRONMENT']+' configuration present.' if sender else 'Rider payout-only configuration; no checkout SDK added.'),flush=True)
   child_env=os.environ.copy()
   if args.validation_build or args.testflight_build:child_env['CIRCUM_ALLOW_SYMBOL_UPLOAD']='0'
   with subprocess.Popen(command,cwd=root,env=child_env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace') as child:
    for line in child.stdout:
     for value in sensitive:
      if value:line=line.replace(value,'[REDACTED_PROVIDER_VALUE]')
     print(line,end='',flush=True)
    code=child.wait()
   if code:raise SystemExit(code)
 finally:
  if args.platform=='ios':
   if old is None:xconfig.unlink(missing_ok=True)
   else:
    if not xconfig.exists() or xconfig.read_bytes()!=old:xconfig.write_bytes(old)
    xconfig.chmod(0o600)
if __name__=='__main__':main()
