#!/usr/bin/env bash
# review-pr.sh — Revue d'un diff Git sur 3 axes : review / sécurité / changelog
# Usage  : git diff main...pr2 | ./review-pr.sh
# Sortie : tableau JSON de findings sur stdout, [] si la PR est propre
#
# Local (Claude Code) : utilise `claude -p` — aucune clé requise
# CI (GitHub Actions) : utilise Python + OPENAI_API_KEY (GitHub Secret)
set -euo pipefail

PROMPT='You are a strict code-security and quality reviewer. Your ONLY output is a JSON array — no text before, no text after, no markdown fences.

Analyze the git diff on three axes:

1. category "review"
   - Bugs or regressions introduced by the diff
   - Tests deleted or weakened so CI passes (test function removed, assert replaced by pass, test marked skip without reason)
   - Any call to print() / console.log() / fmt.Println() left in production code → ALWAYS at least warning

2. category "security"
   - Hardcoded secrets, API tokens, passwords, private keys → ALWAYS critical
   - SQL injection: string concatenation or f-string used to build a SQL query → ALWAYS critical
   - Authentication bypass

3. category "changelog"
   - A public function is added, modified, or removed WITHOUT a corresponding entry under ## [Unreleased] in CHANGELOG.md

Severity rules:
  "critical"  → hardcoded secrets/tokens, SQL injection, deleted/weakened tests
  "warning"   → debug print() left in production code, TODO/FIXME comments, minor quality issues
  "info"      → style suggestions, missing docstrings

Each finding:
  {"file": "<relative/path>", "line": <integer>, "severity": "critical|warning|info", "category": "review|security|changelog", "message": "<concise description in English>"}

Line number rule: in diff hunk headers (@@ -old +NEW,len @@) the number NEW is the first line of the chunk in the new file. Count added (+) and context lines from NEW to find the exact line.

ABSOLUTE RULES — a violation disqualifies the agent:
  - Return EXACTLY [] for a clean diff — NEVER invent findings
  - Only report what is clearly visible in added lines (lines prefixed +) in the diff
  - Output ONLY the JSON array, nothing else'

# Capture le diff stdin dans un fichier temporaire
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT
cat > "$TMPFILE"

if [[ -z "${CI:-}" ]] && command -v claude &>/dev/null; then
  # ── MODE LOCAL : claude -p (authentification Claude Code, pas de clé requise)
  claude -p "$PROMPT" < "$TMPFILE"

else
  # ── MODE CI : Python + OPENAI_API_KEY (GitHub Secret)
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo '{"error": "OPENAI_API_KEY is not set"}' >&2
    exit 1
  fi

  export REVIEW_DIFF_FILE="$TMPFILE"
  export REVIEW_PROMPT="$PROMPT"

  if command -v py &>/dev/null; then
    PYTHON="py -3.11"
  else
    PYTHON="python3"
  fi

  $PYTHON - <<'PYEOF'
import os, sys, json, pathlib
from openai import OpenAI

diff = pathlib.Path(os.environ["REVIEW_DIFF_FILE"]).read_text(encoding="utf-8", errors="replace")

if not diff.strip():
    print("[]")
    sys.exit(0)

model = os.environ.get("REVIEW_MODEL", "gpt-4o-mini")
client = OpenAI()

response = client.chat.completions.create(
    model=model,
    max_tokens=2048,
    messages=[
        {"role": "system", "content": os.environ["REVIEW_PROMPT"]},
        {"role": "user",   "content": "Review this git diff:\n\n" + diff},
    ],
)

text = response.choices[0].message.content.strip()

if text.startswith("```"):
    text = "\n".join(text.split("\n")[1:])
if text.endswith("```"):
    text = "\n".join(text.split("\n")[:-1])
text = text.strip()

findings = json.loads(text)
print(json.dumps(findings, ensure_ascii=False))

# Coût par million de tokens (prix publics OpenAI, juin 2026)
PRICING = {
    "gpt-4o-mini":    {"input": 0.150, "output": 0.600},
    "gpt-4o":         {"input": 2.500, "output": 10.000},
    "gpt-4-turbo":    {"input": 10.00, "output": 30.000},
}
usage = response.usage
prices = PRICING.get(model, {"input": 0.0, "output": 0.0})
cost = (usage.prompt_tokens * prices["input"] + usage.completion_tokens * prices["output"]) / 1_000_000
meta = {
    "model": model,
    "prompt_tokens": usage.prompt_tokens,
    "completion_tokens": usage.completion_tokens,
    "total_tokens": usage.total_tokens,
    "cost_usd": round(cost, 6),
}
pathlib.Path("review_meta.json").write_text(json.dumps(meta, ensure_ascii=False))
PYEOF

fi
