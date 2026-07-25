#!/usr/bin/env bash
# How many people are actually using Sono.
#
# Reads only counters that already exist. Sono itself has no telemetry and this
# does not add any: every number here is either a GitHub counter or a request
# the app was already making.
set -euo pipefail

OWNER=aeyar-studio

printf '\n\033[1mFirst launches\033[0m\n'
# The model archive downloads exactly once per machine: ModelDownloader.ensureModel
# returns early once the files exist. So this counts machines that installed Sono
# AND opened it, which is a truer "users" number than DMG downloads.
gh api "repos/$OWNER/sono-models/releases" \
  --jq '.[].assets[] | "  \(.download_count)\t\(.name)"'

printf '\n\033[1mRepo interest (last 14 days)\033[0m\n'
gh api "repos/$OWNER/sono/traffic/views"  --jq '"  \(.uniques)\tunique visitors (\(.count) views)"'
gh api "repos/$OWNER/sono/traffic/clones" --jq '"  \(.uniques)\tunique cloners (\(.count) clones)"'
gh api "repos/$OWNER/sono" --jq '"  \(.stargazers_count)\tstars\n  \(.forks_count)\tforks"'

printf '\n\033[1mTop referrers\033[0m\n'
# Captured first, not piped: a pipeline reports the last command's status, so
# `gh ... | head || echo none` never falls through on an empty result.
referrers=$(gh api "repos/$OWNER/sono/traffic/popular/referrers" \
  --jq '.[] | "  \(.uniques)\t\(.referrer)"' 2>/dev/null | head -5)
printf '%s\n' "${referrers:-  none yet}"

printf '\n\033[2mActive installs = daily /appcast.xml hits (each install checks\n'
printf 'once every 86400s and sends nothing identifying). Cloudflare dashboard →\n'
printf 'Workers → sono → Observability.\033[0m\n\n'
