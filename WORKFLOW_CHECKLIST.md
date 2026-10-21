# EHT Supplier Evaluation — Detailed Workflow Verification Checklist

Default permission_rules values are shown — Admin can change these per-department anytime in
Master Control → Permissions, so treat "who can do X" below as the *default*, not hardcoded truth.
Always cross-check against Master Control → Permissions for what's actually configured live.

---

## STAGE 1 — Someone opens a new evaluation

**Who:** anyone logged in (any department)
**Where:** Evaluation List → "+ Open New Evaluation" button
**Does:** picks Supplier + Year + Month, or opens an existing row via 👁️/✏️
**Result:** a row exists in `evaluations` with `status = 'draft'`, `quality_submitted_at = null`,
`delivery_submitted_at = null`
**List shows:** badge "รอ QA และ MP/CS" (amber)
**Who does the next step:** QA (Quality section) and CS/MP (Delivery/Purchase section) — independently,
in either order

---

## STAGE 2a — QA fills the Quality section

**Who:** department = `qa` (permission `eval_edit_quality = true` by default)
**Where:** Worksheet page (open the evaluation via List)
**Does:** ticks the A1 (Quality, 9 items) + A2 (Environment, 3 items) checklist rows that actually
happened that month, clicks **"Submit Quality Section"**
**Result:** `quality_score` recalculated automatically (DB trigger), `quality_submitted_at = now()`
**List shows:** if MP/CS hasn't submitted yet → "รอ MP/CS" (amber). If MP/CS already had →
skips straight to "รอ Supervisor" (see Stage 3)
**Can QA edit Delivery/Purchase fields here?** No — disabled, `eval_edit_delivery = false` for `qa`
**Who does the next step:** whichever of QA/MP-CS hasn't submitted yet, or Supervisor once both have

---

## STAGE 2b — CS or MP fills the Delivery/Purchase section

**Who:** department = `cs` or `mp` (permission `eval_edit_delivery = true` by default)
**Where:** same Worksheet page, same evaluation
**Does:** ticks the B (Delivery, 7 items) + C (Purchase tier, pick one of 3) checklist, or marks
"No Shipment" this month with a reason, clicks **"Submit Delivery/Purchase Section"**
**Result:** `delivery_score`/`purchase_score` recalculated, `delivery_submitted_at = now()`
**Can CS/MP edit Quality fields here?** No — disabled, `eval_edit_quality = false` for `cs`/`mp`
**Who does the next step:** same as 2a — whichever side is still missing, or Supervisor once both are in

---

## STAGE 3 — Supervisor reviews (both sections now submitted)

**Who:** department = `cs_supervisor` or `mp_supervisor` (permission `eval_sup_approve = true` by
default; `qa`/`cs`/`mp`/`opd_manager` are `false` by default)
**Where:** Worksheet page — sidebar shows "Quality: ส่งแล้ว ✓ | Delivery/Purchase: ส่งแล้ว ✓" and the
completeness bar at 100% once BOTH are in
**Status at this point:** still `draft` in the database — there is no separate `submitted` status in
this system; "both submitted" is tracked purely by the two timestamp columns being non-null
**List shows:** "รอ Supervisor" (accent/teal)
**Does either of:**
- **Supervisor Approve** → `status = 'sup_approved'`, `sup_approved_at = now()` — enabled only when
  `eval_sup_approve = true` for the logged-in user's department AND both timestamps are set AND
  status isn't already past this point
- **Reject** → `status` stays `'draft'`, both submitted timestamps get cleared back to null,
  `rejection_reason` required — sends it back to Stage 2a/2b for QA and CS/MP to redo
**List shows after Approve:** "รอ Manager" (accent/teal)
**Who does the next step:** Manager

---

## STAGE 4 — Manager reviews (after Supervisor approval)

**Who:** department = `opd_manager` (permission `eval_mgr_approve = true` by default; everyone else
`false` by default except Admin)
**Where:** same Worksheet page — button only enables once `status = 'sup_approved'`
**Does either of:**
- **Manager Approve** → `status = 'mgr_approved'`, `mgr_approved_at = now()`
- **Reject** → `status` bounces all the way back to `'draft'`, both submitted timestamps cleared —
  back to Stage 2a/2b, same as a Supervisor rejection (deliberately harsher than just undoing the
  Supervisor step, since Manager rejecting means the underlying data itself needs redoing, not just
  a second Supervisor look)
