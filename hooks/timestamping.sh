#!/usr/bin/env bash

#	Automated Timestamping
#
#	Copyright (c) 2021 Johannes Milczewski
#
#	Permission is hereby granted, free of charge, to any person obtaining a copy
#	of this software and associated documentation files (the "Software"), to deal
#	in the Software without restriction, including without limitation the rights
#	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#	copies of the Software, and to permit persons to whom the Software is
#	furnished to do so, subject to the following conditions:
#
#	The above copyright notice and this permission notice shall be included in all
#	copies or substantial portions of the Software.
#
#	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#	SOFTWARE.

# region Environment setup

# Error codes
TS_ERROR_CALL=128

TS_ERROR_WITHHOLD=9

TS_ERROR_REQUEST=8
TS_ERROR_RESPONSE=7
TS_ERROR_VERIFY_REQUEST=6
TS_ERROR_VERIFY_DATA=5

TS_ERROR_ROOT_BRANCH=4

TS_ERROR_CONFIG_INVALID=3
TS_ERROR_CONFIG_UNSET=2

TS_ERROR=1
TS_OK=0

# If timestamping is enabled runs the command passed via arguments
# Arguments:
# 	$@: Command to run
#
# Returns:
# 	&1: The output of $@
# 	$?: The exit code of $@
function if_enabled() {
	local TS_ENABLED
	TS_ENABLED=$(git config --get ts.enabled)

	if [[ ${TS_ENABLED} == "true" ]]; then
		eval "$@"
		return $?
	fi

	return $TS_OK
}

# Runs a command passed via arguments after setting up variables for all timestamping options
# Arguments:
# 	$@: Command to run
#
# Returns:
# 	&1: The output of $@
# 	$?: The exit code of $@
function in_environment() {
	shopt -s extglob
	. "$(git --exec-path)/git-sh-setup"

	local RETURN=$TS_OK

	local TS_BRANCH_PREFIX
	local TS_COMMIT_PREFIX

	local TS_DIFF_NOTICE
	local TS_DIFF_FILE
	local TS_DIFF_TYPE

	local TS_SERVER_DIRECTORY
	local TS_SERVER_URL
	local TS_SERVER_CERTIFICATE

	local TS_REQUEST_FILE
	local TS_REQUEST_OPTIONS=()

	local TS_RESPONSE_FILE
	local TS_RESPONSE_OPTIONS=()
	local TS_RESPONSE_VERIFY

	local TS_PUSH_WITHHOLD

	if [[ -z ${TS_ENVIRONMENT_SET+x} ]]; then
		if ! TS_BRANCH_PREFIX=$(git config ts.branch.prefix); then
			echo 'Run "git config ts.branch.prefix" to set the signing branch prefix'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi
		if ! TS_COMMIT_PREFIX=$(git config ts.commit.prefix); then
			echo 'Run "git config ts.commit.prefix" to set the signing commit message prefix'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi

		if ! TS_DIFF_NOTICE=$(git config ts.diff.notice); then
			echo 'Run "git config ts.diff.notice" to set the notice in the diff header'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi
		if ! TS_DIFF_FILE=$(git config ts.diff.file); then
			echo 'run "git config ts.diff.file" to set the name of the generated diff file'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi
		if ! TS_DIFF_TYPE=$(git config ts.diff.type); then
			echo 'run "git config ts.diff.type" to set how the diff is created'
			RETURN=$TS_ERROR_CONFIG_UNSET
		elif [[ ${TS_DIFF_TYPE} != "staged" && ${TS_DIFF_TYPE} != "full" ]]; then
			echo 'ERROR: ts.diff.type must be wither "staged" or "full"'
			RETURN $TS_ERROR_CONFIG_INVALID
		fi

		if ! TS_SERVER_DIRECTORY=$(git config ts.server.directory); then
			echo 'Run "git config ts.server.directory" to set the directory name of the the timestamping.sh server configs'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi
		if ! TS_SERVER_URL=$(git config ts.server.url); then
			echo 'Run "git config ts.server.url" to set the name of the file containing the timestamping.sh server url'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi
		if ! TS_SERVER_CERTIFICATE=$(git config ts.server.certificate); then
			echo 'Run "git config ts.server.certificate" to set the name of the timestamping.sh server certificate file'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi

		if ! TS_REQUEST_FILE=$(git config ts.request.file); then
			echo 'Run "git config ts.request.file" to set the name of the timestamp request file'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi
		if ! mapfile -d " " -t TS_REQUEST_OPTIONS < <(git config ts.request.options | tr -d '\n'); then
			echo 'Run "git config ts.request.options" to set the options for creating the timestamp request file'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi

		if ! TS_RESPONSE_FILE=$(git config ts.respone.file); then
			echo 'Run "git config ts.response.file" to set the name of the timestamp response file'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi
		if ! mapfile -d " " -t TS_RESPONSE_OPTIONS < <(git config ts.respone.options | tr -d '\n'); then
			echo 'Run "git config ts.response.options" to set the options for curling the timestamp response file'
			RETURN=$TS_ERROR_CONFIG_UNSET
		fi
		if ! TS_RESPONSE_VERIFY=$(git config ts.respone.verify); then
			echo 'Run "git config ts.response.verify" to set whether the timestamp response file is verified after'
			RETURN=$TS_ERROR_CONFIG_UNSET
		elif [[ ${TS_RESPONSE_VERIFY} != "true" && ${TS_RESPONSE_VERIFY} != "false" ]]; then
			echo 'ERROR: ts.response.verify must be wither "true" or "false"'
			RETURN $TS_ERROR_CONFIG_INVALID
		fi

		if ! TS_PUSH_WITHHOLD=$(git config ts.push.withhold); then
			echo 'Run "git config ts.push.withhold" to set whether timestamp commits should be withheld from remotes'
			RETURN=$TS_ERROR_CONFIG_UNSET
		elif [[ ${TS_PUSH_WITHHOLD} != "true" && ${TS_PUSH_WITHHOLD} != "false" ]]; then
			echo 'ERROR: ts.push.withhold must be wither "true" or "false"'
			RETURN $TS_ERROR_CONFIG_INVALID
		fi

		if [[ ${RETURN} -ne $TS_OK ]]; then
			return ${RETURN}
		fi

		TS_ENVIRONMENT_SET=
		eval "$@"
		RETURN=$?
		unset TS_ENVIRONMENT_SET
		return ${RETURN}
	else
		eval "$@"
		return $?
	fi
}
# endregion

