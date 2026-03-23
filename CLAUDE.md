# SimpleWhisper (귓속말) 애드온

## 개요
- **애드온**: SimpleWhisper (귓속말) v1.0
- **제작자**: CH00
- **대상 클라이언트**: WoW 클래식~리테일 (Interface: 11508, 20505, 30405, 40402, 50503, 120001)
- **용도**: 간단한 귓속말(Whisper) 메신저
- **UI 언어**: 영어 기본, 한글(koKR) 자동 전환 (다국어 구조)
- **제작 배경**: 기존 귓속말 애드온들이 과도하게 복잡하여 핵심 기능만 새로 구현

## 구조

### 파일 구성
```
SimpleWhisper/
├── SimpleWhisper.toc            -- TOC (멀티 인터페이스)
├── SimpleWhisper.lua            -- 단일 메인 파일 (전체 로직)
├── CLAUDE.md                    -- 이 문서
├── icon/
│   └── icon.PNG                 -- 애드온 아이콘 이미지
├── Sounds/                      -- (커스텀 알림 소리 폴더, 현재 비어있음)
└── libs/
    ├── LibStub/LibStub.lua              -- 라이브러리 로더
    ├── CallbackHandler-1.0/CallbackHandler-1.0.lua  -- 콜백 시스템
    └── LibDataBroker-1.1/LibDataBroker-1.1.lua      -- LDB 연동
```

### 의존성
- **필수**: 없음 (독립 실행 가능)
- **선택**: Arcana — 데이터 바에 귓속말 브로커 표시

### SavedVariables (캐릭터별)
- **`SimpleWhisper_DB`** (`SavedVariablesPerCharacter`): 설정 + 대화 내용 저장
  ```lua
  SimpleWhisper_DB = {
      windowPos = { point, x, y },
      windowSize = { w, h },
      dividerX = 100,
      minimapPos = 220,             -- 미니맵 버튼 각도
      soundEnabled = true,          -- 수신 알림 소리
      soundChoice = 1,              -- 소리 선택 (1=귓속말, 2=경매장, 3=커스텀)
      showTime = false,             -- 시간 표시
      autoOpen = true,              -- 수신 시 자동 열기
      combatOpen = false,           -- 전투 중 자동 열기
      hideFromChat = true,          -- 기본 채팅창 숨기기
      interceptWhisper = true,      -- 귓속말 여기서 열기
      fontSize = 12,                -- 글꼴 크기 (10~22)
      opacity = 0.85,               -- 창 불투명도 (0.3~1.0)
      opacityEnabled = true,        -- 불투명도 적용 여부
      toolbarHidden = false,        -- 툴바 숨김 상태
      nameListHidden = false,       -- 이름 목록 숨김 상태
      conversations = {},           -- 대화 내용 (PLAYER_LOGOUT 시 저장)
      nameList = {},                -- 이름 목록 순서 (PLAYER_LOGOUT 시 저장)
      unreadCounts = {},            -- 안 읽은 메시지 수 (PLAYER_LOGOUT 시 저장)
  }
  ```

## 기능

### 슬래시 명령어
| 명령어 | 기능 |
|--------|------|
| `/swsw` | 메인 창 열기/닫기 |
| `/swsw demo` | 데모 데이터 로드 (테스트용) |

### UI 레이아웃 (450×298 팝업 창, 리사이즈 가능)
```
+--[≡]---[who정보][새로고침]------[◀]--+
| [시간][삭제][복사][초대][옵션][X]     |
+--------+----------------------------+
|        |                            |
| 이름   |   대화 내용                 |
| 목록   |   (ScrollingMessageFrame)  |
|        |                            |
|        |   — 2026-03-20 —           |
| 상대A  |   상대A: 안녕              |
| 상대B  |   내닉네임: ㅎㅇ           |
|        |                        [↓] |
|        +----------------------------+
|        | [메시지 입력...           ] |
+--------+----------------------------+
| 상대A 메모: 클릭하여 입력...    [//] |
+--------------------------------------+
```

