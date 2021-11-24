#!/usr/bin/env bash

# Echos with marking
function script_echo() {
	local TAG="config.sh"
	echo -e "[\e[0;32m${TAG}\e[0m]: $1"
}

# Prints help
function print_help() {
	# Print help
	echo "$(basename "$0") [<OPTIONS>] <PATH>
Installs automated timestamping into a git repository

Options:
    -d, --default install with default options
    -h, --help    show this help text"
}

# Prompts all git config options
function prompt_options() {
	read -r -p "Enter the branch prefix [sig]: " TS_BRANCH_PREFIX
	read -r -p "Enter the commit prefix [Timestamp for: ]: " TS_COMMIT_PREFIX
	read -r -p "Enter the commit options []: " COMMIT_OPTIONS

	read -r -p "Enter the diff notice [Written by $(git config --get user.name)]: " TS_DIFF_NOTICE
	read -r -p "Enter the diff file name [.diff]: " TS_DIFF_FILE
	read -r -p "Enter the diff type [staged]: " TS_DIFF_TYPE

	read -r -p "Enter the TSA configuration directory name [rfc3161]: " TS_SERVER_DIRECTORY
	read -r -p "Enter the TSA keychain file name [cacert.pem]: " TS_SERVER_CERTIFICATE
	read -r -p "Enter the TSA url file name [url]: " TS_SERVER_URL

	read -r -p "Enter the timestamp request file name [request.tsq]: " TS_REQUEST_FILE
	read -r -p "Enter the timestamp request options [-cert -sha256 -no_nonce]: " TS_REQUEST_OPTIONS

	read -r -p "Enter the timestamp response file name [response.tsr]: " TS_RESPONSE_FILE
	read -r -p "Enter the timestamp response options []: " TS_RESPONSE_OPTIONS
	read -r -p "Enter whether timestamps should be verified [true]: " TS_RESPONSE_VERIFY

	read -r -p "Enter whether timestamps should be withheld from remotes [false]: " TS_PUSH_WITHHOLD
}

# Sets all git config options
function set_options() {
	git config ts.enabled "true"

	git config ts.branch.prefix "${TS_BRANCH_PREFIX:-"sig"}"
	git config ts.commit.prefix "${TS_COMMIT_PREFIX:-"Timestamp for: "}"
	git config ts.commit.options "${COMMIT_OPTIONS:-""}"

	git config ts.diff.notice "${TS_DIFF_NOTICE:-"Written by $(git config --get user.name)"}"
	git config ts.diff.file "${TS_DIFF_FILE:-".diff"}"
	git config ts.diff.type "${TS_DIFF_TYPE:-"staged"}"

	git config ts.server.directory "${TS_SERVER_DIRECTORY:-"rfc3161"}"
	git config ts.server.certificate "${TS_SERVER_CERTIFICATE:-"cacert.pem"}"
	git config ts.server.url "${TS_SERVER_URL:-"url"}"

	git config ts.request.file "${TS_REQUEST_FILE:-"request.tsq"}"
	git config ts.request.options "${TS_REQUEST_OPTIONS:-"-cert -sha256 -no_nonce"}"

	git config ts.respone.file "${TS_RESPONSE_FILE:-"response.tsr"}"
	git config ts.respone.options "${TS_RESPONSE_OPTIONS:-""}"
	git config ts.respone.verify "${TS_RESPONSE_VERIFY:-"true"}"

	git config ts.push.withhold "${TS_PUSH_WITHHOLD:-"true"}"
}

