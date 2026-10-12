---
name: to-review
description: >
  내가 리뷰어로 등록된 열린 PR을 전부 모아, 대기 오래된 순으로 보여 준 뒤 PR마다 서브에이전트를 띄워
  review-pr 스킬로 끝까지 리뷰하고 결과를 한 표로 종합하는 스킬. "리뷰 큐 돌려줘", "내 리뷰 대기 PR 다 봐줘",
  "리뷰할 거 뭐 있어", "밀린 리뷰 처리하자", "리뷰 요청 온 거 정리해줘", "review queue"처럼 리뷰 대상 PR을
  한꺼번에 다루려는 요청이면 반드시 이 스킬을 사용한다. 목록만 보고 싶으면 --list-only 를 쓴다.
  PR 하나를 지목해 리뷰해 달라는 요청은 review-pr 스킬이 담당한다.
  사용자가 명시적으로 요청하기 전에는 GitHub에 코멘트·리뷰·approve를 남기지 않는다.
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/fetch-review-queue.sh)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/fetch-review-queue.sh *)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/summarize-reports.sh *)
---

# to-review — 리뷰 큐를 한 번에 돌린다

내가 리뷰어인 열린 PR을 모아 **대기 오래된 순으로 보여 주고**, PR마다 서브에이전트를 하나씩 띄워 **`review-pr` 스킬로 리뷰**한 뒤, 결과를 **한 표로 종합**한다. 리뷰 하나하나의 절차와 보고 형식은 `review-pr`이 정하고, 이 스킬은 그것을 여러 PR에 병렬로 돌리고 모으는 일만 한다.

리뷰 큐는 오래 기다린 PR이 위에 오도록 정렬한다. 대기가 길수록 작성자가 막혀 있을 가능성이 크기 때문이다.

이 스킬은 자주, 같은 큐에 대해 반복 실행된다. 그래서 **같은 커밋을 두 번 리뷰하지 않고**, **보고서는 파일에 두고 터미널에는 요약만** 낸다. 전문은 파일 경로로 열어 보면 되고, 17건 전문을 터미널에 다시 찍는 것은 읽히지도 않으면서 출력 토큰만 쓴다.

## 옵션

| 옵션 | 설명 |
|---|---|
| `--repo <owner/repo>` | 특정 저장소의 PR만 |
| `--limit N` | 대기 오래된 순으로 상위 N건만 리뷰. 나머지는 목록에만 표시 |
| `--list-only` | 리뷰 없이 목록만 |
| `--fresh` | 같은 head 의 저장된 보고서가 있어도 무시하고 다시 리뷰 |
| `--full` | 종합 출력에 보고서 전문을 함께 싣는다 (기본은 요약 + 파일 경로) |

## 절차

### 1) 큐 조회

`${CLAUDE_SKILL_DIR}/scripts/fetch-review-queue.sh` 를 실행한다. `--repo <owner/repo>` 와 `--list-only` 는 그대로 넘긴다. (권한 자동 승인을 받으려면 이 경로 그대로, `bash` 프리픽스나 파이프 없이 실행한다.) 이 스크립트는 PR 저장소의 로컬 클론을 찾기 위해 **현재 디렉터리와 그 부모**를 보므로, 저장소들을 모아 둔 폴더나 그중 하나 안에서 실행하는 것이 좋다.

스크립트가 `gh`·`jq` 확인, 로그인 조회, PR별 메타데이터 병렬 조회, 로컬 저장소 탐색, 저장된 보고서 확인, 정렬까지 끝내고 JSON 하나를 준다. 추가로 `gh` 를 직접 조합할 필요가 없다.

```json
{"me": "login", "total": 15, "cached": 2, "prs": [{"repo", "number", "title", "author", "url", "isDraft",
  "baseRefName", "headRefName", "headRefOid", "changedFiles", "additions", "deletions",
  "elapsed": "8일 21시간", "elapsedHours": 213, "elapsedSource": "review_requested" | "created",
  "localPath": "/path/to/clone" | null, "reportPath": "~/.hardkit/reviews/owner/repo/123-<sha12>.md",
  "cachedReport": "<reportPath>" | null, "body": "(--list-only 일 때만)"}]}
```

- `prs` 는 이미 `elapsedHours` 내림차순이다. `elapsedSource` 가 `created` 면 개인 리뷰 요청 이벤트를 못 찾아 PR 생성 시각으로 잰 근사치다.
- `cachedReport` 가 있으면 **같은 head 커밋을 이미 리뷰한 보고서**다. `--fresh` 가 아니면 에이전트를 띄우지 않고 그 파일을 쓴다.
- `localPath` 가 null 이면 그 PR은 diff 만으로 리뷰된다 (호출부 미확인).

`total` 이 0이면 `리뷰 대기 중인 PR이 없습니다. 🎉` 한 줄만 출력하고 끝낸다.

### 2) 목록 먼저 보여 주기

