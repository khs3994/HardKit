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
| `/to-review` | 스킬 | 내가 리뷰어인 열린 PR을 요약·대기 시간·변경 규모와 함께 대기 오래된 순으로 보여준다 (`gh` 로그인, `jq` 필요) | `/to-review` |

`to-review`는 조회·요약만 하며 GitHub에 아무것도 쓰지 않습니다.

## 로컬 개발

```
git clone https://github.com/khs3994/HardKit
/plugin marketplace add ./HardKit
/plugin install hardkit@hardkit
```

파일을 수정한 뒤에는 `/plugin marketplace update hardkit`으로 새로고침합니다.

## 라이선스

MIT
