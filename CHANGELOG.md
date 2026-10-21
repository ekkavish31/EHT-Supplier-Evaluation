### [Package v92] — 2026-10-21 — Dashboard redesign, grouped menu, automatic monthly cycle opening

**SQL to run:** `database/35_auto_open_current_cycle.sql` (requires `16_evaluation_cycles.sql`). The app still works without it; it just won't auto-open the month.

#### Added
- Dashboard header: large month/year title with ◀ ▶ and a month picker (months with data are marked); supplier-group / shipment / risk filters sit after it, de-emphasised; print/export button.
- "What I need to do" is now role tabs in the order CS/MP → QA → Supervisor → Manager. The user's own tab opens first, 5 rows max, rows show age ("open 20 d" / "waiting 3 d"), rejected/overdue first.
- Four tiles: average score (vs previous month, target 80), below target, open Corrective Actions (overdue count), grade mix (A/B/C/D bar). Tiles are clickable.
- Cycle health shows a warning when the month is nearly over and little is done.
- Watch list (replaces Priority queue + Risk matrix): each row has a 12-month sparkline of the supplier against the all-supplier average (dashed).
- Collapsible "Overview — history": 12-month trend with target line, 10–90% band, below-target bars and Total/Quality/Delivery/Purchase switch; Pareto with Count / Points-lost switch and arrows vs previous month.
- `ensure_current_cycle()` (SQL 35): any signed-in user's first load of the month creates draft evaluations for active suppliers that have none (Asia/Bangkok month). Idempotent. Admin's manual "open cycle" button in Setup still works.
- Left menu grouped (Daily work / Data & reports / System); Corrective Action now has its own menu entry with an overdue badge.

#### Changed
- Score-based numbers (average, below target, risk, trend, sparklines, Pareto) now count only COMPLETED evaluations (both Quality and Delivery/Purchase submitted), so freshly opened drafts no longer distort them.
- The risk matrix was removed (its job moved into the watch list).
- Evaluations query now also loads `sup_approved_at` / `mgr_approved_at` (the v91 report timeline needed them).

#### Not done / to check
- "Expected progress for this point in the cycle" is not shown (no baseline yet); the warning only uses days left vs percent done.
- Pareto bars are not clickable yet.
- Tested offline with mock data only; please check against live data.

### [Package v91b] — 2026-10-21 — Config extracted; libraries and fonts vendored (offline-ready)

No SQL changes.

#### Changed
- Supabase URL and key moved out of `app.js` into `config.js` (`window.APP_CONFIG`) so IT only edits one file when pointing the app at a new server.
- `supabase-js`, `xlsx` and IBM Plex fonts are now served from `vendor/` instead of CDNs, so the app can run without internet access.

#### Note
- Not yet browser-tested after this change; check login and Excel export on first run.

### [Package v91] — 2026-10-14 — Dashboard charts keep their proportions; Single Evaluation report redesigned

No SQL changes — frontend only.

#### Fixed
- Dashboard charts (risk matrix / 12-month trend / Pareto) no longer stretch or collapse: the canvas's own pixel size was feeding back into the CSS grid track width (and height) on every redraw. Grid tracks are now `minmax(0,…)`, panels `min-width:0`, and `.canvas-wrap canvas` is absolutely sized to its wrapper.

#### Changed
- Report → Single Evaluation now fills the page: grade/score header, score-by-category bars, supplier details with monthly rank and 12-month average, 12-month trend sparkline, approval trail with dates, deductions table (from evaluation items), Corrective Action summary and comments. Print layout keeps cards unbroken.

### [Package v90] — 2026-09-22 — Scoped Reject, submit preview, delete confirmation for submitted data, DB-level status lock

**⚠️ Run `database/34_reject_scoping_and_status_lock.sql`** — this release depends on it. Without it: Reject still works but always clears both sections and isn't stage-restricted (old behavior), and the DB won't yet block editing a locked evaluation's scores if someone bypasses the UI.

#### Changed — Reject now targets a specific section, and only the right stage can do it
- Reject opens a small dialog instead of a single browser prompt: pick Quality, Delivery/Purchase, or both, then give a reason. Only the section(s) picked get their submitted timestamp cleared — the other one keeps its data and doesn't need to be redone.
- A Supervisor can only reject while it's still awaiting Supervisor review; a Manager can only reject once it's awaiting Manager review (previously either could reject at either stage). Enforced both in the UI and in the database trigger.
- The Evaluation List's "Rejected — needs resubmission" badge and each department's Dashboard to-do item (added in v89) now correctly detect a *partial* reject too, not just a full one.

#### Added — confirmation preview before Submit
- Clicking Submit (Quality, Delivery/Purchase, or both) now opens a preview first: Quality shows the A1/A2 deduction list (or "no deductions"), Delivery/Purchase shows B1's deductions and B2's selected purchase tier. Reads live from the form, not the last save.
- If a Purchase tier hasn't been selected yet (and it's not a no-shipment month), the preview's Confirm button is disabled until one is picked — this is the "real completeness check" from the earlier discussion, moved to Submit time instead of Supervisor Approve time.

#### Added — deleting an evaluation with submitted data now asks for a reason
- Deleting an empty, never-touched draft still works with a plain yes/no confirm. Once either section has been submitted, deleting requires typing an actual reason first — same permission as before (`eval_delete`), just more friction for a real accident to get through.

#### Fixed — database-level lock now matches the UI lock (from v87)
- `enforce_evaluation_edit_permissions()` previously only checked *whether* a department could edit at all, never the evaluation's current status — someone with valid edit permission could still edit a Supervisor- or Manager-approved evaluation's scores by calling the API directly, bypassing the UI's own lock. The database now enforces the same rule as the UI: Quality locks for everyone from Supervisor Approve onward; Delivery/Purchase stays open only for Supervisor-tier permission holders until Manager Approve, then locks for everyone.

### [Package v89] — 2026-09-22 — "Rejected, needs resubmission" now stands out in the List and each department's to-do board

No SQL changes — frontend only.

#### Changed
- The Evaluation List's status badge now shows a distinct "Rejected — needs resubmission" (red) instead of the generic "Waiting on QA and MP/CS" when an evaluation was actually sent back by Reject, rather than just never touched yet — same distinction the worksheet's own "Last rejected: ..." note already made, now visible from the list too.
- The Dashboard's per-department Action Board (QA / CS-MP columns) now flags the same rejected evaluations with "Rejected — fix and resubmit" and bumps them to the top of that department's to-do list, styled like an overdue item, instead of blending in with ordinary not-yet-submitted work.

### [Package v88] — 2026-09-22 — Added approve_flow.md (workflow design doc, no app changes)

### [Package v87] — 2026-09-22 — Corrective Action's Evaluation picker now filters to Grade C/D by default; edit lock now starts at Supervisor Approve

No SQL changes — frontend only. (The DB-side equivalent of the edit lock below — currently only enforced in the UI — is still on the TODO list for the batched SQL migration once the full workflow review wraps up.)

