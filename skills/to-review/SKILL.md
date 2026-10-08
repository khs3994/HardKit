---
name: to-review
description: >
  내가 리뷰어로 등록된 열린 PR을 한눈에 보는 가벼운 목록 스킬. 각 PR을 (1) 본문을 읽어 만든 한줄요약, (2) 리뷰 요청 시점부터의 대기 경과 시간,
  (3) 변경 파일 규모(개수 + 증감 라인) 3가지로 정리해 대기 오래된 순으로 보여준다.
  "리뷰할 PR 목록", "리뷰 대기 PR 리스트", "내 리뷰 PR 보여줘", "리뷰 대기 얼마나 됐어", "리뷰 큐", "review list"처럼
  리뷰 대상 PR을 빠르게 훑어보고 싶다고 할 때 반드시 이 스킬을 사용할 것.
  이 스킬은 조회·요약만 하는 가벼운 목록 뷰이며, 코드 리뷰 수행·approve 판정·우선순위 점수 같은 무거운 작업은 하지 않고 GitHub에도 아무것도 쓰지 않는다.
allowed-tools:
  - Bash(command -v gh)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/fetch-review-prs.sh)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/fetch-pr-meta.sh *)
---

# to-review — 리뷰 대기 PR 한눈에 보기

내가 리뷰어로 등록된 열린 PR을 훑어, 각 PR을 **한줄요약 · 대기 경과 시간 · 변경 파일 규모** 3가지로 정리해 보여준다. **조회·요약 전용**이며 GitHub에 코멘트/approve/review를 절대 남기지 않는다.

이 스킬은 "지금 내가 리뷰해야 할 게 뭐가 있고, 어떤 게 얼마나 밀려 있나"를 빠르게 파악하기 위한 **가벼운 목록 뷰**다. 실제 코드 리뷰나 approve 판정, 우선순위 점수 매기기 같은 무거운 단계는 하지 않고, 대기 오래된 순으로 훑어보게만 한다.

## 옵션

| 옵션 | 설명 |
|---|---|
| `--repo <owner/repo>` | 특정 레포의 PR만 필터링 (예: `--repo fan-maum/trot-android`) |
| `--limit N` | 상세 조회할 PR 개수 상한 (기본: 전부). 목록이 아주 많을 때 상위 N건만 |
| 옵션 없음 | 리뷰 요청된 전체 열린 PR |

## 스크립트

GitHub 조회는 직접 `gh api`를 조합하지 말고 아래 스크립트를 사용한다:

| 스크립트 | 용도 | 사용법 |
|---|---|---|
| `fetch-review-prs.sh` | 내가 리뷰어인 열린 PR 목록 | `${CLAUDE_SKILL_DIR}/scripts/fetch-review-prs.sh` |
| `fetch-pr-meta.sh` | 특정 PR의 요약용 본문 + 변경 규모 + 대기 경과 시간 | `${CLAUDE_SKILL_DIR}/scripts/fetch-pr-meta.sh <owner/repo> <pr-number>` |

> **호출 규칙(권한 자동 승인과 직결).** 이 스킬은 프론트매터 `allowed-tools`로 위 두 스크립트 실행을 그 턴 동안 프롬프트 없이 자동 승인받는다. 그 승인이 실제로 걸리려면 **본문에 적힌 그대로**, 즉 `${CLAUDE_SKILL_DIR}/scripts/…` 경로를 그대로 써서(변수 이름 그대로, `bash` 프리픽스 없이 직접) 실행해야 한다. 상대경로(`scripts/…`)로 바꾸거나, `bash`로 감싸거나, 파이프(`| jq`)·리다이렉트를 붙이면 자동 승인 패턴과 어긋나 프롬프트가 뜬다. 스크립트는 이미 실행권한(`+x`)이 있고 깔끔한 JSON을 stdout으로 내보내므로, 그냥 실행하고 그 출력을 직접 읽으면 된다.

`fetch-pr-meta.sh`가 반환하는 `elapsed`(예: `"1일 5시간"`)와 `changedFiles`/`additions`/`deletions`는 **이미 계산된 값**이므로 그대로 표에 쓴다. 경과 시간은 스크립트가 timeline에서 "내가 리뷰어로 요청된 시각"을 찾아 계산하며, 개인 요청 이벤트가 없으면(팀 단위 요청 등) PR 생성 시각으로 폴백한다(`elapsedSource` 필드로 구분 가능).

## 실행 플로우

### Step 0: 사전 조건
`command -v gh`를 실행해 `gh` CLI 설치 여부를 확인한다. 실패(비어 있음)하면 *"gh CLI가 필요합니다: `brew install gh && gh auth login`"* 라고 안내하고 멈춘다. (이 명령 하나만 실행 — `|| {...}` 같은 복합형으로 감싸지 말 것. 자동 승인 패턴과 어긋난다.)

### Step 1: PR 목록 조회
`${CLAUDE_SKILL_DIR}/scripts/fetch-review-prs.sh`를 실행해 리뷰 요청된 PR 목록(JSON 배열)을 가져오고, 그 출력을 직접 읽는다.
`--repo`가 주어졌으면 읽은 결과에서 `repository.nameWithOwner`가 일치하는 것만 남긴다.
목록이 비어 있으면 "리뷰 대기 중인 PR이 없습니다."라고 알리고 종료한다.

### Step 2: PR별 메타데이터 수집 (병렬)
목록의 각 PR에 대해 `${CLAUDE_SKILL_DIR}/scripts/fetch-pr-meta.sh <owner/repo> <number>`를 실행한다.
PR이 여러 건이면 **병렬로** 실행해 속도를 높인다. `--limit N`이 있으면 상위 N건만 조회하고, 생략된 건수는 결과 하단에 "(+M건 생략)"으로 밝힌다 — 조용히 잘라내지 않는다.

