<p align="center">
  <img src="assets/banner.png" alt="HardKit" width="480">
</p>

# HardKit

소프트웨어 개발의 하드한 부분(코드 리뷰, PR 큐, 검증)을 돕는 Claude Code 플러그인입니다. 소통·기획·문서 쪽은 [SoftKit](https://github.com/khs3994/SoftKit)이 맡습니다.

## 설치

```
/plugin marketplace add https://github.com/khs3994/HardKit
/plugin install hardkit@hardkit
```

## 구성

| 이름 | 종류 | 하는 일 | 예시 |
|---|---|---|---|
| `/to-review` | 스킬 | 내가 리뷰어인 열린 PR을 대기 오래된 순으로 보여 준 뒤, PR마다 에이전트를 띄워 `review-pr`로 리뷰하고 결과를 한 표로 종합한다. `--list-only`면 목록만 | `/to-review`, `/to-review --repo fan-maum/trot-android --limit 3` |
| `/review-pr` | 스킬 | PR의 목적을 파악하고, 목적대로 구현됐는지 확인한 뒤, 결함을 호출부까지 추적해 유저 재현 가능성과 함께 현상·원인·근거·해결 방안으로 보고한다 | `/review-pr 1593`, "이 PR 머지해도 돼?" + URL |

두 스킬 모두 `gh` 로그인과 `jq`가 필요합니다. 사용자가 명시적으로 요청하기 전에는 GitHub에 코멘트·리뷰·approve를 남기지 않습니다.

## 로컬 개발

```
git clone https://github.com/khs3994/HardKit
/plugin marketplace add ./HardKit
/plugin install hardkit@hardkit
```

파일을 수정한 뒤에는 `/plugin marketplace update hardkit`으로 새로고침합니다.

## 라이선스

MIT
