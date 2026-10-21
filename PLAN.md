# Supplier Evaluation System — Project Plan

**Package version:** v75 (app v2.17.0)
**Last updated:** 2026-09-19
**Purpose of this doc:** ให้ session/AI อื่นหยิบงานต่อได้ทันที โดยไม่ต้องถามซ้ำสิ่งที่ตัดสินใจไปแล้ว
**ดูรายละเอียดการเปลี่ยนแปลงแต่ละเวอร์ชันที่:** `CHANGELOG.md`

---

## 1. Background

บริษัทมีกระบวนการประเมิน Supplier แบบ manual อยู่แล้ว (ดู Flow เดิม) โดยใช้ Excel (`FM0704-3 Rev.2`) เป็นเครื่องมือหลัก ต้องการแปลงเป็นเว็บแอพจริงที่มี database, workflow อนุมัติ, และส่งผลให้ Supplier อัตโนมัติ

**ไฟล์อ้างอิงต้นทาง (source of truth):**
| ไฟล์ | เนื้อหา |
|---|---|
| `Flow_การ_ประเม_น_Supplier.pptx` | Flow การทำงานปัจจุบัน (manual, Excel on SharePoint) |
| `07__JULY_26.xlsx` | ไฟล์ประเมินจริงเดือน ก.ค. 2026 — 32 sheet Supplier + Summary + Template |
| `supplier_evaluation_prototype_EN_TH.html` | Prototype เดิม — CRUD ด้วย localStorage เท่านั้น ยังไม่มี backend จริง |

**Business rules สำคัญที่ต้องคงไว้:**
- คะแนนเต็ม 100: Quality 50 (QA/TQM), Delivery 40 (CS/MP), Purchase 10 (CS/MP)
- เกรด: Score=100→A, 80≤Score<100→B, 70≤Score<80→C, Score<70→D
- ประเมินเดือนละครั้งต่อ Supplier
- Flow: กรอกแยกตามแผนก → หัวหน้างาน Approve → ส่ง PDF/Email ให้ Supplier → ถ้าต่ำกว่าเกณฑ์ต้องส่ง Corrective Action กลับมา

---

## 2. Roadmap (8 phases + 2 correctness/priority fixes)

| # | Phase | Status | Version |
|---|---|---|---|
| 1 | ออกแบบฐานข้อมูลกลาง (Backend + DB) | ✅ Done | v0.1.0 |
| 2 | แยกสิทธิ์และฟอร์มตามแผนก (Auth + Role: QA/CS/MP/Admin) | ✅ Done | v0.3.0 |
| A | **[แทรกนอกลำดับ]** แก้บั๊ก No-Shipment/Applicability — คะแนน % ผิด, default ทำให้แถวที่ยังไม่กรอกดูเหมือนประเมินดีแล้ว | ✅ Done | v0.4.0 |
| 3 | ระบบคำนวณคะแนนอัตโนมัติจาก `evaluation_items` (แทนกรอกคะแนนรวมเอง) | ✅ Done (coexists with manual mode — ดูหัวข้อ 4) | v0.6.0 |
| M | **[แทรกนอกลำดับ]** Master Control — CRUD admin-only สำหรับ suppliers/evaluation_criteria/user roles (ก่อนหน้านี้ suppliers เขียนไม่ได้เลย, evaluation_criteria อ่านไม่ได้เลย) | ✅ Done | v0.6.0 |
| 4 | Workflow การอนุมัติจริง (submit → approve, ผูกกับ role) | ✅ Done — QA submit + CS/MP submit ต้องครบก่อนจึง Approve ได้ (เฉพาะ `cs_supervisor`/`admin`) | v0.7.0 |
| 5 | หน้า Corrective Action Report (หน้า 2 ของ FM0704-3) | ✅ Done (ย้ายขึ้นมาก่อน Phase 3 — ดู Phase B ด้านล่าง) | v0.5.0 |
| 6 | ทำ PDF + ส่งอีเมลอัตโนมัติจริง + supplier acknowledgment | 🟡 Simplified version done — ดูหมายเหตุด้านล่าง | v0.7.0/v1.0.0 |
| 7 | รายงานสรุปรายปี (เทียบเท่า Sheet Summary Mat/Part) | ✅ Done — Yearly Summary tab | v1.0.0 |
| 8 | Migrate ข้อมูลเก่า + Pilot ใช้งานคู่ขนานกับ Excel | 🟡 Data imported, pilot ยังไม่เริ่ม | v0.2.0 |

> **สถานะรวม:** เสร็จ Phase 1, 2, A, 5(→B), 7 และ import ข้อมูลของ Phase 8 แล้ว Phase 6 ทำแบบง่าย (ไม่ auto-send email ตามที่ตกลงกันไว้ — ใช้การแนบไฟล์ + ปุ่มบันทึกสถานะส่ง/รับทราบแทน) มี Login + สิทธิ์ตามแผนกใช้งานได้จริงระดับ database คะแนน/เกรดจัดการเคส No Shipment ถูกต้อง เกรด C/D สร้าง Corrective Action อัตโนมัติพร้อม due date ยังไม่ได้เริ่ม Pilot คู่ขนานจริงกับผู้ใช้งาน
>
> **Phase 6 หมายเหตุ:** ตามที่ตกลงกันไว้ (ไม่เพิ่มระบบ security/auth ใหม่, ไม่ต้อง auto-send) — คำว่า "ทำ PDF+อีเมลอัตโนมัติ" ในชื่อ Phase นี้จึงไม่ตรงทั้งหมดกับสิ่งที่ทำจริง สิ่งที่ทำจริงคือ: (1) แนบไฟล์ PDF/หลักฐานเข้า evaluation หรือ CA ได้ (v0.7.0) (2) ปุ่ม "Mark Sent to Supplier"/"Mark Acknowledged" ให้ staff กดบันทึกเองหลังส่งอีเมลนอกระบบ (v1.0.0, ใหม่ในรอบนี้) — ถ้าต้องการ auto-send จริงในอนาคต ต้องเปิด topic ใหม่แยกต่างหาก

> **ทำไมต้องแทรก Phase A/B ก่อน Phase 3:** ตรวจสอบกับข้อมูลจริงเดือน ก.ค. 2026 พบว่า 5 จาก 30 supplier (ETO, AKIYAMA JP, DAIDO, KYOTO, UGITECH) มีปัญหา No-Shipment อยู่จริงในเดือนเดียว (~17%) และตัว `corrective_actions` ที่มีอยู่แล้วตั้งแต่ v0.1.0 **ใช้งานไม่ได้เลยตั้งแต่สร้างมา** (เปิด RLS ไว้แต่ไม่เคยมี policy — select/insert/update ถูก deny หมด) ปล่อยไว้แล้วไปทำ Phase 3 ต่อ จะยิ่งฝัง business rule ที่ผิดลงลึกกว่าเดิม และเกรด C/D ที่เกิดขึ้นระหว่างนี้จะไม่มีการติดตาม CA เลย

---

## 3. What exists right now

### 3.1 Database (Supabase / PostgreSQL)
ไฟล์: `01_schema.sql`

Tables ที่สร้างแล้ว:
- `suppliers` — master ข้อมูล Supplier
- `evaluation_criteria` — หัวข้อประเมินย่อยคงที่ (22 ข้อ ตาม FM0704-3)
- `evaluations` — ผลประเมินรายเดือน. `total_score`/`grade` **ไม่ใช่ generated column แล้วตั้งแต่ v0.4.0** เปลี่ยนเป็นคำนวณผ่าน trigger `compute_evaluation_score` (ดูข้อ 1 ในหัวข้อ Key decisions) — เพิ่มคอลัมน์ `shipment_status` ('normal'/'no_shipment'), `no_shipment_reason`, และ generated column ล้วนๆ อีก 2 ตัวสำหรับแสดงผล: `raw_score`, `applicable_weight`
- `evaluation_items` — รายละเอียดระดับหัวข้อย่อยต่อ evaluation (ยังไม่มีข้อมูล — รอ Phase 3)
- `corrective_actions` — CAR ตามฟอร์มหน้า 2. **ใช้งานได้จริงตั้งแต่ v0.5.0** (ก่อนหน้านี้เปิด RLS ไว้ตั้งแต่ v0.1.0 แต่ไม่เคยมี policy เลย = ใช้งานไม่ได้เลยจากแอป) เพิ่มคอลัมน์ `due_date`, มี trigger `auto_create_corrective_action` สร้างแถวอัตโนมัติเมื่อ evaluation ถูก approve เป็นเกรด C/D (ครบกำหนด 5 วันทำการ ผ่านฟังก์ชัน `add_working_days`)
- `evaluation_audit_log` — audit trail (ยังไม่ได้ใช้งานจริง — รอ Phase 4)

**Enum types:** `eval_category`, `eval_status`, `eval_grade`, `ca_status`, `department_role`

**RLS:** เปิดใช้งานทุกตารางแล้ว — ตั้งแต่ v0.3.0 เปลี่ยนจาก policy กว้างๆ เป็นสิทธิ์ตามแผนกจริง (ดูหัวข้อ 3.4). ตั้งแต่ v0.4.0 trigger สิทธิ์คอลัมน์ (`enforce_evaluation_edit_permissions`) ครอบคลุม `shipment_status`/`no_shipment_reason` ด้วย (นับเป็นฟิลด์ของ CS/MP เหมือน delivery)

### 3.2 Seed data (v0.2.0)
ไฟล์: `02_seed_data.sql`

- `evaluation_criteria`: 22 แถว (ตรงตาม FM0704-3 ทุกข้อ)
- `suppliers`: 32 บริษัท (29 รหัส `MA-` จาก Sheet "Summary Mat", 3 รหัส `PA-` จาก Sheet "Summary Part") พร้อม attention/tel จริงจากแต่ละ sheet
- `evaluations` (ประวัติ): 542 แถว — ปี 2025 เต็มปี + 2026 ม.ค.-มิ.ย. — **มีแค่คะแนนรวม ไม่มี breakdown Q/D/P** (ไฟล์ต้นทางไม่มีระดับนั้น)
- `evaluations` (ก.ค. 2026): 32 แถว — breakdown Quality/Delivery/Purchase จริง ดึงจากสูตร `Quality=P10+P20, Delivery=P24, Purchase=P32` ของแต่ละ sheet รายบริษัท — ตรวจสอบแล้วว่าผลรวมตรงกับ Total Score ในไฟล์ Excel ครบ 32/32 บริษัท