### Step 3: 한줄요약 생성
각 PR의 `title` + `body`를 읽고, **"무엇을 왜 바꾸는 PR인지" 한국어 한 줄**로 요약한다. 이게 이 스킬의 핵심 가치다 — 제목이 티켓번호(`[TM-8405]`)나 불친절한 문구여도 리뷰어가 열어보지 않고 감을 잡게 해주는 것.

요약 원칙:
- **제목 복붙 금지.** 제목이 이미 충분히 설명적이면 다듬어 쓰되, 티켓 접두사·군더더기는 걷어낸다.
- **본문 우선.** body에 배경/변경내용이 있으면 그걸 근거로 요약한다. body가 비었으면 제목을 정제해 쓰고, 확신이 없으면 지어내지 말고 제목 기반으로만 적는다.
- **길이는 한 줄(대략 40자 이내).** 표 셀에 들어가야 한다. 명사형으로 끝내도 좋다.
- 예: `[TM-8405] 일기 목록/피드/프로필 좋아요 즉시 반영 및 아이콘 크기 통일` → `일기 좋아요를 API 응답 전 즉시 반영 + 좋아요 아이콘 크기 통일`

### Step 4: 출력 (카드형 리스트)
`elapsedHours` **내림차순(가장 오래 기다린 PR이 위)**으로 정렬해, PR마다 한 블록씩 카드형으로 출력한다. 대기가 길수록 먼저 처리해야 하므로 이 순서가 리뷰 큐로서 자연스럽다.

**정확히 이 템플릿을 따른다:**

```markdown
## 📋 리뷰 대기 PR — {N}건 · 대기 오래된 순

**{i}. [{repo}#{number}]({url})** · {긴급도} {elapsed}
{한줄요약}
`{changedFiles} files` · `+{additions}/−{deletions}`
```

`{i}`는 1부터의 순번, `{repo}`는 `nameWithOwner`의 레포명(뒷부분)만 짧게 쓴다. 블록 사이는 빈 줄 하나로 띄운다. 각 필드 채우는 규칙:

- **긴급도 이모지** — `elapsedHours` 기준: `elapsedHours ≥ 72` → 🔴, `≥ 24` → 🟠, 그 미만 → 🟢. (대기 시간을 색으로 한눈에 보게 하는 장치다.)
- **대기(`elapsed`)** — 스크립트가 준 값 그대로. 단 `elapsedSource == "created"`(개인 리뷰 요청 이벤트를 못 찾아 PR 생성 시각으로 폴백)면 값 뒤에 `~`를 붙여 근사치임을 알린다. 예: `🟠 2일 3시간~`.
- **한줄요약** — Step 3에서 만든 한 줄. `isDraft`가 true면 맨 앞에 `**[Draft]** `를 붙인다.
- **변경** — `` `{changedFiles} files` · `+{additions}/−{deletions}` `` (증감은 유니코드 −(U+2212) 사용, 백틱 코드 스팬으로 감싼다).

맨 아래에 한 줄 덧붙인다: *"조회·요약 전용입니다 — 실제 코드 리뷰나 approve는 하지 않습니다."*
`--limit`로 생략된 건이 있으면 그 앞 줄에 `_(+M건은 --limit로 생략됨)_`을 먼저 적는다.

**완성 예시** (실제 데이터):

```markdown
## 📋 리뷰 대기 PR — 5건 · 대기 오래된 순

**1. [allen-semomun-aos#314](https://github.com/specup/allen-semomun-aos/pull/314)** · 🟠 1일 16시간
배너를 창 너비에 따라 비율·이미지를 전환(반응형)하고, 더보기 문구를 리소스로 분리
`8 files` · `+112/−17`

**2. [allen-semomun-aos#313](https://github.com/specup/allen-semomun-aos/pull/313)** · 🟠 1일 1시간
비로그인·미둘러보기 상태에서 홈 위에 로그인 화면을 노출 (iOS 분기 이식)
`18 files` · `+251/−43`

**3. [fanplus-android#1398](https://github.com/fan-maum/fanplus-android/pull/1398)** · 🟢 19시간
팬픽 홈을 Activity에서 Fragment 컨테이너로 전환 (바텀탭/딥링크 진입점 일부)
`9 files` · `+341/−22`

**4. [trot-android#2237](https://github.com/fan-maum/trot-android/pull/2237)** · 🟢 17시간
홈 화면에 "최신 일기" 섹션을 신규 구현하고 API 연동
`10 files` · `+550/−3`

**5. [trot-android#2238](https://github.com/fan-maum/trot-android/pull/2238)** · 🟢 16시간
일기 좋아요를 API 응답 전 즉시 반영하고, 좋아요 아이콘 크기를 통일
`19 files` · `+280/−9`

조회·요약 전용입니다 — 실제 코드 리뷰나 approve는 하지 않습니다.
```

**리뷰 대기 PR이 없으면** 위 템플릿 대신 `리뷰 대기 중인 PR이 없습니다. 🎉` 한 줄만 출력한다.

## 원칙
- **읽기 전용.** 어떤 경우에도 GitHub에 comment/approve/review를 남기거나 PR 상태를 바꾸지 않는다.
- **사실만.** 요약은 title·body에서 확인되는 내용만. 없는 배경·수치를 지어내지 않는다.
- **적을수록 좋다.** 세 칸(요약·대기·변경) 외 정보로 표를 어지럽히지 않는다.
