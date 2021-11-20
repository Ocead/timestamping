#!/usr/bin/env bash

function update_timestamps() {
	local COMMIT_ID=$1
	git branch "${COMMIT_ID}" | tr -d " *"
}

# Creates a timestamp for a single TSA configuration
# Arguments:
# 	$1 Path to file to be timestamped
# 	$2 Path to the TSA configuration directory
#
# Returns:
# 	0 on success
# 	1 on verify error
# 	2 on reply error
# 	3 on query error
function create_timestamp() {
	local DATA_FILE=$1
	local SERVER_DIRECTORY=$2
	local SERVER_URL=$3

	# Create timestamp request
	openssl ts -query \
		-data "${DATA_FILE}" \
		${TS_REQUEST_OPTIONS} \
		-out ${SERVER_DIRECTORY}/${TS_REQUEST_FILE} \
		>/dev/null 2>/dev/null || return 3

	# Get timestamp response
	curl -s -S -H 'Content-Type: application/timestamp-query' \
		${TS_RESPONSE_OPTIONS} \
		--data-binary "@${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
		"${SERVER_URL}" \
		-o "${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
		>/dev/null || return 2

	# Run verifications if set
	if [[ "${TS_RESPONSE_VERIFY}" == "true" ]]; then
		# Verify timestamp against request
		if ! openssl ts -verify \
			-in "${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
			-queryfile "${SERVER_DIRECTORY}/${TS_REQUEST_FILE}" \
			-CAfile "${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" \
			>/dev/null 2>/dev/null; then
			hook_echo "ERROR: Timestamp from server ${TS_SERVER_URL} could not be verified against request!"
			return 1
		fi

		# Verify timestamp against data
		if ! openssl ts -verify \
			-in "${SERVER_DIRECTORY}/${TS_RESPONSE_FILE}" \
			-data "${DATA_FILE}" \
			-CAfile "${SERVER_DIRECTORY}/${TS_SERVER_CERTIFICATE}" \
			>/dev/null 2>/dev/null; then
			hook_echo "ERROR: Timestamp from server ${TS_SERVER_URL} could not be verified against diff!"
			return 1
		fi
	fi

	return 0
}
