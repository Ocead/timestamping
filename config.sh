#!/usr/bin/env bash

if [ $# -eq 0 ]; then
  echo "Call this script with the path of a git repository."
  exit 4
fi

# Copy hooks into target repository
GIT_DIR=$1
cp ./hooks/commit-msg "${GIT_DIR}/.git/hooks" || {
  echo 'ERROR: Could not copy the required files'
  exit 3
}

cd "${GIT_DIR}" || {
  echo 'ERROR: Could not enter the specified directory'
  exit 2
}

if [[ -d ".git" ]]; then
  echo "ERROR: Specified directory is not a git repository"
  exit 1
fi

# Set git config options
git config ts.enabled "true"

read -r -p "Enter the branch prefix [sig]: " BRANCH_PREFIX
git config ts.branch.prefix "${BRANCH_PREFIX:-"sig"}"

read -r -p "Enter the commit prefix [Timestamp for: ]: " COMMIT_PREFIX
git config ts.commit.prefix "${COMMIT_PREFIX:-"Timestamp for:"}"
read -r -p "Enter the commit options []: " COMMIT_OPTIONS
git config ts.commit.options "${COMMIT_OPTIONS:-""}"

read -r -p "Enter the diff notice [© $(git config --get user.name)]: " DIFF_NOTICE
git config ts.diff.notice "${DIFF_NOTICE:-"© $(git config --get user.name)"}"
read -r -p "Enter the diff file name [.diff]: " DIFF_FILE
git config ts.diff.file "${DIFF_FILE:-".diff"}"
read -r -p "Enter the diff type [staged]: " DIFF_TYPE
git config ts.diff.type "${DIFF_TYPE:-"staged"}"

read -r -p "Enter the TSA configuration directory name [rfc3161]: " SERVER_DIRECTORY
git config ts.server.directory "${SERVER_DIRECTORY:-"rfc3161"}"
read -r -p "Enter the TSA keychain file name [rfc3161]: " SERVER_CERTIFICATE
git config ts.server.certificate "${SERVER_CERTIFICATE:-"cacert.pem"}"
read -r -p "Enter the TSA url file name [rfc3161]: " SERVER_URL
git config ts.server.url "${SERVER_URL:-"url"}"

read -r -p "Enter the timestamp request file name [request.tsq]: " REQUEST_FILE
git config ts.request.file "${REQUEST_FILE:-"request.tsq"}"
read -r -p "Enter the timestamp request options [-cert -sha256 -no_nonce]: " REQUEST_OPTIONS
git config ts.request.options "${REQUEST_OPTIONS:-"-cert -sha256 -no_nonce"}"

read -r -p "Enter the timestamp response file name [response.tsr]: " RESPONSE_FILE
git config ts.respone.file "${RESPONSE_FILE:-"response.tsr"}"
read -r -p "Enter the timestamp response options []: " RESPONSE_OPTIONS
git config ts.respone.options "${RESPONSE_OPTIONS:-""}"
read -r -p "Enter whether timestamps should be verified [true]: " RESPONSE_VERIFY
git config ts.respone.verify "${RESPONSE_VERIFY:-"true"}"

# Ge currently checked out branch
BRANCH=$(git symbolic-ref --short HEAD)
if [ $? -ne 0 ]; then
  BRANCH=$(git config init.defaultBranch)
  if [ $? -ne 0 ]; then
    BRANCH="master"
  fi
fi

# Stash staged changed
git stash

# Checkout root signing branch
git checkout --orphan "$(git config --get ts.branch.prefix)"

# Create initial commit in root signing branch
touch "./$(git config --get ts.server.directory)/PLACE_TSA_CONFIGS_HERE"
git add "./$(git config --get ts.server.directory)/PLACE_TSA_CONFIGS_HERE"
git commit -m "Initial timestamping commit"

# Return to previous branch
if git rev-parse --verify "${BRANCH}"; then
  git checkout "${BRANCH}"
else
  git checkout --orphan "${BRANCH}"
fi

# Pop stashed changes
git stash pop

exit 0