- **햄버거 버튼 (≡)**: 툴바 표시/숨기기 토글
- **툴바** (제목 아래): who 정보 + 시간/삭제/복사/초대/옵션/닫기 버튼
- **이름 목록 토글 (◀/▶)**: 왼쪽 이름 패널 접기/펼치기
- **왼쪽 패널**: 대화 상대 이름 버튼 리스트 (최근 활동순, 드래그로 너비 조절)
  - 직업 색상 표시, BNet 친구는 청록색 표시
  - 안 읽은 메시지 수 빨간색 표시, 선택된 대화 하이라이트 (금색 좌측 바)
  - 좌클릭: 대화 선택 + `/who` 자동 조회
  - 우클릭: WoW 기본 플레이어 드롭다운 메뉴 (초대/거래/무시 등)
- **오른쪽 상단**: ScrollingMessageFrame — 대화 내용, 날짜 구분선, 마우스 휠 스크롤
  - 상대 이름은 클릭 가능한 하이퍼링크 (`|Hplayer:이름|h`)
  - URL 자동 링크화 (클릭 시 복사 팝업)
  - 맨 아래로 스크롤 버튼 (↓)
- **오른쪽 하단**: EditBox — 메시지 입력, Enter로 전송, ESC로 창 닫기
- **메모란**: 창 하단에 대화 상대별 메모 입력 가능
- **삭제 버튼**: 확인 팝업 후 선택 대화 삭제
- **복사 버튼**: 선택 대화 전체를 텍스트 팝업으로 복사
- **초대 버튼**: 선택 대화 상대 파티 초대 (BNet 대화에서는 비활성화)
- **옵션 버튼**: 드롭다운 설정 패널 토글
- **리사이즈**: 우하단 핸들 (300×200 ~ 800×600)
- **닫기**: X 버튼 또는 ESC 키

### 옵션 패널 (옵션 버튼 클릭 시 토글)
| 옵션 | 기본값 | 설명 |
|------|--------|------|
| 수신 알림 소리 | 켜짐 | 3종 소리 선택 가능 (귓속말/경매장/커스텀sw3.ogg) |
| 수신 시 자동 열기 | 켜짐 | 귓속말 수신 시 창 자동 팝업 |
| 전투 중 자동 열기 | 꺼짐 | 전투 중에도 자동 팝업 허용 (창이 이미 열려 있으면 이 옵션과 무관하게 내용 갱신됨) |
| 채팅창에서 귓속말 숨기기 | 켜짐 | 귓속말을 SimpleWhisper에만 표시 (`ChatFrame_AddMessageEventFilter` 사용, BNet 포함) |
| 귓속말 여기서 열기 | 켜짐 | 채팅창 이름 클릭/귓속말 시작 시 SimpleWhisper로 가로채기 |
| 글꼴 크기 | 12pt | 슬라이더 (10~22pt), 채팅/입력/이름 목록/메모 모두 적용 |
| 불투명도 | 85% | 체크박스 + 슬라이더 (30~100%), 체크 해제 시 100% |
| 전체삭제 | — | 모든 대화 삭제 (설정 유지) |
| 초기화 | — | 모든 설정 기본값 복원 (대화 유지) |

### /who 조회
- 대화 상대 선택 시 자동으로 `/who` 쿼리 전송
- 결과(레벨, 직업, 길드)를 툴바에 표시 + conversations에 저장
- 오프라인이면 빨간색 "오프라인" 표시
- 새로고침 버튼 + 5초 쿨다운
- `/who` 시스템 메시지가 채팅창에 표시되지 않도록 필터링

### 채팅창 이름 클릭 연동
- `SetItemRef` 후킹으로 기본 채팅창의 플레이어 이름 좌클릭 시 SimpleWhisper 대화 창을 열고 해당 상대 선택
- `BNplayer` 링크 좌클릭 시 BNet 대화 열기
- 우클릭 등 다른 버튼은 WoW 기본 동작 유지
- `interceptWhisper` 옵션이 꺼져 있으면 가로채기 비활성화

### 귓속말 가로채기 (ChatEdit_UpdateHeader)
- WoW의 모든 귓속말 시작 경로(초상화/우클릭/파티/채팅입력 등)를 `ChatEdit_UpdateHeader` (또는 12.0+ `ChatFrameUtil.ActivateChat`) 후킹으로 가로채기
- 귓속말 모드 전환 시 SimpleWhisper 창을 열고 기본 채팅 귓속말 모드 취소

