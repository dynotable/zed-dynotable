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

# sh, not the user's shell (fish has another syntax); the edits that the user sees; .dynotable.json of the project.
if jq -e '.[0].shell.program == "sh" and .[0].save == "current" and .[0].cwd == "$ZED_WORKTREE_ROOT"' "$sql_tasks" >/dev/null; then
  pass "the task runs under sh, saves the file and runs in the worktree root"
else
  fail "the task must have shell.program sh, save current and cwd \$ZED_WORKTREE_ROOT"
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
# The system folders can hold node. The task must not need it, so the cases get sh and nothing else.
sh_dir="$tmp/sys"
mkdir -p "$sh_dir"
ln -s "$(command -v sh)" "$sh_dir/sh"
mac_bin='Library/Application Support/Zed/extensions/work/dynotable/node_modules/.bin'
linux_bin='.local/share/zed/extensions/work/dynotable/node_modules/.bin'

# fake <dir> <version> <marker> [<shebang>]: a dynotable-lsp that prints its version, else the
# marker and args. An empty version prints nothing and exits 1, as a broken install does.
fake() {
  mkdir -p "$1"
  cat >"$1/dynotable-lsp" <<EOF
${4:-#!/bin/sh}
if [ "\$1" = --version ]; then [ -n "$2" ] || exit 1; echo $2; exit 0; fi
echo $3 "\$@"
EOF
  chmod +x "$1/dynotable-lsp"
}

# The npm copy is a Node.js script.
node_shebang='#!/usr/bin/env node'

# fake_node <dir>: a node that runs the script it gets with sh.
fake_node() {
  mkdir -p "$1"
  printf '#!/bin/sh\nexec sh "$@"\n' >"$1/node"
  chmod +x "$1/node"
}

# check <name> <home> <path> <expected stdout> <expected exit> [<stderr target>]
check() {
  local out status
  out=$(HOME="$2" PATH="$3" sh -c "$command" 2>"${6:-/dev/stdout}")
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

for version in 0.1.0 0.1.1 0.0.0-dev; do
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

version_hint='Run could not get the version of dynotable-lsp. Install Node.js 18 or later, or run: npm install -g dynotable-cli'

d=$(case_dir f)
fake "$d/bin" "" path-copy
check "(f) a CLI that prints no version gets the version hint" "$d/home" "$d/bin:$sh_dir" "$version_hint" 1

if PATH="$sh_dir" command -v node >/dev/null 2>&1; then
  fail "the test PATH holds node"
fi

# The stderr of env differs between macOS and Linux, so these cases compare stdout only.
d=$(case_dir g)
fake "$d/home/$mac_bin" 0.1.2 npm-copy "$node_shebang"
check "(g) the npm copy with no node gets the version hint" "$d/home" "$d/bin:$sh_dir" "$version_hint" 1 /dev/null

d=$(case_dir h)
fake "$d/home/$mac_bin" 0.1.2 npm-copy "$node_shebang"
fake_node "$d/home/Library/Application Support/Zed/node/node-v22.5.1-darwin-arm64/bin"
check "(h) the npm copy runs with the node of Zed on macOS" "$d/home" "$d/bin:$sh_dir" "npm-copy run --zed" 0 /dev/null

d=$(case_dir i)
fake "$d/home/$linux_bin" 0.1.2 npm-copy "$node_shebang"
fake_node "$d/home/.local/share/zed/node/node-v22.5.1-linux-x64/bin"
check "(i) the npm copy runs with the node of Zed on Linux" "$d/home" "$d/bin:$sh_dir" "npm-copy run --zed" 0 /dev/null

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
