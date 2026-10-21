# Approve Flow — EHT Supplier Evaluation

สรุป flow การอนุมัติผลประเมิน Supplier ทั้งหมด ตั้งแต่เปิดรายการจนถึงปิดเคส — รวมมติที่ตกลงกันไว้ และ TODO ที่ยังไม่ได้ลงมือทำ

**สถานะเอกสาร:** อัปเดตล่าสุดถึง Package v87 — ยังไม่ครบทุก step (ค้างที่ step 5-6)

---

## ภาพรวม Diagram สถานะ

```
draft ──(Q & D submit ครบ)──> [Supervisor Approve/Reject]
  │                                    │
  │  Reject (เฉพาะ Sup)                │ Approve
  └──────────< sup_approved <──────────┘
                    │
              [Manager Approve/Reject]
                    │ Approve
              mgr_approved  ── ล็อกทั้งใบ แก้ไม่ได้อีกแล้ว ──
                    │
              [Mark Sent to Supplier]
                    │
         ┌──────────┴──────────┐
    Grade A/B                Grade C/D
   auto-close              รอปิด Corrective Action
    (ทันที)                       │
         │                  ปิด CA ตัวสุดท้าย
         └──────────┬───────────┘
                acknowledged (ปิดเคส)
```

---

## ผู้เล่นในระบบ (Permission Matrix — ค่า default)

| Permission | QA | CS | MP | CS Sup | MP Sup | Manager | Admin |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| แก้ Quality (A1/A2) `eval_edit_quality` | ✅ | ✗ | ✗ | ✗ | ✗ | ✗ | ✅ |
| แก้ Delivery/Purchase (B1/B2) `eval_edit_delivery` | ✗ | ✅ | ✅ | ✅ | ✅ | ✗ | ✅ |
| Supervisor Approve `eval_sup_approve` | ✗ | ✗ | ✗ | ✅ | ✅ | ✗ | ✅ |
| Manager Approve `eval_mgr_approve` | ✗ | ✗ | ✗ | ✗ | ✗ | ✅ | ✅ |
| Reject | ✗ | ✗ | ✗ | ✅ | ✅ | ✅ | ✅ |
| Mark Sent to Supplier `eval_mark_sent` | ✗ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ลบผลประเมิน `eval_delete` | ✗ | ✗ | ✗ | ✅ | ✅ | ✅* | ✅ |
| สร้าง CA `ca_create` | ✗ | ✅ | ✅ | ✅ | ✅ | ✗ | ✅ |
| แก้ CA เต็มรูปแบบ `ca_edit_full` | ✗ | ✗ | ✗ | ✅ | ✅ | ✗ | ✅ |
| แก้เฉพาะ Root Cause/Action `ca_edit_restricted` | ✅ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| ปิด CA `ca_close` | ✅ | ✗ | ✗ | ✅ | ✅ | ✗ | ✅ |

\* Manager: ต้องเข้าไปเปิดที่ Setting → Master Control → Permissions เอง (dynamic config ไม่ใช่ default เดิม)

---

## Step 1 — เปิดรายการ

- **ใครทำ:** CS/MP staff หรือ Supervisor
- **ผล:** สร้างรายการสถานะ `draft` รอผลทั้ง Quality (Q) และ Delivery/Purchase (D)

## Step 2 — ฝ่ายใดฝ่ายหนึ่ง (Q หรือ D) กรอกผล + Submit

- **ใครทำ:** QA (ฝั่ง Q) / CS-MP-Supervisor (ฝั่ง D) — ใครก่อนก็ submit ก่อนได้ไม่ต้องรอกัน
- **ผล:** ยังเป็น `draft` แต่รอเฉพาะอีกฝ่าย