### BNet (배틀넷) 귓속말 지원
- `CHAT_MSG_BN_WHISPER` / `CHAT_MSG_BN_WHISPER_INFORM` 이벤트 처리
- 배틀태그에서 `#` 뒤를 제거하여 간결한 이름 표시
- BNet 전용 색상 (수신: 청록 `|cff00b4d8`, 발신: 파랑 `|cff2ca2ff`)
- BNet 메시지 발송: `C_BattleNet.SendWhisper` 또는 `BNSendWhisper` 호환
- BNet 대화는 이름 목록에서 청록색 표시, 초대 버튼 비활성화

### 미니맵 버튼
- 미니맵 주변에 드래그 가능한 버튼 표시
- 안 읽은 메시지가 있으면 숫자 배지 + 아이콘 색상 변경 (핑크)
- 좌클릭: 창 토글
- 우클릭 드래그: 위치 이동
- 툴팁: 제목 + 안 읽은 메시지 수 + 힌트

### 시스템 메시지 처리
- "플레이어를 찾을 수 없습니다" / "무시하고 있습니다" 메시지를 해당 대화에 시스템 메시지(`sys`)로 기록
- `ERR_CHAT_PLAYER_NOT_FOUND_S`, `ERR_CHAT_IGNORED_S` 패턴 매칭

### 직업 캐시 시스템
- 채팅 이벤트(일반/외침/길드/파티/공격대/전장 등)에서 `GetPlayerInfoByGUID`로 직업 정보 수집
- `target`/`focus`/`mouseover`/파티·공격대 유닛에서도 직업 탐색
- `/who` 결과에서도 직업 추출
- 캐시된 직업 정보로 이름 목록에 클래스 색상 표시

### 동작 방식

#### 귓속말 수신 시 (일반 + BNet)
1. 대화 기록에 메시지 추가
2. 이름 목록에서 해당 상대를 최상단으로 이동 (`BumpName`)
3. 알림 소리 재생 (옵션)
4. 창이 닫혀 있으면 자동 열기 (옵션, 전투 중 조건 확인)
5. 선택된 대화가 없으면 수신된 대화를 자동 선택
6. 다른 대화 선택 중이면 해당 상대의 안 읽은 수 증가 (대화 전환 안 됨)

#### 귓속말 발신 시
1. 입력창에서 Enter → `SendChatMessage(text, "WHISPER", nil, fullName)` 또는 BNet은 `SendBNetWhisper(bnID, text)` 호출
2. `CHAT_MSG_WHISPER_INFORM` / `CHAT_MSG_BN_WHISPER_INFORM` 이벤트로 발신 메시지 자동 기록
3. 현재 선택된 대화면 채팅 표시 즉시 갱신

#### 대화 저장/복원
- `PLAYER_LOGOUT` 시 `conversations`, `nameList`, `unreadCounts`를 `SimpleWhisper_DB`에 저장
- `ADDON_LOADED` 시 복원

### 메시지 표시 형식
- **수신 (일반)**: `상대이름: 메시지` (핑크 `|cffff88ff`, 이름은 `|Hplayer:|h` 하이퍼링크)
- **수신 (BNet)**: `상대이름: 메시지` (청록 `|cff00b4d8`)
- **발신 (일반)**: `내닉네임: 메시지` (연핑크 `|cffffbbdd`) — `UnitName("player")`로 실제 캐릭터명 표시
- **발신 (BNet)**: `내닉네임: 메시지` (파랑 `|cff2ca2ff`)
- **/who 결과**: 녹색 `|cff00ff00`
- **시스템 메시지**: 빨간색 `|cffff4444`
- **시간 표시 활성화 시**: `[12:34:56] 상대이름: 메시지`
- **날짜 구분선**: `— 2026-03-20 —` (회색)
- **URL**: 자동 링크화 (파란색 `|cff4488ff`, 클릭 시 복사 팝업)
- **색상**: 시간 `|cffaaaaaa` (회색), 안 읽은 수 `|cffff3333` (빨강)

### LDB (LibDataBroker) 연동
- LDB data source 이름: `"SimpleWhisper"`
- 아이콘: `Interface\CHATFRAME\UI-ChatIcon-Chat-Up` (채팅 아이콘)
- 텍스트: `"귓속말"` — 안 읽은 메시지 있으면 `"귓속말(3)"` 형태로 표시, 없으면 `"귓속말(0)"`
- 좌클릭: 창 토글
- 툴팁: 제목 + 안 읽은 메시지 수 + 힌트