# region Objects

# Removes redundant slashes from paths
# Arguments:
# 	$1: Possibly uncanonical path
#
# Returns:
# 	&1: Canonized path
function canonize() {
	local PATH=$1
	echo "${PATH//\/*(\/)/\/}"
}

# Gets the content of a versioned file
# Arguments:
# 	$1: the branch of the file
# 	$2: the path to the file
#
# Returns:
# 	&1: The contents of the file
function get_file() {
	local BRANCH=$1
	local PATH
	PATH=$(canonize "$2")
	git show "${BRANCH}:${PATH}"
}
# endregion

# region Timestamps

# Creates a timestamp request file
# Arguments:
# 	$1: Path to the file to be signed
# 	$2: Path to the TSA configuration directory
#
# Returns:
# 	$?: The exit code of openssl ts -query
function create_timestamp_request() {
	local DATA_FILE=$1
	local SERVER_DIRECTORY=$2

	openssl ts -query \
		-data "${DATA_FILE}" \
		"${TS_REQUEST_OPTIONS[@]}" \
		-out "${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
		>/dev/null 2>/dev/null
	return $?
}

# Retrieves a timestamp response file
# Arguments:
# 	$1: Path to the TSA configuration directory
#
# Returns:
# 	$?: The exit code of curl
function get_timestamp_response() {
	local SERVER_DIRECTORY=$1

	local SERVER_DIR=${SERVER_DIRECTORY#*${TS_SERVER_DIRECTORY}/}
	SERVER_DIR=${SERVER_DIR%/*}

	local SERVER_URL
	if [[ -f "${SERVER_DIRECTORY}/${TS_SERVER_URL}" ]]; then
		SERVER_URL=$(cat "${SERVER_DIRECTORY}/${TS_SERVER_URL}")
	else
		SERVER_URL="http://${SERVER_DIR}"
	fi
	hook_echo "Generating timestamp for ${SERVER_DIR} at ${SERVER_URL}"

	curl --silent \
		--header 'Content-Type: application/timestamp-query' \
		"${TS_RESPONSE_OPTIONS[@]}" \
		--data-binary "@${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
		"${SERVER_URL}" \
		-o "${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
		>/dev/null

	return $?
}

# Verifies a timestamp response file
# Arguments:
# 	$1: Path to the signed file
# 	$2: Path to the TSA configuration directory
#
# Returns:
# 	0: Response is OK
# 	1: Could not verify against the signed file
# 	2: Could not verify against the request file
function verify_timestamp() {
	local DATA_FILE=$1
	local SERVER_DIRECTORY=$2

	# Verify timestamp against request
	if ! openssl ts -verify \
		-in "${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
		-queryfile "${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
		-CAfile "${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" \
		>/dev/null 2>/dev/null; then
		return $TS_ERROR_VERIFY_REQUEST
	fi

	# Verify timestamp against data
	if ! openssl ts -verify \
		-in "${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
		-data "${DATA_FILE}" \
		-CAfile "${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" \
		>/dev/null 2>/dev/null; then
		return $TS_ERROR_VERIFY_REQUEST
	fi

	return $TS_OK
}
# endregion

# region Stashing

# Stashes uncommitted changes, if any
# Returns:
# 	0: No changes were stashed
# 	1: Changes were stashed
function maybe_stash() {
	if git rev-parse HEAD >/dev/null 2>/dev/null && git diff --cached --quiet --exit-code HEAD; then
		git stash push >/dev/null 2>/dev/null
		return 0
	else
		return 1
	fi
}

# Unstashes uncommitted changes, if any
# Arguments:
# 	$1 1, if changes should be unstashed, 0 otherwise
function maybe_unstash() {
	if [[ $1 != 0 ]]; then
		git stash pop >/dev/null 2>/dev/null
	fi
}
# endregion

# region Branches

# Gets the name of the branch the next commit would go to
# Returns:
# 	&1: The name of the branch
function get_branch() {
	local BRANCH
	if ! BRANCH=$(git symbolic-ref --short HEAD); then
		if ! BRANCH=$(git config init.defaultBranch); then
			BRANCH="master"
		fi
	fi
	echo "${BRANCH}"
}

# Gets the name of the signing branch for the current one
# Arguments:
# 	$1: Actual branch name
#
# Returns:
# 	&1: The name of the signing branch
function get_signing_branch() {
	local BRANCH=$1

	if [[ ! ${BRANCH} == "${TS_BRANCH_PREFIX}/"* && ! ${BRANCH} == "${TS_BRANCH_PREFIX}-" ]]; then
		echo "${TS_BRANCH_PREFIX}/${BRANCH}"
	else
		echo "${BRANCH}"
	fi
}

# Gets the name of best existing signing branch for the current one
# Arguments:
# 	$1: Actual branch name
#
# Returns:
# 	&1: The name of the signing branch
function get_actual_signing_branch() {
	if git rev-parse --verify "${BRANCH}" >/dev/null 2>/dev/null; then
		echo "${TS_BRANCH_PREFIX}/$1"
	else
		echo "${TS_BRANCH_PREFIX}-"
	fi
}

# Checks, if currently on a signing branch
# Returns:
# 	0: On signing branch
# 	1: Not on signing branch
function on_signing_branch() {
	[[ ${BRANCH} == ${TS_BRANCH_PREFIX}/* || ${BRANCH} == "${TS_BRANCH_PREFIX}-" ]]
	return $?
}

# Checks out an actual branch, as orphan if necessary
# Arguments:
# 	$1: Name of the branch
function checkout_actual() {
	local BRANCH=$1
	if git rev-parse --verify "${BRANCH}" >/dev/null 2>/dev/null; then
		hook_echo "Checking out ${BRANCH}"
		git checkout "${BRANCH}" >/dev/null 2>/dev/null
	else
		hook_echo "Checking out orphaned ${BRANCH}"
		git checkout --orphan "${BRANCH}" >/dev/null 2>/dev/null
	fi
}

# Checks out a signing branch, branch if root signing if necessary
# Arguments:
# 	$1: Name of the branch
function checkout_signing() {
	local SIGNING_BRANCH
	SIGNING_BRANCH=$(get_signing_branch "$1")
	if git rev-parse --verify "${SIGNING_BRANCH}" >/dev/null 2>/dev/null; then
		git checkout "${SIGNING_BRANCH}" >/dev/null 2>/dev/null
	else
		git checkout "${TS_BRANCH_PREFIX}-" >/dev/null 2>/dev/null
		git checkout -b "${SIGNING_BRANCH}" >/dev/null 2>/dev/null
	fi
}

# Checks whether an object only exists on signing branches
# Arguments:
# 	$1 OID of the object in question
#
# Returns:
# 	0: Object is signing branch only
# 	1: Object is on at least one actual branch
function is_signing_only_object() {
	local OID=$1
	local ACTUAL=0
	local OUTPUT
	local BRANCHES=()
	local TS_BRANCHES=()
	mapfile -t BRANCHES < <(git branch --contains "${OID}" | tr -d " *")
	for b in "${BRANCHES[@]}"; do
		if [[ ${b} != "${TS_BRANCH_PREFIX}-" && ${b} != "${TS_BRANCH_PREFIX}/"* ]]; then
			ACTUAL=$((ACTUAL + 1))
		else
			TS_BRANCHES+=("${b}")
		fi
	done
	printf -v OUTPUT '%s, ' "${TS_BRANCHES[@]}"
	echo "${OUTPUT%", "}"

	if [ ${ACTUAL} -eq 0 ]; then
		return 1
	else
		return 0
	fi
}

# Prints a list of all active TSA configurations on a branch
# Arguments:
# 	$1: Branch to check
#
# Returns:
# 	&1: All active TSA configuration directory names
function echo_tsa_list() {
	local BRANCH=$1
	local TSA_LIST=()
	local SIGNING_BRANCH
	SIGNING_BRANCH=$(get_actual_signing_branch "${BRANCH}")
	mapfile -t TSA_LIST < <(git ls-tree -r --name-only "${SIGNING_BRANCH}" | grep -w "${TS_SERVER_CERTIFICATE}" --color=never)
	for i in "${!TSA_LIST[@]}"; do
		TSA_LIST[${i}]="${TSA_LIST[${i}]#"${TS_SERVER_DIRECTORY}/"}"
		TSA_LIST[${i}]="${TSA_LIST[${i}]%"/${TS_SERVER_CERTIFICATE}"}"
	done

	echo "${TSA_LIST[@]}"
}
# endregion

# region Diffs

# Prints the standard diff for timestamping
# Returns:
# 	&1: The diff
function get_diff() {
	if [[ "${TS_DIFF_TYPE}" == "staged" ]]; then
		git diff --staged --full-index --binary
		return $TS_OK
	elif [[ "${TS_DIFF_TYPE}" == "full" ]]; then
		git diff --staged --full-index --binary "$(git hash-object -t tree /dev/null)"
		return $TS_OK
	else
		return $TS_ERROR
	fi
}

# Prints a diff for a TSA configuration
# Arguments:
# 	$1: Branch the TSA configuration is on
# 	$2: TSA configuration directory name
#
# Returns:
# 	&1: The generated diff
# 	$?: The exit code of the diff provider
function get_tsa_diff() {
	local BRANCH=$1
	local SERVER_DIRECTORY=$2
	local DIFF_PROVIDER
	local PATH
	PATH=$(canonize "${BRANCH}:${TS_SERVER_DIRECTORY}/${SERVER_DIRECTORY}/${TS_DIFF_FILE}.sh")
	DIFF_PROVIDER=$(git show "${PATH}")
	eval "$DIFF_PROVIDER"
	return $?
}

# Checks if a diff file is well-formed
# Arguments:
# 	$1: Path to the diff file
#
# Returns:
# 	0: Diff file is well-formed
# 	1: Diff file is ill-formed
function check_diff() {
	local DIFF_FILE=$1
	git apply --check "${DIFF_FILE}" >/dev/null 2>/dev/null
	return $?
}

# Writes data to the standard diff file
# Arguments:
# 	$1: The data to write
#
# Returns:
# 	0: Written diff is well-formed
# 	1: Diff file is ill-formed
function write_diff() {
	local DIFF=$1
	echo "${TS_DIFF_NOTICE}" >"${TS_DIFF_FILE}"
	echo "${DIFF}" >>"${TS_DIFF_FILE}"
	echo "" >>"${TS_DIFF_FILE}"
	check_diff "${TS_DIFF_FILE}"
	return $?
}

# Writes data to a TSA configuration's diff file
# Arguments:
# 	$1: The diff
# 	$2: TSA configuration directory name
#
# Returns:
# 	0: Written diff is well-formed
# 	1: Diff file is ill-formed
function write_tsa_diff() {
	local DIFF=$1
	local SERVER_DIRECTORY=$2
	local DIFF_FILE="${TS_SERVER_DIRECTORY}/${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}"
	echo "${TS_DIFF_NOTICE}" >"${DIFF_FILE}"
	echo "${DIFF}" >>"${DIFF_FILE}"
	echo "" >>"${DIFF_FILE}"
	check_diff "${DIFF_FILE}"
	return $?
}
# endregion

# region Commits

# Adds the timestamping files to the staging area
function add_ts_files() {
	git add --force -- "${TS_DIFF_FILE}" "${TS_SERVER_DIRECTORY}/"*
}

# Commits the timestamping files in the staging area
function commit_ts_files() {
	local COMMIT_MSG=$1
	git commit --message "${COMMIT_MSG}" -- "${TS_DIFF_FILE}" "${TS_SERVER_DIRECTORY}/"*
}

# Amends the timestamping files in the staging area to the last commit
function amend_ts_files() {
	local COMMIT_MSG=$1
	git commit --amend --message "${COMMIT_MSG}" -- "${TS_SERVER_DIRECTORY}/"*
}

# Merges changes from the root signing branch into the current signing branch
function merge_branches() {
	local COMMIT_ID=$1
	git merge --strategy=recursive --strategy-option=theirs "${COMMIT_ID}"
}

# Relates a commit to the last timestamping commit
function relate_branches() {
	local COMMIT_MSG=$1
	local COMMIT_ID=$2
	git merge --allow-unrelated-histories --strategy ours --message "${COMMIT_MSG}" "${COMMIT_ID}"
}
# endregion

function comprehend_change() {
	local BRANCH=$1
	local SERVER_DIRECTORY=$2

	local CERT0
	local CERT1
	local URL0
	local URL1

	CERT0=$(git rev-parse @~0:"${SERVER_DIRECTORY}${TS_SERVER_CERTIFICATE}" 2>/dev/null) || CERT0=""
	CERT1=$(git rev-parse @~1:"${SERVER_DIRECTORY}${TS_SERVER_CERTIFICATE}" 2>/dev/null) || CERT1=""
	URL0=$(git rev-parse @~0:"${SERVER_DIRECTORY}${TS_SERVER_URL}" 2>/dev/null) || URL0=""
	URL1=$(git rev-parse @~1:"${SERVER_DIRECTORY}${TS_SERVER_URL}" 2>/dev/null) || URL1=""

	local SERVER_DIR
	SERVER_DIR=${SERVER_DIRECTORY#*${TS_SERVER_DIRECTORY}/}
	SERVER_DIR=${SERVER_DIR%/*}

	# Added/Modified TSAs
	if [[ -n ${CERT0} && ${CERT0} != "${CERT1}" ]] ||
		[[ -n ${URL0} && ${URL0} != "${URL1}" ]]; then
		if [[ -z ${CERT1} && -z ${URL1} ]]; then
			hook_echo "Adding TSA ${SERVER_DIR} to branch ${b}"
		else
			hook_echo "Updating TSA ${SERVER_DIR} to branch ${b}"
		fi

		if [[ -f "${TS_DIFF_FILE}" ]] && create_timestamp "${BRANCH}" "${TS_DIFF_FILE}" "${SERVER_DIRECTORY}"; then
			return $TS_OK
		fi
	fi

	# Removed TSAs
	if [[ ! -f "${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" ]] &&
		[[ ! -f ".${SERVER_DIRECTORY}/${TS_SERVER_URL}" ]]; then
		hook_echo "Removing TSA ${SERVER_DIR} from branch ${b}"
		git rm "${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
			".${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}"

		return $TS_OK
	fi

	return $TS_ERROR
}

# Creates a timestamp for a single TSA configuration
# Arguments:
# 	$1 Actual branch
# 	$2 Path to file to be signed
# 	$3 Path to the TSA configuration directory
#
# Returns:
# 	0 on success
# 	1 on verify error
# 	2 on reply error
# 	3 on query error
function create_timestamp() {
	local BRANCH=$1
	local DATA_FILE=$2
	local SERVER_DIRECTORY=$3
	local SIGNING_BRANCH

	local SERVER_DIR=${SERVER_DIRECTORY#*${TS_SERVER_DIRECTORY}/}
	SERVER_DIR=${SERVER_DIR%/*}

	SIGNING_BRANCH=$(get_signing_branch "${BRANCH}")

	if [[ "${SERVER_DIR}" == "*" ]]; then
		return 5
	fi

	if [[ ! -f "${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" ]]; then
		return 5
	fi

	if [[ -f "${SERVER_DIRECTORY}/${TS_DIFF_FILE}.sh" ]]; then
		local DIFF

		DATA_FILE="${SERVER_DIRECTORY}/${TS_DIFF_FILE}"
		DIFF=$(get_tsa_diff "${SIGNING_BRANCH}" "${SERVER_DIRECTORY}")
		if ! write_tsa_diff "${DIFF}" "${SERVER_DIRECTORY}"; then
			return 4
		fi
	fi

	# Create timestamp request
	create_timestamp_request "${DATA_FILE}" "${SERVER_DIRECTORY}" || return $TS_ERROR_REQUEST

	# Get timestamp response
	get_timestamp_response "${SERVER_DIRECTORY}" || return $TS_ERROR_RESPONSE

	# Run verifications if set
	if [[ "${TS_RESPONSE_VERIFY}" == "true" ]]; then
		local RESULT
		verify_timestamp \
			"${DATA_FILE}" \
			"${SERVER_DIRECTORY}"
		RESULT=$?
		case ${RESULT} in
		$TS_ERROR_VERIFY_REQUEST) hook_echo "ERROR: Timestamp from ${SERVER_DIRECTORY} could not be verified against request!" ;;
		$TS_ERROR_VERIFY_DATA) hook_echo "ERROR: Timestamp from ${SERVER_DIRECTORY} could not be verified against diff!" ;;
		0) ;;
		esac

		return "${RESULT}"
	fi

	return $TS_OK
}

function commit_timestamps() {
	# Checkout signing branch
	checkout_signing "$1"

	# Add timestamp files to stage
	hook_echo "Committing timestamps"
	add_ts_files

	# Commit timestamp files
	commit_ts_files "${TS_COMMIT_PREFIX}${COMMIT_MSG}"
	touch "${GIT_DIR}/TIMESTAMP"
}

function create_timestamps() {
	local BRANCH=$1
	local RETURN=0
	local SIG_COUNT=0

	# Loop for each timestamping server
	for d in "${TS_SERVER_DIRECTORY}/"*/; do
		create_timestamp "${BRANCH}" "${TS_DIFF_FILE}" "${d}"
		case $? in
		0) SIG_COUNT=$((SIG_COUNT + 1)) ;;
		1) RETURN=1 ;;
		2) RETURN=1 ;;
		*) ;;
		esac
	done

	# Check if any signature was generated
	if [[ ${SIG_COUNT} -gt 0 ]] && [[ ${RETURN} -eq 0 ]]; then
		return $TS_OK
	else
		return $TS_ERROR
	fi
}

