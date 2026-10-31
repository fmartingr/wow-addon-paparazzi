#!/usr/bin/env bash
# Tests the release targets of the Makefile in a temporary git repository with a bare origin.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

git init -q --bare -b main "$tmp/origin.git"
git init -q -b main "$tmp/work"
cd "$tmp/work"
git remote add origin "$tmp/origin.git"
cp "$root/Makefile" .
git add Makefile
git commit -q -m "chore: initial"
git push -q origin main

release() {
	make -s "$@" 2>&1
}

expect_output() {
	local want="$1"
	shift
	local out
	out="$(release "$@")" || fail "make $* exited with an error: $out"
	[[ "$out" == *"$want"* ]] || fail "make $*: expected '$want', got '$out'"
}

expect_failure() {
	local why="$1"
	shift
	if release "$@" >/dev/null; then
		fail "make $* should fail: $why"
	fi
}

remote_has_tag() {
	git ls-remote --tags origin "refs/tags/$1" | grep -q "$1"
}

expect_output "v0.0.0 -> v0.0.1" release-patch DRY_RUN=1
remote_has_tag v0.0.1 && fail "a dry run pushed a tag"
git rev-parse -q --verify refs/tags/v0.0.1 >/dev/null && fail "a dry run created a tag"

expect_output "v0.0.0 -> v0.0.1" release-patch
remote_has_tag v0.0.1 || fail "v0.0.1 is not on the remote"
[[ "$(git cat-file -t v0.0.1)" == "tag" ]] || fail "v0.0.1 is not an annotated tag"

expect_output "v0.0.1 -> v0.1.0" release-minor
remote_has_tag v0.1.0 || fail "v0.1.0 is not on the remote"

expect_output "v0.1.0 -> v1.0.0" release-major
remote_has_tag v1.0.0 || fail "v1.0.0 is not on the remote"

git tag -a v1.1.0-beta1 -m beta
expect_output "v1.0.0 -> v1.0.1" release-patch DRY_RUN=1

echo dirty >>Makefile
expect_failure "dirty tree" release-patch
git checkout -q Makefile

git checkout -q -b feature
expect_failure "wrong branch" release-patch
git checkout -q main

git clone -q "$tmp/origin.git" "$tmp/other"
(
	cd "$tmp/other"
	git checkout -q main
	echo change >change.txt
	git add change.txt
	git commit -q -m "chore: change"
	git push -q origin main
)
expect_failure "branch behind the remote" release-patch

git pull -q --ff-only origin main
echo local >local.txt
git add local.txt
git commit -q -m "chore: local"
expect_failure "branch ahead of the remote" release-patch

echo "release tests passed"