## 코드 구조 (SimpleWhisper.lua)

### 다국어 문자열 테이블 `L`
영어 기본값으로 초기화 후 `GetLocale() == "koKR"` 시 한글 오버라이드. 다국어 확장 시 같은 패턴으로 추가.

### 세션 데이터
| 변수 | 타입 | 용도 |
|------|------|------|
| `conversations` | `table` | `["이름"] = { fullName, class, isBN, bnID, guid, whoLevel, whoGuild, memo, {who, msg, time, date}, ... }` |
| `nameList` | `table` | 최근 활동순 이름 배열 |
| `unreadCounts` | `table` | `["이름"] = 숫자` |
| `selectedName` | `string/nil` | 현재 선택된 대화 상대 |
| `mainFrame` | `Frame/nil` | 메인 UI 프레임 (lazy 생성) |
| `ldbObject` | `table/nil` | LDB 데이터 오브젝트 |
| `minimapBadge` | `Frame/nil` | 미니맵 안 읽은 수 배지 |
| `pendingWhoName` | `string/nil` | `/who` 조회 대기 중인 이름 |
| `pendingWhoTimer` | `Timer/nil` | `/who` 타임아웃 타이머 |
| `whoFilterUntil` | `number` | `/who` 시스템 메시지 필터 만료 시간 |
| `classCache` | `table` | 채팅에서 수집한 직업 캐시 `["이름"] = "CLASS_TOKEN"` |

### 핵심 함수
| 함수 | 역할 |
|------|------|
| `ShortName(fullName)` | `Ambiguate`로 서버명 제거 |
| `ResolveBNetName(bnID)` | BNet ID → 배틀태그 또는 계정명 해석 |
| `GetBNetToonName(bnID)` | BNet 친구의 현재 캐릭터명 조회 |
| `SendBNetWhisper(bnID, text)` | BNet 메시지 발송 (Retail/Classic 호환) |
| `ResolveClass(name)` | 캐시/유닛/파티에서 직업 탐색 |
| `EnsureConversation(name, fullName, isBN, bnID)` | 대화 테이블 초기화, fullName/BNet 정보 보존 |
| `BumpName(name)` | 이름을 목록 최상단으로 이동 |
| `PlayWhisperSound()` | 수신 알림 소리 재생 (3종 선택) |
| `UpdateLDBText()` | LDB 텍스트 + 미니맵 배지 갱신 (안 읽은 수) |
| `AddMessage(name, dir, text, fullName)` | 대화 기록 추가 + 이름 순서 갱신 + 안 읽은 수 처리 |
| `LinkifyURLs(text)` | URL 자동 하이퍼링크 변환 |
| `RefreshNameList()` | 왼쪽 이름 버튼 리스트 갱신 |
| `RefreshChatDisplay()` | 오른쪽 대화 내용 갱신 (하이퍼링크, 시간, 날짜 구분선, URL) |
| `SelectConversation(name, noFocus)` | 대화 선택 + 안 읽은 수 초기화 + who 정보/메모 표시 |
| `DeleteConversation(name)` | 대화 삭제 + UI 갱신 |
| `SendWhoQuery(charName)` | `/who` 쿼리 전송 + 결과 파싱 (쿨다운 관리) |
| `CreateMainFrame()` | UI 전체 생성 (lazy, 최초 1회) |
| `ToggleMainFrame()` | 창 표시/숨기기 토글 |
| `OpenWhisperTo(name, fullName)` | 외부에서 일반 대화 열기 (채팅창 이름 클릭용) |
| `OpenBNetWhisperTo(bnID)` | 외부에서 BNet 대화 열기 |

### SetItemRef 후킹
- `player:이름` 링크의 좌클릭을 가로채 `OpenWhisperTo()` 호출
- `BNplayer:이름:bnID` 링크의 좌클릭을 가로채 `OpenBNetWhisperTo()` 호출
- `interceptWhisper` 옵션이 꺼져 있으면 가로채지 않음
- 우클릭 및 기타 링크는 `origSetItemRef`로 전달 (WoW 기본 동작 유지)