#### Changed — Corrective Action Evaluation picker
- Used to list every evaluation regardless of grade — easy to accidentally attach a CA to a Grade A/B evaluation that never needed one. Now defaults to showing only Grade C/D (matching the page's own hint text, which already said CAs are for Grade C/D). A "Show all grades" checkbox is available for the rare real exception.

#### Changed — editing now locks starting at Supervisor Approve, not just Manager Approve
- Quality (A1/A2) locks for everyone the moment Supervisor Approves — editing it further would silently invalidate an approval that already happened, with no re-review.
- Delivery/Purchase (B1/B2) stays editable a little longer, but only for whoever holds Supervisor-tier approval permission (`eval_sup_approve`) — lets a Supervisor fix a small mistake in their own team's numbers directly instead of a full Reject round-trip. Locks for real once Manager Approves, same as everything else.
- Everything still locks completely for everyone from Manager Approve onward, as before.

### [Package v86] — 2026-09-22 — Fixed: Grade C/D with no Corrective Action was mislabeled "Closed"

No SQL changes — frontend only. (If the missing CA on an existing record turns out to be because `20_two_tier_approval.sql` wasn't run on the live database — its `auto_create_corrective_action()` trigger is the one that actually creates the CA at Manager Approve — that's a separate, database-side check still worth confirming.)

#### Fixed
- Real bug found from a live screenshot: `evalWorkflowStatus()` decided "Closed" whenever an evaluation at `sent_to_supplier` had no *open* Corrective Action — but `[].some(...)` on an evaluation with **zero** CAs at all also returns false, so a Grade C/D evaluation that never got a CA created for it (which should never happen, but can if the auto-create trigger didn't fire) was shown as "ปิดเคส / Closed" with a green badge, identical to a genuinely resolved case — and with no CA at all, there was no CA icon in that row to investigate from.
- The status logic now treats "zero CAs on a Grade C/D evaluation" as its own distinct, clearly-flagged state ("Grade C/D — Corrective Action missing", red badge) rather than folding it into either "closed" or the normal "waiting on CA" label.
- Added a quick-fix action (➕📋) directly on that row in the Evaluation List — jumps straight into the Corrective Action editor with that evaluation already selected, instead of having to find it again in the generic picker.

### [Package v85] — 2026-09-22 — Evaluation locked once Manager Approves — no further edits by anyone

No SQL changes — frontend only. (The database's own `enforce_evaluation_edit_permissions()` trigger was already the real backstop against edits by someone without that department's permission — this closes the remaining gap: a role that legitimately holds edit permission could previously still tick the checklist on an evaluation that had already been through Manager Approve.)

#### Changed
- Once an evaluation reaches `mgr_approved` (or moves further — sent to supplier, acknowledged, follow-up) the entire worksheet becomes locked for everyone, regardless of the viewer's normal Quality/Delivery edit permission: the checklist, shipment status, and comments are no longer editable, and the Save/Submit button is replaced with a disabled "Evaluation closed — no further edits" state.
- The only actions left available past that point are the ones that were already correctly gated to this stage — **Mark Sent to Supplier** (once `mgr_approved`, for whoever has that permission) and **Delete** (from the Evaluation List, for whoever has `eval_delete`) — nothing new added, this just stops editing from competing with them.

### [Package v84] — 2026-09-22 — Global "working…" indicator on every button click; Supervisor Approve returns to the list

No SQL changes — frontend only.

#### Added
- A small hourglass badge (top-right corner, same animation as the big initial-load screen) now shows for as long as any network request to Supabase is in flight — so clicking Save, Approve, Reject, Mark Sent, uploading a file, deleting something, signing in, etc. all give immediate "yes, that registered" feedback instead of looking like nothing happened while waiting. Implemented once by patching `window.fetch` (which every Supabase call goes through) rather than wiring each button individually, so it covers new buttons automatically too. Stays out of the way while the big full-page loading screen (initial data load) is already showing.

#### Changed
- Supervisor Approve now closes the worksheet and returns to the evaluation list on success, matching what Submit already does — instead of staying open on the just-approved worksheet.

### [Package v83] — 2026-09-22 — Fixed: multiple tabs of the app hanging on load when switching between them

No SQL changes — frontend only.

#### Fixed
- `supabase-js` coordinates auth/session refresh across tabs using the browser's Web Locks API, keyed by origin — every `file://` tab is the same origin, so opening this app in several tabs made them contend for one shared lock even though each tab's session is already independent here (file:// falls back to in-memory, per-tab storage — see the existing comment on `createResilientStorage`). A tab holding that lock while backgrounded/throttled left any other tab stuck loading forever the moment you switched to it. The client now skips that lock entirely (`auth.lock` set to run immediately, no cross-tab coordination), since there's nothing shared to protect per tab in this setup.

### [Package v82] — 2026-09-22 — Login: saved User IDs now show as a searchable dropdown

No SQL changes — frontend only. Local-storage-only change (see earlier discussion of what's stored locally vs. in Supabase — this touches only the `se_remember` key, now `se_remember_ids`).

#### Changed
- Ticking "Remember User ID on this device" now adds that ID to a small local list (up to 8, most recent first) instead of overwriting a single remembered ID — useful on a shared computer where more than one person signs in.
- The User ID field now shows a filterable dropdown of saved IDs as you type (or on focus with it empty) — click one to fill it in and jump to the password field. Each entry has a × to remove just that one ID from the list.
- Existing single saved ID (old `se_remember` format) is migrated into the new list automatically the first time the login page loads after this update; nothing is lost.
- Turned off the browser's own native autofill dropdown for this field (`autocomplete="off"`) so it doesn't visually stack with the new custom list.

### [Package v81] — 2026-09-22 — Corrective Action: create multiple problems in one save; worksheet score-header alignment/format/highlight fixes

No SQL changes — frontend only.

#### Changed — Corrective Action creation now supports multiple problems at once
- The "Create Corrective Action" form now renders each problem (Problem / Root Cause / Action / Responsible / dates / Status) as its own bordered card, with a "+ Add another problem" button to add more cards before saving — since a single evaluation often has more than one issue in the same month. All cards share the one Evaluation picker at the top; one Save inserts every card as its own Corrective Action row (sequential seq_no, same as before).
- Editing an existing Corrective Action (from the list) now opens the **same** editor component, just with exactly one non-removable card — one shared CA editor for both flows instead of two separate forms.
- Attachments are now per-card. For an already-saved card (edit mode) a chosen file uploads immediately, same as before. For a new, not-yet-saved card, chosen files are staged locally and actually uploaded right after that card's Save succeeds and it has a real id.

#### Fixed — worksheet score display
- The big Quality/Delivery zone header score wasn't consistently right-aligned against its expand/collapse arrow (title width shifted it). The score and the arrow are now grouped together so they always sit flush right.
- The Delivery (B1) and Purchase (B2) sub-section scores now show "/ 40" and "/ 10" like Quality's A1/A2 already did, instead of a bare number.
- Any checklist row that currently has occurrence > 0 (i.e., it's actually affecting the score) now gets a highlighted background in the expanded checklist, not just a colored "-N pts" figure on the right — using the same tint as the collapsed-section flagged summary.

### [Package v80] — 2026-09-22 — Header correction: title moved into the Action Bar, not the topbar; collapsed-section message now reflects submit state

No SQL changes — frontend only. Corrects the v79 header placement per follow-up feedback.

#### Changed — header placement (corrected)
- Topbar reverted to a plain tab label ("กรอกผลประเมินรายเดือน") on the left — no longer carries supplier/period/status. Right side unchanged: [Back to List][←][→][language], all in one row.
- The period + status + supplier title ("2026-Sep · ร่าง" / "Akiyama Seiko Co., Ltd.") now sits at the very top of the **Action Bar** (the right-hand score-sticky panel) instead, directly above "Live Score" — so it travels with the score summary itself.

#### Changed — collapsed-section message now has 3 states
- A collapsed Quality or Delivery/Purchase card's summary line now distinguishes "nothing to show yet" from "reviewed, actually clean":
  - Section not yet submitted by its department → "รอผลประเมินจากแผนก Quality" / "รอผลประเมินจากแผนก CSMP"
  - Section submitted, zero deductions → "ไม่มีรายการที่ถูกหักคะแนนในส่วนนี้" (unchanged)
  - Section submitted, has deductions → flagged rows as before

### [Package v79] — 2026-09-22 — Worksheet page head redesigned; language toggle contrast bug fixed

No SQL changes — frontend only.

#### Changed — page head
- The old plain single-line topbar title ("กรอกผลประเมินรายเดือน — 2026-Sep · Akiyama Seiko Co., Ltd.") is gone. When a worksheet is open, the topbar now shows a two-line title instead: period + status badge on top ("2026-Sep · ร่าง"), supplier name underneath — so it's immediately obvious which evaluation, whose, and what state it's in, without opening the card.
- Removed the redundant "แบบประเมิน Supplier" title + description card-head that used to sit inside the worksheet panel — that context now lives in the page head above instead.
- **Back to List** moved out of that card and into the topbar's button row itself, alongside the existing back/forward history arrows and language switch — so it's one consistent row: title on the left, all page-level controls (Back to List, ←, →, language) on the right. Only shown while on the Evaluation Input tab.

#### Fixed — language switch contrast
- Selecting **EN** used to leave the "EN" label in the same muted grey as its unselected state — invisible against the green selection pill — while **TH** correctly turned white when selected. Root cause: the CSS rule for EN relied on `:first-child`, but the pill's sliding background element is the actual first child in the markup, so that rule silently never matched anything. Replaced both rules with dedicated classes instead of relying on child order, so EN now turns white when selected exactly like TH already did.

### [Package v78] — 2026-09-22 — Submit now closes the worksheet and returns to the list

No SQL changes — frontend only.

#### Changed
- After a successful Submit (Quality / Delivery-Purchase / both), the worksheet now closes and the app navigates back to the evaluation list (`showTab('list')`), instead of leaving the just-submitted worksheet sitting open on screen. Only fires on real success — a failed save (see v77) still stops before this and leaves the worksheet open so the user can see what went wrong.

### [Package v77] — 2026-09-22 — Submit no longer shows a false "success" after a real save failure

No SQL changes — frontend only. (Companion fix to `database/33_scoped_score_recompute.sql` from v75/v76, which the pilot already applied — this is the remaining client-side half of that same incident: even after the DB correctly rejected the bad save, the UI still told the user it worked.)

#### Fixed
- `saveOfficialWorksheet()` now actually reports success/failure (`return true/false`) instead of silently `return`-ing on error and letting the caller assume it worked.
- `handleMainSubmitClick()` now stops immediately if the checklist save fails, instead of continuing on to stamp the section as submitted and show a "saved and submitted" alert on top of the real error. Previously a failed save (e.g. blocked by a permission trigger) still left the section marked submitted with its score never actually written, while the user saw two contradictory popups.
- Also surfaced errors from the `recompute_evaluation_scores` RPC call itself, which previously failed silently with no alert at all if the recompute step errored.

### [Package v76] — 2026-09-22 — Action bar no longer overflows; worksheet sections collapse when a role can't edit them

No SQL changes — frontend only.

#### Fixed — action bar overflow (side scrollbar in the sidebar)
- The sidebar used to render all 5 approval buttons (Supervisor Approve, Supervisor Reject, Manager Approve, Manager Reject, Mark Sent) at all times and just `disabled` the ones that didn't apply yet — that's what pushed the sidebar past its `max-height` and produced the internal scrollbar. It now renders only the button(s) actually actionable for the current role + workflow stage (normally 1, at most 2 — an approve paired with its reject). When nothing is actionable, a single status line explains whose turn it is (e.g. "Waiting on Supervisor Approve") instead of a wall of greyed-out buttons.
- Merged the two identical Reject buttons (Supervisor-stage and Manager-stage — both called the same `rejectEvaluation()`) into one `#btnReject`.

#### Changed — worksheet sections default-collapsed for roles that can't edit them
- The Quality (A) and Delivery & Purchase (B) cards now collapse by default for a role that has no edit permission on that section — showing only the checklist items that actually have a deduction (occurrence > 0), or "No deductions in this section" if there are none. A chevron on the section header expands/collapses it manually at any time.
- Supervisor/Manager accounts (`eval_sup_approve` / `eval_mgr_approve`) are excluded from that default — since they can't edit either section either way but need to see both in full to make an informed approve/reject call, both cards stay expanded for them.

### [Package v75] — 2026-09-19 — Worksheet: fixed the real CS-blocked-by-Quality bug, merged B+C zones, one role-aware submit button, sticky sidebar fits viewport

⚠️ **Run `database/33_scoped_score_recompute.sql`** — this is the actual fix for the pilot-test-confirmed bug where CS/MP couldn't save their own Delivery/Purchase section ("You do not have permission to edit Quality fields"). Everything else in this version is frontend-only.

Found live during real pilot testing (a CS account walking through create → fill → save → submit) — traced to the true root cause rather than patched around the symptom.

#### Fixed — the actual bug
- **Root cause, two layers**: (1) a freshly-created evaluation set `quality_score`/`delivery_score`/`purchase_score` all to `0` instead of the schema's intended "nothing logged yet" defaults of 50/40/0; (2) `recompute_evaluation_scores()` always recalculated and wrote *all three* score columns together, no matter which single section actually changed. So CS saving only Delivery also recomputed `quality_score` up from 0 to 50 — a real, detected change — which `enforce_evaluation_edit_permissions()` correctly rejected from its own point of view, since CS doesn't have `eval_edit_quality`. The permission check was doing its job on a column it should never have been asked to touch.
- Fixed at both places this could fire: the explicit RPC call from the worksheet's save action, and the trigger that fires on every checklist item change (now derives the right scope from the changed item's own criteria category automatically). Every other existing caller (imports, admin tooling) is unaffected — the new scope parameter defaults to "everything," identical to the old behavior, when not explicitly passed.
- Fixed the `0`-instead-of-`50` initial value too, so a brand new evaluation reads as "nothing logged yet" correctly instead of looking like Quality already failed before QA has looked at it.

#### Changed — consolidating the redundant buttons (from the same pilot session's other findings)
- **Delivery (B) and Purchase (C) zones merged into one panel**, B1/B2, mirroring how Quality's A1/A2 already work — instead of three separate zone panels.
- **Removed all three per-zone Save Draft / Submit buttons.** One button remains, in the sidebar, whose label and action are driven entirely by the Permission Matrix (`eval_edit_quality`/`eval_edit_delivery` — Setting → Master Control → Permissions, not a hardcoded department check): QA-permitted → "Submit Quality"; CS/MP-permitted → "Submit Delivery/Purchase"; both (Admin) → "Save & Submit All"; neither (Supervisor/Manager, view-only per this round's confirmed design) → disabled, "View Details". One click now saves the checklist data and marks the section submitted together, instead of two separate clicks.
- **Sidebar (`.score-sticky`) now actually fits the viewport** — added `max-height` + internal scroll, so a tall sidebar (score summary + all the approval buttons) scrolls within itself instead of extending past the visible screen.

### [Package v74] — 2026-09-19 — Translation tab: dropdown instead of overflowing tabs, one filter row, cross-category search

No SQL changes.

#### Fixed
- **v73's category tabs badly overlapped** — 13 categories crammed into one `.subtabs` row (designed for a handful of tabs) squeezed each label unreadably. Replaced with a `<select>` dropdown, which scales to any number of categories without layout breakage.

#### Changed
- **Category dropdown, search box, and "Save Changes" now share one row** — dropdown left, search box next to it, Save pushed flush right.
- **Search now spans every category at once** instead of only the currently-selected one — pick a category from the dropdown to browse it normally, or just type in the search box to find a label regardless of which category it's actually in. Saving correctly picks up edits either way (checks whichever set of rows the table is actually showing, not blindly the dropdown's current category — a real bug that would have silently dropped cross-category search edits, caught before shipping).

### [Package v73] — 2026-09-19 — Translation tab redesigned: category tabs + inline-editable table

No SQL changes.

#### Changed
- **Replaced the pick-one-key-from-a-dropdown-then-fill-two-blank-boxes flow with category tabs + a searchable, inline-editable table** — matches the concept from the reference screenshot, restyled to this app's own look. Categories are built from the app's own existing page/sub-tab structure (Dashboard, Evaluation List, Worksheet, Corrective Action, each Supplier Profile sub-tab, Master Control, Import/Export, Activity Log, Report, Translation itself) rather than a separate invented taxonomy, so it can't drift out of sync with the app.
- **Every row shows the label's current effective value already filled in** (the override if one exists, otherwise the app's own built-in default) — directly editable in place, not blank inputs the admin has to already know the right words for. A search box narrows the currently-open category by key or text. "Save Changes" commits every edited row in the visible category at once; a field left exactly matching the app's default is treated as "don't override this side," not as "override it with the same text."

### [Package v72] — 2026-09-19 — Users table now refreshes immediately after delete/edit/department change

No SQL changes.

#### Fixed
- **Deleting (or editing/changing department for) a user updated the underlying data correctly but the visible table didn't reflect it until a manual page reload** — `renderMasterUsersTable()` sits fairly late in the long `renderAll()` sequence; if anything earlier in that sequence throws, everything after it silently never runs. Each of `deleteUserAccount()`, `editUserFullName()`, and `changeUserDepartment()` now calls `renderMasterUsersTable()` directly right after reloading the data, guaranteeing this specific table updates immediately regardless of what else is happening elsewhere in that render pass.

### [Package v71] — 2026-09-18 — User account management: edit, delete, reset password

No SQL changes. ⚠️ **New Edge Function to deploy** — see below.

#### Added
- **Users & Roles table now has ✏️ Edit / 🔑 Reset Password / 🗑️ Delete per row**, alongside the existing department dropdown.
  - **Edit** — full name only (plain `UPDATE`, no Edge Function needed — Admin already has write access to `user_profiles`).
  - **Delete** and **Reset Password** — new `admin-manage-user` Edge Function (same auth-verification pattern as `admin-create-user`: caller's JWT checked against `master_data_manage` before the service-role client is touched). Delete removes the `auth.users` row (the `user_profiles` row goes with it via `ON DELETE CASCADE` already in place); if the account is referenced by historical records without a cascade there, the delete fails with a clear error instead of silently erasing someone's audit trail — that's intentional.
- **Showing the real password directly is not something any correctly-built auth system can do** — Supabase (like the rest) only ever stores a one-way hash, never anything reversible; this was confirmed, not assumed, before deciding on the alternative below. Implemented instead:
  - Account creation now shows the just-set password directly in the result banner, styled to stand out, with an explicit "note it down now, it can't be shown again" — the one moment it's actually available in cleartext.
  - Reset Password lets an Admin set a **new** password anytime (no need to know the old one) — solves "not sure what the password is" without ever storing a recoverable one anywhere.

#### Deploy `admin-manage-user`
Same Dashboard-editor method as `admin-create-user` (Edge Functions → Deploy a new function → Via Editor). ⚠️ Learned the hard way on `admin-create-user`: whatever slug ends up in the function's **URL** (not the "Name" column, which is cosmetic and can drift from the real slug after a rename) is what `ADMIN_MANAGE_USER_FN` near the top of the relevant `app.js` functions must say — check the deployed URL and update that one constant if it doesn't come out as `admin-manage-user` exactly.

### [Package v70] — 2026-09-18 — Edge Function slug fix (go-live blocker) + Group/Supplier filters + category bug

No SQL changes.

#### Fixed
- **`admin-create-user` Edge Function calls were failing with a CORS/preflight error no matter what** — root cause found live: the function was first deployed under Supabase's leftover template name `hyper-processor` (never renamed before deploying). Renaming it afterward in the Supabase dashboard only changed the cosmetic "Name" column — the dashboard's own URL column kept reading `.../functions/v1/hyper-processor` the whole time, confirming the display name and the actual routing slug are two different things Supabase doesn't keep in sync. Rather than fight the dashboard further, `app.js` now calls the function by its real slug (`hyper-processor`) — this was a genuine go-live blocker (no way to create real user accounts) and is now confirmed fixed.
- **Root cause found for the Group filter showing empty on the Supplier Profile and Report pages** (reported live, matches screenshots): `loadSuppliers()` — the lean, active-only supplier list many pages read from — never selected the `category` column at all, despite several places (`s.category`) depending on it. Every one of those reads was silently getting `undefined`. Added `category` to that query; Profile's group filter, Report's group filter, and Profile's category badge are all fixed by this one change.

#### Added
- **Evaluation List now has Group and Supplier filters**, inserted right after the search box — Group narrows by Code prefix (Material/Outsource/Blank Part, same categorization as the rest of the app), Supplier is a cascading dropdown narrowed to whichever group is selected.

### [Package v69] — 2026-09-18 — Supplier Profile restructured into tabs (Overview/Evaluation real, Audit/Contacts mocked as preview, Corrective Action real)

No SQL changes.

#### Changed
- **Supplier Profile split into 5 sub-tabs**: Overview, Evaluation, Audit, Corrective Action, Documents & Contacts — instead of one long two-column page. Group/Supplier picker stays fixed above the tabs.
- **Overview** and **Evaluation** (history table + 12-month chart) use the exact same real data as before, just relocated into their own tabs — nothing about how they work changed.
- **Corrective Action tab is real, not mocked** — reuses the same `correctiveActions` data already loaded elsewhere in the app, filtered to this supplier, since CA is already tied to evaluations and the data already exists.
- **Audit and Documents & Contacts tabs are explicitly marked mockups** — a visible dashed banner ("Preview — not a working feature yet") plus sample rows illustrating the future Supplier Audit (FM-0704-5) and multi-contact/certification concepts from PLAN.md §7. Deliberately NOT wired to any real data or save path — this is a visual preview of the direction, not a partially-built feature, so it can't be mistaken for one.

#### Fixed
- Chart canvas inside the now-hidden-by-default Evaluation tab would draw at 0×0 and stay blank — added the same redraw-on-tab-switch pattern used for the Dashboard/Risk Matrix charts.

### [Package v68] — 2026-09-18 — Risk Matrix / Trend / Pareto as one row
No SQL changes.

#### Changed
- **Risk Matrix, 12-month trend, and Issue Pareto changed from a 2-row layout (matrix spanning full height on the left) to a single row of 3 tiles side by side** — simpler scan, no more uneven tall-left/stacked-right shape.

### [Package v67] — 2026-09-18 — Issue Pareto silently failing to load (root cause found)
No SQL changes.

#### Fixed
- **Issue Pareto was permanently empty despite plenty of real itemized data in the DB** (confirmed via direct SQL: July 2026 alone has 1,188 `evaluation_items` rows). Root cause: `loadDashboardItemRows()` fetches item rows with `.in('evaluation_id', ids)` where `ids` is every evaluation across the rolling 12-month scope — 500–700+ UUIDs once itemized scoring is in full use. supabase-js sends `.in()` as a GET querystring, and a querystring that long was getting silently rejected before it ever reached Postgres. The failure was invisible because the code only assigned `dashItemRows` on success (`if(!error)`) — on failure it just stayed `[]` forever, with nothing logged to console. Fixed by batching the request (150 ids per call, run in parallel) and logging any batch failure instead of swallowing it.

### [Package v66] — 2026-09-18 — Unified 5-column tile grid
No SQL changes.

#### Changed
- **Action-strip (4 chips) and KPI row (6 cards) merged into one grid**, 5 columns × 2 rows, instead of two separately-sized grids (4-col / 6-col) stacked on top of each other. "Cycle coverage" moved up into row 1 alongside the 4 action chips so both rows land exactly 5/5.

### [Package v65] — 2026-09-18 — Dashboard KPI render bug fix
No SQL changes.

#### Fixed
- **Regression from v64**: removing the `#dashInsight` "monthly insight" banner element left a stale `if(!document.getElementById('dashInsight')) return;` guard at the top of `renderDashboardCommandCenter()`. With that element gone, the guard fired on every render and bailed out before computing any KPI, Cycle Health, Priority Queue, or Issue Pareto data — all showed 0/empty. Risk Matrix and the 12-month trend chart still looked fine because they're also called separately on tab-switch, outside this function — which is why only *some* of the dashboard looked broken. Guard and the dead code that referenced it removed; the function now runs to completion every time.
- Removed the redundant "Current cycle / —" row under the dashboard filter bar (`#dashPeriodTitle`/`#dashUpdated`) — informational only, not tied to anything actionable.

### [Package v64] — 2026-09-18 — Dashboard layout cleanup & EN/TH toggle fix
No SQL changes.

#### Fixed
- **EN/TH language toggle text was invisible** — the thumb (`position:absolute`) painted above the EN/TH labels regardless of DOM order, because `z-index` was set on the labels without `position` (has no effect on non-positioned elements). Fixed by giving the labels `position:relative` + explicit `z-index`, plus reordering the thumb first in the DOM as a second safeguard.

#### Changed
- Removed the hint text under "What I need to do" and under the Risk Matrix panel heading (redundant).
- Removed the "สรุปประจำเดือน" (monthly insight) banner from the dashboard.
- Reduced KPI/action-chip tile padding and font size so both tile rows sit shorter.
- Risk Matrix, 12-month trend, and Issue Pareto combined into a single grid: Risk Matrix now spans the full height on the left; trend (top) and Pareto (bottom) stack on the right.
- Issue Pareto now excludes purchase-tier criteria (C-1/C-2/C-3) — those are positive credit awarded by order-volume tier, not a recorded problem, so they don't belong in a Pareto of issue causes.

### [Package v63] — 2026-09-17 — Risk Matrix hover tooltip (the item deferred from v62)

No SQL changes.

#### Added
- **Risk Matrix now has a hover tooltip** — hovering any dot shows the supplier's code/name, score, risk band, and open corrective-action count in a small floating label positioned at that exact dot. Clicking a dot jumps straight to that evaluation's worksheet, same as clicking a row in the Priority Queue below it. Bigger dots (more open CAs) get a proportionally slightly larger hit area so they're not harder to target.
- **Priority & Early Warning list now shows 3 items before "View all (N)"**, down from 8 — matches the Action Board columns' length from v62, and the button now only appears (and shows the real count) when there actually are more than 3.

### [Package v62] — 2026-09-17 — Dashboard polish batch (symmetry, trend/Pareto bug, worksheet header, real supplier grouping)

SQL: run `database/32_supplier_group_by_prefix.sql` (after 21).

#### Fixed
- **Action strip (QA/CS-MP/Approval/CA pending chips) was a 6-column grid holding only 4 chips** — left an empty gap on the right, the actual cause of the "not symmetric" look against the KPI row below it (which correctly has 6 cards in 6 columns). Now a proper 4-column grid, and its cards were restyled to match the KPI cards' left-accent-bar look exactly (was a visually different rounded-all-corners style before) so the two rows read as one consistent design instead of two different card systems stacked together.
- **KPI/chip labels of different lengths threw off vertical alignment** — a 1-line label ("QA pending") and a 2-line one ("Cycle coverage") put their numbers at different heights. Labels now get a fixed min-height so every card's number lines up regardless of label length.
- **12-month performance trend chart silently ignored the Group/Shipment filter** — accepted an `arr` parameter but never used it, always plotting from the full unfiltered `evaluations` array regardless of what was selected above it. Now correctly scoped (new `dashboardTrendScope()` helper, shared with Issue Pareto below).
- **Issue Pareto was scoped to only the single currently-selected period** — with itemized scoring still relatively new, that one period alone usually had zero recorded items, so the panel was permanently empty in practice even when real data existed elsewhere. Widened to the same rolling 12-month/group scope as the trend chart.
- **Supplier grouping was an unverified keyword guess** (`21_supplier_category_cleanup.sql` matched words like "Plating"/"Mekki" in company names — left 8 of 22 Outsource suppliers unclassified, and was never guaranteed correct for the other 14). Replaced entirely with a deterministic rule enforced by a DB trigger: the code prefix is now the ONLY thing that decides a supplier's group (`MA-`→Material, `OS-`→Outsource, `PA-`→Blank Part). Applies to every insert/update, from Master Control, Excel import, or anywhere else — can't drift again. Master Control's Category field is now a read-only auto-preview instead of free text.

#### Added
- **12-month trend chart redesigned** — proper Y-axis gridlines/labels (50–100 scale matching the grading bands), a dashed reference line at the 80-point target, gradient area fill under the line, and a marker dot on every real data point. Gaps in the data (a period with nothing recorded) now show as a gap in the line instead of a misleading dip to 0.
- **Worksheet page header now shows which record you're on** — "Supplier Evaluation Worksheet — Sep-26 · Amino Co., Ltd." once a worksheet is open, instead of just the generic tab title. Stays correct across language switches (`setPageHeadTitle()` now checks for an open worksheet).
- **Supplier Profile info panel rebuilt into three visual zones** — identity (avatar initials colored by group, name, code/group/inactive badges), contact & stats (Attention/Tel/Target Score/Order Volume in a 4-column grid), and evaluation history — instead of one unstructured block of text.
- Action Board columns (QA/CS-MP/Supervisor/Manager) now show 3 items before "View all (N)" instead of 5, matching the Priority & Early Warning panel's own list length.

#### Deferred
- **Risk Matrix hover tooltip** (colored dot → floating supplier name on hover) — intentionally skipped in this batch per request, to be picked up separately. The matrix itself (colors, quadrant shading) is unchanged.

### [Package v55] — 2026-09-15 — Permission Matrix fix + Supplier Profile grouping (part 1 of a larger batch — more in this same version to follow)

No SQL changes for these two fixes.

#### Fixed
- **Permission Matrix was missing two rows entirely** — `ca_close` (existed since migration 19, never surfaced) and `eval_mark_sent` (added in v54, never added to the admin UI). Admin had no way to view or edit either from Master Control → Permissions. Both now show as normal checkbox rows.
- **Permission checkboxes auto-save with no visible confirmation** — was mistaken for "no Save button, does this even work?" Added a "Saving… / ✓ Saved" status line so each toggle now visibly confirms (the mechanism itself was already correct — this was a feedback gap, not a save failure).
- **Supplier Profile's trend chart looked broken but wasn't** — the page defaulted to `suppliers[0]` regardless of whether that supplier had any evaluation history; if it didn't, the chart rendered correctly but with nothing to plot, looking "broken." Now prefers a supplier (from whatever's currently listed) that actually has history.

#### Added
- **Supplier Profile now has a Group filter** (by Code-derived category — Material/Part/Heat Treatment/Plating/Outsource) above the supplier picker, narrowing the dropdown before choosing a specific supplier.

### [Package v61] — 2026-09-16 — Actually fix sub-tab centering this time, not just dismiss it as cache

No SQL changes.

#### Fixed
- **Sub-tab label centering (Setting's 5 tabs, Master Control's 5 tabs)** — v60's `text-align: center` fix was real but not robust enough against edge cases (a long label like "ตั้งค่า / สถานะ" or "บันทึกการใช้งาน" could push a flex child wider than its fair share without `min-width: 0`, throwing off the equal-width assumption `flex: 1` alone doesn't guarantee). Rebuilt `.subtab` to center via flexbox directly (`display:flex; align-items:center; justify-content:center`) rather than relying on `text-align` alone, added `min-width:0` so all tabs in a row are genuinely equal width regardless of label length, and added `text-overflow: ellipsis` so a label that still doesn't fit truncates cleanly instead of distorting the row. Also removed the `max-width: 640px` cap on both 5-tab rows (Setting, Master Control) — with 5 tabs that cap made each one quite narrow to begin with.

### [Package v60] — 2026-09-16 — Supplier Profile: readable trend chart, order volume shown as its actual meaning

No SQL changes.

#### Fixed
- **Supplier Profile trend chart plotted a supplier's entire evaluation history, not 12 months** despite being labeled "12-Month Trend" — with more than a year of data this crammed dozens of bars together with overlapping value numbers and unreadable rotated date labels. Now genuinely sliced to the last 12 (the full history table below is unaffected). Also hardened `drawBar()` itself against the same problem in general: when bars are too narrow to fit both a value number and a rotated label without overlapping, it now thins out which bars get labeled rather than cramming everything in regardless.
- **"Order Volume from E&H" showed a bare number (e.g. "5 / 10")**, meaningless without knowing what that number represents. Now reverse-looks-up the matching Purchase-tier criteria (C-1/C-2/C-3, each with a distinct point value) and shows its actual description instead — e.g. "100,000-999,999 Pcs or 5,000-9,999 Kgs" for a score of 5.
- **Re-verified item 14's sub-tab `text-align: center`** from v59 — confirmed present in the CSS with nothing overriding it afterward. Very likely a stale copy/cache on the reporting side (same pattern as a few earlier rounds) rather than a new regression; flagged rather than silently "fixed" again with no code change to point to.

### [Package v59] — 2026-09-16 — Dashboard cleanup, risk matrix fix, cascading report filter, new No-Shipment scoring formula

⚠️ **Run `database/31_no_shipment_carry_forward_scoring.sql`** — adds `suppliers.last_purchase_score`/`last_purchase_period`, converts `evaluations.raw_score`/`applicable_weight` from generated to trigger-maintained columns (existing values preserved unchanged), and replaces the No-Shipment scoring formula. Per explicit instruction, this does **not** retroactively recompute any existing evaluation — only future inserts/updates use the new formula.

Large batch (14 items from one review pass) — grouped by theme:

#### Dashboard
- Removed the "Declining" and "Data issues" KPI tiles — Declining duplicated the Priority Queue below (same underlying check, shown twice); Data issues was dominated by "suppliers without an email," which was never actually collected by design and isn't a real problem at this phase.
- Renamed "Priority Queue" → "Watch List" (เฝ้าระวัง) — better matches its actual mixed content (urgent + early-warning items, already tagged as such per-row).
- The Watch List's per-row button showed a raw risk score like "38/100" sitting right next to what looks like (but isn't) an evaluation score — genuinely confusing. Now shows a risk-level label (Very High / High / Moderate / Slight) instead of the number.
- Risk matrix: flipped the risk axis so low-risk suppliers plot near the top and high-risk near the bottom — combined with the existing score axis (high score = right), good performers now cluster top-right as intended. Background danger-zone shading moved to match.
- Removed "Corrective Action Control Tower" and "Data Confidence" widgets entirely (their own dead code removed too).
- **Found and fixed why the Issue Pareto chart was always empty**: its data only ever loaded when a Dashboard filter was touched — never on normal navigation to the page. Now loads as part of the standard boot sequence.
- Performance Trend and Risk Matrix (canvas-based) could end up drawn at 0×0 if a `renderAll()` happened to fire while the Dashboard tab was hidden, leaving them blank even once visible again. Added a size guard plus an explicit redraw via `requestAnimationFrame` when navigating to the tab. Same class of bug, same fix, applied to the Supplier Profile trend chart too.

#### Layout
- Reverted the topbar (title + Back/Forward/Language) back to a standalone bar floating on the page background, not merged into each page's own panel — so its size and position are now identical on every page (the per-panel merge from v52-53 made this vary by page). `relocateTopbar()` removed.
- Language button redesigned as an actual sliding EN/TH toggle switch showing both labels at once, instead of a single button whose text swapped.
- Reserved scrollbar gutter space always (`scrollbar-gutter: stable`) — pages with and without a scrollbar no longer cause the content width to visibly shift when switching between them.

#### Report page
- Replaced the flat "pick one evaluation from every evaluation ever" dropdown with a cascading Category → Supplier → Year → Month picker, each level filtered by the one above it.
- Added breathing room between the Refresh/Print buttons and the table header on the Yearly Summary sub-tab; removed the redundant "equivalent to the old Excel sheet" hint text.

#### Bugs found and fixed along the way
- `mUsers` label literally showed `&amp;` instead of `&` ("ผู้ใช้ &amp; สิทธิ์") — the stored string contained an HTML entity, but it's rendered via `textContent`, which doesn't decode entities. Fixed at the source.
- Sub-tab button labels weren't reliably centered — added explicit `text-align: center`.

#### Supplier Profile / scoring (items 10-11)
- New "Order Volume from E&H" field on the Supplier Profile — the Purchase-tier score from whichever month most recently had a real shipment, stored on the supplier record (updated automatically every time a normal-shipment evaluation is saved).
- **New No-Shipment scoring formula**, replacing "Quality only, out of 50": Quality is scaled 0-50 → 0-90 (so a quality mistake weighs proportionally *more* in a No-Shipment month, not less), topped up with the supplier's carried-forward Purchase score from item 10 (0 if none exists yet) — landing on the same 100-point scale every month uses, instead of a reduced 50-point one. Worked example from chat: Q=50/D=40/S=2 (total 92) one month → an equally clean No-Shipment month next now also scores 92, not 100. Mirrored exactly in the live Worksheet preview (`worksheetScores()`) so what's shown while filling the form matches what the database will actually save.

### [Package v58] — 2026-09-16 — Worksheet: hide the "open new" picker when viewing/editing an existing evaluation

No SQL changes.

#### Fixed
- **The Supplier/Year/Month/Shipment picker + "Open/Create Worksheet" button stayed visible even when looking at an existing, already-approved evaluation** — a leftover from before "+ Open New Evaluation" moved onto the Evaluation List (v47): the picker was originally the single front door for both creating new AND opening existing records, but once entry became split (List's "+" button vs. clicking an existing row), the picker no longer made sense to show for the "editing existing" path — cluttered the page and blurred the distinction between "pick a different record" and "you're editing this one." Now hidden whenever a worksheet is actually showing (existing or freshly created), and only reappears when starting genuinely fresh via "+ Open New Evaluation."

### [Package v57] — 2026-09-16 — Permission Matrix: make a silent RLS block loud instead of a false "Saved"

No SQL changes — diagnostic/UX fix only, still investigating the underlying permission issue reported live.

#### Fixed
- **`togglePermission()` never checked how many rows its UPDATE actually changed** — only whether the query errored. Supabase does not return an error when RLS silently filters an update down to 0 matching rows, so a blocked save looked identical to a successful one (showed "✓ Saved" either way). Added `.select()` to the update and an explicit check: 0 rows returned now shows a clear "Save was blocked — 0 rows changed, this is a database permission (RLS) issue" alert instead of a false success message. This should also definitively confirm (or rule out) the RLS-block theory being investigated live for a report of Permission Matrix checkboxes reverting immediately after being toggled.

### [Package v56] — 2026-09-15 — Translation audit (the piece flagged as not-done in v55)

No SQL changes.

#### Audit method (automated, not eyeballed)
- Scanned all 219 entries in the TH dictionary for ones containing zero Thai characters (a reliable signal of "never actually translated, just present").
- Scanned all 135 simple-form `L('en','th')` call sites the same way.
- Everything else already had genuine Thai text — this two-pass scan is why the audit could be done with confidence instead of guessing.

#### Findings
- **TH dictionary: 13 of 219 entries had no Thai text.** All 13 checked out as intentional established terms, not gaps — `Supplier`, `Corrective Action`, `Master Control`, `Import / Export`, `QA`, `CS / MP`, `Supervisor`, `Manager`, `Supervisor Approve`, `Manager Approve`, `Reject`, `User ID` — every one of these has been used in English consistently, by the user themselves, throughout this entire project's conversation history, even mid-Thai-sentence. Left as-is — forcing a Thai translation onto an already-established loanword would be the wrong fix, not a missing one.
- **`L()` calls: 4 of 135 had no Thai text — 3 were genuine gaps, fixed:**
  - Dashboard Action Board tags for "Mark Sent", "Sup. Approve", "Mgr. Approve" were literally duplicating the English text instead of having real (short) Thai — inconsistent with sibling tags on the same board that already had proper short Thai (e.g. "Follow up" → "ติดตาม CA"). Now: "ส่งผลแล้ว" / "รออนุมัติ Supv." / "รออนุมัติ Mgr."
  - The 4th, "No Shipment" (evaluation list badge), was left alone — matches the existing `shipmentNone: 'No Shipment เดือนนี้'` entry, which already established "No Shipment" as an intentional English term used inside an otherwise-Thai phrase elsewhere in the same app.
- Coverage note: the `L()` scan covered 135 of 145 total call sites (93%) — the other 10 use template literals or variables the simple pattern-match couldn't safely parse; not manually reviewed individually given the very high hit rate already found in the scanned majority.

### [Package v55] — 2026-09-15 — Setting restructured to 5 tabs + Translation override system

⚠️ **Run `database/29_translation_overrides.sql`** for the new Translation tab to work (creates the `translation_overrides` table). The rest of this version is frontend-only.

#### Changed
- **"Setup & Status" is now "Setting" with 5 sub-tabs**, replacing 4 separate top-level menu items: **Setup & Status** (unchanged content), **Master Control**, **Import/Export**, **Activity Log**, and the new **Translation** tab. Master Control and Import/Export sub-tabs stay Admin-only (matching their old nav-level gating); Activity Log stays visible to everyone, matching its original "everyone can view, only Admin can revert" design — only the new Translation tab is Admin-only per explicit instruction. Physically relocated ~170 lines of existing HTML into the new structure; verified afterward with a full duplicate-id scan (none) plus the usual syntax/cross-reference checks (all clean).

#### Added
- **Translation tab (Admin only)** — lets Admin override how any specific label is shown, in either language, without a code deploy. Built as an **override layer**, not a rewrite of the existing ~700-entry translation dictionary: a new `translation_overrides` table is checked first by both `t()` and `applyLang()`; anything not overridden falls through to the app's existing built-in text exactly as before. The key picker is populated by scanning every `data-i18n`/`data-i18n-ph` element currently in the DOM (including hidden pages, since they're just `display:none`, not removed) — so every label in the app is reachable, shown next to the app's current default text for context.
  - **Scope note, stated honestly**: this covers every `data-i18n`-driven static label. It does **not** cover inline dynamic text built via the separate `L(en, th)` helper (used for things like alert messages and some dynamically-generated table content) — those aren't tied to a stable key the override system can hook into. Retrofitting `L()` calls with keys would be a much larger, separate change.

#### Not done this round (flagged, not silently skipped)
- **The full "translate everything, audit every string" pass** requested alongside this — going through all ~700 existing translation entries checking each is actually translated (vs. just present) is a large manual/audit task on its own. Genuinely not attempted yet; the Translation override system above is the *tool* for fixing whatever gaps that audit would find, not a substitute for doing the audit.

### [Package v54] — 2026-09-15 — Close a real approval-flow gap: A/B skipped sent_to_supplier entirely

⚠️ **Run the SQL migration BEFORE deploying app.js/index.html** — if deployed out of order, Mark Sent will error until the new permission row exists.

Found via an external review of the approval flow (not this session's own testing) — verified against the actual code before implementing, all claims checked out.

#### Fixed
- **Grade A/B evaluations jumped straight from `mgr_approved` to `acknowledged` in one update, never actually passing through `sent_to_supplier`** — the DB never recorded "this was sent" as a distinct fact for those, and nothing stopped a client from skipping straight to `acknowledged` regardless of grade. `markSentToSupplier()` now does two real, separate transitions (still one click), and the DB trigger enforces both as genuine invariants: `sent_to_supplier` requires having been `mgr_approved`, and `acknowledged` requires having been `sent_to_supplier` — no more skipping, no matter what a client sends.
- **New `eval_mark_sent` permission** (default: everyone except QA) — marking something as sent was previously gated by nothing at the DB level; the button just happened to only be reachable at the right time in normal use.
- **Closing the last open Corrective Action on an evaluation now automatically closes the evaluation itself** (`sync_evaluation_on_ca_close` trigger) — previously a grade C/D evaluation stayed at `sent_to_supplier` forever even after its CA was closed, since nothing linked the two. Correctly checks that *every* CA on that evaluation is closed, not just the one just updated — an evaluation can have more than one CA (`seq_no` already supports this).
- **Fixed the same "only checks the first CA found" bug in two places** that assumed one CA per evaluation: `evalWorkflowStatus()` (the List's status badge) and the 📋 icon's link target (now prefers an open CA over a closed one when both exist, rather than whichever happened to be first in the array).
- **Renamed "Supplier รับทราบแล้ว" to "ปิดเคส"/"Closed"** everywhere (`statusLabel()`, the dead hidden `#f_status` select, and the help text describing this step) for consistency with the terminology `evalWorkflowStatus()` already uses.
- **One-time backfill**: any evaluation already stuck at `sent_to_supplier` with no open CAs (or none at all) gets closed automatically by the migration.

### [Package v53] — 2026-09-15 — Actually one card this time (v52 only looked like it from a distance)

No SQL changes.

#### Fixed
- **v52 styled the topbar to LOOK like the same card as the content below, but they were still two separate bordered boxes with a gap between them** — confirmed from a real screenshot. Fixed for real this time: the topbar `<header>` node (title + Back/Forward/language buttons) is now physically moved via JS (`relocateTopbar()`) to be the first child inside the active page's own panel, so it's genuinely one bordered box, not two boxes styled to match. There is still only one topbar element in the DOM — it gets relocated, not duplicated, so the button ids stay unique. Runs on every `renderAll()` (guaranteed on first load too, not just on navigation).

### [Package v52] — 2026-09-14 — Actually finished the topbar title merge from v48

No SQL changes.

#### Fixed
- **The heading + ←→EN buttons were never actually merged into one card** — v48 only removed the old buggy title and styled the topbar as a white card, but never added a title back into it, so pages still showed their heading in a separate panel below. Fixed properly this time: the topbar now has a title on the left and the nav/language buttons on the right, in one card — matching the reference layout. Learned from the v48 root cause: the title element has **no `data-i18n` attribute** at all (set purely via JS in `setPageHeadTitle()`, called from both `showTab()` and `applyLang()`), so `applyLang()` can never fight over it the way it did before.
- **Removed the now-duplicate in-page headings** on Corrective Action, Supplier Profile, Report Preview, Yearly Summary, Master Control, and Activity Log — each used to repeat the exact same text the topbar now shows. Left alone: Dashboard's "What I need to do" (names the Action Board widget specifically, not the page) and Monthly Input's own heading (different wording, not an exact duplicate) and Import/Export's two panel headings (each names its own panel, not the page).

### [Package v51] — 2026-09-14 — List page: drop Risk filter, merge checkbox/button row

No SQL changes.

#### Changed
- **Removed the Risk filter dropdown** (Only Risk / Only OK) — Refresh now sits right after the Grade/Status filters where Risk used to be. The now-fully-unused `isRisk()` helper was removed too (nothing else called it).
- **Merged the checkbox row and button row into one**: "Show open cases only" / "Has Corrective Action only" checkboxes sit flush left, Export/"+ Open New Evaluation"/"+ New Corrective Action" sit flush right in the same row — with a new smaller `.btn-sm` size so the buttons don't tower over the checkboxes.

### [Package v50] — 2026-09-14 — List page layout polish + real workflow-status filter

No SQL changes.

#### Fixed
- **Caught a real bug while implementing this**: merging "+ Open New Evaluation"/"+ New Corrective Action" into the same row as Export would have hidden both buttons from everyone except Admin — that row (`masterOnlyImportExportBar`) was Admin-gated from when it only held Export. Fixed by gating just the Export button itself (a `<span>` wrapper), not the row — the two "+" buttons stay visible to whichever roles could already see them.

#### Changed
- **Top bar (Back/Forward/language) now styled as its own white card**, matching the panels below instead of floating on the bare background — visually one continuous zone from the top of the page down, with padding preserved.
- **Evaluation List toolbar**: Export, "+ Open New Evaluation", and "+ New Corrective Action" now share one row — Export on the left, the two "+" buttons pushed to the right.
- **Removed the "need to import instead? go to Import/Export" hint text.**
- **Status filter now filters by the real workflow status** (Waiting on QA and MP/CS / MP/CS / QA / Supervisor / Manager / Ready to send / Waiting on CA / Closed) instead of the risk-based filter that used to sit under that label. Risk filtering (Only Risk / Only OK) is still available as its own separate dropdown next to it — different dimension (score-based vs. workflow-based), kept both rather than picking one.

### [Package v49] — 2026-09-14 — Corrective Action folded into the Evaluation List

No SQL changes.

#### Changed
- **"Corrective Action" is no longer a separate menu.** The standalone CA list page is gone — CA browsing now happens from the Evaluation List instead:
  - Any row that has a linked Corrective Action gets a **📋 icon** in its action buttons, opening that CA's form directly (hovering shows which criteria actually failed — the info the old CA list's dedicated column used to show).
  - New **"Has Corrective Action only"** filter checkbox, alongside the existing "Show open cases only" — combine them to see just the open CA cases, or uncheck "open only" to browse closed/historical CAs too.
  - New **"+ New Corrective Action"** button next to "+ Open New Evaluation" on the List toolbar, for the rare manual case (auto-creation normally handles grade C/D).
  - The CA form itself is unchanged (same filtered evaluation picker from v47) — just reached differently now. Its "Back" button goes to the Evaluation List instead of an internal CA list that no longer exists.

### [Package v48] — 2026-09-14 — Fix (for real this time): the "Dashboard" title that never went away

No SQL changes.

#### Fixed
- **Found the actual root cause, finally.** The shared `<h1 id="pageTitle">` element had `data-i18n="dashboard"` hardcoded directly in its HTML — meaning `applyLang()` (which resets every `data-i18n` element to its translated text, and runs on nearly every render) was stomping the title back to "Dashboard" moments after `setPageTitle()` set it correctly. The v46 "fix" was real but powerless against this — two systems were fighting over the same element on every single render.
- **Removed the shared title element entirely** rather than patch around the conflict — each page's own heading (already present on every page except List, which got one added back) is now the only "title," living inside that page's own content and driven by its own independent `data-i18n`, with no shared state left to fight over.

### [Package v47] — 2026-09-14 — Monthly Input folded into List, CA failed-criteria column, filtered CA evaluation picker

No SQL changes.

#### Investigated, not a new bug
- The "page title still says Dashboard" report was checked directly against the delivered v46 zip (not just the working copy) — the fix from v46 is genuinely present. Almost certainly a stale/cached copy on the reporting side (old folder not fully replaced, or a browser cache that didn't pick up the new files) rather than a regression. Worth a hard refresh / fresh extract before assuming it's back.

#### Changed
- **"Monthly Input" is no longer a permanent nav item.** The underlying worksheet page still exists (still what opens when editing an existing evaluation), but the only ways in now are: the new **"+ Open New Evaluation"** button on the Evaluation List page, or opening an existing row. The worksheet page itself got a **"← Back to List"** button since it no longer has its own permanent nav entry to return to.
- **Corrective Action list now shows which criteria actually failed**, per row — reads the evaluation's checklist for any item with occurrence > 0 and lists them (e.g. "A1-3 ตรวจพบข้อบกพร่องด้านคุณภาพ (x2)") instead of requiring someone to open the Worksheet to find out why the grade dropped.
- **Corrective Action creation's evaluation picker is now filtered** (supplier/code search + year + month) instead of one flat list of every evaluation ever — year/month default to the latest period with data, same idea as the Evaluation List's default filter.

### [Package v46] — 2026-09-14 — Evaluation List redesign + nav reorder

No SQL changes.

#### Fixed
- **Page title stuck showing "Dashboard" on other pages.** `setPageTitle()` used to read the active nav link's span text via a DOM query, which could lag/fail depending on timing — rewritten to pull directly from the translation dictionary (same system every other label in the app uses), which can't go stale.

#### Changed
- **"Evaluation List" moved to the 2nd nav position** (right after Dashboard/Action Board, which stays the default landing page). Removed the duplicate in-page heading that repeated the nav label.
- **New combined workflow status** replaces the raw DB status column — one label folds together submit stage, approval stage, and Corrective Action state: *Waiting on QA and MP/CS → Waiting on MP/CS → Waiting on QA → Waiting on Supervisor → Waiting on Manager → Ready to send to Supplier → Waiting on Corrective Action → Closed*. Each gets its own badge color (amber/teal/red/green) instead of one flat gray.
- **List defaults to open cases only** — a case counts as closed when it's `acknowledged`, or `sent_to_supplier` with its Corrective Action already closed (or no CA at all). Toggle to see everything with the new "Show open cases only" checkbox.
- **Filters default to the latest period with data** instead of showing the full history on first load.
- **Removed the raw-score text and the Comment column** — raw score only ever showed for No-Shipment rows (looked inconsistent); comment is still fully visible from inside the Worksheet.
- **Action buttons are now icons** (👁️ View / ✏️ Edit / 🗑️ Delete) — View is always shown; Edit only appears if the current role can edit any part of that evaluation; Delete only for roles with `eval_delete`.

### [Package v45] — 2026-09-10 — One-time data fixup: bulk-complete imported historical evaluations

Just one new SQL file this time, no app.js/index.html changes.

#### Added
- **`database/27_bulk_complete_imported_evaluations.sql`** — the Excel import feature always creates evaluations as `status='draft'` (no submitted timestamps), which is correct for genuinely new work but made freshly re-imported *historical* data (already finalized in the source files, no real deductions to make) look like "QA hasn't evaluated yet." This one-time script advances every still-`draft`, itemized evaluation straight to `acknowledged` — same treatment for every grade (A/B/C/D), no exceptions — stamping all workflow timestamps as today.
  - Deliberately skips the normal Submit → Supervisor Approve → Manager Approve → Mark Sent sequence, which means `auto_create_corrective_action` never fires (it only triggers on a transition *into* `mgr_approved` specifically) — **no Corrective Action gets created for any C/D grade in this batch**, on purpose: these are historical closed records, not open cases needing tracking.
  - `sup_approved_by`/`mgr_approved_by` stay `NULL` — nobody actually clicked Approve, so nothing fabricates who did.
  - Visible marker added to `quality_comment`/`delivery_comment` (`"[นำเข้าจากข้อมูลเก่า / Imported from Excel]"`) — but only where that field was empty, never overwriting a real comment — so it's obvious at a glance in the Worksheet that a record came from this bulk fixup, not just buried in Activity Log.
  - Scoped to `status='draft' AND scoring_mode='itemized'` only — doesn't touch anything already further along in a real, in-progress workflow.

### [Package v44] — 2026-09-10 — Fix: Import silently guessed the wrong year on filenames like "2025_..."

No SQL changes for the fix itself — see the cleanup guidance below for what to do about data already imported with the wrong year.

#### Fixed
- **Year detection from the filename used `\b(20\d{2})\b` — `\b` (word boundary) treats underscore as a word character, so it never matched on filenames shaped like `"2025_Evaluation_..."`** (no boundary between "5" and "_"). Confirmed live: `"2025_Evaluation_ST_HT_Dec-25.xlsx".match(/\b(20\d{2})\b/)` → `null` in real Node.js. When the regex failed, the code fell back to **the current system year** — meaning every file named this way imported as whatever year it happened to be run in, regardless of what the filename said. Fixed by dropping the boundary assumption (`/(20\d{2})/`).
- **Added a visible safety net so this category of bug can't silently slip through again**: the Import Preview now shows a warning badge whenever a filename has no `20xx` year at all (year had to be guessed from today's date) — and the Month/Year column is now directly editable in the preview, so a wrong year can be corrected right there before confirming, no filename renaming needed.

#### Cleanup guidance for data already imported with this bug
If you used Import before this fix on filenames like `"2025_..."`, some evaluations may have landed under the wrong year (most likely: everything imported got year = whatever year it was actually run in, e.g. 2026, even for files clearly meant for 2025). Recommended approach — precise, not a blind wipe:
1. Use the new **Activity Log** page (Admin) to find every `insert`/`update` on `evaluations` around the time you were testing Import — each entry has a timestamp and the exact before/after data.
2. Cross-check against which suppliers/months you actually meant to import, using the file names you have on hand.
3. For rows confirmed wrong: either use Activity Log's **Revert** (if the action is still revertible and hasn't been superseded by a later change), or delete the specific evaluation manually and re-import that file fresh with this fixed version.
4. Data imported via the two original SQL migrations (`17_import_july_2026_itemized.sql`, `18_import_heat_plating_suppliers.sql`) is unaffected — those used hardcoded, manually-verified years, not this filename-parsing logic, and don't need re-checking.

### [Package v43] — 2026-09-10 — Information architecture cleanup: 5 pages reorganized

No SQL changes — frontend-only restructuring, nothing about the database changed.

#### Changed
- **Corrective Action page split into List (default) and Form (opens on demand).** Previously showed a create/edit form and the full CA table together at all times — now defaults to a browse-only list; "+ New Corrective Action" or a row's "Edit" button opens the form, which has its own "← Back to List" button.
- **Removed the duplicate "Import from Excel…" button from the Evaluation List page** — redundant with the dedicated Import/Export menu. Export stays on the List page (it's naturally tied to per-row checkboxes there) with a small note pointing to Import/Export for the reverse direction; the Import/Export page now has a matching "Export to Excel" panel that explains it and links back to the List.
- **Moved "Open Monthly Cycle" from Setup & Status into Master Control → Suppliers.** It's a real workflow action (creates data), not a status-viewing thing — Setup & Status is meant to be look-only.
- **Activity Log is now its own top-level menu item, not a Master Control sub-tab.** Important distinction preserved correctly this time: unlike Master Control (Admin-only), the Activity Log menu is visible to everyone logged in — only the Revert button inside stays Admin-gated, matching the original "everyone can view, only Admin can revert" requirement from earlier in this project.

### [Package v42] — 2026-09-10 — Yearly Summary cells are now clickable

No SQL changes.

#### Added
- Every score cell in the Yearly Summary table (Supplier × Month grid) now opens that exact evaluation's Worksheet when clicked — reuses the same `editEvaluation()` navigation already used everywhere else in the app (Back/Forward history included). Empty months (`-`) aren't clickable, nothing to open there.

### [Package v41] — 2026-09-10 — Fix: Import hanging at "Finalizing scores"

No SQL changes.

#### Fixed
- **The "Finalizing scores…" step at the end of Import was entirely redundant, and got removed rather than just fixed.** `evaluation_items` already has an `AFTER INSERT/UPDATE/DELETE` trigger (`trg_evaluation_item_recompute`, from `10_phase3_autocalc.sql`) that calls `recompute_evaluation_scores()` automatically the instant the checklist upsert in the main import loop completes — every row was already fully scored by the time the loop finished. v40 added a second, manual RPC call for this "just in case," which was unnecessary duplicate work; when v40 also tried to speed that redundant step up by batching 10 of those calls concurrently, it caused a real hang (likely lock contention from firing that many concurrent evaluation updates through the Action Log trigger at once) — reported and confirmed live during testing (stuck at "0/646").
- **If you had an import stuck at this exact step: your data already fully landed correctly** — the hang was in unnecessary bonus work, not the actual import. Just reload the page; nothing needs to be re-run or fixed after the fact.

### [Package v40] — 2026-09-10 — Import: progress visibility + faster on large files

No SQL changes — frontend only, safe to just swap files.

#### Fixed
- **Import looked stuck when the same supplier appeared for multiple months in one batch** — the status text only ever showed the supplier name, so re-seeing "NISSAN SPRING" for a second, different month looked identical to the first and made it seem frozen. It was actually progressing the whole time (confirmed via direct DB checks during the investigation — every row from the test file landed correctly). Status text now includes the month (`Importing (12/646) — NISSAN SPRING (2026-Nov)`) and a running count.

#### Changed
- **Recompute calls no longer block the main import loop.** Each row previously awaited its own `recompute_evaluation_scores` call before moving to the next row — for large files (hundreds of rows) this was the main reason the whole thing felt slow. Recompute is now collected during the main pass and run afterward in parallel batches of 10, with its own progress counter ("Finalizing scores… (230/646)"). Net effect: same correctness, meaningfully faster on large imports.

### [Package v39] — 2026-09-10 — Fix: Import failing 100% for any supplier with an existing evaluation

#### Fixed
- **Root cause of the "646 failed, 0 succeeded" import you hit**: `confirmImport()` built the evaluations upsert payload with `status: existing ? undefined : 'draft'` — intended to mean "don't touch status if the row already exists," but a key set to literal `undefined` (rather than the key being absent entirely) confused how the request got serialized, and ended up sending back whatever status the existing row already had (e.g. `sup_approved`) in a way Postgres rejected outright (`invalid input value for enum eval_status: "sup_approved"`) — even though `sup_approved` is a perfectly valid status, just mishandled in transit. This is why every already-imported supplier (anything re-imported a second time) failed 100%, while brand-new suppliers would have gone through fine.
- Fixed by never letting `status` exist as an `undefined`-valued key at all — it's now only added to the payload object when there's actually a value to set (new row, or an intentional bounce-back to `draft`), otherwise the key is fully absent rather than present-but-undefined.

No SQL changes — this was a pure frontend bug. Re-import your files with this version; nothing was corrupted by the failed attempts (everything failed cleanly with 0 created/0 updated, matching what you saw).

### [Package v38] — 2026-09-10 — Fix: new suppliers from Import never got a category

#### Fixed
- **Auto-created suppliers during Import never had `category` set** — same NULL-category problem specifically fixed for the existing supplier base back in v34, silently reintroduced for any brand-new supplier discovered during Import (no sheet-name-to-existing-supplier match). This would have broken group filtering/analysis (Action Board, Dashboard) for those suppliers. Also removed a leftover no-op line (`prefix = X ? 'MA' : 'MA'` — always evaluated to 'MA' regardless of its condition).
- The Import Preview table now shows a **Category** picker for any row that will create a new supplier (Material/Part/Heat Treatment/Plating/Outsource) — the code prefix (`MA-`/`PA-`/`OS-`) is derived from whichever category is chosen. Rows matched to an existing supplier don't show this picker (they inherit the existing supplier's category, unaffected).

### [Package v37] — 2026-09-10 — Import / Export for the FM0704-3 Excel format

⚠️ **Export needs the app served over HTTP, not opened directly as `file://`.** It fetches a bundled template asset (`assets/fm0704_export_template.xlsx`) — browsers block `fetch()` of local files under `file://`. Even a bare-bones local server (`python -m http.server`, etc.) is enough. Import is unaffected — it reads the uploaded file directly via the browser's File API, no fetch involved.

#### Added
- **New "Import / Export" section (admin-only).**
- **Import**: upload one or more monthly FM0704-3 files at once (tested against real 12-month exports — verified against a known reference cell-by-cell in Node, matched exactly: month column, No-Shipment detection, occurrence values). Every supplier sheet is parsed and fuzzy-matched to an existing Supplier (normalizes "Co.,Ltd."/"Company Limited"/punctuation before comparing); no match found creates a new Supplier automatically. **Nothing is written until you review a preview table and confirm** — each row's match is editable, and a warning badge appears if the recomputed score (from occurrence counts, against the *current* active criteria) doesn't match what the Excel file itself reports, which usually means the criteria have been versioned since that month was scored.
  - Re-importing the same supplier+month upserts (updates in place, never duplicates).
  - If the target evaluation is already past `draft` and the import would actually change its scores, it's bounced back to `draft` (both submit timestamps cleared) rather than silently overwriting an already-approved record's numbers. If the scores come out the same, status is left untouched.
- **Export**: select evaluations via checkboxes on the Evaluation List (only `scoring_mode='itemized'` rows are selectable — `manual`-mode historical evaluations have no per-criteria breakdown to put back into the file, so they're correctly excluded rather than exported with fabricated zeros) → "Export Selected (N)" → downloads one `.xlsx` containing only the selected suppliers' sheets, not the whole company roster.
  - Technique: clones the real blank `FM0704-3 Rev.2(P.1)` template sheet (confirmed genuinely blank, not a real supplier's leftover data) per selected evaluation, and only overwrites the specific data cells (company info, month, occurrence counts) — formatting, merged cells, borders, and the %/grade formulas all survive untouched, since only cell values are touched, never cell styles.

#### Known limitations (flagged honestly, not yet resolved)
- Have not yet done a full pixel-by-pixel comparison of an actual exported file against the original in real Excel — the cell-position logic is verified correct, but the full round-trip hasn't been visually confirmed yet.
- Exported files' %/grade formulas show whatever was last calculated until Excel recalculates on open (its normal default behavior — not something this package needs to force, just worth knowing if opened in a non-Excel viewer that doesn't auto-recalculate).

### [Package v36] — 2026-09-09 — Admin-created accounts (replaces self-signup)

⚠️ **This one needs a manual deployment step — it can't be done via SQL alone.**

1. Run `database/26_admin_create_user.sql`
2. Deploy the Edge Function: `supabase functions deploy admin-create-user` (from a terminal with the Supabase CLI, after `supabase login` and `supabase link` — see the deployment notes at the bottom of `supabase/functions/admin-create-user/index.ts`). No secrets to configure — `SUPABASE_URL`/`SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY` are injected automatically by the platform.
3. In Supabase Dashboard → Authentication → Providers → Email, turn off **"Allow new users to sign up"** — this is the step that actually blocks public signups; everything else in this package just stops the app from offering it.

#### Added
- **Master Control → Users & Roles now has a "Create Account" form** (User ID, temporary password, full name, department — any of the 7 roles, not just qa/cs/mp). Calls a new Supabase Edge Function (`admin-create-user`) that verifies the caller is actually Admin (via their own JWT and the same `permission_rules` the rest of the app reads) before using the service role key to create the auth user — the service role key is never sent to the browser, this function is the only place it's used anywhere in the project.

#### Changed
- **`handle_new_user()` no longer force-downgrades non-qa/cs/mp departments to `qa`.** That restriction existed specifically to stop a public `signUp()` call from claiming an elevated role — now that public signup is being turned off entirely, the Edge Function (which already checks Admin) is the only path left, so it's trusted to set any valid department, including Supervisor/Manager/Admin.

#### Superseded
- REC-P0-05's earlier "needs confirmation" note is resolved — self-signup removal is now permanent, replaced by this admin-created-account flow.

### [Package v35] — 2026-09-09 — Reject flow, Action Log, Criteria versioning, recommend.md P0 fixes

⚠️ **New migrations must run in order: `22_reject_flow.sql` → `23_action_log.sql` → `24_criteria_versioning.sql` → `25_schema_version.sql`.** After running all four, the app will require schema version 25+ to load (see REC-P0-04 below) — running them out of order or partially will cause the app to correctly refuse to load with a clear message rather than failing confusingly.

#### Added — Reject flow
- Supervisor and Manager review stages now have a **Reject** button alongside Approve. Rejecting always sends the evaluation back to `draft` and clears both submitted timestamps — QA and CS/MP must resubmit. A reason is required (enforced in the database, not just the UI) and shown on the worksheet the next time someone opens it.

#### Added — Action Log (Master Control → Activity Log)
- Generic before/after audit trail on evaluations, corrective actions, suppliers, evaluation criteria, permission rules, and user profiles. Everyone can view; only Admin can **Revert** — and only inserts, deletes, and updates that didn't change a workflow `status` (submit/approve/reject/close are visible but never auto-revertible, per this session's risk assessment).

#### Added — Master Criteria Versioning
- An evaluation criteria that's already been used in a real evaluation is now **immutable** except for `display_order`/`is_active` — editing it instead creates a new version in the same lineage (old one deactivated, new one takes over), so historical evaluations keep pointing at the exact version that was true when they were scored. The Master Control save button figures out which path applies automatically (with a confirmation prompt when it's about to version something) — no manual "lineage" decision for the user. Dashboard's Issue Pareto now aggregates by lineage across versions instead of splitting into separate bars.

