-- ============================================================
-- 14_criteria_thai_translation.sql
-- Thai translations for the 22 official evaluation criteria.
--
-- Checked the source Excel (07__JULY_26.xlsx) for existing Thai text
-- first, including the actual FM0704-3 template sheet and the
-- "ตัวอย่างสูตร" (formula example) sheet — the whole workbook turned
-- out to be English-only, no Thai text anywhere. These are fresh
-- translations, not sourced from the file.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

alter table evaluation_criteria add column description_th text;

comment on column evaluation_criteria.description_th is 'Thai translation of description, shown when the app is set to TH. Falls back to the English description if null.';

update evaluation_criteria set description_th = case item_no
  when 'A1-1' then 'การเคลมจากลูกค้าปลายทาง, การเรียกคืนสินค้า, การเคลมประกัน, การคืนสินค้าจากตัวแทนจำหน่าย'
  when 'A1-2' then 'สายการผลิตของลูกค้า E&H หยุดเนื่องจากปัญหาคุณภาพ (SCAR ระดับ A)'
  when 'A1-3' then 'สายการผลิตของ E&H หยุดเนื่องจากปัญหาคุณภาพ (SCAR ระดับ B)'
  when 'A1-4' then 'ลูกค้าของ E&H ร้องเรียน (SCAR ระดับ B)'
  when 'A1-5' then 'ตรวจพบข้อบกพร่องในกระบวนการผลิต (SCAR ระดับ C)'
  when 'A1-6' then 'ปัญหาคุณภาพเกิดซ้ำภายใน 1 ปี (12 เดือน)'
  when 'A1-7' then 'ส่งรายงานมาตรการแก้ไขล่าช้ากว่ากำหนด'
  when 'A1-8' then 'ดำเนินการแก้ไขตามผลตรวจประเมิน (Audit) ล่าช้ากว่ากำหนด'
  when 'A1-9' then 'ไม่ให้ความร่วมมือในกิจกรรมด้านคุณภาพ (เช่น การคัดแยก, การแก้ไขงาน)'
  when 'A2-1' then 'ปริมาณสารเคมีเกินมาตรฐานที่กำหนด (E.Partner Management)'
  when 'A2-2' then 'การจัดการน้ำเสียและสิ่งปฏิกูลไม่เป็นไปตามที่กฎหมายกำหนด'
  when 'A2-3' then 'รายงานผลทดสอบสารอันตราย (ICP Report) ไม่ใช่ฉบับล่าสุด'
  when 'B-1'  then 'Supplier จัดส่งสินค้าไม่ตรงเวลา'
  when 'B-2'  then 'สายการผลิตของลูกค้า E&H หยุดเนื่องจากปัญหาการจัดส่ง'
  when 'B-3'  then 'จัดส่งสินค้าไม่ครบตามจำนวนที่ระบุใน P/O'
  when 'B-4'  then 'มีค่าขนส่งเพิ่มเติมนอกเหนือที่กำหนด'
  when 'B-5'  then 'สินค้าเสียหายจากการขนส่งที่ Supplier จัดเตรียม'
  when 'B-6'  then 'บรรจุภัณฑ์ผิดปกติ (ชำรุด, แตกหัก)'
  when 'B-7'  then 'ส่งเอกสารหรือให้ข้อมูลตอบกลับล่าช้ากว่ากำหนด'
  when 'C-1'  then 'ยอดซื้อ 1,000,000 ชิ้น หรือ 10,000 กก. ขึ้นไป'
  when 'C-2'  then 'ยอดซื้อ 100,000-999,999 ชิ้น หรือ 5,000-9,999 กก.'
  when 'C-3'  then 'ยอดซื้อต่ำกว่า 100,000 ชิ้น หรือ 5,000 กก.'
  else description_th
end
where item_no in ('A1-1','A1-2','A1-3','A1-4','A1-5','A1-6','A1-7','A1-8','A1-9',
                   'A2-1','A2-2','A2-3','B-1','B-2','B-3','B-4','B-5','B-6','B-7',
                   'C-1','C-2','C-3');

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * Any NEW criteria added later via Master Control -> Evaluation
--   Criteria won't have a Thai translation until someone fills in
--   description_th for that row (SQL update, same pattern as above —
--   there's no Thai input field in the Master Control form yet).
-- ============================================================