리뷰는 PR당 수 분이 걸린다. 사용자가 그동안 큐 전체를 파악할 수 있도록 목록을 먼저 출력한다.

```markdown
## 📋 리뷰 대기 PR — {N}건 · 대기 오래된 순{ · 저장된 보고서 M건}

| # | PR | 대기 | 변경 | 제목 |
|---|---|---|---|---|
| 1 | [{repo}#{number}]({url}) | {🔴/🟠/🟢} {elapsed} | {changedFiles} files · +{additions}/−{deletions} | {[Draft] }{♻️ }{제목에서 티켓 접두사를 뺀 것} |
```

- `{repo}` 는 `nameWithOwner` 의 뒷부분만. `−` 는 U+2212.
- 긴급도: `elapsedHours ≥ 72` 🔴, `≥ 24` 🟠, 그 미만 🟢. `elapsedSource == "created"` 면 `elapsed` 뒤에 `~` 를 붙인다.
- `cachedReport` 가 있고 `--fresh` 가 아니면 제목 앞에 ♻️. 리뷰를 다시 돌리지 않는다는 뜻이다.
- `--limit N` 이면 N+1번째부터는 `(목록만)` 을 제목 끝에 붙인다.

`--list-only` 면 여기서 끝낸다. 이때는 제목 대신 **본문을 읽어 만든 한 줄 요약**을 쓴다. 제목이 티켓 번호뿐이어도 열어 보지 않고 감을 잡게 하는 것이 목록 뷰의 가치다. 본문이 비었으면 제목을 정제해 쓰고, 지어내지 않는다. 마지막 줄에 "목록만 조회했습니다. 리뷰하려면 `--list-only` 없이 다시 실행해 주세요." 를 적는다.

### 3) PR마다 서브에이전트로 review-pr 실행

리뷰 대상은 `--limit` 적용 후, `cachedReport` 가 없는 것(또는 `--fresh`)이다. 각각에 대해 **서브에이전트를 하나씩, 한 메시지에서 동시에** 띄운다. 8건을 넘으면 6~8건씩 나눠 띄우고 앞 묶음이 끝나는 대로 다음을 띄운다. 한 번에 너무 많이 띄우면 같은 저장소에 대한 `git fetch` 가 몰려 느려진다.

각 에이전트에게는 아래 틀을 그대로 채워 넘긴다. 에이전트는 이 세션을 볼 수 없으므로 필요한 것을 전부 프롬프트에 담는다.

````
다음 PR을 리뷰하라.
- 스킬: {CLAUDE_SKILL_DIR의 부모}/review-pr/SKILL.md 를 먼저 읽고 그대로 따른다. 그 파일의 ${CLAUDE_SKILL_DIR} 는 {CLAUDE_SKILL_DIR의 부모}/review-pr 를 뜻한다.
- 대상: {owner/repo} PR #{number} ({url})
- 준비: {CLAUDE_SKILL_DIR의 부모}/review-pr/scripts/prepare-pr.sh {owner/repo} {number} --work {스크래치 디렉터리}/{레포명}-pr-{number}{ --local {localPath}} 를 첫 번째 명령으로 실행한다. 그 출력에 필요한 것이 다 있으니 gh·git 을 따로 조합하지 않는다.
- 보고서: 스킬 6)의 형식으로 prepare-pr 이 알려 준 report 경로에 저장한다. 파일이 이 리뷰의 결과물이다.
- 최종 메시지: 저장한 파일에서 `## PR #` 줄, `**목적**`·`**목적 대비 구현**`·`**결론**` 줄, `### n. [..]` 이슈 제목 줄만 그대로 옮기고 마지막 줄에 `report: {경로}` 를 적는다. 그 외 인사말·작업 메모·전문은 넣지 않는다. 전문은 파일로 읽는다.
- 제약: GitHub에 아무것도 쓰지 않는다 (gh pr comment / gh pr review / gh api 의 쓰기 호출 금지). 로컬 저장소의 작업 트리·브랜치·stash 를 건드리지 않는다 (fetch 와 워크트리 추가만 허용). 끝나면 prepare-pr 이 알려 준 cleanup 명령을 실행한다. 진행 중에 나(메인)에게 메시지를 보내지 않는다. 결과는 최종 메시지와 파일로만 전달한다.
````

`{localPath}` 는 큐 JSON 의 값이다. null 이면 `--local` 을 빼고 "로컬 저장소 없음 — diff만으로 진행하고 보고서에 호출부 미확인을 명시" 한 줄을 덧붙인다.

에이전트에 이름을 붙이는 것은 선택이다. 환경에 따라 이름 지정이 거부되면 이름 없이 다시 띄운다.

