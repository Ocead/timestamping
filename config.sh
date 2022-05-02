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
    -f, --force   don't check files when copying/deleting
    -h, --help    show this help text
    -r, --remove  removes automated timestamping, but keeps the generated timestamps
    -p, --purge   removes automated timestamping and the generated timestamps"
}

# Prompts all git config options
function prompt_options() {
	read -r -p "Enter the branch prefix [sig]: " TS_BRANCH_PREFIX
	read -r -p "Enter how remote and local signing branches should be managed [merge]: " TS_BRANCH_REMOTE
	read -r -p "Enter whether timestamps should be withheld from remotes [false]: " TS_BRANCH_WITHHOLD

	read -r -p "Enter the commit prefix [Timestamp for: ]: " TS_COMMIT_PREFIX
	read -r -p "Enter the commit options []: " TS_COMMIT_OPTIONS
	read -r -p "Enter whether timestamp commits should be related to actual [true]: " TS_COMMIT_RELATE

	read -r -p "Enter the diff notice [Written by $(git config --get user.name)]: " TS_DIFF_NOTICE
	read -r -p "Enter the diff file name [.diff]: " TS_DIFF_FILE
	read -r -p "Enter the diff type [staged]: " TS_DIFF_TYPE

	read -r -p "Enter the TSA configuration directory name [rfc3161]: " TS_SERVER_DIRECTORY
	read -r -p "Enter the TSA certificate bundle file name [cacert.pem]: " TS_SERVER_CERTIFICATE
	read -r -p "Enter the TSA url file name [url]: " TS_SERVER_URL
	read -r -p "Enter whether existing timestamp should be updated on TSA config changes [true]: " TS_SERVER_UPDATE

	read -r -p "Enter the timestamp request file name [request.tsq]: " TS_REQUEST_FILE
	read -r -p "Enter the timestamp request options [-cert -sha256 -no_nonce]: " TS_REQUEST_OPTIONS

	read -r -p "Enter the timestamp response file name [response.tsr]: " TS_RESPONSE_FILE
	read -r -p "Enter the timestamp response options []: " TS_RESPONSE_OPTIONS
	read -r -p "Enter whether timestamps should be verified [true]: " TS_RESPONSE_VERIFY
}

# Sets all git config options
function set_options() {
	git config ts.enabled "true"

	git config --local ts.branch.prefix "${TS_BRANCH_PREFIX:-"sig"}"
	git config --local ts.branch.remote "${TS_BRANCH_REMOTE:-"merge"}"
	git config --local ts.branch.withhold "${TS_BRANCH_WITHHOLD:-"false"}"

	git config --local ts.commit.prefix "${TS_COMMIT_PREFIX:-"Timestamp for: "}"
	git config --local ts.commit.options "${TS_COMMIT_OPTIONS:-""}"
	git config --local ts.commit.relate "${TS_COMMIT_RELATE:-""true}"

	git config --local ts.diff.notice "${TS_DIFF_NOTICE:-"Written by $(git config --get user.name)"}"
	git config --local ts.diff.file "${TS_DIFF_FILE:-".diff"}"
	git config --local ts.diff.type "${TS_DIFF_TYPE:-"staged"}"

	git config --local ts.server.directory "${TS_SERVER_DIRECTORY:-"rfc3161"}"
	git config --local ts.server.certificate "${TS_SERVER_CERTIFICATE:-"cacert.pem"}"
	git config --local ts.server.url "${TS_SERVER_URL:-"url"}"
	git config --local ts.server.update "${TS_SERVER_UPDATE:-"true"}"

	git config --local ts.request.file "${TS_REQUEST_FILE:-"request.tsq"}"
	git config --local ts.request.options "${TS_REQUEST_OPTIONS:-"-cert -sha256 -no_nonce"}"

	git config --local ts.respone.file "${TS_RESPONSE_FILE:-"response.tsr"}"
	git config --local ts.respone.options "${TS_RESPONSE_OPTIONS:-""}"
	git config --local ts.respone.verify "${TS_RESPONSE_VERIFY:-"true"}"
}

# Copy the hooks into the repository
function copy_hooks() {
	local HOOKS_PATH=$1
	local FILES=("commit-msg" "post-commit" "pre-push" "timestamping.sh")
	for f in "${FILES[@]}"; do
		maybe_copy "./hooks" "${HOOKS_PATH}" "${f}" || {
			script_echo "Could not copy file ${f}"
			exit 4
		}
	done
}

# Copy the hooks from the repository
function remove_hooks() {
	local HOOKS_PATH=$1
	local FILES=("commit-msg" "post-commit" "pre-push" "timestamping.sh")
	for f in "${FILES[@]}"; do
		maybe_remove "./hooks" "${HOOKS_PATH}" "${f}" || {
			script_echo "Could not remove file ${f}"
			exit 4
		}
	done
}

function add_to_gitattributes() {
	local LINE=$1
	touch ".gitattributes"
	if ! grep -q -F "${LINE}" < <(tr -s ' ' <.gitattributes); then
		echo "${LINE}" >>.gitattributes
	fi
}