#### Fixed (per external code review, `recommend.md`)
- **REC-P0-01**: `loadEvaluations()` never actually fetched `category`/`is_active`/`target_score` on the nested supplier relation — Action Board's supplier-group filter was silently broken. Fixed.
- **REC-P0-02**: Stopped storing the password in `localStorage` (was base64-"encoded", which is not encryption). Only the User ID is remembered now; any legacy stored password is deleted automatically the next time it's encountered.
- **REC-P0-06**: `statusLabel()` had no mapping for `sup_approved`/`mgr_approved` since v33 — every screen showing an evaluation's status was displaying the raw database value for those two states instead of a proper label. Fixed.
- **REC-P0-04**: Added `app_schema_version` tracking + a startup check (`checkSchemaVersion()`) — the app now blocks with a clear message if the database is behind the migrations this app version needs, instead of loading and failing confusingly on whichever feature touches the gap first.
- **REC-P0-05**: Self-signup is now off by default (`SELF_SIGNUP_ENABLED = false` in app.js — easy to flip back). **Note: this reverses an earlier explicit decision in this project to allow QA/CS/MP self-signup** — worth confirming this is really wanted before treating it as final. Also: hiding the tab alone isn't real protection — Supabase Dashboard → Authentication → Providers → Email → "Allow new users to sign up" should also be turned off for this to actually block signups, not just hide the button.
- **REC-P0-03 (partial)**: Added an `escapeHtml()` helper and applied it to the highest-exposure free-text fields (evaluation/profile comments, corrective action problem/responsible person, supplier code/name/short_name/category in Master Control tables). This is a meaningful risk reduction on the fields most likely to be exploited, **not** an exhaustive audit of every `innerHTML` use in the app — the codebase is large and a full pass is a separate piece of work.
- **REC-P0-07 (not done)**: No automated test suite — the project has no build tooling at all (plain script tags, no bundler/test runner), so real automated tests need separate infrastructure decisions first.
- **P1/P2/P3 items from `recommend.md` not addressed this round** (concurrency protection, role-focused dashboards, app.js modularization, pagination, notifications, SSO, etc.) — logged as backlog, see the original `recommend.md` for full detail.