### 3.3 Auth & Roles (v0.3.0)
ไฟล์: `03_phase2_auth_and_roles.sql`

- ตาราง `user_profiles` (id ผูกกับ `auth.users`, `department` enum: qa/cs/mp/supervisor/admin) สร้างอัตโนมัติผ่าน trigger ตอนสมัคร (`handle_new_user`)
- Trigger `enforce_evaluation_edit_permissions` บังคับสิทธิ์ **ระดับคอลัมน์** บนตาราง `evaluations`:
  - QA แก้ได้เฉพาะ `quality_score`, `quality_comment`
  - CS/MP แก้ได้เฉพาะ `delivery_score`, `purchase_score`, `delivery_comment`
  - เปลี่ยน `status` เป็น `approved` ได้เฉพาะ supervisor/admin (auto stamp `approved_by`/`approved_at`)
  - supervisor/admin แก้ได้ทุกฟิลด์
- Frontend (`app/`) มีหน้า Login จริงแล้ว ปิดใช้งาน field ที่ role ไม่มีสิทธิ์แก้ให้อัตโนมัติ
- **อัปเดต:** ปิด self-service signup แล้ว (v04) — หน้าเว็บเหลือแค่ Sign in เท่านั้น การสร้าง user ใหม่ให้ทำผ่าน Supabase Dashboard → Authentication → Users → Add user เท่านั้น

### 3.4 Frontend
`app/index.html`, `app/style.css`, `app/app.js` — เชื่อม Supabase จริงแล้ว (ไม่ใช้ localStorage) มี Dashboard (เพิ่ม KPI "CA Overdue" ตั้งแต่ v0.5.0), Monthly Input (role-gated, Shipment Status v0.4.0, Scoring Mode manual/itemized v0.6.0, ปุ่ม submit แยก QA/CS-MP + ไฟล์แนบ v0.7.0), Evaluation List, Corrective Actions (v0.5.0, ไฟล์แนบ v0.7.0), **Master Control (ใหม่ v0.6.0, admin only)** — Suppliers/Evaluation Criteria/Users & Roles CRUD, Supplier Profile, Report Preview (print to PDF), Setup & Status tab

---

## 4. Key decisions & assumptions (สำคัญมาก อ่านก่อนแก้อะไร)

1. **`total_score`/`grade` ไม่ใช่ generated column แล้ว ตั้งแต่ v0.4.0** — ย้ายไปคำนวณผ่าน trigger `compute_evaluation_score` (BEFORE INSERT/UPDATE) แทน เพราะสูตรมี branching ตาม `shipment_status` และ PostgreSQL ไม่ให้ generated column อ้างอิง generated column อื่นในตารางเดียวกัน
   - **แก้ไขความเข้าใจผิดเดิม (เคยเขียนไว้ผิดในเอกสารนี้):** ก่อนหน้านี้เข้าใจว่ากรณี No Shipment ตัวหารควรเปลี่ยนเป็น **60** (ตัดแค่ Delivery 40 ออก แต่ยังเหลือ Purchase 10 อยู่ในตัวหาร) — ตรวจสอบกับข้อมูลจริงเดือน ก.ค. 2026 (5 supplier: ETO, AKIYAMA JP, DAIDO, KYOTO, UGITECH) แล้วพบว่า **60 คือสูตรเดิมของ Excel ที่เป็นบั๊ก** (Quality 50/50 → โชว์ 83.33%/B ทั้งที่ Quality เต็ม) สูตรที่ถูกต้องคือตัด **ทั้ง Delivery (40) และ Purchase (10)** ออกจากตัวหารเมื่อ No Shipment เหลือแค่ 50 (Quality เต็ม 50/50 = 100% = Grade A)
   - สูตรที่ implement จริงตอนนี้ (v0.4.0): `applicable_weight = 50 + (shipment_status='normal' ? 40:0) + (shipment_status='normal' ? 10:0)`, `total_score = round(raw_score / applicable_weight * 100, 2)` — กรณี `normal` (ปกติ) ตัวหารคือ 100 เหมือนเดิมทุกประการ ไม่กระทบข้อมูลเก่า เปลี่ยนเฉพาะเคส `no_shipment`
   - **ถ้า Phase 3 (auto-calc จาก `evaluation_items`) จะ generate คะแนนย่อยเอง ต้องคงหลักการนี้ไว้ — ห้ามกลับไปใช้สูตร ÷60 อีก**
2. **enum cast bug ที่เจอแล้ว**: PostgreSQL ไม่ auto-cast string literal เป็น enum ใน generated column ต้อง cast ชัดเจน (`'A'::eval_grade`) — แก้ไปแล้วใน `supplier_evaluation_schema.sql` เวอร์ชันปัจจุบัน
3. **ข้อมูลย้อนหลัง (542 แถว) เป็นคะแนนรวมเท่านั้น** ห้ามเชื่อ `quality_score`/`delivery_score`/`purchase_score` ของแถวเหล่านี้ตรงตัว — ใช้ `total_score`/`grade` เพื่อดู trend ได้เท่านั้น (มี comment กำกับไว้ในแต่ละแถวว่า "Historical import...")
4. **เดือน ก.ค. 2026 เท่านั้นที่มี breakdown แม่นยำ** — ตรวจสอบ cross-check กับ Excel แล้วครบ 100%
5. **Contact info (attention/tel) มีอยู่ในไฟล์ Excel จริง** (คอลัมน์ C4/I4 ของแต่ละ sheet) — ก่อนหน้านี้เข้าใจผิดว่าไม่มี ที่ถูกคือมีครบทุกบริษัท และ import เข้าไปแล้ว
6. ยังไม่มี field email ของ Supplier ในไฟล์ต้นทาง — ต้องหาแหล่งข้อมูลเพิ่มก่อนทำ Phase 6 (ส่งอีเมลอัตโนมัติ)
7. **แก้ default ที่ทำให้เข้าใจผิด (v0.4.0):** เดิม row ใหม่ของ `evaluations` default เป็น `quality_score=50, delivery_score=40, purchase_score=0` ซึ่งรวมแล้ว 90/B ทั้งที่ยังไม่มีใครกรอกอะไรเลย — แถวที่ "ยังไม่เริ่ม" หน้าตาเหมือน "ประเมินดีแล้ว" เปลี่ยน default ทั้ง 3 ฟิลด์เป็น `0` แล้ว (แถวใหม่ที่ไม่มีใครแตะจะเป็น 0/D ซึ่งสังเกตเห็นง่ายกว่าว่ายังไม่ได้ทำ)
8. **Corrective Action ไม่ล็อกสิทธิ์ตามแผนก (v0.5.0):** ต่างจาก `evaluations` ที่ QA/CS-MP แก้ได้เฉพาะคอลัมน์ตัวเอง — `corrective_actions` เปิดให้ authenticated user ทุกแผนกอ่าน/แก้ได้หมด เพราะการปิดเคส CA จริงต้องอาศัยหลายแผนกทยอยกรอกคนละช่วง (Problem → Root Cause → Action → Verify) ถ้าจะ tighten ทีหลังค่อยทำ
9. **"Overdue" ของ CA เป็นค่าที่คำนวณฝั่ง frontend** (`due_date < วันนี้ และ status ยังไม่ closed`) ไม่ใช่ค่าที่เก็บในคอลัมน์ `status` เพราะมันเปลี่ยนไปตามปฏิทินทุกวัน — enum `ca_status` ยังมีค่า `'overdue'` ไว้เผื่ออยากตั้งเองแบบถาวร แต่ไม่มี trigger ไหนตั้งให้อัตโนมัติ
10. **~~"5 วันทำการ" นับแบบ Mon-Fri เท่านั้น~~ — แก้แล้วใน v1.3.0:** เพิ่มตาราง `public_holidays` (seed ด้วยวันหยุดราชการไทยปี 2026 ที่ตรวจสอบแล้ว) `add_working_days()` ข้ามทั้งเสาร์-อาทิตย์และวันหยุดในตารางนี้ Admin เพิ่ม/แก้วันหยุดเองได้ที่ Master Control → Holidays (ปีถัดไปหรือวันหยุดเฉพาะบริษัทต้องเพิ่มเอง ยังไม่มีใครเพิ่มให้อัตโนมัติ)
11. **"Supervisor" retired จริงๆ แล้วตั้งแต่ v0.7.0** — enum ยังมีค่า `'supervisor'` อยู่ (Postgres ลบ enum value ไม่ได้) แต่ทุก account ที่เคยเป็น `supervisor` ถูก migrate เป็น `admin` แล้ว และไม่มีที่ไหนใน UI/logic ให้เลือก `supervisor` ได้อีก แยก role `cs_supervisor` ใหม่ออกมาต่างหาก — มีสิทธิ์แก้ delivery/purchase เหมือน CS/MP บวกสิทธิ์ approve evaluation (admin ก็ approve ได้เหมือนกัน)
12. **Approve ต้องรอทั้ง QA และ CS/MP submit ครบก่อน** — เพิ่มคอลัมน์ `quality_submitted_at/by`, `delivery_submitted_at/by` บังคับใน trigger `enforce_evaluation_edit_permissions` — กด "ส่งผลด้าน Quality"/"ส่งผลด้าน Delivery/Purchase" แยกปุ่มกันในหน้า Monthly Input จนกว่าจะครบทั้งคู่ ตัวเลือก "Approved" ใน dropdown สถานะจะยังกดไม่ได้
13. **CS/MP แยก login ต่อคน ไม่ share account** (ตามที่ตกลง) — สิทธิ์เหมือนกันทุกอย่างระหว่าง CS/MP อยู่แล้ว การแยก login มีไว้เพื่อ audit trail (`quality_submitted_by`/`delivery_submitted_by`/`approved_by` อ้างถึง `auth.users.id` เสมอ) ไม่ใช่เพื่อจำกัดสิทธิ์เพิ่ม
14. **ไฟล์แนบ ไม่ทำ Supplier Portal** — ตามที่ตกลง (PDF+Email ยังคงเป็นช่องทางส่งผลหลัก, ไม่เพิ่ม auth surface ใหม่) คำตอบ/หลักฐานจาก Supplier ที่ส่งกลับมาทางอีเมล ให้ staff อัปโหลดเป็นไฟล์แนบเข้า evaluation หรือ corrective action โดยตรงในแอป (ตาราง `evaluation_attachments` + Supabase Storage bucket `attachments`) — **ต้องสร้าง bucket เองใน Supabase Dashboard, SQL สร้างไม่ได้** (ดู `11_approval_flow_and_attachments.sql`)
15. **⚠️ บั๊กที่เจอและแก้แล้วใน v20 — session อื่น (v17-v19) rebuild หน้า Monthly Input เป็น "Official Worksheet"** (ดี ตรงกับแนวทาง Phase 3 เดิม) **แต่มี 2 จุดพัง:**
    - **เสี่ยงข้อมูลพัง:** `editEvaluation()`/`saveOfficialWorksheet()` เดิมไม่เช็ค `scoring_mode` เลย — เปิด evaluation เก่าที่เป็น `'manual'` (574 แถวเก่าทั้งหมด) แล้วกด Save ครั้งเดียว จะโดนบังคับแปลงเป็น `'itemized'` แล้วคำนวณคะแนนใหม่จาก checklist ที่ว่างเปล่า (เพราะไม่เคยมี `evaluation_items`) → **คะแนนจริงถูกเขียนทับเป็น 50/40/0 แบบไม่มีการเตือนเลย** แก้แล้วโดยเพิ่ม banner เตือน + `confirm()` popup ก่อนบันทึกทุกครั้งที่ evaluation ยังเป็น `'manual'` (ดู `renderOfficialWorksheet`/`saveOfficialWorksheet` ใน `app.js`)
    - **ปุ่ม Approve หายไปทั้งหมด:** `f_status` ถูกซ่อนเป็น `hidden` และไม่มีโค้ดจุดไหนเขียน `status:'approved'` เลย ทำให้ approve evaluation ไม่ได้จากหน้าเว็บอีกต่อไป (Phase 4 ทั้ง Phase ใช้งานจริงไม่ได้) แก้แล้วโดยเพิ่มปุ่ม "Approve Evaluation" / "Mark Sent to Supplier" / "Mark Acknowledged" แยกต่างหาก (ดูหัวข้อ 16)
    - **โค้ดซ้ำซ้อน:** `resetForm`/`editEvaluation`/`saveEvaluation` เคยถูกประกาศ 2 รอบในไฟล์เดียว (JS ใช้ตัวหลังทับตัวแรกเงียบๆ ไม่ error) — ลบตัวแรก (เดดโค้ด ~70 บรรทัด) ออกแล้ว เหลือ declaration เดียว
