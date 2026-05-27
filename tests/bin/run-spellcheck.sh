#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers/test-common.sh"

cd "${REPO_DIR}"
mapfile -t files < <(spell_files)
if ((${#files[@]} == 0)); then
  echo "No text files found."
  exit 0
fi

if command -v codespell >/dev/null 2>&1; then
  exec codespell --ignore-words="${SPELL_ALLOWLIST}" "${files[@]}"
fi

python3 - "$SPELL_ALLOWLIST" "${files[@]}" <<'PY'
import pathlib
import re
import sys

allowlist_path = pathlib.Path(sys.argv[1])
files = [pathlib.Path(p) for p in sys.argv[2:]]
allow = {
    line.strip().lower()
    for line in allowlist_path.read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.lstrip().startswith("#")
}
typos = {
    "teh": "the",
    "enviroment": "environment",
    "recieve": "receive",
    "seperate": "separate",
    "definately": "definitely",
}
pattern = re.compile(r"[A-Za-z][A-Za-z'-]+")
problems = []

for file_path in files:
    try:
        text = file_path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    for lineno, line in enumerate(text.splitlines(), start=1):
        for token in pattern.findall(line):
            word = token.lower()
            if word in allow:
                continue
            if word in typos:
                problems.append(f"{file_path}:{lineno}: {token} -> {typos[word]}")

if problems:
    print("\n".join(problems), file=sys.stderr)
    sys.exit(1)
PY