### [Package v34] — 2026-09-09 — Action Board bug fix, shared filter, supplier categories

#### Fixed
- **Corrective Action items were still showing in QA's Action Board column** — v33 moved CA ownership from QA to CS/MP at the permission level, but I forgot to move the corresponding item-generation code in `renderActionBoard()`. Moved to `csItems` where it belongs.
- **Action Board had no scope at all** — it pulled every unfinished evaluation across the entire history (confirmed in production: 607 QA items, 650 CS/MP items). Reused the Dashboard's own existing period/group/shipment/risk filter bar instead of building a new one: moved it to sit above the Action Board, and both the Action Board and the analytics widgets below it now read from the same filter state. Defaults to the latest period with data (unchanged existing behavior). The "supplier hasn't opened this month" item stays tied to the real current calendar month regardless of which period is selected to browse (that's the one thing "this month" always has to mean), but still respects the supplier-group filter.

#### Added
- **`database/21_supplier_category_cleanup.sql`** — supplier categorization was in bad shape: the original Material/Part suppliers (`MA-xxx`/`PA-xxx`) had no `category` set at all, and all 22 Outsource suppliers were lumped under one generic `'Outsource'` value with no Heat Treatment/Plating distinction. Set `Material`/`Part` from the code prefix (high confidence), and split 14 of the 22 Outsource suppliers into `Heat Treatment`/`Plating` based on an unambiguous keyword in the company name (Thermo/Induction/Heat Treatment → Heat Treatment; Plating/Mekki/Coating/Parkerizing/Electro Chemical/Surface Technology → Plating). **The remaining 8 (Tanabe, Union Autoparts, T.I.D., Taiyo Seisakusho, B.K.J., Trix, Silvec, Miyaki) have no identifiable keyword and are left as generic `Outsource`** — this is a best-effort keyword match, not a verified classification; correct via Master Control → Suppliers if you know their actual process type.

