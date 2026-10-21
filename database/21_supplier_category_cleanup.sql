-- ============================================================
-- 21_supplier_category_cleanup.sql
-- Fixes supplier categorization for the Dashboard/Action Board filter:
--   - MA-xxx / PA-xxx suppliers had NO category at all (seeded without
--     one back in 02_seed_data.sql) — set to 'Material' / 'Part'
--     respectively, matching what those code prefixes have meant in
--     every conversation about this data so far.
--   - The 22 Outsource suppliers (18_import_heat_plating_suppliers.sql)
--     were all lumped under one generic 'Outsource' category — split
--     into 'Heat Treatment' / 'Plating' where the company name itself
--     contains an unambiguous keyword (Thermo, Induction, Heat
--     Treatment, Plating, Mekki [Japanese for plating], Coating,
--     Parkerizing, Electro Chemical, Surface Technology/Treatment).
--     14 of the 22 matched a keyword; the other 8 (Tanabe, Union
--     Autoparts, T.I.D., Taiyo Seisakusho, B.K.J., Trix, Silvec,
--     Miyaki) have no identifiable keyword in their name and are left
--     as generic 'Outsource' — correct these via Master Control ->
--     Suppliers if you know their actual process type, this migration
--     is a best-effort keyword match, not a verified classification.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

update suppliers set category = 'Material' where code like 'MA-%';
update suppliers set category = 'Part'     where code like 'PA-%';

update suppliers set category = 'Heat Treatment' where code in ('OS-002','OS-012','OS-018');
update suppliers set category = 'Plating'        where code in ('OS-004','OS-005','OS-007','OS-009','OS-010','OS-011','OS-013','OS-014','OS-017','OS-019','OS-020');
-- OS-001, OS-003, OS-006, OS-008, OS-015, OS-016, OS-021, OS-022 stay 'Outsource' (no keyword match)

-- Sanity check
select category, count(*) from suppliers group by category order by category;
