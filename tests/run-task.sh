#!/usr/bin/env bash
# Checks the Run task in languages/*/tasks.json and runs its shell command against fake CLIs.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
sql_tasks="$root/languages/dynotable-sql/tasks.json"
partiql_tasks="$root/languages/partiql/tasks.json"
hint='Run needs dynotable-cli 0.1.2 or later: npm install -g dynotable-cli'
failures=0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

pass() {
  echo "ok: $1"
}

# Zed puts the task in a shell string with no escaping. A quote or a ZED_ reference in a task
# lets a file name break the command or inject one, so the task reads ZED_FILE from the env.
gate() {
  local file=$1
  if [ "$(jq '[.[] | has("args")] | any' "$file")" != false ]; then
    echo "a task has args"
    return 1
  fi
  local bad
  bad=$(jq -r --arg q "'" '
    .[] | to_entries[]
    | select((.key == "cwd" and .value == "$ZED_WORKTREE_ROOT") | not)
    | .value | .. | strings
    | select(contains($q) or contains("\"") or contains("ZED_"))
  ' "$file")
  if [ -n "$bad" ]; then
    echo "unsafe string: $bad"
    return 1
  fi
}

if cmp -s "$sql_tasks" "$partiql_tasks"; then
  pass "both tasks.json are equal"
else
  fail "languages/dynotable-sql/tasks.json and languages/partiql/tasks.json differ"
fi

if out=$(gate "$sql_tasks"); then
  pass "gate accepts tasks.json"
else
  fail "gate: $out"
fi

jq '.[0].command += "; echo ${ZED_FILE}"' "$sql_tasks" >"$tmp/mutated.json"
if gate "$tmp/mutated.json" >/dev/null; then
  fail "gate accepts a command holding \${ZED_FILE}"
else
  pass "gate refuses a command holding \${ZED_FILE}"
fi

task_tags=$(jq -c '.[0].tags' "$sql_tasks")
for lang in dynotable-sql partiql; do
  tag=$(sed -n 's/.*(#set! tag \([^)]*\)).*/\1/p' "$root/languages/$lang/runnables.scm")
  if [ "$task_tags" = "[\"$tag\"]" ]; then
    pass "$lang runnables.scm tag equals the task tags"
  else
    fail "$lang runnables.scm tag '$tag' is not the task tags $task_tags"
  fi
done

command=$(jq -r '.[0].command' "$sql_tasks")
sh_dir=$(dirname "$(command -v sh)")
mac_bin='Library/Application Support/Zed/extensions/work/dynotable/node_modules/.bin'
linux_bin='.local/share/zed/extensions/work/dynotable/node_modules/.bin'

# fake <dir> <version> <marker>: a dynotable-lsp that prints its version, else the marker and args.
fake() {
  mkdir -p "$1"
  cat >"$1/dynotable-lsp" <<EOF
#!/bin/sh
if [ "\$1" = --version ]; then echo $2; exit 0; fi
echo $3 "\$@"
EOF
  chmod +x "$1/dynotable-lsp"
}

# check <name> <home> <path> <expected stdout> <expected exit>
check() {
  local out status
  out=$(HOME="$2" PATH="$3" sh -c "$command" 2>&1)
  status=$?
  if [ "$out" = "$4" ] && [ "$status" = "$5" ]; then
    pass "$1"
  else
    fail "$1: got exit $status and output '$out', expected exit $5 and '$4'"
  fi
}

case_dir() {
  mkdir -p "$tmp/$1/home" "$tmp/$1/bin"
  echo "$tmp/$1"
}

d=$(case_dir a)
fake "$d/bin" 0.1.2 path-copy
check "(a) a 0.1.2 CLI on PATH runs run --zed" "$d/home" "$d/bin:$sh_dir" "path-copy run --zed" 0

for version in 0.1.1 0.0.0-dev; do
  d=$(case_dir "b-$version")
  fake "$d/bin" "$version" path-copy
  check "(b) a $version CLI gets the upgrade hint" "$d/home" "$d/bin:$sh_dir" "$hint" 1
done

d=$(case_dir c)
check "(c) no CLI gets the install hint" "$d/home" "$d/bin:$sh_dir" "$hint" 127

d=$(case_dir d)
fake "$d/home/$mac_bin" 0.1.2 npm-copy
check "(d) the macOS npm copy runs when PATH has none" "$d/home" "$d/bin:$sh_dir" "npm-copy run --zed" 0

d=$(case_dir linux)
fake "$d/home/$linux_bin" 0.1.2 npm-copy
check "the Linux npm copy runs when PATH has none" "$d/home" "$d/bin:$sh_dir" "npm-copy run --zed" 0

d=$(case_dir e)
fake "$d/bin" 0.1.2 path-copy
fake "$d/home/$mac_bin" 0.1.1 npm-copy
check "(e) the PATH CLI wins over an older npm copy" "$d/home" "$d/bin:$sh_dir" "path-copy run --zed" 0

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
