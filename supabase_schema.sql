-- ============================================================
-- 강남구 사업장 지도 - Supabase 스키마
-- 실행 방법: Supabase 대시보드 → SQL Editor → New query → 붙여넣기 → Run
-- ============================================================

-- 1) 사용자 프로필 테이블 (역할/승인 관리)
create table if not exists gnmap_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  role text not null default 'viewer' check (role in ('admin', 'viewer')),
  approved boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table gnmap_profiles is '강남구 사업장 지도 - 사용자 프로필(역할/승인)';

-- 2) 사업장 데이터 테이블 (엑셀 업로드 시 전체 교체)
create table if not exists gnmap_sites (
  id bigint generated always as identity primary key,
  company_name text not null,          -- 담당 회사명 (양식1:본사명 / 양식2:사업장명)
  site_name text not null,             -- 현장 이름   (양식1:사업장명 / 양식2:사업현장명)
  address text,                        -- 주소 (지오코딩 입력값)
  lat double precision,                -- 위도 (지오코딩 결과, 실패 시 null)
  lng double precision,                -- 경도
  dong text,                           -- 행정동 (좌표 확보 후 계산)
  amount bigint,                       -- 공사금액(원)
  period_start date,                   -- 공사시작일
  period_end date,                     -- 공사종료일
  accident_report_count int,           -- 산재조사표(건) - 양식2엔 없어 null 가능
  supervision_count int,               -- 지도감독(건)   - 양식2엔 없어 null 가능
  source_form text,                    -- 어느 엑셀 양식에서 왔는지 ('form1' | 'form2')
  status text not null default 'confirmed' check (status in ('confirmed', 'review')), -- review = 주소/좌표 확인 필요
  uploaded_at timestamptz not null default now()
);

comment on table gnmap_sites is '강남구 사업장 지도 - 사업장 데이터(엑셀 업로드 시 전체 교체)';
create index if not exists gnmap_sites_dong_idx on gnmap_sites(dong);
create index if not exists gnmap_sites_status_idx on gnmap_sites(status);

-- ============================================================
-- RLS(Row Level Security) 활성화
-- ============================================================
alter table gnmap_profiles enable row level security;
alter table gnmap_sites enable row level security;

-- ------- gnmap_profiles 정책 -------

-- 본인 프로필은 항상 조회 가능
create policy "본인 프로필 조회"
  on gnmap_profiles for select
  using (auth.uid() = id);

-- admin은 전체 프로필 조회 가능 (승인 화면용)
create policy "관리자 전체 프로필 조회"
  on gnmap_profiles for select
  using (
    exists (select 1 from gnmap_profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- 신규 가입 시 본인 행 1건 생성 허용 (역할은 기본 viewer로 고정, approved는 기본 false)
create policy "본인 프로필 생성"
  on gnmap_profiles for insert
  with check (auth.uid() = id);

-- admin만 다른 사람의 role/approved 수정 가능
create policy "관리자 프로필 수정"
  on gnmap_profiles for update
  using (
    exists (select 1 from gnmap_profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- ------- gnmap_sites 정책 -------

-- 승인된 로그인 사용자만 조회 가능 (admin, viewer 공통)
create policy "승인된 사용자 조회"
  on gnmap_sites for select
  using (
    exists (
      select 1 from gnmap_profiles p
      where p.id = auth.uid() and p.approved = true
    )
  );

-- admin만 업로드(삽입) 가능
create policy "관리자 업로드"
  on gnmap_sites for insert
  with check (
    exists (select 1 from gnmap_profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- admin만 삭제 가능 (엑셀 재업로드 시 기존 데이터 전체 삭제용)
create policy "관리자 삭제"
  on gnmap_sites for delete
  using (
    exists (select 1 from gnmap_profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- admin만 수정 가능
create policy "관리자 수정"
  on gnmap_sites for update
  using (
    exists (select 1 from gnmap_profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- ============================================================
-- 최초 관리자 지정 방법 (SQL Editor에서 별도 실행)
-- ============================================================
-- 1) 먼저 지도 웹앱의 회원가입 화면에서 본인 계정으로 가입한다.
-- 2) 아래 쿼리로 본인을 관리자 + 승인 상태로 즉시 전환한다.
--    (이메일은 실제 가입한 이메일로 교체)
--
-- update gnmap_profiles
-- set role = 'admin', approved = true
-- where id = (select id from auth.users where email = '가입한이메일@example.com');