# Copy the hooks into the repository
function copy_hooks() {
	local REPO_PATH=$1
	local FILES=("commit-msg" "post-commit" "timestamping.sh")
	for f in "${FILES[@]}"; do
		[[ ! -f "${REPO_PATH}/${f}" ]] || {
			script_echo "ERROR: Could not copy the required files"
			exit 4
		}
	done
	cp ./hooks/* "${REPO_PATH}/.git/hooks/" >/dev/null || {
		script_echo "ERROR: Could not copy the required files"
		exit 3
	}
}

function add_to_gitattributes() {
	local LINE=$1
	if ! grep -q -F -x "${LINE}" .gitattributes >/dev/null 2>/dev/null; then
		echo "${LINE}" >>.gitattributes
	fi
}

# Create initial timestamping objects
function configure_repo() {
	# Get currently checked out branch
	if ! BRANCH=$(git symbolic-ref --short HEAD); then
		if ! BRANCH=$(git config init.defaultBranch); then
			BRANCH="master"
		fi
	fi

	# Stash staged changed
	! git rev-parse HEAD >/dev/null 2>/dev/null || git stash >/dev/null 2>/dev/null

	# Checkout root signing branch
	git checkout --orphan "$(git config --get ts.branch.prefix)-" >/dev/null 2>/dev/null

	# Create initial commit in root signing branch
	TS_SERVER_DIRECTORY=$(git config --get ts.server.directory)
	mkdir -p "./${TS_SERVER_DIRECTORY}"
	echo "Place your TSA configuration in this directory." >"./${TS_SERVER_DIRECTORY}/PLACE_TSA_CONFIGS_HERE"
	add_to_gitattributes "*.diff binary"
	add_to_gitattributes "*.tsq binary"
	add_to_gitattributes "*.tsr binary"
	git add "./${TS_SERVER_DIRECTORY}/PLACE_TSA_CONFIGS_HERE" >/dev/null 2>/dev/null
	git add "./.gitattributes" >/dev/null 2>/dev/null
	git commit -m "Initial timestamping commit" -- "./.gitattributes" "./${TS_SERVER_DIRECTORY}/PLACE_TSA_CONFIGS_HERE" >/dev/null 2>/dev/null

	# Return to previous branch
	if git rev-parse --verify "${BRANCH}" >/dev/null 2>/dev/null; then
		git checkout "${BRANCH}" >/dev/null 2>/dev/null
	else
		git checkout --orphan "${BRANCH}" >/dev/null 2>/dev/null
		# Remove timestamping files
		git rm -rf -- "./${TS_SERVER_DIRECTORY}/PLACE_TSA_CONFIGS_HERE" "./.gitattributes" >/dev/null 2>/dev/null
	fi

	# Pop stashed changes
	if git rev-parse HEAD >/dev/null 2>/dev/null; then
		git stash pop >/dev/null 2>/dev/null
	else
		# Remove timestamping files
		rm -rf "./${TS_SERVER_DIRECTORY}/" "./.gitattributes" >/dev/null 2>/dev/null
	fi
}

# Install automated timestamping to target repository
function install_timestamping() {
	local REPO_PATH=$1

	local TS_BRANCH_PREFIX
	local TS_COMMIT_PREFIX
	local COMMIT_OPTIONS

	local TS_DIFF_NOTICE
	local TS_DIFF_FILE
	local TS_DIFF_TYPE

	local TS_SERVER_DIRECTORY
	local TS_SERVER_CERTIFICATE
	local TS_SERVER_URL

	local TS_REQUEST_FILE
	local TS_REQUEST_OPTIONS

	local TS_RESPONSE_FILE
	local TS_RESPONSE_OPTIONS
	local TS_RESPONSE_VERIFY

	copy_hooks "${REPO_PATH}"

	(
		cd "${REPO_PATH}" || {
			script_echo "ERROR: Could not enter the specified directory"
			exit 2
		}

		if ! [[ -d ".git" ]]; then
			script_echo "ERROR: Specified directory is not a git repository"
			exit 1
		fi

		if ! git diff --exit-code >/dev/null 2>/dev/null; then
			git status
			script_echo "ERROR: You have local uncommitted changes. Please commit or reset them before installing."
		fi

		if [[ ${OPT_DEFAULT} == false ]]; then
			prompt_options
		fi

		set_options

		configure_repo
	)
}

# Short options
for arg in "$@"; do
	shift
	case "${arg}" in
	"--default") set -- "$@" "-d" ;;
	"--help") set -- "$@" "-h" ;;
	*) set -- "$@" "${arg}" ;;
	esac
done

OPT_DEFAULT=false

# Parse options
OPTIND=1
while getopts "dh" opt; do
	case "${opt}" in
	"d")
		OPT_DEFAULT=true
		;;
	"h")
		print_help
		exit 0
		;;
	"?")
		print_help
		exit 4
		;;
	esac
done
shift $((OPTIND - 1))

if [ $# -eq 0 ]; then
	print_help
	exit 4
fi

install_timestamping "$1"

exit 0