**มติที่ตกลงแล้ว:**
| เรื่อง | มติ | สถานะ |
|---|---|---|
| แก้ไขของตัวเองซ้ำ หลัง submit (ก่อน Sup approve) | แก้ไข/submit ซ้ำได้เอง ไม่ต้องรอ Reject + ต้องมี log | ✅ ใช้ audit log ที่มีอยู่แล้ว (`admin_action_log`) ไม่ต้องเขียนใหม่ |
| ลบทั้งรายการ ตอนมีข้อมูล submitted แล้ว | ลบได้ แต่ต้องกรอกเหตุผลยืนยันก่อน (สิทธิ์เดียว `eval_delete` ไม่แยกตาม timing) | 🔲 ยังไม่ทำ |
| Preview ก่อน Submit | โชว์หน้าต่างสรุปก่อนยืนยัน Submit ทั้งสองฝั่ง (QA เห็น A1/A2, CS/MP เห็น B1/B2) — บังคับต้องเลือก purchase tier ก่อนยืนยันได้ (ถ้าไม่ใช่ no-shipment) | 🔲 ยังไม่ทำ |
| Badge แยก "เคยโดน Reject" ในหน้า List | ยังไม่ตัดสินใจ — ตอนนี้เห็นแค่ตอนเปิดใบเข้าไปดู (ข้อความ "ครั้งล่าสุดถูก Reject: ...") | ❓ รอตัดสินใจ |

## Step 3 — Supervisor Approve / Reject

- **เงื่อนไขกดได้:** ต้อง submit ครบทั้ง Q และ D ก่อน (เช็คทั้ง UI + DB)
- **ใครทำ:** `eval_sup_approve` (CS Sup / MP Sup / Admin)
- **ผล Approve:** สถานะ → `sup_approved`, กลับหน้ารายการอัตโนมัติ

**มติที่ตกลงแล้ว:**
| เรื่อง | มติ | สถานะ |
|---|---|---|
| ใครกด Reject ได้ตอนขั้นนี้ | เฉพาะ Supervisor เท่านั้น (Manager แทรกไม่ได้แล้ว จากเดิมที่ทำได้ทั้งคู่) | 🔲 ยังไม่ทำ — โค้ดปัจจุบัน `canReject = canSupApprove \|\| canMgrApprove` ยังให้ Manager reject ขั้นนี้ได้อยู่ |
| Reject ล้างข้อมูลฝั่งไหน | ต้องระบุได้ว่า Q/D/ทั้งสองผิด — ล้าง `submitted_at` เฉพาะฝ่ายที่ถูกระบุเท่านั้น | 🔲 ยังไม่ทำ — ตอนนี้ล้างทั้งสองฝ่ายเสมอ ไม่ว่าจะระบุเหตุผลเจาะจงแค่ไหน |
| เช็คความครบถ้วนข้อมูลก่อน Approve | ไม่เช็คตรงนี้ — ย้ายไปเป็น Preview ตอน Submit แทน (ดู Step 2) | ✅ ตัดสินใจแล้ว (ย้ายจุดเช็ค) |
| สิทธิ์ลบ (`eval_delete`) | เพิ่ม Manager เข้าไปด้วย (เดิมมีแค่ Supervisor+Admin) | ✅ ทำได้เลยผ่าน Master Control → Permissions ไม่ต้องแก้โค้ด |

**Bug ที่แก้ไปแล้ว (v87):** การแก้ไขคะแนนตอนนี้ล็อกทันทีที่ Supervisor Approve แล้ว — **ยกเว้น** Delivery/Purchase ที่ยังแก้ได้สำหรับคนมี `eval_sup_approve` (ลดขั้นตอนไม่ต้อง Reject เพื่อแก้เล็กน้อยของทีมตัวเอง) Quality ล็อกทันทีทุกคนไม่มีข้อยกเว้น

## Step 4 — Manager Approve / Reject

- **เงื่อนไขกดได้:** ต้องผ่าน `sup_approved` มาก่อน — **เช็คแล้วว่า DB บังคับลำดับนี้จริง** (ไม่ใช่แค่ UI ตามที่เคยเข้าใจผิดไปช่วงแรก)
- **ใครทำ:** `eval_mgr_approve` (เฉพาะ Manager/Admin)
- **ผล Approve:** สถานะ → `mgr_approved`
  - เกรด C/D → auto-create Corrective Action (ต้องเช็คว่า migration `20_two_tier_approval.sql` รันแล้วจริงบน Supabase — เป็นตัวที่แก้ trigger ให้เช็ค `mgr_approved` แทน `approved` เก่า)
  - **ใบถูกล็อกทั้งหมด ทุก role แก้ไม่ได้อีกเลย** (v85)

**เดียวกับ Step 3:** Manager ก็ควรกด Reject ได้เฉพาะตอนถึงคิวตัวเอง (`sup_approved` เท่านั้น) เรื่องนี้ผูกกับ TODO เดียวกับ Step 3 (แยก reject ตาม stage + ระบุฝ่ายที่ผิด)

