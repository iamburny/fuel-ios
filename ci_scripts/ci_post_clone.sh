#!/bin/sh
set -e

# Xcode Cloud clones straight from git, which never includes gitignored secrets
# (Config/Secrets.xcconfig, FuelTracker/Resources/GoogleService-Info.plist — see CLAUDE.md's
# "Local secrets setup"). Secrets.xcconfig's absence degrades gracefully (its `#include?` is
# optional), but GoogleService-Info.plist is wired into an actual Copy Files build phase that
# hard-fails the archive with "Build input file cannot be found" if it's missing. Reconstruct both
# here from Environment Variables configured on the Xcode Cloud workflow (App Store Connect ->
# Xcode Cloud -> workflow -> Environment -> Environment Variables), each added as a Secret,
# base64-encoded so a whole file's contents survive as one env var value. Silently skipped (not an
# error) if a variable isn't set, so PR-validation workflows without secrets configured still run.

if [ -n "$GOOGLE_SERVICE_INFO_PLIST_BASE64" ]; then
  mkdir -p "$CI_PRIMARY_REPOSITORY_PATH/FuelTracker/Resources"
  echo "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > "$CI_PRIMARY_REPOSITORY_PATH/FuelTracker/Resources/GoogleService-Info.plist"
  echo "ci_post_clone.sh: wrote GoogleService-Info.plist"
else
  echo "ci_post_clone.sh: GOOGLE_SERVICE_INFO_PLIST_BASE64 not set, skipping (archive will fail without it)"
fi

if [ -n "$SECRETS_XCCONFIG_BASE64" ]; then
  mkdir -p "$CI_PRIMARY_REPOSITORY_PATH/Config"
  echo "$SECRETS_XCCONFIG_BASE64" | base64 --decode > "$CI_PRIMARY_REPOSITORY_PATH/Config/Secrets.xcconfig"
  echo "ci_post_clone.sh: wrote Config/Secrets.xcconfig"
else
  echo "ci_post_clone.sh: SECRETS_XCCONFIG_BASE64 not set, skipping (build succeeds but Google Sign-In/Maps/Unleash degrade to their no-op state)"
fi
