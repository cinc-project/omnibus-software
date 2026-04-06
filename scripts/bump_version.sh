#!/bin/bash
#
# Bumps the VERSION file using YY.MM.BUILD format and creates a git tag.
# Intended to be called from GitLab CI on merges to stable/cinc.
#
set -euo pipefail

YEAR=$(date +"%y" | sed -e 's/^0//')
MONTH=$(date +"%m" | sed -e 's/^0//')
OLD_BUILD=$(cut -f3 -d. < VERSION)
NEW_BUILD=$((OLD_BUILD + 1))
NEW_VERSION="${YEAR}.${MONTH}.${NEW_BUILD}"

echo "Bumping version from $(cat VERSION) to ${NEW_VERSION}"
echo "${NEW_VERSION}" > VERSION

git config user.name "Cinc CI"
git config user.email "ci@cinc.sh"
git add VERSION
git commit -m "Bump version to ${NEW_VERSION}"
git tag "${NEW_VERSION}"
git push "https://gitlab-ci-token:${CI_JOB_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" HEAD:${CI_COMMIT_BRANCH} --tags
