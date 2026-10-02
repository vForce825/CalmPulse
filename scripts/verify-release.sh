#!/bin/bash
set -euo pipefail
python3 -m unittest discover -s Tests -p 'test_*.py'
swift test --package-path Packages/WellnessCore
swift test
bash scripts/verify-platform.sh
# Tracked text only; no real health records, certificates, keys or analytics may be published.
python3 - <<'PY'
import pathlib, re, subprocess
for path in subprocess.check_output(['git','ls-files'], text=True).splitlines():
    p=pathlib.Path(path)
    if p.suffix in {'.p12','.p8','.mobileprovision','.pem','.key'}: raise SystemExit('Credential file prohibited: '+path)
    text=p.read_text(errors='ignore')
    if re.search(r'(gh[pousr]_[A-Za-z0-9]{25,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC )?PRIVATE KEY-----)',text):
        raise SystemExit('Possible credential in '+path)
print('Tracked text credential scan passed')
PY
