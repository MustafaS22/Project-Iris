"""Sign Iris and nested update helpers using the pinned existing Apple identity.

Private update-signing material stays in Keychain. Never sign releases ad hoc:
stable code requirements are how macOS recognizes future Iris updates.
"""
from pathlib import Path
import json, subprocess, sys

ROOT = Path(__file__).resolve().parents[1] / 'macOS'
def sign(app: Path):
    config = json.loads((ROOT/'Configuration/ReleaseSigning.json').read_text())
    identity = config['identity']
    found = subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
    if identity not in found:
        raise RuntimeError('The pinned Iris signing identity is unavailable. Restore it before making a release; do not switch to ad hoc signing.')
    def run(path, main=False):
        args=['codesign','--force','--sign',identity,'--options','runtime']
        args += ['--entitlements',str(ROOT/'Configuration/Iris.entitlements')] if main else ['--preserve-metadata=entitlements']
        subprocess.run(args+[str(path)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    # Sign nested Mach-O helpers first, then their bundles from the inside out.
    magic={b'\xcf\xfa\xed\xfe',b'\xce\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xca\xfe\xba\xbf'}
    for path in app.rglob('*'):
        if path.is_symlink() or not path.is_file(): continue
        with path.open('rb') as f: header=f.read(4)
        if header in magic: run(path)
    bundles=[p for p in app.rglob('*') if not p.is_symlink() and p.is_dir() and p.suffix in {'.app','.xpc','.framework'}]
    for path in sorted(bundles,key=lambda p:len(p.parts),reverse=True): run(path)
    run(app,main=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    public_key = __import__('plistlib').loads((app/'Contents/Info.plist').read_bytes()).get('SUPublicEDKey')
    if public_key != config['publicKey']: raise RuntimeError('The embedded update key differs from the release key.')

if __name__=='__main__': sign(Path(sys.argv[1]).resolve())
