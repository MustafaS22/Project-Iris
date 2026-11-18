"""Package an already tested Iris release. Quit Iris through its UI before using."""
from pathlib import Path
import sys,plistlib,subprocess,os,shutil,hashlib,json
root=Path(__file__).resolve().parents[1];stage=root/'macOS';version,build=sys.argv[1:3]
out=root/'outputs'/('Iris-'+version);pack=stage/'packaging'/('Iris-'+version)
out.mkdir(exist_ok=True);pack.mkdir(exist_ok=True)
for config,folder in [('Debug','build'),('Release','release-build')]:
 d=plistlib.loads((stage/folder/'Build/Products'/config/'Project IRIS.app/Contents/Info.plist').read_bytes())
 assert d['CFBundleShortVersionString']==version and str(d['CFBundleVersion'])==build
assert not subprocess.run(['pgrep','-f','^/Applications/Iris.app/Contents/MacOS/'],stdout=subprocess.DEVNULL).returncode==0,'Quit installed Iris first'
def run(args):subprocess.run(args,check=True,stdout=subprocess.DEVNULL)
app=pack/'Iris.app';run(['ditto',str(stage/'release-build/Build/Products/Release/Project IRIS.app'),str(app)])
if tuple(map(int,version.split('.'))) >= (2,0,32):
 run([sys.executable,str(root/'tools/sign-iris-release.py'),str(app)])
else:
 run(['codesign','--force','--deep','--sign','-','--options','runtime','--entitlements',str(stage/'Configuration/Iris.entitlements'),str(app)])
run(['codesign','--verify','--deep','--strict',str(app)])
if not (pack/'Applications').exists():(pack/'Applications').symlink_to('/Applications')
(pack/'Read Me.txt').write_text('Iris '+version+' by AriZe\nApple Silicon · macOS 15+. Apple Development signed; not Apple-notarized.\nUpdate Iris from Settings → Updates. Source credits included in the app.\n')
backup=out/('Iris-before-'+version+'.app')
if not backup.exists():os.rename('/Applications/Iris.app',backup)
else:
 current=plistlib.loads(Path('/Applications/Iris.app/Contents/Info.plist').read_bytes())
 assert current['CFBundleShortVersionString']==version,'Unexpected app replacement'
run(['ditto',str(app),'/Applications/Iris.app']);run(['codesign','--verify','--deep','--strict','/Applications/Iris.app'])
dmg=root/'outputs'/('Iris-'+version+'.dmg');run(['hdiutil','create','-ov','-volname','Iris '+version,'-srcfolder',str(pack),'-format','UDZO',str(dmg)]);run(['hdiutil','verify',str(dmg)])
(out/'package.json').write_text(json.dumps({'version':version,'build':build,'sha256':hashlib.sha256(dmg.read_bytes()).hexdigest()},indent=2));print('Installed and verified Iris '+version)
if tuple(map(int,version.split('.'))) >= (2,0,32):
 config=json.loads((stage/'Configuration/ReleaseSigning.json').read_text())
 tool=stage/'release-build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update'
 if not tool.exists(): tool=stage/'Vendor/Sparkle/bin/sign_update'
 signature=subprocess.check_output([str(tool),'--account',config['account'],'-p',str(dmg)],text=True).strip()
 run([str(tool),'--account',config['account'],'--verify',str(dmg),signature])
 (out/'updater.json').write_text(json.dumps({'version':version,'build':build,'signature':signature,'length':dmg.stat().st_size},indent=2))
 print('Signed the installer for in-app updates; upload updater.json values with the DMG.')

sync_tool=root/'tools/sync-source.py'
sync_config=root/'.iris-sync.local.json'
if sync_tool.exists() and sync_config.exists():
 run([sys.executable,str(sync_tool),'--config',str(sync_config),'--apps','--push','--version',version])
 print('Pushed release source and its version tag to GitHub.')
