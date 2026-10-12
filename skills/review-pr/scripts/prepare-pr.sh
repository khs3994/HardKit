#!/usr/bin/env bash
# PR 리뷰 준비를 한 번에 끝낸다: gh 확인, PR 컨텍스트, diff, 워크트리, 코드 규칙 파일 탐색, 보고서 경로.
#
# usage: prepare-pr.sh <owner/repo> <번호> --work <작업 디렉터리> [--local <로컬 저장소 경로>]
#
# 결과물
#   <work>/context.json   본문·코멘트·리뷰·변경 파일 (fetch-pr-context.sh 출력)
#   <work>/diff.patch     gh pr diff 전문
#   <work>/src            --local 이 있으면 PR head 를 체크아웃한 워크트리
# stdout 에는 위 경로들과 요약, context.json 전문, diff 가 작으면 diff 전문을 찍는다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="${1:?owner/repo}"; num="${2:?PR 번호}"; shift 2
work=""; local_repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --work) work="$2"; shift 2 ;;
    --local) local_repo="$2"; shift 2 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 2 ;;
  esac
done
[ -n "$work" ] || { echo "--work <디렉터리> 가 필요합니다" >&2; exit 2; }
command -v gh >/dev/null || { echo "gh CLI가 필요합니다: brew install gh && gh auth login" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq가 필요합니다: brew install jq" >&2; exit 1; }

INLINE_DIFF_LINES=${HARDKIT_INLINE_DIFF_LINES:-400}
LARGE_FILES=${HARDKIT_LARGE_FILES:-40}
LARGE_LINES=${HARDKIT_LARGE_LINES:-1500}
review_root="${HARDKIT_REVIEW_DIR:-$HOME/.hardkit/reviews}"

mkdir -p "$work"
"$here/fetch-pr-context.sh" "$repo" "$num" > "$work/context.json"

ctx="$work/context.json"
head_sha=$(jq -r .headRefOid "$ctx")
base=$(jq -r .baseRefName "$ctx")
files=$(jq -r .changedFiles "$ctx")
adds=$(jq -r .additions "$ctx")
dels=$(jq -r .deletions "$ctx")
draft=$(jq -r .isDraft "$ctx")
state=$(jq -r .state "$ctx")
title=$(jq -r .title "$ctx")
mode="normal"
if [ "$files" -gt "$LARGE_FILES" ] || [ $((adds + dels)) -gt "$LARGE_LINES" ]; then mode="large"; fi

report="$review_root/$repo/$num-${head_sha:0:12}.md"
mkdir -p "$(dirname "$report")"

# 워크트리: FETCH_HEAD 대신 이름 있는 ref 를 써서, 같은 저장소에 여러 PR 이 동시에 fetch 해도 섞이지 않게 한다.
src="없음 — diff만으로 진행 (호출부 미확인)"
cleanup=""
if [ -n "$local_repo" ]; then
  if git -C "$local_repo" rev-parse --git-dir >/dev/null 2>&1; then
    ref="refs/hardkit/pr/$num"
    git -C "$local_repo" fetch -q origin "pull/$num/head:$ref" 2>&1 | tail -1 >&2 || true
    git -C "$local_repo" fetch -q origin "$base" 2>/dev/null || true
    if [ -d "$work/src" ] && git -C "$work/src" rev-parse --git-dir >/dev/null 2>&1; then
      git -C "$work/src" checkout -q --detach "$head_sha" 2>/dev/null || true
    else
      rm -rf "$work/src"
      git -C "$local_repo" worktree add -q --detach "$work/src" "$head_sha" 2>&1 | tail -1 >&2
    fi
    if [ "$(git -C "$work/src" rev-parse HEAD 2>/dev/null)" = "$head_sha" ]; then
      src="$work/src"
      cleanup="git -C \"$local_repo\" worktree remove --force \"$work/src\"; git -C \"$local_repo\" update-ref -d $ref"
    else
      src="없음 — 워크트리 생성 실패, diff만으로 진행 (호출부 미확인)"
    fi
  else
    src="없음 — $local_repo 는 git 저장소가 아님, diff만으로 진행 (호출부 미확인)"
  fi
fi

# diff: gh 가 300파일 넘는 PR 은 거부하므로 그때는 로컬 저장소의 git diff 로 대체한다.
diff_note=""
if ! gh pr diff "$num" --repo "$repo" > "$work/diff.patch" 2>"$work/diff.err"; then
  if [ -d "$work/src" ] && mb=$(git -C "$local_repo" merge-base "origin/$base" "$head_sha" 2>/dev/null); then
    git -C "$local_repo" diff "$mb" "$head_sha" > "$work/diff.patch"
    diff_note="(gh 거부 — 로컬 git diff $mb..head 로 대체)"
  else
    : > "$work/diff.patch"
    diff_note="(받지 못함: $(tr '\n' ' ' < "$work/diff.err" | cut -c1-160) — context.json 의 files 목록으로 범위만 본다)"
  fi
fi
rm -f "$work/diff.err"
diff_lines=$(wc -l < "$work/diff.patch" | tr -d ' ')

# 코드 규칙 파일: 저장소 안과 사용자 전역에서 흔한 위치만 찾는다. 읽을지는 에이전트가 줄 수로 판단한다.
rules=()
add_rule() { [ -f "$1" ] || return 0; rules+=("$3${1#$2}  ($(wc -l < "$1" | tr -d ' ')줄)"); }
is_guide() { case "$(basename "$(dirname "$1")")" in *guide*|*style*|*convention*|*rule*|*lint*|*code*) return 0 ;; *) return 1 ;; esac; }
if [ -d "$work/src" ]; then
  for f in CLAUDE.md AGENTS.md .gemini/styleguide.md .github/PULL_REQUEST_TEMPLATE.md; do add_rule "$work/src/$f" "$work/src/" ""; done
  for f in "$work/src"/.claude/skills/*/SKILL.md; do is_guide "$f" && add_rule "$f" "$work/src/" ""; done
fi
for f in "$HOME"/.claude/skills/*/SKILL.md; do is_guide "$f" && add_rule "$f" "$HOME/" "~/"; done

