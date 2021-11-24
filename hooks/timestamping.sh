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
function if_enabled() {
	local TS_ENABLED
	TS_ENABLED=$(git config --get ts.enabled)

	if [[ ${TS_ENABLED} == "true" ]]; then
		# shellcheck disable=SC2068
		$@
		return $?
	fi

	return 0
}

function in_environment() {
	. "$(git --exec-path)/git-sh-setup"

	local RETURN=0

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

	if [[ -z ${TS_ENVIRONMENT_SET+x} ]]; then
		if ! TS_BRANCH_PREFIX=$(git config ts.branch.prefix); then
			echo 'Run "git config ts.branch.prefix" to set the signing branch prefix'
			RETURN=2
		fi
		if ! TS_COMMIT_PREFIX=$(git config ts.commit.prefix); then
			echo 'Run "git config ts.commit.prefix" to set the signing commit message prefix'
			RETURN=2
		fi

		if ! TS_DIFF_NOTICE=$(git config ts.diff.notice); then
			echo 'Run "git config ts.diff.notice" to set the notice in the diff header'
			RETURN=2
		fi
		if ! TS_DIFF_FILE=$(git config ts.diff.file); then
			echo 'run "git config ts.diff.file" to set the name of the generated diff file'
			RETURN=2
		fi
		if ! TS_DIFF_TYPE=$(git config ts.diff.type); then
			echo 'run "git config ts.diff.type" to set how the diff is created'
			RETURN=2
		fi

		if ! TS_SERVER_DIRECTORY=$(git config ts.server.directory); then
			echo 'Run "git config ts.server.directory" to set the directory name of the the timestamping.sh server configs'
			RETURN=2
		fi
		if ! TS_SERVER_URL=$(git config ts.server.url); then
			echo 'Run "git config ts.server.url" to set the name of the file containing the timestamping.sh server url'
			RETURN=2
		fi
		if ! TS_SERVER_CERTIFICATE=$(git config ts.server.certificate); then
			echo 'Run "git config ts.server.certificate" to set the name of the timestamping.sh server certificate file'
			RETURN=2
		fi

		if ! TS_REQUEST_FILE=$(git config ts.request.file); then
			echo 'Run "git config ts.request.file" to set the name of the timestamp request file'
			RETURN=2
		fi
		if ! mapfile -d " " -t TS_REQUEST_OPTIONS < <(git config ts.request.options | tr -d '\n'); then
			echo 'Run "git config ts.request.options" to set the options for creating the timestamp request file'
			RETURN=2
		fi

		if ! TS_RESPONSE_FILE=$(git config ts.respone.file); then
			echo 'Run "git config ts.response.file" to set the name of the timestamp response file'
			RETURN=2
		fi
		if ! mapfile -d " " -t TS_RESPONSE_OPTIONS < <(git config ts.respone.options | tr -d '\n'); then
			echo 'Run "git config ts.response.options" to set the options for curling the timestamp response file'
			RETURN=2
		fi
		if ! TS_RESPONSE_VERIFY=$(git config ts.respone.verify); then
			echo 'Run "git config ts.response.verify" to set whether the timestamp response file is verified after'
			RETURN=2
		fi

		if [[ ${RETURN} -ne 0 ]]; then
			return ${RETURN}
		fi

		TS_ENVIRONMENT_SET=
		# shellcheck disable=SC2068
		$@
		RETURN=$?
		unset TS_ENVIRONMENT_SET
		return ${RETURN}
	else
		# shellcheck disable=SC2068
		$@
		return $?
	fi
}
# endregion

# region Timestamps
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

function get_timestamp_response() {
	local SERVER_DIRECTORY=$1

	curl --silent \
		--header 'Content-Type: application/timestamp-query' \
		"${TS_RESPONSE_OPTIONS[@]}" \
		--data-binary "@${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
		"${SERVER_URL}" \
		-o "${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
		>/dev/null
}

function verify_timestamp() {
	local DATA_FILE=$1
	local SERVER_DIRECTORY=$2

	# Verify timestamp against request
	if ! openssl ts -verify \
		-in "${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
		-queryfile "${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
		-CAfile "${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" \
		>/dev/null 2>/dev/null; then
		return 2
	fi

	# Verify timestamp against data
	if ! openssl ts -verify \
		-in "${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
		-data "${DATA_FILE}" \
		-CAfile "${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" \
		>/dev/null 2>/dev/null; then
		return 1
	fi

	return 0
}
# endregion

# region Stashing