16. **Phase 6 แบบง่าย (v1.0.0):** ไม่ auto-send email ตามที่ตกลงไว้ก่อนหน้า — เพิ่มปุ่ม "Approve Evaluation" (เช็ค `cs_supervisor`/`admin` + submit ครบทั้งคู่ก่อนถึงจะกดได้), "Mark Sent to Supplier" (เขียน `sent_at`, เปิดใช้ได้เมื่อ approved แล้ว), "Mark Acknowledged" (เขียน `acknowledged_at`, เปิดใช้ได้เมื่อ sent แล้ว) — staff ส่งอีเมล/PDF นอกระบบเอง แล้วกลับมากดปุ่มบันทึกสถานะในแอป ไม่มี RLS ใหม่ (สถานะเหล่านี้ authenticated ทุกคนกดได้ ยกเว้น approve ที่ล็อกด้วย role)
17. **Phase 7 (v1.0.0):** เพิ่มแท็บ "Yearly Summary" — ตาราง Supplier × เดือน (1-12) + เฉลี่ย YTD + เกรด เทียบเท่า Sheet Summary Mat/Part ของ Excel เดิม กรองตาม Category ได้ (ใช้ field `suppliers.category` เดิม) ไม่มีการเปลี่ยน schema
18. **Corrective Action permission tiers (v1.1.0):** เดิมเปิดกว้างให้ authenticated ทุกคนแก้/ลบได้หมด (v0.5.0) — ตอนนี้แยกชัดแล้ว: **สร้างใหม่** = CS/MP/CS Supervisor/Admin (ไม่รวม QA), **แก้ไข/ลบรายการที่เปิดแล้ว** = CS Supervisor/Admin เท่านั้น, **QA แก้ได้เฉพาะ** `root_cause`/`action` (ผ่าน trigger `enforce_ca_edit_permissions` เช็ค column-level เหมือน evaluations), **ลบไฟล์แนบ** = CS Supervisor/Admin เท่านั้น (กฎเดียวกันใช้ทั้งไฟล์แนบของ evaluation และของ CA เพราะใช้ตาราง `evaluation_attachments` ร่วมกัน) **อัปโหลดไฟล์แนบ** ยังเปิดกว้างให้ทุกฝ่ายที่เกี่ยวข้อง — ดู `12_ca_permission_tiers.sql`
19. **~~หน้า "Permissions" ใน Master Control เป็นข้อมูลอ้างอิงเท่านั้น~~ — แก้แล้วใน v1.2.0: ตอนนี้แก้ได้จริง** เพิ่มตาราง `permission_rules` (rule_key × department × allowed) ที่ trigger/RLS ทุกตัวอ่านค่าจากตารางนี้ผ่านฟังก์ชันกลาง `has_permission(rule_key)` แทนการ hardcode `department in (...)` แบบเดิม — Admin ติ๊ก/ปลดติ๊กในหน้า Permissions แล้วมีผลทันทีทั้งฝั่ง DB (บังคับจริง) และฝั่งหน้าเว็บ (โหลด rules มา gate ฟอร์ม/ปุ่มแบบเดียวกัน ผ่าน `hasPerm()` ใน `app.js`) — ดู `13_dynamic_permission_rules.sql`
    - rule_key ที่มีตอนนี้: `eval_edit_quality`, `eval_edit_delivery`, `eval_approve`, `eval_delete`, `ca_create`, `ca_edit_full`, `ca_edit_restricted`, `ca_delete`, `attachment_upload`, `attachment_delete`, `master_data_manage`
    - ค่าเริ่มต้นที่ seed มาตรงกับกฎเดิมทุกตัว (v1.1.0) ไม่กระทบพฤติกรรมปัจจุบัน จนกว่า Admin จะไปกดเปลี่ยนเอง
    - **บั๊กที่เจอระหว่างทำ (แก้แล้ว):** `worksheetRoleAccess()` เดิมให้ CS/MP แก้ A2 Environmental ได้ (เพราะเทียบ string `category==='environment'` ผิด ทั้งที่ A2 เป็น DB category `'quality'` เหมือน A1) ทั้งที่ DB trigger จะ reject อยู่แล้วเวลาบันทึกจริง (error สับสน) — แก้ให้ A1+A2 ผูกกับ `eval_edit_quality` เหมือนกันแล้ว
    - **บั๊กเดิมอีกจุด (แก้แล้ว):** `enforce_evaluation_edit_permissions` เวอร์ชันก่อนหน้า ให้ admin ข้ามเงื่อนไข "QA+CS/MP submit ครบก่อน approve" ไปเลย (cs_supervisor ต้องผ่านเงื่อนไขนี้ แต่ admin ไม่ต้อง — ไม่สม่ำเสมอ) ตอนนี้ทุก department ที่มี `eval_approve` ต้องผ่านเงื่อนไข submit ครบเหมือนกันหมด รวม admin ด้วย