function update_timestamps() {
	local COMMIT_ID=$1
	local BRANCH=$2

	local REVS
	local BRANCHES=()
	local IFS

	mapfile -t REVS < <(git branch --contains "$(git rev-list --max-parents=0 HEAD)" 2>/dev/null | tr -d " *")

	for i in "${!REVS[@]}"; do
		if [[ "${REVS[$i]}" == "${TS_BRANCH_PREFIX}/"* ]]; then
			BRANCHES+=("${REVS[$i]}")
		fi
	done

	IFS=" "
	read -r -a BRANCHES <<<"$(tr ' ' '\n' <<<"${BRANCHES[@]}" | sort -u | tr '\n' ' ')"

	local STASH
	maybe_stash
	STASH=$?

	local SIG_COUNT=0

	for b in "${BRANCHES[@]}"; do
		hook_echo "Applying TSA changes to ${b}"
		git checkout "${b}" >/dev/null 2>/dev/null
		merge_branches "${COMMIT_ID}"

		for d in "${TS_SERVER_DIRECTORY}/"*/; do
			if comprehend_change "${b}" "${d}"; then
				SIG_COUNT=$((SIG_COUNT + 1))
			fi
		done

		if [[ ${SIG_COUNT} -gt 0 ]]; then
			hook_echo "Committing timestamps"
			add_ts_files
			amend_ts_files "Applied updates from '${COMMIT_ID}' to ${b}"
		else
			hook_echo "No timestamps to amend"
			rm "${TS_DIFF_FILE}" >/dev/null
		fi
	done

	git checkout "${BRANCH}" >/dev/null 2>/dev/null
	maybe_unstash ${STASH}
}