function file_is_also_object() {
	local FILE_PATH=$1
	local FILE_HASH
	if FILE_HASH=$(git hash-object "${FILE_PATH}"); then
		git show "${FILE_HASH}" 2>/dev/null | diff --strip-trailing-cr "${FILE_PATH}" - >/dev/null 2>/dev/null
		return $?
	else
		return 1
	fi
}

function files_are_same() {
	local LHP=$1
	local RHP=$2

	if [[ -f ${LHP} && -f ${RHP} ]]; then
		local LHH
		local RHH
		LHH=$(git hash-object "${LHP}")
		RHH=$(git hash-object "${RHP}")
		test "${LHH}" == "${RHH}" || diff --strip-trailing-cr "${LHP}" "${RHP}" >/dev/null 2>/dev/null
		return $?
	else
		return 1
	fi
}

function maybe_copy() {
	local LOCAL_PATH=$1
	local REPO_PATH=$2
	local FILE=$3
	local LHP="${LOCAL_PATH}/${FILE}"
	local RHP="${REPO_PATH}/${FILE}"

	if [[ ! -f "${RHP}" || ${OPT_FORCE} == "true" ]]; then
		cp "${LHP}" "${RHP}"
	elif [[ -d .git ]]; then
		file_is_also_object "${RHP}" && cp "${LHP}" "${RHP}"
	fi
	return $?
}

function maybe_remove() {
	local LOCAL_PATH=$1
	local REPO_PATH=$2
	local FILE=$3
	local LHP="${LOCAL_PATH}/${FILE}"
	local RHP="${REPO_PATH}/${FILE}"

	if [[ -f "${RHP}" ]]; then
		if [[ -d .git ]] && file_is_also_object "${RHP}" || [[ ${OPT_FORCE} == "true" ]]; then
			rm "${RHP}"
		else
			files_are_same "${LHP}" "${RHP}" && rm "${RHP}"
		fi
	fi
	return $?
}

# Create initial timestamping objects
function configure_repo() {
	local TS_BRANCH_PREFIX
	TS_BRANCH_PREFIX=$(git config --get ts.branch.prefix)
	if git rev-parse --verify "${TS_BRANCH_PREFIX}/root" >/dev/null 2>/dev/null; then
		script_echo "Root signing branch already present"
		return 0
	fi

	# Get currently checked out branch
	if ! BRANCH=$(git symbolic-ref --short HEAD); then
		if ! BRANCH=$(git config init.defaultBranch); then
			BRANCH="master"
		fi
	fi

	# Stash staged changed
	if git rev-parse HEAD >/dev/null 2>/dev/null; then
		if ! git diff-index --quiet HEAD --; then
			script_echo "Stashing changes"
			git stash push >/dev/null 2>/dev/null
			STASHED=$?
		fi
	fi

	# Checkout root signing branch
	script_echo "Checking out root signing branch"
	if ! git checkout "${TS_BRANCH_PREFIX}/root" >/dev/null 2>/dev/null; then
		git checkout --orphan "${TS_BRANCH_PREFIX}/root" >/dev/null 2>/dev/null

		# Create initial commit in root signing branch
		script_echo "Creating TSA config directory"
		TS_SERVER_DIRECTORY=$(git config --get ts.server.directory)
		mkdir -p "./${TS_SERVER_DIRECTORY}"
		echo "Place your TSA configuration in this directory." >"./${TS_SERVER_DIRECTORY}/PLACE_TSA_CONFIGS_HERE"
		add_to_gitattributes "*.diff binary"
		add_to_gitattributes "*.pem binary"
		add_to_gitattributes "*.tsq binary"
		add_to_gitattributes "*.tsr binary"
		add_to_gitattributes "*.sh text eol=lf"
		git add "./${TS_SERVER_DIRECTORY}/PLACE_TSA_CONFIGS_HERE" >/dev/null 2>/dev/null
		git add "./.gitattributes" >/dev/null 2>/dev/null
		git commit -m "Initial timestamping commit" -- "./.gitattributes" "./${TS_SERVER_DIRECTORY}/PLACE_TSA_CONFIGS_HERE" >/dev/null 2>/dev/null
	else
		script_echo "Root signing branch already present"
	fi

	# Return to previous branch
	script_echo "Checking out actual branch"
	git checkout "${BRANCH}" >/dev/null 2>/dev/null || {
		git checkout --orphan "${BRANCH}" >/dev/null 2>/dev/null
		# Remove timestamping files
		git rm -rf -- "./${TS_SERVER_DIRECTORY}/PLACE_TSA_CONFIGS_HERE" "./.gitattributes" >/dev/null 2>/dev/null
	}

	# Pop stashed changes
	if [[ ${STASHED} -eq 0 ]]; then
		script_echo "Unstashing changes"
		git stash pop >/dev/null 2>/dev/null
	else
		# Remove timestamping files
		script_echo "Removing timestamping files"
		rm -rf "./${TS_SERVER_DIRECTORY}/" "./.gitattributes" >/dev/null 2>/dev/null
	fi
}