20. **ข้อจำกัดของระบบ permission แบบ dynamic นี้:** แก้ได้แค่ "ใครทำอะไรได้" ตาม rule_key ที่กำหนดไว้แล้วเท่านั้น (11 ตัวด้านบน) — เพิ่ม rule_key ใหม่ หรือเพิ่ม department ใหม่ ยังต้องแก้ SQL/deploy migration ใหม่อยู่ดี (เพราะต้องมีโค้ดจริงๆ ไปเรียก `has_permission('rule_key_ใหม่')` ที่จุดที่เกี่ยวข้อง ไม่ใช่แค่เพิ่มแถวในตาราง)
21. **คำแปลไทยของหัวข้อประเมิน (v1.3.0):** ตรวจไฟล์ Excel ต้นฉบับแล้ว (ทั้ง sheet FM0704-3 จริงและ sheet "ตัวอย่างสูตร") **พบว่าทั้งไฟล์เป็นภาษาอังกฤษล้วน ไม่มีคำแปลไทยอยู่จริงอย่างที่คาดไว้ทีแรก** — คำแปลไทยทั้งหมดที่ใส่เข้าไป (`evaluation_criteria.description_th`) เป็นการแปลขึ้นใหม่ ไม่ได้ดึงมาจากไฟล์ ถ้าพบคำแปลไม่ตรงกับที่ทีมงานคุ้นเคย แก้ไขได้ที่ Master Control → Evaluation Criteria (มีช่อง "Description (TH)" ให้แก้เองแล้ว)
22. **Sidebar เปลี่ยนเป็น `position:fixed` (v1.3.0):** จากเดิมเป็น flex sibling ของ `.main` ทำให้สูงยืด/หดตามเนื้อหา ตอนนี้ fix เป็น `height:100vh` เต็มจอเสมอ ไม่ขึ้นกับเนื้อหาเมนูหรือความยาวหน้า — `.main` ใช้ `margin-left:230px` แทนแล้ว (230px = ความกว้าง `.rail`) ถ้าจะเปลี่ยนความกว้าง sidebar ทีหลัง ต้องแก้ทั้ง 2 จุดให้ตรงกัน
23. **`evaluation_cycles` table + "Open Monthly Cycle" (v1.3.0):** ตามที่ Dashboard v0.8.0 เคย note ไว้ว่า "cycle coverage ยังคำนวณจาก evaluations ตรงๆ" — เพิ่มตารางนี้ + ปุ่ม "Open Monthly Cycle" ใน Setup & Status (admin only) กด 1 ครั้งจะสร้าง evaluation แบบร่าง (draft/itemized/0 คะแนน) ให้ Supplier active ทุกบริษัทที่ยังไม่มีรายการเดือนนั้น รันซ้ำได้ปลอดภัย (ไม่แตะ evaluation ที่มีอยู่แล้ว) — **แต่ Dashboard ยังไม่ได้ผูกเข้ากับตารางนี้** (ยังคำนวณ cycle coverage จาก evaluations ตรงๆ เหมือนเดิม) เป็นงานต่อยอดในอนาคตถ้าต้องการ
24. **หน้าจอ Loading + ปุ่ม disabled ที่ดูไม่ออกว่า disabled (v1.4.0):** เดิม `appShell` โชว์ทันทีตอน login สำเร็จ ก่อน `reloadAll()` (8 ขั้นตอนเรียงกัน) จะโหลดเสร็จ ทำให้เห็น dashboard ว่างๆ/ครึ่งๆ กลางๆ ช่วงที่ยังโหลดไม่ครบ — เพิ่ม loading overlay (progress bar + hourglass animation + "กำลังโหลด X (i/8)") บังหน้าจอไว้จนกว่า `reloadAll()` จะเสร็จจริง และพบว่า **ปุ่ม `.btn:disabled` ไม่เคยมี style แยกจากปุ่มปกติเลยตั้งแต่แรก** (สาเหตุที่ปุ่ม Approve/input ต่างๆ ดู "เหมือนกดได้" ทั้งที่จริงๆ disabled อยู่) เพิ่ม `.btn:disabled`/`input:disabled` ให้จางลงชัดเจนแล้ว
25. **หน้า Loading โผล่ทุกครั้งที่สลับ browser tab (แก้แล้ว v1.4.1):** สาเหตุคือ `sb.auth.onAuthStateChange` ยิง event `TOKEN_REFRESHED` ทุกครั้งที่กลับมาที่ tab (Supabase client refresh token อัตโนมัติ) และโค้ดเดิมเรียก `reloadAll()` ทุกครั้งที่ event นี้ยิงแบบไม่กรอง — ก่อนหน้านี้ (ตอนยังไม่มี loading overlay) ไม่มีใครสังเกตเพราะไม่มีอะไรกระพริบให้เห็น แต่พอมี overlay เต็มจอ ก็เห็นชัดว่าโหลดซ้ำโดยไม่จำเป็น แก้โดยเช็คใน `handleSession()`: ถ้าเป็น user คนเดิมที่โหลดข้อมูลอยู่แล้ว (appShell เปิดอยู่) จะข้าม reload ทั้งหมด ไม่ต้องรอ event type จาก Supabase (เผื่อ SDK เปลี่ยนชื่อ event ในอนาคต)
26. **Default ภาษาเปลี่ยนเป็นไทย (v1.4.1):** `let lang = safeLSGet('se_lang') || 'th'` (เดิม default 'en') — ผู้ใช้ที่เคยเปลี่ยนเป็น EN เองไว้แล้วยังคงเป็น EN ตามที่เลือกไว้ (เก็บใน localStorage) กระทบเฉพาะผู้ใช้ใหม่/เบราว์เซอร์ใหม่ที่ยังไม่เคยตั้งค่า
27. **UI polish ตาราง (v1.5.0):** ตาราง list ทุกหน้า (Evaluation List, CA, Master Control ฯลฯ) ใช้ CSS ชุดใหม่ร่วมกัน — การ์ดขอบมน + เส้นขอบ, hover แถวไฮไลท์, badge เป็นทรงยาวมีจุดสีนำหน้า, ปุ่ม "แก้ไข/ลบ" เปลี่ยนจากตัวหนังสือสีล้วนเป็นปุ่มขอบบางมี hover state ชัดเจนขึ้น ไม่ได้เปลี่ยนโครงสร้าง HTML/ฟังก์ชันใดๆ แก้แค่ `style.css`
28. **ข้อความ Login/Create ID บอกผลชัดเจนขึ้น (v1.5.0):** เดิม sign-in ที่สำเร็จไม่มีข้อความอะไรเลยก่อนหน้าจอเปลี่ยนไป Dashboard (อาจดูเหมือนไม่มีอะไรเกิดขึ้นถ้ามี delay) — เพิ่มข้อความ "เข้าสู่ระบบสำเร็จ — กำลังโหลดข้อมูล…" ก่อน transition และแปล error message ที่เจอบ่อยที่สุดจาก Supabase (เช่น "Invalid login credentials") เป็นไทยให้อ่านเข้าใจง่ายขึ้นเมื่อตั้งค่าเป็น TH (ฟังก์ชัน `friendlyAuthError()`) ข้อความ login/signup ทั้งหมดตอนนี้แสดงเป็น banner แจ้งเตือนสีเขียว/แดงชัดเจนแทนตัวหนังสือสีเปล่าๆ
29. **แยกคอลัมน์ Q/E ในตาราง Evaluation List (v1.6.0):** DB เก็บ Quality+Environment รวมเป็นตัวเลขเดียว (`quality_score`) มาตั้งแต่แรก — แยกจริงได้เฉพาะ evaluation ที่เป็น `scoring_mode='itemized'` (คำนวณจาก `evaluation_items` ย้อนกลับ ผ่านฟังก์ชัน `qualityEnvSplit()`) ส่วน evaluation แบบ `manual` (574 รายการเดิม) แสดง Q = ค่ารวมเดิม, E = "-" เพราะไม่มีข้อมูลให้แยกจริงๆ (ตกลงกับผู้ใช้แล้วว่าเอาเท่าที่มี)
30. **ตัวเลขคะแนนประเมินแสดงแบบปัดเป็นจำนวนเต็ม + hover ดูทศนิยม 2 ตำแหน่ง (v1.6.0):** ฟังก์ชัน `scoreNum(value)` คืน `<span title="X.XX">Y</span>` — ใช้เฉพาะกับ**คะแนนประเมิน**เท่านั้นตามที่ตกลง (total_score, quality/delivery/purchase score, ค่าเฉลี่ยคะแนน) ไม่ใช้กับตัวเลขนับจำนวน (KPI count, occurrence) **ข้อยกเว้น: หน้า Report Preview (สำหรับพิมพ์/ส่ง Supplier) ไม่ใช้ scoreNum** เพราะ tooltip ใช้ไม่ได้ตอนพิมพ์ออกมาเป็น PDF — คงแสดงทศนิยมเต็มตรงๆ ในรายงานที่จะพิมพ์แทน
31. **รูปแบบเดือน-ปี "2026-Jul" ทุกจุด (v1.6.0):** ฟังก์ชัน `ymLabel(year, month)` ใช้แทนที่การโชว์ปี/เดือนแยกคอลัมน์หรือรูปแบบอื่นๆ ทั่วแอป (Evaluation List, Supplier Profile, Corrective Actions, Report Preview, Dashboard period selector) **ข้อยกเว้น:** กราฟ trend 12 เดือนบน Dashboard (canvas, พื้นที่แคบ 12 จุดในกราฟเดียว) ใช้แค่ชื่อเดือนย่อ (ไม่ใส่ปี) เพราะพื้นที่ไม่พอ, ตาราง Yearly Summary ไม่เปลี่ยน (โครงสร้างเป็น matrix ที่ header คือชื่อเดือนอยู่แล้ว ไม่มีอะไรให้ "รวม" เพิ่ม)
32. **Back/Forward navigation (v1.7.0):** ใช้ browser History API จริง (`history.pushState`/`popstate`) ไม่ได้ทำ custom stack เอง — แต่ละ tab switch push state ใหม่ ส่วนการเปิดดู record เฉพาะ (evaluation/CA/supplier profile/report) จะ `replaceState` แนบ id เข้าไปในตำแหน่งปัจจุบัน ทำให้ Back พากลับไปที่ record เดิมที่เปิดดูจริงๆ ไม่ใช่แค่กลับไป tab เฉยๆ ปุ่ม Back/Forward บน topbar เป็นแค่ shortcut เรียก `history.back()`/`history.forward()` เหมือนปุ่มเบราว์เซอร์เป๊ะ ไม่ได้มี logic แยกของตัวเอง
33. **Dashboard: รวม "Priority Queue" กับ "Early Warning" เป็นการ์ดเดียว (v1.7.0)** — เดิม 2 การ์ดนี้ overlap กันเยอะ (ทั้งคู่เช็คเงื่อนไข "CA เกินกำหนด" กับ "คะแนนลดลง" ซ้ำกัน) ต่างกันแค่ Priority เรียงตาม risk score รวม (threshold≥35, ครอบคลุมกว้างกว่ารวมเหตุผลอื่นเช่น below target) ส่วน Early Warning เจาะจงที่ "มีการเปลี่ยนแปลงล่าสุด" (declining 3 รอบ/ตกแรง/CA เกินกำหนด) เท่านั้น ไม่สนใจ risk score รวม — ตอนนี้รวมเป็น list เดียว sort ตาม risk score พร้อม badge "Priority"/"Early Warning" ต่อแถวว่า trigger จากเงื่อนไขไหนบ้าง (มีได้ทั้งคู่พร้อมกัน)
34. **Import ข้อมูล July 2026 แบบ itemized จาก Excel จริง (v1.7.0):** `17_import_july_2026_itemized.sql` — ดึงจำนวนครั้งที่เกิดขึ้นจริงต่อหัวข้อ (คอลัมน์ N "Time Score" ในแต่ละ sheet supplier) มาใส่ `evaluation_items` ให้ 31 จาก 32 supplier (ยกเว้น MA-088 Yamaichi ที่ sheet ชื่อ "No eva YAMAICHI" จริงๆ มีข้อมูลเดือนมิถุนายนอยู่ ไม่ใช่กรกฎาคม — ตรวจสอบจาก cell S4 ของแต่ละ sheet แล้ว) พร้อมตั้ง `scoring_mode='itemized'` และ `shipment_status` ตามค่า wDelivery/wPurchase ของ July ในแต่ละ sheet (พบว่ามี 9 จาก 31 supplier เป็น No Shipment เดือนนี้ ไม่ใช่แค่ 5 ที่เคยสุ่มเช็คบางส่วนไว้ตอนต้น) — **ผลข้างเคียงที่ดี:** คะแนนของ supplier ที่เคย No Shipment จะถูกคำนวณใหม่ให้ถูกต้องตามสูตรที่แก้ใน Phase A โดยอัตโนมัติ (เช่น ALMET THAI จาก 76.67% ตามสูตรเดิมของ Excel ที่เป็นบั๊ก → 92% ตามสูตรที่ถูกต้อง)
    - **บั๊กที่เจอตอน implement (แก้แล้ว v1.7.1/v1.7.2):** สคริปต์เดิมใช้ `UPDATE evaluations` ธรรมดา ถ้าแถวยังไม่มีจะไม่ทำอะไรเลยเงียบๆ ทำให้ INSERT evaluation_items ถัดไปหา evaluation_id ไม่เจอ (NULL) พังทั้ง transaction เปลี่ยนเป็น `INSERT ... ON CONFLICT DO UPDATE` (upsert) แล้ว ทำให้สคริปต์ไม่ต้องพึ่งพาว่าต้องมี evaluations row มาก่อนอีกต่อไป
    - **Import/Export function แบบเต็ม (อัปโหลด Excel ใหม่ทุกเดือน + export กลับเป็น format เดิม) ยังไม่ได้ทำ** — เป็นฟีเจอร์แยกที่ใหญ่กว่านี้มาก รอ scope แยกต่างหากถ้ายังต้องการ
