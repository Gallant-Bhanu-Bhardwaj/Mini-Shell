#!/usr/bin/env bash
# ─────────────────────────────────────────────────
#  test_shell.sh  —  Automated tests for minish
#  Usage: bash test_shell.sh
# ─────────────────────────────────────────────────

SHELL_BIN="./minish"
PASS=0; FAIL=0

RED='\033[1;31m'; GREEN='\033[1;32m'; NC='\033[0m'

run_test() {
    local desc="$1"
    local input="$2"
    local expected="$3"
    local actual
    actual=$(echo -e "$input" | $SHELL_BIN 2>/dev/null | grep -v "^minish" | grep -v "^╔\|^║\|^╚")
    if echo "$actual" | grep -qF "$expected"; then
        printf "${GREEN}[PASS]${NC} %s\n" "$desc"
        ((PASS++))
    else
        printf "${RED}[FAIL]${NC} %s\n  Expected: %s\n  Got:      %s\n" \
               "$desc" "$expected" "$actual"
        ((FAIL++))
    fi
}

echo "═══════════════════════════════════════════"
echo " Mini Shell Test Suite"
echo "═══════════════════════════════════════════"

# ── 1. Basic command ──────────────────────────────
run_test "echo command"         "echo hello world\nexit" "hello world"

# ── 2. cd + pwd ───────────────────────────────────
run_test "cd to /tmp"           "cd /tmp\npwd\nexit"     "/tmp"

# ── 3. Output redirection (>) ─────────────────────
TMP_OUT=$(mktemp)
echo -e "echo redirection_test > $TMP_OUT\nexit" | $SHELL_BIN >/dev/null 2>&1
if grep -q "redirection_test" "$TMP_OUT"; then
    printf "${GREEN}[PASS]${NC} output redirect >\n"; ((PASS++))
else
    printf "${RED}[FAIL]${NC} output redirect >\n"; ((FAIL++))
fi
rm -f "$TMP_OUT"

# ── 4. Append redirection (>>) ────────────────────
TMP_OUT=$(mktemp)
{
  echo -e "echo line1 > $TMP_OUT\necho line2 >> $TMP_OUT\nexit" | $SHELL_BIN >/dev/null 2>&1
}
LINE_COUNT=$(wc -l < "$TMP_OUT")
if [ "$LINE_COUNT" -eq 2 ]; then
    printf "${GREEN}[PASS]${NC} append redirect >>\n"; ((PASS++))
else
    printf "${RED}[FAIL]${NC} append redirect >> (expected 2 lines, got %s)\n" "$LINE_COUNT"; ((FAIL++))
fi
rm -f "$TMP_OUT"

# ── 5. Input redirection (<) ──────────────────────
TMP_IN=$(mktemp); echo "input_redirect_works" > "$TMP_IN"
run_test "input redirect <"     "cat < $TMP_IN\nexit"    "input_redirect_works"
rm -f "$TMP_IN"

# ── 6. Single pipe ────────────────────────────────
run_test "pipe echo|grep"       "echo foo bar | grep foo\nexit" "foo"

# ── 7. Multi-stage pipe ───────────────────────────
actual=$(printf 'echo one two three | tr " " "\\n" | grep two\nexit\n' | $SHELL_BIN 2>/dev/null | grep -v "^minish\|^╔\|^║\|^╚")
if echo "$actual" | grep -q "two"; then
    printf "${GREEN}[PASS]${NC} pipe 3 stages\n"; ((PASS++))
else
    printf "${RED}[FAIL]${NC} pipe 3 stages (got: %s)\n" "$actual"; ((FAIL++))
fi

# ── 8. Background job ─────────────────────────────
actual=$(echo -e "sleep 1 &\njobs\nexit" | $SHELL_BIN 2>/dev/null | grep -v "^minish\|^╔\|^║\|^╚")
if echo "$actual" | grep -qE "\[1\]|Running"; then
    printf "${GREEN}[PASS]${NC} background job + jobs\n"; ((PASS++))
else
    printf "${RED}[FAIL]${NC} background job + jobs (got: %s)\n" "$actual"; ((FAIL++))
fi

# ── 9. help built-in ──────────────────────────────
run_test "help command"         "help\nexit"            "Built-in commands"

# ── 10. Unknown command error ─────────────────────
actual=$(echo -e "__no_such_cmd__\nexit" | $SHELL_BIN 2>&1 | grep "not found")
if [ -n "$actual" ]; then
    printf "${GREEN}[PASS]${NC} unknown command error\n"; ((PASS++))
else
    printf "${RED}[FAIL]${NC} unknown command error\n"; ((FAIL++))
fi

echo "═══════════════════════════════════════════"
printf " Results: ${GREEN}%d passed${NC}  ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
echo "═══════════════════════════════════════════"
[ $FAIL -eq 0 ] && exit 0 || exit 1