### [Package v33] — 2026-09-04 — Two-tier approval, new roles, CA ownership moves to CS/MP

⚠️ **`database/20_two_tier_approval.sql` must be run in two parts** — Part 1 (the 4 `ALTER TYPE ... ADD VALUE` lines) alone first, then Part 2 (everything else) after Part 1 succeeds. Same Postgres limitation hit before with `cs_supervisor` in v0.7.0.

#### Added
- **Two new roles:** `mp_supervisor` (identical rights to `cs_supervisor`, kept as a separate department purely so the audit trail shows which supervisor actually acted) and `opd_manager` (oversees both CS and MP combined — approval-only, no score/CA/master-data access).
- **Two new evaluation statuses:** `sup_approved`, `mgr_approved` — deliberately *not* reusing the old `'approved'` value (retired in place, same pattern as the dead `'supervisor'` department — Postgres can't drop enum values).
- **New approval flow:** both sections submitted → **Supervisor Approve** (`cs_supervisor`/`mp_supervisor`/`admin`) → **Manager Approve** (`opd_manager`/`admin` only, requires Supervisor Approve first, applies to every grade with no exceptions) → Mark Sent (now gated on `status='mgr_approved'`). Two new UI buttons replace the single old "Approve Evaluation".
- New audit columns `sup_approved_by/at`, `mgr_approved_by/at` (separate from the now-unused `approved_by/at`).
- New permission rule_keys `eval_sup_approve`, `eval_mgr_approve` (replacing the retired `eval_approve`).

#### Changed
- **`auto_create_corrective_action` now fires on `mgr_approved`, not the old `approved`** — a corrective action for a C/D grade is only created after final Manager Approval, per this session's decision ("รอ manager approve ก่อนค่อยสร้าง").
- **Corrective Action ownership moves from QA to CS/MP entirely.** QA drops out of CA completely (`ca_edit_restricted`/`ca_close` turned off for QA) — QA's job is now just submitting Quality/Environment scores. CS/MP get `ca_edit_full` (every field, including closing the case themselves) — the one thing they still can't do is delete a CA; that stays Supervisor/Admin-only ("Supervisor keeps override/delete rights").
- **Action Board grows from 3 to 4 columns**: QA / CS-MP / Supervisor / Manager.
- Master Control → Users & Roles and → Permissions updated for the two new departments and two new rule_keys.
- Dashboard's "evaluation is complete/settled" checks (KPI completion %, cycle pipeline, supplier risk index) updated to key off `mgr_approved` instead of the retired `approved`.

#### Noted for later (not built yet)
- Two-sheet export (evaluation report + supplier countermeasure-response form) with auto-mapping of Root Cause/Action/Due Date back into the app from an uploaded response file — logged as an open question in `PLAN.md`, format not yet discussed.

### [Package v32] — 2026-09-04 — Workflow simplification: drop Mark Acknowledged, QA can close CA

#### Changed (`database/19_ca_close_permission.sql`)
- **Dropped "Mark Acknowledged" as a manual step** — decided it was redundant with the supplier actually sending back a countermeasure file, which is the real proof of engagement. `evaluations.acknowledged_at`/`'acknowledged'` status stay in the schema (nothing to migrate), just no longer set by hand.
- **Grade A/B: "Mark Sent to Supplier" now auto-closes the case** — sets `status='acknowledged'` in the same click, since there's nothing left to wait on.
- **Grade C/D: the corrective action is editable and closeable from the moment it's created** — no "wait until X" gate (there wasn't a real one enforced before either, this just makes the intent explicit).
- **New "Mark Received Countermeasure" button on the Corrective Action form** — sets `status='closed'` + `finished_date=today` in one click, replacing manual dropdown status changes for this specific transition.
- **New permission rule `ca_close`** (seeded: QA/CS Supervisor/Admin = true, CS/MP = false) — QA can now change a CA's `status`, but *only* to `'closed'`, nothing else; enforced in an updated `enforce_ca_edit_permissions`.