### ChatEdit_UpdateHeader 후킹
- WoW의 귓속말 모드 전환(`chatType == "WHISPER"`)을 감지하여 SimpleWhisper 창으로 리다이렉트
- 12.0+ (`ChatFrameUtil.ActivateChat`) / 이전 버전 (`ChatEdit_UpdateHeader`) 분기 처리

### 이벤트 처리
| 이벤트 | 처리 내용 |
|--------|-----------|
| `ADDON_LOADED` | DB 초기화, 대화/안읽음 복원, LDB 생성, 미니맵 버튼, 채팅 필터 등록, /who 필터, 슬래시 명령어 등록 |
| `PLAYER_LOGOUT` | 대화 내용 + 이름 목록 + 안 읽은 수 저장 |
| `CHAT_MSG_WHISPER` | 수신 메시지 기록, GUID/직업 저장, 소리 재생, 자동 열기 |
| `CHAT_MSG_WHISPER_INFORM` | 발신 메시지 기록, 채팅 표시 갱신 |
| `CHAT_MSG_BN_WHISPER` | BNet 수신 메시지 기록, 소리 재생, 자동 열기 |
| `CHAT_MSG_BN_WHISPER_INFORM` | BNet 발신 메시지 기록, 채팅 표시 갱신 |
| `CHAT_MSG_SYSTEM` | `/who` 결과 파싱, 오프라인 감지, 발송 실패 메시지 기록 |
| `CHAT_MSG_*` (채팅 캐시) | 일반/외침/길드/파티/공격대/전장 채팅에서 직업 정보 수집 |

## 호환성 처리
- **BackdropTemplate**: `BackdropTemplateMixin and "BackdropTemplate"` 패턴으로 9.0+ / 이전 버전 모두 지원
- **이름 정규화**: `Ambiguate(name, "none")`으로 서버명 제거, `fullName` 별도 보존하여 `SendChatMessage`에 사용
- **멀티 인터페이스 TOC**: 클래식(11508) ~ 리테일(120001) 6개 버전 동시 지원
- **플레이어 드롭다운**: `FriendsFrame_ShowDropdown` 존재 시 사용, 없으면 `ChatFrame_SendTell` 폴백
- **BNet API**: `C_BattleNet.GetAccountInfoByID` (Retail) / `BNGetFriendInfoByID` (Classic) 분기
- **BNet 발송**: `C_BattleNet.SendWhisper` / `BNSendWhisper` 분기
- **파티 초대**: `C_PartyInfo.InviteUnit` / `InviteUnit` 분기
- **리사이즈**: `SetResizeBounds` (10.0+) / `SetMinResize`+`SetMaxResize` (이전) 분기
- **채팅 후킹**: `ChatFrameUtil.ActivateChat` (12.0+) / `ChatEdit_UpdateHeader` (이전) 분기
- **/who API**: `C_FriendList.SendWho` / `SlashCmdList["WHO"]` 분기
- **직업 이름 매핑**: 영어/한글 직업명 → CLASS_TOKEN 테이블 별도 관리

## 수정 시 참고사항
- 단일 파일(`SimpleWhisper.lua`) 구조이므로 모든 수정은 이 파일에서 이루어짐
- UI 프레임은 lazy 생성 — `CreateMainFrame()`이 호출되기 전까지 프레임 없음
- `nameButtons`는 동적 생성 (풀링 없음) — 대화 상대가 매우 많을 경우 성능 고려 필요
- `SetItemRef` 전역 덮어쓰기 방식 — 다른 애드온과 충돌 가능성 있음
- `ChatEdit_UpdateHeader` 후킹으로 모든 귓속말 경로를 가로채므로 관련 애드온과 충돌 가능성 있음
- `AddMessage`, `RefreshNameList`, `RefreshChatDisplay`, `SelectConversation`, `DeleteConversation`은 forward declare 패턴 사용 (함수 참조가 순서에 의존)
- `/who` 조회 시 `SetWhoToUI(false)`로 누구 목록 UI 표시를 억제하고 결과 수신 후 복원
- 채팅 캐시 프레임(`classCacheFrame`)은 애드온 로드 즉시 생성되어 채팅 이벤트를 상시 수집
