#!/bin/bash
# 내가 리뷰어로 등록된 열린 PR 목록을 조회한다.
# 출력: JSON 배열 (repository, number, title, url, createdAt, author, labels, isDraft)
set -euo pipefail

gh search prs \
  --review-requested=@me \
  --state=open \
  --json repository,number,title,url,createdAt,author,labels,isDraft \
  --limit 100
