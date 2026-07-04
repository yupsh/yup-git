#!/bin/sh
# Integration checks for yup-git, run inside a Debian container with real `git`.
#
# yup-git wraps real git: it forks `git`, drains stdin, forwards the argument
# vector, and streams git's stdout onward. BUT it is NOT a transparent
# passthrough. The wrapper is a urfave/cli root command with no registered
# subcommands, so cli parses the WHOLE argument vector for the root command and
# rejects any unknown `-flag`/`--flag` token — even one that follows the git
# subcommand. Only flag-free invocations reach git; `--version` is intercepted
# by the wrapper's own version flag; a bare invocation is rejected up front.
# (See gloo-foo/cmd-git/COMPATIBILITY.md.) The harness is therefore split:
#
#   parity DESC OURS GNU  — a flag-free git operation forwarded by yup-git must
#                           be byte-identical to running it under real git.
#   assert WANT DESC CMD… — exact output, for fixed values and for the wrapper's
#                           own divergent front-matter (--version, ErrNoArgs,
#                           and the rejection of flag tokens).
#
# Every yup-git call redirects stdin from /dev/null: the wrapper reads stdin to
# completion before forking git, so an open stdin would block. Git identity and
# dates are pinned and global/system config is voided, so output is reproducible.
set -eu

export GIT_AUTHOR_NAME='Y' GIT_AUTHOR_EMAIL='y@y' \
	GIT_COMMITTER_NAME='Y' GIT_COMMITTER_EMAIL='y@y' \
	GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' \
	GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
	GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

fails=0

parity() {
	if [ "$2" = "$3" ]; then
		printf 'ok    parity  %s\n' "$1"
	else
		printf 'FAIL  parity  %s\n        gnu:  %s\n        ours: %s\n' "$1" "$3" "$2"
		fails=$((fails + 1))
	fi
}

assert() {
	want=$1
	desc=$2
	shift 2
	got=$("$@" 2>/dev/null </dev/null || true)
	if [ "$got" = "$want" ]; then
		printf 'ok    assert  %s\n' "$desc"
	else
		printf 'FAIL  assert  %s\n        want: %s\n        got:  %s\n' "$desc" "$want" "$got"
		fails=$((fails + 1))
	fi
}

# repo DIR BIN — a clean repo at DIR with a fixed initial branch (uses real git
# so setup never depends on the wrapper under test).
repo() {
	rm -rf "$1"
	mkdir -p "$1"
	git -C "$1" init -q -b main
}

# --- Passthrough parity: flag-free operations match real git exactly. ---

# `git version` (subcommand form, no flags): forwarded to git, reports git's own.
parity 'version' \
	"$(yup-git version </dev/null)" \
	"$(git version)"

# `git status` on a clean repo: forwarded verbatim, identical output.
repo /tmp/clean_ours
repo /tmp/clean_gnu
parity 'status (clean repo)' \
	"$(cd /tmp/clean_ours && yup-git status </dev/null)" \
	"$(cd /tmp/clean_gnu && git status)"

# `git hash-object <file>` (path operand, no --stdin): content-addressed and
# deterministic; the SHA-1 proves the operand and working dir are forwarded.
repo /tmp/ho_ours; printf 'content\n' >/tmp/ho_ours/f.txt
repo /tmp/ho_gnu; printf 'content\n' >/tmp/ho_gnu/f.txt
parity 'hash-object f.txt' \
	"$(cd /tmp/ho_ours && yup-git hash-object f.txt </dev/null)" \
	"$(cd /tmp/ho_gnu && git hash-object f.txt)"

# `git add f.txt` + `git write-tree`: a flag-free staging sequence. The tree
# SHA-1 is deterministic and must match real git's.
repo /tmp/wt_ours; printf 'content\n' >/tmp/wt_ours/f.txt
repo /tmp/wt_gnu; printf 'content\n' >/tmp/wt_gnu/f.txt
(cd /tmp/wt_ours && yup-git add f.txt </dev/null)
(cd /tmp/wt_gnu && git add f.txt)
parity 'write-tree (after add f.txt)' \
	"$(cd /tmp/wt_ours && yup-git write-tree </dev/null)" \
	"$(cd /tmp/wt_gnu && git write-tree)"

# --- Fixed-value assertion. ---

# The SHA-1 of the "content\n" blob is reproducible; assert it exactly so the
# parity above is anchored to a known value, not just self-agreement.
assert 'd95f3ad14dee633a758d2e331151e950dd13e4ed' \
	'hash-object f.txt == known blob SHA' \
	sh -c 'cd /tmp/ho_ours && yup-git hash-object f.txt'

# --- Wrapper front-matter & divergences (yup-git's own behavior). ---

# `--version`: intercepted by the wrapper's own version flag (the init override),
# so it prints the WRAPPER's "git version <ver>", not git's. The container builds
# with the default version "dev".
assert 'git version dev' \
	'--version prints the wrapper version (not git'\''s)' \
	yup-git --version

# No subcommand: rejected with the ErrNoArgs sentinel, "git:"-prefixed, exit 1 —
# it never reaches real git.
err=$(yup-git </dev/null 2>&1 >/dev/null || true)
yup-git </dev/null >/dev/null 2>&1 && code=0 || code=$?
if [ "$code" = '1' ] && printf '%s' "$err" | grep -q 'git: no git subcommand given'; then
	printf 'ok    assert  no subcommand -> ErrNoArgs, exit 1\n'
else
	printf 'FAIL  assert  no subcommand\n        code: %s\n        err:  %s\n' "$code" "$err"
	fails=$((fails + 1))
fi

# DIVERGENCE: a flag token after the subcommand is parsed by urfave/cli (not git)
# and rejected, so flag-bearing git invocations DO NOT pass through. yup-git
# exits 1 with "flag provided but not defined", real git would print porcelain
# status. This is the wrapper's defining limitation.
err=$(cd /tmp/clean_ours && yup-git status --porcelain </dev/null 2>&1 >/dev/null || true)
(cd /tmp/clean_ours && yup-git status --porcelain </dev/null >/dev/null 2>&1) && code=0 || code=$?
if [ "$code" = '1' ] && printf '%s' "$err" | grep -q 'flag provided but not defined'; then
	printf 'ok    assert  flag after subcommand is rejected (no passthrough)\n'
else
	printf 'FAIL  assert  flag rejection\n        code: %s\n        err:  %s\n' "$code" "$err"
	fails=$((fails + 1))
fi

if [ "$fails" -ne 0 ]; then
	printf '\n%s check(s) failed\n' "$fails"
	exit 1
fi
printf '\nall checks passed\n'