# Stashes uncommitted changes, if any
# Returns:
# 	0 No changes were stashed
# 	1 Changes were stashed
function maybe_stash() {
	if ! git diff --cached --quiet --exit-code HEAD; then
		git stash push
		return 1
	else
		return 0
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
function get_branch() {
	local BRANCH
	if ! BRANCH=$(git symbolic-ref --short HEAD); then
		if ! BRANCH=$(git config init.defaultBranch); then
			BRANCH="master"
		fi
	fi
	echo "${BRANCH}"
}

function get_signing_branch() {
	echo "${TS_BRANCH_PREFIX}/$1"
}

function on_signing_branch() {
	[[ ${BRANCH} == ${TS_BRANCH_PREFIX}/* || ${BRANCH} == "${TS_BRANCH_PREFIX}-" ]]
	return $?
}

function check_out_actual() {
	local BRANCH=$1
	if git rev-parse --verify "${BRANCH}" >/dev/null 2>/dev/null; then
		hook_echo "Restoring stage on ${BRANCH}"
		git checkout "${BRANCH}" >/dev/null 2>/dev/null
	else
		hook_echo "Restoring stage on orphaned ${BRANCH}"
		git checkout --orphan "${BRANCH}" >/dev/null 2>/dev/null
	fi
}

function check_out_signing() {
	hook_echo "Switch to signing branch"
	local SIGNING_BRANCH
	SIGNING_BRANCH=$(get_signing_branch "$1")
	if git rev-parse --verify "${SIGNING_BRANCH}" >/dev/null 2>/dev/null; then
		git checkout "${SIGNING_BRANCH}" >/dev/null 2>/dev/null
	else
		git checkout -b "${SIGNING_BRANCH}" >/dev/null 2>/dev/null
	fi
}

function check_out_signing_or_root() {
	hook_echo "Switch to signing branch"
	local SIGNING_BRANCH
	SIGNING_BRANCH=$(get_signing_branch "$1")
	if git rev-parse --verify "${SIGNING_BRANCH}" >/dev/null 2>/dev/null; then
		git checkout "${SIGNING_BRANCH}" -- "${TS_DIFF_FILE}" "${TS_SERVER_DIRECTORY}/"* >/dev/null 2>/dev/null
	else
		git checkout "${TS_BRANCH_PREFIX}-" >/dev/null 2>/dev/null
	fi
}
# endregion

# region Diffs
function get_diff() {
	if [[ "${TS_DIFF_TYPE}" == "staged" ]]; then
		git diff --staged --full-index --binary
		return 0
	elif [[ "${TS_DIFF_TYPE}" == "full" ]]; then
		git diff --staged --full-index --binary "$(git hash-object -t tree /dev/null)"
		return 0
	else
		return 3
	fi
}

function write_diff() {
	echo "${TS_DIFF_NOTICE}" >"${TS_DIFF_FILE}"
	echo "$1" >>"${TS_DIFF_FILE}"
	echo "" >>"${TS_DIFF_FILE}"
}
# endregion

# region Commits
function add_ts_files() {
	git add \
		--force \
		-- \
		"${TS_DIFF_FILE}" \
		"${TS_SERVER_DIRECTORY}/"* \
		>/dev/null 2>/dev/null
}

function commit_ts_files() {
	git commit \
		--message "$1" \
		-- "${TS_DIFF_FILE}" "${TS_SERVER_DIRECTORY}/" \
		>/dev/null 2>/dev/null
}

function amend_ts_files() {
	git commit \
		--amend \
		--message "$1" \
		-- "./${TS_SERVER_DIRECTORY}/"* \
		>/dev/null 2>/dev/null
}

function merge_branches() {
	git merge \
		--strategy=recursive \
		--strategy-option=theirs \
		"$1" \
		>/dev/null 2>/dev/null
}

function relate_branches() {
	git merge \
		--allow-unrelated-histories \
		--strategy ours \
		--message "$1" \
		"$2" \
		>/dev/null 2>/dev/null
}
# endregion

function comprehend_change() {
	local d=$1

	local CERT0
	local CERT1
	local URL0
	local URL1
	CERT0=$(git rev-parse @~0:"${d}${TS_SERVER_CERTIFICATE}" 2>/dev/null) || CERT0=""
	CERT1=$(git rev-parse @~1:"${d}${TS_SERVER_CERTIFICATE}" 2>/dev/null) || CERT1=""
	URL0=$(git rev-parse @~0:"${d}${TS_SERVER_URL}" 2>/dev/null) || URL0=""
	URL1=$(git rev-parse @~1:"${d}${TS_SERVER_URL}" 2>/dev/null) || URL1=""

	local SERVER_DIR
	SERVER_DIR=${d#*${TS_SERVER_DIRECTORY}/}
	SERVER_DIR=${SERVER_DIR%/*}

	# Added/Modified TSAs
	if [[ -n ${CERT0} && ${CERT0} != "${CERT1}" ]] ||
		[[ -n ${URL0} && ${URL0} != "${URL1}" ]]; then
		if [[ -z ${CERT1} && -z ${URL1} ]]; then
			hook_echo "Adding TSA ${SERVER_DIR} to branch ${b}"
		else
			hook_echo "Updating TSA ${SERVER_DIR} to branch ${b}"
		fi

		if [[ -f "${TS_DIFF_FILE}" ]] && create_timestamp "${TS_DIFF_FILE}" "${d}"; then
			return 0
		fi
	fi

	# Removed TSAs
	if [[ ! -f "${d}/${TS_SERVER_CERTIFICATE}" ]] &&
		[[ ! -f ".${d}/${TS_SERVER_URL}" ]]; then
		hook_echo "Removing TSA ${SERVER_DIR} from branch ${b}"
		git rm "${d}/${TS_REQUEST_FILE}" \
			".${d}/${TS_RESPONSE_FILE}"
	fi

	return 1
}

# Creates a timestamp for a single TSA configuration
# Arguments:
# 	$1 Path to file to be timestamped
# 	$2 Path to the TSA configuration directory
#   $3 URL of the server
#
# Returns:
# 	0 on success
# 	1 on verify error
# 	2 on reply error
# 	3 on query error
function create_timestamp() {
	local DATA_FILE=$1
	local SERVER_DIRECTORY=$2

	local SERVER_DIR=${SERVER_DIRECTORY#*${TS_SERVER_DIRECTORY}/}
	SERVER_DIR=${SERVER_DIR%/*}

	if [[ "${SERVER_DIR}" == "*" ]]; then
		return 4
	fi

	if [[ ! -f "${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" ]]; then
		return 4
	fi

	local SERVER_URL
	if [[ -f "${SERVER_DIRECTORY}/${TS_SERVER_URL}" ]]; then
		SERVER_URL=$(cat "${SERVER_DIRECTORY}/${TS_SERVER_URL}")
	else
		SERVER_URL="http://${SERVER_DIR}"
	fi
	hook_echo "Generating timestamp for ${SERVER_DIR} at ${SERVER_URL}"

	# Create timestamp request
	create_timestamp_request "${DATA_FILE}" "${SERVER_DIRECTORY}" || return 3

	# Get timestamp response
	get_timestamp_response "${SERVER_DIRECTORY}" || return 2

	# Run verifications if set
	if [[ "${TS_RESPONSE_VERIFY}" == "true" ]]; then
		local RESULT
		verify_timestamp \
			"${DATA_FILE}" \
			"${SERVER_DIRECTORY}"
		RESULT=$?
		case ${RESULT} in
		2) hook_echo "ERROR: Timestamp from ${SERVER_DIRECTORY} could not be verified against request!" ;;
		1) hook_echo "ERROR: Timestamp from ${SERVER_DIRECTORY} could not be verified against diff!" ;;
		0) ;;
		esac

		return "${RESULT}"
	fi

	return 0
}

function commit_timestamps() {
	# Checkout signing branch
	check_out_signing "$1"

	# Add timestamp files to stage
	hook_echo "Committing timestamps"
	add_ts_files

	# Commit timestamp files
	commit_ts_files "${TS_COMMIT_PREFIX}${COMMIT_MSG}"
	touch "${GIT_DIR}/TIMESTAMP"
}

function create_and_commit_timestamps() {
	local RETURN=0
	local SIG_COUNT=0

	# Loop for each timestamping server
	for d in "${TS_SERVER_DIRECTORY}/"*/; do
		create_timestamp "${TS_DIFF_FILE}" "${d}"
		case $? in
		0) SIG_COUNT=$((SIG_COUNT + 1)) ;;
		1) RETURN=1 ;;
		2) RETURN=1 ;;
		*) ;;
		esac
	done

	# Check if any signature was generated
	if [[ ${SIG_COUNT} -gt 0 ]] && [[ ${RETURN} -eq 0 ]]; then
		commit_timestamps "${BRANCH}"
	else
		hook_echo "No timestamps to commit"
		rm "${TS_DIFF_FILE}" >/dev/null
	fi

	return ${RETURN}
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
			if comprehend_change "${d}"; then
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