## Step 5 — Mark Sent to Supplier *(ยังคุยไม่จบ)*

- **เงื่อนไขกดได้:** ต้องมาจาก `mgr_approved` เท่านั้น (เช็คทั้ง UI+DB)
- **ใครทำ:** `eval_mark_sent` (ทุกคนยกเว้น QA)
- **ผล:**
  - เกรด A/B → auto-close ทันที (`sent_to_supplier` → `acknowledged` ในคลิกเดียว)
  - เกรด C/D → ค้างที่ `sent_to_supplier` รอปิด CA

**ค้างคุย/ยังไม่ตัดสินใจ:**
- ปุ่มนี้จะอัปเกรดเป็น "ส่งเมลจริง" — เลือกไปแล้วว่าจะทำแบบ **ส่งจริงจาก server** (Supabase Edge Function + บริการอีเมล เช่น Resend/SendGrid) ไม่ใช่แค่ mailto — งานนี้ใหญ่ ต้อง (1) สมัครบริการอีเมล + verify โดเมน (2) เขียน Edge Function ใหม่ (3) หน้าเว็บส่ง PDF/ข้อมูลไปให้ Edge Function แนบส่ง — **ยังไม่เริ่มทำ**
- ใครปิด CA ได้ควรมี Manager ด้วยไหม (ตอนนี้ `ca_close` = QA + Sup ทั้งคู่ + Admin ไม่มี Manager/CS/MP ธรรมดา) — ยังไม่ได้ตอบ

## Step 6 — Corrective Action (เฉพาะเกรด C/D) *(คุยแค่บางส่วน)*

- Auto-create ตอน Manager Approve (ถ้า migration 20 รันแล้ว)
- **สร้างได้หลายปัญหาในครั้งเดียว** (multi-set, v81) — ผูกกับ Evaluation เดียวกันทั้งหมด ไฟล์แนบต่อปัญหาแยกกัน
- ปิด CA ตัวสุดท้ายของ evaluation → auto-sync evaluation เป็น `acknowledged`
- **Bug ที่แก้แล้ว (v86):** เกรด C/D ที่ยังไม่มี CA เคยโดนขึ้น badge "ปิดเคส" ผิดๆ (เพราะเช็ค "ไม่มี CA เปิดอยู่" ปนกับ "ไม่มี CA เลย") — ตอนนี้แยกเป็นสถานะ "เกรด C/D แต่ยังไม่มี Corrective Action" (แดง) + ปุ่มลัดสร้าง CA ให้ตรงจุดในหน้า List
- **Bug ที่แก้แล้ว (v87):** หน้าเลือก Evaluation ตอนสร้าง CA กรองเฉพาะเกรด C/D เป็น default แล้ว (มี checkbox โชว์ทุกเกรดได้)

---

## 🔲 TODO List สะสม (ยังไม่ได้ลงมือทำ — รอ flow คุยจบก่อน)

1. ~~Reject เฉพาะ stage ของตัวเอง~~ ✅ ทำแล้ว (v90)
2. ~~Reject ระบุฝ่ายที่ผิดได้~~ ✅ ทำแล้ว (v90)
3. ~~Preview ก่อน Submit~~ ✅ ทำแล้ว (v90)
4. ~~ลบรายการที่มีข้อมูล submitted แล้ว ต้องกรอกเหตุผลยืนยัน~~ ✅ ทำแล้ว (v90)
5. ~~DB-level lock การแก้ไขคะแนน~~ ✅ ทำแล้ว (v90 — ต้องรัน `database/34_reject_scoping_and_status_lock.sql`)
6. ~~ใครปิด CA ได้~~ ✅ ตกลงแล้ว = ทุกคน (ตั้งค่าผ่าน Master Control → Permissions เอง ไม่ต้องแก้โค้ด)
7. ~~Badge แยก "เคยโดน Reject"~~ ✅ ทำแล้ว (v89, รองรับ partial reject ด้วยใน v90)
8. **ส่งอีเมลจริงจาก Server** (Supabase Edge Function + บริการอีเมล) แทนที่ Mark Sent เดิม — ยังอยู่ใน plan รอคุยกับ IT เรื่อง SMTP ก่อน (ดูหัวข้อ "แผนย้าย Backend" ด้านล่าง)

---

## 🗂️ แผนระยะยาว — อาจย้ายออกจาก Supabase ไปเป็น Server บริษัทเอง

