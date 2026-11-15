#!/usr/bin/env python3
"""Create a checksum-pinned makepkg input from the current working tree."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path, help='new or empty directory outside the checkout')
args = parser.parse_args()
out = args.output.resolve()
if out == root or root in out.parents:
    parser.error('output must be outside the checkout')
out.mkdir(parents=True, exist_ok=True)
if any(out.iterdir()):
    parser.error('output directory must be empty')

def git_files(directory):
    data = subprocess.check_output(['git', '-C', str(directory), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'])
    return {os.fsdecode(p) for p in data.split(b'\0') if p}

files = git_files(root)
files = sorted(p for p in files if (root / p).is_file() or (root / p).is_symlink())
epoch = int(subprocess.check_output(['git', '-C', str(root), 'show', '-s', '--format=%ct', 'HEAD'], text=True))
archive = out / 'fjord-files-source.tar.gz'
with tempfile.NamedTemporaryFile() as listing:
    listing.write(b''.join(os.fsencode(p) + b'\0' for p in files))
    listing.flush()
    tar = subprocess.Popen(['tar', '-C', str(root), '--no-recursion', '--null', '-T', listing.name,
                            '--sort=name', '--mtime=@' + str(epoch), '--owner=0', '--group=0',
                            '--numeric-owner', '--format=gnu', '--transform=flags=r;s,^,fjord-files/,', '-cf', '-'], stdout=subprocess.PIPE)
    with archive.open('wb') as dest:
        gzip = subprocess.run(['gzip', '-n', '-9'], stdin=tar.stdout, stdout=dest, check=True)
    tar.stdout.close()
    if tar.wait():
        raise SystemExit('tar failed')
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
recipe = (root / 'distro/arch/PKGBUILD').read_text().replace('SNAPSHOT_CHECKSUM', checksum)
(out / 'PKGBUILD').write_text(recipe)
(out / '.source-date-epoch').write_text(str(epoch) + '\n')
print(f'Snapshot: {archive}\nSHA256: {checksum}\nSOURCE_DATE_EPOCH: {epoch}')
