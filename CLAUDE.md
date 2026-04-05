# CH00의 WoW 애드온 모음

## 개요
- **제작자**: CH00
- **UI 언어**: 영어 기본, 한글(koKR) 자동 전환 (다국어 구조)

## 레포지토리 구조

애드온별로 **독립된 GitHub 레포**로 관리한다. 로컬에서는 하나의 작업 폴더(`C:\Claude\WOW_Addon\`) 아래 각 애드온 폴더가 자체 `.git`을 가진다.

| 애드온 | 레포 | 설명 |
|--------|------|------|
| SimpleWhisper | `cdcdcd050/SimpleWhisper` | 귓속말 메신저 |
| SimpleRepu | `cdcdcd050/SimpleRepu` | TBC 평판 가이드 |
| SimpleRepItem | `cdcdcd050/SimpleRepItem` | TBC 평판 아이템 브라우저 (BCC 전용) |

> **커밋/푸시/릴리즈는 반드시 해당 애드온 폴더 안에서 수행한다.** 다른 애드온의 레포에 영향을 주지 않도록 주의.

> **각 애드온의 상세 문서는 해당 폴더의 `CLAUDE.md`를 참조한다.**

---

## 공통 코딩 규칙

### 다국어 처리
- 영어 기본값으로 초기화 후 `GetLocale() == "koKR"` 시 한글 오버라이드
- 다국어 확장 시 같은 패턴으로 추가

### WoW API 호환성 패턴
- **BackdropTemplate**: `BackdropTemplateMixin and "BackdropTemplate"` 패턴으로 9.0+ / 이전 버전 모두 지원
- **이름 정규화**: `Ambiguate(name, "none")`으로 서버명 제거
- **리사이즈**: `SetResizeBounds` (10.0+) / `SetMinResize`+`SetMaxResize` (이전) 분기

### 공통 의존성
- **LibStub**, **CallbackHandler**, **LibDataBroker (LDB)** — 각 애드온 `libs/` 폴더에 번들
- **선택**: Arcana — 데이터 바에 LDB 브로커 표시

---

## 릴리즈 절차

모든 애드온은 동일한 자동화 파이프라인을 사용한다:

1. TOC 파일에서 `## Version:` 버전 올리기
2. 커밋 → 태그(`v{버전}`) 푸시 → GitHub release 생성
3. GitHub Actions (`BigWigsMods/packager@v2`)가 CurseForge에 자동 업로드

**필요 파일 (각 애드온 레포):**
- `.github/workflows/release.yml` — 태그 푸시 트리거, `-g` 플래그로 대상 클라이언트 지정
- `.pkgmeta` — 패키지 이름, ignore 목록

**CurseForge API 키:** CurseForge 웹에서 페이로드 URL로 관리 (GitHub Secrets 불필요)

**TOC 파일명 규칙:** 클라이언트별 접미사 사용 (예: `_TBC.toc` = BCC 전용)

### 클라이언트 지정 (애드온마다 대상 게임 버전이 다름)
| 애드온 | `-g` 플래그 | TOC 파일 | Interface 버전 |
|--------|-----------|----------|---------------|
| SimpleWhisper | `classic bcc wrath cata retail` | `SimpleWhisper.toc` (120005) + `_Vanilla` (11508), `_TBC` (20505), `_Wrath` (30405), `_WrathTR` (38000), `_Cata` (40402), `_Mists` (50503) | 멀티 클라이언트 |
| SimpleRepu | `bcc` | `SimpleRepu_TBC.toc` (20505) | BCC 전용 |
| SimpleRepItem | `bcc` | `SimpleRepItem_TBC.toc` (20505) | BCC 전용 |

> **CurseForge 업로드 시 게임 버전은 TOC의 `## Interface:` 값에 의해 결정된다.** 새 클라이언트 지원 추가 시 해당 TOC 파일 생성 + release.yml의 `-g` 플래그 추가 필요.
