#!/usr/bin/env bash

# region Environment setup
function if_enabled() {
	local TS_ENABLED
	TS_ENABLED=$(git config --get ts.enabled)

	if [[ ${TS_ENABLED} == "true" ]]; then
		# shellcheck disable=SC2068
		$@
		exit $?
	fi
}

function in_environment() {
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
	local TS_REQUEST_OPTIONS

	local TS_RESPONSE_FILE
	local TS_RESPONSE_OPTIONS
	local TS_RESPONSE_VERIFY

	if [[ -z ${TS_ENVIRONMENT_SET+x} ]]; then
		TS_BRANCH_PREFIX=$(git config ts.branch.prefix)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.branch.prefix" to set the signing branch prefix'
			RETURN=2
		fi
		TS_COMMIT_PREFIX=$(git config ts.commit.prefix)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.commit.prefix" to set the signing commit message prefix'
			RETURN=2
		fi

		TS_DIFF_NOTICE=$(git config ts.diff.notice)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.diff.notice" to set the notice in the diff header'
			RETURN=2
		fi
		TS_DIFF_FILE=$(git config ts.diff.file)
		if [ $? -ne 0 ]; then
			echo 'run "git config ts.diff.file" to set the name of the generated diff file'
			RETURN=2
		fi
		TS_DIFF_TYPE=$(git config ts.diff.type)
		if [ $? -ne 0 ]; then
			echo 'run "git config ts.diff.type" to set how the diff is created'
			RETURN=2
		fi

		TS_SERVER_DIRECTORY=$(git config ts.server.directory)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.server.directory" to set the directory name of the the timestamping.sh server configs'
			RETURN=2
		fi
		TS_SERVER_URL=$(git config ts.server.url)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.server.url" to set the name of the file containing the timestamping.sh server url'
			RETURN=2
		fi
		TS_SERVER_CERTIFICATE=$(git config ts.server.certificate)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.server.certificate" to set the name of the timestamping.sh server certificate file'
			RETURN=2
		fi

		TS_REQUEST_FILE=$(git config ts.request.file)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.request.file" to set the name of the timestamp request file'
			RETURN=2
		fi
		TS_REQUEST_OPTIONS=$(git config ts.request.options)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.request.options" to set the options for creating the timestamp request file'
			RETURN=2
		fi

		TS_RESPONSE_FILE=$(git config ts.respone.file)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.response.file" to set the name of the timestamp response file'
			RETURN=2
		fi
		TS_RESPONSE_OPTIONS=$(git config ts.respone.options)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.response.options" to set the options for curling the timestamp response file'
			RETURN=2
		fi
		TS_RESPONSE_VERIFY=$(git config ts.respone.verify)
		if [ $? -ne 0 ]; then
			echo 'Run "git config ts.response.verify" to set whether the timestamp response file is verified after'
			RETURN=2
		fi

		if [[ ${RETURN} -ne 0 ]]; then
			return ${RETURN}
		fi

		TS_ENVIRONMENT_SET=
		# shellcheck disable=SC2068
		$@
		unset TS_ENVIRONMENT_SET
	else
		# shellcheck disable=SC2068
		$@
	fi
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

function verify_timestamp() {
	local IN_FILE=$1
	local QUERY_FILE=$2
	local CA_FILE=$3
	local DATA_FILE=$4
	# Verify timestamp against request
	if ! openssl ts -verify \
		-in "${IN_FILE}" \
		-queryfile "${QUERY_FILE}" \
		-CAfile "${CA_FILE}" \
		>/dev/null 2>/dev/null; then
		return 2
	fi

	# Verify timestamp against data
	if ! openssl ts -verify \
		-in "${IN_FILE}" \
		-data "${DATA_FILE}" \
		-CAfile "${CA_FILE}" \
		>/dev/null 2>/dev/null; then
		return 1
	fi

	return 0
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

	local SERVER_DIR
	local SERVER_URL

	SERVER_DIR=${SERVER_DIRECTORY#*${TS_SERVER_DIRECTORY}/}
	SERVER_DIR=${SERVER_DIR%/*}

	if [[ "${SERVER_DIR}" == "*" ]]; then
		return 4
	fi

	if [[ ! -f "${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" ]]; then
		return 4
	fi

	if [[ -f "${SERVER_DIRECTORY}/${TS_SERVER_URL}" ]]; then
		SERVER_URL=$(cat "${SERVER_DIRECTORY}/${TS_SERVER_URL}")
	else
		SERVER_URL="http://${SERVER_DIR}"
	fi
	hook_echo "Generating timestamp for ${SERVER_DIR} at ${SERVER_URL}"

	# Create timestamp request
	openssl ts -query \
		-data "${DATA_FILE}" \
		${TS_REQUEST_OPTIONS} \
		-out "${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
		>/dev/null 2>/dev/null || return 3

	# Get timestamp response
	curl --silent --header 'Content-Type: application/timestamp-query' \
		${TS_RESPONSE_OPTIONS} \
		--data-binary "@${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
		"${SERVER_URL}" \
		-o "${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
		>/dev/null || return 2

	# Run verifications if set
	if [[ "${TS_RESPONSE_VERIFY}" == "true" ]]; then
		local RESULT
		RESULT=$(verify_timestamp \
			"${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
			"${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
			"${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" \
			"${DATA_FILE}" \
			>/dev/null)
		case ${RESULT} in
		2)
			hook_echo "ERROR: Timestamp from ${SERVER_DIRECTORY} could not be verified against request!"
			;;
		1)
			hook_echo "ERROR: Timestamp from ${SERVER_DIRECTORY} could not be verified against diff!"
			;;
		0) ;;

		esac

		return ${RESULT}
	fi

	return 0
}

function commit_timestamps() {
	# Checkout signing branch
	if git rev-parse --verify "${SIGNING_BRANCH}" >/dev/null 2>/dev/null; then
		git checkout "${SIGNING_BRANCH}" >/dev/null 2>/dev/null
	else
		git checkout -b "${SIGNING_BRANCH}" >/dev/null 2>/dev/null
	fi

	# Add timestamp files to stage
	hook_echo "Committing timestamps"
	git add \
		--force \
		-- \
		"${TS_DIFF_FILE}" \
		${TS_SERVER_DIRECTORY}/* \
		>/dev/null 2>/dev/null

	# Commit timestamp files
	git commit \
		--message "${TS_COMMIT_PREFIX}${COMMIT_MSG}" \
		-- "${TS_DIFF_FILE}" "./${TS_SERVER_DIRECTORY}/" \
		>/dev/null 2>/dev/null
	touch "${GIT_DIR}/TIMESTAMP"
}

function create_and_commit_timestamps() {
	local SIG_COUNT=0

	# Loop for each timestamping server
	for d in "${TS_SERVER_DIRECTORY}/"*/; do
		create_timestamp "${TS_DIFF_FILE}" "${d}"
		case $? in
		0)
			SIG_COUNT=$((SIG_COUNT + 1))
			;;
		1)
			RETURN=1
			;;
		2)
			RETURN=1
			;;
		*) ;;

		esac
	done

	# Check if any signature was generated
	if [[ ${SIG_COUNT} -gt 0 ]] && [[ ${RETURN} -eq 0 ]]; then
		commit_timestamps
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
		git merge \
			--strategy=recursive \
			--strategy-option=theirs \
			"${COMMIT_ID}" \
			>/dev/null 2>/dev/null

		for d in "${TS_SERVER_DIRECTORY}/"*/; do
			local CERT0
			local CERT1
			local URL0
			local URL1
			CERT0=$(git rev-parse @~0:"${d}${TS_SERVER_CERTIFICATE}" 2>/dev/null)
			test $? -eq 0 || CERT0=""
			CERT1=$(git rev-parse @~1:"${d}${TS_SERVER_CERTIFICATE}" 2>/dev/null)
			test $? -eq 0 || CERT1=""
			URL0=$(git rev-parse @~0:"${d}${TS_SERVER_URL}" 2>/dev/null)
			test $? -eq 0 || URL0=""
			URL1=$(git rev-parse @~1:"${d}${TS_SERVER_URL}" 2>/dev/null)
			test $? -eq 0 || URL1=""

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

				if [[ -f "${TS_DIFF_FILE}" ]]; then
					create_timestamp "${TS_DIFF_FILE}" "${d}"
					case $? in
					0)
						SIG_COUNT=$((SIG_COUNT + 1))
						;;
					*)
						hook_echo "create_timestamp returned $?"
						;;
					esac
				fi
			fi

			# Removed TSAs
			if [[ ! -f "${d}/${TS_SERVER_CERTIFICATE}" ]] &&
				[[ ! -f ".${d}/${TS_SERVER_URL}" ]]; then
				hook_echo "Removing TSA ${SERVER_DIR} from branch ${b}"
				git rm "${d}/${TS_REQUEST_FILE}" \
					".${d}/${TS_RESPONSE_FILE}"
			fi
		done

		if [[ ${SIG_COUNT} -gt 0 ]]; then
			hook_echo "Committing timestamps"
			git add \
				--force \
				-- \
				"${TS_DIFF_FILE}" \
				${TS_SERVER_DIRECTORY}/* \
				>/dev/null 2>/dev/null

			git commit \
				--amend \
				--message "Applied updates from '${COMMIT_ID}' to ${b}" \
				-- "./${TS_SERVER_DIRECTORY}/"* \
				>/dev/null 2>/dev/null
		else
			hook_echo "No timestamps to amend"
			rm "${TS_DIFF_FILE}" >/dev/null
		fi
	done

	git checkout "${BRANCH}" >/dev/null 2>/dev/null
	maybe_unstash ${STASH}
}
