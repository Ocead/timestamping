#!/usr/bin/env bash

function echo_error() {
	echo >&2 -e "[\e[0;31mERROR\e[0m]: $1"
}

function verify_actual() {
	git checkout "master"
	! test -d rfc3161 || echo_error "rfc3161/ should not exist."
	! test -f .diff || echo_error ".diff should not exist."
	test -f a.txt || echo_error "a.txt should exist."

	if git rev-parse --verify "sig/master" 2>/dev/null; then
		git checkout "sig/master"
		test -d rfc3161/ || echo_error "rfc3161/ should exist."
		! test -f a.txt 2>/dev/null || echo_error "a.txt should not exist."
	fi
}

# Install to empty repository
echo -e "[\e[0;32mTEST\e[0m]: Install to empty repository"
REPO_PATH="./test/target/empty"
mkdir -p "${REPO_PATH}"
git --git-dir="${REPO_PATH}/.git" init
(
	echo ""
)
./config.sh -d "${REPO_PATH}"
(
	cd "${REPO_PATH}" || exit 255
	echo "Gnampf" >"./a.txt"
	git add "./a.txt"
	git commit -m "Initial commit"

	verify_actual
)
echo ""

# Install to filled unstaged repository
echo -e "[\e[0;32mTEST\e[0m]: Install to filled unstaged repository"
REPO_PATH="./test/target/unstaged"
mkdir -p "${REPO_PATH}"
git --git-dir="${REPO_PATH}/.git" init
(
	cd "${REPO_PATH}" || exit 255
	echo "Gnampf" >"./a.txt"
)
./config.sh --default "${REPO_PATH}"
(
	cd "${REPO_PATH}" || exit 255
	git add "./a.txt"
	git commit -m "Initial commit"

	verify_actual
)
echo ""

# Install to filled uncommitted repository
echo -e "[\e[0;32mTEST\e[0m]: Install to filled uncommitted repository"
REPO_PATH="./test/target/uncommitted"
mkdir -p "${REPO_PATH}"
git --git-dir="${REPO_PATH}/.git" init
(
	cd "${REPO_PATH}" || exit 255
	echo "Gnampf" >"./a.txt"
	git add "./a.txt"
)
./config.sh -d "${REPO_PATH}"
(
	cd "${REPO_PATH}" || exit 255
	git commit -m "Initial commit"

	verify_actual
)
echo ""

# Install to filled committed repository
echo -e "[\e[0;32mTEST\e[0m]: Install to filled committed repository"
REPO_PATH="./test/target/committed"
mkdir -p "${REPO_PATH}"
git --git-dir="${REPO_PATH}/.git" init
(
	cd "${REPO_PATH}" || exit 255
	echo "Gnampf" >"./a.txt"
	git add "./a.txt"
	git commit -m "Initial commit"
)
./config.sh --default "${REPO_PATH}"
(
	cd "${REPO_PATH}" || exit 255

	verify_actual
)
echo ""

# Install to filled staged repository
echo -e "[\e[0;32mTEST\e[0m]: Install to filled staged repository"
REPO_PATH="./test/target/staged"
mkdir -p "${REPO_PATH}"
git --git-dir="${REPO_PATH}/.git" init
(
	cd "${REPO_PATH}" || exit 255
	echo "Gnampf" >"./a.txt"
	git add "./a.txt"
	git commit -m "Initial commit"
	echo "Schnampf" >"./b.txt"
	git add "./b.txt"
)
./config.sh --default "${REPO_PATH}"
(
	cd "${REPO_PATH}" || exit 255

	verify_actual
	test -f b.txt || echo_error "a.txt should exist."
)
echo ""
