# BOOM JEJU 앱 알림 설정

이 기능은 상담문의 또는 새 공개 게시물이 생기면 승인된 최고관리자에게 푸시 알림을 보내고, 읽지 않은 알림 수를 PWA 아이콘에 표시합니다. 고객 이름·전화번호·문의 내용은 푸시 본문에 넣지 않습니다.

## 1. Supabase 데이터베이스

Supabase 대시보드의 **SQL Editor**에서 `boom_notifications.sql` 내용을 한 번 실행합니다. 이 작업은 알림함, 푸시 구독 정보, 문의·공개 게시물 알림 트리거와 RLS 정책을 만듭니다.

## 2. VAPID 키 만들기

Deno를 사용할 수 있는 안전한 로컬 환경에서 아래 내용을 `generate-vapid.ts`로 저장하고 실행합니다.

```ts
import * as webpush from "jsr:@negrel/webpush@0.5.0";
const keys = await webpush.generateVapidKeys({ extractable: true });
console.log(JSON.stringify(await webpush.exportVapidKeys(keys)));
```

`VAPID_KEYS` 환경 변수에 출력된 전체 JSON을 저장합니다. 이 JSON에는 개인 키가 포함되므로 GitHub나 웹사이트 코드에 올리지 마세요.

## 3. Edge Function 배포 및 비밀값

`supabase/functions/boom-push/index.ts`를 `boom-push` 이름의 Supabase Edge Function으로 배포합니다. Supabase Functions 설정에 다음 비밀값을 추가합니다.

- `VAPID_KEYS`: 2단계에서 만든 전체 키 JSON
- `VAPID_SUBJECT`: `mailto:운영자이메일주소` 형식의 연락처

Supabase의 `SUPABASE_URL`과 `SUPABASE_SERVICE_ROLE_KEY`는 함수 런타임 기본 환경값을 사용합니다. 서비스 키를 웹페이지나 GitHub에 추가하지 마세요.

## 4. Database Webhook 연결

Supabase 대시보드의 **Database Webhooks**에서 새 Webhook을 만듭니다.

- 테이블: `public.boom_notifications`
- 이벤트: `INSERT`
- URL: `https://rfpwbwivdlagqjkhjsxq.supabase.co/functions/v1/boom-push`
- 헤더: `Content-Type: application/json`, `Authorization: Bearer <서비스 역할 키>`

서비스 역할 키는 Webhook 헤더 설정에만 저장하고 공유하지 마세요.

## 5. 관계자 휴대폰에서 켜기

운영 사이트를 홈 화면에 추가한 뒤 관계자 최고관리자 계정으로 로그인하고 **새 글·문의 알림 받기**를 누릅니다. iPhone은 iOS 16.4 이상에서 홈 화면 웹 앱으로 실행해야 푸시와 아이콘 배지가 동작합니다. Android 아이콘 배지의 모양은 런처 설정에 따라 달라질 수 있습니다.

현재 앱 코드는 위 Supabase SQL과 Edge Function 설정이 적용되기 전까지 알림 연결 상태를 표시하지 못합니다. 실제 Supabase 설정 적용 여부는 GitHub 코드만으로 확인할 수 없습니다.
