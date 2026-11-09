#!/usr/bin/env python3
"""Export a working tree without ignored artifacts or Git metadata."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys

root, destination = map(Path, sys.argv[1:3])
epoch = int(sys.argv[3])
names = subprocess.check_output([
    "git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"
]).split(b"\0")
digest = hashlib.sha256()
for raw in sorted(set(names)):
    if not raw:
        continue
    name = Path(os.fsdecode(raw))
    source, target = root / name, destination / name
    if not source.is_file() and not source.is_symlink():
        continue
    digest.update(raw + b"\0")
    digest.update(str(source.lstat().st_mode & 0o777).encode() + b"\0")
    digest.update(os.fsencode(os.readlink(source)) if source.is_symlink() else source.read_bytes())
    digest.update(b"\0")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target, follow_symlinks=False)
    os.utime(target, (epoch, epoch), follow_symlinks=False)

print(digest.hexdigest())
