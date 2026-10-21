# EHT Supplier Evaluation — v19 / App v0.9.0

Package สำหรับส่งต่องานให้ session/ทีมอื่นทำต่อ

## เริ่มจากตรงนี้
1. อ่าน **`PLAN.md`** ก่อน — มี roadmap, สถานะปัจจุบัน, และ "immediate next step" ที่ต้องทำต่อ
2. ดู **`CHANGELOG.md`** ถ้าต้องการรู้ว่าแต่ละเวอร์ชันเปลี่ยนอะไรไปบ้าง

## วิธีติดตั้ง (ตามลำดับ)
1. รัน `database/01_schema.sql` ใน Supabase SQL Editor
2. รัน `database/02_seed_data.sql`
3. รัน `database/03_phase2_auth_and_roles.sql`
4. เปิด Supabase Dashboard → Authentication → Providers → Email → ปิด "Confirm email" ถ้าต้องการทดสอบเร็วๆ
5. แก้ `app/app.js` บรรทัดบนสุด ใส่ `SUPABASE_URL` และ `SUPABASE_ANON_KEY` ของโปรเจกต์ตัวเอง
6. เปิด `app/index.html` ในเบราว์เซอร์ → สมัครสมาชิกแรก (เลือกแผนกได้ตอนสมัคร) → เข้าใช้งาน

## โครงสร้างไฟล์
```
EHT_Supplier_Evaluation_v03/
├── PLAN.md                 ← roadmap + สถานะ + next step (อ่านก่อน)
├── CHANGELOG.md             ← ประวัติเวอร์ชัน
├── README.md                ← ไฟล์นี้
├── database/
│   ├── 01_schema.sql         ← ตารางหลักทั้งหมด (รันก่อน)
│   ├── 02_seed_data.sql      ← ข้อมูล Supplier + ประวัติจาก Excel (รันสอง)
│   └── 03_phase2_auth_and_roles.sql  ← Login + สิทธิ์ตามแผนก (รันสาม)
└── app/
    ├── index.html
    ├── style.css
    └── app.js               ← ต้องแก้ SUPABASE_URL / ANON_KEY ก่อนใช้งาน
```
