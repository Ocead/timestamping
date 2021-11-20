#!/usr/bin/env bash

# Print an error
function echo_error() {
	echo >&2 -e "[\e[0;31mERROR\e[0m]: $1"
	exit 254
}

# Adds a TSA configuration to the repository
function add_tsa() {
	git checkout "sig-"
	mkdir "./rfc3161/zeitstempel.dfn.de"
	curl "https://pki.pca.dfn.de/dfn-ca-global-g2/pub/cacert/chain.txt" -o "./rfc3161/zeitstempel.dfn.de/cacert.pem"
	git add "./rfc3161/zeitstempel.dfn.de/cacert.pem"
	git commit -m "Added simple TSA" "./rfc3161/zeitstempel.dfn.de/cacert.pem"

	# Checkout original branch
  if git rev-parse --verify "master" >/dev/null 2>/dev/null; then
  	git checkout "master" >/dev/null 2>/dev/null
  else
  	git checkout --orphan "master" >/dev/null 2>/dev/null
  	git rm -rf ./rfc3161/* >/dev/null 2>/dev/null
  fi
}

# Verifies the repository after first actual commit
function verify_first() {
	git checkout "master" >/dev/null 2>/dev/null
	! test -d rfc3161 || echo_error "rfc3161/ should not exist."
	! test -f .diff || echo_error ".diff should not exist."
	test -f a.txt || echo_error "a.txt should exist."

	if git rev-parse --verify "sig/master" >/dev/null 2>/dev/null; then
		git checkout "sig/master" >/dev/null 2>/dev/null
		test -d rfc3161/ || echo_error "rfc3161/ should exist."
		! test -f a.txt 2>/dev/null || echo_error "a.txt should not exist."
	fi

	git checkout "master" >/dev/null 2>/dev/null
}

# Verifies the repository after second actual commit
function verify_second() {
	git checkout "master" >/dev/null 2>/dev/null
	! test -d rfc3161 || echo_error "rfc3161/ should not exist."
	! test -f .diff || echo_error ".diff should not exist."
	test -f a.txt || echo_error "a.txt should exist."
	test -f b.txt || echo_error "b.txt should exist."

	if git rev-parse --verify "sig/master" >/dev/null 2>/dev/null; then
		git checkout "sig/master" >/dev/null 2>/dev/null
		test -d rfc3161/ || echo_error "rfc3161/ should exist."
		! test -f a.txt 2>/dev/null || echo_error "a.txt should not exist."
		! test -f b.txt 2>/dev/null || echo_error "b.txt should not exist."
	fi

	git checkout "master" >/dev/null 2>/dev/null
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
	add_tsa
	echo "Gnampf" >"./a.txt"
	git add "./a.txt" >/dev/null 2>/dev/null
	git commit -m "Initial commit"

	verify_first

	echo "Schnampf" >"./b.txt"
	git add "./b.txt" >/dev/null 2>/dev/null
	git commit -m "Second commit"

	verify_second
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
	add_tsa
	git add "./a.txt"
	git commit -m "Initial commit"

	verify_first

	echo "Schnampf" >"./b.txt"
	git add "./b.txt"
	git commit -m "Second commit"

	verify_second
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
	add_tsa
	git commit -m "Initial commit"

	verify_first

	echo "Schnampf" >"./b.txt"
	git add "./b.txt"
	git commit -m "Second commit"

	verify_second
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
	add_tsa

	verify_first

	echo "Schnampf" >"./b.txt"
	git add "./b.txt"
	git commit -m "Second commit"

	verify_second
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
	add_tsa

	verify_first
	test -f b.txt || echo_error "b.txt should exist."



	echo "Schnampf" >"./b.txt"
	git add "./b.txt"
	git commit -m "Second commit"

	verify_second
)
echo ""