**List shows after Approve:** "รอส่ง Sup" (accent/teal)
**If grade turns out to be C or D:** nothing auto-happens yet at this exact step — the Corrective
Action only gets created at the NEXT step (Mark Sent), not here
**Who does the next step:** CS or MP (send the report to the supplier, outside the app)

---

## STAGE 5 — CS/MP sends the result to the Supplier and marks it

**Who:** whoever normally handles supplier communication — same `cs`/`mp`/`cs_supervisor`/
`mp_supervisor` departments already doing Stage 2b
**Where:** Worksheet page — export/print the result, email it to the supplier **outside this app**,
then come back and click **"Mark Sent to Supplier"**
**Does:** clicks the button once the physical/email sending is done
**Result — depends on grade:**
- **Grade A or B:** `status = 'acknowledged'` directly, `sent_at = now()` — **case is fully closed,
  nothing else to do.** List shows "ปิดเคส" (green)
- **Grade C or D:** `status = 'sent_to_supplier'`, `sent_at = now()`, **and a Corrective Action row is
  auto-created** (`auto_create_corrective_action` trigger fires on the `mgr_approved` transition,
  due date = 5 working days later, skipping weekends + public holidays). List shows "รอ CA" (red) and
  a 📋 icon appears on that row
**Who does the next step:** for A/B, nobody — done. For C/D, whoever's handling the Corrective Action

---

## STAGE 6 — (Grade C/D only) Corrective Action gets worked and closed

**Who to fill the CA form:** `ca_create = true` by default for `cs`/`mp`/`cs_supervisor`/
`mp_supervisor`/admin; `qa` is `false` by default (QA can view/comment but not own the CA)
**Where:** click the 📋 icon on that row in the Evaluation List
**Does:** fills Problem / Root Cause / Corrective Action / Responsible Person / Start Date / Due Date,
attaches the supplier's countermeasure document (SCAR/CAR/Claim form etc.) via the file upload,
clicks **Save Corrective Action**
**Then, once the supplier's countermeasure is actually received:**
**Does:** clicks **"Mark Received Countermeasure"**
**Result:** CA `status = 'closed'`, `finished_date = today`
**List shows:** "ปิดเคส" (green) — since `sent_to_supplier` + CA closed now counts as fully closed
**Who can close a CA:** `ca_close` permission — QA also has this by default (QA can close a CA even
though QA can't create one), alongside cs/mp/cs_supervisor/mp_supervisor/admin

---

## Quick status-to-action lookup table (for verification)

| List shows | DB `status` | Timestamps present | Who acts next | What they click |
|---|---|---|---|---|
| รอ QA และ MP/CS | draft | neither submitted | QA and MP/CS | Submit Quality / Submit Delivery |
| รอ MP/CS | draft | quality only | MP/CS | Submit Delivery/Purchase |
| รอ QA | draft | delivery only | QA | Submit Quality Section |
| รอ Supervisor | draft | both submitted | Supervisor | Supervisor Approve / Reject |
| รอ Manager | sup_approved | both submitted | Manager | Manager Approve / Reject |
| รอส่ง Sup | mgr_approved | both submitted | CS/MP | Mark Sent to Supplier |
| รอ CA | sent_to_supplier | both submitted | CS/MP/Supervisor | Fill + close the CA |
| ปิดเคส | acknowledged, or sent_to_supplier+CA closed | both submitted | — nobody, done | — |

---

## Things worth double-checking manually against this table

1. **Log in as each role once** (qa / cs or mp / cs_supervisor or mp_supervisor / opd_manager / admin)
   and confirm the button states on a test evaluation match exactly what this table says at each
   stage — this is the fastest way to catch a permission mismatch like the one in the screenshot.
2. **Reject at both stages** — confirm it really clears both timestamps and bounces to `draft`,
   and that a reason is required both times.
3. **One A/B-grade and one C/D-grade evaluation all the way through** — confirm A/B skips straight to
   ปิดเคส with no CA created, and C/D creates exactly one CA with the correct due date.
4. **Permission changes in Master Control → Permissions actually take effect** — flip one rule,
   confirm the corresponding button enables/disables for that department without needing a code change.