35. **Supplier กลุ่ม Outsource (Heat Treatment/Plating) — เพิ่ม 22 รายใหม่ (v1.8.0):** `18_import_heat_plating_suppliers.sql` — จากไฟล์ `01_FM-0704-3_..._Jul-26_.xlsx` ใช้ code prefix `OS-001`..`OS-022`, `category='Outsource'` ใช้ template/สูตร import เดียวกับ Material (Phase A No-Shipment fix ใช้ได้เหมือนกัน, พบ 5 supplier กลุ่มนี้เป็น No Shipment เดือนนี้ด้วย) — **สิ่งที่ต้องเช็คก่อนเชื่อ:** เซลล์ "wQuality/wDelivery/wPurchase" ในไฟล์นี้ไม่ใช่ "น้ำหนักคงที่" แบบที่ชื่อบอก แต่เป็น**คะแนนที่ได้จริงเดือนนั้น** (ยืนยันจาก SAHASIN ที่ wQuality=44 ไม่ใช่ 50) — ไม่กระทบ logic การ import เพราะเราคำนวณจาก occurrence column (N) โดยตรงอยู่แล้ว ไม่ได้อิงจากเซลล์นี้ แต่บันทึกไว้กันงงถ้ามีคนอ่าน Excel เทียบเอง
36. **Action Board บน Dashboard (v1.8.0):** ปักหัวสุดของ Dashboard เดิม (ไม่ทำหน้าแยก) แบ่ง 3 คอลัมน์ QA / CS-MP / CS Supervisor แสดง top 5 รายการต่อคอลัมน์ + "ดูทั้งหมด" ถ้าเกิน, คอลัมน์ที่ตรงกับสิทธิ์ผู้ใช้ (`hasPerm()`) จะไฮไลท์กรอบสี ส่วนคอลัมน์อื่นแสดงจางเป็น context — **ไม่ผูกกับ filter ของ Dashboard เอง** (period/category/shipment/risk) เพราะ to-do ควรโชว์งานค้างจริงเสมอ ไม่ใช่หายไปเพราะ filter ถูกตั้งไว้ — ตรรกะที่ใช้: QA=รอ submit quality + CA ที่ยังเปิดอยู่(เรียง overdue ก่อน), CS/MP=supplier ที่ยังไม่เปิดรายการเดือนปฏิทินปัจจุบัน + รอ submit delivery/purchase + approved แล้วรอ mark sent, CS Supervisor=submit ครบทั้งคู่แล้วรออนุมัติ
37. **ตัด "Mark Acknowledged" ออก + เปิดให้แก้/ปิด CA ได้ทันทีที่สร้าง (v1.9.0):** เดิม flow มี 3 สถานะกด (Approve→Mark Sent→Mark Acknowledged) และเคยคิดจะล็อกไม่ให้แก้ CA จนกว่าจะ Acknowledge — ตัดทั้งคู่ทิ้งหลังคุยกันแล้วว่าซ้ำซ้อนและไม่มีประโยชน์จริง (ไม่มีใครนั่งเช็คว่า Supplier "เปิดอ่าน" หรือยัง สิ่งที่พิสูจน์ว่า Supplier ตอบสนองจริงคือไฟล์แก้ไขที่ส่งกลับมาต่างหาก) กฎใหม่:
    - **เกรด A/B:** กด "Mark Sent to Supplier" ครั้งเดียว → ระบบตั้ง `status='acknowledged'` ให้อัตโนมัติทันที (ใช้ enum value เดิม ไม่เพิ่ม column ใหม่) ปิดเคสในคลิกเดียว ไม่ต้องกดอะไรต่อ
    - **เกรด C/D:** CA ที่ auto-create ไว้ตอน Approve แก้ไข/แนบไฟล์ได้ทันที ไม่มีการล็อกรอ Acknowledge (ซึ่งจริงๆ เดิมก็ไม่เคย implement เป็น hard-lock ไว้ตั้งแต่แรกด้วย)
    - เพิ่มปุ่ม **"Mark Received Countermeasure"** ในฟอร์ม CA — กดแล้ว set `status='closed'` + `finished_date=today` ปิดเคสในคลิกเดียว (แทนการเปลี่ยน dropdown สถานะด้วยมือ)
    - เพิ่ม permission rule ใหม่ `ca_close` (seed: qa=true, cs_supervisor=true, admin=true, cs/mp=false) — **QA เป็น role แรกที่แก้ status ของ CA ได้** แต่จำกัดเฉพาะเปลี่ยนเป็น 'closed' เท่านั้น เปลี่ยนเป็นค่าอื่นไม่ได้ (บังคับใน `enforce_ca_edit_permissions` เวอร์ชันใหม่) — ดู `19_ca_close_permission.sql`
    - Action Board ฝั่ง QA เหลือ CA เป็น**กลุ่มเดียว** (ไม่แยก "รอไฟล์"/"ไฟล์มาแล้ว" อีกต่อไป) ข้อความบอกแค่ "เปิดอยู่ — กรอกข้อมูล/แนบไฟล์ แล้วปิดเคสได้เลย"
38. **Two-tier approval + CA ย้ายเจ้าของจาก QA → CS/MP เต็มรูปแบบ (v2.0.0) — เปลี่ยนใหญ่สุดของ session นี้:**
    - **Role ใหม่ 2 ตัว:** `mp_supervisor` (สิทธิ์เหมือน `cs_supervisor` เป๊ะ ทุก rule_key แค่แยก department เพื่อ log ว่าใคร approve) และ `opd_manager` (ดูแลรวมทั้ง CS+MP คนเดียว ไม่แก้คะแนน/CA เลย มีแค่สิทธิ์ manager approve)
    - **Status ใหม่ 2 ตัวใน `eval_status` enum:** `sup_approved`, `mgr_approved` — **ไม่ได้ reuse `'approved'` เดิม** ตามที่ยืนยันไว้ (`'approved'` เดิมถูกปลดระวางไปเฉยๆ เหมือน `'supervisor'` department — enum ลบค่าไม่ได้)
    - **Flow ใหม่:** Submit ครบ (QA+CS/MP) → **Supervisor Approve** (`cs_supervisor`/`mp_supervisor`/`admin`, เงื่อนไข submit ครบเหมือนเดิม) → **Manager Approve** (`opd_manager`/`admin` เท่านั้น, ต้องผ่าน Supervisor ก่อนเสมอ, **ทุกเคสไม่มีข้อยกเว้นเกรด**) → Mark Sent (เปิดใช้ได้เมื่อ `status='mgr_approved'` เท่านั้น)
    - **CA auto-create ย้ายจาก trigger บน `'approved'` ไปเป็น trigger บน `'mgr_approved'`** — สร้าง CA ก็ต่อเมื่อ Manager approve แล้วเท่านั้น (ตามที่ตกลง "รอ manager approve ก่อนค่อยสร้าง")
    - เพิ่มคอลัมน์ audit แยก `sup_approved_by/at`, `mgr_approved_by/at` (คนละคู่กับ `approved_by/at` เดิมที่เลิกใช้แล้ว) เพื่อ log ว่าใคร approve ระดับไหนเมื่อไหร่
    - **CA ย้ายเจ้าของจาก QA → CS/MP เต็มรูปแบบ** — QA เหลือแค่กรอก+submit Quality/Environment เท่านั้น ไม่แตะ CA อีกต่อไป (`ca_edit_restricted`/`ca_close` ของ QA ปิดหมด), CS/MP ได้ `ca_edit_full` (แก้ได้ทุกฟิลด์รวมถึงปิดเคสเอง) **ยกเว้นสิทธิ์ลบ (`ca_delete`) ที่ยังเป็นของ Supervisor/Admin เท่านั้น** ("Supervisor เก็บไว้แค่สิทธิ์ override/ลบ")
    - Action Board ขยายจาก 3 เป็น **4 คอลัมน์**: QA / CS-MP / Supervisor (`eval_sup_approve`) / Manager (`eval_mgr_approve`)
    - **ยังไม่ได้ทำ:** export ฟอร์มผลประเมิน 2 ชีต (ฟอร์มผลประเมิน + ฟอร์มตอบการแก้ไข) พร้อม auto-mapping ดึงข้อมูลจากไฟล์ที่ Supplier ส่งกลับมาขึ้นในแอปอัตโนมัติ — รอคุย format ให้ชัดก่อนจะประเมิน scope
