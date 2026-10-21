-- ============================================================
-- Supplier Evaluation System — Supabase (PostgreSQL) Schema
-- ============================================================
-- ออกแบบตาม:
--   1) Flow การประเมิน Supplier (PPTX)
--   2) แบบฟอร์ม FM0704-3 Rev.2 (Excel) — หน้า 1 แบบประเมิน / หน้า 2 Corrective Action
--   3) Prototype HTML (dashboard, list, profile, report)
--
-- รันไฟล์นี้ทั้งไฟล์ใน Supabase SQL Editor ครั้งเดียวได้เลย
-- ============================================================

-- เปิด extension สำหรับสร้าง UUID (Supabase มักเปิดให้แล้ว แต่ IF NOT EXISTS ไว้กันเหนียว)
create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 0. ENUM types
-- ------------------------------------------------------------
create type eval_category as enum ('quality', 'delivery', 'purchase');

create type eval_status as enum (
  'draft',
  'submitted',
  'approved',
  'sent_to_supplier',
  'acknowledged',
  'follow_up_required'
);

create type eval_grade as enum ('A', 'B', 'C', 'D');

create type ca_status as enum ('open', 'in_progress', 'closed', 'overdue');

-- ------------------------------------------------------------
-- 1. SUPPLIERS — ข้อมูลหลักของ Supplier (master data)
-- ------------------------------------------------------------
create table suppliers (
  id            uuid primary key default gen_random_uuid(),
  code          text unique not null,          -- เช่น 'MA-003'
  name          text not null,                 -- ชื่อเต็มบริษัท
  short_name    text,                           -- ชื่อย่อ ใช้แสดงในตาราง/กราฟ
  attention     text,                           -- ผู้ติดต่อ
  tel           text,
  email         text,                           -- ใช้ส่งผลประเมินอัตโนมัติ
  category      text,                           -- เช่น 'Material', 'Part'
  target_score  numeric(5,2) default 80,        -- เกณฑ์เป้าหมายรายบริษัท (ปกติ 80)
  is_active     boolean not null default true,  -- false = No eval. (เลิกประเมินแล้ว เช่น sheet "No eva. NST")
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table suppliers is 'Supplier master, 1 row ต่อ 1 บริษัท (เทียบเท่า 1 sheet ใน Excel เดิม)';

-- ------------------------------------------------------------
-- 2. EVALUATION_CRITERIA — รายการหัวข้อประเมินย่อย (คงที่ตาม FM0704-3)
-- ------------------------------------------------------------
create table evaluation_criteria (
  id              uuid primary key default gen_random_uuid(),
  category        eval_category not null,       -- quality / delivery / purchase
  item_no         text not null,                 -- เช่น 'A1-1', 'B-5'
  description     text not null,                 -- เช่น 'Claim from the field return...'
  full_score      numeric(5,2),                  -- คะแนนเต็มของหมวด (เช่น 40, 50, 10) — ใส่เฉพาะแถวหัวข้อหลัก
  deduction_points numeric(5,2),                 -- คะแนนที่หักต่อครั้ง เช่น -40, -10, -1
  display_order   int not null default 0,
  is_active       boolean not null default true
);

comment on table evaluation_criteria is 'Master list หัวข้อย่อยตาม FM0704-3 (A1,A2,B,C) ใช้คำนวณ Time Score/Deduction';

-- ------------------------------------------------------------
-- 3. EVALUATIONS — ผลประเมินรายเดือนต่อ Supplier (ตารางหลัก)
-- ------------------------------------------------------------
create table evaluations (
  id                uuid primary key default gen_random_uuid(),
  supplier_id       uuid not null references suppliers(id) on delete restrict,
  year              int not null,
  month             int not null check (month between 1 and 12),

  -- คะแนนรวมต่อหมวด (ผู้ใช้กรอกหรือคำนวณจาก evaluation_items)
  quality_score     numeric(5,2) not null default 50,   -- เต็ม 50, กรอกโดย QA
  delivery_score    numeric(5,2) not null default 40,   -- เต็ม 40, กรอกโดย CS/MP
  purchase_score    numeric(5,2) not null default 0,    -- เต็ม 10, กรอกโดย CS/MP

  total_score       numeric(5,2) generated always as
                       (quality_score + delivery_score + purchase_score) stored,

  -- Grade คำนวณอัตโนมัติจาก total_score ตามเกณฑ์ Excel เดิม
  -- Score=100→A, 80<=Score<100→B, 70<=Score<80→C, Score<70→D
  grade             eval_grade generated always as (
                       case
                         when (quality_score + delivery_score + purchase_score) >= 100 then 'A'::eval_grade
                         when (quality_score + delivery_score + purchase_score) >= 80  then 'B'::eval_grade
                         when (quality_score + delivery_score + purchase_score) >= 70  then 'C'::eval_grade
                         else 'D'::eval_grade
                       end
                     ) stored,

  quality_comment   text,
  delivery_comment  text,

  status            eval_status not null default 'draft',

  submitted_by      uuid references auth.users(id),
  approved_by       uuid references auth.users(id),
  approved_at       timestamptz,

  sent_at           timestamptz,          -- เวลาที่ส่ง PDF/Email ให้ Supplier
  acknowledged_at   timestamptz,          -- เวลาที่ Supplier กดรับทราบ

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  unique (supplier_id, year, month)       -- 1 Supplier ประเมินได้เดือนละ 1 ครั้ง
);

comment on table evaluations is 'ผลประเมินรายเดือน 1 แถว = 1 Supplier x 1 เดือน (เทียบเท่าฟอร์ม FM0704-3 หน้า 1)';

create index idx_evaluations_supplier on evaluations(supplier_id);
create index idx_evaluations_year_month on evaluations(year, month);
create index idx_evaluations_status on evaluations(status);

-- ------------------------------------------------------------
-- 4. EVALUATION_ITEMS — รายละเอียดระดับหัวข้อย่อย (ตรวจสอบย้อนหลังได้ทุกจุด)
-- ------------------------------------------------------------
create table evaluation_items (
  id              uuid primary key default gen_random_uuid(),
  evaluation_id   uuid not null references evaluations(id) on delete cascade,
  criteria_id     uuid not null references evaluation_criteria(id),
  occurrence      int not null default 0,        -- จำนวนครั้งที่เกิดปัญหาในเดือนนั้น
  points_applied  numeric(5,2) not null default 0, -- occurrence * deduction_points (คำนวณฝั่ง backend)
  note            text,
  created_at      timestamptz not null default now(),

  unique (evaluation_id, criteria_id)
);

comment on table evaluation_items is 'บันทึกละเอียดต่อหัวข้อย่อย เผื่อ audit / คำนวณคะแนนใหม่ย้อนหลัง';

create index idx_eval_items_evaluation on evaluation_items(evaluation_id);

-- ------------------------------------------------------------
-- 5. CORRECTIVE_ACTIONS — หน้า 2 ของ FM0704-3 (CAR)
-- ------------------------------------------------------------
create table corrective_actions (
  id              uuid primary key default gen_random_uuid(),
  evaluation_id   uuid not null references evaluations(id) on delete cascade,
  seq_no          int not null,                 -- ลำดับที่ (No.)
  problem         text not null,
  root_cause      text,
  action          text,
  responsible_person text,
  start_date      date,
  finished_date   date,
  status          ca_status not null default 'open',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table corrective_actions is 'Corrective Action Report ต่อ evaluation ที่คะแนนต่ำกว่าเกณฑ์ (เทียบเท่า FM0704-3 หน้า 2)';

create index idx_ca_evaluation on corrective_actions(evaluation_id);
create index idx_ca_status on corrective_actions(status);

-- ------------------------------------------------------------
-- 6. AUDIT LOG (เผื่ออนาคต — ใครแก้/อนุมัติอะไรเมื่อไร)
-- ------------------------------------------------------------
create table evaluation_audit_log (
  id              uuid primary key default gen_random_uuid(),
  evaluation_id   uuid not null references evaluations(id) on delete cascade,
  action          text not null,            -- 'created' | 'updated' | 'approved' | 'sent' | 'acknowledged'
  performed_by    uuid references auth.users(id),
  detail          jsonb,
  created_at      timestamptz not null default now()
);

create index idx_audit_evaluation on evaluation_audit_log(evaluation_id);

-- ------------------------------------------------------------
-- 7. updated_at auto-touch trigger (ใช้ซ้ำได้ทุกตาราง)
-- ------------------------------------------------------------
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_suppliers_updated_at
  before update on suppliers
  for each row execute function set_updated_at();

create trigger trg_evaluations_updated_at
  before update on evaluations
  for each row execute function set_updated_at();

create trigger trg_ca_updated_at
  before update on corrective_actions
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 8. Row Level Security (เปิดไว้ก่อน — ตั้ง policy ตาม role จริงภายหลัง)
-- ------------------------------------------------------------
alter table suppliers enable row level security;
alter table evaluation_criteria enable row level security;
alter table evaluations enable row level security;
alter table evaluation_items enable row level security;
alter table corrective_actions enable row level security;
alter table evaluation_audit_log enable row level security;

-- ตัวอย่าง policy พื้นฐาน: authenticated user อ่านได้ทุกตาราง (ปรับตาม role จริงทีหลัง)
create policy "Authenticated users can read suppliers"
  on suppliers for select
  to authenticated
  using (true);

create policy "Authenticated users can read evaluations"
  on evaluations for select
  to authenticated
  using (true);

-- ตัวอย่าง policy เขียน: อนุญาตให้ authenticated user insert/update ได้ก่อน
-- (แนะนำให้แยกตาม role QA/CS/MP จริงในขั้นถัดไป เช่นใช้ custom claim หรือตาราง profiles+role)
create policy "Authenticated users can insert evaluations"
  on evaluations for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update evaluations"
  on evaluations for update
  to authenticated
  using (true);