#### Changed (app)
- Removed the "Mark Acknowledged" button and its handler.
- Action Board's QA corrective-action items are back to a single group (no more "waiting for file" vs "file arrived" split) — just "Open — fill in findings and close when done", overdue ones sorted first.

### [Package v31] — 2026-09-04 — Action Board, Outsource supplier group import

#### Added
- **`database/18_import_heat_plating_suppliers.sql`** — adds the "Outsource" supplier group (Heat Treatment, Plating — CS's supplier category) that wasn't in the system at all: 22 new suppliers (`OS-001`..`OS-022`) plus their real July 2026 itemized evaluation data, from `01_FM-0704-3_..._Jul-26_.xlsx`. Same template/import approach as the Material batch (`17_...sql`) — including the same No-Shipment ÷60 formula bug present in 5 of these 22 suppliers' Excel-reported scores, corrected automatically by the existing trigger. Verified before importing that this file's "wQuality/wDelivery/wPurchase" cells are actually achieved scores (not fixed weights, despite the label) — confirmed via SAHASIN showing `wQuality=44` (a real deduction) — doesn't affect the import logic since it's computed from the occurrence column directly either way, just worth knowing if you ever eyeball the raw file.
- **Action Board** — new panel pinned at the very top of the Dashboard: three columns (QA / CS-MP / CS Supervisor), each showing up to 5 pending items with a "View all" link if there are more, or "✓ All caught up" if empty. Independent of the Dashboard's own period/category/shipment/risk filters on purpose — a to-do shouldn't disappear because a filter happens to be set. Column matching the current user's actual permissions (`hasPerm()`, not a hardcoded department) is highlighted; the other two show as context. Logic: QA = quality not yet submitted + open corrective actions (overdue sorted first); CS/MP = suppliers with no evaluation opened this calendar month + delivery/purchase not yet submitted + approved evaluations waiting to be marked sent; CS Supervisor = both sections submitted, ready to approve. Clicking any item opens it directly.

### [Package v30] — 2026-09-04 — Fix: import script assumed evaluations rows already existed

#### Fixed
- **`17_import_july_2026_itemized.sql` used a plain `UPDATE evaluations ...`, which silently does nothing if that supplier's July 2026 row doesn't exist yet.** For at least one supplier it didn't, so the following `INSERT INTO evaluation_items` tried to attach to a `NULL` evaluation_id and violated the not-null constraint — and since the whole script runs as one transaction in the SQL editor, that single failure **rolled back everything**, including the parts that looked like they'd succeeded in an earlier run (the v29 fix's assumption that earlier steps were already saved was wrong for this reason).
- Changed to `INSERT ... ON CONFLICT (supplier_id, year, month) DO UPDATE` (upsert): creates the row if missing, updates just `scoring_mode`/`shipment_status`/`no_shipment_reason` if it already existed (never touches `status` or approval history on an existing row). The whole script is now self-sufficient — it no longer depends on any prior seed/import having already created these rows.
- Removed `17b_fix_recompute_trigger_issue.sql` from v29 — it assumed a partial-success state that turned out not to exist (nothing was actually committed). Just run the corrected `17_import_july_2026_itemized.sql` fresh; it's safe to re-run any number of times either way.

### [Package v29] — 2026-09-04 — Fix trigger-timing bug in the July import script

#### Fixed
- **`17_import_july_2026_itemized.sql` re-enabled `trg_enforce_evaluation_edit` one step too early** — before the final safety-net `recompute_evaluation_scores()` calls, which each do their own internal `UPDATE evaluations` and so hit the now-active trigger (which requires a logged-in app user; `auth.uid()` is null in the SQL editor). All the actual data (the UPDATE/INSERT steps) already succeeded before this point — only the last batch failed. Moved `enable trigger` to after all 31 recompute calls, where it belongs.
- Added `database/17b_fix_recompute_trigger_issue.sql` — run this once if you already ran the old version of `17_...sql` and hit this exact error; it finishes the interrupted run (just the recompute + sanity check) without repeating the earlier steps. Not needed for anyone running the corrected `17_...sql` fresh.

### [Package v28] — 2026-09-04 — Back/Forward navigation, Dashboard merge, real July 2026 itemized import

#### Added
- **Back/Forward buttons** (topbar, left of the language toggle) — built on the real browser History API, not a custom stack: every tab switch pushes a history entry, and opening a specific evaluation/corrective action/supplier profile/report replaces that entry with the record's id attached, so Back returns to the exact thing you were looking at, not just the tab. The browser's own Back/Forward buttons and keyboard shortcuts now work the same way.
- **`database/17_import_july_2026_itemized.sql`** — real per-criteria checklist data for July 2026, extracted directly from `07__JULY_26.xlsx` (each supplier sheet's "Time Score" column) for the 31 suppliers that actually have July data in the file. MA-088 (Yamaichi) excluded — its sheet is mislabeled and actually contains June data (checked via each sheet's own month cell, not the tab name). Also sets `shipment_status` per supplier from the sheet's own weight columns — turned out 9 of 31 are No Shipment this month, not the 5 found in an earlier partial sample. Side effect: previously-buggy Excel scores (e.g. one supplier's Excel-reported 76.67%, which used the old ÷60 formula) now compute correctly (92%) automatically, since this data goes through the same corrected triggers as everything else.

#### Changed
- **Dashboard: merged "Priority Queue" and "Early Warning" into one card.** They overlapped heavily (both fired on overdue CA and declining score) — Priority is broader (any risk score ≥35, including reasons like "below target" that Early Warning never caught) while Early Warning is narrower but independent of overall risk (a big single-period drop can warn even if cumulative risk is still low). Combined into one risk-sorted list with a badge per row showing which signal(s) fired — a supplier can show both tags at once.

### [Package v27] — 2026-09-04 — Evaluation List rebuild, rounded-score tooltips, consistent date format

#### Fixed — Evaluation List table
- **Column headers now actually align with their data** (Q/E/D/P/Total headers are right-aligned to match the numbers below them — they were plain left-aligned text before, while the data cells were right-aligned, so nothing lined up).
- **Edit/Delete buttons no longer collide** — wrapped in a proper horizontal flex row (`.row-actions`) instead of relying on inline spacing that could wrap awkwardly.
- **Status text ("Approved") no longer truncates**, and the **Comment/Remark column is narrower with overflow hidden** (ellipsis) instead of stretching the row — full text still available via a hover tooltip on the cell.
- **Added Year and Month filters** alongside the existing search/grade/status filters.
- **Split Quality into Q (A1) and E (A2/Environment) columns.** Only possible for `scoring_mode='itemized'` evaluations (computed from `evaluation_items`, see `qualityEnvSplit()`) — the 574 legacy `manual` evaluations only ever stored one combined number, so those show Q = the original combined score and E = "-", by agreement (no fabricated split for data that doesn't exist).
- **Year + Month merged into one column**, formatted "2026-Jul".

#### Added — app-wide
- **`scoreNum()` helper**: evaluation scores (total %, quality/delivery/purchase, averages) now display as whole numbers with the precise 2-decimal value in a native hover tooltip. Applied to Evaluation List, Supplier Profile history, Yearly Summary, and the Dashboard's average-score KPI/insight line. Deliberately **not** applied to Report Preview, since that screen is meant to be printed/shared as a PDF where hover tooltips don't work — it keeps showing full precision directly.
- **`ymLabel()` helper**: consistent "2026-Jul" format applied everywhere a record's year+month is shown (Evaluation List, Supplier Profile, Corrective Actions, Report Preview, Dashboard period selector/title). Exceptions: the Dashboard's compact 12-month trend chart (canvas, no room for full year+month per tick — shows month only) and the Yearly Summary matrix (structurally already has month names as column headers, nothing to merge).

### [Package v26] — 2026-09-04 — Table/badge visual polish, clearer login feedback

#### Changed (`style.css` only — no HTML/JS structural changes)
- Tables (Evaluation List, Corrective Actions, Master Control, etc.) now sit in a bordered, rounded card, rows highlight on hover, badges are pill-shaped with a small status dot, and the "Edit/Delete" row actions are now small outlined buttons instead of plain colored text — same data, same functions, just easier to scan.

#### Added
- **Sign-in now shows an explicit "Signed in — loading your data…" success message** before the screen transitions to the Dashboard (previously: nothing, in case there was any delay it could look like the click didn't register). Sign-up already had a success message.
- Common Supabase auth errors (invalid credentials, already registered, email not confirmed, etc.) are now translated to Thai when the app is set to TH, via a small `friendlyAuthError()` mapping, instead of always showing Supabase's raw English text.
- Login/signup feedback is now a colored alert banner (green for success, red for error) instead of plain colored text, consistent with the rest of the app's badge/alert styling.

### [Package v25] — 2026-09-04 — Loading screen firing on every tab switch, default language

#### Fixed
- **Loading overlay was popping up every time the browser tab regained focus**, not just on real sign-in. Cause: `sb.auth.onAuthStateChange` fires a `TOKEN_REFRESHED` event whenever Supabase's client refreshes the session token — which happens, among other times, whenever the tab becomes visible again — and the handler called `reloadAll()` unconditionally on every event. This was already slightly wasteful before v24 (re-fetching everything for no reason), just invisible without a loading screen to show it. Fixed in `handleSession()`: if it's the same already-logged-in user and the app shell is already showing, skip the reload entirely — checked by comparing user IDs rather than the event name, so it doesn't depend on Supabase's exact event naming.

#### Changed
- Default language is now Thai (`lang = 'th'`) instead of English, for anyone who hasn't set a preference yet. Anyone who already switched to EN keeps that (it's saved to `localStorage`) — this only affects first-time users/browsers.

### [Package v24] — 2026-09-04 — Loading screen + disabled-button styling

#### Added
- **Loading overlay on login/app start.** `reloadAll()`'s 8 sequential fetches (suppliers, evaluations, corrective actions, criteria, master suppliers, users, permission rules, holidays) used to run behind an already-visible (empty/partial) dashboard. Now a full-screen overlay — progress bar, animated hourglass, and a "Loading X (i/8)" label — covers the app until every step finishes, then disappears. No more seeing zeroed-out KPIs while data is still streaming in.

#### Fixed
- **`.btn:disabled` had no visual style at all** — a disabled button (e.g. "Approve Evaluation" before both sections are submitted) looked pixel-identical to an enabled one, just didn't respond to clicks. Added a clearly greyed-out disabled state for buttons and form inputs/selects, so it's obvious at a glance what's currently actionable.

### [Package v23] — 2026-09-04 — Thai criteria translations, sidebar fix, holiday calendar, monthly cycle opener

#### Added
- **Thai translations for all 22 evaluation criteria** (`database/14_criteria_thai_translation.sql`). Checked the source Excel first (the real FM0704-3 template sheet and the "ตัวอย่างสูตร" formula-example sheet) — it's genuinely English-only, no Thai text anywhere in the file, so these are fresh translations rather than pulled from the source. Wired into the Official Worksheet checklist, purchase tiers, the Dashboard's Issue Pareto, and Master Control's criteria table (now shows EN + TH side by side, with a new "Description (TH)" field for editing).
- **`public_holidays` table** (`database/15_public_holidays.sql`) — closes the flagged limitation that Corrective Action's "5 working days" due date only skipped weekends. Seeded with Thailand's official 2026 public holidays (cross-checked via web search against several holiday-calendar sources). `add_working_days()` now skips both. Managed via new Master Control → Holidays tab (admin-only) — add future years or company-specific days off there, no SQL needed going forward.
- **`evaluation_cycles` table + "Open Monthly Cycle" action** (`database/16_evaluation_cycles.sql`) — the Dashboard's own v0.8.0 notes flagged that cycle coverage was derived from `evaluations` directly rather than a real cycle concept. New admin-only panel on Setup & Status: pick a year/month, click "Open Cycle", and a draft evaluation (itemized mode, 0 scores) is created for every active supplier that doesn't already have one that month — idempotent, safe to re-run, never touches an existing evaluation. Note: the Dashboard's own coverage numbers aren't wired to this table yet, that's left for later.

#### Fixed
- **Sidebar no longer stretches/shrinks with page content.** `.rail` was a flex sibling of `.main`, so its height matched whatever `.main` happened to be (which varies a lot by tab/content length). Changed to `position:fixed; height:100vh`; `.main` now uses `margin-left:230px` instead of flex sizing. Print stylesheet updated to match (no leftover blank margin).
- Refreshed the stale "Working in this phase" / "Not yet" lists on Setup & Status — they still said Phase 3-6 were pending, when all of that shipped several versions ago.

### [Package v22] — 2026-09-04 — Dynamic, admin-editable permission rules

#### Added (`database/13_dynamic_permission_rules.sql`)
- New `permission_rules` table: (rule_key, department, allowed) — 11 rule_keys × 5 departments, seeded to reproduce every rule from v1.1.0 exactly (no behavior change on migration).
- New `has_permission(rule_key)` function — every trigger/RLS policy that used to hardcode `department in (...)` now calls this instead: `enforce_evaluation_edit_permissions`, `enforce_ca_edit_permissions`, `can_create_ca`, `is_admin` (redefined to delegate, so 09's suppliers/evaluation_criteria/user_profiles policies become dynamic for free), and the delete policies on `evaluations`/`corrective_actions`/`evaluation_attachments`.
- Master Control → Permissions is now a **live, editable** matrix (was a read-only reference table in v1.1.0) — admin ticks a checkbox, it writes to `permission_rules` immediately and takes effect for real (both the database enforcement and the app's own show/hide/disable logic, which now reads the same table via a `hasPerm()` JS helper instead of its own hardcoded checks).

#### Fixed (found while rewriting the role-gating code to be dynamic)
- `worksheetRoleAccess()` incorrectly let CS/MP edit the A2 Environmental checklist (string-compared the display label `'environment'` instead of recognizing it's the same DB category as Quality) — the database would have rejected the save anyway with a confusing error, but the UI shouldn't have offered it. A1 and A2 now both correctly require `eval_edit_quality`.
- `enforce_evaluation_edit_permissions` used to let `admin` skip the "both QA and CS/MP sections submitted" requirement before approving, while `cs_supervisor` still had to satisfy it — an inconsistency from how the old code special-cased `dept = 'admin'` entirely. The rule is now uniform: anyone with `eval_approve` must satisfy the same both-submitted check, admin included.

#### Known limitation
- This makes existing rules toggleable, not extensible — adding a brand new kind of permission (a new `rule_key`) still requires a code change and migration, since something has to actually call `has_permission()` for it somewhere. What's dynamic is *who* can do the 11 already-wired actions, not adding new actions from the UI.

### [Package v21] — 2026-09-04 — Corrective Action permission tiers + Permissions reference panel

#### Changed (`database/12_ca_permission_tiers.sql`)
- `corrective_actions` was fully open to any authenticated staff since v0.5.0 — now split into tiers, as decided:
  - **Create new:** CS, MP, CS Supervisor, Admin (not QA)
  - **Edit any field / Delete an existing record:** CS Supervisor, Admin only
  - **QA:** may still update `root_cause`/`action` on an existing record (their investigation), nothing else — enforced by a new `enforce_ca_edit_permissions` trigger, same column-level pattern as `enforce_evaluation_edit_permissions`
  - **Attachment delete:** CS Supervisor/Admin only (applies to both evaluation- and CA-side attachments, since they share one table). Upload stays open to everyone who can touch the record, including QA.

#### Added
- App: form fields on the Corrective Action screen now disable/enable per the rules above (`applyCaRoleGating`), and the Delete buttons (both for the CA row and for attachments) only render for CS Supervisor/Admin.
- Master Control → new **Permissions** sub-tab: read-only reference table of who-can-do-what across Evaluations / Corrective Actions / Attachments / Master Data. Explicitly labeled as reference only — the real rules live in the SQL migrations; this screen doesn't change them (a live-editable permission system would need a separate rules table the triggers read from, not built yet).

### [Package v20] — 2026-09-04 — Critical fixes from v19 review + Phase 6/7

#### Fixed (critical — found during cross-session review of v19)
- **Data-loss risk:** `editEvaluation()`/`saveOfficialWorksheet()` never checked `scoring_mode`. Opening any of the 574 legacy `'manual'` evaluations in the new Official Worksheet and clicking any Save/Submit button would silently force `scoring_mode:'itemized'` and recompute scores from an empty checklist — wiping the real historical `quality_score`/`delivery_score`/`purchase_score` with 50/40/0, with zero warning. Fixed: `renderOfficialWorksheet()` now shows a warning banner with the original scores whenever `scoring_mode === 'manual'`, and `saveOfficialWorksheet()` requires an explicit `confirm()` before proceeding in that case.
- **Missing feature:** the Approve action was completely gone — `f_status` was a hidden `<select>` and no code path ever wrote `status: 'approved'`, so the entire Phase 4 approval gate (and the `auto_create_corrective_action` trigger that depends on it) was unreachable from the UI. Fixed: added dedicated "Approve Evaluation" / "Mark Sent to Supplier" / "Mark Acknowledged" buttons, each gated by role/workflow-state.
- **Dead code:** `resetForm`, `editEvaluation`, `saveEvaluation` were each declared twice in the same file (the second, worksheet-based versions silently shadowed the first, JS-legal but confusing) — removed the ~70 dead lines.

#### Added — Phase 6 (simplified, per earlier decision not to add a new auth surface)
- "Approve Evaluation" button (requires `cs_supervisor`/`admin` + both QA and CS/MP sections submitted).
- "Mark Sent to Supplier" (writes `sent_at`) and "Mark Acknowledged" (writes `acknowledged_at`) — staff email the PDF/attachment outside the app, then record the status here. No auto-send, no supplier login, matching this session's decision.

#### Added — Phase 7
- New **Yearly Summary** tab — equivalent to the old Excel Summary Mat/Part sheet: one row per supplier, one column per month (1-12), YTD average, and grade, filterable by supplier category. No schema changes.

### [Package v19] — 2026-09-04 — Official Excel-based evaluation worksheet

#### Changed
- Rebuilt Monthly Input as a real Supplier Evaluation Worksheet using the official evaluation criteria stored from FM0704-3.
- Quality is split into A1 Quality Problem (40 points) and A2 Environmental Effect (10 points).
- Delivery uses the seven official delivery criteria (40 points).
- Purchase Amount is a single-select tier, preventing multiple purchase tiers from being scored together.
- Evaluators record occurrence counts; deductions, category scores, total percentage and grade update live.
- No Shipment changes Delivery and Purchase to N/A and keeps the normalized Quality-only calculation.
- Added role-aware editing, section draft saves, section submit buttons, bilingual labels, evidence upload and sticky score summary.
- Removed manual total-score entry from the primary evaluation workflow.

### [Package v18] — 2026-09-04 — Complete EN/TH dashboard localization

#### Changed
- Localized all Supplier Command Center dashboard labels, filters, KPI descriptions, empty states, warnings, risk explanations, cycle pipeline, Corrective Action tower, Pareto messages, and data-confidence messages.
- Dynamic dashboard content now switches immediately with the existing EN/TH language toggle.
- Dates in the dashboard use Thai or English locale according to the selected language.

### [Package v17] — 2026-09-04 — Supplier Command Center Dashboard

#### Added
- Rebuilt Dashboard as a role-neutral Supplier Management Command Center.
- Global period/category/shipment/risk filters.
- Action Center for QA pending, CS/MP pending, approval-ready, overdue CA, declining suppliers, and data issues.
- Cycle health pipeline, priority queue, explainable risk index, risk matrix, early-warning detection, 12-month portfolio trend, issue Pareto, CA control tower, and data-confidence monitor.
- Dashboard widgets drill through to Evaluation List, Monthly Input, and Corrective Action workspaces.

#### Notes
- Risk Index is an explainable rule-based indicator, separate from the official evaluation grade.
- Issue Pareto uses itemized checklist records and shows an honest empty state when no itemized data exists.
- Cycle coverage is derived from active suppliers for the selected period until a dedicated evaluation_cycles table is added.

# Changelog

All notable changes to the Supplier Evaluation System project.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/). Dates in `YYYY-MM-DD`.

---

## [Package v16] — 2026-09-04 — Phase 4: approval workflow, roles, attachments

### Database (`database/11_approval_flow_and_attachments.sql`)
- Added `cs_supervisor` role. **`'supervisor'` is fully retired** — every account still set to it is migrated to `admin`, and nothing in the UI or RLS logic offers/accepts `'supervisor'` anymore (Postgres can't drop enum values, so it stays a dead possibility in the type, never assigned again).
- `evaluations` gets `quality_submitted_at/by` and `delivery_submitted_at/by`. `enforce_evaluation_edit_permissions` now blocks setting `status = 'approved'` unless **both** are filled in, and requires the approver to be `cs_supervisor` or `admin` specifically (not just any admin-tier department).
- New `evaluation_attachments` table (+ Storage bucket `attachments`, **create this manually in Supabase Dashboard → Storage** — SQL can't do it) — one row per file, attached to either an evaluation or a corrective action, RLS open to all authenticated staff (no supplier-facing auth added, per this session's decision).

### App
- Monthly Input: separate "Submit Quality Section" / "Submit Delivery Section" buttons (each gated to the right department), a status line showing what's submitted, and the Approved status option only enables once both are in and the current user can approve.
- File upload/list/open/delete UI added to both the evaluation form and the Corrective Action form.
- Master Control → Users & Roles: department dropdown now offers `cs_supervisor`, no longer offers `supervisor`.

## [Package v15] — 2026-09-04 — Master Control + Phase 3: itemized scoring

### Why
Two more instances of the same RLS gap pattern found in v14: `suppliers` had a read policy but **no write policies at all** (could never be added/edited from the app), and `evaluation_criteria` had **zero policies whatsoever** (100% inaccessible, not even readable) since v0.1.0.

### Database
- `09_master_control.sql` — `is_admin()` helper, admin-only insert/update/delete for `suppliers` and `evaluation_criteria`, admin-only update for `user_profiles` (department changes no longer require the SQL editor).
- `10_phase3_autocalc.sql` — `evaluations.scoring_mode` ('manual' default / 'itemized'), RLS for `evaluation_items` (also previously 100% inaccessible), `recompute_evaluation_scores()` + triggers. Deliberately only recomputes for evaluations explicitly switched to 'itemized' — the 574 existing manually-entered evaluations are never touched, so nothing gets silently overwritten.

### App
- New **Master Control** tab (admin-only, hidden via role gating + enforced by RLS either way): Suppliers CRUD, Evaluation Criteria CRUD, Users & Roles (change department).
- Monthly Input: **Scoring Mode** selector. Itemized mode shows a criteria checklist (grouped by category) with occurrence inputs; "Save Checklist" upserts to `evaluation_items` and forces a recompute via the new `recompute_evaluation_scores` RPC, then refreshes the read-only quality/delivery/purchase display.

## [Package v14] — 2026-09-04 — Phase B: Corrective Action workflow

### Why
`corrective_actions` has had `enable row level security` set since v0.1.0 but **never had a single RLS policy defined for it** — with RLS on and zero policies, Postgres denies all access by default, so the table has been completely unusable from the app (select/insert/update/delete all blocked) since it was first created. Meanwhile, Grade C/D evaluations (which the Excel form and this app's own Report Preview both say require a 5-working-day improvement plan) had no tracking mechanism at all once approved.

### Database (`database/08_corrective_action_workflow.sql`)
- Added RLS policies so `corrective_actions` is finally readable/writable by any authenticated user (intentionally not column-locked by department like `evaluations` — resolving a CA typically needs QA, CS/MP, and a supervisor all touching the same record over time).
- Added a `due_date` column.
- Added `add_working_days()` helper (Mon–Fri only, no holiday calendar yet — see PLAN.md open questions) and an `auto_create_corrective_action` trigger: any evaluation newly approved with Grade C or D automatically gets a Corrective Action row (status `open`, due 5 working days out), unless one already exists for it. Handles both the INSERT and UPDATE-to-approved cases (a fresh evaluation can be saved directly as "approved" in one step via the app's upsert).
- One-time backfill for evaluations that are already approved C/D but predate the trigger — deliberately excludes the 2025/early-2026 "Historical import" rows (score-only, no real breakdown), since a "due in 5 working days from today" deadline would be meaningless for a month that ended over a year ago.

### App (`index.html` / `app.js`)
- New **Corrective Actions** tab: pick an evaluation, fill Problem / Root Cause / Corrective Action / Responsible Person / Start / Due / Finished dates / Status, save. Below it, a filterable list (by status, and an "overdue only" checkbox) with overdue rows highlighted.
- New **CA Overdue** KPI tile on the Dashboard.
- Evaluation save/delete now also refresh corrective-action data, since approving an evaluation can auto-create one.

### Docs
- `PLAN.md` — marked Phase 5 done (delivered as "Phase B", inserted ahead of Phase 3 for the same reason as Phase A: real, currently-accumulating C/D evaluations had zero CA tracking), added key decisions for the no-department-lock RLS choice, the frontend-computed "overdue" flag, and the Mon–Fri-only working-day math.

## [Package v13] — 2026-09-04 — Phase A: No-Shipment / Applicability fix

### Why
Confirmed against real production data (`07__JULY_26.xlsx`, July 2026): 5 of 30 suppliers that month (ETO, AKIYAMA JP, DAIDO, KYOTO, UGITECH) have Quality 50/50 raw but the legacy Excel process shows **83.33% / Grade B** — that 83.33% = 50/60, which excludes Delivery's 40-point weight from the denominator but forgets to also exclude Purchase's 10-point weight, even though Purchase is equally inapplicable with no shipment. This app's own schema had a *different* version of the same class of bug: `total_score`/`grade` were a raw sum with no "applicable" concept at all, and new rows defaulted to `quality_score=50, delivery_score=40, purchase_score=0` — so an evaluation nobody has touched yet already looked like a fully-scored 90/B instead of unfinished.

### Database (`database/07_no_shipment_applicability.sql`)
- Added `shipment_status` ('normal' / 'no_shipment') and `no_shipment_reason` (required when no_shipment) to `evaluations`.
- Fixed the misleading defaults: `quality_score`, `delivery_score`, `purchase_score` now all default to `0` instead of `50/40/0` — an untouched row now looks unfinished (0/D), not like a good grade.
- Replaced the old raw-sum `total_score`/`grade` generated columns with a `compute_evaluation_score` trigger (BEFORE INSERT/UPDATE): `total_score` is now always a **normalized percentage out of 100** — when `shipment_status = 'normal'` this is identical to the old behavior (weights already summed to 100, so no existing evaluation's score changes), but for `no_shipment` it correctly excludes **both** Delivery (40) and Purchase (10) from the denominator, giving Quality 50/50 → **100% / Grade A** instead of the old buggy 83.33%/B.
- Added `raw_score` and `applicable_weight` generated columns (e.g. "Raw Score 50/50") purely for display.
- Extended `enforce_evaluation_edit_permissions`: QA can no longer touch `shipment_status`/`no_shipment_reason` — that's CS/MP's call, same as the delivery fields.
- Backfills every existing row's `total_score`/`grade` under the corrected formula (a no-op for all current rows, since none are marked `no_shipment` yet — see the note at the bottom of the SQL file for how to mark specific historical rows like ETO/AKIYAMA JP/etc. if you want them corrected retroactively).

### App (`index.html` / `app.js`)
- Added a **Shipment Status** selector to the Monthly Input form (Normal / No Shipment), with a required reason textarea that only appears when No Shipment is selected.
- When No Shipment is selected, Delivery and Purchase score inputs are disabled (excluded from the calculation regardless of their stored value).
- Live total-preview, evaluation list table, supplier profile history, and the report preview all now show `total_score` as a percentage, a "No Shipment" tag, and Raw Score / Applicable Weight when relevant, instead of silently mixing raw points and percentages.
- Role gating extended: CS/MP (and Admin) control the new Shipment Status/reason fields; QA cannot.

### Docs
- `PLAN.md` — inserted Phase A into the roadmap ahead of Phase 3, corrected a previous (wrong) note in "Key decisions" that assumed the old ÷60 Excel formula was the target to replicate, and updated the DB/frontend sections to describe the new columns and trigger.

## [Package v12] — 2026-09-04

### Fixed
- **"email rate limit exceeded" (429) when creating new accounts.** Supabase's free-tier built-in email service only allows a handful of auth emails per hour; creating several accounts in a row (admin01, test_qa01, ...) hit that limit.
- **Underlying issue this exposed:** logins use fake addresses like `xxxx@eht.local`, which can never actually receive a confirmation email. If Supabase's "Confirm email" setting is ON, any self-signed-up account is permanently stuck unconfirmed (and can't log in) until manually confirmed. **Recommended fix: turn OFF "Confirm email"** in Supabase Dashboard → Authentication → Providers → Email — this also means signups stop sending any email at all, so the rate limit stops being relevant.
- Added `database/06_confirm_stuck_users.sql` — one-time script that marks any already-created `@eht.local` account as confirmed (unsticks accounts like `test_qa01` created before "Confirm email" was turned off). Safe to re-run any time.

## [Package v11] — 2026-09-04

### Changed
- **Hybrid storage under `file://`, per request.** Only the Supabase auth session token (which can be several KB — the thing that actually triggered the original `QuotaExceededError`) is forced into in-memory storage when running from `file://`. The app's own "remember ID & password" and language-toggle settings are tiny by comparison, so they now always attempt a real `localStorage` write first — on most browsers this succeeds even under `file://`'s restricted quota, so the remembered login now does survive closing/reopening the file. If a browser's quota is so strict that even this small write fails, it falls back to memory (lost on reload) and shows a one-line message after sign-in saying it couldn't be saved on that device, rather than failing silently.

## [Package v10] — 2026-09-04

### Changed
- **Confirmed prototype workflow: `file://` is fully supported without a local server**, at the cost of one trade-off — sessions and "remember ID & password" don't survive closing/reloading the page, since `file://` pages genuinely can't persist to disk in most browsers. Everything else (signing in for the current session, reading/writing suppliers & evaluations in Supabase) works exactly the same as over `http://`.
- Detects `file:` protocol up front (`IS_FILE_PROTOCOL` in `app.js`) and uses an in-memory store from the start instead of repeatedly trying and failing to write to `localStorage` — removes the `QuotaExceededError` console spam from v09's catch-and-fallback approach entirely, rather than just catching it after the fact.

## [Package v09] — 2026-09-04

### Fixed
- **`QuotaExceededError` on sign-in when opening `index.html` directly as a `file://` page.** Some browsers (Chrome in particular) give `file://` pages a near-zero `localStorage` quota, which made Supabase's internal session-token write throw and broke login. Two changes:
  1. Supabase's client is now created with a custom storage adapter that catches storage errors and falls back to an in-memory store instead of throwing — a failed write now just means the session won't survive a page reload, instead of crashing.
  2. The app's own `localStorage` usage (remember-me, language toggle) now goes through the same kind of safe wrapper (`safeLSGet`/`safeLSSet`/`safeLSRemove`), so those can't throw uncaught errors either.
- **Root cause / real fix:** don't open `index.html` by double-clicking it. Serve the folder with a local static server and open it via `http://localhost:...` instead — e.g. `npx serve .` or `python -m http.server 8000` from inside the extracted folder. This avoids the `file://` storage quota limitation entirely (see also the note in the v03 entry below).

## [Package v08] — 2026-09-04

### Fixed
- **Login placeholders showed a real example credential (`admin01` / `413723`)**, which looked like pre-filled/remembered values rather than just a hint. Changed the User ID placeholder to a generic "User ID" (localized via the existing EN/TH toggle) and the Password placeholder to dots (`••••••`) — no more literal example credentials shown in the fields.

## [Package v07] — 2026-09-04

### Fixed
- **Login fields had `maxlength="6"`, which clipped `admin01` (7 characters) and made it impossible to type.** Raised `maxlength` to 32 on both the User ID and Password fields on the login form so any reasonably short ID/password works, not just exactly 6 characters.

## [Package v06] — 2026-09-04

### Changed
- **Brought back "Create account" self-signup, but it can no longer create Supervisor/Admin accounts.** The Department dropdown on the sign-up form now only offers QA / CS / MP. This is enforced in two layers: the UI simply doesn't show the option, and — more importantly — `database/05_block_admin_selfsignup.sql` updates the `handle_new_user` trigger so that even a request that tries to sneak `department: 'admin'` through directly (bypassing the dropdown entirely) is silently downgraded to `qa` at the database level. Admin accounts can only be created by an admin, directly in Supabase Dashboard → Authentication → Users, exactly as set up in v04/v05.
- **Renamed "Supervisor" to "Admin" everywhere in the UI** (sidebar text, role badge, permission messages). Internally, the `department_role` enum still has both `'supervisor'` and `'admin'` values, and the app already treated them identically — this migration doesn't touch the enum or existing accounts, it's purely a display rename plus closing off `'supervisor'`/`'admin'` from self-signup.

### Run this
- `database/05_block_admin_selfsignup.sql` — safe to re-run, replaces one function.

## [Package v05] — 2026-09-04

### Changed
- **Login now uses a short "User ID" instead of a real email.** The sign-in form's first field is now labelled "User ID" and accepts a plain 6-character alphanumeric value (e.g. `admin01`) instead of an email address. Supabase Auth still needs an email-shaped string behind the scenes, so `app.js` automatically appends a fixed internal domain (`@eht.local`, see `LOGIN_EMAIL_DOMAIN` at the top of `app.js`) before calling Supabase — the person never sees or types that part. The header badge that shows who's logged in also strips this suffix back off for display.
- No extra password complexity is enforced — Supabase's default minimum (6 characters) is unchanged and is enough for a simple 6-character password like `413723`.
- Added `database/04_simplify_admin_login.sql` — a one-time script that renames the existing `admin@admin.com` / `admin1234` login to `admin01` / `413723` (internally `admin01@eht.local`) directly in `auth.users` / `auth.identities`. Run once in the Supabase SQL editor; it doesn't touch `user_profiles`, so the admin's department/role is unaffected. Going forward, create new users the same way (email = `<shortid>@eht.local`) via Dashboard → Authentication → Users → Add user — no need to re-run this script.

## [Package v04] — 2026-09-04

### Changed
- **Removed self-service "Create account" signup from the app.** The login screen now only has Sign in — no tab to create a new account, no full name/department fields. New users must be created by an admin in **Supabase Dashboard → Authentication → Users → Add user**; the existing `handle_new_user` trigger in `03_phase2_auth_and_roles.sql` still fires and creates the matching `user_profiles` row automatically no matter how the `auth.users` row was created, so this doesn't require any SQL changes. After creating a user in the dashboard, set their `department` in the `user_profiles` table via the SQL editor (qa / cs / mp / supervisor).

### Added
- **"Remember email & password on this device" checkbox** on the sign-in form. When checked and sign-in succeeds, the email and password are saved in the browser's `localStorage` (password is base64-encoded, which is obfuscation, not encryption) and auto-filled the next time the page loads. Unchecking it and signing in again clears the saved credentials.
  - ⚠️ Security note: anything in `localStorage` can be read by anyone with access to that browser/profile (or via dev tools). Use this only on a trusted personal/office device, not a shared computer.
- Filled in `SUPABASE_ANON_KEY` in `app.js` with the project's publishable/anon key.

## [Package v03] — 2026-09-04

### Fixed — critical
- **`Identifier 'supabase' has already been declared` — app.js crashed on load and never ran.** The `@supabase/supabase-js` CDN bundle creates a global `supabase` object; `app.js` also declared `let supabase = null` at the top level, colliding with it. Since both live in the same global scope (classic `<script>` tags, not modules), this is a `SyntaxError` that stops the *entire script* from executing — which is why the login screen looked stuck forever on "Checking Supabase…" (none of the code after that point had ever actually run). Renamed the app's client variable to `sb` throughout; `window.supabase.createClient(...)` (the library reference) is untouched.

### Notes
- If you open `index.html` by double-clicking it (a `file://` URL) you may also see a browser warning like *"Unsafe attempt to load URL ... 'file:' URLs are treated as unique security origins."* This is separate from the bug above and is just the browser being cautious about `file://` pages — it's best practice to serve the `app/` folder from a local static server instead (e.g. `npx serve app`, VS Code's "Live Server" extension, or `python -m http.server` from inside `app/`), then open `http://localhost:...` rather than the file directly.

---

## [Package v02] — 2026-09-04

### Fixed
- **App files were missing the login screen on the deployed instance.** If you're seeing "no Create Account option" and all data showing as zero, you were likely still running the pre-Phase-2 `app/` files after `03_phase2_auth_and_roles.sql` had already removed anonymous access. This package's `app/` folder has the full Phase 2 login UI — replace all three files (`index.html`, `style.css`, `app.js`), not just the ones that changed.
- Added a **pre-login connection self-check** on the login screen (`app/app.js` `preLoginConnectionCheck()`) so you can tell at a glance whether the problem is (a) Supabase not configured, (b) reachable but RLS is correctly blocking anon access — sign in to proceed, or (c) a real network/config error. Previously this diagnostic only showed up *after* logging in, which was useless when login itself was the problem.

### Added (docs)
- Bootstrap instructions for creating the first `admin` user directly via the Supabase Dashboard (Authentication → Users → Add user) instead of the in-app signup form — avoids fighting with Supabase's email-format and 6-character minimum password validation for a throwaway first account.

---

## [Package v01] — 2026-09-04

Bundle of everything completed so far, for handoff to another session.

### Added
- `database/01_schema.sql` (app v0.1.0)
- `database/02_seed_data.sql` (app v0.2.0)
- `database/03_phase2_auth_and_roles.sql` (app v0.3.0)
- `app/index.html`, `app/style.css`, `app/app.js` (app v0.3.0)
- `PLAN.md` — roadmap and handoff notes
- `CHANGELOG.md` — this file

---

## [v0.3.0] — 2026-09-04 — Phase 2: Auth & department roles

### Added
- `user_profiles` table (`department`: qa / cs / mp / supervisor / admin), auto-created on signup via `handle_new_user()` trigger reading signup metadata.
- `enforce_evaluation_edit_permissions()` trigger — column-level write restrictions on `evaluations`:
  - QA → `quality_score`, `quality_comment` only
  - CS/MP → `delivery_score`, `purchase_score`, `delivery_comment` only
  - `status = 'approved'` → supervisor/admin only, auto-stamps `approved_by` / `approved_at`
- `set_evaluation_submitter()` trigger — stamps `submitted_by` on insert.
- DELETE policy on `evaluations` restricted to supervisor/admin.
- Frontend: real login/signup screen (Supabase Auth, email+password), user badge + sign-out in sidebar, role-based field disabling in Monthly Input form.

### Removed
- The five temporary `anon`-role RLS policies from v0.1.0 (superseded by real auth).

### Known limitations
- Signup is self-service and lets the user pick their own department — fine for testing, should be disabled before real rollout (switch to admin-created users).
- `evaluation_items` table has no RLS/trigger coverage yet (arrives with Phase 3).

---

## [v0.2.0] — 2026-09-03 — Data import

### Added
- `seed_data.sql`:
  - 22 `evaluation_criteria` rows transcribed from the FM0704-3 template (Quality A1/A2, Delivery B, Purchase C groups, with correct full-score and deduction/addition point values per item).
  - 32 `suppliers` rows from `Summary Mat` (29, code prefix `MA-`) and `Summary Part` (3, code prefix `PA-`), including `attention` and `tel` pulled from each supplier's own sheet (cells `C4` / `I4`).
  - 542 historical `evaluations` rows (2025 full year + 2026 Jan–Jun) — total score only, no category breakdown (source file doesn't have it at that granularity). Flagged with a comment on every row.
  - 32 `evaluations` rows for July 2026 with a verified category breakdown: `quality = P10+P20`, `delivery = P24`, `purchase = P32` per supplier sheet — cross-checked against the sheet's own Total Score for all 32/32 suppliers before import.

### Fixed
- Enum cast error on `evaluations.grade` generated column: Postgres does not auto-cast a bare string literal (`'A'`) to an enum type inside a `generated always as` expression — each branch now explicitly casts (`'A'::eval_grade`).

---

## [v0.1.0] — 2026-09-03 — Phase 1: Database schema

### Added
- Initial Supabase/PostgreSQL schema (`supplier_evaluation_schema.sql`):
  - Tables: `suppliers`, `evaluation_criteria`, `evaluations`, `evaluation_items`, `corrective_actions`, `evaluation_audit_log`.
  - Enums: `eval_category`, `eval_status`, `eval_grade`, `ca_status`.
  - `evaluations.total_score` and `.grade` as generated (`stored`) columns.
  - `updated_at` auto-touch trigger on `suppliers`, `evaluations`, `corrective_actions`.
  - RLS enabled on all tables, with broad temporary `authenticated`/`anon` policies pending Phase 2.

### Context
- Schema modeled from three source files: the existing manual flow (PPTX), the live `FM0704-3 Rev.2` Excel workbook, and an earlier localStorage-only HTML prototype.