echo "== PR $repo #$num — $title =="
echo "head: $head_sha  base: $base  state: $state  draft: $draft"
echo "files: $files  +$adds/−$dels  diff: ${diff_lines}줄"
echo "mode: $mode"
echo "report: $report $( [ -f "$report" ] && echo '(이미 있음 — 같은 head 로 리뷰한 보고서. 다시 쓰지 말고 그대로 쓴다)' )"
echo "worktree: $src"
if [ -n "$cleanup" ]; then echo "cleanup: $cleanup"; fi
echo "context: $ctx"
echo "diff: $work/diff.patch $diff_note"
echo "code rules (워크트리 기준 상대 경로, ~/ 는 사용자 전역):"
if [ ${#rules[@]} -eq 0 ]; then echo "  (없음)"; else printf '  %s\n' "${rules[@]}"; fi

# diff 색인: 파일별 줄 범위. 큰 diff 를 파일 단위로 잘라 읽을 때 쓴다.
awk '/^diff --git/ { if (f) printf "%s  %d-%d  (+%d/-%d)\n", f, s, NR-1, a, d; f=$3; sub(/^a\//,"",f); s=NR; a=0; d=0 }
     /^\+[^+]/ { a++ } /^-[^-]/ { d++ }
     END { if (f) printf "%s  %d-%d  (+%d/-%d)\n", f, s, NR, a, d }' "$work/diff.patch" > "$work/diff-index.txt"
index_lines=$(wc -l < "$work/diff-index.txt" | tr -d ' ')

echo
if [ "$files" -gt 60 ]; then
  echo "== context.json (files 는 ${files}개라 뺐다. 목록은 $work/diff-index.txt) =="
  jq -c 'del(.files)' "$ctx"
else
  echo "== context.json =="
  jq -c . "$ctx"
fi

echo
if [ "$diff_lines" -le "$INLINE_DIFF_LINES" ]; then
  echo "== diff =="
  cat "$work/diff.patch"
elif [ "$index_lines" -le 60 ]; then
  echo "== diff 는 ${diff_lines}줄이라 파일로만 둔다. 파일별 줄 범위 (sed -n '시작,끝p' $work/diff.patch) =="
  sed 's/^/  /' "$work/diff-index.txt"
else
  echo "== diff 는 ${diff_lines}줄·${index_lines}파일. 파일별 줄 범위는 $work/diff-index.txt (grep 으로 찾아 sed -n 으로 읽는다). 디렉터리별 집계 =="
  awk '{ n=split($1, p, "/"); dir=(n>2 ? p[1]"/"p[2] : p[1]); c[dir]++; gsub(/[()+-]/, " ", $3); split($3, ad, "/"); a[dir]+=ad[1]; d[dir]+=ad[2] }
       END { for (k in c) printf "  %s  %d파일  (+%d/-%d)\n", k, c[k], a[k], d[k] }' "$work/diff-index.txt" | sort -t'	' -k1
fi