**완료 처리.** 에이전트가 끝나면 최종 메시지의 요약 줄을 그 PR의 결과로 기록한다. 완료 알림에 본문이 비어 오면(전달 실패) 에이전트에게 되묻지 말고 큐 JSON 의 `reportPath` 를 `${CLAUDE_SKILL_DIR}/scripts/summarize-reports.sh <reportPath>` 로 읽는다. 파일도 없으면 4)의 실패 처리로 넘긴다. 리뷰를 다시 돌리지는 않는다. 비용이 크고 결과는 이미 있거나, 없더라도 다시 돈다고 생기지 않기 때문이다.

진행 상황은 한 줄로만 알린다 (예: `#1592 완료 (8/17)`). 에이전트가 보낸 중간 메시지에는 답하지 않는다.

**저장된 보고서.** `cachedReport` 가 있는 PR 전부를 `${CLAUDE_SKILL_DIR}/scripts/summarize-reports.sh <경로1> <경로2> ...` 한 번으로 읽어 같은 요약 줄을 얻는다. 에이전트를 띄우는 것과 같은 턴에 하면 기다림이 없다.

### 4) 종합 출력

모든 에이전트가 끝나면 아래 순서로 출력한다. 요약 표가 먼저 와야 사용자가 어디부터 볼지 정할 수 있다.

```markdown
## ✅ 리뷰 결과 — {리뷰한 건수}건{ (저장된 보고서 M건 재사용)}

| # | PR | 대기 | 결론 | 이슈 | 가장 심각한 것 |
|---|---|---|---|---|---|
| 1 | [{repo}#{number}]({url}) | {elapsed} | {머지 가능 / 수정 후 머지 / 재검토 필요} | P0 {a} · P1 {b} · P2 {c} · P3 {d} | {최고 심각도 이슈의 제목 한 줄, 없으면 —} |

### 1. {repo}#{number} — {보고서 제목의 "리뷰 — " 뒤 부분}
**결론** {보고서의 결론 줄 그대로}
- [🟡 P1] {이슈 제목}
- [🟢 P3] {이슈 제목}
📄 {reportPath}

### 2. ...
```

- 순서는 2)의 목록과 같다 (대기 오래된 순).
- 결론·심각도·이슈 제목은 에이전트가 돌려준 줄(또는 summarize-reports 출력)을 **고치지 않고 그대로** 옮긴다. 이슈가 없으면 "이슈 없음" 한 줄.
- `--full` 이면 각 PR 절 아래에 보고서 파일 전문을 그대로 싣는다. 이때만 파일을 읽는다.
- 에이전트가 실패했거나 형식에 맞지 않는 결과를 돌려주면 그 PR 행의 결론에 `실패 — {이유 한 줄}` 을 적고 절에 에이전트의 마지막 메시지를 그대로 둔다. 조용히 빼지 않는다.
- `--limit` 으로 리뷰하지 않은 건이 있으면 표 아래에 `_(+M건은 --limit로 목록만 표시)_` 를 적는다.

맨 아래 두 줄:
*"보고서 전문은 📄 경로의 파일에 있습니다. 특정 PR 전문을 터미널에서 보려면 `/review-pr <번호>` 를, 전부 보려면 `--full` 을 쓰세요."*
*"GitHub에는 아무것도 남기지 않았습니다. 특정 PR에 코멘트로 올리려면 PR 번호와 함께 말씀해 주세요."*

## 원칙

- **쓰지 않는다.** 이 스킬도, 띄운 에이전트도 GitHub에 코멘트·리뷰·approve를 남기지 않는다. 사용자가 PR을 지목해 명시적으로 요청하면 그때 `review-pr` 의 7)단계 절차를 따른다.
- **리뷰 내용은 review-pr 의 것이다.** 이 스킬은 에이전트가 돌려준 결론과 이슈 제목을 요약 표로 묶을 뿐, 결론이나 심각도를 고쳐 쓰지 않는다. 표의 결론과 파일의 결론이 다르면 사용자가 신뢰할 수 없다.
- **목록을 먼저.** 리뷰가 끝나기를 기다리게 하지 말고 큐 전체를 먼저 보여 준다.
- **같은 커밋은 한 번만.** head 가 바뀌지 않은 PR은 저장된 보고서를 쓴다. 다시 보고 싶으면 `--fresh`.

## 스크립트

| 스크립트 | 용도 |
|---|---|
| `scripts/fetch-review-queue.sh [--repo owner/repo] [--list-only] [--repos-dir <폴더>]` | 큐 전체를 메타데이터·로컬 경로·저장된 보고서 포함 JSON 하나로 |
| `scripts/fetch-pr-meta.sh <owner/repo> <번호> [login]` | PR 하나의 대기 시간·변경 규모·보고서 경로. 위 스크립트가 내부에서 병렬 호출 |
| `scripts/summarize-reports.sh <보고서.md>...` | 저장된 보고서에서 요약 표에 쓸 줄만 추출 |

보고서 저장 위치는 `~/.hardkit/reviews/` (`HARDKIT_REVIEW_DIR`), 로컬 저장소 탐색 폴더는 현재 디렉터리의 부모 (`HARDKIT_REPOS_DIR` 또는 `--repos-dir`).
