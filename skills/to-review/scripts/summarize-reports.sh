#!/bin/bash
# 저장된 review-pr 보고서에서 요약 표에 필요한 줄만 뽑는다: 제목, 목적, 목적 대비 구현, 결론, 이슈 제목.
# usage: summarize-reports.sh <보고서.md>...
set -euo pipefail
for f in "$@"; do
  echo "=== $f"
  if [ ! -s "$f" ]; then echo "(파일 없음 또는 비어 있음)"; continue; fi
  grep -E '^## PR #|^\*\*(목적|목적 대비 구현|결론)\*\*|^### [0-9]+\. \[' "$f" || echo "(형식에 맞는 줄 없음)"
done