39. **แก้บั๊ก + เพิ่ม filter ที่ Action Board (v2.0.1):**
    - **บั๊ก:** ตอนย้ายเจ้าของ CA จาก QA→CS/MP ใน v33 แก้ permission ถูกแล้ว แต่ลืมย้ายโค้ด Action Board — รายการ CA ยังโผล่ที่คอลัมน์ QA เหมือนเดิม แก้แล้วให้ push เข้า `csItems` ตรงตาม permission จริง
    - **เพิ่ม filter:** Action Board เดิมดึงงานค้าง**ทุกเดือนย้อนหลังทั้งหมด** (เห็นในภาพจริง 607/650 รายการ!) ทำให้ใช้งานไม่ได้จริง — ย้าย filter bar เดิมของ Dashboard (period/group/shipment/risk) ขึ้นมาไว้เหนือ Action Board แล้ว **ใช้ตัวเดียวกันกรองทั้ง Action Board และ widget วิเคราะห์ด้านล่างทั้งหมด** (ไม่ใช่ filter แยกอันใหม่) — default เป็นเดือนล่าสุดที่มีข้อมูลจริงอยู่แล้ว (`populateDashboardFilters` เดิม sort แล้วเลือก indexแรก) ยกเว้นรายการ "Supplier ยังไม่เปิดเคสเดือนนี้" ที่ยังผูกกับปฏิทินจริงเสมอ (ไม่ตาม filter ที่เลือกดู) แต่ยัง filter ตาม supplier group ได้
    - **แก้ supplier category ให้ถูกต้อง (`21_supplier_category_cleanup.sql`):** เดิม MA-xxx/PA-xxx ไม่มี category เลย (NULL) และ 22 supplier กลุ่ม Outsource ถูกรวมเป็นก้อนเดียวหมด ไม่แยก Heat Treatment/Plating — ตั้งเป็น `Material`/`Part` ตาม prefix, แยก Outsource 14/22 รายเป็น `Heat Treatment`/`Plating` ตาม keyword ในชื่อบริษัท (Thermo/Induction/Heat Treatment → Heat Treatment; Plating/Mekki/Coating/Parkerizing/Electro Chemical/Surface Technology → Plating) **อีก 8 รายที่ไม่มี keyword ชัดเจน (Tanabe, Union Autoparts, T.I.D., Taiyo Seisakusho, B.K.J., Trix, Silvec, Miyaki) ยังเป็น `Outsource` เฉยๆ — เป็นการเดาจากชื่อบริษัท ไม่ได้ verify จริง แก้ไขเองได้ที่ Master Control ถ้าทราบประเภทจริง**

40. **Reject flow (v2.1.0):** Reject กลับไป `status='draft'` เสมอ ไม่ว่า reject จากชั้น Supervisor หรือ Manager — QA/CS-MP ต้อง submit ใหม่ทั้งคู่ (เคลียร์ `quality_submitted_at`/`delivery_submitted_at`) บังคับกรอกเหตุผล (`rejection_reason` — DB บังคับ ไม่ใช่แค่ frontend) เก็บ `rejected_by`/`rejected_at` — สังเกตว่าสถานะ `status` ยังเป็น `'draft'` เดิมตลอดตอนรอ Supervisor review (ไม่มี status 'submitted' จริงในระบบ) เพราะงั้น "reject ระดับ Supervisor" ไม่ใช่ status transition แต่คือการเคลียร์ submitted_at ตอน status ยังเป็น draft — ส่วน "reject ระดับ Manager" คือ transition จริง `sup_approved→draft`
41. **Action Log ทั่วระบบ (v2.1.0):** ตาราง `admin_action_log` ผ่าน generic trigger `log_admin_action()` แนบกับ 6 ตาราง (evaluations, corrective_actions, suppliers, evaluation_criteria, permission_rules, user_profiles) เก็บ before/after snapshot ทุก insert/update/delete — **ทุกคนดูได้ Admin เท่านั้นที่ revert ได้** ผ่าน RPC `revert_admin_action()` (ใช้ `jsonb_populate_record` แปลง type อัตโนมัติ ไม่ต้อง cast มือ) — Revert ได้เฉพาะ insert/delete เสมอ + update ที่ **ไม่ได้เปลี่ยนคอลัมน์ `status`** (workflow transition อย่าง submit/approve/reject/close เห็นใน log แต่กดย้อนไม่ได้ ตามที่ตกลงกันไว้ว่า 🔴 อันตรายเกินจะ auto-revert)
42. **Master Criteria Versioning (v2.1.0):** เพิ่ม `lineage_id`/`version`/`superseded_by` ให้ `evaluation_criteria` — หัวข้อที่เคย `criteria_is_used()` แล้ว (มี evaluation_items อ้างอิง) **ล็อกทุกฟิลด์ยกเว้น `display_order`/`is_active`** แก้ตรงไม่ได้เลย ต้องผ่าน RPC `create_criteria_version()` (ปิดตัวเก่า + สร้างตัวใหม่ lineage เดิม version+1) — ตัวใหม่ที่ยังไม่เคยใช้เลยสร้างผ่าน `create_new_criteria()` เริ่ม lineage ใหม่ — Frontend (`saveCriteria()`) เช็ค `criteria_is_used()` ก่อนตัดสินใจว่าจะ plain-update หรือเรียก versioning RPC โดยอัตโนมัติ ไม่ต้องให้ user เลือกเอง (ผูกกับปุ่ม Edit ที่กดมาแทน) — Dashboard Issue Pareto group ตาม `lineage_id` ไม่ใช่ `id` เพื่อรวมยอดข้าม version ให้ถูกต้อง
46. **จัดระเบียบเมนู/หน้าที่ของแต่ละหน้าใหม่ (v2.5.0)** — โครงสร้างเดิมมีหลายหน้าที่ทำ 2-3 อย่างปนกันจนงง แก้ 5 จุด:
    - **แยก Corrective Action list ออกจากฟอร์ม** — เดิมหน้าเดียวโชว์ฟอร์มสร้าง/แก้ไข + ตารางรายการพร้อมกันตลอด ตอนนี้ default = ดูรายการอย่างเดียว (`caListPanel`) กด "+ New" หรือ "แก้ไข" ต่อแถวถึงจะเปิดฟอร์ม (`caFormPanel`, มีปุ่ม "← กลับไปที่รายการ") — สลับ view ด้วย `showCaList()`/`showCaForm()`, ผูกกับ `showTab('ca')` ให้ default เป็น list เสมอเวลาเข้าจาก nav โดยตรง
    - **ลบปุ่ม "Import from Excel…" ออกจากหน้า Evaluation List** — ซ้ำซ้อนกับเมนู Import/Export ที่มีอยู่แล้ว เหลือแค่ปุ่ม Export (ซึ่งจำเป็นต้องอยู่ที่นี่เพราะผูกกับ checkbox เลือกรายการต่อแถวโดยธรรมชาติ) พร้อมข้อความเล็กๆ ชี้ไปเมนู Import/Export แทน
    - **เพิ่ม cross-reference กลับ** — หน้า Import/Export มี panel "Export to Excel" อธิบายว่า export ต้องไปทำที่ Evaluation List พร้อมปุ่มพาไปเลย (ไม่ได้ย้าย Export มาจริงๆ เพราะ UX ต้องอาศัย checkbox ต่อแถวซึ่งอยู่ที่ List เป็นธรรมชาติที่สุด)
    - **ย้าย "Open Monthly Cycle" จาก Setup & Status ไป Master Control → Suppliers** — เพราะเป็น workflow action ที่ทำงานจริง ไม่ใช่แค่ดูสถานะ (Setup & Status ควรเหลือแค่ดูอย่างเดียว)
    - **แยก Activity Log ออกจาก Master Control เป็นเมนูของตัวเอง** (top-level nav ใหม่) — **สำคัญ: ไม่ใช่ admin-only เหมือน Master Control** เพราะ requirement เดิมคือ "ทุกคนดูได้ Admin เท่านั้นที่ revert ได้" เกือบพลาดไปตั้งเป็น admin-only ตอนย้าย แก้แล้วให้เห็นเมนูนี้เสมอสำหรับทุกคนที่ login อยู่ (ปุ่ม Revert ในตารางยังคง gate ด้วย `hasPerm('master_data_manage')` เหมือนเดิม)

45. **Import / Export ฟอร์ม FM0704-3 Excel (v2.3.0):** แท็บใหม่ "Import / Export" (admin only) — ใช้ SheetJS (CDN) ทำงานในเบราว์เซอร์ล้วนๆ ไม่ต้องมี server แยก
    - **Import:** อัปโหลดได้หลายไฟล์พร้อมกัน (รองรับ 12 เดือนทีเดียว) parse ทุก sheet, จับคู่ชื่อบริษัทกับ Supplier เดิมแบบ fuzzy (ตัด "Co.,Ltd."/"Company Limited" ออกก่อนเทียบ + เทียบ exact → contains) **ไม่เจอ = สร้าง Supplier ใหม่อัตโนมัติ** ตามที่ตกลง — โชว์หน้า **Preview ก่อนเขียนจริงเสมอ** (แก้การจับคู่เองได้ทีละแถวถ้าจับผิด) มี badge เตือนถ้าคะแนนที่คำนวณจาก occurrence ไม่ตรงกับที่ Excel รายงานไว้เกิน 2 แต้ม (เผื่อ criteria เปลี่ยนเวอร์ชันไปแล้ว — "เซฟตี้เน็ต" ตามที่คุยกันไว้ ไม่ได้ auto-หาเวอร์ชันเก่าให้ ให้ Admin ตัดสินใจเอง)
    - **Import ซ้ำเดือนเดิม = upsert ทับ** ตามที่ตกลง (`on conflict (supplier_id,year,month)`)
    - **evaluation ที่เคย submit/approve ไปแล้ว:** ถ้าคะแนนที่ import ใหม่**ตรงกับของเดิม** (ห่างกัน <0.5) คงสถานะเดิมไว้ทั้งหมด — ถ้า**ไม่ตรง** (ข้อมูลเปลี่ยนจริง) ระบบจะดีดกลับเป็น `draft` ให้อัตโนมัติ (เคลียร์ submitted_at ทั้งคู่) แทนที่จะเขียนทับตัวเลขของ record ที่อนุมัติไปแล้วเงียบๆ
    - **Export:** เลือก evaluation จากหน้า Evaluation List (checkbox ทีละแถว — **เฉพาะที่เป็น `scoring_mode='itemized'` เท่านั้น** ถึงจะ export ได้ เพราะ evaluation แบบ `manual` เก่าไม่มีข้อมูล breakdown รายหัวข้อให้ใส่กลับเข้าไฟล์) → "Export Selected (N)" → ได้ไฟล์ .xlsx ที่มีแค่ sheet ของ Supplier ที่เลือกจริงๆ
    - **เทคนิค Export:** เก็บไฟล์จริง 1 ไฟล์ไว้เป็น asset (`assets/fm0704_export_template.xlsx`) ใช้ sheet "FM0704-3 Rev.2(P.1)" ซึ่งเป็น**ชีตต้นแบบเปล่าจริงในไฟล์เดิม**ที่ผู้ใช้ทำไว้อยู่แล้ว (ตรวจแล้วว่า blank จริง ไม่ใช่ sheet supplier ที่มีข้อมูล) → deep-clone ทั้ง object ของ sheet ต่อ 1 Supplier → แก้แค่ค่าที่จำเป็น (ชื่อบริษัท, เดือน, occurrence) → **สไตล์/เส้นขอบ/merge cell/สูตรติดมาฟรีเพราะไม่ได้แตะ** — ทดสอบแล้วว่าตำแหน่งคอลัมน์/แถวตรงกับไฟล์จริง 100% (เทียบกับ ETO เดือน ก.ค. ที่เคยตรวจมือไว้ก่อนหน้า)
    - **⚠️ ข้อจำกัดสำคัญที่ต้องรู้ไว้:** ปุ่ม Export ต้อง `fetch()` ไฟล์ template asset ซึ่ง **เบราว์เซอร์บล็อกการ fetch ไฟล์ local เวลาเปิดแอปแบบ `file://` ตรงๆ (double-click index.html)** — Export จะใช้งานได้เฉพาะตอนเสิร์ฟผ่าน HTTP เท่านั้น (แม้จะเป็นแค่ local server ง่ายๆ ก็พอ เช่น `python -m http.server`) ส่วน **Import ไม่กระทบ** (ใช้ File API อ่านไฟล์ที่อัปโหลดโดยตรง ไม่ต้อง fetch)
    - **สิ่งที่ยังไม่ได้ทำ/ทดสอบเต็มที่:** ยังไม่ได้ลอง export ไฟล์จริงแล้วเปิดด้วย Excel จริงเทียบผลลัพธ์ทีละพิกเซล (ตามที่บอกไว้ก่อนหน้าว่าจะลองก่อนมั่นใจ 100%) — สูตร %/เกรดในไฟล์ที่ export จะยังเป็นค่าเดิมจนกว่า Excel จะ recalculate ตอนเปิดไฟล์ (ปกติเป็น default behavior ของ Excel เอง ไม่ต้องทำอะไรเพิ่ม)

