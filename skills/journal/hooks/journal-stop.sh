#!/usr/bin/env bash
# Stop hook: fires when Claude is about to stop. Enforces the barrier audit trail
# (exit 2 + reason on stderr re-wakes Claude), in order:
#   1. run-entry schema — every `type: run` entry carries the required structured
#      header (agent/task/verdict∈{PASS,BLOCK,SKIP}/critical/high/rework). A
#      prose-only run entry is rejected, so the rework cap + rollup can read fields.
#   2. audit completeness — every gate run recorded by run-check.sh has a matching
#      `run` entry (a missing entry is an error, not just a nudge).
#   3. docs changed since the last journal entry → nudge to log (pre-existing).
# Resolves paths against CLAUDE_PROJECT_DIR (BASH_SOURCE fallback) — Stop hooks do
# NOT reliably run from the project root.

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
journal="$root/journal.yaml"

# No journal yet → nothing to check.
[[ -f "$journal" ]] || exit 0

# ── 1. run-entry schema validation (POSIX awk — must run under BSD awk) ───────
# Prints one line per malformed `run` entry; empty output means all valid.
run_schema_problems() {
  awk '
    function flush() {
      if (isrun) {
        miss = ""
        if (!fa) miss = miss "agent "
        if (!ft) miss = miss "task "
        if (!fv) miss = miss "verdict "
        if (!fc) miss = miss "critical "
        if (!fh) miss = miss "high "
        if (!fr) miss = miss "rework "
        if (miss != "")
          print "  - run entry [" id "]: missing field(s): " miss
        else if (vv !~ /^(PASS|BLOCK|SKIP)$/)
          print "  - run entry [" id "]: invalid verdict \"" vv "\" (want PASS|BLOCK|SKIP)"
      }
    }
    /^-[[:space:]]/ {
      flush()
      isrun = 0; fa = 0; ft = 0; fv = 0; fc = 0; fh = 0; fr = 0; vv = ""
      id = "?"
      if (match($0, /date:[[:space:]]*/)) id = substr($0, RSTART + RLENGTH)
    }
    /^[[:space:]]+type:[[:space:]]*run[[:space:]]*$/ { isrun = 1 }
    /^[[:space:]]+agent:[[:space:]]*[^[:space:]]/    { fa = 1 }
    /^[[:space:]]+task:[[:space:]]*[^[:space:]]/     { ft = 1 }
    /^[[:space:]]+critical:[[:space:]]*[0-9]/        { fc = 1 }
    /^[[:space:]]+high:[[:space:]]*[0-9]/            { fh = 1 }
    /^[[:space:]]+rework:[[:space:]]*[0-9]/          { fr = 1 }
    /^[[:space:]]+verdict:[[:space:]]*[A-Za-z]/ {
      fv = 1; v = $0
      sub(/^[[:space:]]+verdict:[[:space:]]*/, "", v)
      sub(/[[:space:]#].*$/, "", v)
      vv = v
    }
    END { flush() }
  ' "$journal"
}

problems="$(run_schema_problems)"
if [[ -n "$problems" ]]; then
  {
    echo "Malformed 'run' journal entries — the barrier audit schema requires agent/task/verdict(PASS|BLOCK|SKIP)/critical/high/rework as structured fields (the prose summary does not substitute). Fix before stopping:"
    echo "$problems"
  } >&2
  exit 2
fi

# ── 2. audit completeness — recorded gate runs must each have a run entry ─────
pending="$root/.claude/state/pending-gate-runs"
baseline="$root/.claude/state/pending-baseline"
if [[ -s "$pending" ]]; then
  ran=$(grep -c . "$pending" 2>/dev/null || true);   ran=${ran:-0}
  base=$(cat "$baseline" 2>/dev/null || echo 0);      base=${base:-0}
  now=$(grep -cE '^[[:space:]]+type:[[:space:]]*run[[:space:]]*$' "$journal" 2>/dev/null || true); now=${now:-0}
  written=$(( now - base ))
  if [[ "$written" -lt "$ran" ]]; then
    echo "Barrier audit incomplete: ${ran} gate run(s) this session but only ${written} 'run' entry(ies) logged. Append a 'run' entry for each gate that ran (pending: $(sort -u "$pending" | tr '\n' ' ')) before stopping." >&2
    exit 2
  fi
  # Reconciled — clear the session markers.
  rm -f "$pending" "$baseline"
fi

# ── 3. docs changed since last journal entry (pre-existing nudge) ─────────────
newer=$(find "$root/docs" -name '*.md' -newer "$journal" 2>/dev/null | head -1)
if [[ -n "$newer" ]]; then
  echo "Docs modified since last journal entry ($(basename "$newer")). Write any missing /journal entries before stopping." >&2
  exit 2
fi

exit 0
