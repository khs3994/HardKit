#!/bin/bash
# PR 본문·이슈 코멘트·리뷰·인라인 리뷰 코멘트·변경 파일 목록을 JSON 하나로 모은다. 조회 전용.
# 사용법: fetch-pr-context.sh <owner/repo> <pr-number>
set -euo pipefail

repo="$1"
num="$2"

pr=$(gh pr view "$num" --repo "$repo" \
  --json number,title,body,author,baseRefName,headRefName,headRefOid,url,isDraft,state,createdAt,additions,deletions,changedFiles,files,labels)

comments=$(gh api "repos/$repo/issues/$num/comments?per_page=100" \
  --jq '[.[] | {author: .user.login, createdAt: .created_at, body: .body}]')

reviews=$(gh api "repos/$repo/pulls/$num/reviews?per_page=100" \
  --jq '[.[] | {author: .user.login, state: .state, submittedAt: .submitted_at, body: .body}]')

review_comments=$(gh api "repos/$repo/pulls/$num/comments?per_page=100" \
  --jq '[.[] | {id: .id, inReplyTo: .in_reply_to_id, author: .user.login, path: .path, line: (.line // .original_line), createdAt: .created_at, body: .body}]')

jq -n \
  --argjson pr "$pr" \
  --argjson comments "$comments" \
  --argjson reviews "$reviews" \
  --argjson reviewComments "$review_comments" \
  '$pr + {
    author: $pr.author.login,
    files: [$pr.files[] | .path],
    labels: [$pr.labels[] | .name],
    comments: $comments,
    reviews: $reviews,
    reviewComments: $reviewComments
  }'