44. **Admin สร้างบัญชีจากในแอปได้เอง แทน self-signup (v2.2.0):** self-signup ปิดถาวรแล้วตามที่ตกลง (REC-P0-05) — เปลี่ยนมาให้ **Admin สร้างบัญชีให้จากในแอปได้เลย** (Master Control → Users & Roles → ฟอร์ม Create Account) แทนที่จะต้องไปสร้างเองใน Supabase Dashboard
    - **ทำไมต้องมี Edge Function:** สร้าง Supabase Auth user ใหม่จากฝั่ง client โดยตรงทำได้แค่ผ่าน `signUp()` สาธารณะ (ซึ่งกำลังจะถูกปิด) — การสร้าง user แบบ admin จริงๆ (ไม่ผ่าน signUp) ต้องใช้ **service role key** ซึ่ง**ห้ามส่งมาที่ browser เด็ดขาด** (bypass RLS ทั้งหมด) จึงต้องมี server-side function (`supabase/functions/admin-create-user/index.ts`) เป็นตัวกลาง — function เช็คว่าคนเรียกเป็น Admin จริงก่อน (ผ่าน JWT ของคนเรียกเอง ไม่ใช่ trust จาก client) แล้วค่อยใช้ service role สร้าง user ให้
    - **ต้อง deploy เอง — ทำจากในนี้ไม่ได้:** รัน `supabase functions deploy admin-create-user` ผ่าน Supabase CLI (ดูขั้นตอนละเอียดท้ายไฟล์ .ts) ไม่มี secret ต้องตั้งเอง (`SUPABASE_URL`/`SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY` platform ใส่ให้อัตโนมัติ)
    - **แก้ `handle_new_user()` trigger (`26_admin_create_user.sql`):** เดิม trigger บังคับ downgrade ทุก department ที่ไม่ใช่ qa/cs/mp เป็น 'qa' อัตโนมัติ (กันไม่ให้ self-signup ปลอมตัวเป็น role สูง) — พอปิด self-signup แล้วช่องทางเดียวที่จะสร้าง user ได้คือผ่าน Edge Function (ที่เช็ค Admin แล้ว) เลยแก้ trigger ให้เชื่อ department ที่ส่งมาได้เต็มที่ (validate แค่ว่าเป็นค่า enum จริง) ไม่งั้น Admin สร้างบัญชี Supervisor/Manager/Admin จากแอปไม่ได้เลย (จะโดน downgrade เป็น QA ทุกครั้ง)
    - **ยังต้องไปปิด "Allow new users to sign up" ที่ Supabase Dashboard → Authentication → Providers → Email เองด้วย** (SQL/Edge Function ทำให้ไม่ได้จากในนี้) — ไม่งั้น public signUp() endpoint ยังเปิดอยู่ (แค่ปุ่มในแอปหายไป ไม่ได้บล็อกจริงตามที่เตือนไว้ใน REC-P0-05)

43. **Implement ตาม `recommend.md` (external code review, P0 เท่านั้น) — v2.1.0:**
    - **REC-P0-01 (ยืนยันเป็นบั๊กจริง):** `loadEvaluations()` ไม่เคยดึง `category`/`is_active`/`target_score` มาพร้อม supplier relation เลย ทำให้ Action Board filter ตาม supplier group พังเงียบๆ — แก้แล้ว
    - **REC-P0-02:** เลิกเก็บ password ใน localStorage (เดิมเก็บแบบ base64 ซึ่งไม่ใช่การเข้ารหัส) เหลือจำแค่ User ID, ลบ key เก่าที่มี password ทิ้งอัตโนมัติเมื่อเจอ
    - **REC-P0-03 (ทำบางส่วน ไม่ครบ):** เพิ่ม `escapeHtml()` แล้วใช้กับจุดเสี่ยงสูงสุด (comment ในตาราง evaluation list/profile, CA problem/responsible_person, supplier code/name/short_name/category ในตาราง Master Control) — **ยังไม่ได้ไล่ตรวจทุกจุด `innerHTML` ในไฟล์ทั้งหมด** (ไฟล์ใหญ่มาก มีจุดเสี่ยงกระจายอยู่หลายสิบจุด) ต้องถือว่าเป็นการลดความเสี่ยงบางส่วน ไม่ใช่ตรวจครบ 100% ตามที่ recommend.md แนะนำ
    - **REC-P0-04:** เพิ่มตาราง `app_schema_version` + ฟังก์ชัน `checkSchemaVersion()` เช็คตอน login ก่อนโหลดข้อมูลใดๆ ถ้า schema ล้าหลังกว่าที่แอปต้องการ (`REQUIRED_SCHEMA_VERSION` ใน app.js) จะบล็อกพร้อมข้อความบอก Admin ชัดเจน แทนที่จะโหลดแล้วพังทีละจุดแบบงงๆ
    - **REC-P0-05 (ยืนยันปิดถาวรแล้ว):** ปิด self-signup ถาวรตามที่ยืนยัน — แทนที่ด้วย Admin สร้างบัญชีจากในแอปเอง (ดูข้อ 44)
    - **REC-P0-06 (ยืนยันเป็นบั๊กจริง):** `statusLabel()` ไม่มี mapping ของ `sup_approved`/`mgr_approved` เลยตั้งแต่ทำ v33 (ตกหล่นตอนย้าย) ทำให้ทุกหน้าที่โชว์สถานะนี้เห็น raw database value (`sup_approved` ตรงๆ) แทนข้อความสวยๆ — แก้แล้ว
    - **REC-P0-07 (ยังไม่ทำ):** Automated test suite — โปรเจกต์นี้เป็น static HTML/JS ไม่มี build tooling ใดๆ การทำ automated test จริงต้องตั้ง infrastructure แยก (เช่น Playwright/Jest) เป็น scope การตัดสินใจแยกต่างหาก ยังไม่ได้เริ่ม
    - **P1/P2/P3 ทั้งหมดใน recommend.md ยังไม่ได้ทำ** (concurrency protection, role-based dashboard, app.js modularization, pagination, notification, SSO ฯลฯ) — เก็บไว้เป็น backlog อ้างอิงเอกสารต้นฉบับ `recommend.md` ที่ user แนบมา

---

## 4.5 What Phase B just delivered (v0.5.0) — for quick reference