เหตุผล: นโยบาย information security ของบริษัท — ยังไม่ยืนยันแน่ชัดว่าห้ามแบบไหน (ห้ามฝากข้อมูลคลาวด์นอกเฉยๆ vs ห้ามใช้ซอฟต์แวร์ Supabase เลย) ต้องคุยกับ IT/ทีม security ก่อน

**สรุปสิ่งที่ backend ของแอปนี้ทำอยู่ (= ไฟล์ SQL ทั้งหมดใน `database/`):**
- เก็บข้อมูลจริง (Postgres)
- บังคับกฎ/สิทธิ์ (RLS + trigger — `enforce_evaluation_edit_permissions()` เป็นตัวหลัก)
- ยืนยันตัวตน (Supabase Auth)
- เก็บไฟล์แนบ (Supabase Storage)

**2 เส้นทางถ้าต้องย้ายจริง:**
| เส้นทาง | ความยาก | สิ่งที่ต้องทำ |
|---|---|---|
| Self-host Supabase เอง (ซอฟต์แวร์เดิม ย้ายแค่ที่ตั้ง) | เบา | รันไฟล์ SQL ทั้ง 34 ไฟล์กับ Postgres ของบริษัท, เปลี่ยน `SUPABASE_URL` ใน app.js — โค้ดแทบไม่ต้องแก้ |
| เขียน backend เองใหม่ทั้งหมด (ไม่ใช้ซอฟต์แวร์ Supabase เลย) | หนัก — โปรเจกต์แยก | ไฟล์ SQL ทั้งหมดที่มีอยู่แล้วเป็น **spec ที่สมบูรณ์** (กฎ/เหตุผลมีคอมเมนต์ครบ) ใช้เป็นแนวทางแปลงเป็นเทคโนโลยีใหม่ได้ แต่ต้องเขียนเซิร์ฟเวอร์ใหม่จริง (API, auth, business logic ทั้งหมด) |

**สถานะ:** ยังไม่ตัดสินใจ รอถาม IT ก่อนว่านโยบายห้ามแบบไหน

---

## ✅ สิ่งที่ทำและแพ็กส่งไปแล้ว (สรุปย่อ — ดูรายละเอียดเต็มใน CHANGELOG.md)

| Version | สรุป |
|---|---|
| v75 | แก้บั๊ก CS ถูกบล็อกโดย Quality permission ตอน submit, รวม B+C zone |
| v76 | Action bar แสดงปุ่มตาม role/สถานะจริง, ยุบ section ที่แก้ไม่ได้ |
| v77 | Submit ไม่โชว์ success ปลอมถ้า save ล้มเหลวจริง |
| v78 | Submit สำเร็จ → กลับหน้ารายการอัตโนมัติ |
| v79-80 | จัดหัวเพจใหม่ (title ย้ายไป Action Bar), แก้ปุ่มภาษา EN มองไม่เห็น |
| v81 | สร้าง Corrective Action ได้หลายปัญหาในครั้งเดียว (multi-set) |
| v82 | Login จำหลาย User ID พร้อม smart search dropdown |
| v83 | แก้บั๊กเปิดหลายแท็บแล้วค้างโหลด (Supabase Web Locks) |
| v84 | Badge นาฬิกาทรายบอกสถานะ "กำลังทำงาน" ทุกปุ่ม, Sup Approve กลับหน้ารายการ |
| v85 | ล็อกทั้งใบหลัง Manager Approve ไม่ว่า role ไหน |
| v86 | แก้บั๊กเกรด C/D ไม่มี CA แต่ขึ้น "ปิดเคส" ผิด + ปุ่มสร้าง CA ด่วน |
| v87 | กรอง CA picker เฉพาะเกรด C/D, ล็อกการแก้ไขเริ่มตั้งแต่ Sup Approve (มีข้อยกเว้น Delivery ให้ Sup) |
| v88 | เพิ่มไฟล์ approve_flow.md (เอกสารนี้เอง) เข้าไปในแพ็ก |
| v89 | Badge/to-do แยก "เคยโดน Reject" ในหน้า List และ Dashboard แต่ละแผนก |
| v90 | Reject แยก stage+แยกฝ่าย, Preview ก่อน Submit, ลบต้องกรอกเหตุผลถ้ามีข้อมูล, ล็อกการแก้ไขคะแนนที่ database (ต้องรัน SQL 34) |
