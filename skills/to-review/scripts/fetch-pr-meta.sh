#!/bin/bash
# 특정 PR의 리뷰-대기 메타데이터를 한 줄 JSON으로 출력한다. 조회 전용.
# 사용법: fetch-pr-meta.sh <owner/repo> <pr-number> [my-login]
#   my-login을 주면 gh api user 호출을 생략한다. fetch-review-queue.sh가 한 번만 조회해 넘긴다.
#
# elapsed 기준: 내가 리뷰어로 "요청된" 시점(timeline의 review_requested 이벤트).
# 팀 단위 요청 등으로 개인 요청 이벤트가 없으면 PR 생성 시점(createdAt)으로 폴백한다.
set -euo pipefail

repo="$1"
num="$2"
me="${3:-${GH_LOGIN:-$(gh api user --jq .login)}}"

pr=$(gh pr view "$num" --repo "$repo" \
  --json title,author,body,changedFiles,additions,deletions,createdAt,url,isDraft,baseRefName,headRefName,headRefOid)

# 같은 head 로 이미 쓴 보고서가 있으면 경로를 준다. 같은 커밋을 다시 리뷰하는 비용을 막기 위해서다.
head_sha=$(echo "$pr" | jq -r .headRefOid)
report="${HARDKIT_REVIEW_DIR:-$HOME/.hardkit/reviews}/$repo/$num-${head_sha:0:12}.md"
if [ -s "$report" ]; then cached="$report"; else cached=""; fi

# 로컬 저장소: 현재 디렉터리의 origin 이 이 저장소면 그것, 아니면 --repos-dir (기본: 현재 디렉터리의 부모) 아래 레포명 폴더.
repos_dir="${HARDKIT_REPOS_DIR:-$(dirname "$PWD")}"
name="${repo#*/}"
local_path=""
matches_repo() { git -C "$1" remote get-url origin 2>/dev/null | grep -qiE "[:/]${repo}(\.git)?/?$"; }
if matches_repo "$PWD"; then local_path="$PWD"
elif [ -d "$repos_dir/$name" ] && matches_repo "$repos_dir/$name"; then local_path="$repos_dir/$name"
fi

# 타임라인이 100건을 넘는 PR에서도 요청 시각을 놓치지 않도록 끝까지 읽는다.
rr=$(gh api "repos/$repo/issues/$num/timeline?per_page=100" --paginate \
  --jq ".[] | select(.event==\"review_requested\" and .requested_reviewer.login==\"$me\") | .created_at" \
  2>/dev/null | tail -n 1 || true)

created=$(echo "$pr" | jq -r .createdAt)
base="${rr:-$created}"

# ISO8601(UTC) → epoch. macOS(BSD date) 우선, 실패 시 GNU date 폴백.
to_epoch() {
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null
}
base_epoch=$(to_epoch "$base")
now=$(date -u +%s)
secs=$(( now - base_epoch ))
[ "$secs" -lt 0 ] && secs=0
total_hours=$(( secs / 3600 ))
days=$(( secs / 86400 ))
hours=$(( (secs % 86400) / 3600 ))
if [ "$days" -gt 0 ]; then
  elapsed="${days}일 ${hours}시간"
else
  elapsed="${hours}시간"
fi

if [ -n "$rr" ]; then source="review_requested"; else source="created"; fi

echo "$pr" | jq -c \
  --arg repo "$repo" \
  --arg num "$num" \
  --arg base "$base" \
  --arg elapsed "$elapsed" \
  --arg source "$source" \
  --arg cached "$cached" \
  --arg local_path "$local_path" \
  --arg report "$report" \
  --arg with_body "${HARDKIT_WITH_BODY:-0}" \
  --argjson total_hours "$total_hours" \
  '{
    repo: $repo,
    number: ($num | tonumber),
    title: .title,
    author: .author.login,
    body: (if $with_body == "1" then (.body // "" | .[0:600]) else null end),
    changedFiles: .changedFiles,
    additions: .additions,
    deletions: .deletions,
    url: .url,
    isDraft: .isDraft,
    baseRefName: .baseRefName,
    headRefName: .headRefName,
    headRefOid: .headRefOid,
    localPath: (if $local_path == "" then null else $local_path end),
    reportPath: $report,
    cachedReport: (if $cached == "" then null else $cached end),
    createdAt: .createdAt,
    reviewRequestedAt: $base,
    elapsedSource: $source,
    elapsed: $elapsed,
    elapsedHours: $total_hours
  }'
