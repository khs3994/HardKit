#!/bin/bash
# 내가 리뷰어로 등록된 열린 PR을 메타데이터까지 포함해 한 번에 가져온다. 조회 전용.
# 사용법: fetch-review-queue.sh [--repo owner/repo]
# 출력: {"me": "<login>", "total": N, "prs": [ ...대기 오래된 순... ]}
#
# 이전에는 목록 1회 + PR별 메타 N회를 따로 실행했고, 메타 스크립트마다 gh api user를 다시 불렀다.
# 이제 로그인은 한 번만 조회하고 PR별 조회는 병렬로 돌리므로, 호출자는 이 스크립트 하나만 실행하면 된다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo_filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo_filter="$2"; shift 2 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null || { echo "gh CLI가 필요합니다: brew install gh && gh auth login" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq가 필요합니다: brew install jq" >&2; exit 1; }

me=$(gh api user --jq .login)

search_args=(--review-requested=@me --state=open --json repository,number --limit 100)
[ -n "$repo_filter" ] && search_args+=(--repo "$repo_filter")

list=$(gh search prs "${search_args[@]}")
total=$(echo "$list" | jq 'length')

if [ "$total" -eq 0 ]; then
  jq -n --arg me "$me" '{me: $me, total: 0, prs: []}'
  exit 0
fi

# PR별 메타데이터를 최대 6개씩 병렬로 조회한다. 결과는 임시 파일에 모은다.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
i=0
while read -r r n; do
  i=$((i+1))
  "$here/fetch-pr-meta.sh" "$r" "$n" "$me" > "$tmp/$i.json" 2>"$tmp/$i.err" &
  if [ $((i % 6)) -eq 0 ]; then wait; fi
done < <(echo "$list" | jq -r '.[] | "\(.repository.nameWithOwner) \(.number)"')
wait

# 실패한 PR이 있으면 stderr로 알리되, 나머지 결과는 그대로 낸다.
for e in "$tmp"/*.err; do
  [ -s "$e" ] && { echo "경고: $(basename "$e" .err)번째 PR 조회 실패:" >&2; cat "$e" >&2; }
done

cat "$tmp"/*.json | jq -s --arg me "$me" --argjson total "$total" \
  '{me: $me, total: $total, prs: sort_by(-.elapsedHours)}'