# Install automated timestamping to target repository
function install_timestamping() {
	local REPO_PATH=$1
	local HOOKS_PATH

	if ! HOOKS_PATH=$(git --git-dir "${REPO_PATH}" config --get core.hooksPath); then
		HOOKS_PATH="${REPO_PATH}/.git/hooks"
	fi

	local TS_BRANCH_PREFIX
	local TS_BRANCH_REMOTE

	local TS_COMMIT_PREFIX
	local TS_COMMIT_OPTIONS
	local TS_COMMIT_RELATE

	local TS_DIFF_NOTICE
	local TS_DIFF_FILE
	local TS_DIFF_TYPE

	local TS_SERVER_DIRECTORY
	local TS_SERVER_CERTIFICATE
	local TS_SERVER_URL
	local TS_SERVER_UPDATE

	local TS_REQUEST_FILE
	local TS_REQUEST_OPTIONS

	local TS_RESPONSE_FILE
	local TS_RESPONSE_OPTIONS
	local TS_RESPONSE_VERIFY

	copy_hooks "${HOOKS_PATH}"

	(
		cd "${REPO_PATH}" || {
			script_echo "ERROR: Could not enter the specified directory"
			exit 2
		}

		if ! [[ -d ".git" ]]; then
			script_echo "ERROR: Specified directory is not a git repository"
			exit 1
		fi

		if [[ ${OPT_DEFAULT} == false ]]; then
			script_echo "Specify options:"
			prompt_options
		else
			script_echo "Assuming default options"
		fi

		script_echo "Setting options for repository"
		set_options

		script_echo "Configuring repository"
		configure_repo

		script_echo "Installation complete."
	)
}

function uninstall_timestamping() {
	local REPO_PATH=$1
	local HOOKS_PATH

	if ! HOOKS_PATH=$(git --git-dir "${REPO_PATH}" config --get core.hooksPath); then
		HOOKS_PATH="${REPO_PATH}/.git/hooks"
	fi

	script_echo "Removing hooks"
	remove_hooks "${HOOKS_PATH}"

	if [[ ${OPT_PURGE} == true ]]; then
		(
			cd "${REPO_PATH}" || {
				script_echo "ERROR: Could not enter the specified directory"
				exit 2
			}

			local TS_BRANCH_PREFIX
			if ! TS_BRANCH_PREFIX=$(git config --get ts.branch.prefix); then
				script_echo "ERROR: Could not get option 'ts.branch.prefix'"
			fi
			local BRANCHES=()
			mapfile -t BRANCHES < <(git branch --list | tr -d ' *')

			for b in "${BRANCHES[@]}"; do
				if [[ ${b} == "${TS_BRANCH_PREFIX}/root" || ${b} == "${TS_BRANCH_PREFIX}/b/"* ]]; then
					script_echo "Removing branch ${b}"
					git branch -D "${b}"
				fi
			done

			git config --unset --local ts.branch.prefix
		)
	fi

	script_echo "Unsetting options"
	git config --unset --local ts.enabled

	git config --unset --local ts.branch.prefix
	git config --unset --local ts.branch.remote
	git config --unset --local ts.branch.withhold

	git config --unset --local ts.commit.prefix
	git config --unset --local ts.commit.options
	git config --unset --local ts.commit.relate

	git config --unset --local ts.diff.notice
	git config --unset --local ts.diff.file
	git config --unset --local ts.diff.type

	git config --unset --local ts.server.directory
	git config --unset --local ts.server.certificate
	git config --unset --local ts.server.url
	git config --unset --local ts.server.update

	git config --unset --local ts.request.file
	git config --unset --local ts.request.options

	git config --unset --local ts.respone.file
	git config --unset --local ts.respone.options
	git config --unset --local ts.respone.verify

	script_echo "Uninstall complete."
}

# Short options
for arg in "$@"; do
	shift
	case "${arg}" in
	"--default") set -- "$@" "-d" ;;
	"--force") set -- "$@" "-f" ;;
	"--help") set -- "$@" "-h" ;;
	"--remove") set -- "$@" "-r" ;;
	"--purge") set -- "$@" "-p" ;;
	*) set -- "$@" "${arg}" ;;
	esac
done

OPT_DEFAULT=false
OPT_FORCE=false
OPT_REMOVE=false
OPT_PURGE=false

# Parse options
OPTIND=1
while getopts "dfhrp" opt; do
	case "${opt}" in
	"d")
		OPT_DEFAULT=true
		;;
	"f")
		OPT_FORCE=true
		;;
	"h")
		print_help
		exit 0
		;;
	"r")
		OPT_REMOVE=true
		;;
	"p")
		OPT_PURGE=true
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

(
	cd "$(dirname "$0")" || exit 255
	if [[ ${OPT_REMOVE} == false && ${OPT_PURGE} == false ]]; then
		install_timestamping "$(realpath "$1")"
	else
		uninstall_timestamping "$(realpath "$1")"
	fi
)

exit 0