- `database/08_corrective_action_workflow.sql`: RLS policies (finally usable table), `due_date` column, `add_working_days()` helper, `auto_create_corrective_action` trigger, one-time backfill for existing approved C/D evaluations (excluding pure historical-import rows — see the SQL file's own notes).
- New "Corrective Actions" tab in the app: add/edit form (pick an evaluation, fill Problem/Root Cause/Action/Responsible/Start/Due/Finished/Status) + filterable list (status, overdue-only) with overdue rows highlighted red.
- Dashboard: new "CA Overdue" KPI tile.
- **Not done yet (left for later, not blocking):** no email/notification when a CA is created or overdue; no "reject/resubmit" workflow (see Step 11 of the AI-analyzed proposal in the earlier chat) — this is just Problem→Action→Status tracking, not the full review cycle. No supplier-facing portal for suppliers to fill in their own CA (still an internal-only tool).

---

## 5. Immediate next step (Phase 8 — Pilot)

**Task:** เริ่ม Pilot ใช้งานคู่ขนานกับ Excel จริง — Phase 1-7 เสร็จหมดแล้ว (ดูตารางหัวข้อ 2)

Checklist:
- [ ] เลือก supplier กลุ่มเล็ก (5-10 บริษัท) ให้ QA/CS/MP ลองใช้แอปจริงคู่ขนานกับ Excel เดือนถัดไป
- [ ] เทียบผลคะแนน/เกรดระหว่างแอปกับ Excel ทุกบริษัทที่ pilot — ควรตรงกันเป๊ะยกเว้นเคส No Shipment (ซึ่งแอปถูกกว่า Excel เดิม ดูข้อ 1)
- [ ] เก็บ feedback การใช้งานจริงจาก QA/CS/MP/cs_supervisor โดยเฉพาะเรื่อง "Official Worksheet" ใหม่ (ติ๊ก checklist แทนกรอกตัวเลข) — ใช้งานง่ายกว่าเดิมจริงไหม
- [ ] ตัดสินใจว่าจะ migrate evaluation เก่าที่เป็น `manual` ไป `itemized` ทีละบริษัท หรือปล่อยให้อยู่แบบ manual ตลอดไป (ทั้งสองแบบใช้งานได้ ไม่บังคับต้องแปลง)
- [ ] เมื่อมั่นใจแล้ว ค่อย cutover เต็มรูปแบบ เลิกใช้ Excel

---

## 5.5 (เดิม) Phase 3 checklist — เก็บไว้อ้างอิง, ทำเสร็จแล้ว

Checklist:
- [x] สร้าง UI ในหน้า Monthly Input ให้เลือกหัวข้อจาก `evaluation_criteria` ทีละหมวด (Quality/Delivery/Purchase) พร้อมกรอกจำนวนครั้งที่เกิด — ตอนนี้คือหน้า "Official Worksheet" (v0.9.0)
- [x] เขียนไปที่ตาราง `evaluation_items` (evaluation_id, criteria_id, occurrence, points_applied)
- [x] เขียนฟังก์ชัน/trigger คำนวณ `quality_score`/`delivery_score`/`purchase_score` จาก `evaluation_items` อัตโนมัติ (full_score บวก/ลบตาม `deduction_points × occurrence` แต่ห้ามติดลบเกิน 0)
- [x] ~~ต้อง revisit สูตร generated column `total_score`/`grade`~~ — แก้แล้วใน v0.4.0 (Phase A): เปลี่ยนเป็น trigger-based, normalize ตาม `shipment_status` ถูกต้องแล้ว (ดูข้อ 1 ในหัวข้อ Key decisions) — Phase 3 แค่ต้องคงหลักการนี้ไว้ ไม่ต้องออกแบบสูตรใหม่
- [x] ปรับ RLS/trigger ของ Phase 2 ให้ครอบคลุมตาราง `evaluation_items` ด้วย (ตอนนี้มีแค่ `evaluations`)

---

## 6. Open questions (ต้องตัดสินใจก่อนไปต่อไกลกว่านี้)

- [ ] เลือก framework frontend อะไร (คง HTML/JS เดิม vs. ย้ายไป React/Next.js)?
- [ ] แหล่งข้อมูล email ของ Supplier จะเอามาจากไหน?
- [ ] **Export ฟอร์มผลประเมิน 2 ชีต + Auto-mapping (v2.0.0, ยังไม่ scope):** CS/MP export ไฟล์ผลประเมินตอน Mark Sent — แนวคิดคือทำ 2 sheet ในไฟล์เดียว (1) ฟอร์มผลประเมิน (2) ฟอร์มให้ Supplier กรอกตอบการแก้ไข (root cause/corrective action/due date) แล้วเมื่อ Supplier ส่งไฟล์กลับมา แนบเข้าแอปได้ตามปกติ **บวกไอเดียเพิ่ม:** แอปดึงหัวข้อ Root Cause/Action/Due Date จากไฟล์ที่แนบมาขึ้นแสดงในแอปแบบ auto ผ่านการ mapping cell ที่ตกลงไว้ล่วงหน้า (ไม่ต้องพิมพ์ซ้ำ) — ยังไม่ได้คุย format ของฟอร์มให้ชัดเจน เป็นงานถัดไปที่ต้อง scope แยก (คาดว่าต้องใช้ SheetJS parse ไฟล์ที่อัปโหลดกลับมา ไม่ใช่แค่เก็บเป็นไฟล์แนบเฉยๆ เหมือนตอนนี้)
- [x] จะใช้ Supabase Storage เก็บไฟล์แนบ/PDF ไหม — ใช้แล้ว ตั้งแต่ v0.7.0 (bucket ชื่อ `attachments`, ดู `11_approval_flow_and_attachments.sql`)
- [x] ปิด self-service signup แล้ว เปลี่ยนเป็น admin-only user creation ผ่าน Supabase Dashboard (v04)

### Dashboard v0.8.0
Dashboard has been upgraded to a Supplier Command Center with action queues, cycle health, supplier risk index, early warning, CA control tower, issue Pareto, and data-confidence monitoring. The dashboard derives the selected period from existing evaluations. A dedicated evaluation_cycles table remains a future phase.

### Localization v0.8.1
All static and dynamic Supplier Command Center strings are connected to the existing EN/TH toggle.

### Evaluation Worksheet v0.9.0
Monthly Input now evaluates actual FM0704-3 criteria by occurrence and calculates scores automatically. Manual score entry is no longer the primary workflow.

---

## 7. Supplier 360 — วิสัยทัศน์ระยะยาว (Concept เท่านั้น — ยังไม่เริ่มทำ)

**สถานะ:** เก็บไว้เป็นทิศทางในอนาคต — **priority ตอนนี้คือ go-live ของ Supplier Evaluation ที่มีอยู่แล้ว** (ดูหัวข้อ 8) ไม่ใช่ขยาย scope ต่อ ห้าม assume ว่าเริ่มทำได้จนกว่าจะมีคนสั่งชัดเจน

### บริบท / ที่มา
วิเคราะห์จากไฟล์อ้างอิงจริงของบริษัท (Approved Supplier List, Quality Problem/CAR log ปี 2023, Audit checklist FM-0704-5, PO data, Meeting Minutes เป้า FY2024) พบว่าระบบปัจจุบันครอบคลุมแค่ 1 ใน 3 เสาหลักของการจัดการ Supplier แบบครบวงจรที่บริษัทใช้งานจริง:

| เสาหลัก | สถานะ |
|---|---|
| **Evaluation** (คะแนนรายเดือน Q/D/P) | ✅ มีระบบเต็มรูปแบบ |
| **Master Data / ASL** (ทะเบียน Supplier, cert, ผู้ติดต่อ, สถานะ ASL/Potential) | 🟡 มีแค่ช่องพื้นฐาน |
| **Audit** (ตรวจเชิงลึกแบบลงพื้นที่ 20 หมวด ~85 ข้อ, FM-0704-5) | ❌ ไม่มีเลย |

### จุดสำคัญ: Corrective Action มี 3 ประเภทที่ทริกเกอร์ต่างกัน ต้องแยกกัน ไม่ใช่ก้อนเดียว
1. **CA จาก Evaluation** (คะแนนรวมเดือน = C/D) — มีอยู่แล้ว
2. **CAR รายเหตุการณ์ของเสีย** (พบของเสีย 1 ครั้ง ผูก Part No./Lot-Heat No./NG Rate) — ตอนนี้ระบบเก็บแค่ "จำนวนครั้ง" ผ่าน checklist รายเดือน ไม่มีรายละเอียด
3. **CA จาก Audit** (FM-0704-10 — ข้อ Audit ได้คะแนน <3/4) — ยังไม่มีเลยเพราะยังไม่มีระบบ Audit

### แนวคิดหน้า Supplier Profile ในอนาคต ("Supplier 360")
รวม 3 เสาหลักเข้าหน้าเดียวแบบ Tab: ภาพรวม / ผลประเมิน / Audit / Corrective Action (แยก 2 ประเภทย่อยข้างในตามข้อบน) / เอกสาร-ผู้ติดต่อ

### Roadmap แบบเฟส (อย่าทำพร้อมกันทีเดียว — บทเรียนจากรอบ 14-ข้อก่อนหน้านี้)
- **เฟส 1**: ขยาย supplier master data (type, manufacturer จริงกรณี Trading, multi-contact, ISO/CQI cert + วันหมดอายุ, ASL/Potential status) + จัดหน้า Profile เป็น Tab — **สร้างเฉพาะ Tab ที่มีข้อมูลจริงรองรับเท่านั้น** (ภาพรวม/ผลประเมิน/เอกสาร-ผู้ติดต่อ) ห้ามสร้าง Tab Audit/CA-เต็มรูปแบบเป็น placeholder ว่างๆ
- **เฟส 2**: ยกระดับ CA ให้ตรงฟอร์ม CAR จริง — เลขเอกสารรันต่อปี, traceability (Part/Lot/Heat/NG Rate), ผู้ติดต่อ 2 ฝั่ง (Attend/P.I.C.), checklist เอกสารทวนสอบ, ปิด 2 ชั้น (CA Closed → Monitoring 1 เดือน Closed), ตรวจจับ re-occurrence อัตโนมัติ
- **เฟส 3**: ระบบ Audit ใหม่ทั้งระบบ (20 หมวด ~85 ข้อ ให้คะแนน 1-4, ออกแบบให้กรอกสะดวกบนแท็บเล็ตหน้างาน) — งานใหญ่สุดในทั้งหมด
- **เฟส 4**: เชื่อม ASL Governance อัตโนมัติ — เตือนตามกฎจริงที่บริษัทใช้ (เกรด D ติดต่อกัน 3 เดือน → ตัดออกจาก ASL, ไม่มีคำสั่งซื้อ 2 ปี → ย้าย Potential)
- **เฟส 5** (ไกลสุด, อาจไม่จำเป็นเร็วๆ นี้): เชื่อมข้อมูล PO จริงจาก ERP เพื่อให้ "ปริมาณสั่งซื้อ" เป็นตัวเลขจริงระดับ part แทน tier ปัจจุบัน

---

## 8. Go-Live Readiness (priority ตอนนี้)

เป้าหมาย: เอา Supplier Evaluation ที่มีอยู่แล้วขึ้นใช้งานจริงให้ได้ก่อน เพื่อใช้เป็นเหตุผลขอ server จาก IT — ดูรายละเอียด checklist ในข้อความถัดไปของบทสนทนา (ยังไม่ finalize ในไฟล์นี้จนกว่าจะสรุปครบ)

### เมนู "ตั้งค่า/สถานะ" ซ้อนลึก 2 ชั้น — รอ feedback จริงก่อนจัดใหม่
สังเกตเห็นว่า Master Control ซ้อนอีก 5 แท็บย่อยอยู่ใน Setting ที่มี 5 แท็บอยู่แล้ว (ซ้อน 2 ชั้น) — สำหรับ Admin ถือว่าเยอะจริง แต่สำหรับ role อื่น (QA/CS/MP/Supervisor) เห็นแค่ 2 แท็บเท่านั้น (แท็บที่เหลือ gate ไว้เฉพาะ Admin) — **ตัดสินใจไม่จัดใหม่ตอนนี้** เพราะยังไม่มี feedback จริงจาก Admin คนอื่นที่ใช้งานจริง (มีแค่ผู้พัฒนาคนเดียวที่เห็น) และช่วงนี้ priority คือ go-live ไม่ใช่ขัดเกลา UI ต่อ — รอ pilot จริงแล้วค่อยจัดใหม่ให้ตรงจุดตาม feedback จริง
