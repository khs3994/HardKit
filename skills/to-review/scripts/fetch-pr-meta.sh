#!/bin/bash
# 특정 PR의 리뷰-대기 메타데이터를 조회한다.
# Usage: fetch-pr-meta.sh <owner/repo> <pr-number>
# 출력: JSON 객체 (요약용 body + 변경 규모 + 리뷰 요청 시점 기준 경과 시간)
#
# elapsed 기준: 내가(@me) 리뷰어로 "요청된" 시점(timeline의 review_requested 이벤트).
# 팀 단위 요청 등으로 개인 요청 이벤트가 없으면 PR 생성 시점(createdAt)으로 폴백한다.
set -euo pipefail

repo="$1"
num="$2"
me="${GH_LOGIN:-$(gh api user --jq .login)}"

pr=$(gh pr view "$num" --repo "$repo" \
  --json title,author,body,changedFiles,additions,deletions,createdAt,url,isDraft)

# 내가 리뷰어로 요청된 가장 최근 시각 (없으면 빈 문자열)
# timeline은 오래된 순이고 review_requested는 보통 맨 앞(PR 생성 직후)에 있으므로,
# 끝까지 긁는 --paginate 대신 첫 한 페이지(최대 100개)만 단발로 가져온다 → API 호출 1회, 빠름.
rr=$(gh api "repos/$repo/issues/$num/timeline?per_page=100" \
  -q "[.[] | select(.event==\"review_requested\" and .requested_reviewer.login==\"$me\") | .created_at] | last" \
  2>/dev/null || echo "")
[ "$rr" = "null" ] && rr=""

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

echo "$pr" | jq \
  --arg repo "$repo" \
  --arg num "$num" \
  --arg base "$base" \
  --arg elapsed "$elapsed" \
  --arg source "$source" \
  --argjson total_hours "$total_hours" \
  '{
    repo: $repo,
    number: ($num | tonumber),
    title: .title,
    author: .author.login,
    body: (.body // "" | .[0:1500]),
    changedFiles: .changedFiles,
    additions: .additions,
    deletions: .deletions,
    url: .url,
    isDraft: .isDraft,
    createdAt: .createdAt,
    reviewRequestedAt: $base,
    elapsedSource: $source,
    elapsed: $elapsed,
    elapsedHours: $total_hours
  }'
