/* ============================================================
   Supabase connection
   Fill these in with your project's values, then reload the page.
   Settings → API in your Supabase project dashboard.
   ============================================================ */
const SUPABASE_URL = (window.APP_CONFIG && window.APP_CONFIG.SUPABASE_URL) || 'https://YOUR-PROJECT.supabase.co'; // set in config.js
const SUPABASE_ANON_KEY = (window.APP_CONFIG && window.APP_CONFIG.SUPABASE_ANON_KEY) || 'YOUR-ANON-KEY'; // set in config.js

// Bump this whenever a new migration is added that this app.js version
// depends on (matches the `version` column set by the last-numbered
// migration file — see database/25_schema_version.sql). Checked once
// on login via checkSchemaVersion(); a mismatch blocks the app shell
// with a clear message instead of loading and failing confusingly on
// whichever feature happens to touch the missing piece first.
const REQUIRED_SCHEMA_VERSION = 25;

/* Opening this file directly as file:// (instead of via a local server)
   gives localStorage a near-zero quota in most browsers, which throws
   QuotaExceededError on every write. Rather than hit that error
   repeatedly, we detect file:// up front and just use an in-memory
   store for the whole page load — this is a deliberate prototype
   trade-off: signing in works normally, but the session won't survive
   a reload/close, since nothing can actually be saved to disk under
   file://. Serving over http://localhost instead avoids this trade-off
   entirely (see CHANGELOG), but is not required for this to work. */
const IS_FILE_PROTOCOL = window.location.protocol === 'file:';

function createResilientStorage(){
  const mem = {};
  if (IS_FILE_PROTOCOL) {
    return {
      getItem: (key) => (key in mem) ? mem[key] : null,
      setItem: (key, value) => { mem[key] = value; },
      removeItem: (key) => { delete mem[key]; }
    };
  }
  return {
    getItem: (key) => {
      try { return window.localStorage.getItem(key); } catch (e) { return (key in mem) ? mem[key] : null; }
    },
    setItem: (key, value) => {
      try { window.localStorage.setItem(key, value); } catch (e) { mem[key] = value; }
    },
    removeItem: (key) => {
      try { window.localStorage.removeItem(key); } catch (e) { delete mem[key]; }
    }
  };
}

// ------------------------------------------------------------
// Global "working…" indicator — shows a small hourglass badge for as
// long as any network request from this page is in flight, so any
// button click (Save, Approve, Reject, delete, upload, login, ...)
// gives immediate visual feedback that it registered instead of
// looking like nothing happened while it waits on Supabase. Patching
// window.fetch here (before the Supabase client is created below,
// which is what actually issues the requests) catches every REST,
// RPC, Storage and Auth call the app makes without having to wire up
// each button individually — a counter handles overlapping requests
// so the badge only hides once the last one finishes. The big
// full-page #loadingOverlay (initial data load) already gives its own
// feedback, so this stays out of the way while that's showing.
let busyRequestCount = 0;
function showBusyIndicator(){
  busyRequestCount++;
  const el = document.getElementById('busyIndicator');
  const overlay = document.getElementById('loadingOverlay');
  const overlayVisible = !!overlay && overlay.style.display !== 'none' && overlay.style.display !== '';
  if (el && !overlayVisible) el.style.display = 'flex';
}
function hideBusyIndicator(){
  busyRequestCount = Math.max(0, busyRequestCount - 1);
  if (busyRequestCount === 0) {
    const el = document.getElementById('busyIndicator');
    if (el) el.style.display = 'none';
  }
}
(function instrumentFetchForBusyIndicator(){
  if (typeof window.fetch !== 'function') return;
  const originalFetch = window.fetch.bind(window);
  window.fetch = async function(...args){
    showBusyIndicator();
    try {
      return await originalFetch(...args);
    } finally {
      hideBusyIndicator();
    }
  };
})();

let sb = null;
try {
  sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      storage: createResilientStorage(), persistSession: true,
      // supabase-js normally coordinates session refresh across tabs of
      // the same origin using the browser's Web Locks API. Every file://
      // tab counts as the same origin, so multiple tabs of this file end
      // up contending for one shared lock even though each tab's session
      // here is already independent (see createResilientStorage — file://
      // falls back to in-memory storage per tab, nothing is actually
      // shared). A tab holding that lock (e.g. while backgrounded/
      // throttled) leaves any other tab waiting on it stuck loading
      // forever. There's nothing real to protect per tab here, so skip
      // the lock entirely and let each tab run its own auth calls
      // immediately.
      lock: async (_name, _acquireTimeout, fn) => await fn(),
    }
  });
} catch (e) {
  console.error('Could not create Supabase client', e);
}

/* Supabase Auth needs an email-shaped address internally. Users only type a
   short ID (e.g. "admin01") in the login form; this suffix is appended
   automatically. Change this if you use a different internal domain. */
const LOGIN_EMAIL_DOMAIN = '@eht.local';
function idToLoginEmail(idOrEmail){
  return idOrEmail.includes('@') ? idOrEmail : idOrEmail + LOGIN_EMAIL_DOMAIN;
}

/* ============================================================
   State
   ============================================================ */
// Unlike the Supabase auth token (which can be several KB and is the main
// thing that blows the near-zero file:// quota, see IS_FILE_PROTOCOL
// above), our own keys here are tiny (a short ID + password, or a 2-letter
// language code) — small enough to often still fit even under a very
// restrictive file:// quota. So these always try a real localStorage
// write first, and only fall back to memory (lost on reload) if that
// specific write actually fails.
const _memLS = {};
function safeLSGet(key){
  try { return window.localStorage.getItem(key); } catch (e) { return (key in _memLS) ? _memLS[key] : null; }
}
function safeLSSet(key, value){
  try { window.localStorage.setItem(key, value); return true; } catch (e) { _memLS[key] = value; return false; }
}
function safeLSRemove(key){
  try { window.localStorage.removeItem(key); } catch (e) { delete _memLS[key]; }
}

let lang = safeLSGet('se_lang') || 'th';
let suppliers = [];     // [{id, code, name, short_name, attention, tel}]
let evaluations = [];   // [{...evaluation row, supplier:{...}}]
let correctiveActions = []; // [{...ca row, evaluation:{...evaluation, supplier:{...}}}]
let evaluationCriteria = []; // master list — [{id, category, item_no, description, full_score, deduction_points, display_order, is_active}]
let allSuppliers = [];   // all suppliers incl. inactive, for Master Control (vs `suppliers` = active-only, for pickers)
let userProfilesList = []; // [{id, full_name, department, created_at}] for Master Control
let permissionRules = []; // [{rule_key, department, allowed}] — the whole table, all departments
let holidays = []; // [{id, holiday_date, name, name_th}] for Master Control -> Holidays
let allEvaluationItems = []; // [{evaluation_id, criteria_id, occurrence}] — every itemized evaluation's items, for the Q/E split column in the list table
let translationOverrides = {}; // { [data-i18n key]: {th_text, en_text} } — admin-managed, see Setting -> Translation
let currentEditingEvalId = null; // set when editing an existing evaluation, needed for the itemized checklist
let evaluationItemsCache = []; // loaded on-demand when editing an itemized evaluation
const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

let currentUser = null;      // { id, email }
let currentProfile = null;   // { full_name, department }

/* ============================================================
   i18n
   ============================================================ */
const TH = {
  appTitle:'ระบบประเมิน Supplier', appSub:'อี แอนด์ เอช พรีซิชั่น (ไทยแลนด์)',
  dashboard:'แดชบอร์ด', monthlyInput:'กรอกข้อมูลรายเดือน', evalList:'รายการผลประเมิน',
  supplierProfile:'โปรไฟล์ Supplier', reportPreview:'รายงาน', setting:'ตั้งค่า / สถานะ',
  reportSingleTab:'ดูรายตัว',
  connChecking:'กำลังเชื่อมต่อ Supabase…',
  totalEvals:'จำนวนผลประเมินที่แสดง', avgScore:'คะแนนเฉลี่ย', gradeA:'เกรด A', gradeB:'เกรด B',
  gradeCD:'เกรด C / D', belowTarget:'ต่ำกว่าเป้าหมาย (<80)',
  scoreRanking:'อันดับคะแนน', gradeDist:'สัดส่วนเกรด', riskList:'Supplier ที่ต้องติดตาม',
  monthlyInputTitle:'กรอกผลประเมินรายเดือน',
  inputHint:'คะแนนจะถูกบันทึกเข้า Supabase โดยตรง ผลรวมและเกรดคำนวณโดยฐานข้อมูล',
  supplier:'Supplier', year:'ปี', month:'เดือน', status:'สถานะ',
  st_draft:'ร่าง', st_submitted:'ส่งแล้ว', st_approved:'อนุมัติแล้ว',
  st_sup_approved:'Supervisor อนุมัติแล้ว', st_mgr_approved:'Manager อนุมัติแล้ว (อนุมัติสมบูรณ์)',
  st_sent:'ส่งให้ Supplier แล้ว', st_ack:'ปิดเคส', st_followup:'ต้องติดตาม',
  qualityScore:'คะแนนคุณภาพ /50', deliveryScore:'คะแนนจัดส่ง /40', purchaseScore:'คะแนนยอดซื้อ /10',
  totalScore:'คะแนนรวม (ตัวอย่าง)',
  qualityComment:'หมายเหตุคุณภาพ', deliveryComment:'หมายเหตุการจัดส่ง',
  shipmentStatus:'สถานะการจัดส่ง', shipmentNormal:'ปกติ (มี Shipment/ยอดซื้อ)', shipmentNone:'No Shipment เดือนนี้',
  noShipReason:'เหตุผลที่ No Shipment (จำเป็นต้องกรอก)', noShipReasonRequired:'กรุณากรอกเหตุผลที่ No Shipment',
  rawScoreLabel:'คะแนนดิบ',
  saveEval:'บันทึกผลประเมิน', resetForm:'ล้างฟอร์ม',
  mockAttach:'แนบไฟล์ — จะเปิดใช้งานใน Phase 6',
  filterTextPh:'ค้นหา Supplier / รหัส / หมายเหตุ', filterYearPh:'ปี', filterOpenOnly:'แสดงเฉพาะเคสที่ยังเปิดอยู่', filterHasCaOnly:'เฉพาะที่มี Corrective Action',
  allGrades:'ทุกเกรด', allStatus:'ทุกสถานะ', allMonths:'ทุกเดือน', refresh:'รีเฟรช',
  wf_wait_both:'รอ QA และ MP/CS', wf_wait_cs:'รอ MP/CS', wf_wait_qa:'รอ QA', wf_wait_sup:'รอ Supervisor',
  wf_wait_mgr:'รอ Manager', wf_wait_send:'รอส่ง Sup', wf_wait_ca:'รอ CA', wf_closed:'ปิดเคส',
  selectSupplier:'เลือก Supplier', profileGroupLabel:'กลุ่ม (ตาม Code)', trend:'แนวโน้ม 12 เดือน', selectEval:'เลือกผลประเมิน',
  profileOverviewTab:'ภาพรวม', profileEvalTab:'ผลประเมิน', profileAuditTab:'Audit', profileContactsTab:'เอกสาร/ผู้ติดต่อ', profileEvalHistory:'ประวัติการประเมิน',
  mockPreviewTitle:'ตัวอย่าง — ยังไม่ใช่ฟีเจอร์ที่ใช้งานได้จริง',
  mockAuditHint:'แนวคิดสำหรับระบบ Supplier Audit ในอนาคต (FM-0704-5, 20 หมวด) ข้อมูลตัวอย่างด้านล่างเพื่อให้เห็นภาพเฉยๆ ไม่ใช่ข้อมูลจริงและไม่ถูกบันทึก',
  mockAuditDate:'วันที่', mockAuditor:'ผู้ตรวจ', mockAuditScore:'คะแนน', mockAuditGrade:'เกรด',
  mockAuditMore:'(แถวตัวอย่างเท่านั้น — ประวัติ Audit จริงจะแสดงที่นี่เมื่อระบบนี้ถูกสร้างขึ้นจริง)',
  mockContactsHint:'แนวคิดสำหรับระบบเก็บผู้ติดต่อหลายคนและใบรับรอง (ISO/CQI พร้อมวันหมดอายุ) อ้างอิงจาก Approved Supplier List จริง ข้อมูลตัวอย่างด้านล่าง ไม่ใช่ข้อมูลจริงและไม่ถูกบันทึก',
  mockContactName:'ชื่อ', mockContactRole:'ตำแหน่ง', mockCerts:'ใบรับรอง', mockCertStandard:'มาตรฐาน', mockCertExpiry:'ใช้ได้ถึง', mockSample:'(ตัวอย่าง)',
  printPdf:'พิมพ์ / บันทึกเป็น PDF',
  working:'สิ่งที่ใช้งานได้แล้วในเฟสนี้', nextStep:'ยังไม่ทำ — เฟสถัดไป',
  w1:'อ่าน/เขียนข้อมูล Supabase แบบ real-time (suppliers, evaluations)',
  w2:'คะแนนรวมและเกรดคำนวณโดยฐานข้อมูล',
  w3:'KPI และกราฟบนแดชบอร์ดใช้ข้อมูลจริง',
  w4:'โปรไฟล์ Supplier พร้อมแนวโน้ม 12 เดือน',
  w5:'สลับภาษา EN / TH',
  n1:'ระบบ Login และสิทธิ์ตามแผนก (Phase 2)',
  n1:'ส่งอีเมล/PDF อัตโนมัติเต็มรูปแบบ หรือพอร์ทัลให้ Supplier รับทราบเอง — ตอนนี้: staff แนบไฟล์ PDF แล้วกดปุ่ม Mark Sent แล้วปิดเคสอัตโนมัติ (เกรด A/B) หรือปิดผ่าน Corrective Action (เกรด C/D)',
  n2:'เริ่ม Pilot ใช้งานแทน Excel (Phase 8 — งานกระบวนการ ไม่ใช่โค้ด)',
  n3:'ตัวเลขความครอบคลุมของรอบใน Dashboard ยังคำนวณจาก evaluations ตรงๆ ยังไม่ได้อ่านจาก evaluation_cycles',
  connSetup:'การเชื่อมต่อ Supabase', connHint:'ใส่ Project URL และ anon key ที่ด้านบนของ app.js แล้วโหลดหน้านี้ใหม่',
  rlsHint:'อย่าลืมรันไฟล์ phase2_auth_and_roles.sql ใน Supabase SQL editor ด้วย ไม่งั้นระบบ Login และสิทธิ์ตามแผนกจะยังไม่ทำงาน',
  noData:'ไม่พบข้อมูล', notConfigured:'ยังไม่ได้ตั้งค่า Supabase',
  connOk:'เชื่อมต่อ Supabase แล้ว', connFail:'เชื่อมต่อไม่สำเร็จ — ดูแท็บ Setup & Status',
  w6:'เข้าสู่ระบบด้วยอีเมล/รหัสผ่าน (Supabase Auth)',
  w7:'สิทธิ์ตามแผนก — QA / CS / MP / CS Supervisor / Admin',
  w8:'ระบบ checklist คำนวณคะแนนอัตโนมัติ (Official Worksheet)',
  w9:'Workflow Submit → Approve, Corrective Action, ไฟล์แนบ',
  w10:'สิทธิ์ปรับได้จริงจากหน้าเว็บ (Master Control → Permissions)',
  w11:'เปิดรอบประเมินประจำเดือนให้ทุก Supplier พร้อมกันได้ในคลิกเดียว',
  signIn:'เข้าสู่ระบบ', signUp:'สร้างบัญชีใหม่', userId:'รหัสผู้ใช้', password:'รหัสผ่าน',
  rememberMe:'จำรหัสผู้ใช้ไว้ในเครื่องนี้',
  rememberFailed:'เข้าสู่ระบบสำเร็จ แต่เบราว์เซอร์นี้ไม่อนุญาตให้บันทึกรหัสผู้ใช้ไว้ในเครื่อง',
  fullName:'ชื่อ-นามสกุล', department:'แผนก', signOut:'ออกจากระบบ',
  authErrFields:'กรุณากรอกรหัสผู้ใช้และรหัสผ่าน',
  authSignupOk:'สร้างบัญชีสำเร็จ — ถ้าเปิดใช้ Confirm Email ไว้ ให้เช็คอีเมลก่อนเข้าสู่ระบบ',
  authSigninOk:'เข้าสู่ระบบสำเร็จ — กำลังโหลดข้อมูล…',
  signupDisabled:'ปิดการสมัครสมาชิกเองไว้ชั่วคราว — ติดต่อ Admin ให้สร้างบัญชีให้',
  noProfile:'ไม่พบข้อมูลแผนกของผู้ใช้นี้ — ติดต่อผู้ดูแลระบบ',
  caTab:'Corrective Action', caHint:'ผลประเมินเกรด C/D จะสร้างรายการ Corrective Action ให้อัตโนมัติ (ครบกำหนด 5 วันทำการหลังอนุมัติ) หรือจะเพิ่มเองก็ได้',
  caEvalPick:'เลือกผลประเมิน', caProblem:'ปัญหา', caRootCause:'สาเหตุที่แท้จริง', caAction:'มาตรการแก้ไข',
  caResponsible:'ผู้รับผิดชอบ', caStartDate:'วันที่เริ่ม', caDueDate:'วันครบกำหนด', caFinishedDate:'วันที่เสร็จสิ้น',
  caStatus:'สถานะ', ca_st_open:'เปิด', ca_st_progress:'กำลังดำเนินการ', ca_st_closed:'ปิดแล้ว', ca_st_overdue:'เกินกำหนด (ตั้งเอง)',
  caSave:'บันทึก Corrective Action', caReset:'ล้างฟอร์ม', caListTitle:'รายการ Corrective Action',
  caMarkReceived:'Mark Received Countermeasure (ปิดเคส)',
  caNew:'+ สร้าง Corrective Action ใหม่', backToList:'← กลับไปที่รายการ', backToEvalList:'← กลับไปที่รายการผลประเมิน', btnNewEvaluation:'+ เปิดรายการประเมินใหม่', caAddSet:'+ เพิ่มปัญหาอีกรายการ', caShowAllGrades:'แสดงทุกเกรด (ค่าเริ่มต้น: เฉพาะเกรด C/D)',
  caOverdueOnly:'เฉพาะที่เกินกำหนด', caOverdueKpi:'CA เกินกำหนด',
  scoringMode:'วิธีให้คะแนน', scoringManual:'กรอกเอง (Manual)', scoringItemized:'ติ๊กรายการ (คำนวณอัตโนมัติ)',
  itemizedNeedsSave:'บันทึกผลประเมินครั้งแรกก่อน (โหมด Manual ก็ได้) แล้วค่อยเปลี่ยนเป็น Itemized — checklist ต้องผูกกับผลประเมินที่มีอยู่แล้ว',
  itemizedChecklist:'รายการตรวจ (Checklist)', itemizedHint:'กรอกจำนวนครั้งที่เกิดแต่ละรายการในเดือนนี้ คะแนนด้านบนจะคำนวณใหม่อัตโนมัติหลังบันทึก',
  saveItems:'บันทึก Checklist',
  masterControl:'Master Control', masterHint:'จัดการ Supplier, หัวข้อประเมิน, และสิทธิ์ผู้ใช้ — เฉพาะ Admin เท่านั้น (บังคับโดยฐานข้อมูล ไม่ใช่แค่หน้าจอนี้)',
  mSuppliers:'Supplier', mCriteria:'หัวข้อประเมิน', mUsers:'ผู้ใช้ & สิทธิ์',
  mCode:'รหัส', mName:'ชื่อ', mShortName:'ชื่อย่อ', mCategory:'กลุ่ม', mCategoryAutoHint:'ระบบตรวจจากรหัสอัตโนมัติ (MA-/OS-/PA-) — แก้เองไม่ได้', mAttention:'ผู้ติดต่อ', mTel:'เบอร์โทร', mEmail:'อีเมล',
  mTargetScore:'คะแนนเป้าหมาย', mIsActive:'ใช้งานอยู่', mSave:'บันทึก', mClear:'ล้างฟอร์ม',
  mCriteriaCategory:'หมวด', mItemNo:'รหัสข้อ', mDescription:'คำอธิบาย (EN)', mDescriptionTh:'คำอธิบาย (TH)', mFullScore:'คะแนนเต็ม (เฉพาะแถวหัวข้อหลัก)',
  mDeduction:'คะแนนหัก/เครดิตต่อครั้ง', mDisplayOrder:'ลำดับแสดงผล',
  mUsersHint:'สร้างบัญชีใหม่ได้ด้านล่าง หรือเปลี่ยนแผนก/สิทธิ์ของผู้ใช้เดิมได้ในตาราง',
  mNewUserId:'User ID', mNewUserPassword:'รหัสผ่านชั่วคราว', mNewUserName:'ชื่อ-นามสกุล', mNewUserDept:'แผนก', mCreateUser:'สร้างบัญชี',
  mPermissions:'สิทธิ์การใช้งาน', mPermissionsHint:'ติ๊ก/ปลดติ๊กเพื่อเปลี่ยนสิทธิ์ของแผนกนั้นได้ทันที — มีผลจริงที่ฐานข้อมูล ไม่ใช่แค่หน้าจอนี้ ระวัง: ถ้าปลดสิทธิ์ของแผนกตัวเองออก อาจล็อกตัวเองไม่ให้ทำ action นั้นได้จนกว่า admin คนอื่นจะเปิดคืนให้',
  mHolidays:'วันหยุด', mHolidaysHint:'ไม่นับรวมในการคำนวณ "5 วันทำการ" ของ Corrective Action (นอกจากเสาร์-อาทิตย์) — ปี 2026 ใส่วันหยุดราชการไทยไว้ให้แล้ว เพิ่มเองได้ (วันหยุดบริษัท, ปีถัดไป)',
  mHolidayDate:'วันที่',
  mActivityLog:'บันทึกการใช้งาน', mActivityLogHint:'ทุกคนดูได้ เฉพาะ Admin ที่ย้อนคืนได้ — ย้อนได้แค่การสร้าง/ลบ และการแก้ไขที่ไม่ได้เปลี่ยนสถานะ Workflow (Submit/Approve/Reject/ปิดเคส เห็นในนี้แต่ย้อนคืนไม่ได้)',
  settingStatusTab:'ตั้งค่า / สถานะ',
  translationTab:'คำแปล', translationHint:'ปรับคำที่แสดงในแอปได้เอง ทั้งภาษาไทยและอังกฤษ — เหมาะกับคำทับศัพท์ที่อยากสะกดแบบเฉพาะ เฉพาะ Admin เท่านั้น เว้นช่องไหนว่างไว้ จะใช้คำ default ของแอปแทน',
  translationSaveAll:'บันทึกการเปลี่ยนแปลง', translationSearchPh:'ค้นหาในหมวดนี้…',
  importExport:'Import / Export',
  ieImportTitle:'Import จาก Excel', ieImportHint:'อัปโหลดไฟล์ FM0704-3 รายเดือน (เลือกได้หลายไฟล์) — ระบบจะอ่านทุก sheet ของ Supplier แล้วพยายามจับคู่กับ Supplier ที่มีอยู่ในระบบ ยังไม่บันทึกอะไรจนกว่าจะตรวจสอบหน้า preview แล้วกดยืนยัน',
  ieParse:'อ่านไฟล์', ieConfirmImport:'ยืนยัน Import',
  ieExportTitle:'Export เป็น Excel', ieExportHint:'การ Export ทำที่หน้ารายการผลประเมิน — ติ๊ก Supplier/เดือนที่ต้องการ (เฉพาะที่เป็น itemized เท่านั้นที่ export ได้) แล้วกด "Export ที่เลือก" ที่นั่น',
  goToListForExport:'ไปที่รายการผลประเมิน →',
  allTables:'ทุกตาราง', allActions:'ทุก Action', alInsert:'สร้าง', alUpdate:'แก้ไข', alDelete:'ลบ', alRevertableOnly:'เฉพาะที่ย้อนคืนได้',
  openCycleTitle:'เปิดรอบประเมินประจำเดือน', openCycleHint:'สร้างผลประเมินแบบร่างให้ทุก Supplier ที่ยังใช้งานอยู่และยังไม่มีรายการของเดือนนี้ ให้แต่ละแผนกเจอรายการรอกรอกทันที ไม่ต้องสร้างเองทีละบริษัท รันซ้ำได้ ไม่กระทบผลประเมินที่มีอยู่แล้ว',
  openCycleBtn:'เปิดรอบ',
  loadingTitle:'กำลังโหลดข้อมูล',
  actionBoardTitle:'ฉันต้องทำอะไรบ้าง', actionBoardHint:'แสดงเฉพาะสิ่งที่เกี่ยวกับบัญชีคุณตอนนี้ — กดรายการเพื่อเปิดได้เลย',
  actionColQa:'QA', actionColCsMp:'CS / MP', actionColSup:'Supervisor', actionColMgr:'Manager',
  submitQuality:'ส่งผลด้าน Quality', submitDelivery:'ส่งผลด้าน Delivery/Purchase',
  supApproveEval:'Supervisor Approve', mgrApproveEval:'Manager Approve', rejectEval:'Reject', markSent:'บันทึกว่าส่งผลแล้ว',
  yearlySummary:'สรุปรายปี', yearlySummaryHint:'เทียบเท่า Sheet Summary Mat/Part เดิม — หนึ่งแถวต่อ Supplier หนึ่งคอลัมน์ต่อเดือน พร้อมเฉลี่ย YTD และเกรด',
  allCategories:'ทุกหมวด', allSuppliers:'ทุก Supplier',
  attachTitle:'ไฟล์แนบ', attachUpload:'อัปโหลด', loadingBusy:'กำลังดำเนินการ…',
  cancel:'ยกเลิก', rejectModalTitle:'Reject ผลประเมิน', rejectModalHint:'เลือกฝั่งที่ต้องแก้ไขใหม่ แล้วระบุเหตุผล',
  rejectDeliveryLabel:'Delivery/Purchase', rejectReasonLabel:'เหตุผล (จำเป็นต้องกรอก)', rejectConfirm:'ยืนยัน Reject',
  submitPreviewTitle:'ยืนยันการส่งผล', submitPreviewHint:'ตรวจสอบสรุปก่อนส่งผลจริง', submitPreviewConfirm:'ยืนยัน & ส่งผล',
  noAdminSignup:'ไม่สามารถสร้างบัญชี Admin ผ่านหน้านี้ได้ — ให้ผู้ดูแลระบบสร้างให้ผ่าน Supabase',
  qaLocked:'บทบาท QA แก้ไขได้เฉพาะคะแนน/หมายเหตุด้านคุณภาพ',
  csmpLocked:'บทบาท CS/MP แก้ไขได้เฉพาะคะแนน/หมายเหตุด้านจัดส่งและยอดซื้อ',
  approveLocked:'เฉพาะ Admin เท่านั้นที่เลือกสถานะ "อนุมัติแล้ว" ได้',
  navGroupWork:'งานประจำ', navGroupData:'ข้อมูลและรายงาน', navGroupAdmin:'ระบบ',
  dashPrint:'พิมพ์ / ส่งออก', dashGradeMix:'การกระจายเกรด', dashWatchHint:'เส้นสี = Supplier · เส้นประ = ค่าเฉลี่ยทุกราย · ย้อนหลัง 12 เดือน',
  dashOverviewTitle:'ภาพรวมย้อนหลัง', dashIssueParetoHint2:'ย้อนหลัง 12 เดือน · ลูกศร = เทียบเดือนก่อน',
  segTotal:'รวม', segQuality:'Quality', segDelivery:'Delivery', segPurchase:'Purchase', segCount:'จำนวนครั้ง', segPoints:'คะแนนที่ถูกหัก',
};

Object.assign(TH, {
  dashPeriodLabel:'รอบการประเมิน', dashGroupLabel:'กลุ่ม Supplier', dashShipmentLabel:'สถานะ Shipment', dashRiskLabel:'ระดับความเสี่ยง',
  dashAllGroups:'ทุกกลุ่ม', dashAll:'ทั้งหมด', dashNormal:'ปกติ', dashNoShipment:'ไม่มี Shipment', dashCritical:'วิกฤต', dashHigh:'สูง', dashWatch:'เฝ้าระวัง', dashLow:'ต่ำ', dashLowRisk:'ความเสี่ยงต่ำ', dashReset:'ล้างตัวกรอง', dashLoading:'กำลังวิเคราะห์ข้อมูล Supplier…',
  dashQaPending:'QA ยังไม่ส่ง', dashCsPending:'CS/MP ยังไม่ส่ง', dashReadyApproval:'พร้อมอนุมัติ', dashCaOverdue:'CA เกินกำหนด', dashDeclining:'แนวโน้มลดลง', dashDataIssues:'ปัญหาข้อมูล',
  dashCycleCoverage:'ความครอบคลุมของรอบ', dashBelowTarget:'ต่ำกว่าเป้าหมาย', dashHighRiskSuppliers:'Supplier ความเสี่ยงสูง', dashOpenCa:'Corrective Action ที่ยังเปิด', dashNeedsIntervention:'ต้องดำเนินการ', dashRiskIndex60:'ดัชนีความเสี่ยง ≥ 60', dashExcludedNa:'ไม่นับส่วนที่เป็น N/A',
  dashCycleHealth:'สุขภาพรอบการประเมิน', dashCycleHealthHint:'ความคืบหน้าตามส่วนงานและการอนุมัติ', dashPriorityQueue:'เฝ้าระวัง', dashPriorityHint:'เรียงงานที่มีผลกระทบสูงก่อน', dashViewAll:'ดูทั้งหมด',
  dashRiskMatrix:'เมทริกซ์ความเสี่ยง Supplier', dashRiskMatrixHint:'เปรียบเทียบผลงานกับดัชนีความเสี่ยง ขนาดวงกลมสะท้อนตัวแทนผลกระทบทางธุรกิจที่มีอยู่', dashEarlyWarning:'สัญญาณเตือนล่วงหน้า', dashEarlyWarningHint:'ตรวจจับด้วยกฎที่อธิบายเหตุผลได้',
  dashPerformance12M:'วิเคราะห์ผลงานย้อนหลัง 12 เดือน', dashPerformanceHint:'การเคลื่อนไหวของผลงานในช่วงเวลาที่เลือก', dashIssuePareto:'พาเรโตสาเหตุปัญหา', dashIssueParetoHint:'สาเหตุหลักจากการให้คะแนนแบบรายหัวข้อ ย้อนหลัง 12 เดือน',
  monthJan:'ม.ค.', monthFeb:'ก.พ.', monthMar:'มี.ค.', monthApr:'เม.ย.', monthMay:'พ.ค.', monthJun:'มิ.ย.', monthJul:'ก.ค.', monthAug:'ส.ค.', monthSep:'ก.ย.', monthOct:'ต.ค.', monthNov:'พ.ย.', monthDec:'ธ.ค.',
  deptQa:'QA — คุณภาพ', deptCs:'CS — บริการลูกค้า', deptMp:'MP — วางแผนวัตถุดิบ', catQuality:'คุณภาพ', catDelivery:'การส่งมอบ', catPurchase:'ยอดซื้อ',
  dashCaTower:'ศูนย์ควบคุม Corrective Action', dashCaTowerHint:'อายุงาน วันครบกำหนด และสถานะการปิดงาน', dashOpenCaWorkspace:'เปิดหน้าจัดการ CA', dashDataConfidence:'ความน่าเชื่อถือของข้อมูล', dashDataConfidenceHint:'ตรวจความพร้อมและธรรมาภิบาลข้อมูล'
});

Object.assign(TH, {
  realEvalTitle:'แบบประเมิน Supplier', realEvalHint:'บันทึกเหตุการณ์ที่เกิดขึ้นจริง ระบบจะคำนวณคะแนนอัตโนมัติตามเกณฑ์อย่างเป็นทางการ',
  loadWorksheet:'เปิด / สร้างแบบประเมิน', worksheetStartHint:'เลือก Supplier และรอบประเมิน แล้วกดเปิดแบบประเมิน',
  qualityEvalOfficial:'การประเมินด้านคุณภาพ (QA และ TQM)', qualityProblemTitle:'A1 ปัญหาด้านคุณภาพ', qualityProblemSub:'ค่าน้ำหนักอย่างเป็นทางการ 40 คะแนน',
  environmentTitle:'A2 ผลกระทบต่อสิ่งแวดล้อม', environmentSub:'ค่าน้ำหนักอย่างเป็นทางการ 10 คะแนน',
  deliveryPurchaseEvalOfficial:'การประเมินด้านการส่งมอบและยอดซื้อ (CS และ MP)', deliveryTitle:'B1 การส่งมอบ', deliverySub:'ค่าน้ำหนักอย่างเป็นทางการ 40 คะแนน', purchaseTitle:'B2 ยอดซื้อ', purchaseSub:'ค่าน้ำหนักอย่างเป็นทางการ 10 คะแนน',
  deliveryNaMessage:'การส่งมอบเป็น N/A เนื่องจาก Supplier ไม่มี Shipment ในเดือนนี้', purchaseNaMessage:'ยอดซื้อเป็น N/A เนื่องจาก Supplier ไม่มี Shipment ในเดือนนี้',
  saveQualityDraft:'บันทึกร่าง Quality', saveDeliveryDraft:'บันทึกร่าง Delivery', evaluationEvidence:'หลักฐานประกอบการประเมิน',
  evaluationEvidenceHint:'แนบ SCAR, CAR, Claim, บันทึกการส่งมอบ หรือหลักฐานอื่นที่เกี่ยวข้อง', liveScore:'คะแนนปัจจุบัน',
  dataCompleteness:'ความครบถ้วนของข้อมูล', saveAllDraft:'บันทึกร่างทั้งหมด', occurrenceLabel:'จำนวนครั้ง', deductionLabel:'คะแนนที่ใช้',
  noIncident:'ไม่เกิดเหตุการณ์', purchaseSelectOne:'เลือกช่วงยอดซื้อ 1 รายการ', points:'คะแนน', gradeLabel:'เกรด', worksheetDraft:'ร่าง', worksheetLoaded:'เปิดแบบประเมินแล้ว'
});

function applyLang(){
  document.querySelectorAll('[data-i18n]').forEach(el=>{
    if (el.dataset.enText === undefined) el.dataset.enText = el.textContent;
    const k = el.dataset.i18n;
    const ov = translationOverrides[k];
    const ovText = ov && (lang === 'th' ? ov.th_text : ov.en_text);
    el.textContent = ovText || ((lang === 'th' && TH[k]) ? TH[k] : el.dataset.enText);
  });
  document.querySelectorAll('[data-i18n-ph]').forEach(el=>{
    if (el.dataset.enPh === undefined) el.dataset.enPh = el.placeholder;
    const k = el.dataset.i18nPh;
    const ov = translationOverrides[k];
    const ovText = ov && (lang === 'th' ? ov.th_text : ov.en_text);
    el.placeholder = ovText || ((lang === 'th' && TH[k]) ? TH[k] : el.dataset.enPh);
  });
  document.getElementById('langToggle').dataset.lang = lang;
  safeLSSet('se_lang', lang);
  setPageHeadTitle();
}

function t(key, fallback){
  const ov = translationOverrides[key];
  const ovText = ov && (lang === 'th' ? ov.th_text : ov.en_text);
  if (ovText) return ovText;
  return (lang === 'th' && TH[key]) ? TH[key] : fallback;
}
function L(en, th){ return lang === 'th' ? th : en; }

/* ============================================================
   Small helpers
   ============================================================ */
function toNum(v){ const n = Number(v); return Number.isFinite(n) ? n : 0; }

// Mirrors the DB trigger in 32_supplier_group_by_prefix.sql — the code
// prefix is the ONLY thing that decides a supplier's group. Used to
// live-preview the group in Master Control before saving; the actual
// stored value always comes from the trigger, not this function.
function supplierGroupFromCode(code){
  code = (code || '').toUpperCase();
  if (code.startsWith('MA-')) return 'Material';
  if (code.startsWith('OS-')) return 'Outsource';
  if (code.startsWith('PA-')) return 'Blank Part';
  return '';
}

// Escapes free-text values before they're interpolated into an
// innerHTML template string — every comment/problem/name field that
// came from a form input (not written by us) needs this wherever it
// lands inside HTML rather than a plain textContent assignment.
function escapeHtml(value){
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}
function monthName(n){ return MONTHS[(toNum(n) || 1) - 1] || '-'; }

// Evaluation scores show as whole numbers in the UI, with the real
// 2-decimal value in a native hover tooltip — used for total_score,
// quality/delivery/purchase scores, and score averages. Not used for
// plain counts (KPI tallies, occurrence counts, etc).
function scoreNum(value){
  if (value === null || value === undefined || value === '') return '-';
  const num = toNum(value);
  return `<span title="${num.toFixed(2)}">${Math.round(num)}</span>`;
}

// "2026-Jul" — the one format for year+month everywhere in the app.
function ymLabel(year, month){ return `${year}-${monthName(month)}`; }
function gradeOf(total){ return total >= 100 ? 'A' : total >= 80 ? 'B' : total >= 70 ? 'C' : 'D'; }
function gradeBadge(g){ return `<span class="badge ${g}">${g}</span>`; }
function statusLabel(s){
  const map = { draft:'st_draft', submitted:'st_submitted', sup_approved:'st_sup_approved', mgr_approved:'st_mgr_approved',
    approved:'st_approved', sent_to_supplier:'st_sent', acknowledged:'st_ack', follow_up_required:'st_followup' };
  const key = map[s];
  return key ? t(key, s.replace(/_/g,' ')) : (s || '-');
}

// One combined "where is this case really at" label for the
// Evaluation List — folds submit/approval stage + CA state into a
// single, specific status instead of showing the raw DB status
// column, per this session's redesign. `colorClass` maps to a badge
// color variant (see .badge.wf-* in style.css); `isOpen` drives the
// "show open cases only" filter default.
function evalWorkflowStatus(e){
  const qOk = !!e.quality_submitted_at, dOk = !!e.delivery_submitted_at;
  // A rejected evaluation looks identical to "never touched yet" once
  // both submitted timestamps are cleared (see renderSubmitStatusNote,
  // which already makes this same distinction inside the worksheet) —
  // surface it distinctly here too, in the List's badge, so it doesn't
  // get lost among ordinary pending drafts.
  // both — or now, either one — of the submitted timestamps are
  // cleared (see renderSubmitStatusNote, which makes this same
  // distinction inside the worksheet) — surface it distinctly here
  // too, in the List's badge, so it doesn't get lost among ordinary
  // pending drafts. Reject can now target just one section, so this
  // checks "at least one still missing", not "both".
  if (e.status === 'draft' && e.rejection_reason && (!qOk || !dOk)) {
    return { code:'rejected', label: L('Rejected — needs resubmission','ถูก Reject — ต้องแก้ไขและส่งใหม่'), color:'wf-danger', isOpen:true };
  }
  if (!qOk && !dOk) return { code:'wait_both', label: L('Waiting on QA and MP/CS','รอ QA และ MP/CS'), color:'wf-warn', isOpen:true };
  if (qOk && !dOk)  return { code:'wait_cs', label: L('Waiting on MP/CS','รอ MP/CS'), color:'wf-warn', isOpen:true };
  if (!qOk && dOk)  return { code:'wait_qa', label: L('Waiting on QA','รอ QA'), color:'wf-warn', isOpen:true };
  if (e.status === 'draft')        return { code:'wait_sup', label: L('Waiting on Supervisor','รอ Supervisor'), color:'wf-accent', isOpen:true };
  if (e.status === 'sup_approved') return { code:'wait_mgr', label: L('Waiting on Manager','รอ Manager'), color:'wf-accent', isOpen:true };
  if (e.status === 'mgr_approved') return { code:'wait_send', label: L('Ready to send to Supplier','รอส่ง Sup'), color:'wf-accent', isOpen:true };
  if (e.status === 'sent_to_supplier') {
    const casForEval = correctiveActions.filter(c => c.evaluation?.id === e.id);
    // Grade C/D always requires a Corrective Action — zero CAs here
    // means one is still missing (most likely it never got auto-
    // created), not that there's nothing left to do. Only count as
    // "closed" once at least one CA exists AND every one of them is
    // closed — an empty list must never read as "closed".
    if (['C','D'].includes(e.grade) && !casForEval.length) {
      return { code:'missing_ca', label: L('Grade C/D — Corrective Action missing','เกรด C/D แต่ยังไม่มี Corrective Action'), color:'wf-danger', isOpen:true };
    }
    const hasOpenCa = casForEval.length === 0 || casForEval.some(c => c.status !== 'closed');
    if (hasOpenCa) return { code:'wait_ca', label: L('Waiting on Corrective Action','รอ CA'), color:'wf-danger', isOpen:true };
    return { code:'closed', label: L('Closed','ปิดเคส'), color:'wf-good', isOpen:false };
  }
  if (e.status === 'acknowledged') return { code:'closed', label: L('Closed','ปิดเคส'), color:'wf-good', isOpen:false };
  return { code:'other', label: statusLabel(e.status), color:'wf-warn', isOpen:true };
}
function showBanner(msg){
  const b = document.getElementById('banner');
  b.textContent = msg;
  b.style.display = 'block';
}
function hideBanner(){ document.getElementById('banner').style.display = 'none'; }

/* ============================================================
   Pre-login connection self-check (visible before auth)
   ============================================================ */
async function preLoginConnectionCheck(){
  const el = document.getElementById('loginConnStatus');
  if (!el) return;
  if (!sb || SUPABASE_URL.includes('YOUR-PROJECT')) {
    el.textContent = lang === 'th'
      ? '⚠ ยังไม่ได้ตั้งค่า Supabase — ใส่ SUPABASE_URL / ANON_KEY ในไฟล์ config.js'
      : '⚠ Supabase not configured — set SUPABASE_URL / ANON_KEY in config.js';
    el.className = 'conn-check err';
    return;
  }
  try {
    const { error } = await sb.from('suppliers').select('id').limit(1);
    if (error) {
      // We reached the project — this is most likely RLS blocking anon access, which is expected.
      el.textContent = lang === 'th'
        ? '✓ เชื่อมต่อ Supabase สำเร็จ — กรุณา Sign in เพื่อดูข้อมูล'
        : '✓ Reached Supabase — sign in to see data';
      el.className = 'conn-check ok';
    } else {
      el.textContent = lang === 'th' ? '✓ เชื่อมต่อ Supabase สำเร็จ' : '✓ Connected to Supabase';
      el.className = 'conn-check ok';
    }
  } catch (e) {
    el.textContent = (lang === 'th' ? '✗ เชื่อมต่อ Supabase ไม่สำเร็จ: ' : '✗ Could not reach Supabase: ') + (e.message || e);
    el.className = 'conn-check err';
  }
}

/* ============================================================
   Auth
   ============================================================ */
let authMode = 'signin';     // 'signin' | 'signup'

function setLoginMsg(msg, ok){
  const el = document.getElementById('loginMsg');
  el.textContent = msg || '';
  el.className = 'login-msg' + (ok ? ' ok' : '');
}

function setAuthMode(mode){
  if (mode === 'signup' && !SELF_SIGNUP_ENABLED) return; // defense-in-depth, see SELF_SIGNUP_ENABLED
  authMode = mode;
  document.querySelectorAll('.login-tab').forEach(b => b.classList.toggle('active', b.dataset.mode === mode));
  document.querySelectorAll('.signup-only').forEach(el => el.style.display = mode === 'signup' ? 'block' : 'none');
  document.querySelectorAll('.signin-only').forEach(el => el.style.display = mode === 'signup' ? 'none' : 'flex');
  document.getElementById('btnAuthSubmit').textContent = mode === 'signup' ? t('signUp','Create account') : t('signIn','Sign in');
  setLoginMsg('');
}

// Self-signup can only ever create these departments — Admin accounts must
// be set up directly in Supabase (see database/04_simplify_admin_login.sql
// and the handle_new_user trigger, which also blocks 'admin'/'supervisor'
// server-side even if this list were bypassed).
const SELF_SIGNUP_DEPARTMENTS = ['qa', 'cs', 'mp'];

// Set to true to restore the earlier decision (self-signup open to
// QA/CS/MP). Currently false per the pilot-readiness recommendation:
// creating accounts should go through an Admin during the pilot, to
// keep a clean record of who has access. NOTE: hiding the tab is only
// half the protection — for this to actually stop signups (not just
// hide the button), also turn off "Allow new users to sign up" in
// Supabase Dashboard -> Authentication -> Providers -> Email. This
// flag alone does not do that.
const SELF_SIGNUP_ENABLED = false;

async function handleAuthSubmit(){
  const rawId = document.getElementById('auth_email').value.trim();
  const password = document.getElementById('auth_password').value;
  if (!rawId || !password) { setLoginMsg(t('authErrFields','Please enter your ID and password')); return; }

  if (authMode === 'signup') {
    if (!SELF_SIGNUP_ENABLED) { setLoginMsg(t('signupDisabled','Self-signup is currently disabled — ask an Admin to create your account')); return; }
    const full_name = document.getElementById('auth_fullname').value.trim();
    let department = document.getElementById('auth_department').value;
    if (!SELF_SIGNUP_DEPARTMENTS.includes(department)) department = 'qa';

    const { error } = await sb.auth.signUp({
      email: idToLoginEmail(rawId), password,
      options: { data: { full_name, department } }
    });
    if (error) { setLoginMsg(friendlyAuthError(error.message)); return; }
    setLoginMsg(t('authSignupOk','Account created — check your email if confirmation is required'), true);
  } else {
    const { error } = await sb.auth.signInWithPassword({ email: idToLoginEmail(rawId), password });
    if (error) { setLoginMsg(friendlyAuthError(error.message)); return; }

    setLoginMsg(t('authSigninOk','Signed in — loading your data…'), true);

    const remember = document.getElementById('auth_remember').checked;
    if (remember) {
      const saved = addSavedId(rawId);
      if (!saved) {
        setLoginMsg(t('rememberFailed','Signed in, but this browser would not let your User ID be saved on this device'), true);
      }
    }
    // Unchecked just means "don't add/refresh this ID" — it does not
    // wipe the rest of the saved list (other people may share this
    // device); use the × next to an entry in the suggestion list to
    // remove one specifically.
  }
}

// Supabase's own error text is in English and sometimes terse — swap in a
// clearer Thai message for the handful of errors people actually hit, fall
// back to the raw message for anything else (still shown either way, never
// silently swallowed).
function friendlyAuthError(msg){
  if (lang !== 'th') return msg;
  const map = {
    'Invalid login credentials': 'รหัสผู้ใช้หรือรหัสผ่านไม่ถูกต้อง',
    'User already registered': 'มีบัญชีนี้อยู่แล้วในระบบ',
    'Email not confirmed': 'บัญชีนี้ยังไม่ได้ยืนยันอีเมล',
    'Password should be at least 6 characters': 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร',
    'Email signups are disabled': 'ปิดการสมัครสมาชิกด้วยอีเมลไว้ — ติดต่อผู้ดูแลระบบ',
    'Signup requires a valid password': 'กรุณากรอกรหัสผ่านให้ถูกต้อง',
  };
  return map[msg] || msg;
}

// ------------------------------------------------------------
// Remembered User IDs on this device — a small local list (not the
// old single {email} shape) so a shared computer can offer everyone's
// last-used ID back as a "smart search" dropdown under the User ID
// field, instead of only ever remembering the one most recent person.
// ------------------------------------------------------------
const SAVED_ID_MAX = 8;
function getSavedIds(){
  try {
    const raw = safeLSGet('se_remember_ids');
    if (raw) return JSON.parse(raw);
  } catch (e) { /* fall through to migration */ }
  // One-time migration from the old single-ID format.
  try {
    const legacy = safeLSGet('se_remember');
    if (legacy) {
      const parsed = JSON.parse(legacy);
      safeLSRemove('se_remember');
      if (parsed.email) {
        const migrated = [parsed.email];
        safeLSSet('se_remember_ids', JSON.stringify(migrated));
        return migrated;
      }
    }
  } catch (e) { safeLSRemove('se_remember'); }
  return [];
}
function addSavedId(id){
  if (!id) return false;
  let list = getSavedIds().filter(x => x.toLowerCase() !== id.toLowerCase());
  list.unshift(id);
  if (list.length > SAVED_ID_MAX) list = list.slice(0, SAVED_ID_MAX);
  return safeLSSet('se_remember_ids', JSON.stringify(list));
}
function removeSavedId(id){
  const list = getSavedIds().filter(x => x !== id);
  safeLSSet('se_remember_ids', JSON.stringify(list));
  renderIdSuggestions();
}
function renderIdSuggestions(){
  const input = document.getElementById('auth_email');
  const box = document.getElementById('authIdSuggestions');
  if (!input || !box) return;
  const q = input.value.trim().toLowerCase();
  const all = getSavedIds();
  const matches = q ? all.filter(id => id.toLowerCase().includes(q)) : all;
  if (!matches.length) { box.style.display = 'none'; box.innerHTML = ''; return; }
  box.innerHTML = matches.map(id => `<div class="id-suggest-row" data-saved-id="${escAttr(id)}">
    <span class="id-suggest-text">${id}</span>
    <button type="button" class="id-suggest-remove" data-remove-id="${escAttr(id)}" aria-label="Remove">×</button>
  </div>`).join('');
  box.style.display = 'block';
}

function restoreRememberedLogin(){
  const list = getSavedIds();
  if (list.length) {
    document.getElementById('auth_email').value = list[0];
    document.getElementById('auth_remember').checked = true;
  }
}

async function loadProfile(){
  if (!currentUser) { currentProfile = null; return; }
  const { data, error } = await sb
    .from('user_profiles')
    .select('full_name, department')
    .eq('id', currentUser.id)
    .single();
  if (error) { console.error(error); currentProfile = null; return; }
  currentProfile = data;
}

function applyRoleGating(){
  const dept = currentProfile?.department;
  const ev = evaluations.find(x => x.id === currentEditingEvalId);
  const locked = evaluationLocked(ev);
  const canEditQuality = worksheetRoleAccess('quality');
  const canEditDelivery = worksheetRoleAccess('delivery');
  const canApprove = hasPerm('eval_sup_approve') || hasPerm('eval_mgr_approve');
  const canManageMaster = hasPerm('master_data_manage');
  const isItemized = document.getElementById('f_scoring_mode')?.value === 'itemized' && !!currentEditingEvalId;

  ['f_quality','f_qcomment'].forEach(id => document.getElementById(id).disabled = !canEditQuality);
  const noShip = document.getElementById('f_shipment')?.value === 'no_shipment';
  ['f_delivery','f_purchase'].forEach(id => document.getElementById(id).disabled = !canEditDelivery || noShip);
  ['f_dcomment','f_shipment','f_noship_reason'].forEach(id => document.getElementById(id).disabled = !canEditDelivery);
  // Itemized mode makes the 3 score fields computed/read-only regardless of
  // permission — they're driven by the checklist, not typed directly.
  if (isItemized) ['f_quality','f_delivery','f_purchase'].forEach(id => document.getElementById(id).disabled = true);

  // Consolidated submit button (was 3 separate Save/Submit buttons per
  // zone + a 4th in the sidebar) — one button, label and action driven
  // by which section(s) this department can actually edit, per
  // Permission Matrix (Setting -> Master Control -> Permissions),
  // not a hardcoded department check. canEditQuality/canEditDelivery
  // are already forced false above once the evaluation is locked, so
  // this naturally falls through to the disabled "nothing to do" state.
  const btnSave = document.getElementById('btnSave');
  if (btnSave) {
    if (canEditQuality && canEditDelivery) {
      btnSave.textContent = L('Save & Submit All','บันทึกและส่งผลทั้งหมด');
      btnSave.disabled = false; btnSave.dataset.mode = 'all';
    } else if (canEditQuality) {
      btnSave.textContent = L('Submit Quality','ส่งผล Quality');
      btnSave.disabled = false; btnSave.dataset.mode = 'quality';
    } else if (canEditDelivery) {
      btnSave.textContent = L('Submit Delivery/Purchase','ส่งผล Delivery/Purchase');
      btnSave.disabled = false; btnSave.dataset.mode = 'delivery';
    } else {
      btnSave.textContent = locked ? L('Evaluation closed — no further edits','ปิดรายการแล้ว — แก้ไขเพิ่มเติมไม่ได้') : L('View Details','ดูรายละเอียด');
      btnSave.disabled = true; btnSave.dataset.mode = 'none';
    }
  }

  const bothSubmitted = !!(ev?.quality_submitted_at && ev?.delivery_submitted_at);
  const statusSel = document.getElementById('f_status');
  Array.from(statusSel.options).forEach(opt => {
    opt.disabled = (opt.value === 'approved' && !(canApprove && bothSubmitted)); // vestigial hidden select, kept harmless
  });

  const note = document.getElementById('roleNote');
  if (note) {
    note.textContent = canManageMaster ? '' : dept === 'qa' ? t('qaLocked','') : (dept === 'cs' || dept === 'mp' || dept === 'cs_supervisor') ? t('csmpLocked','') : t('noProfile','');
  }

  // Master Control and Import/Export are now sub-tabs inside Setting
  // (not their own top-level nav items) — gate the sub-tab buttons
  // themselves, and bounce a non-admin back to the Status sub-tab if
  // they're currently looking at one of the admin-only ones (e.g. role
  // changed mid-session). Activity Log stays visible to everyone on
  // purpose — only its Revert button is Admin-gated, not the tab itself.
  const settingTabMaster = document.getElementById('settingTabMaster');
  const settingTabIE = document.getElementById('settingTabIE');
  const settingTabTranslation = document.getElementById('settingTabTranslation');
  if (settingTabMaster) settingTabMaster.style.display = canManageMaster ? 'inline-flex' : 'none';
  if (settingTabIE) settingTabIE.style.display = canManageMaster ? 'inline-flex' : 'none';
  if (settingTabTranslation) settingTabTranslation.style.display = canManageMaster ? 'inline-flex' : 'none';
  if (!canManageMaster) {
    const activeSettingTab = document.querySelector('[data-settingtab].active')?.dataset.settingtab;
    if (activeSettingTab === 'master' || activeSettingTab === 'importexport' || activeSettingTab === 'translation') {
      setSettingTab('status');
    }
  }

  const cyclePanel = document.getElementById('cycleOpenerPanel');
  if (cyclePanel) cyclePanel.style.display = canManageMaster ? 'block' : 'none';

  const ieBar = document.getElementById('masterOnlyImportExportBar');
  if (ieBar) ieBar.style.display = canManageMaster ? 'flex' : 'none';
}

function renderUserBadge(){
  const rawEmail = currentUser?.email || '';
  document.getElementById('userName').textContent = rawEmail.endsWith(LOGIN_EMAIL_DOMAIN)
    ? rawEmail.slice(0, -LOGIN_EMAIL_DOMAIN.length)
    : (rawEmail || '—');
  const deptLabels = { qa:'QA', cs:'CS', mp:'MP', cs_supervisor:'CS Supervisor', mp_supervisor:'MP Supervisor', opd_manager:'OPD Manager', supervisor:'Admin', admin:'Admin' };
  document.getElementById('userDept').textContent = deptLabels[currentProfile?.department] || (currentProfile ? '—' : t('noProfile','No profile'));
}

async function bootAuth(){
  const { data: { session } } = await sb.auth.getSession();
  await handleSession(session);

  sb.auth.onAuthStateChange(async (_event, session) => {
    await handleSession(session);
  });
}

async function handleSession(session){
  const shellVisible = document.getElementById('appShell').style.display !== 'none';
  const sameUserAlreadyLoaded = !!(currentUser && session?.user?.id === currentUser.id && shellVisible);
  currentUser = session?.user || null;
  if (currentUser) {
    // onAuthStateChange also fires for routine token refreshes — which
    // happen, among other times, whenever the browser tab regains focus.
    // That's still the same logged-in user with everything already
    // loaded, so there's nothing to do — reloading here was what made
    // the loading screen flash on every tab switch.
    if (sameUserAlreadyLoaded) return;
    await loadProfile();
    document.getElementById('loginGate').style.display = 'none';
    document.getElementById('appShell').style.display = 'flex';
    renderUserBadge();
    applyRoleGating();
    await reloadAll();
  } else {
    currentProfile = null;
    document.getElementById('loginGate').style.display = 'flex';
    document.getElementById('appShell').style.display = 'none';
  }
}

/* ============================================================
   Data loading
   ============================================================ */
async function checkConnection(){
  const dot = document.getElementById('connDot');
  const label = document.getElementById('connLabel');
  if (!sb || SUPABASE_URL.includes('YOUR-PROJECT')) {
    dot.className = 'dot err';
    label.textContent = t('notConfigured','Supabase not configured');
    showBanner(lang==='th'
      ? 'ยังไม่ได้ตั้งค่า Supabase — ไปที่แท็บ "ตั้งค่า / สถานะ" เพื่อดูวิธีตั้งค่า'
      : 'Supabase is not configured yet — see the "Setup & Status" tab.');
    return false;
  }
  try {
    const { error } = await sb.from('suppliers').select('id').limit(1);
    if (error) throw error;
    dot.className = 'dot ok';
    label.textContent = t('connOk','Connected to Supabase');
    hideBanner();
    return true;
  } catch (e) {
    dot.className = 'dot err';
    label.textContent = t('connFail','Connection failed');
    showBanner((lang==='th' ? 'เชื่อมต่อ Supabase ไม่สำเร็จ: ' : 'Could not reach Supabase: ') + (e.message || e));
    console.error(e);
    return false;
  }
}

// Checked once per login (called from reloadAll, before any data
// loads). A behind-schema database is worse than a connection failure
// — the app would otherwise load and then fail confusingly on
// whichever specific feature touches the missing table/column/function
// first. table-not-found (migration 25 itself not run yet) and an
// actual version mismatch are both treated as "too old" — the message
// tells an Admin exactly what to do either way.
async function checkSchemaVersion(){
  try {
    const { data, error } = await sb.from('app_schema_version').select('version, package_version').eq('id', 1).maybeSingle();
    if (error) throw error;
    if (!data || data.version < REQUIRED_SCHEMA_VERSION) {
      showSchemaVersionBlock(data?.version ?? null, data?.package_version ?? null);
      return false;
    }
    return true;
  } catch (e) {
    // Missing table entirely (pre-25 database) surfaces here too.
    showSchemaVersionBlock(null, null);
    return false;
  }
}

function showSchemaVersionBlock(currentVersion, currentPackage){
  hideLoadingOverlay();
  document.getElementById('appShell').style.display = 'none';
  document.getElementById('loginGate').style.display = 'flex';
  const msg = currentVersion === null
    ? (lang==='th'
        ? `ฐานข้อมูลนี้ยังไม่มีตาราง app_schema_version (ต้องรัน database/25_schema_version.sql เป็นอย่างน้อย) — แอปเวอร์ชันนี้ต้องการ schema version ${REQUIRED_SCHEMA_VERSION}ขึ้นไป กรุณาแจ้ง Admin ให้รัน migration ที่ยังไม่ได้รันให้ครบก่อนใช้งาน`
        : `This database has no app_schema_version table yet (run at least database/25_schema_version.sql). This app version requires schema ${REQUIRED_SCHEMA_VERSION}+. Ask an Admin to finish running the outstanding migrations before using the app.`)
    : (lang==='th'
        ? `ฐานข้อมูลอยู่ที่ schema เวอร์ชัน ${currentVersion} (${currentPackage||'-'}) แต่แอปนี้ต้องการอย่างน้อย ${REQUIRED_SCHEMA_VERSION} — กรุณาแจ้ง Admin ให้รัน migration ที่เหลือให้ครบก่อนใช้งาน`
        : `This database is at schema version ${currentVersion} (${currentPackage||'-'}), but this app requires at least ${REQUIRED_SCHEMA_VERSION}. Ask an Admin to run the remaining migrations before using the app.`);
  showBanner(msg);
}

async function loadSuppliers(){
  const { data, error } = await sb
    .from('suppliers')
    .select('id, code, name, short_name, attention, tel, category, last_purchase_score, last_purchase_period')
    .eq('is_active', true)
    .order('code');
  if (error) { console.error(error); showBanner('Load suppliers failed: ' + error.message); return; }
  suppliers = data || [];
}

async function loadEvaluations(){
  const { data, error } = await sb
    .from('evaluations')
    .select('id, year, month, quality_score, delivery_score, purchase_score, total_score, grade, quality_comment, delivery_comment, status, shipment_status, no_shipment_reason, raw_score, applicable_weight, scoring_mode, quality_submitted_at, delivery_submitted_at, sent_at, acknowledged_at, rejection_reason, rejected_at, sup_approved_at, mgr_approved_at, supplier:suppliers(id,code,name,short_name,attention,tel,category,is_active,target_score)')
    .order('year', { ascending:false })
    .order('month', { ascending:false });
  if (error) { console.error(error); showBanner('Load evaluations failed: ' + error.message); return; }
  evaluations = data || [];
}

async function loadCorrectiveActions(){
  const { data, error } = await sb
    .from('corrective_actions')
    .select('id, seq_no, problem, root_cause, action, responsible_person, start_date, due_date, finished_date, status, evaluation:evaluations(id, year, month, grade, total_score, supplier:suppliers(id,code,name,short_name))')
    .order('due_date', { ascending: true, nullsFirst: false });
  if (error) { console.error(error); showBanner('Load corrective actions failed: ' + error.message); return; }
  correctiveActions = data || [];
}

async function loadEvaluationCriteria(){
  const { data, error } = await sb
    .from('evaluation_criteria')
    .select('id, category, item_no, description, description_th, full_score, deduction_points, display_order, is_active, lineage_id, version, superseded_by')
    .order('display_order');
  if (error) { console.error(error); showBanner('Load evaluation criteria failed: ' + error.message); return; }
  evaluationCriteria = data || [];
}

async function loadAllSuppliers(){
  const { data, error } = await sb
    .from('suppliers')
    .select('id, code, name, short_name, attention, tel, email, category, target_score, is_active, last_purchase_score, last_purchase_period')
    .order('code');
  if (error) { console.error(error); showBanner('Load suppliers (master) failed: ' + error.message); return; }
  allSuppliers = data || [];
}

async function loadUserProfilesList(){
  const { data, error } = await sb
    .from('user_profiles')
    .select('id, full_name, department, created_at')
    .order('created_at');
  if (error) { console.error(error); showBanner('Load user profiles failed: ' + error.message); return; }
  userProfilesList = data || [];
}

async function loadPermissionRules(){
  const { data, error } = await sb.from('permission_rules').select('rule_key, department, allowed');
  if (error) { console.error(error); showBanner('Load permission rules failed: ' + error.message); return; }
  permissionRules = data || [];
}

async function loadHolidays(){
  const { data, error } = await sb.from('public_holidays').select('id, holiday_date, name, name_th').order('holiday_date');
  if (error) { console.error(error); showBanner('Load holidays failed: ' + error.message); return; }
  holidays = data || [];
}

async function loadAllEvaluationItems(){
  const { data, error } = await sb.from('evaluation_items').select('evaluation_id, criteria_id, occurrence');
  if (error) { console.error(error); showBanner('Load evaluation items failed: ' + error.message); return; }
  allEvaluationItems = data || [];
}

// hasPerm(ruleKey) — does the CURRENT user's department have this
// permission? Reads from permissionRules (loaded once per session,
// refreshed after any change in Master Control -> Permissions).
// Mirrors has_permission() in the database exactly — this is for UI
// gating (show/hide/disable) only; the database is what actually
// enforces it, this just keeps the screen from looking misleading.
function hasPerm(ruleKey){
  const dept = currentProfile?.department;
  if (!dept) return false;
  const row = permissionRules.find(r => r.rule_key === ruleKey && r.department === dept);
  return !!row?.allowed;
}

function showLoadingOverlay(){
  const el = document.getElementById('loadingOverlay');
  if (el) el.style.display = 'flex';
}
function hideLoadingOverlay(){
  const el = document.getElementById('loadingOverlay');
  if (el) el.style.display = 'none';
}
function updateLoadingProgress(done, total, label){
  const bar = document.getElementById('loadingProgressBar');
  const txt = document.getElementById('loadingStatusText');
  if (bar) bar.style.width = `${Math.round((done/total)*100)}%`;
  if (txt) txt.textContent = `${label} (${done}/${total})`;
}

// Opens this month's cycle automatically (creates draft evaluations for
// every active supplier that has none yet). Runs at most once per page
// load, only when something is actually missing, and never blocks the app:
// if database/35_auto_open_current_cycle.sql has not been run yet, or the
// call fails for any reason, it just logs and carries on.
let autoCycleTried = false;
async function autoOpenCurrentCycle(){
  if (autoCycleTried) return;
  autoCycleTried = true;
  try {
    const now = bangkokToday();
    const opened = new Set(evaluations.filter(e => e.year === now.y && e.month === now.m).map(e => e.supplier?.id));
    const missing = allSuppliers.filter(s => s.is_active !== false && !opened.has(s.id));
    if (!missing.length) return;
    const { data, error } = await sb.rpc('ensure_current_cycle');
    if (error) { console.warn('ensure_current_cycle unavailable (run database/35_auto_open_current_cycle.sql):', error.message); return; }
    const row = Array.isArray(data) ? data[0] : data;
    if (row && row.created_count > 0) {
      await loadEvaluations();
      console.info(`ensure_current_cycle created ${row.created_count} evaluation(s) for ${now.y}-${now.m}`);
    }
  } catch (err) { console.warn('autoOpenCurrentCycle failed:', err); }
}

async function reloadAll(){
  showLoadingOverlay();
  const ok = await checkConnection();
  if (!ok) { hideLoadingOverlay(); renderAll(); return; }
  const schemaOk = await checkSchemaVersion();
  if (!schemaOk) { return; } // showSchemaVersionBlock() already hid the overlay and shows the login gate

  const steps = [
    { fn: loadSuppliers,          label: lang==='th' ? 'ข้อมูล Supplier' : 'Suppliers' },
    { fn: loadEvaluations,        label: lang==='th' ? 'ผลประเมิน' : 'Evaluations' },
    { fn: loadCorrectiveActions,  label: lang==='th' ? 'Corrective Action' : 'Corrective Actions' },
    { fn: loadEvaluationCriteria, label: lang==='th' ? 'หัวข้อประเมิน' : 'Evaluation Criteria' },
    { fn: loadAllSuppliers,       label: lang==='th' ? 'ข้อมูล Supplier ทั้งหมด' : 'All Suppliers (Master)' },
    { fn: loadUserProfilesList,   label: lang==='th' ? 'รายชื่อผู้ใช้' : 'User List' },
    { fn: loadPermissionRules,    label: lang==='th' ? 'สิทธิ์การใช้งาน' : 'Permission Rules' },
    { fn: loadHolidays,           label: lang==='th' ? 'วันหยุด' : 'Holidays' },
    { fn: loadAllEvaluationItems, label: lang==='th' ? 'รายละเอียดคะแนน' : 'Score Details' },
    { fn: loadTranslationOverrides, label: lang==='th' ? 'คำแปลที่ตั้งค่าไว้' : 'Translation Overrides' },
    { fn: loadDashboardItemRows, label: lang==='th' ? 'ข้อมูล Pareto' : 'Pareto Data' },
  ];

  for (let i = 0; i < steps.length; i++) {
    updateLoadingProgress(i, steps.length, steps[i].label);
    await steps[i].fn();
  }
  updateLoadingProgress(steps.length, steps.length, lang==='th' ? 'เสร็จสิ้น' : 'Done');

  await autoOpenCurrentCycle();
  renderAll();
  hideLoadingOverlay();
}

/* ============================================================
   Tabs
   ============================================================ */


// Back/Forward navigation — built on the browser's native History API so
// the app remembers which tab (and, for input/ca/profile/report, which
// specific record) was open, and both the on-screen buttons and the
// browser's own Back/Forward work the same way.
let isRestoringHistory = false;

function showTab(tab){
  document.querySelectorAll('.rail-link').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
  document.querySelectorAll('.view').forEach(v => v.classList.toggle('active', v.id === tab));
  setPageHeadTitle();
  if (tab === 'setting') setSettingTab(document.querySelector('[data-settingtab].active')?.dataset.settingtab || 'status');
  if (!isRestoringHistory) {
    history.pushState({ tab }, '', '#' + tab);
  }
  renderAll();
  // Canvas charts drawn while their tab was hidden end up a 0x0 buffer
  // (clientWidth/Height read 0) and stay blank even after becoming
  // visible, since nothing else re-triggers a redraw. requestAnimationFrame
  // guarantees a redraw happens after the browser has actually painted
  // this tab as visible, so the canvas has real dimensions to draw into.
  if (tab === 'dashboard') requestAnimationFrame(() => { renderPerformanceTrend(); });
  if (tab === 'profile') requestAnimationFrame(renderProfile);
}

function setSettingTab(tab){
  document.querySelectorAll('[data-settingtab]').forEach(b => b.classList.toggle('active', b.dataset.settingtab === tab));
  document.getElementById('settingStatus').style.display = tab === 'status' ? 'block' : 'none';
  document.getElementById('settingMaster').style.display = tab === 'master' ? 'block' : 'none';
  document.getElementById('settingImportExport').style.display = tab === 'importexport' ? 'block' : 'none';
  document.getElementById('settingActivityLog').style.display = tab === 'activitylog' ? 'block' : 'none';
  document.getElementById('settingTranslation').style.display = tab === 'translation' ? 'block' : 'none';
  if (tab === 'activitylog') loadActionLog().then(renderActionLogTable);
  if (tab === 'translation') { buildTranslationCatalog(); populateTranslationCategoryDropdown(); loadTranslationOverrides().then(renderTranslationTable); }
}

// Sets the topbar title purely via JS — deliberately has NO data-i18n
// attribute in the HTML, so applyLang() (which resets every
// data-i18n element on every render) can never fight over it the way
// it did with the old shared title element. Called from showTab() on
// navigation and from applyLang() on language switch, always deriving
// the tab from whichever .view is currently active rather than being
// passed one, so it's correct no matter which one called it.
function setPageHeadTitle(){
  const tab = document.querySelector('.view.active')?.id || 'dashboard';
  const map = {
    dashboard:'dashboard', list:'evalList', input:'monthlyInputTitle', ca:'caTab',
    profile:'supplierProfile', report:'reportPreview',
    setting:'setting',
  };
  const key = map[tab] || 'dashboard';
  const el = document.getElementById('pageHeadTitle');
  const btnBack = document.getElementById('btnBackToListFromInput');
  if (!el) return;
  // "Back to List" only makes sense on the Input tab (whether the
  // picker or an open worksheet is showing) — hidden everywhere else.
  if (btnBack) btnBack.style.display = (tab === 'input') ? 'inline-flex' : 'none';
  el.textContent = t(key, key);
}

// Call after showTab() has already landed on a tab, to record which
// specific record within that tab is showing — so Back returns to this
// exact item, not just the tab in general. Replaces (doesn't push) the
// entry showTab just created for this same navigation moment.
function attachHistoryId(id){
  if (isRestoringHistory) return;
  const activeView = document.querySelector('.view.active');
  const tab = activeView?.id;
  if (tab) history.replaceState({ tab, id }, '', '#' + tab);
}

window.addEventListener('popstate', (event) => {
  const state = event.state || { tab: 'dashboard' };
  isRestoringHistory = true;
  showTab(state.tab);
  if (state.id) {
    if (state.tab === 'input') editEvaluation(state.id);
    else if (state.tab === 'ca') editCorrectiveAction(state.id);
    else if (state.tab === 'profile') { const sel = document.getElementById('profileSupplier'); if (sel) { sel.value = state.id; renderProfile(); } }
    else if (state.tab === 'report') { const sel = document.getElementById('reportSelect'); if (sel) { sel.value = state.id; renderReport(); } }
  }
  isRestoringHistory = false;
});

/* ============================================================
   Rendering — dashboard
   ============================================================ */
function renderKPI(){
  const a = evaluations, n = a.length;
  const avg = n ? a.reduce((s,e) => s + toNum(e.total_score), 0) / n : 0;
  document.getElementById('kpiTotal').textContent = n;
  document.getElementById('kpiAvg').textContent = avg.toFixed(1);
  document.getElementById('kpiA').textContent = a.filter(e => e.grade === 'A').length;
  document.getElementById('kpiB').textContent = a.filter(e => e.grade === 'B').length;
  document.getElementById('kpiCD').textContent = a.filter(e => ['C','D'].includes(e.grade)).length;
  document.getElementById('kpiRisk').textContent = a.filter(e => toNum(e.total_score) < 80).length;
  document.getElementById('kpiCaOverdue').textContent = correctiveActions.filter(isCaOverdue).length;
}

function drawBar(canvas, labels, values, colorFn){
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const dpr = window.devicePixelRatio || 1;
  const W0 = canvas.clientWidth, H0 = canvas.clientHeight;
  if (!W0 || !H0) return; // hidden tab — nothing to draw into yet, showTab() re-triggers this once visible
  const w = canvas.width = W0 * dpr;
  const h = canvas.height = H0 * dpr;
  ctx.setTransform(1,0,0,1,0,0);
  ctx.scale(dpr, dpr);
  ctx.clearRect(0,0,w,h);
  const W = canvas.clientWidth, H = canvas.clientHeight, pad = 34;
  if (!values.length) { return; }
  const max = Math.max(100, ...values);
  const bw = (W - pad*2) / values.length;
  // Bars this narrow can't fit a value number and a rotated date label
  // on every single one without them overlapping into an unreadable
  // smear — thin them out rather than force everything in.
  const skipEvery = bw < 22 ? 3 : bw < 34 ? 2 : 1;
  ctx.font = '11px IBM Plex Mono, monospace';
  values.forEach((v,i) => {
    const x = pad + i*bw + 5;
    const bh = (H - pad*2) * (Math.max(v,0) / max);
    const y = H - pad - bh;
    ctx.fillStyle = colorFn(i, v);
    ctx.fillRect(x, y, Math.max(6, bw - 10), bh);
    if (i % skipEvery === 0) {
      ctx.fillStyle = '#5B6470';
      ctx.save();
      ctx.translate(x + 3, H - 16);
      ctx.rotate(-Math.PI/4);
      ctx.fillText(String(labels[i]).slice(0,10), 0, 0);
      ctx.restore();
      if (bw >= 22) { ctx.fillStyle = '#1B1F23'; ctx.fillText(String(v), x, y - 4); }
    }
  });
  ctx.strokeStyle = '#E3E1D9';
  ctx.beginPath(); ctx.moveTo(pad, H-pad); ctx.lineTo(W-pad, H-pad); ctx.stroke();
}

function drawDonut(canvas, data){
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const dpr = window.devicePixelRatio || 1;
  canvas.width = canvas.clientWidth * dpr;
  canvas.height = canvas.clientHeight * dpr;
  ctx.setTransform(1,0,0,1,0,0);
  ctx.scale(dpr, dpr);
  ctx.clearRect(0,0,canvas.width,canvas.height);
  const cx = canvas.clientWidth/2, cy = 116, r = 82;
  const total = Object.values(data).reduce((a,b)=>a+b,0) || 1;
  let start = -Math.PI/2;
  const colors = { A:'#3F7A4E', B:'#0E6E66', C:'#B4650A', D:'#A23B3B' };
  Object.entries(data).forEach(([k,v]) => {
    const ang = v/total * Math.PI*2;
    ctx.beginPath(); ctx.moveTo(cx,cy);
    ctx.arc(cx,cy,r,start,start+ang);
    ctx.fillStyle = colors[k] || '#999';
    ctx.fill();
    start += ang;
  });
  ctx.beginPath(); ctx.arc(cx,cy,44,0,Math.PI*2); ctx.fillStyle = '#fff'; ctx.fill();
  ctx.fillStyle = '#1B1F23'; ctx.font = '700 22px IBM Plex Mono, monospace'; ctx.textAlign = 'center';
  ctx.fillText(total, cx, cy+7);
  ctx.font = '11.5px IBM Plex Sans, sans-serif'; ctx.textAlign = 'left';
  let ly = cy + r + 26;
  Object.keys(data).forEach(k => {
    ctx.fillStyle = colors[k];
    ctx.fillRect(18, ly-9, 11, 11);
    ctx.fillStyle = '#5B6470';
    ctx.fillText(`Grade ${k}: ${data[k]}`, 34, ly);
    ly += 18;
  });
}

function renderCharts(){
  const rank = [...evaluations].sort((a,b) => toNum(b.total_score) - toNum(a.total_score)).slice(0,16);
  drawBar(
    document.getElementById('scoreChart'),
    rank.map(e => e.supplier?.code || '-'),
    rank.map(e => toNum(e.total_score)),
    (i,v) => v < 80 ? '#A23B3B' : v >= 100 ? '#3F7A4E' : '#0E6E66'
  );
  const gd = { A:0, B:0, C:0, D:0 };
  evaluations.forEach(e => { if (e.grade) gd[e.grade] = (gd[e.grade]||0) + 1; });
  drawDonut(document.getElementById('gradeChart'), gd);
}

function renderRiskTable(){
  const el = document.getElementById('riskTable');
  const arr = evaluations.filter(isRisk);
  if (!arr.length) {
    el.innerHTML = `<div class="empty-note">${t('noRisk', lang==='th' ? 'ไม่พบ Supplier ที่มีความเสี่ยง' : 'No suppliers currently at risk')}</div>`;
    return;
  }
  const heads = lang==='th' ? ['Supplier','คะแนน','เกรด','หมายเหตุ','สถานะ'] : ['Supplier','Score','Grade','Comment','Status'];
  el.innerHTML = `<table><thead><tr>${heads.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${
    arr.map(e => `<tr>
      <td><b>${escapeHtml(e.supplier?.code||'')}</b><br><span class="muted-small">${escapeHtml(e.supplier?.name||'')}</span></td>
      <td class="num">${e.total_score}</td>
      <td>${gradeBadge(e.grade)}</td>
      <td class="muted-small">${[e.quality_comment,e.delivery_comment].filter(Boolean).join('<br>') || '-'}</td>
      <td><span class="badge status">${statusLabel(e.status)}</span></td>
    </tr>`).join('')
  }</tbody></table>`;
}

/* ============================================================
   Rendering — evaluation list
   ============================================================ */
function filteredEvaluations(){
  let arr = [...evaluations];
  const txt = (document.getElementById('filterText').value || '').toLowerCase();
  const grp = document.getElementById('filterGroup')?.value;
  const supId = document.getElementById('filterSupplier')?.value;
  const yr = document.getElementById('filterYear').value;
  const mo = document.getElementById('filterMonth').value;
  const g = document.getElementById('filterGrade').value;
  const ws = document.getElementById('filterWorkflowStatus')?.value;
  const openOnly = document.getElementById('filterOpenOnly')?.checked;
  const hasCaOnly = document.getElementById('filterHasCaOnly')?.checked;
  if (txt) arr = arr.filter(e => `${e.supplier?.code} ${e.supplier?.name} ${e.quality_comment||''} ${e.delivery_comment||''}`.toLowerCase().includes(txt));
  if (grp) arr = arr.filter(e => (suppliers.find(s => s.id === e.supplier?.id)?.category) === grp);
  if (supId) arr = arr.filter(e => e.supplier?.id === supId);
  if (yr) arr = arr.filter(e => e.year === toNum(yr));
  if (mo) arr = arr.filter(e => e.month === toNum(mo));
  if (g) arr = arr.filter(e => e.grade === g);
  if (ws) arr = arr.filter(e => evalWorkflowStatus(e).code === ws);
  if (openOnly) arr = arr.filter(e => evalWorkflowStatus(e).isOpen);
  if (hasCaOnly) arr = arr.filter(e => correctiveActions.some(ca => ca.evaluation?.id === e.id));
  return arr;
}

// Group dropdown — populated once (categories are stable within a
// session); Supplier dropdown is re-populated whenever Group changes,
// narrowed to just that group, matching the cascading pattern already
// used on the Report page.
function populateListGroupFilter(){
  const sel = document.getElementById('filterGroup');
  if (!sel || sel.options.length > 1) return;
  const categories = [...new Set(suppliers.map(s => s.category).filter(Boolean))].sort();
  sel.innerHTML = `<option value="">${t('allCategories','All Categories')}</option>` +
    categories.map(c => `<option value="${escapeHtml(c)}">${escapeHtml(c)}</option>`).join('');
}
function populateListSupplierFilter(){
  const grpSel = document.getElementById('filterGroup');
  const sel = document.getElementById('filterSupplier');
  if (!sel) return;
  const prev = sel.value;
  const grp = grpSel?.value || '';
  const filtered = grp ? suppliers.filter(s => s.category === grp) : suppliers;
  sel.innerHTML = `<option value="">${t('allSuppliers','All Suppliers')}</option>` +
    filtered.map(s => `<option value="${s.id}">${s.code} — ${s.short_name||s.name}</option>`).join('');
  if (prev && filtered.some(s => s.id === prev)) sel.value = prev;
}

// Called once when the list is first shown, to default the year/month
// filters to the latest period that actually has data — instead of
// "All", which used to dump the entire history in one screen.
let listDefaultFilterApplied = false;
function applyListDefaultFilter(){
  if (listDefaultFilterApplied || !evaluations.length) return;
  const yrInput = document.getElementById('filterYear');
  const moInput = document.getElementById('filterMonth');
  if (!yrInput || !moInput || yrInput.value || moInput.value) { listDefaultFilterApplied = true; return; }
  const latest = [...evaluations].sort((a,b) => (b.year*12+b.month) - (a.year*12+a.month))[0];
  if (latest) { yrInput.value = latest.year; moInput.value = latest.month; }
  listDefaultFilterApplied = true;
}

let evalSelection = new Set(); // ids currently checked, for Export

function renderEvalTable(){
  applyListDefaultFilter();
  populateListGroupFilter();
  populateListSupplierFilter();
  const el = document.getElementById('evalTable');
  const arr = filteredEvaluations();
  // Selection only survives across a re-render for rows still in view.
  evalSelection = new Set([...evalSelection].filter(id => arr.some(e => e.id === id)));
  updateExportButton();
  if (!arr.length) {
    el.innerHTML = `<div class="empty-note">${t('noData','No data yet — add one from Monthly Input.')}</div>`;
    return;
  }
  const H = lang==='th'
    ? [{t:'',num:false},{t:'เดือน-ปี'},{t:'Supplier'},{t:'Q',num:true},{t:'E',num:true},{t:'D',num:true},{t:'P',num:true},{t:'รวม',num:true},{t:'เกรด'},{t:'สถานะ'},{t:'จัดการ'}]
    : [{t:'',num:false},{t:'Month-Year'},{t:'Supplier'},{t:'Q',num:true},{t:'E',num:true},{t:'D',num:true},{t:'P',num:true},{t:'Total',num:true},{t:'Grade'},{t:'Status'},{t:'Action'}];
  const canEditSomething = hasPerm('eval_edit_quality') || hasPerm('eval_edit_delivery');
  const canDelete = hasPerm('eval_delete');
  el.innerHTML = `<table><thead><tr>${H.map(h=>`<th${h.num?' class="num"':''}>${h.t}</th>`).join('')}</tr></thead><tbody>${
    arr.map(e => {
      const noShip = e.shipment_status === 'no_shipment';
      const split = qualityEnvSplit(e);
      const exportable = e.scoring_mode === 'itemized';
      const wf = evalWorkflowStatus(e);
      return `<tr>
      <td>${exportable
        ? `<input type="checkbox" ${evalSelection.has(e.id)?'checked':''} onchange="toggleEvalSelection('${e.id}',this.checked)">`
        : `<input type="checkbox" disabled title="${L('No itemized checklist to export — manual-mode evaluation','ไม่มี checklist รายหัวข้อให้ export — เป็น evaluation แบบ manual')}">`}</td>
      <td class="nowrap">${ymLabel(e.year, e.month)}</td>
      <td><b>${escapeHtml(e.supplier?.code||'')}</b><br><span class="muted-small">${escapeHtml(e.supplier?.name||'')}</span></td>
      <td class="num">${scoreNum(split.q)}</td>
      <td class="num">${split.env===null ? '-' : scoreNum(split.env)}</td>
      <td class="num">${noShip ? 'N/A' : scoreNum(e.delivery_score)}</td>
      <td class="num">${noShip ? 'N/A' : scoreNum(e.purchase_score)}</td>
      <td class="num"><b>${scoreNum(e.total_score)}%</b></td>
      <td>${gradeBadge(e.grade)}</td>
      <td class="nowrap"><span class="badge ${wf.color}">${wf.label}</span>${noShip ? `<br><span class="badge status">${t('shipmentNone','No Shipment')}</span>` : ''}</td>
      <td class="nowrap">
        <div class="row-actions">
          <button class="row-btn" onclick="editEvaluation('${e.id}')" title="${L('View','ดู')}">👁️</button>
          ${canEditSomething ? `<button class="row-btn" onclick="editEvaluation('${e.id}')" title="${L('Edit','แก้ไข')}">✏️</button>` : ''}
          ${canDelete ? `<button class="row-btn danger" onclick="deleteEvaluation('${e.id}')" title="${L('Delete','ลบ')}">🗑️</button>` : ''}
          ${(() => {
            const casForEval = correctiveActions.filter(c => c.evaluation?.id === e.id);
            if (!casForEval.length) {
              // Grade C/D with zero CAs shouldn't happen (one should
              // have been auto-created) — surface a direct fix instead
              // of leaving the row with no way to create one but the
              // generic "+ New Corrective Action" button up top (which
              // doesn't pre-select which evaluation it's for).
              if (['C','D'].includes(e.grade) && hasPerm('ca_create')) {
                return `<button class="row-btn danger" onclick="createCaForEvaluation('${e.id}')" title="${L('Grade C/D has no Corrective Action yet — create one','เกรด C/D แต่ยังไม่มี Corrective Action — กดเพื่อสร้าง')}">➕📋</button>`;
              }
              return '';
            }
            // If there are multiple CAs on this evaluation, link to
            // whichever one is still open (the one someone actually
            // needs to act on) — only fall back to "most recent" if
            // every CA is already closed.
            const ca = casForEval.find(c => c.status !== 'closed')
                    || casForEval.reduce((a,b) => (b.seq_no||0) > (a.seq_no||0) ? b : a);
            const failed = failedCriteriaFor(e.id);
            return `<button class="row-btn" onclick="editCorrectiveAction('${ca.id}')" title="${escapeHtml(L('Corrective Action — failed: ','Corrective Action — ตกที่: ') + failed)}">📋</button>`;
          })()}
        </div>
      </td>
    </tr>`; }).join('')
  }</tbody></table>`;
}

function toggleEvalSelection(id, checked){
  if (checked) evalSelection.add(id); else evalSelection.delete(id);
  updateExportButton();
}

function updateExportButton(){
  const btn = document.getElementById('btnExportSelected');
  if (!btn) return;
  btn.disabled = evalSelection.size === 0;
  btn.textContent = `${L('Export Selected','Export ที่เลือก')} (${evalSelection.size})`;
}

/* ============================================================
   Rendering — monthly input form
   ============================================================ */
function populateSupplierSelect(){
  const sel = document.getElementById('f_supplier');
  sel.innerHTML = suppliers.map(s => `<option value="${s.id}">${s.code} — ${s.short_name || s.name}</option>`).join('');
}

function calcPreview(){
  const q = toNum(document.getElementById('f_quality').value);
  const d = toNum(document.getElementById('f_delivery').value);
  const p = toNum(document.getElementById('f_purchase').value);
  const noShip = document.getElementById('f_shipment').value === 'no_shipment';
  const applicableWeight = noShip ? 50 : 100;
  const raw = q + (noShip ? 0 : d) + (noShip ? 0 : p);
  const total = Math.round((raw / applicableWeight) * 100 * 100) / 100;
  const rawLabel = noShip ? ` — ${t('rawScoreLabel','Raw')} ${raw}/${applicableWeight}` : '';
  document.getElementById('f_total_preview').value = `${total}%  (${gradeOf(total)})${rawLabel}`;
}

function toggleShipmentFields(){
  const noShip = document.getElementById('f_shipment').value === 'no_shipment';
  document.getElementById('noShipRow').style.display = noShip ? 'grid' : 'none';
  applyRoleGating();
  calcPreview();
}

// NOTE: resetForm / editEvaluation / handleMainSubmitClick are defined once, further
// down this file, as part of the Official Worksheet (see "Override legacy
// form entry points" — that comment is stale now, there is no legacy version
// to override anymore; this used to be a duplicate declaration that got
// silently shadowed by the later one, which is real but easy to miss in
// JavaScript. Removed here to avoid ~70 lines of dead, misleading code.)

async function submitQualitySection(silent){
  if (!currentEditingEvalId) return;
  const { error } = await sb.from('evaluations').update({
    quality_submitted_at: new Date().toISOString(),
    quality_submitted_by: currentUser?.id || null,
  }).eq('id', currentEditingEvalId);
  if (error) { alert('Submit failed: ' + error.message); return; }
  await loadEvaluations();
  renderAll();
  if (!silent) alert(lang==='th' ? 'ส่งผลด้าน Quality แล้ว' : 'Quality section submitted');
}

async function submitDeliverySection(silent){
  if (!currentEditingEvalId) return;
  const { error } = await sb.from('evaluations').update({
    delivery_submitted_at: new Date().toISOString(),
    delivery_submitted_by: currentUser?.id || null,
  }).eq('id', currentEditingEvalId);
  if (error) { alert('Submit failed: ' + error.message); return; }
  await loadEvaluations();
  renderAll();
  if (!silent) alert(lang==='th' ? 'ส่งผลด้าน Delivery/Purchase แล้ว' : 'Delivery/Purchase section submitted');
}

function renderSubmitStatusNote(){
  const note = document.getElementById('submitStatusNote');
  if (!note) return;
  const e = evaluations.find(x => x.id === currentEditingEvalId);
  if (!e) { note.textContent = ''; return; }
  const qOk = !!e.quality_submitted_at;
  const dOk = !!e.delivery_submitted_at;
  const qLabel = lang==='th' ? 'Quality' : 'Quality';
  const dLabel = lang==='th' ? 'Delivery/Purchase' : 'Delivery/Purchase';
  const yes = lang==='th' ? 'ส่งแล้ว ✓' : 'Submitted ✓';
  const no = lang==='th' ? 'ยังไม่ส่ง' : 'Not submitted';
  let text = `${qLabel}: ${qOk ? yes : no}  |  ${dLabel}: ${dOk ? yes : no}`;
  if (e.status === 'draft' && e.rejection_reason && (!qOk || !dOk)) {
    text += ` — ${L('Last rejected:','ครั้งล่าสุดถูก Reject:')} ${e.rejection_reason}`;
  }
  note.textContent = text;
}

/* ============================================================
   Attachments (evaluations + corrective actions share one table)
   ============================================================ */
let evalAttachments = [];
let caAttachments = [];
const ATTACH_BUCKET = 'attachments';

async function loadEvaluationAttachments(evaluationId){
  const { data, error } = await sb.from('evaluation_attachments').select('*').eq('evaluation_id', evaluationId).order('uploaded_at', { ascending:false });
  if (error) { console.error(error); evalAttachments = []; return; }
  evalAttachments = data || [];
}

async function loadCaAttachments(caId){
  const { data, error } = await sb.from('evaluation_attachments').select('*').eq('corrective_action_id', caId).order('uploaded_at', { ascending:false });
  if (error) { console.error(error); caAttachments = []; return; }
  caAttachments = data || [];
}

function renderAttachTable(el, list){
  if (!list.length) { el.innerHTML = `<div class="empty-note">${lang==='th'?'ยังไม่มีไฟล์แนบ':'No attachments yet'}</div>`; return; }
  el.innerHTML = `<table><tbody>${
    list.map(a => `<tr>
      <td>${a.file_name}</td>
      <td class="muted-small">${a.file_size_bytes ? (a.file_size_bytes/1024).toFixed(0)+' KB' : ''}</td>
      <td class="muted-small">${(a.uploaded_at||'').slice(0,16).replace('T',' ')}</td>
      <td>
        <button class="row-btn" onclick="openAttachment('${a.storage_path}')">${lang==='th'?'เปิด':'Open'}</button>
        ${canDeleteAttachments() ? `<button class="row-btn danger" onclick="deleteAttachment('${a.id}')">${t('del', lang==='th'?'ลบ':'Delete')}</button>` : ''}
      </td>
    </tr>`).join('')
  }</tbody></table>`;
}

function renderEvalAttachList(){ renderAttachTable(document.getElementById('evalAttachList'), evalAttachments); }

async function openAttachment(storagePath){
  const { data, error } = await sb.storage.from(ATTACH_BUCKET).createSignedUrl(storagePath, 60);
  if (error) { alert('Open failed: ' + error.message); console.error(error); return; }
  window.open(data.signedUrl, '_blank');
}

async function deleteAttachment(id){
  if (!confirm(lang==='th' ? 'ลบไฟล์นี้ใช่ไหม?' : 'Delete this file?')) return;
  const row = [...evalAttachments, ...caAttachments].find(a => a.id === id);
  if (row) await sb.storage.from(ATTACH_BUCKET).remove([row.storage_path]);
  const { error } = await sb.from('evaluation_attachments').delete().eq('id', id);
  if (error) { alert('Delete failed: ' + error.message); return; }
  if (row?.evaluation_id) { await loadEvaluationAttachments(row.evaluation_id); renderEvalAttachList(); }
  if (row?.corrective_action_id) {
    await loadCaAttachments(row.corrective_action_id);
    const set = caSets.find(s => s.dbId === row.corrective_action_id);
    if (set) { set.attachments = caAttachments; renderCaSets(); }
  }
}

async function uploadEvaluationAttachment(){
  if (!currentEditingEvalId) { alert(lang==='th' ? 'กรุณาบันทึกผลประเมินก่อน' : 'Please save the evaluation first'); return; }
  const fileInput = document.getElementById('f_attach_file');
  const file = fileInput.files[0];
  if (!file) { alert(lang==='th' ? 'กรุณาเลือกไฟล์' : 'Please choose a file'); return; }
  const path = `evaluations/${currentEditingEvalId}/${Date.now()}_${file.name}`;
  const { error: upErr } = await sb.storage.from(ATTACH_BUCKET).upload(path, file);
  if (upErr) { alert('Upload failed: ' + upErr.message); console.error(upErr); return; }
  const { error: dbErr } = await sb.from('evaluation_attachments').insert({
    evaluation_id: currentEditingEvalId, file_name: file.name, storage_path: path,
    file_size_bytes: file.size, content_type: file.type, uploaded_by: currentUser?.id || null,
  });
  if (dbErr) { alert('Save failed: ' + dbErr.message); console.error(dbErr); return; }
  fileInput.value = '';
  await loadEvaluationAttachments(currentEditingEvalId);
  renderEvalAttachList();
}

async function deleteEvaluation(id){
  const e = evaluations.find(x => x.id === id);
  // Once either department has submitted real data, deleting outright
  // is a bigger deal than deleting an empty, never-touched draft — a
  // plain confirm() is easy to click through without really reading
  // it, so this asks for an actual typed reason instead. This is
  // friction, not a separate permission — anyone who could already
  // delete can still delete, just has to say why for a non-empty one.
  const hasData = !!(e?.quality_submitted_at || e?.delivery_submitted_at);
  if (hasData) {
    const reason = prompt(L('This evaluation has submitted data. Type a reason to confirm deletion:','รายการนี้มีข้อมูลที่ submit ไปแล้ว กรุณาพิมพ์เหตุผลเพื่อยืนยันการลบ:'));
    if (reason === null) return;
    if (!reason.trim()) { alert(L('A reason is required to delete this.','ต้องกรอกเหตุผลก่อนลบรายการนี้')); return; }
  } else {
    if (!confirm(lang==='th' ? 'ต้องการลบรายการนี้ใช่ไหม?' : 'Delete this evaluation?')) return;
  }
  const { error } = await sb.from('evaluations').delete().eq('id', id);
  if (error) { alert('Delete failed: ' + error.message); return; }
  if (currentEditingEvalId === id) { currentEditingEvalId = null; resetForm(); }
  await loadEvaluations();
  await loadCorrectiveActions();
  renderAll();
}

/* ============================================================
   Itemized scoring (Phase 3)
   ============================================================ */
async function updateScoringModeUI(){
  const mode = document.getElementById('f_scoring_mode').value;
  const itemized = mode === 'itemized';
  const hasEvalId = !!currentEditingEvalId;

  document.getElementById('itemizedNeedsSaveHint').style.display = (itemized && !hasEvalId) ? 'block' : 'none';
  document.getElementById('itemizedPanel').style.display = (itemized && hasEvalId) ? 'block' : 'none';

  applyRoleGating(); // aware of scoring mode itself — see applyRoleGating

  if (itemized && hasEvalId) {
    await loadEvaluationItemsFor(currentEditingEvalId);
    renderItemizedChecklist(currentEditingEvalId);
  }
}

function renderItemizedChecklist(evaluationId){
  const el = document.getElementById('itemizedTable');
  const items = evaluationCriteria.filter(c => c.is_active !== false);
  if (!items.length) {
    el.innerHTML = `<div class="empty-note">${lang==='th' ? 'ยังไม่มีหัวข้อประเมินใน Master Control → Evaluation Criteria' : 'No criteria yet — add some in Master Control → Evaluation Criteria'}</div>`;
    return;
  }
  const existing = {};
  evaluationItemsCache.filter(x => x.evaluation_id === evaluationId).forEach(x => { existing[x.criteria_id] = x.occurrence; });

  const catLabel = { quality: lang==='th'?'คุณภาพ':'Quality', delivery: lang==='th'?'การส่งมอบ':'Delivery', purchase: lang==='th'?'ยอดซื้อ':'Purchase' };
  const grouped = { quality: [], delivery: [], purchase: [] };
  items.forEach(c => { if (grouped[c.category]) grouped[c.category].push(c); });

  let html = `<table><thead><tr>
    <th>${lang==='th'?'รหัส':'No.'}</th><th>${lang==='th'?'รายการ':'Item'}</th>
    <th class="num">${lang==='th'?'เต็ม':'Full'}</th><th class="num">${lang==='th'?'หัก/เครดิตต่อครั้ง':'Pts/occurrence'}</th>
    <th class="num">${lang==='th'?'จำนวนครั้ง':'Occurrence'}</th>
  </tr></thead><tbody>`;
  ['quality','delivery','purchase'].forEach(cat => {
    if (!grouped[cat].length) return;
    html += `<tr><td colspan="5" style="background:var(--paper);font-weight:600">${catLabel[cat]}</td></tr>`;
    grouped[cat].forEach(c => {
      const val = existing[c.id] ?? 0;
      html += `<tr>
        <td>${c.item_no}</td>
        <td class="muted-small">${officialDescription(c)}</td>
        <td class="num">${c.full_score ?? '-'}</td>
        <td class="num">${c.deduction_points ?? '-'}</td>
        <td class="num"><input type="number" min="0" step="1" value="${val}" data-criteria-id="${c.id}" class="item-occurrence" style="width:70px"></td>
      </tr>`;
    });
  });
  html += `</tbody></table>`;
  el.innerHTML = html;
}

async function loadEvaluationItemsFor(evaluationId){
  const { data, error } = await sb.from('evaluation_items').select('id, evaluation_id, criteria_id, occurrence').eq('evaluation_id', evaluationId);
  if (error) { console.error(error); showBanner('Load evaluation items failed: ' + error.message); return; }
  evaluationItemsCache = data || [];
}

async function saveItemizedChecklist(){
  if (!currentEditingEvalId) return;
  const rows = Array.from(document.querySelectorAll('.item-occurrence')).map(inp => ({
    evaluation_id: currentEditingEvalId,
    criteria_id: inp.dataset.criteriaId,
    occurrence: toNum(inp.value) || 0,
  }));
  const { error } = await sb.from('evaluation_items').upsert(rows, { onConflict: 'evaluation_id,criteria_id' });
  if (error) { alert('Save failed: ' + error.message); console.error(error); return; }
  // Force a recompute even if every occurrence was 0 (no item rows would
  // otherwise trigger it), so switching to itemized always reflects reality.
  await sb.rpc('recompute_evaluation_scores', { p_evaluation_id: currentEditingEvalId });
  await loadEvaluations();
  await loadEvaluationItemsFor(currentEditingEvalId);
  const e = evaluations.find(x => x.id === currentEditingEvalId);
  if (e) {
    document.getElementById('f_quality').value = e.quality_score;
    document.getElementById('f_delivery').value = e.delivery_score;
    document.getElementById('f_purchase').value = e.purchase_score;
  }
  renderAll();
  updateScoringModeUI();
  alert(lang==='th' ? 'บันทึกและคำนวณคะแนนใหม่แล้ว' : 'Saved and scores recalculated');
}

/* ============================================================
   Rendering — supplier profile
   ============================================================ */
function populateProfileSelect(){
  const groupSel = document.getElementById('profileGroup');
  if (groupSel && groupSel.options.length <= 1) {
    const categories = [...new Set(suppliers.map(s => s.category).filter(Boolean))].sort();
    groupSel.innerHTML = `<option value="" data-i18n="allCategories">${t('allCategories','All Categories')}</option>` +
      categories.map(c => `<option value="${escapeHtml(c)}">${escapeHtml(c)}</option>`).join('');
  }
  const group = groupSel?.value || '';
  const filtered = group ? suppliers.filter(s => s.category === group) : suppliers;

  const sel = document.getElementById('profileSupplier');
  const prev = sel.value;
  sel.innerHTML = filtered.map(s => `<option value="${s.id}">${s.code} — ${s.short_name || s.name}</option>`).join('');
  if (prev && filtered.some(s => s.id === prev)) sel.value = prev;
}

function renderProfile(){
  const sel = document.getElementById('profileSupplier');
  // Default pick: prefer a supplier from the currently-listed options
  // that actually HAS evaluation history — picking blindly from the
  // top of the list often landed on one with zero history, making the
  // trend chart look broken/empty when nothing was actually wrong.
  let id = sel.value;
  if (!id) {
    const listedIds = new Set([...sel.options].map(o => o.value));
    const withHistory = evaluations.find(e => listedIds.has(e.supplier?.id))?.supplier?.id;
    id = withHistory || sel.options[0]?.value;
  }
  if (!id) { document.getElementById('profileInfo').innerHTML = `<div class="empty-note">${t('noData','No data')}</div>`; return; }
  sel.value = id;
  const supplier = suppliers.find(s => s.id === id);
  const hist = evaluations.filter(e => e.supplier?.id === id).sort((a,b) => a.year - b.year || a.month - b.month);
  const hist12 = hist.slice(-12); // chart only — the table below still lists full history

  const info = document.getElementById('profileInfo');
  if (!supplier) { info.innerHTML = `<div class="empty-note">${t('noData','No data')}</div>`; return; }
  const rowsHtml = hist.length
    ? `<table><tr><th>${lang==='th'?'เดือน-ปี':'Month-Year'}</th><th class="num">${lang==='th'?'รวม':'Total'}</th><th>${lang==='th'?'เกรด':'Grade'}</th><th>${lang==='th'?'หมายเหตุ':'Comment'}</th></tr>${
      hist.map(x => `<tr><td class="nowrap">${ymLabel(x.year, x.month)}</td><td class="num">${scoreNum(x.total_score)}%${x.shipment_status==='no_shipment' ? `<br><span class="muted-small">${t('shipmentNone','No Shipment')}</span>` : ''}</td><td>${gradeBadge(x.grade)}</td><td class="cell-truncate" title="${escapeHtml([x.quality_comment,x.delivery_comment].filter(Boolean).join(' | '))}">${escapeHtml([x.quality_comment,x.delivery_comment].filter(Boolean).join(' | ')||'-')}</td></tr>`).join('')
    }</table>`
    : `<div class="empty-note">${t('noData','No evaluation history yet')}</div>`;

  // Show what the carried-forward score actually MEANS (the matching
  // Purchase-tier criteria's own description, e.g. "100,000-999,999
  // Pcs or 5,000-9,999 Kgs") rather than a bare number nobody can
  // interpret on sight — reverse-lookup by matching deduction_points,
  // since the three Purchase tiers (C-1/C-2/C-3) each have a distinct,
  // fixed point value.
  const tierCriteria = evaluationCriteria.find(c => c.category === 'purchase' && toNum(c.deduction_points) === toNum(supplier.last_purchase_score));
  const orderVolumeText = supplier.last_purchase_score != null
    ? (tierCriteria ? officialDescription(tierCriteria) : `${scoreNum(supplier.last_purchase_score)} / 10`)
    : L('No shipment data recorded yet','ยังไม่มีข้อมูลการสั่งซื้อ');

  const groupColor = { Material:'accent', Outsource:'warn', 'Blank Part':'good' }[supplier.category] || 'accent';
  const initials = (supplier.short_name || supplier.name || '?').trim().slice(0,2).toUpperCase();

  info.innerHTML = `
    <div class="profile-zone profile-zone-header">
      <div class="profile-avatar profile-avatar-${groupColor}">${escapeHtml(initials)}</div>
      <div>
        <h3>${escapeHtml(supplier.name)}</h3>
        <div class="profile-tags">
          <span class="badge status mono">${escapeHtml(supplier.code)}</span>
          ${supplier.category ? `<span class="badge status">${escapeHtml(supplier.category)}</span>` : ''}
          ${supplier.is_active === false ? `<span class="badge risk">${L('Inactive','ปิดใช้งาน')}</span>` : ''}
        </div>
      </div>
    </div>
    <div class="profile-zone profile-contact-grid">
      <div><span class="profile-field-label">${lang==='th'?'ผู้ติดต่อ':'Attention'}</span><b>${escapeHtml(supplier.attention || '-')}</b></div>
      <div><span class="profile-field-label">Tel</span><b>${escapeHtml(supplier.tel || '-')}</b></div>
      <div><span class="profile-field-label">${L('Target Score','เป้าหมายคะแนน')}</span><b>${supplier.target_score ?? 80}%</b></div>
      <div><span class="profile-field-label">${L('Order Volume from E&H','ปริมาณการสั่งซื้อจาก E&H')}</span><b>${escapeHtml(orderVolumeText)}</b>${supplier.last_purchase_period ? `<br><span class="muted-small">${L('as of','ข้อมูลล่าสุดเดือน')} ${supplier.last_purchase_period}</span>` : ''}</div>
    </div>`;
  const histZone = document.getElementById('profileHistoryZone');
  if (histZone) histZone.innerHTML = rowsHtml;

  renderProfileCaList(id);

  drawBar(
    document.getElementById('trendChart'),
    hist12.map(x => ymLabel(x.year, x.month)),
    hist12.map(x => toNum(x.total_score)),
    (i,v) => v < 80 ? '#A23B3B' : '#0E6E66'
  );
}

// Real data (not mocked) — this supplier's Corrective Actions, reusing
// the same correctiveActions the rest of the app already loads.
function renderProfileCaList(supplierId){
  const el = document.getElementById('profileCaList');
  if (!el) return;
  const rows = correctiveActions.filter(c => c.evaluation?.supplier?.id === supplierId)
    .sort((a,b) => (b.evaluation?.year - a.evaluation?.year) || (b.evaluation?.month - a.evaluation?.month));
  if (!rows.length) { el.innerHTML = `<div class="empty-note">${t('noData','No data yet')}</div>`; return; }
  const H = lang==='th' ? ['เดือน','เกรด','Problem','สถานะ','จัดการ'] : ['Month','Grade','Problem','Status','Action'];
  el.innerHTML = `<table><thead><tr>${H.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${
    rows.map(c => `<tr>
      <td class="nowrap">${c.evaluation ? ymLabel(c.evaluation.year, c.evaluation.month) : '-'}</td>
      <td>${c.evaluation ? gradeBadge(c.evaluation.grade) : '-'}</td>
      <td class="muted-small">${escapeHtml(c.problem) || '-'}</td>
      <td><span class="badge status">${caStatusLabel(c.status)}</span></td>
      <td><button class="row-btn" onclick="editCorrectiveAction('${c.id}')">${t('edit', lang==='th'?'แก้ไข':'Edit')}</button></td>
    </tr>`).join('')
  }</tbody></table>`;
}

/* ============================================================
   Rendering — report preview
   ============================================================ */
function populateReportCategoryFilter(){
  const sel = document.getElementById('rp_category');
  if (!sel || sel.options.length > 1) return; // populate once — categories don't change during a session
  const categories = [...new Set(suppliers.map(s => s.category).filter(Boolean))].sort();
  sel.innerHTML = `<option value="">${t('allCategories','All Categories')}</option>` +
    categories.map(c => `<option value="${escapeHtml(c)}">${escapeHtml(c)}</option>`).join('');
}

function populateReportSupplierFilter(){
  const catSel = document.getElementById('rp_category');
  const sel = document.getElementById('rp_supplier');
  const prev = sel.value;
  const cat = catSel?.value || '';
  // Only suppliers that actually have at least one evaluation — no
  // point offering a supplier with nothing to show a report for.
  const suppliersWithData = new Set(evaluations.map(e => e.supplier?.id));
  const filtered = suppliers.filter(s => (!cat || s.category === cat) && suppliersWithData.has(s.id));
  sel.innerHTML = filtered.map(s => `<option value="${s.id}">${s.code} — ${s.short_name||s.name}</option>`).join('');
  if (prev && filtered.some(s => s.id === prev)) sel.value = prev;
}

function populateReportYearFilter(){
  const supplierId = document.getElementById('rp_supplier')?.value;
  const sel = document.getElementById('rp_year');
  const prev = sel.value;
  const years = [...new Set(evaluations.filter(e => e.supplier?.id === supplierId).map(e => e.year))].sort((a,b) => b-a);
  sel.innerHTML = years.map(y => `<option value="${y}">${y}</option>`).join('');
  if (prev && years.includes(toNum(prev))) sel.value = prev;
}

function populateReportSelect(){
  const supplierId = document.getElementById('rp_supplier')?.value;
  const year = toNum(document.getElementById('rp_year')?.value);
  const sel = document.getElementById('reportSelect');
  const prev = sel.value;
  const filtered = evaluations.filter(e => e.supplier?.id === supplierId && e.year === year).sort((a,b) => a.month-b.month);
  sel.innerHTML = filtered.map(e => `<option value="${e.id}">${monthName(e.month)} — ${e.grade} (${e.total_score}%)</option>`).join('');
  if (prev && filtered.some(e => e.id === prev)) sel.value = prev;
}

// Runs the whole chain top-to-bottom, keeping each level's selection
// where possible and only resetting the levels below whichever one
// actually changed.
function refreshReportCascade(){
  populateReportCategoryFilter();
  populateReportSupplierFilter();
  populateReportYearFilter();
  populateReportSelect();
}

/* ============================================================
   Phase 7 — Yearly Summary (equivalent to the old Excel Summary Mat/Part sheet)
   ============================================================ */
function populateYearlyCategoryFilter(){
  const sel = document.getElementById('ys_category');
  if (!sel) return;
  const cats = Array.from(new Set(allSuppliers.map(s => s.category).filter(Boolean))).sort();
  const prev = sel.value;
  sel.innerHTML = `<option value="" data-i18n="allCategories">${t('allCategories','All Categories')}</option>` +
    cats.map(c => `<option value="${c}">${c}</option>`).join('');
  sel.value = prev;
}

function renderYearlySummary(){
  const el = document.getElementById('yearlySummaryTable');
  if (!el) return;
  const year = toNum(document.getElementById('ys_year').value) || new Date().getFullYear();
  const categoryFilter = document.getElementById('ys_category').value;

  let rows = allSuppliers.filter(s => s.is_active !== false);
  if (categoryFilter) rows = rows.filter(s => s.category === categoryFilter);
  rows = [...rows].sort((a,b) => (a.code||'').localeCompare(b.code||''));

  if (!rows.length) { el.innerHTML = `<div class="empty-note">${t('noData','No data yet')}</div>`; return; }

  const byKey = {};
  evaluations.forEach(e => {
    if (e.year !== year) return;
    byKey[`${e.supplier?.id}-${e.month}`] = e;
  });

  const monthHeads = Array.from({length:12}, (_,i) => monthName(i+1));
  const H = [lang==='th'?'รหัส':'Code', lang==='th'?'ชื่อ':'Name', ...monthHeads, lang==='th'?'เฉลี่ย YTD':'YTD Avg', lang==='th'?'เกรด':'Grade'];

  el.innerHTML = `<table><thead><tr>${H.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${
    rows.map(s => {
      const monthCells = [];
      const scores = [];
      for (let m=1; m<=12; m++){
        const e = byKey[`${s.id}-${m}`];
        if (e) { scores.push(toNum(e.total_score)); monthCells.push(`<td class="num"><button class="cell-link" onclick="editEvaluation('${e.id}')" title="${L('Open this evaluation','เปิดผลประเมินนี้')}">${scoreNum(e.total_score)}<br><span class="muted-small">${e.grade}</span></button></td>`); }
        else monthCells.push(`<td class="num muted-small">-</td>`);
      }
      const avg = scores.length ? (scores.reduce((a,b)=>a+b,0)/scores.length) : null;
      return `<tr>
        <td><b>${s.code}</b></td>
        <td class="muted-small">${s.short_name||s.name}</td>
        ${monthCells.join('')}
        <td class="num"><b>${avg!==null ? scoreNum(avg)+'%' : '-'}</b></td>
        <td>${avg!==null ? gradeBadge(gradeOf(avg)) : '-'}</td>
      </tr>`;
    }).join('')
  }</tbody></table>`;
}

function renderReport(){
  const sel = document.getElementById('reportSelect');
  const id = sel.value || (evaluations[0] && evaluations[0].id);
  const box = document.getElementById('reportBox');
  if (!id) { box.innerHTML = `<div class="empty-note">${t('noData','No data')}</div>`; return; }
  sel.value = id;
  const e = evaluations.find(x => x.id === id);
  if (!e) { box.innerHTML = `<div class="empty-note">${t('noData','No data')}</div>`; return; }
  box.classList.add('rich');
  const th = lang === 'th';
  const noShip = e.shipment_status === 'no_shipment';
  const fmtDt = v => v ? new Date(v).toLocaleDateString(th ? 'th-TH' : 'en-GB', {day:'2-digit',month:'short',year:'numeric'}) : '';
  const esc = v => String(v == null ? '' : v).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

  // --- score bars (Quality 50 / Delivery 40 / Purchase 10) ---
  const bar = (label, got, full, na) => {
    if (na) return `<div class="rpt-bar"><span>${label}</span><span class="track"></span><b>N/A</b></div>`;
    const pct = full ? Math.max(0, Math.min(100, toNum(got) / full * 100)) : 0;
    const cls = pct >= 90 ? '' : pct >= 70 ? 'warn' : 'bad';
    return `<div class="rpt-bar"><span>${label}</span><span class="track"><span class="fill ${cls}" style="width:${pct}%"></span></span><b>${toNum(got)}/${full}</b></div>`;
  };

  // --- 12-month history of this supplier (inline SVG sparkline) ---
  const hist = evaluations.filter(x => x.supplier?.id === e.supplier?.id)
    .sort((a,b) => (a.year*12+a.month) - (b.year*12+b.month)).slice(-12);
  let spark = `<div class="rpt-empty">${th ? 'ยังไม่มีประวัติเพียงพอ' : 'Not enough history yet'}</div>`;
  if (hist.length >= 2) {
    const W = 360, H = 96, pl = 24, pr = 8, pt = 8, pb = 16;
    const x = i => pl + i * ((W - pl - pr) / (hist.length - 1));
    const y = v => pt + (H - pt - pb) * (1 - (Math.max(50, Math.min(100, v)) - 50) / 50);
    const pts = hist.map((h,i) => `${x(i).toFixed(1)},${y(toNum(h.total_score)).toFixed(1)}`).join(' ');
    const cur = hist.findIndex(h => h.id === e.id);
    spark = `<svg class="rpt-spark" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="trend">
      <line x1="${pl}" x2="${W-pr}" y1="${y(80)}" y2="${y(80)}" stroke="#c99a39" stroke-dasharray="3 3"/>
      <text x="2" y="${y(80)+3}" font-size="9" fill="#8a9096">80</text>
      <polyline points="${pts}" fill="none" stroke="#0e6e66" stroke-width="2" vector-effect="non-scaling-stroke"/>
      ${hist.map((h,i) => `<circle cx="${x(i)}" cy="${y(toNum(h.total_score))}" r="${i===cur?4.5:2.6}" fill="${i===cur?'#0e6e66':'#fff'}" stroke="#0e6e66" stroke-width="1.5" vector-effect="non-scaling-stroke"/>`).join('')}
      <text x="${pl}" y="${H-3}" font-size="9" fill="#5b6470">${ymLabel(hist[0].year, hist[0].month)}</text>
      <text x="${W-pr}" y="${H-3}" font-size="9" fill="#5b6470" text-anchor="end">${ymLabel(hist[hist.length-1].year, hist[hist.length-1].month)}</text>
    </svg>`;
  }
  const avg12 = hist.length ? hist.reduce((s,h) => s + toNum(h.total_score), 0) / hist.length : null;

  // --- rank among all suppliers evaluated in the same month ---
  const peers = evaluations.filter(x => x.year === e.year && x.month === e.month).sort((a,b) => toNum(b.total_score) - toNum(a.total_score));
  const rank = peers.findIndex(x => x.id === e.id) + 1;

  // --- approval timeline ---
  const steps = [
    [th?'QA ส่งส่วน Quality':'Quality submitted', e.quality_submitted_at],
    [th?'MP/CS ส่งส่วน Delivery/Purchase':'Delivery/Purchase submitted', e.delivery_submitted_at],
    [th?'Supervisor อนุมัติ':'Supervisor approved', e.sup_approved_at],
    [th?'Manager อนุมัติ':'Manager approved', e.mgr_approved_at],
    [th?'ส่งผลให้ Supplier':'Sent to supplier', e.sent_at],
  ];
  const timeline = `<ul class="rpt-timeline">${steps.map(([l,v]) => `<li class="${v?'done':''}"><i></i><span>${l}</span><span class="t">${v ? fmtDt(v) : '—'}</span></li>`).join('')}</ul>`;

  // --- corrective actions ---
  const cas = caForEval(e);
  const caHtml = cas.length
    ? cas.map(c => `<div style="margin-bottom:8px"><b>${esc(c.problem || c.problem_description || '-')}</b><div class="rpt-sub muted-small">${caStatusLabel(c.status)}${c.due_date ? ' · ' + (th?'กำหนด ':'due ') + fmtDt(c.due_date) : ''}</div></div>`).join('')
    : `<div class="rpt-empty">${['C','D'].includes(e.grade) ? (th?'ยังไม่มี Corrective Action':'No Corrective Action yet') : (th?'ไม่ต้องมี Corrective Action (เกรด A/B)':'Not required (Grade A/B)')}</div>`;

  const status = evalWorkflowStatus(e);
  box.innerHTML = `
    <div class="rpt-hero">
      <div class="rpt-grade ${e.grade}">${e.grade}</div>
      <div>
        <h2>${th ? 'รายงานประเมิน Supplier' : 'Supplier Evaluation Report'}</h2>
        <div><b>${esc(e.supplier?.name)}</b> <span class="muted-small">(${esc(e.supplier?.code)})</span></div>
        <div class="rpt-sub">${ymLabel(e.year, e.month)} · ${status.label}${noShip ? ' · ' + t('shipmentNone','No Shipment') : ''}</div>
      </div>
      <div class="rpt-score"><b>${e.total_score}%</b><span>${noShip ? `${t('rawScoreLabel','Raw')} ${e.raw_score}/${e.applicable_weight}` : (th?'คะแนนรวม':'Total score')}</span></div>
    </div>

    <div class="rpt-grid">
      <div class="rpt-card">
        <h3>${th?'คะแนนแยกหมวด':'Score by category'}</h3>
        ${bar(th?'คุณภาพ':'Quality', e.quality_score, 50)}
        ${bar(th?'การส่งมอบ':'Delivery', e.delivery_score, 40, noShip)}
        ${bar(th?'ยอดซื้อ':'Purchase', e.purchase_score, 10, noShip)}
        ${noShip ? `<p class="muted-small" style="margin:6px 0 0"><b>${t('noShipReason','Reason for No Shipment')}:</b> ${esc(e.no_shipment_reason) || '-'}</p>` : ''}
        <p class="muted-small" style="margin:10px 0 0">${th?'เกณฑ์เกรด':'Grade criteria'}: A = 100 &nbsp; B = 80–99 &nbsp; C = 70–79 &nbsp; D &lt; 70</p>
      </div>
      <div class="rpt-card">
        <h3>${th?'ข้อมูล Supplier':'Supplier details'}</h3>
        <dl class="rpt-kv">
          <dt>${th?'ชื่อบริษัท':'Company'}</dt><dd>${esc(e.supplier?.name)}</dd>
          <dt>Attention</dt><dd>${esc(e.supplier?.attention) || '-'}</dd>
          <dt>Tel</dt><dd>${esc(e.supplier?.tel) || '-'}</dd>
          <dt>${th?'อันดับเดือนนี้':'Rank this month'}</dt><dd>${rank ? `${rank} / ${peers.length}` : '-'}</dd>
          <dt>${th?'เฉลี่ย 12 เดือน':'12-mo average'}</dt><dd>${avg12 != null ? scoreNum(avg12) + '%' : '-'}</dd>
        </dl>
      </div>
    </div>

    <div class="rpt-grid">
      <div class="rpt-card"><h3>${th?'แนวโน้ม 12 เดือนของ Supplier นี้':'12-month trend — this supplier'}</h3>${spark}</div>
      <div class="rpt-card"><h3>${th?'สถานะการอนุมัติ':'Approval trail'}</h3>${timeline}</div>
    </div>

    <div class="rpt-grid">
      <div class="rpt-card"><h3>${th?'รายการที่ถูกหักคะแนน':'Deductions'}</h3><div id="rptDeductions"><div class="rpt-empty">${th?'กำลังโหลด…':'Loading…'}</div></div></div>
      <div class="rpt-card"><h3>Corrective Action</h3>${caHtml}</div>
    </div>

    <div class="rpt-card">
      <h3>${th?'หมายเหตุ':'Comments'}</h3>
      <dl class="rpt-kv"><dt>${th?'คุณภาพ':'Quality'}</dt><dd>${esc(e.quality_comment) || '-'}</dd>
      <dt>${th?'การส่งมอบ':'Delivery'}</dt><dd>${esc(e.delivery_comment) || '-'}</dd></dl>
    </div>`;

  // Deductions load asynchronously (items are fetched per evaluation); guard against a newer selection.
  sb.from('evaluation_items').select('criteria_id, occurrence').eq('evaluation_id', e.id).then(({ data, error }) => {
    const target = document.getElementById('rptDeductions');
    if (!target || sel.value !== e.id) return;
    if (error) { target.innerHTML = `<div class="rpt-empty">${esc(error.message)}</div>`; return; }
    const rows = (data || []).filter(r => toNum(r.occurrence) > 0).map(r => {
      const c = evaluationCriteria.find(k => k.id === r.criteria_id);
      if (!c || String(c.category || '').toLowerCase().startsWith('purchase')) return null;
      const desc = th && c.description_th ? c.description_th : c.description;
      return { code: `${c.category || ''} ${c.item_no || ''}`.trim(), desc, n: toNum(r.occurrence), pts: toNum(c.deduction_points) * toNum(r.occurrence) };
    }).filter(Boolean);
    target.innerHTML = rows.length
      ? `<table class="rpt-ded"><tr><th>${th?'ข้อ':'Item'}</th><th>${th?'รายละเอียด':'Description'}</th><th class="num">${th?'ครั้ง':'×'}</th><th class="num">${th?'หัก':'Pts'}</th></tr>${rows.map(r => `<tr><td>${esc(r.code)}</td><td>${esc(r.desc)}</td><td class="num">${r.n}</td><td class="num">-${r.pts}</td></tr>`).join('')}</table>`
      : `<div class="rpt-empty">${th?'ไม่มีรายการหักคะแนน (หรือเป็นข้อมูลนำเข้าแบบสรุป)':'No deductions recorded (or imported as a summary score)'}</div>`;
  });
}

/* ============================================================
   Rendering — corrective actions
   ============================================================ */
function isCaOverdue(ca){
  return ca.due_date && ca.status !== 'closed' && ca.due_date < todayIso();
}
function todayIso(){ return new Date().toISOString().slice(0,10); }

let caEvalFilterDefaultApplied = false;
function populateCaEvalSelect(){
  const sel = document.getElementById('ca_evaluation');
  const prev = sel.value;

  // Default year/month to the latest period with data, same idea as
  // the Evaluation List's default filter — only ever applied once,
  // and only if the user hasn't already typed something in.
  const yrInput = document.getElementById('ca_ev_filter_year');
  const moInput = document.getElementById('ca_ev_filter_month');
  if (!caEvalFilterDefaultApplied && evaluations.length && yrInput && moInput && !yrInput.value && !moInput.value) {
    const latest = [...evaluations].sort((a,b) => (b.year*12+b.month) - (a.year*12+a.month))[0];
    if (latest) { yrInput.value = latest.year; moInput.value = latest.month; }
    caEvalFilterDefaultApplied = true;
  }

  const txt = (document.getElementById('ca_ev_filter_supplier')?.value || '').toLowerCase();
  const yr = yrInput?.value;
  const mo = moInput?.value;
  const showAllGrades = document.getElementById('ca_ev_filter_allgrades')?.checked;
  let arr = [...evaluations];
  // A Corrective Action only ever makes sense against a Grade C/D
  // evaluation (that's the whole reason one exists — see caHint on
  // this page) — filter to that by default so this picker can't be
  // used to attach a CA to the wrong evaluation by mistake. The
  // checkbox is there for the rare real exception.
  if (!showAllGrades) arr = arr.filter(e => ['C','D'].includes(e.grade));
  if (txt) arr = arr.filter(e => `${e.supplier?.code} ${e.supplier?.name} ${e.supplier?.short_name}`.toLowerCase().includes(txt));
  if (yr) arr = arr.filter(e => e.year === toNum(yr));
  if (mo) arr = arr.filter(e => e.month === toNum(mo));
  const sorted = arr.sort((a,b) => (b.year-a.year) || (b.month-a.month));
  sel.innerHTML = sorted.map(e =>
    `<option value="${e.id}">${e.year}-${monthName(e.month)} | ${e.supplier?.code||''} | ${e.supplier?.short_name||e.supplier?.name||''} | ${e.grade} (${e.total_score}%)</option>`
  ).join('');
  if (prev && sorted.some(e => e.id === prev)) sel.value = prev;
}

function caStatusLabel(s){
  const map = { open:'ca_st_open', in_progress:'ca_st_progress', closed:'ca_st_closed', overdue:'ca_st_overdue' };
  return t(map[s] || 'ca_st_open', s);
}

// ------------------------------------------------------------
// Corrective Action editor — one shared component for both flows:
// creating one or more new CAs against the same Evaluation (one
// "set" of fields per problem, "+" adds another, one Save inserts
// them all), and editing a single already-existing CA (opens with
// exactly one, non-removable set, same card markup). caEditorMode
// distinguishes the two; caSets holds the set objects currently on
// screen. Typed field values live in the DOM (read via
// syncCaSetsFromDom before any structural change); caSets itself
// tracks each set's DB id (null = not saved yet) and its
// attachments/pendingFiles, which the DOM can't hold across renders.
// ------------------------------------------------------------
let caSets = [];
let caEditorMode = 'create';
let caSetSeq = 0;

function makeEmptyCaSet(){
  caSetSeq++;
  return { localKey:'new-'+caSetSeq, dbId:null, problem:'', root_cause:'', action:'', responsible_person:'',
    start_date: todayIso(), due_date:'', finished_date:'', status:'open', attachments:[], pendingFiles:[] };
}
function caSetFromRow(ca){
  return { localKey:ca.id, dbId:ca.id, problem:ca.problem||'', root_cause:ca.root_cause||'', action:ca.action||'',
    responsible_person:ca.responsible_person||'', start_date:ca.start_date||'', due_date:ca.due_date||'',
    finished_date:ca.finished_date||'', status:ca.status||'open', attachments:[], pendingFiles:[] };
}
// Reads whatever's currently typed in each rendered set's fields back
// into caSets — must run before any add/remove/re-render, or the
// structural change would wipe unsaved text in the other sets.
function syncCaSetsFromDom(){
  caSets.forEach((set, idx) => {
    const card = document.querySelector(`.ca-set-card[data-ca-set-idx="${idx}"]`);
    if (!card) return;
    ['problem','root_cause','action','responsible_person','start_date','due_date','finished_date','status'].forEach(f => {
      const el = card.querySelector(`[data-ca-field="${f}"]`);
      if (el) set[f] = el.value;
    });
  });
}
function escAttr(s){ return String(s ?? '').replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;'); }

function caSetAttachHtml(set, idx){
  if (set.dbId) {
    if (!set.attachments.length) return `<div class="empty-note">${L('No attachments yet','ยังไม่มีไฟล์แนบ')}</div>`;
    return `<table><tbody>${set.attachments.map(a => `<tr>
      <td>${a.file_name}</td>
      <td class="muted-small">${a.file_size_bytes ? (a.file_size_bytes/1024).toFixed(0)+' KB' : ''}</td>
      <td class="muted-small">${(a.uploaded_at||'').slice(0,16).replace('T',' ')}</td>
      <td>
        <button type="button" class="row-btn" onclick="openAttachment('${a.storage_path}')">${L('Open','เปิด')}</button>
        ${canDeleteAttachments() ? `<button type="button" class="row-btn danger" onclick="deleteAttachment('${a.id}')">${L('Delete','ลบ')}</button>` : ''}
      </td>
    </tr>`).join('')}</tbody></table>`;
  }
  if (!set.pendingFiles.length) return `<div class="empty-note">${L('No files yet — attaches after you Save','ยังไม่มีไฟล์ (จะอัปโหลดหลังกด Save)')}</div>`;
  return `<table><tbody>${set.pendingFiles.map((f,fi) => `<tr>
    <td>${f.name}</td>
    <td class="muted-small">${(f.size/1024).toFixed(0)} KB</td>
    <td class="muted-small">${L('Pending — uploads on Save','รอ Save')}</td>
    <td><button type="button" class="row-btn danger" onclick="removeCaSetPendingFile(${idx},${fi})">${L('Remove','ลบ')}</button></td>
  </tr>`).join('')}</tbody></table>`;
}
function caSetCardHtml(set, idx, removable){
  const statusEnLabels = { open:'Open', in_progress:'In Progress', closed:'Closed', overdue:'Overdue (manual)' };
  const statusOptions = ['open','in_progress','closed','overdue'].map(s =>
    `<option value="${s}" ${set.status===s?'selected':''} data-i18n="ca_st_${s}">${statusEnLabels[s]}</option>`).join('');
  return `<div class="ca-set-card" data-ca-set-idx="${idx}">
    <div class="ca-set-head">
      <b>${L('Problem','ปัญหา')} ${idx+1}</b>
      ${removable ? `<button type="button" class="row-btn danger" onclick="removeCaSet(${idx})">${L('Remove this problem','ลบรายการนี้')}</button>` : ''}
    </div>
    <div class="form-grid">
      <div class="field"><label data-i18n="caProblem">Problem</label><input data-ca-field="problem" type="text" value="${escAttr(set.problem)}"></div>
      <div class="field"><label data-i18n="caRootCause">Root Cause</label><input data-ca-field="root_cause" type="text" value="${escAttr(set.root_cause)}"></div>
      <div class="field"><label data-i18n="caAction">Corrective Action</label><input data-ca-field="action" type="text" value="${escAttr(set.action)}"></div>
      <div class="field"><label data-i18n="caResponsible">Responsible Person</label><input data-ca-field="responsible_person" type="text" value="${escAttr(set.responsible_person)}"></div>
      <div class="field"><label data-i18n="caStartDate">Start Date</label><input data-ca-field="start_date" type="date" value="${set.start_date||''}"></div>
      <div class="field"><label data-i18n="caDueDate">Due Date</label><input data-ca-field="due_date" type="date" value="${set.due_date||''}"></div>
      <div class="field"><label data-i18n="caFinishedDate">Finished Date</label><input data-ca-field="finished_date" type="date" value="${set.finished_date||''}"></div>
      <div class="field"><label data-i18n="caStatus">Status</label><select data-ca-field="status">${statusOptions}</select></div>
    </div>
    <div class="ca-set-attach">
      <label data-i18n="attachTitle">Attachments</label>
      <div class="actions-row">
        <input type="file" data-ca-file-input>
        <button type="button" class="btn ghost" onclick="addCaSetFile(${idx})">${L('Upload','อัปโหลด')}</button>
      </div>
      <div class="table-wrap">${caSetAttachHtml(set, idx)}</div>
    </div>
  </div>`;
}
function renderCaSets(){
  const container = document.getElementById('caSetsContainer');
  if (!container) return;
  const removable = caEditorMode === 'create' && caSets.length > 1;
  container.innerHTML = caSets.map((set, idx) => caSetCardHtml(set, idx, removable)).join('');
  const btnAdd = document.getElementById('btnCaAddSet');
  if (btnAdd) btnAdd.style.display = caEditorMode === 'create' ? 'inline-flex' : 'none';
  const btnMarkReceived = document.getElementById('btnCaMarkReceived');
  if (btnMarkReceived) btnMarkReceived.style.display = caEditorMode === 'edit' ? 'inline-flex' : 'none';
  applyLang();
  applyCaRoleGating();
}
function addCaSet(){
  if (!caUserCanCreate()) return;
  syncCaSetsFromDom();
  caSets.push(makeEmptyCaSet());
  renderCaSets();
}
function removeCaSet(idx){
  syncCaSetsFromDom();
  caSets.splice(idx, 1);
  renderCaSets();
}
function removeCaSetPendingFile(idx, fileIdx){
  syncCaSetsFromDom();
  caSets[idx].pendingFiles.splice(fileIdx, 1);
  renderCaSets();
}
async function uploadFileToCa(caId, file){
  const path = `corrective_actions/${caId}/${Date.now()}_${file.name}`;
  const { error: upErr } = await sb.storage.from(ATTACH_BUCKET).upload(path, file);
  if (upErr) { alert('Upload failed: ' + upErr.message); console.error(upErr); return false; }
  const { error: dbErr } = await sb.from('evaluation_attachments').insert({
    corrective_action_id: caId, file_name: file.name, storage_path: path,
    file_size_bytes: file.size, content_type: file.type, uploaded_by: currentUser?.id || null,
  });
  if (dbErr) { alert('Save failed: ' + dbErr.message); console.error(dbErr); return false; }
  return true;
}
function addCaSetFile(idx){
  const card = document.querySelector(`.ca-set-card[data-ca-set-idx="${idx}"]`);
  const fileInput = card?.querySelector('[data-ca-file-input]');
  const file = fileInput?.files[0];
  if (!file) { alert(L('Please choose a file','กรุณาเลือกไฟล์')); return; }
  syncCaSetsFromDom();
  const set = caSets[idx];
  if (set.dbId) {
    // Already-saved record (edit mode) — nothing to wait on, upload now.
    uploadFileToCa(set.dbId, file).then(ok => {
      if (!ok) return;
      loadCaAttachments(set.dbId).then(() => { set.attachments = caAttachments; renderCaSets(); });
    });
  } else {
    // New, unsaved set — stage it; actually uploads once Save creates the row.
    set.pendingFiles.push(file);
    renderCaSets();
  }
}

function caUserCanCreate(){
  return hasPerm('ca_create');
}
function caUserCanFullEdit(){
  return hasPerm('ca_edit_full');
}
function caUserCanRestrictedEdit(){
  return hasPerm('ca_edit_restricted');
}
function caUserCanClose(){
  return hasPerm('ca_close');
}
function canDeleteAttachments(){
  return hasPerm('attachment_delete');
}

function applyCaRoleGating(){
  const fullEdit = caUserCanFullEdit();
  const restrictedEdit = caUserCanRestrictedEdit();
  const creating = caEditorMode === 'create';

  const restrictedFields = ['problem','responsible_person','start_date','due_date','finished_date','status'];
  const qaEditableFields = ['root_cause','action'];

  let evalEditable, restrictedEditable, qaEditableNow;
  if (fullEdit) {
    evalEditable = restrictedEditable = qaEditableNow = true;
  } else if (creating) {
    const canCreate = caUserCanCreate();
    evalEditable = restrictedEditable = qaEditableNow = canCreate;
  } else if (restrictedEdit) {
    evalEditable = false; restrictedEditable = false; qaEditableNow = true;
  } else {
    evalEditable = restrictedEditable = qaEditableNow = false;
  }

  const evalSel = document.getElementById('ca_evaluation');
  if (evalSel) evalSel.disabled = !evalEditable;

  document.querySelectorAll('.ca-set-card').forEach(card => {
    restrictedFields.forEach(f => { const el = card.querySelector(`[data-ca-field="${f}"]`); if (el) el.disabled = !restrictedEditable; });
    qaEditableFields.forEach(f => { const el = card.querySelector(`[data-ca-field="${f}"]`); if (el) el.disabled = !qaEditableNow; });
  });

  const btnAdd = document.getElementById('btnCaAddSet');
  if (btnAdd) btnAdd.disabled = !creating || !caUserCanCreate();

  const btnSave = document.getElementById('btnCaSave');
  if (btnSave) btnSave.disabled = creating ? !caUserCanCreate() : !(fullEdit || restrictedEdit);

  // "Mark Received Countermeasure" — closes the case. Only makes sense
  // on an already-created, still-open case, for whoever has ca_close
  // (full-edit roles always can; QA specifically via ca_close).
  const btnMarkReceived = document.getElementById('btnCaMarkReceived');
  if (btnMarkReceived) {
    const dbId = !creating ? caSets[0]?.dbId : null;
    const ca = dbId ? correctiveActions.find(c => c.id === dbId) : null;
    const alreadyClosed = ca?.status === 'closed';
    const canClose = fullEdit || (restrictedEdit && caUserCanClose());
    btnMarkReceived.disabled = creating || !ca || alreadyClosed || !canClose;
  }
}

function resetCaForm(){
  caEditorMode = 'create';
  caSets = [ makeEmptyCaSet() ];
  renderCaSets();
}
// Jumps straight to the CA editor with a specific evaluation already
// selected — used by the "grade C/D but no CA yet" quick-fix button in
// the Evaluation List, so fixing a missing CA doesn't require finding
// the right evaluation again in the generic picker.
function createCaForEvaluation(evaluationId){
  resetCaForm();
  showTab('ca');
  // Clear the evaluation picker's own filters — the CA tab defaults to
  // only listing the latest period with data, which might not include
  // this evaluation if it's from an earlier month.
  const filterSupplier = document.getElementById('ca_ev_filter_supplier');
  const filterYear = document.getElementById('ca_ev_filter_year');
  const filterMonth = document.getElementById('ca_ev_filter_month');
  if (filterSupplier) filterSupplier.value = '';
  if (filterYear) filterYear.value = '';
  if (filterMonth) filterMonth.value = '';
  populateCaEvalSelect();
  const sel = document.getElementById('ca_evaluation');
  if (sel) sel.value = evaluationId;
}

function editCorrectiveAction(id){
  const ca = correctiveActions.find(x => x.id === id);
  if (!ca) return;
  showTab('ca');
  caEditorMode = 'edit';
  if (ca.evaluation?.id) document.getElementById('ca_evaluation').value = ca.evaluation.id;
  caSets = [ caSetFromRow(ca) ];
  renderCaSets();
  loadCaAttachments(id).then(() => { if (caSets[0]?.dbId === id) { caSets[0].attachments = caAttachments; renderCaSets(); } });
  attachHistoryId(id);
}

async function markCaCountermeasureReceived(){
  const editId = caEditorMode === 'edit' ? caSets[0]?.dbId : null;
  if (!editId) return;
  if (!confirm(L('Mark this corrective action as closed? This means the supplier\'s countermeasure has been received and reviewed.','ยืนยันปิดเคสนี้? หมายถึงได้รับและตรวจสอบไฟล์แก้ไขจาก Supplier แล้ว'))) return;
  const { error } = await sb.from('corrective_actions').update({
    status: 'closed',
    finished_date: todayIso(),
  }).eq('id', editId);
  if (error) { alert('Failed: ' + error.message); console.error(error); return; }
  await loadCorrectiveActions();
  editCorrectiveAction(editId);
  renderAll();
  alert(L('Corrective action closed','ปิดเคส Corrective Action แล้ว'));
}

function buildCaPayload(evaluationId, set){
  return {
    evaluation_id: evaluationId,
    problem: (set.problem||'').trim(),
    root_cause: (set.root_cause||'').trim() || null,
    action: (set.action||'').trim() || null,
    responsible_person: (set.responsible_person||'').trim() || null,
    start_date: set.start_date || null,
    due_date: set.due_date || null,
    finished_date: set.finished_date || null,
    status: set.status,
  };
}

async function saveCorrectiveAction(){
  syncCaSetsFromDom();
  const evaluationId = document.getElementById('ca_evaluation').value;
  if (!evaluationId) { alert(lang==='th' ? 'กรุณาเลือก Evaluation' : 'Please select an evaluation'); return; }
  if (caEditorMode === 'create' && !caUserCanCreate()) {
    alert(lang==='th' ? 'เฉพาะ CS/MP/CS Supervisor/Admin เท่านั้นที่สร้าง Corrective Action ใหม่ได้' : 'Only CS/MP/CS Supervisor/Admin can create a new corrective action');
    return;
  }
  if (caEditorMode === 'edit' && !(caUserCanFullEdit() || caUserCanRestrictedEdit())) {
    alert(lang==='th' ? 'ไม่มีสิทธิ์แก้ไข Corrective Action ที่เปิดไว้แล้ว' : 'You do not have permission to edit an existing corrective action');
    return;
  }
  if (caSets.some(s => !(s.problem||'').trim())) {
    alert(L('Please enter Problem for every item','กรุณากรอก Problem ให้ครบทุกรายการ'));
    return;
  }

  if (caEditorMode === 'edit') {
    const set = caSets[0];
    const { error } = await sb.from('corrective_actions').update(buildCaPayload(evaluationId, set)).eq('id', set.dbId);
    if (error) { alert('Save failed: ' + error.message); console.error(error); return; }
    for (const file of set.pendingFiles) await uploadFileToCa(set.dbId, file);
  } else {
    const existingForEval = correctiveActions.filter(c => c.evaluation?.id === evaluationId);
    let nextSeq = existingForEval.length ? Math.max(...existingForEval.map(c => c.seq_no || 0)) + 1 : 1;
    for (const set of caSets) {
      const { data, error } = await sb.from('corrective_actions').insert({ ...buildCaPayload(evaluationId, set), seq_no: nextSeq }).select().single();
      if (error) { alert(`Save failed on "${set.problem}": ` + error.message); console.error(error); return; }
      nextSeq++;
      for (const file of set.pendingFiles) await uploadFileToCa(data.id, file);
    }
  }
  await loadCorrectiveActions();
  resetCaForm();
  renderAll();
  alert(lang==='th' ? 'บันทึกข้อมูลแล้ว' : 'Saved');
}

async function deleteCorrectiveAction(id){
  if (!confirm(lang==='th' ? 'ต้องการลบรายการนี้ใช่ไหม?' : 'Delete this corrective action?')) return;
  const { error } = await sb.from('corrective_actions').delete().eq('id', id);
  if (error) { alert('Delete failed: ' + error.message); return; }
  await loadCorrectiveActions();
  renderAll();
}

// Short summary of which criteria actually had occurrences on the CA's
// evaluation — "why did this grade drop", shown directly in the
// Evaluation List's CA info instead of making someone open the
// Worksheet to find out.
function failedCriteriaFor(evaluationId){
  if (!evaluationId) return '-';
  const items = allEvaluationItems.filter(i => i.evaluation_id === evaluationId && toNum(i.occurrence) > 0);
  if (!items.length) return '-';
  return items.map(i => {
    const c = evaluationCriteria.find(cr => cr.id === i.criteria_id);
    if (!c) return null;
    const desc = lang==='th' && c.description_th ? c.description_th : c.description;
    return `${c.item_no} ${desc}${toNum(i.occurrence)>1 ? ` (x${i.occurrence})` : ''}`;
  }).filter(Boolean).join('; ');
}

/* ============================================================
   Master Control — Suppliers
   ============================================================ */
function setMasterTab(tab){
  document.querySelectorAll('[data-mastertab]').forEach(b => b.classList.toggle('active', b.dataset.mastertab === tab));
  document.getElementById('masterSuppliers').style.display = tab === 'suppliers' ? 'block' : 'none';
  document.getElementById('masterCriteria').style.display = tab === 'criteria' ? 'block' : 'none';
  document.getElementById('masterUsers').style.display = tab === 'users' ? 'block' : 'none';
  document.getElementById('masterPermissions').style.display = tab === 'permissions' ? 'block' : 'none';
  document.getElementById('masterHolidays').style.display = tab === 'holidays' ? 'block' : 'none';
  if (tab === 'permissions') renderPermissionMatrix();
  if (tab === 'holidays') renderHolidaysTable();
}

function setReportTab(tab){
  document.querySelectorAll('[data-reporttab]').forEach(b => b.classList.toggle('active', b.dataset.reporttab === tab));
  document.getElementById('reportSingle').style.display = tab === 'single' ? 'block' : 'none';
  document.getElementById('reportYearly').style.display = tab === 'yearly' ? 'block' : 'none';
  if (tab === 'yearly') renderYearlySummary();
}

function setProfileTab(tab){
  document.querySelectorAll('[data-profiletab]').forEach(b => b.classList.toggle('active', b.dataset.profiletab === tab));
  document.getElementById('profileTabOverview').style.display = tab === 'overview' ? 'block' : 'none';
  document.getElementById('profileTabEvaluation').style.display = tab === 'evaluation' ? 'block' : 'none';
  document.getElementById('profileTabAudit').style.display = tab === 'audit' ? 'block' : 'none';
  document.getElementById('profileTabCa').style.display = tab === 'ca' ? 'block' : 'none';
  document.getElementById('profileTabContacts').style.display = tab === 'contacts' ? 'block' : 'none';
  if (tab === 'evaluation') requestAnimationFrame(renderProfile); // chart canvas was 0-size while its tab was hidden
}

function renderPermissionMatrix(){
  const el = document.getElementById('masterPermissionsTable');
  if (!el) return;
  // Labels only — the actual allowed/denied values come from `permissionRules`
  // (loaded from the `permission_rules` table), not from this list.
  const ruleLabels = {
    eval_edit_quality:  { area: lang==='th'?'ผลประเมิน':'Evaluations', action: lang==='th'?'กรอกคะแนน Quality':'Edit Quality score' },
    eval_edit_delivery: { area: lang==='th'?'ผลประเมิน':'Evaluations', action: lang==='th'?'กรอกคะแนน Delivery/Purchase':'Edit Delivery/Purchase score' },
    eval_sup_approve:   { area: lang==='th'?'ผลประเมิน':'Evaluations', action: lang==='th'?'Supervisor Approve':'Supervisor Approve' },
    eval_mgr_approve:   { area: lang==='th'?'ผลประเมิน':'Evaluations', action: lang==='th'?'Manager Approve':'Manager Approve' },
    eval_delete:        { area: lang==='th'?'ผลประเมิน':'Evaluations', action: lang==='th'?'ลบ':'Delete' },
    ca_create:          { area:'Corrective Action', action: lang==='th'?'สร้างใหม่':'Create new' },
    ca_edit_full:       { area:'Corrective Action', action: lang==='th'?'แก้ไขทุกฟิลด์ / เปลี่ยนสถานะ':'Edit any field / change status' },
    ca_edit_restricted: { area:'Corrective Action', action: lang==='th'?'แก้เฉพาะ Root Cause / Action':'Edit only Root Cause / Action' },
    ca_close:           { area:'Corrective Action', action: lang==='th'?'ปิดเคส (Mark Received Countermeasure)':'Close case (Mark Received Countermeasure)' },
    eval_mark_sent:     { area: lang==='th'?'ผลประเมิน':'Evaluations', action: lang==='th'?'Mark Sent to Supplier':'Mark Sent to Supplier' },
    ca_delete:          { area:'Corrective Action', action: lang==='th'?'ลบ':'Delete' },
    attachment_upload:  { area: lang==='th'?'ไฟล์แนบ':'Attachments', action: lang==='th'?'อัปโหลด':'Upload' },
    attachment_delete:  { area: lang==='th'?'ไฟล์แนบ':'Attachments', action: lang==='th'?'ลบ':'Delete' },
    master_data_manage: { area:'Master Data', action: lang==='th'?'Suppliers / Evaluation Criteria / Users / Permissions':'Suppliers / Evaluation Criteria / Users / Permissions' },
  };
  const ruleOrder = Object.keys(ruleLabels);
  const roleCols = [
    { key:'qa', label:'QA' }, { key:'cs', label:'CS' }, { key:'mp', label:'MP' },
    { key:'cs_supervisor', label:'CS Supervisor' }, { key:'mp_supervisor', label:'MP Supervisor' },
    { key:'opd_manager', label:'OPD Manager' }, { key:'admin', label:'Admin' },
  ];
  const canEdit = hasPerm('master_data_manage');
  const H = [lang==='th'?'ส่วน':'Area', lang==='th'?'สิทธิ์':'Action', ...roleCols.map(r=>r.label)];

  const cell = (ruleKey, dept) => {
    const row = permissionRules.find(r => r.rule_key === ruleKey && r.department === dept);
    const checked = !!row?.allowed;
    if (!canEdit) return checked ? '<span class="badge ok">✓</span>' : '<span class="muted-small">—</span>';
    return `<input type="checkbox" ${checked?'checked':''} onchange="togglePermission('${ruleKey}','${dept}',this.checked)">`;
  };

  el.innerHTML = `<table><thead><tr>${H.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${
    ruleOrder.map(rk => `<tr><td>${ruleLabels[rk].area}</td><td class="muted-small">${ruleLabels[rk].action}</td>${roleCols.map(c=>`<td>${cell(rk,c.key)}</td>`).join('')}</tr>`).join('')
  }</tbody></table>`;
}

async function togglePermission(ruleKey, department, allowed){
  const statusEl = document.getElementById('permSaveStatus');
  if (statusEl) statusEl.textContent = L('Saving…','กำลังบันทึก…');
  // .select() added specifically so we can tell "0 rows matched/changed"
  // apart from "genuinely succeeded" — Supabase does NOT return an
  // error for an update that RLS silently filtered down to 0 rows, so
  // without this the code had no way to know the difference and could
  // report a false "Saved" even when nothing was actually written.
  const { data, error } = await sb.from('permission_rules')
    .update({ allowed })
    .eq('rule_key', ruleKey).eq('department', department)
    .select();
  if (error) {
    if (statusEl) statusEl.textContent = '';
    alert('Update failed: ' + error.message); console.error(error); renderPermissionMatrix(); return;
  }
  if (!data || data.length === 0) {
    if (statusEl) statusEl.textContent = '';
    alert(L(
      'Save was blocked — 0 rows changed even though there was no error. This is a database permission (RLS) issue, not a bug in this screen — check that is_admin()/has_permission() are correctly installed.',
      'การบันทึกถูกปฏิเสธ — ไม่มีแถวไหนถูกแก้เลย (0 rows) ทั้งที่ไม่มี error ขึ้น — เป็นปัญหาสิทธิ์ระดับฐานข้อมูล (RLS) ไม่ใช่บั๊กหน้าจอนี้ — เช็คว่า is_admin()/has_permission() ถูกติดตั้งถูกต้องหรือยัง'
    ));
    renderPermissionMatrix();
    return;
  }
  await loadPermissionRules();
  renderAll(); // only rebuilds #masterPermissionsTable's own contents, permSaveStatus (its sibling) is untouched
  if (statusEl) {
    statusEl.textContent = L(`✓ Saved — ${department} / ${ruleKey} = ${allowed}`,`✓ บันทึกแล้ว — ${department} / ${ruleKey} = ${allowed}`);
    setTimeout(() => { statusEl.textContent = ''; }, 3000);
  }
}

function resetHolidayForm(){
  document.getElementById('mh_date').value = '';
  document.getElementById('mh_name').value = '';
  document.getElementById('mh_name_th').value = '';
  delete document.getElementById('btnHolidaySave').dataset.editId;
}

function editHoliday(id){
  const h = holidays.find(x => x.id === id);
  if (!h) return;
  document.getElementById('mh_date').value = h.holiday_date;
  document.getElementById('mh_name').value = h.name || '';
  document.getElementById('mh_name_th').value = h.name_th || '';
  document.getElementById('btnHolidaySave').dataset.editId = id;
}

async function openMonthlyCycle(){
  const year = toNum(document.getElementById('oc_year').value);
  const month = toNum(document.getElementById('oc_month').value);
  const resultEl = document.getElementById('openCycleResult');
  resultEl.textContent = lang==='th' ? 'กำลังเปิดรอบ...' : 'Opening cycle...';
  const { data, error } = await sb.rpc('open_evaluation_cycle', { p_year: year, p_month: month });
  if (error) { resultEl.textContent = 'Failed: ' + error.message; console.error(error); return; }
  const row = Array.isArray(data) ? data[0] : data;
  const created = row?.created_count ?? 0;
  const existed = row?.cycle_already_existed;
  resultEl.textContent = lang==='th'
    ? `เปิดรอบ ${ymLabel(year, month)} แล้ว — สร้างผลประเมินใหม่ ${created} รายการ${existed ? ' (รอบนี้เคยเปิดไว้แล้ว)' : ''}`
    : `Opened ${ymLabel(year, month)} — created ${created} new evaluation(s)${existed ? ' (this cycle was already open)' : ''}`;
  await loadEvaluations();
  renderAll();
}

async function saveHoliday(){
  const holidayDate = document.getElementById('mh_date').value;
  const name = document.getElementById('mh_name').value.trim();
  if (!holidayDate || !name) { alert(lang==='th' ? 'กรุณากรอกวันที่และชื่อวันหยุด' : 'Please enter a date and name'); return; }
  const editId = document.getElementById('btnHolidaySave').dataset.editId;
  const payload = {
    holiday_date: holidayDate,
    name,
    name_th: document.getElementById('mh_name_th').value.trim() || null,
  };
  let error;
  if (editId) ({ error } = await sb.from('public_holidays').update(payload).eq('id', editId));
  else ({ error } = await sb.from('public_holidays').insert(payload));
  if (error) { alert('Save failed: ' + error.message); console.error(error); return; }
  await loadHolidays();
  resetHolidayForm();
  renderHolidaysTable();
  alert(lang==='th' ? 'บันทึกข้อมูลแล้ว' : 'Saved');
}

async function deleteHoliday(id){
  if (!confirm(lang==='th' ? 'ลบวันหยุดนี้ใช่ไหม?' : 'Delete this holiday?')) return;
  const { error } = await sb.from('public_holidays').delete().eq('id', id);
  if (error) { alert('Delete failed: ' + error.message); return; }
  await loadHolidays();
  renderHolidaysTable();
}

function renderHolidaysTable(){
  const el = document.getElementById('masterHolidaysTable');
  if (!el) return;
  if (!holidays.length) { el.innerHTML = `<div class="empty-note">${t('noData','No data yet')}</div>`; return; }
  const H = lang==='th' ? ['วันที่','ชื่อ (EN)','ชื่อ (TH)','จัดการ'] : ['Date','Name (EN)','Name (TH)','Action'];
  el.innerHTML = `<table><thead><tr>${H.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${
    holidays.map(h => `<tr>
      <td><b>${h.holiday_date}</b></td>
      <td class="muted-small">${h.name}</td>
      <td class="muted-small">${h.name_th || '-'}</td>
      <td>
        <button class="row-btn" onclick="editHoliday('${h.id}')">${t('edit', lang==='th'?'แก้ไข':'Edit')}</button>
        <button class="row-btn danger" onclick="deleteHoliday('${h.id}')">${t('del', lang==='th'?'ลบ':'Delete')}</button>
      </td>
    </tr>`).join('')
  }</tbody></table>`;
}

/* ============================================================
   Translation Overrides (Setting -> Translation, Admin only)
   ============================================================ */
async function loadTranslationOverrides(){
  const { data, error } = await sb.from('translation_overrides').select('key, th_text, en_text');
  if (error) { console.error(error); return; }
  translationOverrides = {};
  (data || []).forEach(row => { translationOverrides[row.key] = { th_text: row.th_text, en_text: row.en_text }; });
}

// Groups every data-i18n/-ph key by the page (or Setting/Profile
// sub-tab) it actually lives on — reuses the app's own existing
// structure as the category taxonomy instead of inventing a separate
// one, so it stays accurate as pages change.
const TRANSLATION_CATEGORY_MAP = {
  dashboard: 'Dashboard', input: 'Worksheet', list: 'Evaluation List', ca: 'Corrective Action',
  profileTabOverview: 'Supplier Profile — Overview', profileTabEvaluation: 'Supplier Profile — Evaluation',
  profileTabAudit: 'Supplier Profile — Audit', profileTabCa: 'Supplier Profile — Corrective Action', profileTabContacts: 'Supplier Profile — Contacts',
  report: 'Report', settingStatus: 'Setting — Status', settingMaster: 'Master Control',
  settingImportExport: 'Import / Export', settingActivityLog: 'Activity Log', settingTranslation: 'Translation (this page)',
};
function categoryForElement(el){
  let node = el;
  while (node && node !== document.body) {
    if (node.id && TRANSLATION_CATEGORY_MAP[node.id]) return TRANSLATION_CATEGORY_MAP[node.id];
    node = node.parentElement;
  }
  return L('General / Menu','ทั่วไป / เมนูหลัก');
}

let translationCatalog = {}; // { category: [{key, enDefault, thDefault}] } — rebuilt each time the Translation tab is opened
let translationActiveCategory = '';

function buildTranslationCatalog(){
  const seen = new Map();
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.dataset.i18n;
    if (seen.has(key)) return;
    seen.set(key, { enDefault: (el.dataset.enText || el.textContent || '').trim(), thDefault: TH[key] || '', category: categoryForElement(el) });
  });
  document.querySelectorAll('[data-i18n-ph]').forEach(el => {
    const key = el.dataset.i18nPh;
    if (seen.has(key)) return;
    seen.set(key, { enDefault: (el.dataset.enPh || el.placeholder || '').trim(), thDefault: TH[key] || '', category: categoryForElement(el) });
  });
  translationCatalog = {};
  seen.forEach((v, key) => { (translationCatalog[v.category] ||= []).push({ key, enDefault: v.enDefault, thDefault: v.thDefault }); });
  Object.values(translationCatalog).forEach(arr => arr.sort((a,b) => a.key.localeCompare(b.key)));
}

function populateTranslationCategoryDropdown(){
  const sel = document.getElementById('tr_category');
  if (!sel) return;
  const categories = Object.keys(translationCatalog).sort((a,b) => translationCatalog[b].length - translationCatalog[a].length);
  if (!translationActiveCategory || !categories.includes(translationActiveCategory)) translationActiveCategory = categories[0] || '';
  sel.innerHTML = categories.map(c => `<option value="${escapeHtml(c)}" ${c===translationActiveCategory?'selected':''}>${escapeHtml(c)} (${translationCatalog[c].length})</option>`).join('');
}

function renderTranslationTable(){
  const el = document.getElementById('translationTableWrap');
  if (!el) return;
  const search = (document.getElementById('tr_search')?.value || '').toLowerCase();
  const rows = search
    ? Object.values(translationCatalog).flat().filter(r =>
        r.key.toLowerCase().includes(search) || r.enDefault.toLowerCase().includes(search) || r.thDefault.toLowerCase().includes(search))
    : (translationCatalog[translationActiveCategory] || []);
  if (!rows.length) { el.innerHTML = `<div class="empty-note">${t('noData','No data yet')}</div>`; return; }
  const H = lang==='th' ? ['Label','ไทย','English'] : ['Label','Thai','English'];
  el.innerHTML = `<table><thead><tr>${H.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${
    rows.map(r => {
      const ov = translationOverrides[r.key];
      const thVal = ov?.th_text ?? r.thDefault;
      const enVal = ov?.en_text ?? r.enDefault;
      return `<tr>
        <td class="muted-small">${escapeHtml(r.enDefault || r.key)}<br><span style="font-size:10px;opacity:.6">${escapeHtml(r.key)}</span></td>
        <td><input type="text" class="tr-cell" data-trkey="${escapeHtml(r.key)}" data-trlang="th" value="${escapeHtml(thVal)}"></td>
        <td><input type="text" class="tr-cell" data-trkey="${escapeHtml(r.key)}" data-trlang="en" value="${escapeHtml(enVal)}"></td>
      </tr>`;
    }).join('')
  }</tbody></table>`;
}

async function saveAllTranslationChanges(){
  const inputs = document.querySelectorAll('#translationTableWrap .tr-cell');
  const byKey = {};
  inputs.forEach(inp => { (byKey[inp.dataset.trkey] ||= {})[inp.dataset.trlang] = inp.value.trim(); });
  const search = (document.getElementById('tr_search')?.value || '').toLowerCase();
  const rows = search ? Object.values(translationCatalog).flat() : (translationCatalog[translationActiveCategory] || []);
  const writes = [];
  rows.forEach(r => {
    const edited = byKey[r.key];
    if (!edited) return;
    const curTh = translationOverrides[r.key]?.th_text ?? r.thDefault;
    const curEn = translationOverrides[r.key]?.en_text ?? r.enDefault;
    if (edited.th === curTh && edited.en === curEn) return; // unchanged, skip
    // Matching the app's own default exactly means "don't override this
    // side" (store null), not "override it with the same text."
    writes.push({
      key: r.key,
      th_text: edited.th === r.thDefault ? null : (edited.th || null),
      en_text: edited.en === r.enDefault ? null : (edited.en || null),
      updated_by: currentUser?.id, updated_at: new Date().toISOString(),
    });
  });
  if (!writes.length) { alert(L('No changes to save','ไม่มีการเปลี่ยนแปลงให้บันทึก')); return; }
  const { error } = await sb.from('translation_overrides').upsert(writes, { onConflict: 'key' });
  if (error) { alert('Save failed: ' + error.message); console.error(error); return; }
  await loadTranslationOverrides();
  renderTranslationTable();
  applyLang(); // re-render every visible label immediately with the new overrides
  alert(L(`Saved ${writes.length} change(s)`,`บันทึกแล้ว ${writes.length} รายการ`));
}

/* ============================================================
   Activity Log (v2.1.0) — visible to everyone, revert is Admin-only.
   ============================================================ */
let actionLog = [];

async function loadActionLog(){
  const tableFilter = document.getElementById('alFilterTable')?.value || '';
  const actionFilter = document.getElementById('alFilterAction')?.value || '';
  const revertableOnly = document.getElementById('alRevertableOnly')?.checked;
  let q = sb.from('admin_action_log').select('*').order('performed_at', { ascending:false }).limit(300);
  if (tableFilter) q = q.eq('table_name', tableFilter);
  if (actionFilter) q = q.eq('action', actionFilter);
  if (revertableOnly) q = q.eq('revert_supported', true).eq('reverted', false);
  const { data, error } = await q;
  if (error) { console.error(error); showBanner('Load activity log failed: ' + error.message); return; }
  actionLog = data || [];
}

function actionLogUserName(userId){
  if (!userId) return '-';
  const u = userProfilesList.find(p => p.id === userId);
  return u?.full_name || `${userId.slice(0,8)}…`;
}

const actionLogLabels = {
  insert: { en:'Created', th:'สร้าง' },
  update: { en:'Updated', th:'แก้ไข' },
  delete: { en:'Deleted', th:'ลบ' },
};

function renderActionLogTable(){
  const el = document.getElementById('masterActivityLogTable');
  if (!el) return;
  if (!actionLog.length) { el.innerHTML = `<div class="empty-note">${t('noData','No data yet')}</div>`; return; }
  const canRevert = hasPerm('master_data_manage');
  const H = lang==='th'
    ? ['เวลา','ใคร','ตาราง','การกระทำ','ฟิลด์ที่เปลี่ยน','สถานะ','จัดการ']
    : ['Time','Who','Table','Action','Changed Fields','Status','Action'];
  el.innerHTML = `<table><thead><tr>${H.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${
    actionLog.map(a => {
      const actionLabel = actionLogLabels[a.action]?.[lang] || a.action;
      const fields = (a.changed_fields || []).join(', ') || '-';
      let statusBadge;
      if (a.reverted) statusBadge = `<span class="badge status">${L('Reverted','ย้อนคืนแล้ว')}</span>`;
      else if (!a.revert_supported) statusBadge = `<span class="muted-small">${L('Not revertible','ย้อนคืนไม่ได้')}</span>`;
      else statusBadge = `<span class="muted-small">${L('Revertible','ย้อนคืนได้')}</span>`;
      const canRevertThis = canRevert && a.revert_supported && !a.reverted;
      return `<tr>
        <td class="muted-small nowrap">${(a.performed_at||'').slice(0,16).replace('T',' ')}</td>
        <td class="muted-small">${actionLogUserName(a.performed_by)}</td>
        <td>${a.table_name}</td>
        <td>${actionLabel}</td>
        <td class="cell-truncate" title="${escapeHtml(fields)}">${escapeHtml(fields)}</td>
        <td>${statusBadge}</td>
        <td>${canRevertThis ? `<button class="row-btn danger" onclick="revertActionLog('${a.id}')">${L('Revert','ย้อนคืน')}</button>` : ''}</td>
      </tr>`;
    }).join('')
  }</tbody></table>`;
}

async function revertActionLog(logId){
  if (!confirm(L('Revert this action? This will restore the affected record to how it was before this change.','ย้อนคืน action นี้? จะคืนค่ารายการที่เกี่ยวข้องกลับไปเป็นก่อนหน้าการเปลี่ยนแปลงนี้'))) return;
  const { error } = await sb.rpc('revert_admin_action', { p_log_id: logId });
  if (error) { alert(L('Revert failed: ','ย้อนคืนไม่สำเร็จ: ') + error.message); console.error(error); return; }
  await loadActionLog();
  renderActionLogTable();
  await reloadAll();
  alert(L('Reverted','ย้อนคืนแล้ว'));
}

/* ============================================================
   Import / Export (v2.3.0) — round-trips the FM0704-3 Excel format
   that E&H already uses. Import: parse uploaded monthly files, match
   each supplier sheet to an existing Supplier (fuzzy, with manual
   fallback), preview before writing anything. Export: clone the real
   blank template sheet per selected (itemized-only) evaluation and
   fill in just the data cells, so formatting/formulas survive intact.
   ============================================================ */
const IE_ROW_TO_ITEM = {};
for (let i=0;i<9;i++) IE_ROW_TO_ITEM[10+i] = `A1-${i+1}`;
for (let i=0;i<3;i++) IE_ROW_TO_ITEM[20+i] = `A2-${i+1}`;
for (let i=0;i<7;i++) IE_ROW_TO_ITEM[24+i] = `B-${i+1}`;
for (let i=0;i<3;i++) IE_ROW_TO_ITEM[32+i] = `C-${i+1}`;
const IE_SKIP_SHEET_RE = /^(DATA|FM0704|ตัวอย่าง|FORMAT|Summary)/i;

let ieParsedRows = [];

function ieNormalizeName(name){
  return String(name||'').toUpperCase()
    .replace(/\bCO\.?,?\s*LTD\.?/g,'')
    .replace(/\bCOMPANY LIMITED\b/g,'')
    .replace(/\bLIMITED\b/g,'')
    .replace(/[.,()]/g,'')
    .replace(/\s+/g,' ')
    .trim();
}

function ieFuzzyMatchSupplier(name){
  const norm = ieNormalizeName(name);
  if (!norm) return null;
  let best = allSuppliers.find(s => ieNormalizeName(s.name) === norm || ieNormalizeName(s.short_name) === norm);
  if (best) return best;
  best = allSuppliers.find(s => ieNormalizeName(s.short_name).length > 2 && norm.includes(ieNormalizeName(s.short_name)));
  if (best) return best;
  best = allSuppliers.find(s => ieNormalizeName(s.name).length > 2 && (ieNormalizeName(s.name).includes(norm) || norm.includes(ieNormalizeName(s.name))));
  return best || null;
}

// Recomputes quality/delivery/purchase from occurrence counts using the
// CURRENT active criteria version — used only to flag a warning in the
// preview if it doesn't match what the Excel file itself reports for
// that month (a sign the criteria have changed since that month was
// scored — see PLAN.md's "safety net" decision for versioned criteria).
function ieRecomputeFromOccurrence(occ){
  const activeByItem = {};
  evaluationCriteria.forEach(c => { if (c.is_active) activeByItem[c.item_no] = c; });
  let quality = 50, delivery = 40, purchase = 0;
  Object.entries(occ).forEach(([itemNo, count]) => {
    if (!count) return;
    const c = activeByItem[itemNo];
    if (!c) return;
    const amt = count * toNum(c.deduction_points);
    if (itemNo.startsWith('A1') || itemNo.startsWith('A2')) quality += amt;
    else if (itemNo.startsWith('B')) delivery += amt;
    else if (itemNo.startsWith('C')) purchase += amt;
  });
  return {
    quality: Math.max(0, Math.min(50, quality)),
    delivery: Math.max(0, Math.min(40, delivery)),
    purchase: Math.max(0, Math.min(10, purchase)),
  };
}

async function parseImportFiles(){
  const files = document.getElementById('ie_file_input').files;
  if (!files.length) { alert(L('Choose at least one .xlsx file first','กรุณาเลือกไฟล์ .xlsx อย่างน้อย 1 ไฟล์')); return; }
  if (typeof XLSX === 'undefined') { alert(L('The Excel library failed to load — check your internet connection and reload the page.','ไลบรารี Excel โหลดไม่สำเร็จ — เช็คอินเทอร์เน็ตแล้วรีโหลดหน้านี้')); return; }
  document.getElementById('ieParseStatus').textContent = L('Parsing…','กำลังอ่านไฟล์…');
  ieParsedRows = [];

  for (const file of files) {
    // Was \b(20\d{2})\b — \b (word boundary) treats underscore as a word
    // character, so it silently failed to match on filenames like
    // "2025_Evaluation_..." (no boundary between "5" and "_") and fell
    // through to the current-system-year fallback below instead. Fixed
    // to just find any 20xx run of digits, no boundary assumptions.
    const yearMatch = file.name.match(/(20\d{2})/);
    const yearGuessed = !yearMatch; // true = no year found in filename, fell back to today's year — needs a human check
    const fallbackYear = yearMatch ? parseInt(yearMatch[1],10) : new Date().getFullYear();
    const buf = await file.arrayBuffer();
    const wb = XLSX.read(buf, { type:'array' });
    wb.SheetNames.forEach(sheetName => {
      if (IE_SKIP_SHEET_RE.test(sheetName)) return;
      const ws = wb.Sheets[sheetName];
      const get = (ref) => ws[ref] ? ws[ref].v : undefined;
      const companyName = get('C3');
      if (!companyName) return; // not a real supplier sheet
      const monthAbbr = String(get('S4')||'').trim().toLowerCase();
      const monthIdx = MONTHS.findIndex(m => m.toLowerCase() === monthAbbr.slice(0,3));
      if (monthIdx < 0) return; // can't determine month, skip this sheet
      const monthNum = monthIdx + 1;
      const colLetter = XLSX.utils.encode_col(18 + monthNum);
      const wQuality = toNum(get(`${colLetter}31`));
      const wDelivery = toNum(get(`${colLetter}32`));
      const wPurchase = toNum(get(`${colLetter}33`));
      const noShipment = wDelivery === 0 && wPurchase === 0;

      const occ = {};
      Object.entries(IE_ROW_TO_ITEM).forEach(([row,itemNo]) => { occ[itemNo] = toNum(get(`N${row}`)); });

      const recomputed = ieRecomputeFromOccurrence(occ);
      const versionMismatch = Math.abs(recomputed.quality - (wQuality||50)) > 2
        || (!noShipment && Math.abs(recomputed.delivery - (wDelivery||40)) > 2);

      const matched = ieFuzzyMatchSupplier(companyName);
      ieParsedRows.push({
        _key: `${file.name}__${sheetName}__${Math.random().toString(36).slice(2,8)}`,
        fileName: file.name, sheetName,
        companyName: String(companyName).trim(),
        attention: get('C4') ? String(get('C4')).trim() : '',
        tel: get('I4') ? String(get('I4')).trim() : '',
        year: fallbackYear, month: monthNum, yearGuessed,
        occ, noShipment, versionMismatch,
        matchedSupplierId: matched ? matched.id : null,
        newCategory: 'Material',
        include: true,
      });
    });
  }

  document.getElementById('ieParseStatus').textContent =
    `${L('Parsed','อ่านไฟล์เสร็จ')}: ${ieParsedRows.length} ${L('supplier-month rows found','รายการ (supplier x เดือน)')}`;
  renderImportPreview();
}

function renderImportPreview(){
  const el = document.getElementById('ieImportPreview');
  const confirmRow = document.getElementById('ieConfirmRow');
  if (!ieParsedRows.length) { el.innerHTML=''; confirmRow.style.display='none'; return; }
  confirmRow.style.display = 'flex';
  const supplierOptions = allSuppliers.filter(s=>s.is_active!==false).sort((a,b)=>a.code.localeCompare(b.code));
  el.innerHTML = `<div class="table-wrap"><table><thead><tr>
      <th></th><th>${L('File / Sheet','ไฟล์ / Sheet')}</th><th>${L('Company (as read)','ชื่อที่อ่านได้')}</th>
      <th>${L('Month','เดือน')}</th><th>${L('Match to Supplier','จับคู่กับ Supplier')}</th><th>${L('New Supplier Category','กลุ่ม Supplier ใหม่')}</th><th>${L('Flags','สถานะ')}</th>
    </tr></thead><tbody>${ieParsedRows.map(r => `<tr>
      <td><input type="checkbox" ${r.include?'checked':''} onchange="ieToggleInclude('${r._key}',this.checked)"></td>
      <td class="muted-small">${escapeHtml(r.fileName)}<br>${escapeHtml(r.sheetName)}</td>
      <td>${escapeHtml(r.companyName)}</td>
      <td class="nowrap">
        <input type="number" value="${r.year}" style="width:64px" onchange="ieSetYear('${r._key}',this.value)">-${monthName(r.month)}
      </td>
      <td><select onchange="ieSetMatch('${r._key}',this.value)">
        <option value="" ${!r.matchedSupplierId?'selected':''}>${L('— Create New Supplier —','— สร้าง Supplier ใหม่ —')}</option>
        ${supplierOptions.map(s=>`<option value="${s.id}" ${r.matchedSupplierId===s.id?'selected':''}>${escapeHtml(s.code)} — ${escapeHtml(s.short_name||s.name)}</option>`).join('')}
      </select></td>
      <td>${r.matchedSupplierId ? '<span class="muted-small">-</span>' : `<select onchange="ieSetCategory('${r._key}',this.value)">
        <option value="Material" ${r.newCategory==='Material'?'selected':''}>Material</option>
        <option value="Outsource" ${r.newCategory==='Outsource'?'selected':''}>Outsource</option>
        <option value="Blank Part" ${r.newCategory==='Blank Part'?'selected':''}>Blank Part</option>
      </select>`}</td>
      <td>${[
        r.yearGuessed ? `<span class="badge risk">${L('Year not found in filename — guessed, please check','หาปีจากชื่อไฟล์ไม่เจอ — เดาไว้ กรุณาตรวจสอบ')}</span>` : '',
        !r.matchedSupplierId ? `<span class="badge status">${L('New supplier','Supplier ใหม่')}</span>` : '',
        r.noShipment ? `<span class="badge status">${L('No Shipment','No Shipment')}</span>` : '',
        r.versionMismatch ? `<span class="badge risk">${L('Score vs. current criteria differs — check before confirming','คะแนนไม่ตรงกับหัวข้อประเมินปัจจุบัน — ตรวจสอบก่อนยืนยัน')}</span>` : '',
      ].filter(Boolean).join(' ')}</td>
    </tr>`).join('')}</tbody></table></div>`;
}

function ieToggleInclude(key, checked){
  const r = ieParsedRows.find(x=>x._key===key); if (r) r.include = checked;
}
function ieSetYear(key, year){
  const r = ieParsedRows.find(x=>x._key===key); if (r) { r.year = toNum(year); r.yearGuessed = false; }
}
function ieSetMatch(key, supplierId){
  const r = ieParsedRows.find(x=>x._key===key); if (r) r.matchedSupplierId = supplierId || null;
  renderImportPreview();
}
function ieSetCategory(key, category){
  const r = ieParsedRows.find(x=>x._key===key); if (r) r.newCategory = category;
}

async function confirmImport(){
  const rows = ieParsedRows.filter(r=>r.include);
  if (!rows.length) { alert(L('Nothing selected to import','ไม่มีรายการที่เลือกไว้')); return; }
  if (!confirm(L(`Import ${rows.length} supplier-month record(s)? Existing evaluations for the same supplier+month will be updated (upserted), not duplicated.`,`Import ${rows.length} รายการ? evaluation เดือนเดียวกันของ supplier เดิมจะถูกอัปเดตทับ (ไม่ซ้ำ)`))) return;

  const resultEl = document.getElementById('ieImportResult');
  let created = 0, updated = 0, failed = 0;

  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    resultEl.textContent = `${L('Importing','กำลัง import')} (${i+1}/${rows.length}) — ${r.sheetName} (${ymLabel(r.year, r.month)})`;
    let supplierId = r.matchedSupplierId;

    if (!supplierId) {
      const category = r.newCategory || 'Material';
      const prefix = category === 'Blank Part' ? 'PA' : category === 'Outsource' ? 'OS' : 'MA';
      const code = `${prefix}-NEW-${Date.now().toString().slice(-6)}`;
      const { data: newSupplier, error: supErr } = await sb.from('suppliers').insert({
        code, name: r.companyName, short_name: r.companyName.split('(')[0].split(',')[0].trim(),
        category, attention: r.attention || null, tel: r.tel || null, target_score: 80, is_active: true,
      }).select().single();
      if (supErr) { failed++; console.error(supErr); continue; }
      supplierId = newSupplier.id;
      allSuppliers.push(newSupplier);
    }

    // Preserve workflow status if the evaluation is already past draft
    // AND the recomputed scores would come out the same — otherwise
    // (score would actually change) fall back to draft so the change
    // goes through review again rather than silently altering an
    // already-approved historical record.
    const existing = evaluations.find(e => e.supplier?.id === supplierId && e.year === r.year && e.month === r.month);
    const recomputed = ieRecomputeFromOccurrence(r.occ);
    let statusPayload = {};
    if (existing && !['draft'].includes(existing.status)) {
      const scoreUnchanged = Math.abs(toNum(existing.quality_score) - recomputed.quality) < 0.5
        && (r.noShipment || Math.abs(toNum(existing.delivery_score) - recomputed.delivery) < 0.5);
      if (!scoreUnchanged) statusPayload = { status: 'draft', quality_submitted_at: null, delivery_submitted_at: null };
    }

    const evalPayload = {
      supplier_id: supplierId, year: r.year, month: r.month,
      scoring_mode: 'itemized',
      shipment_status: r.noShipment ? 'no_shipment' : 'normal',
      no_shipment_reason: r.noShipment ? 'Imported from Excel — no shipment/purchase that month' : null,
      quality_score: 0, delivery_score: 0, purchase_score: 0,
    };
    if (!existing) evalPayload.status = 'draft'; // new row: must set a valid initial status
    Object.assign(evalPayload, statusPayload); // only present at all if we decided to bounce back to draft

    const { data: evalRow, error: evalErr } = await sb.from('evaluations').upsert(evalPayload, { onConflict: 'supplier_id,year,month' }).select().single();
    if (evalErr) { failed++; console.error(evalErr); continue; }

    const itemRows = Object.entries(r.occ).map(([itemNo,count]) => {
      const c = evaluationCriteria.find(cr => cr.item_no === itemNo && cr.is_active);
      return c ? { evaluation_id: evalRow.id, criteria_id: c.id, occurrence: count } : null;
    }).filter(Boolean);
    if (itemRows.length) {
      const { error: itemErr } = await sb.from('evaluation_items').upsert(itemRows, { onConflict: 'evaluation_id,criteria_id' });
      if (itemErr) { failed++; console.error(itemErr); continue; }
    }
    // No separate "recompute" step needed here — evaluation_items has
    // an AFTER INSERT/UPDATE/DELETE trigger (trg_evaluation_item_
    // recompute, see 10_phase3_autocalc.sql) that already calls
    // recompute_evaluation_scores() automatically the instant the
    // upsert above completes. An earlier version of this function
    // added a manual RPC call here too, "just in case" — that was
    // redundant, and when an attempt to speed it up by batching those
    // calls concurrently caused a real hang, removing it entirely
    // turned out to be the actual fix, not just working around it.

    existing ? updated++ : created++;
  }

  resultEl.textContent = `${L('Done','เสร็จสิ้น')} — ${L('created','สร้างใหม่')}: ${created}, ${L('updated','อัปเดต')}: ${updated}, ${L('failed','ล้มเหลว')}: ${failed}`;
  await loadAllSuppliers(); await loadEvaluations(); await loadAllEvaluationItems();
  renderAll();
}

// ---- Export: clone the real blank template sheet per selected evaluation ----
let ieExportTemplateWb = null;
async function ieGetExportTemplate(){
  if (ieExportTemplateWb) return ieExportTemplateWb;
  const res = await fetch('assets/fm0704_export_template.xlsx');
  const buf = await res.arrayBuffer();
  ieExportTemplateWb = XLSX.read(buf, { type:'array', cellStyles:true });
  return ieExportTemplateWb;
}

async function exportSelectedEvaluations(){
  const ids = [...evalSelection];
  if (!ids.length) return;
  const templateWb = await ieGetExportTemplate();
  const templateSheetName = 'FM0704-3 Rev.2(P.1)';
  const templateSheet = templateWb.Sheets[templateSheetName];
  if (!templateSheet) { alert('Template sheet not found in bundled asset.'); return; }

  const outWb = XLSX.utils.book_new();
  for (const id of ids) {
    const e = evaluations.find(x=>x.id===id);
    if (!e) continue;
    const sheet = JSON.parse(JSON.stringify(templateSheet));
    const set = (ref, v) => { sheet[ref] = { ...(sheet[ref]||{}), v, t: typeof v === 'number' ? 'n' : 's' }; };
    set('C3', e.supplier?.name || '');
    set('C4', e.supplier?.attention || '');
    set('I4', e.supplier?.tel || '');
    set('S4', MONTHS[e.month-1].toUpperCase());
    const items = allEvaluationItems.filter(x=>x.evaluation_id===e.id);
    Object.entries(IE_ROW_TO_ITEM).forEach(([row,itemNo]) => {
      const item = items.find(i => evaluationCriteria.find(cr=>cr.id===i.criteria_id)?.item_no === itemNo);
      set(`N${row}`, item ? toNum(item.occurrence) : 0);
    });
    let sheetName = (e.supplier?.short_name || e.supplier?.code || 'Supplier').replace(/[\\/?*[\]:]/g,'').slice(0,28);
    let uniqueName = sheetName, i2 = 1;
    while (outWb.SheetNames.includes(uniqueName)) { uniqueName = `${sheetName.slice(0,25)}_${++i2}`; }
    XLSX.utils.book_append_sheet(outWb, sheet, uniqueName);
  }
  const fname = `Evaluation_Export_${new Date().toISOString().slice(0,10)}.xlsx`;
  XLSX.writeFile(outWb, fname);
}

function resetSupplierForm(){
  ['ms_code','ms_name','ms_short_name','ms_category','ms_attention','ms_tel','ms_email'].forEach(id => document.getElementById(id).value = '');
  document.getElementById('ms_target_score').value = 80;
  document.getElementById('ms_is_active').checked = true;
  delete document.getElementById('btnSupplierSave').dataset.editId;
}

function editSupplier(id){
  const s = allSuppliers.find(x => x.id === id);
  if (!s) return;
  document.getElementById('ms_code').value = s.code || '';
  document.getElementById('ms_name').value = s.name || '';
  document.getElementById('ms_short_name').value = s.short_name || '';
  document.getElementById('ms_category').value = s.category || supplierGroupFromCode(s.code);
  document.getElementById('ms_attention').value = s.attention || '';
  document.getElementById('ms_tel').value = s.tel || '';
  document.getElementById('ms_email').value = s.email || '';
  document.getElementById('ms_target_score').value = s.target_score ?? 80;
  document.getElementById('ms_is_active').checked = !!s.is_active;
  document.getElementById('btnSupplierSave').dataset.editId = id;
}

async function saveSupplier(){
  const code = document.getElementById('ms_code').value.trim();
  const name = document.getElementById('ms_name').value.trim();
  if (!code || !name) { alert(lang==='th' ? 'กรุณากรอก Code และ Name' : 'Please enter Code and Name'); return; }
  const editId = document.getElementById('btnSupplierSave').dataset.editId;
  const payload = {
    code, name,
    short_name: document.getElementById('ms_short_name').value.trim() || null,
    category: supplierGroupFromCode(code) || null,
    attention: document.getElementById('ms_attention').value.trim() || null,
    tel: document.getElementById('ms_tel').value.trim() || null,
    email: document.getElementById('ms_email').value.trim() || null,
    target_score: toNum(document.getElementById('ms_target_score').value) || 80,
    is_active: document.getElementById('ms_is_active').checked,
  };
  let error;
  if (editId) ({ error } = await sb.from('suppliers').update(payload).eq('id', editId));
  else ({ error } = await sb.from('suppliers').insert(payload));
  if (error) { alert('Save failed: ' + error.message); console.error(error); return; }
  await loadAllSuppliers();
  await loadSuppliers();
  resetSupplierForm();
  renderAll();
  alert(lang==='th' ? 'บันทึกข้อมูลแล้ว' : 'Saved');
}

async function deleteSupplier(id){
  if (!confirm(lang==='th' ? 'ลบ Supplier นี้ใช่ไหม? (ถ้ามีผลประเมินผูกอยู่จะลบไม่ได้ — ใช้ปิด Active แทน)' : 'Delete this supplier? (Will fail if evaluations reference it — deactivate instead.)')) return;
  const { error } = await sb.from('suppliers').delete().eq('id', id);
  if (error) { alert('Delete failed: ' + error.message); return; }
  await loadAllSuppliers();
  await loadSuppliers();
  renderAll();
}

function renderMasterSupplierTable(){
  const el = document.getElementById('masterSupplierTable');
  if (!allSuppliers.length) { el.innerHTML = `<div class="empty-note">${t('noData','No data yet')}</div>`; return; }
  const H = lang==='th'
    ? ['รหัส','ชื่อ','ชื่อย่อ','หมวด','เป้าหมาย','ใช้งาน','จัดการ']
    : ['Code','Name','Short Name','Category','Target','Active','Action'];
  el.innerHTML = `<table><thead><tr>${H.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${
    allSuppliers.map(s => `<tr>
      <td><b>${escapeHtml(s.code)}</b></td>
      <td>${escapeHtml(s.name)}</td>
      <td>${escapeHtml(s.short_name)||'-'}</td>
      <td>${escapeHtml(s.category)||'-'}</td>
      <td class="num">${s.target_score ?? '-'}</td>
      <td>${s.is_active ? `<span class="badge ok">${lang==='th'?'ใช้งาน':'Active'}</span>` : `<span class="badge risk">${lang==='th'?'ปิด':'Inactive'}</span>`}</td>
      <td>
        <button class="row-btn" onclick="editSupplier('${s.id}')">${t('edit', lang==='th'?'แก้ไข':'Edit')}</button>
        <button class="row-btn danger" onclick="deleteSupplier('${s.id}')">${t('del', lang==='th'?'ลบ':'Delete')}</button>
      </td>
    </tr>`).join('')
  }</tbody></table>`;
}

/* ============================================================
   Master Control — Evaluation Criteria
   ============================================================ */
function resetCriteriaForm(){
  document.getElementById('mc_category').value = 'quality';
  document.getElementById('mc_item_no').value = '';
  document.getElementById('mc_description').value = '';
  document.getElementById('mc_description_th').value = '';
  document.getElementById('mc_full_score').value = '';
  document.getElementById('mc_deduction').value = '';
  document.getElementById('mc_display_order').value = 0;
  document.getElementById('mc_is_active').checked = true;
  delete document.getElementById('btnCriteriaSave').dataset.editId;
}

function editCriteria(id){
  const c = evaluationCriteria.find(x => x.id === id);
  if (!c) return;
  document.getElementById('mc_category').value = c.category;
  document.getElementById('mc_item_no').value = c.item_no || '';
  document.getElementById('mc_description').value = c.description || '';
  document.getElementById('mc_description_th').value = c.description_th || '';
  document.getElementById('mc_full_score').value = c.full_score ?? '';
  document.getElementById('mc_deduction').value = c.deduction_points ?? '';
  document.getElementById('mc_display_order').value = c.display_order ?? 0;
  document.getElementById('mc_is_active').checked = !!c.is_active;
  document.getElementById('btnCriteriaSave').dataset.editId = id;
}

async function saveCriteria(){
  const itemNo = document.getElementById('mc_item_no').value.trim();
  const description = document.getElementById('mc_description').value.trim();
  if (!itemNo || !description) { alert(lang==='th' ? 'กรุณากรอก Item No. และ Description' : 'Please enter Item No. and Description'); return; }
  const editId = document.getElementById('btnCriteriaSave').dataset.editId;
  const fullScoreRaw = document.getElementById('mc_full_score').value;
  const deductionRaw = document.getElementById('mc_deduction').value;
  const category = document.getElementById('mc_category').value;
  const descriptionTh = document.getElementById('mc_description_th').value.trim() || null;
  const fullScore = fullScoreRaw === '' ? null : toNum(fullScoreRaw);
  const deduction = deductionRaw === '' ? null : toNum(deductionRaw);
  const displayOrder = toNum(document.getElementById('mc_display_order').value) || 0;
  const isActive = document.getElementById('mc_is_active').checked;

  if (!editId) {
    // Brand new criteria — start a new lineage.
    const { error } = await sb.rpc('create_new_criteria', {
      p_category: category, p_item_no: itemNo, p_description: description, p_description_th: descriptionTh,
      p_full_score: fullScore, p_deduction_points: deduction, p_display_order: displayOrder,
    });
    if (error) { alert('Save failed: ' + error.message); console.error(error); return; }
  } else {
    const { data: isUsed, error: checkErr } = await sb.rpc('criteria_is_used', { p_criteria_id: editId });
    if (checkErr) { alert('Check failed: ' + checkErr.message); console.error(checkErr); return; }

    if (isUsed) {
      // Already used in a real evaluation — every field except
      // display_order/is_active is locked. Only offer to version if
      // something beyond those two actually changed.
      const current = evaluationCriteria.find(c => c.id === editId);
      const contentChanged = current && (
        current.category !== category || current.item_no !== itemNo ||
        current.description !== description || (current.description_th||null) !== descriptionTh ||
        toNum(current.full_score) !== fullScore || toNum(current.deduction_points) !== deduction
      );
      if (contentChanged) {
        if (!confirm(L(
          'This criteria has already been used in a real evaluation. Saving will create a new version (v' + ((current?.version||1)+1) + ') and deactivate this one — historical evaluations keep pointing at the old version, unaffected. Continue?',
          'หัวข้อนี้เคยใช้ในผลประเมินจริงแล้ว การบันทึกจะสร้างเวอร์ชันใหม่ (v' + ((current?.version||1)+1) + ') และปิดตัวเดิม — ผลประเมินเก่ายังผูกกับเวอร์ชันเดิม ไม่กระทบ ดำเนินการต่อหรือไม่?'
        ))) return;
        const { error } = await sb.rpc('create_criteria_version', {
          p_old_id: editId, p_category: category, p_item_no: itemNo, p_description: description, p_description_th: descriptionTh,
          p_full_score: fullScore, p_deduction_points: deduction, p_display_order: displayOrder,
        });
        if (error) { alert('Save failed: ' + error.message); console.error(error); return; }
      } else {
        // Only display_order/is_active changed — plain update is allowed.
        const { error } = await sb.from('evaluation_criteria').update({ display_order: displayOrder, is_active: isActive }).eq('id', editId);
        if (error) { alert('Save failed: ' + error.message); console.error(error); return; }
      }
    } else {
      // Never used yet — free to edit directly.
      const { error } = await sb.from('evaluation_criteria').update({
        category, item_no: itemNo, description, description_th: descriptionTh,
        full_score: fullScore, deduction_points: deduction, display_order: displayOrder, is_active: isActive,
      }).eq('id', editId);
      if (error) { alert('Save failed: ' + error.message); console.error(error); return; }
    }
  }

  await loadEvaluationCriteria();
  resetCriteriaForm();
  renderAll();
  alert(lang==='th' ? 'บันทึกข้อมูลแล้ว' : 'Saved');
}

async function deleteCriteria(id){
  if (!confirm(lang==='th' ? 'ลบหัวข้อประเมินนี้ใช่ไหม? (ถ้ามี evaluation_items ผูกอยู่จะลบไม่ได้ — ใช้ปิด Active แทน)' : 'Delete this criteria item? (Will fail if evaluation_items reference it — deactivate instead.)')) return;
  const { error } = await sb.from('evaluation_criteria').delete().eq('id', id);
  if (error) { alert('Delete failed: ' + error.message); return; }
  await loadEvaluationCriteria();
  renderAll();
}

function renderMasterCriteriaTable(){
  const el = document.getElementById('masterCriteriaTable');
  if (!evaluationCriteria.length) { el.innerHTML = `<div class="empty-note">${t('noData','No data yet')}</div>`; return; }
  const H = lang==='th'
    ? ['หมวด','รหัสข้อ','คำอธิบาย (EN)','คำอธิบาย (TH)','เต็ม','หัก/เครดิต','ลำดับ','เวอร์ชัน','ใช้งาน','จัดการ']
    : ['Category','Item No.','Description (EN)','Description (TH)','Full','Deduction/Credit','Order','Version','Active','Action'];
  const sorted = [...evaluationCriteria].sort((a,b) => a.display_order - b.display_order || a.version - b.version);
  el.innerHTML = `<table><thead><tr>${H.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${
    sorted.map(c => {
      const superseded = !!c.superseded_by;
      return `<tr${superseded?' style="opacity:.55"':''}>
      <td>${c.category}</td>
      <td><b>${c.item_no}</b></td>
      <td class="muted-small">${c.description}</td>
      <td class="muted-small">${c.description_th || '<span class="badge risk">' + (lang==='th'?'ยังไม่แปล':'Not translated') + '</span>'}</td>
      <td class="num">${c.full_score ?? '-'}</td>
      <td class="num">${c.deduction_points ?? '-'}</td>
      <td class="num">${c.display_order}</td>
      <td class="muted-small">v${c.version}${superseded?` → ${L('superseded','ถูกแทนที่แล้ว')}`:''}</td>
      <td>${c.is_active ? `<span class="badge ok">${lang==='th'?'ใช้งาน':'Active'}</span>` : `<span class="badge risk">${lang==='th'?'ปิด':'Inactive'}</span>`}</td>
      <td>
        <button class="row-btn" onclick="editCriteria('${c.id}')">${t('edit', lang==='th'?'แก้ไข':'Edit')}</button>
        <button class="row-btn danger" onclick="deleteCriteria('${c.id}')">${t('del', lang==='th'?'ลบ':'Delete')}</button>
      </td>
    </tr>`; }).join('')
  }</tbody></table>`;
}

/* ============================================================
   Master Control — Users & Roles
   ============================================================ */
async function createUser(){
  const resultEl = document.getElementById('createUserResult');
  const userId = document.getElementById('nu_userid').value.trim();
  const password = document.getElementById('nu_password').value;
  const fullName = document.getElementById('nu_fullname').value.trim();
  const department = document.getElementById('nu_department').value;
  if (!userId || !password) { alert(L('User ID and password are required','กรุณากรอก User ID และรหัสผ่าน')); return; }
  if (password.length < 6) { alert(L('Password must be at least 6 characters','รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร')); return; }

  resultEl.textContent = L('Creating account…','กำลังสร้างบัญชี…');
  resultEl.classList.remove('create-user-success');
  // NOTE: this calls the Edge Function by its actual deployed slug,
  // not a descriptive name — Supabase's dashboard "Name" column is
  // purely cosmetic and does NOT change the URL/routing slug a
  // function was created with. This project's function was first
  // deployed as "hyper-processor" (a template default name that
  // didn't get changed before deploying), and renaming it in the
  // dashboard only updated the display label, not the real slug —
  // confirmed from the dashboard's own URL column still reading
  // .../functions/v1/hyper-processor after the rename. Simpler to
  // point the app at the real slug than to fight the dashboard UI.
  const { data, error } = await sb.functions.invoke('hyper-processor', {
    body: { userId, password, fullName, department },
  });
  if (error || data?.error) {
    const msg = data?.error || error.message;
    resultEl.textContent = '';
    alert(L('Failed to create account: ','สร้างบัญชีไม่สำเร็จ: ') + msg);
    console.error(error || data?.error);
    return;
  }
  resultEl.textContent = L(`Account created: ${userId} (${department}) — password: ${password} — note it down now, it can't be shown again`,`สร้างบัญชีแล้ว: ${userId} (${department}) — รหัสผ่าน: ${password} — จดไว้ตอนนี้เลย จะไม่โชว์ซ้ำอีก`);
  resultEl.classList.add('create-user-success');
  document.getElementById('nu_userid').value = '';
  document.getElementById('nu_password').value = '';
  document.getElementById('nu_fullname').value = '';
  document.getElementById('nu_department').value = 'qa';
  await loadUserProfilesList();
  renderAll();
}

async function changeUserDepartment(userId, department){
  const { error } = await sb.from('user_profiles').update({ department }).eq('id', userId);
  if (error) { alert('Update failed: ' + error.message); console.error(error); return; }
  await loadUserProfilesList();
  renderMasterUsersTable();
  renderAll();
}

async function editUserFullName(userId, currentName){
  const next = prompt(L('New full name for this user:','ชื่อ-นามสกุลใหม่สำหรับบัญชีนี้:'), currentName || '');
  if (next === null) return; // cancelled
  const { error } = await sb.from('user_profiles').update({ full_name: next.trim() }).eq('id', userId);
  if (error) { alert('Update failed: ' + error.message); console.error(error); return; }
  await loadUserProfilesList();
  renderMasterUsersTable();
  renderAll();
}

// NOTE: same slug-vs-display-name caveat as admin-create-user — call
// this by whatever slug the Edge Functions page's URL column actually
// shows for the function you deploy, not necessarily the literal
// string below. Update this one string if your deployed slug differs.
const ADMIN_MANAGE_USER_FN = 'admin-manage-user';

async function deleteUserAccount(userId, label){
  if (!confirm(L(`Permanently delete the account "${label}"? This cannot be undone.`,`ลบบัญชี "${label}" ถาวร? กู้คืนไม่ได้`))) return;
  const { data, error } = await sb.functions.invoke(ADMIN_MANAGE_USER_FN, { body: { action: 'delete', userId } });
  if (error || data?.error) {
    alert(L('Delete failed: ','ลบไม่สำเร็จ: ') + (data?.error || error.message));
    console.error(error || data?.error);
    return;
  }
  await loadUserProfilesList();
  renderMasterUsersTable(); // guaranteed immediate refresh of this table, even if something else in renderAll() fails partway through
  renderAll();
}

async function resetUserPassword(userId, label){
  const newPassword = prompt(L(`Set a new password for "${label}" (min 6 characters):`,`ตั้งรหัสผ่านใหม่ให้ "${label}" (อย่างน้อย 6 ตัวอักษร):`));
  if (newPassword === null) return; // cancelled
  if (newPassword.length < 6) { alert(L('Password must be at least 6 characters','รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร')); return; }
  const { data, error } = await sb.functions.invoke(ADMIN_MANAGE_USER_FN, { body: { action: 'reset_password', userId, newPassword } });
  if (error || data?.error) {
    alert(L('Password reset failed: ','ตั้งรหัสผ่านใหม่ไม่สำเร็จ: ') + (data?.error || error.message));
    console.error(error || data?.error);
    return;
  }
  alert(L(`Password reset — new password: ${newPassword} — give this to the user now, it can't be shown again`,`ตั้งรหัสผ่านใหม่แล้ว — รหัสผ่านใหม่: ${newPassword} — แจ้งผู้ใช้ตอนนี้เลย จะไม่โชว์ซ้ำอีก`));
}

function renderMasterUsersTable(){
  const el = document.getElementById('masterUsersTable');
  if (!userProfilesList.length) { el.innerHTML = `<div class="empty-note">${t('noData','No data yet')}</div>`; return; }
  const depts = ['qa','cs','mp','cs_supervisor','mp_supervisor','opd_manager','admin'];
  const deptDisplay = { qa:'QA', cs:'CS', mp:'MP', cs_supervisor:'CS Supervisor', mp_supervisor:'MP Supervisor', opd_manager:'OPD Manager', admin:'Admin' };
  const H = lang==='th' ? ['ชื่อ','User ID (บางส่วน)','แผนก','สมัครเมื่อ','จัดการ'] : ['Name','User ID (partial)','Department','Joined','Action'];
  el.innerHTML = `<table><thead><tr>${H.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${
    userProfilesList.map(u => { const label = escapeHtml((u.full_name || u.id.slice(0,8)).replace(/'/g,"\\'")); return `<tr>
      <td>${u.full_name || '-'}</td>
      <td class="muted-small">${u.id.slice(0,8)}…</td>
      <td>
        <select onchange="changeUserDepartment('${u.id}', this.value)">
          ${depts.map(d => `<option value="${d}" ${u.department===d?'selected':''}>${deptDisplay[d]}</option>`).join('')}
          ${u.department==='supervisor' ? `<option value="supervisor" selected>Admin (legacy value — re-save to migrate)</option>` : ''}
        </select>
      </td>
      <td class="muted-small">${(u.created_at||'').slice(0,10)}</td>
      <td class="nowrap">
        <button class="row-btn" onclick="editUserFullName('${u.id}','${label}')" title="${L('Edit name','แก้ชื่อ')}">✏️</button>
        <button class="row-btn" onclick="resetUserPassword('${u.id}','${label}')" title="${L('Reset password','ตั้งรหัสผ่านใหม่')}">🔑</button>
        <button class="row-btn danger" onclick="deleteUserAccount('${u.id}','${label}')" title="${L('Delete','ลบ')}">🗑️</button>
      </td>
    </tr>`; }).join('')
  }</tbody></table>`;
}


/* ============================================================
   Supplier Command Center dashboard v0.8.0
   ============================================================ */
let dashItemRows = [];
// Screen-space points from the last Risk Matrix draw, kept around so the
// mousemove/click handlers (wired once in wireEvents) can hit-test against
// whatever was plotted most recently, without re-attaching a listener on
// every dashboard refresh.
let riskMatrixPoints = [];
function evalPeriodKey(e){ return `${e.year}-${String(e.month).padStart(2,'0')}`; }
function periodKeyToLabel(key){ const [y,m] = String(key).split('-'); return ymLabel(y, parseInt(m,10)); }
function selectedDashPeriod(){ return document.getElementById('dashPeriod')?.value || ''; }
function populateDashboardFilters(){
  const p=document.getElementById('dashPeriod'); if(!p) return;
  const prev=p.value;
  const periods=[...new Set(evaluations.map(evalPeriodKey))].sort().reverse();
  p.innerHTML=periods.map(x=>`<option value="${x}">${periodKeyToLabel(x)}</option>`).join('');
  p.value=periods.includes(prev)?prev:(periods[0]||'');
  const c=document.getElementById('dashCategory');
  const old=c.value;
  const cats=[...new Set(allSuppliers.map(s=>s.category).filter(Boolean))].sort();
  c.innerHTML=`<option value="">${L('All groups','ทุกกลุ่ม')}</option>`+cats.map(x=>`<option>${x}</option>`).join(''); c.value=cats.includes(old)?old:'';
}
function dashboardEvaluations(){
  const period=selectedDashPeriod(), cat=document.getElementById('dashCategory')?.value||'', ship=document.getElementById('dashShipment')?.value||'', risk=document.getElementById('dashRisk')?.value||'';
  return evaluations.filter(e=>{
    if(period && evalPeriodKey(e)!==period) return false;
    const sm=allSuppliers.find(s=>s.id===e.supplier?.id);
    if(cat && sm?.category!==cat) return false;
    if(ship && (e.shipment_status||'normal')!==ship) return false;
    if(risk && riskBand(supplierRisk(e))!==risk) return false;
    return true;
  });
}
// An evaluation only counts toward scores/risk/trends once BOTH sections
// (Quality and Delivery/Purchase) have been submitted. Freshly opened
// drafts carry placeholder scores and must not distort averages.
function isEvalComplete(e){ return !!(e && e.quality_submitted_at && e.delivery_submitted_at); }
function supplierHistory(e){ return evaluations.filter(x=>x.supplier?.id===e.supplier?.id && isEvalComplete(x)).sort((a,b)=>a.year-b.year||a.month-b.month); }
function scoreDelta(e){ const h=supplierHistory(e), i=h.findIndex(x=>x.id===e.id); return i>0?toNum(e.total_score)-toNum(h[i-1].total_score):0; }
function declining(e){ const h=supplierHistory(e).filter(x=>x.year<e.year||(x.year===e.year&&x.month<=e.month)); if(h.length<3)return false; const a=h.slice(-3).map(x=>toNum(x.total_score)); return a[0]>a[1]&&a[1]>a[2]; }
function caForEval(e){ return correctiveActions.filter(c=>c.evaluation?.id===e.id); }
function supplierRisk(e){
  let r=0, delta=scoreDelta(e), cas=caForEval(e);
  if(!isEvalComplete(e)){ // unfinished draft: only corrective-action signals, never its placeholder score
    if(cas.some(isCaOverdue)) r+=30; else if(cas.some(c=>c.status!=='closed')) r+=12;
    return Math.min(100,r);
  }
  if(toNum(e.total_score)<80) r+=30; else if(toNum(e.total_score)<90) r+=12;
  if(delta<=-5) r+=18; else if(delta<0) r+=8;
  if(declining(e)) r+=18;
  if(cas.some(isCaOverdue)) r+=30; else if(cas.some(c=>c.status!=='closed')) r+=12;
  if(e.status!=='mgr_approved'&&e.status!=='sent_to_supplier'&&e.status!=='acknowledged') r+=7;
  if(e.scoring_mode==='manual') r+=5;
  return Math.min(100,r);
}
function riskBand(r){ return r>=80?'critical':r>=60?'high':r>=35?'watch':'low'; }
function riskBandLabel(band){ return { critical:L('Very High Risk','เสี่ยงมาก'), high:L('High Risk','เสี่ยงสูง'), watch:L('Moderate Risk','ปานกลาง'), low:L('Slight Risk','เล็กน้อย') }[band] || band; }
function dashboardCa(){ const ids=new Set(dashboardEvaluations().map(e=>e.id)); return correctiveActions.filter(c=>ids.has(c.evaluation?.id)); }
/* ============================================================
   Action Board — "what do I need to do" (v1.8.0)
   Deliberately independent of the Dashboard's own period/category
   filters — a to-do list should show real pending work regardless of
   which period someone happens to be browsing, not disappear because
   a filter is set. Always uses full evaluations/correctiveActions/
   allSuppliers state.
   ============================================================ */
function startNewEvaluationFor(supplierId, year, month){
  showTab('input');
  resetForm();
  document.getElementById('f_supplier').value = supplierId;
  document.getElementById('f_year').value = year;
  document.getElementById('f_month').value = month;
  openOrCreateWorksheet();
}

function renderActionBoard(){
  if (!document.getElementById('actionTabs')) return;
  const today = new Date();
  const curYear = today.getFullYear(), curMonth = today.getMonth()+1;

  // Reuses the Dashboard's own period/group filter bar (moved above the
  // Action Board) — period defaults to the latest period with data
  // (see populateDashboardFilters), so the to-do list is scoped to
  // "this cycle" by default instead of every unfinished item ever.
  const periodFilter = selectedDashPeriod();
  const categoryFilter = document.getElementById('dashCategory')?.value || '';
  const matchesFilter = (e) => {
    if (periodFilter && evalPeriodKey(e) !== periodFilter) return false;
    if (categoryFilter && e.supplier?.category !== categoryFilter) return false;
    return true;
  };
  const scopedEvaluations = evaluations.filter(matchesFilter);

  const qaItems = [];
  const csItems = [];
  const supItems = [];
  const mgrItems = [];

  // QA — quality not yet submitted (a rejected evaluation is flagged
  // distinctly and bumped to the top instead of blending into
  // ordinary new items — only checks quality_submitted_at here since
  // we're already inside "quality not submitted", and reject can now
  // target just one section).
  scopedEvaluations.forEach(e => {
    if (!e.quality_submitted_at) {
      const rejected = e.status === 'draft' && !!e.rejection_reason;
      qaItems.push({
        title: `${e.supplier?.code||''} · ${ymLabel(e.year,e.month)}`,
        subtitle: rejected ? L('Rejected — fix and resubmit','ถูก Reject — แก้ไขแล้วส่งใหม่') : L('Quality not submitted yet','รอกรอก Quality'),
        tag: rejected ? L('Fix & resubmit','แก้ไข & ส่งใหม่') : L('Evaluate','ประเมิน'),
        onclick: `editEvaluation('${e.id}')`,
        overdue: rejected,
        sortKey: rejected ? '0' : `1${e.year}${String(e.month).padStart(2,'0')}`,
      });
    }
  });
  qaItems.sort((a,b) => a.sortKey.localeCompare(b.sortKey));

  // CS/MP — suppliers with no evaluation opened for the current calendar
  // month. Always tied to the real current month (not the period filter
  // above — "not opened yet" only makes sense for the actual present),
  // but still respects the supplier-group filter.
  const openedThisMonth = new Set(evaluations.filter(e=>e.year===curYear&&e.month===curMonth).map(e=>e.supplier?.id));
  allSuppliers.filter(s => s.is_active!==false && (!categoryFilter || s.category===categoryFilter)).forEach(s => {
    if (!openedThisMonth.has(s.id)) {
      csItems.push({
        title: `${s.code} · ${s.short_name||s.name}`,
        subtitle: L('Not opened this month yet','ยังไม่เปิดรายการเดือนนี้'),
        tag: L('Open','เปิดรายการ'),
        onclick: `startNewEvaluationFor('${s.id}',${curYear},${curMonth})`,
        sortKey: '0',
      });
    }
  });
  // CS/MP — delivery/purchase not yet submitted (same rejected-state
  // flag as the QA list above)
  scopedEvaluations.forEach(e => {
    if (!e.delivery_submitted_at) {
      const rejected = e.status === 'draft' && !!e.rejection_reason;
      csItems.push({
        title: `${e.supplier?.code||''} · ${ymLabel(e.year,e.month)}`,
        subtitle: rejected ? L('Rejected — fix and resubmit','ถูก Reject — แก้ไขแล้วส่งใหม่') : L('Delivery/Purchase not submitted yet','รอกรอก Delivery/Purchase'),
        tag: rejected ? L('Fix & resubmit','แก้ไข & ส่งใหม่') : L('Evaluate','ประเมิน'),
        onclick: `editEvaluation('${e.id}')`,
        overdue: rejected,
        sortKey: rejected ? '0' : '1',
      });
    }
  });
  // CS/MP — Manager-approved, waiting to be marked sent
  scopedEvaluations.forEach(e => {
    if (e.status === 'mgr_approved' && !e.sent_at) {
      csItems.push({
        title: `${e.supplier?.code||''} · ${ymLabel(e.year,e.month)}`,
        subtitle: L('Approved — mark as sent once emailed','อนุมัติแล้ว รอทำเครื่องหมายว่าส่งแล้ว'),
        tag: L('Mark Sent','ส่งผลแล้ว'),
        onclick: `editEvaluation('${e.id}')`,
        sortKey: '2',
      });
    }
  });
  // CS/MP — open corrective actions (ownership moved from QA to CS/MP in v33)
  correctiveActions.forEach(ca => {
    if ((ca.status === 'open' || ca.status === 'in_progress') && ca.evaluation && matchesFilter({ year: ca.evaluation.year, month: ca.evaluation.month, supplier: ca.evaluation.supplier })) {
      const overdue = isCaOverdue(ca);
      csItems.push({
        title: `${ca.evaluation?.supplier?.code||''} · ${ymLabel(ca.evaluation.year,ca.evaluation.month)}`,
        subtitle: overdue ? L('Corrective action is overdue','CA เกินกำหนด — ต้องติดตาม') : L('Open — fill in findings and close when done','เปิดอยู่ — กรอกข้อมูล/แนบไฟล์ แล้วปิดเคสได้เลย'),
        tag: L('Follow up','ติดตาม CA'),
        onclick: `editCorrectiveAction('${ca.id}')`,
        overdue,
        sortKey: overdue ? '0' : '3',
      });
    }
  });
  csItems.sort((a,b) => (b.overdue?1:0)-(a.overdue?1:0) || a.sortKey.localeCompare(b.sortKey));

  // Supervisor — both sections submitted, ready for Supervisor Approve
  scopedEvaluations.forEach(e => {
    if (e.quality_submitted_at && e.delivery_submitted_at && !['sup_approved','mgr_approved','sent_to_supplier','acknowledged'].includes(e.status)) {
      supItems.push({
        title: `${e.supplier?.code||''} · ${ymLabel(e.year,e.month)}`,
        subtitle: L('Both sections submitted','Submit ครบทั้งสองฝั่งแล้ว'),
        tag: L('Sup. Approve','รออนุมัติ Supv.'),
        onclick: `editEvaluation('${e.id}')`,
      });
    }
  });

  // Manager — Supervisor-approved, ready for final Manager Approve
  scopedEvaluations.forEach(e => {
    if (e.status === 'sup_approved') {
      mgrItems.push({
        title: `${e.supplier?.code||''} · ${ymLabel(e.year,e.month)}`,
        subtitle: L('Supervisor approved','Supervisor อนุมัติแล้ว'),
        tag: L('Mgr. Approve','รออนุมัติ Mgr.'),
        onclick: `editEvaluation('${e.id}')`,
      });
    }
  });

  const canEditQuality = hasPerm('eval_edit_quality');
  const canEditDelivery = hasPerm('eval_edit_delivery');
  const canSupApprove = hasPerm('eval_sup_approve');
  const canMgrApprove = hasPerm('eval_mgr_approve');

  actionBoardData = [
    { key:'cs',  label:'CS / MP',    items: csItems,  mine: canEditDelivery },
    { key:'qa',  label:'QA',         items: qaItems,  mine: canEditQuality },
    { key:'sup', label:'Supervisor', items: supItems, mine: canSupApprove },
    { key:'mgr', label:'Manager',    items: mgrItems, mine: canMgrApprove },
  ];
  renderActionTabs();
}

function renderActionColumnSimple(elId, items, mine){
  const el = document.getElementById(elId);
  if (!el) return;
  const col = el.closest('.action-col');
  if (col) col.classList.toggle('mine', mine);
  if (!items.length) {
    el.innerHTML = `<div class="action-empty">✓ ${L('All caught up','ครบหมดแล้ว')}</div>`;
    return;
  }
  const shown = items.slice(0, 3);
  el.innerHTML = shown.map(it => `
    <button class="action-item${it.overdue?' overdue':''}" onclick="${it.onclick}">
      <div class="action-item-main"><b>${it.title}</b><span>${it.subtitle}</span></div>
      <span class="action-item-tag">${it.tag}</span>
    </button>`).join('');
  if (items.length > 3) {
    const btn = document.createElement('button');
    btn.className = 'action-viewall';
    btn.textContent = `${L('View all','ดูทั้งหมด')} (${items.length})`;
    btn.addEventListener('click', () => showTab('list'));
    el.appendChild(btn);
  }
}


/* ============================================================
   Dashboard v92 — month header, role tabs, 4 tiles, cycle health,
   watch list (sparklines), collapsible history overview.
   All score-based numbers count only COMPLETED evaluations
   (both sections submitted) — see isEvalComplete().
   ============================================================ */
const MONTHS_FULL_EN=['January','February','March','April','May','June','July','August','September','October','November','December'];
const MONTHS_FULL_TH=['มกราคม','กุมภาพันธ์','มีนาคม','เมษายน','พฤษภาคม','มิถุนายน','กรกฎาคม','สิงหาคม','กันยายน','ตุลาคม','พฤศจิกายน','ธันวาคม'];
function monthFull(m){ return (lang==='th'?MONTHS_FULL_TH:MONTHS_FULL_EN)[(m||1)-1] || ''; }
function bangkokToday(){
  const p=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());
  const g=k=>parseInt(p.find(x=>x.type===k).value,10);
  return {y:g('year'),m:g('month'),d:g('day')};
}
function dashPeriodKeys(){ // ascending, only periods that have evaluations
  const sel=document.getElementById('dashPeriod'); if(!sel) return [];
  return [...sel.options].map(o=>o.value).filter(Boolean).sort();
}
function setDashPeriod(key){
  const sel=document.getElementById('dashPeriod'); if(!sel||!key) return;
  sel.value=key; refreshDashboard();
}
function dashboardTrendScope(){
  const cat=document.getElementById('dashCategory')?.value||'', ship=document.getElementById('dashShipment')?.value||'';
  return evaluations.filter(e=>{
    if(cat){ const sm=allSuppliers.find(s=>s.id===e.supplier?.id); if(sm?.category!==cat) return false; }
    if(ship && (e.shipment_status||'normal')!==ship) return false;
    return true;
  });
}
function daysSince(ts){ if(!ts) return null; const d=Math.floor((Date.now()-new Date(ts).getTime())/86400000); return d<0?0:d; }
function mean(a){ return a.length ? a.reduce((s,x)=>s+x,0)/a.length : null; }
function pct(sorted,p){ if(!sorted.length) return null; const i=(sorted.length-1)*p, lo=Math.floor(i), hi=Math.ceil(i); return sorted[lo]+(sorted[hi]-sorted[lo])*(i-lo); }

let dashPopYear = null;
function renderDashHead(arr, activeInScope){
  const keys=dashPeriodKeys();
  const cur=selectedDashPeriod();
  const now=bangkokToday();
  const [py,pm]= cur ? cur.split('-').map(n=>parseInt(n,10)) : [now.y, now.m];
  document.getElementById('dashMonthText').textContent=`${monthFull(pm)} ${py}`;
  const idx=keys.indexOf(cur);
  document.getElementById('dashPrev').disabled = !(idx>0);
  document.getElementById('dashNext').disabled = !(idx>=0 && idx<keys.length-1);
  const done=arr.filter(isEvalComplete).length;
  document.getElementById('dashSumMain').textContent=`${L('Evaluated','ประเมินเสร็จ')} ${done} / ${activeInScope} ${L('suppliers','Supplier')}`;
  const parts=[];
  if(py===now.y && pm===now.m){
    const dim=new Date(now.y,now.m,0).getDate();
    parts.push(`${L('Days left this month:','เหลือ')} ${dim-now.d} ${L('','วันของเดือนนี้')}`.trim());
  }
  const noShip=arr.filter(e=>e.shipment_status==='no_shipment').length;
  if(noShip) parts.push(`${L('No shipment','ไม่มีการส่งของ')} ${noShip}`);
  document.getElementById('dashSumSub').textContent=parts.join(' · ');
}
function renderMonthPopover(){
  const pop=document.getElementById('dashMonthPop'); if(!pop) return;
  const keys=dashPeriodKeys(); const cur=selectedDashPeriod();
  const curY= cur ? parseInt(cur.slice(0,4),10) : bangkokToday().y;
  if(dashPopYear==null) dashPopYear=curY;
  const years=keys.map(k=>parseInt(k.slice(0,4),10));
  const minY=years.length?Math.min(...years):curY, maxY=years.length?Math.max(...years):curY;
  let cells='';
  for(let m=1;m<=12;m++){
    const key=`${dashPopYear}-${String(m).padStart(2,'0')}`;
    const has=keys.includes(key);
    cells+=`<button type="button" class="mp-cell${has?' has':' off'}${key===cur?' cur':''}" data-key="${key}" ${has?'':'disabled'}>${MONTHS[m-1]}</button>`;
  }
  pop.innerHTML=`<div class="mp-year"><button type="button" class="arrow-btn sm" data-yr="-1" ${dashPopYear<=minY?'disabled':''}>&#9664;</button><span>${dashPopYear}</span><button type="button" class="arrow-btn sm" data-yr="1" ${dashPopYear>=maxY?'disabled':''}>&#9654;</button></div>
    <div class="mp-grid">${cells}</div>
    <div class="mp-note">${L('● has evaluations · grey = none','● มีข้อมูลประเมิน · สีเทา = ยังไม่มี')}</div>
    <button type="button" class="btn btn-sm mp-latest" data-latest="1">${L('Go to latest month','ไปเดือนล่าสุด')}</button>`;
}

/* ---- Action board (tabs) ---- */
let actionBoardData = null, actionTabSel = null;
const ACTION_ROLES = [
  {key:'cs',  label:'CS / MP'},
  {key:'qa',  label:'QA'},
  {key:'sup', label:'Supervisor'},
  {key:'mgr', label:'Manager'},
];
function actionItemAge(role, it){
  const m=/editEvaluation\('([^']+)'\)/.exec(it.onclick||''); if(!m) return null;
  const e=evaluations.find(x=>x.id===m[1]); if(!e) return null;
  if(it.overdue && e.rejected_at) return {d:daysSince(e.rejected_at), kind:'waiting'};
  if(role==='sup'){ const t=[e.quality_submitted_at,e.delivery_submitted_at].filter(Boolean).sort().pop(); const d=daysSince(t); return d==null?null:{d,kind:'waiting'}; }
  if(role==='mgr'){ const d=daysSince(e.sup_approved_at); return d==null?null:{d,kind:'waiting'}; }
  if(role==='cs' && e.status==='mgr_approved'){ const d=daysSince(e.mgr_approved_at); return d==null?null:{d,kind:'waiting'}; }
  const d=daysSince(new Date(e.year,e.month-1,1).toISOString());
  return d==null?null:{d,kind:'open'};
}
function renderActionTabs(){
  const wrap=document.getElementById('actionTabs'), list=document.getElementById('actionList');
  if(!wrap||!list||!actionBoardData) return;
  const data=actionBoardData;
  const first=data.find(r=>r.mine&&r.items.length)||data.find(r=>r.mine)||data.find(r=>r.items.length)||data[0];
  if(!actionTabSel || !data.some(r=>r.key===actionTabSel)) actionTabSel=first.key;
  wrap.innerHTML=data.map(r=>{
    const over=r.items.some(i=>i.overdue);
    return `<button type="button" class="tab${r.key===actionTabSel?' on':''}${over?' has-overdue':''}" data-role="${r.key}">${r.label}${r.mine?` · ${L('mine','ของฉัน')}`:''} <b>${r.items.length}</b></button>`;
  }).join('');
  const cur=data.find(r=>r.key===actionTabSel);
  if(!cur.items.length){ list.innerHTML=`<div class="action-empty wide">✓ ${L('All caught up','ครบหมดแล้ว')}</div>`; return; }
  const LIMIT=5;
  list.innerHTML=cur.items.slice(0,LIMIT).map(it=>{
    const a=actionItemAge(cur.key,it);
    const age=a&&a.d!=null?`${a.kind==='open'?L('open','เปิดมา'):L('waiting','รอ')} ${a.d} ${L('d','วัน')}`:it.tag;
    return `<button class="action-item${it.overdue?' overdue':''}" onclick="${it.onclick}">
      <div class="action-item-main"><b>${it.title}</b><span>${it.subtitle}</span></div>
      <span class="action-item-tag">${age}</span></button>`;
  }).join('')+(cur.items.length>LIMIT?`<button type="button" class="action-item action-more" data-more="${cur.key}">${L('View all','ดูทั้งหมด')} (${cur.items.length}) →</button>`:'');
}

/* ---- Main render ---- */
function renderDashboardCommandCenter(){
  if(!document.getElementById('dashMonthBtn')) return;
  renderActionBoard();
  const arr=dashboardEvaluations(), cas=dashboardCa();
  const catSel=document.getElementById('dashCategory').value;
  const activeInScope=allSuppliers.filter(s=>s.is_active!==false && (!catSel||s.category===catSel)).length||suppliers.length;
  renderDashHead(arr, activeInScope);
  renderMonthPopover();
  renderDashTiles(arr, cas);
  renderCyclePipeline(arr, activeInScope);
  renderWatchList(arr);
  renderPerformanceTrend();
  renderIssuePareto();
  // Rail badge: overdue corrective actions across everything
  const badge=document.getElementById('navCaBadge');
  if(badge){ const n=correctiveActions.filter(isCaOverdue).length; badge.textContent=n; badge.style.display=n?'inline-block':'none'; }
}
function renderDashTiles(arr, cas){
  const done=arr.filter(isEvalComplete);
  const set=(id,v)=>{const el=document.getElementById(id); if(el) el.textContent=v;};
  const avg=mean(done.map(e=>toNum(e.total_score)));
  document.getElementById('kpiAvgLabel').textContent=`${L('Average score','คะแนนเฉลี่ย')} (${done.length} ${L('completed','ใบที่เสร็จแล้ว')})`;
  document.getElementById('kpiAvg').innerHTML = avg==null ? '—' : scoreNum(avg);
  const keys=dashPeriodKeys(), cur=selectedDashPeriod(), idx=keys.indexOf(cur);
  let deltaTxt=`${L('Target','เป้า')} 80`;
  if(avg!=null && idx>0){
    const prevKey=keys[idx-1];
    const pv=mean(dashboardTrendScope().filter(e=>evalPeriodKey(e)===prevKey && isEvalComplete(e)).map(e=>toNum(e.total_score)));
    if(pv!=null){ const d=avg-pv; deltaTxt=`<span class="${d>=0?'up':'dn'}">${d>=0?'▲':'▼'} ${Math.abs(d).toFixed(1)}</span> ${L('vs previous month','จากเดือนก่อน')} · ${deltaTxt}`; }
  }
  document.getElementById('kpiAvgDelta').innerHTML=deltaTxt;
  const below=done.filter(e=>toNum(e.total_score)<(allSuppliers.find(s=>s.id===e.supplier?.id)?.target_score||80)).length;
  set('kpiBelow', below);
  set('kpiBelowSub', done.length?`${L('of','จาก')} ${done.length} ${L('completed','ใบที่เสร็จแล้ว')} →`:L('No completed evaluations yet','ยังไม่มีใบที่เสร็จ'));
  const open=cas.filter(c=>c.status!=='closed'), over=open.filter(isCaOverdue).length;
  set('kpiOpenCa', open.length);
  document.getElementById('kpiCaSub').innerHTML=over?`<span class="dn">${L('Overdue','เกินกำหนด')} ${over}</span> →`:`${L('None overdue','ไม่มีที่เกินกำหนด')} →`;
  const g={A:0,B:0,C:0,D:0}; done.forEach(e=>{ const k=e.grade||gradeOf(toNum(e.total_score)); if(g[k]!=null) g[k]++; });
  document.getElementById('kpiGradeLabel').textContent=`${L('Grade mix','การกระจายเกรด')} (${done.length})`;
  const bar=document.getElementById('gradeBar'), lg=document.getElementById('gradeLegend');
  bar.innerHTML = done.length ? ['A','B','C','D'].map(k=>g[k]?`<i class="g-${k}" style="width:${g[k]/done.length*100}%"></i>`:'').join('') : '<i class="g-none" style="width:100%"></i>';
  lg.innerHTML=['A','B','C','D'].map(k=>`<span><i class="gdot g-${k}"></i>${k} ${g[k]}</span>`).join('');
}
function renderCyclePipeline(arr,total){
  const unopened=Math.max(0,total-arr.length);
  const notStarted=unopened+arr.filter(e=>!e.quality_submitted_at&&!e.delivery_submitted_at).length;
  const supOk=['sup_approved','mgr_approved','sent_to_supplier','acknowledged'], mgrOk=['mgr_approved','sent_to_supplier','acknowledged'];
  const rows=[
    [L('Not started','ยังไม่เริ่มกรอก'),notStarted,'warn'],
    [L('QA submitted','QA ส่งแล้ว'),arr.filter(e=>e.quality_submitted_at).length,''],
    [L('CS/MP submitted','CS/MP ส่งแล้ว'),arr.filter(e=>e.delivery_submitted_at).length,''],
    [L('Supervisor approved','Supervisor อนุมัติ'),arr.filter(e=>supOk.includes(e.status)).length,''],
    [L('Manager approved (done)','Manager อนุมัติ (เสร็จ)'),arr.filter(e=>mgrOk.includes(e.status)).length,'good'],
  ];
  const donePct=total?Math.round(rows[4][1]/total*100):0;
  document.getElementById('cycleHealthPct').textContent=`${donePct}%`;
  document.getElementById('cyclePipeline').innerHTML=rows.map(([l,n,c])=>`<div class="pipe-row"><span class="pipe-label">${l}</span><div class="pipe-track"><div class="pipe-fill ${c}" style="width:${total?Math.min(100,n/total*100):0}%"></div></div><span class="pipe-num">${n}</span></div>`).join('');
  const note=document.getElementById('cycleNote');
  const cur=selectedDashPeriod(), now=bangkokToday();
  if(note){
    note.style.display='none';
    if(cur===`${now.y}-${String(now.m).padStart(2,'0')}`){
      const left=new Date(now.y,now.m,0).getDate()-now.d;
      if(left<=7 && donePct<80){ note.textContent=`⚠ ${L('Only','เหลือ')} ${left} ${L('days left but only','วัน แต่เสร็จแล้วเพียง')} ${donePct}% ${L('is done','')}`.trim(); note.style.display='block'; }
    }
  }
}

/* ---- Watch list ---- */
function sparkSvg(vals, avgVals, color){
  const n=vals.length, W=150, H=34; if(n<2) return `<span class="muted-small">—</span>`;
  const all=vals.concat(avgVals.filter(v=>v!=null));
  let lo=Math.min(...all), hi=Math.max(...all); if(hi-lo<6){ const c=(hi+lo)/2; lo=c-3; hi=c+3; }
  const X=i=>2+i*(W-4)/(n-1), Y=v=>H-3-(v-lo)/(hi-lo)*(H-6);
  const line=vals.map((v,i)=>`${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join(' ');
  const avgPts=avgVals.map((v,i)=>v==null?null:`${X(i).toFixed(1)},${Y(v).toFixed(1)}`).filter(Boolean).join(' ');
  return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" aria-hidden="true">${avgPts?`<polyline points="${avgPts}" fill="none" stroke="#9aa0a6" stroke-width="1.2" stroke-dasharray="3 3"/>`:''}<polyline points="${line}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round"/><circle cx="${X(n-1).toFixed(1)}" cy="${Y(vals[n-1]).toFixed(1)}" r="3" fill="${color}"/></svg>`;
}
function renderWatchList(arr){
  const el=document.getElementById('watchList'); if(!el) return;
  const rows=[];
  arr.forEach(e=>{
    const r=supplierRisk(e);
    const overdueCa=caForEval(e).find(isCaOverdue);
    const dec=isEvalComplete(e)&&declining(e), delta=isEvalComplete(e)?scoreDelta(e):0;
    const isPriority=r>=35, isWarning=dec||delta<=-5||!!overdueCa;
    if(!isPriority&&!isWarning) return;
    let reason='';
    if(overdueCa) reason=L('Corrective action overdue','CA เกินกำหนด');
    else if(dec) reason=L('Score declined 3 periods in a row','คะแนนลดลง 3 รอบติดต่อกัน');
    else if(delta<=-5) reason=`${L('Score dropped','คะแนนลดลง')} ${Math.abs(delta).toFixed(1)} ${L('points','คะแนน')}`;
    else if(isEvalComplete(e)&&toNum(e.total_score)<(e.supplier?.target_score||80)) reason=`${L('Below target','ต่ำกว่าเป้าหมาย')} (${scoreNum(e.total_score)})`;
    else reason=L('Open corrective action','มี CA ที่ยังเปิดอยู่');
    rows.push({e,r,reason,delta});
  });
  rows.sort((a,b)=>b.r-a.r);
  const LIMIT=5, shown=rows.slice(0,LIMIT);
  const trendScope=dashboardTrendScope().filter(isEvalComplete);
  const avgByPeriod={}; trendScope.forEach(x=>{ const k=evalPeriodKey(x); (avgByPeriod[k]=avgByPeriod[k]||[]).push(toNum(x.total_score)); });
  const colors={critical:'#a23b3b',high:'#b4650a',watch:'#c99a39',low:'#0e6e66'};
  el.innerHTML = shown.length ? shown.map(x=>{
    const band=riskBand(x.r), color=colors[band]||colors.watch;
    const hist=supplierHistory(x.e).filter(h=>evalPeriodKey(h)<=evalPeriodKey(x.e)).slice(-12);
    const vals=hist.map(h=>toNum(h.total_score));
    const avgs=hist.map(h=>mean(avgByPeriod[evalPeriodKey(h)]||[]));
    const sc=isEvalComplete(x.e)?scoreNum(x.e.total_score):'—';
    const d=x.delta; const dTxt=isEvalComplete(x.e)&&hist.length>1 ? `<small class="${d<0?'dn':d>0?'up':''}">${d<0?'▼':d>0?'▲':'▬'} ${Math.abs(d).toFixed(1)}</small>` : '';
    return `<button type="button" class="watch-row" onclick="editEvaluation('${x.e.id}')">
      <span class="priority-dot" style="background:${color}"></span>
      <span class="watch-main"><b>${escapeHtml(x.e.supplier?.code||'')} · ${escapeHtml(x.e.supplier?.short_name||x.e.supplier?.name||'')}</b><small>${x.reason}</small></span>
      <span class="watch-spark">${sparkSvg(vals,avgs,color)}</span>
      <span class="watch-score">${sc}${dTxt}</span></button>`;
  }).join('') : `<div class="action-empty wide">✓ ${L('No priority or early-warning signal in this view','ไม่พบสัญญาณเร่งด่วนหรือเตือนล่วงหน้าในมุมมองนี้')}</div>`;
  const btn=document.getElementById('btnViewAllRisk');
  if(btn){ btn.style.display=rows.length>LIMIT?'inline-block':'none'; btn.textContent=`${L('View all','ดูทั้งหมด')} (${rows.length})`; }
}

/* ---- 12-month trend ---- */
let trendMetric='total';
function trendValue(e, metric){
  const noShip=e.shipment_status==='no_shipment';
  if(metric==='total') return toNum(e.total_score);
  if(metric==='quality') return toNum(e.quality_score)/50*100;
  if(noShip) return null;
  if(metric==='delivery') return toNum(e.delivery_score)/40*100;
  if(metric==='purchase') return toNum(e.purchase_score)/10*100;
  return null;
}
function renderPerformanceTrend(){
  const c=document.getElementById('performanceTrend'); if(!c) return;
  const scoped=dashboardTrendScope().filter(isEvalComplete);
  const periods=[...new Set(scoped.map(evalPeriodKey))].sort().slice(-12);
  const per=periods.map(p=>{
    const vs=scoped.filter(e=>evalPeriodKey(e)===p).map(e=>({v:trendValue(e,trendMetric),e})).filter(x=>x.v!=null);
    const sorted=vs.map(x=>x.v).sort((a,b)=>a-b);
    return {n:sorted.length, avg:mean(sorted), lo:sorted.length>=5?pct(sorted,.1):null, hi:sorted.length>=5?pct(sorted,.9):null,
            below: trendMetric==='total' ? vs.filter(x=>x.v<(allSuppliers.find(s=>s.id===x.e.supplier?.id)?.target_score||80)).length : 0};
  });
  const cap=document.getElementById('trendCap');
  if(cap) cap.textContent = trendMetric==='total'
    ? L('Line = average · shaded = where most suppliers fall (10–90%) · bars = suppliers below target','เส้น = คะแนนเฉลี่ย · แถบจาง = ช่วงที่ Supplier ส่วนใหญ่อยู่ (10–90%) · แท่ง = จำนวน Supplier ต่ำกว่าเป้า')
    : L('Shown as % of the section maximum · completed evaluations only','แสดงเป็น % ของคะแนนเต็มของส่วนนั้น · เฉพาะใบที่เสร็จแล้ว');
  const ctx=c.getContext('2d'),dpr=devicePixelRatio||1,W=c.clientWidth,H=c.clientHeight;
  if(!W||!H) return;
  c.width=W*dpr; c.height=H*dpr; ctx.scale(dpr,dpr); ctx.clearRect(0,0,W,H);
  if(!periods.length){
    ctx.fillStyle='#5b6470'; ctx.font='12px IBM Plex Sans'; ctx.textAlign='center';
    ctx.fillText(L('No completed evaluations yet','ยังไม่มีใบประเมินที่เสร็จแล้ว'), W/2, H/2); ctx.textAlign='left'; return;
  }
  const vals=per.map(p=>p.avg).filter(v=>v!=null), lows=per.map(p=>p.lo).filter(v=>v!=null);
  const minV=Math.min(...vals,...(lows.length?lows:[100]));
  const yMin=Math.max(0,Math.min(50,Math.floor((minV-5)/10)*10)), yMax=100;
  const padL=34,padR=10,padT=10,padB=22, plotW=W-padL-padR, plotH=H-padT-padB;
  const yFor=v=>padT+plotH-((v-yMin)/(yMax-yMin))*plotH;
  const xFor=i=>padL+(periods.length>1?i*(plotW/(periods.length-1)):plotW/2);
  ctx.strokeStyle='#eceae3'; ctx.fillStyle='#8a9096'; ctx.font='10px IBM Plex Mono'; ctx.textAlign='right';
  for(let v=yMin; v<=yMax; v+=10){ const y=yFor(v); ctx.beginPath(); ctx.moveTo(padL,y); ctx.lineTo(W-padR,y); ctx.stroke(); ctx.fillText(String(v),padL-6,y+3); }
  ctx.textAlign='left';
  if(trendMetric==='total'){
    ctx.save(); ctx.strokeStyle='#a23b3b'; ctx.setLineDash([4,4]); ctx.lineWidth=1;
    ctx.beginPath(); ctx.moveTo(padL,yFor(80)); ctx.lineTo(W-padR,yFor(80)); ctx.stroke(); ctx.restore();
    ctx.fillStyle='#a23b3b'; ctx.font='9px IBM Plex Sans'; ctx.textAlign='right'; ctx.fillText(L('Target 80','เป้า 80'),W-padR,yFor(80)-4); ctx.textAlign='left';
  }
  // shaded 10–90% band between consecutive periods that both have it
  ctx.fillStyle='rgba(14,110,102,.10)';
  for(let i=0;i<per.length-1;i++){
    const a=per[i], b=per[i+1]; if(a.lo==null||b.lo==null) continue;
    ctx.beginPath(); ctx.moveTo(xFor(i),yFor(a.hi)); ctx.lineTo(xFor(i+1),yFor(b.hi)); ctx.lineTo(xFor(i+1),yFor(b.lo)); ctx.lineTo(xFor(i),yFor(a.lo)); ctx.closePath(); ctx.fill();
  }
  // below-target bars (total only), drawn in a thin strip at the bottom of the plot
  if(trendMetric==='total'){
    const maxB=Math.max(1,...per.map(p=>p.below)); ctx.fillStyle='rgba(180,101,10,.55)';
    per.forEach((p,i)=>{ if(!p.below) return; const h=p.below/maxB*Math.min(28,plotH*.22); ctx.fillRect(xFor(i)-6,padT+plotH-h,12,h); });
  }
  ctx.strokeStyle='#0e6e66'; ctx.lineWidth=2.4; ctx.lineJoin='round'; ctx.lineCap='round';
  let seg=false; ctx.beginPath();
  per.forEach((p,i)=>{ if(p.avg==null){ seg=false; return; } if(!seg){ ctx.moveTo(xFor(i),yFor(p.avg)); seg=true; } else ctx.lineTo(xFor(i),yFor(p.avg)); });
  ctx.stroke();
  per.forEach((p,i)=>{ if(p.avg==null) return; ctx.beginPath(); ctx.arc(xFor(i),yFor(p.avg),3.4,0,Math.PI*2); ctx.fillStyle='#fff'; ctx.fill(); ctx.lineWidth=1.6; ctx.strokeStyle='#0e6e66'; ctx.stroke(); });
  ctx.fillStyle='#5b6470'; ctx.font='10px IBM Plex Sans'; ctx.textAlign='center';
  periods.forEach((p,i)=>{ ctx.fillText(monthName(parseInt(p.slice(5),10)),xFor(i),H-6); });
  ctx.textAlign='left';
}

/* ---- Pareto ---- */
let paretoMode='count';
function renderIssuePareto(){
  const el=document.getElementById('issuePareto'); if(!el) return;
  const doneIds=new Set(evaluations.filter(isEvalComplete).map(e=>e.id));
  const periodOf=new Map(evaluations.map(e=>[e.id,evalPeriodKey(e)]));
  const keys=dashPeriodKeys(), cur=selectedDashPeriod(), idx=keys.indexOf(cur);
  const prevKey= idx>0 ? keys[idx-1] : null;
  const tot={}, curP={}, prevP={}, label={}, cat={};
  (dashItemRows||[]).forEach(x=>{
    if(!doneIds.has(x.evaluation_id)) return;
    const c=evaluationCriteria.find(k=>k.id===x.criteria_id);
    // Purchase tiers are credit by order-volume, not a recorded problem
    if(!c||c.category==='purchase'||toNum(x.occurrence)<=0) return;
    const key=c.lineage_id||c.id;
    const w=paretoMode==='points' ? toNum(x.occurrence)*criteriaPoint(c) : toNum(x.occurrence);
    tot[key]=(tot[key]||0)+w;
    const pk=periodOf.get(x.evaluation_id);
    if(pk===cur) curP[key]=(curP[key]||0)+w;
    if(prevKey && pk===prevKey) prevP[key]=(prevP[key]||0)+w;
    if(!label[key]||c.is_active) label[key]=officialDescription(c);
    cat[key]=isEnvironmentCriteria(c)?L('Environment','สิ่งแวดล้อม'):(c.category==='delivery'?'Delivery':'Quality');
  });
  const rows=Object.entries(tot).sort((a,b)=>b[1]-a[1]).slice(0,7), max=rows[0]?.[1]||1;
  if(!rows.length){ el.innerHTML=`<div class="empty-note">${L('No recorded issues yet','ยังไม่มีสาเหตุปัญหาที่บันทึกไว้')}</div>`; return; }
  const fmt=n=>paretoMode==='points'?(Math.round(n*10)/10):n;
  el.innerHTML=rows.map(([key,n])=>{
    const l=escapeHtml(label[key]||key);
    let arrow='';
    if(prevKey){ const d=(curP[key]||0)-(prevP[key]||0); arrow=d>0?`<span class="pareto-num dn">▲ ${fmt(d)}</span>`:d<0?`<span class="pareto-num up">▼ ${fmt(-d)}</span>`:`<span class="pareto-num">▬</span>`; }
    return `<div class="pareto-row"><span class="pareto-label" title="${l}">${l} <small>· ${cat[key]}</small></span><div class="pareto-track"><div class="pareto-fill" style="width:${n/max*100}%"></div></div><span class="pareto-num">${fmt(n)}</span>${arrow}</div>`;
  }).join('');
}

async function loadDashboardItemRows(){
  // Was scoped to only the single currently-selected period — with itemized
  // scoring still new, that period alone often has little or no data,
  // leaving the Pareto permanently empty. Widened to the same rolling
  // 12-month/category scope the trend chart uses, so there's an honest
  // chance of real data to show.
  const scoped = dashboardTrendScope();
  const periods = [...new Set(scoped.map(evalPeriodKey))].sort().slice(-12);
  const ids = scoped.filter(e => periods.includes(evalPeriodKey(e))).map(e => e.id);
  if (!ids.length) { dashItemRows = []; return; }
  // A full 12-month/all-supplier scope can be 500-700+ evaluation ids.
  // supabase-js sends .in() as a GET querystring ("evaluation_id=in.(uuid,uuid,...)"),
  // and a querystring that long gets silently rejected by intermediate infra
  // before it ever reaches Postgres — with only `if(!error)` guarding the
  // assignment below, that failure was invisible: dashItemRows just stayed
  // [] forever, no console output, no visible error. Batching keeps every
  // request's URL well under any length limit, and errors are now logged
  // instead of swallowed.
  const BATCH = 150;
  const batches = [];
  for (let i = 0; i < ids.length; i += BATCH) batches.push(ids.slice(i, i + BATCH));
  try {
    const results = await Promise.all(batches.map(b =>
      sb.from('evaluation_items').select('evaluation_id,criteria_id,occurrence').in('evaluation_id', b)
    ));
    const failed = results.find(r => r.error);
    if (failed) { console.error('loadDashboardItemRows batch failed:', failed.error); dashItemRows = []; return; }
    dashItemRows = results.flatMap(r => r.data || []);
  } catch (err) {
    console.error('loadDashboardItemRows failed:', err);
    dashItemRows = [];
  }
}
async function refreshDashboard(){await loadDashboardItemRows();renderDashboardCommandCenter();}


/* ============================================================
   Official Excel-based Supplier Evaluation Worksheet v0.9.0
   ============================================================ */
function criteriaPoint(c){ return Math.abs(toNum(c.deduction_points)); }
function isEnvironmentCriteria(c){ return /^A2/i.test(c.item_no||'') || /environment|chemical|wastewater|sewage|ICP/i.test(c.description||''); }

// Splits quality_score into Quality (A1, /40) and Environment (A2, /10)
// for display — only possible for 'itemized' evaluations, since that's
// the only mode where per-criteria occurrences are actually recorded.
// 'manual' evaluations only ever had one combined number, so there's
// nothing to split — returns env: null for those, caller shows '-'.
function qualityEnvSplit(e){
  if (e.scoring_mode !== 'itemized') return { q: e.quality_score, env: null };
  const items = allEvaluationItems.filter(x => x.evaluation_id === e.id);
  let a1Delta = 0, a2Delta = 0;
  items.forEach(x => {
    const c = evaluationCriteria.find(k => k.id === x.criteria_id);
    if (!c || c.category !== 'quality') return;
    const amt = toNum(x.occurrence) * toNum(c.deduction_points);
    if (isEnvironmentCriteria(c)) a2Delta += amt; else a1Delta += amt;
  });
  return {
    q: Math.max(0, Math.min(40, 40 + a1Delta)),
    env: Math.max(0, Math.min(10, 10 + a2Delta)),
  };
}
function worksheetRoleAccess(category){
  const ev = evaluations.find(e => e.id === currentEditingEvalId);
  if (!ev) return false;
  const isQuality = (category === 'quality' || category === 'environment');
  const hasEditPerm = isQuality ? hasPerm('eval_edit_quality') : hasPerm('eval_edit_delivery');
  if (!hasEditPerm) return false;

  // Fully locked from Manager Approve onward — no exceptions for
  // anyone. The only actions left past that point are Mark Sent and
  // Delete, both handled elsewhere with their own gating.
  if (evaluationLocked(ev)) return false;

  // Once Supervisor has approved, QA/CS/MP lose edit access — editing
  // now would silently invalidate an approval that already happened
  // without triggering a re-review. Whoever holds Supervisor-tier
  // approval permission is the exception: they can keep fixing
  // Delivery/Purchase (their own team's data — not Quality, that's
  // not theirs to touch) right up until Manager Approve locks it for
  // real, so a small fix doesn't require a full Reject round-trip.
  if (ev.status === 'sup_approved') {
    if (isQuality) return false;
    return hasPerm('eval_sup_approve');
  }

  return true; // draft (and anything earlier): normal permission-based access
}
function evaluationLocked(ev){
  return !!ev && ['mgr_approved','sent_to_supplier','acknowledged','follow_up_required'].includes(ev.status);
}
// A department that can Supervisor- or Manager-approve can't edit either
// worksheet section, but still needs to actually SEE both to make an
// approve/reject call — so it's excluded from the "can't edit it →
// collapse it by default" rule below (see setSectionCollapsed).
function isApproverRole(){ return hasPerm('eval_sup_approve') || hasPerm('eval_mgr_approve'); }

// Collapses/expands one worksheet card (Quality, or Delivery & Purchase).
// Collapsed state hides the full checklist and shows only the flagged
// items (see renderFlaggedSummary) so a role that can't edit this section
// doesn't have to scroll past a checklist that's entirely zeroed out.
function setSectionCollapsed(sectionEl, collapsed){
  if (!sectionEl) return;
  sectionEl.classList.toggle('collapsed', collapsed);
  const toggle = sectionEl.querySelector('.section-toggle');
  if (toggle) toggle.setAttribute('aria-expanded', String(!collapsed));
}
// Renders the compact "only what's flagged" view shown when a section is
// collapsed: any checklist row with occurrence > 0 (a real deduction),
// plus — for the delivery/purchase card — the currently selected purchase
// tier, since that always affects the score even though it isn't a
// "deduction". Shows a calm empty-state when nothing is flagged.
function renderFlaggedSummary(containerId, rows, category){
  const container = document.getElementById(containerId);
  if (!container) return;
  const current = {}; evaluationItemsCache.forEach(x => current[x.criteria_id] = toNum(x.occurrence));
  const flagged = rows.filter(c => (current[c.id] || 0) > 0);
  if (!flagged.length){
    const ev = evaluations.find(e => e.id === currentEditingEvalId);
    const submitted = category === 'quality' ? ev?.quality_submitted_at : ev?.delivery_submitted_at;
    const msg = submitted
      ? L('No deductions in this section','ไม่มีรายการที่ถูกหักคะแนนในส่วนนี้')
      : (category === 'quality'
          ? L('Waiting on the Quality department to submit','รอผลประเมินจากแผนก Quality')
          : L('Waiting on the CS/MP department to submit','รอผลประเมินจากแผนก CSMP'));
    container.innerHTML = `<div class="flagged-summary-empty">${msg}</div>`;
    return;
  }
  container.innerHTML = flagged.map(c => {
    const val = current[c.id] || 0, pts = criteriaPoint(c), applied = pts * val;
    return `<div class="flagged-summary-row"><span>${c.item_no ? c.item_no + ' — ' : ''}${officialDescription(c)} (×${val})</span><b>-${applied} ${L('pts','คะแนน')}</b></div>`;
  }).join('');
}
function renderPurchaseFlaggedSummary(containerId, rows){
  const container = document.getElementById(containerId);
  if (!container) return;
  const selectedId = document.querySelector('input[name="purchaseTier"]:checked')?.value;
  const tier = rows.find(c => c.id === selectedId);
  if (!tier) return;
  const pts = Math.max(0, toNum(tier.deduction_points));
  container.innerHTML += `<div class="flagged-summary-row"><span>${tier.item_no ? tier.item_no + ' — ' : ''}${officialDescription(tier)}</span><b>+${pts} ${L('pts','คะแนน')}</b></div>`;
}
function officialDescription(c){
  // Criteria descriptions come from the database (seeded from FM0704-3,
  // which is English-only — description_th is a separate translation
  // added on top, see 14_criteria_thai_translation.sql). Falls back to
  // English if a Thai translation hasn't been filled in for a row yet
  // (e.g. a criteria added later via Master Control).
  if (lang === 'th' && c.description_th) return c.description_th;
  return c.description || c.item_no || '';
}
function renderOccurrenceRows(target, rows, category){
  const current={}; evaluationItemsCache.forEach(x=>current[x.criteria_id]=toNum(x.occurrence));
  const editable=worksheetRoleAccess(category);
  target.innerHTML=`<div class="criteria-list">${rows.map(c=>{
    const val=current[c.id]||0, pts=criteriaPoint(c), applied=pts*val;
    return `<div class="criteria-row ${editable?'':'locked'} ${applied?'has-deduction':''}" data-category="${category}">
      <span class="criteria-code">${c.item_no||''}</span>
      <div class="criteria-desc"><b>${officialDescription(c)}</b><span>${L(`Deduction ${pts} points / occurrence`,`หัก ${pts} คะแนน / ครั้ง`)}</span></div>
      <div class="occurrence-control"><button type="button" onclick="changeOccurrence('${c.id}',-1)">−</button><input class="ws-occurrence" data-criteria-id="${c.id}" data-category="${category}" data-points="${pts}" type="number" min="0" step="1" value="${val}"><button type="button" onclick="changeOccurrence('${c.id}',1)">+</button></div>
      <div class="deduction-live ${applied?'active':''}" data-deduction-for="${c.id}">${applied?`-${applied}`:'0'} ${L('pts','คะแนน')}</div>
    </div>`;
  }).join('')}</div>`;
}
function renderPurchaseTiers(rows){
  const current={}; evaluationItemsCache.forEach(x=>current[x.criteria_id]=toNum(x.occurrence));
  let selected=rows.find(c=>current[c.id]>0)?.id||'';
  const editable=worksheetRoleAccess('purchase') && document.getElementById('f_shipment').value!=='no_shipment';
  document.getElementById('purchaseTierRows').innerHTML=rows.map(c=>{
    const pts=Math.max(0,toNum(c.deduction_points));
    return `<label class="tier-card ${editable?'':'locked'}"><input type="radio" name="purchaseTier" value="${c.id}" ${selected===c.id?'checked':''} ${editable?'':'disabled'}><div><b>${c.item_no||''} · ${officialDescription(c)}</b><span>${L('Select one applicable purchase tier','เลือกช่วงยอดซื้อที่ตรงกับเดือนนี้เพียงรายการเดียว')}</span></div><strong class="tier-points">+${pts}</strong></label>`;
  }).join('');
  document.querySelectorAll('input[name="purchaseTier"]').forEach(x=>x.addEventListener('change',updateWorksheetPreview));
}
function changeOccurrence(id,delta){
  const el=document.querySelector(`.ws-occurrence[data-criteria-id="${id}"]`); if(!el||el.disabled)return;
  el.value=Math.max(0,toNum(el.value)+delta); updateWorksheetPreview();
}
function worksheetScores(){
  let a1Ded=0,a2Ded=0,dDed=0;
  document.querySelectorAll('.ws-occurrence').forEach(x=>{
    const amount=toNum(x.value)*toNum(x.dataset.points);
    if(x.dataset.category==='quality') a1Ded+=amount;
    if(x.dataset.category==='environment') a2Ded+=amount;
    if(x.dataset.category==='delivery') dDed+=amount;
  });
  const q=Math.max(0,40-a1Ded)+Math.max(0,10-a2Ded);
  const noShip=document.getElementById('f_shipment').value==='no_shipment';
  const d=noShip?0:Math.max(0,40-dDed);
  const checked=document.querySelector('input[name="purchaseTier"]:checked');
  const pc=checked?evaluationCriteria.find(c=>c.id===checked.value):null;
  const purchase=noShip?0:Math.max(0,toNum(pc?.deduction_points));
  const weight=100;
  let raw;
  if (noShip) {
    // Mirrors compute_evaluation_score() in 31_no_shipment_carry_forward_scoring.sql:
    // Quality scaled 0-50 -> 0-90 (a mistake weighs 1.8x heavier with
    // nothing else to grade on), topped up with this supplier's last
    // known Purchase score from a real-shipment month (0 if it has
    // never had one).
    const supplierId = document.getElementById('f_supplier')?.value;
    const supplierRow = allSuppliers.find(s => s.id === supplierId);
    const carriedPurchase = toNum(supplierRow?.last_purchase_score) || 0;
    raw = Math.round(q*1.8*100)/100 + carriedPurchase;
  } else {
    raw = q+d+purchase;
  }
  const total=weight?Math.round(raw/weight*10000)/100:0;
  return {a1:Math.max(0,40-a1Ded),a2:Math.max(0,10-a2Ded),q,d,purchase,weight,raw,total,grade:gradeOf(total)};
}
function updateWorksheetPreview(){
  if(!document.getElementById('worksheetBody'))return;
  document.querySelectorAll('.ws-occurrence').forEach(x=>{const n=toNum(x.value)*toNum(x.dataset.points),el=document.querySelector(`[data-deduction-for="${x.dataset.criteriaId}"]`);if(el){el.textContent=`${n?'-'+n:'0'} ${L('pts','คะแนน')}`;el.classList.toggle('active',n>0);}x.closest('.criteria-row')?.classList.toggle('has-deduction',n>0);});
  const x=worksheetScores(), noShip=document.getElementById('f_shipment').value==='no_shipment';
  const set=(id,v)=>{const e=document.getElementById(id);if(e)e.textContent=v};
  set('wsA1',`${x.a1} / 40`);set('wsA2',`${x.a2} / 10`);set('wsQuality',x.q);set('wsDelivery',noShip?'N/A':`${x.d} / 40`);set('wsPurchase',noShip?'N/A':`${x.purchase} / 10`);set('wsDeliveryPurchase',noShip?'N/A':(x.d+x.purchase));set('wsTotal',`${x.total}%`);set('wsGrade',`${L('Grade','เกรด')} ${x.grade}`);set('sumQuality',`${x.q} / 50`);set('sumDelivery',noShip?'N/A':`${x.d} / 40`);set('sumPurchase',noShip?'N/A':`${x.purchase} / 10`);
  const badge=document.getElementById('wsGrade');badge.className=`badge ${x.grade}`;
  const occurrences=[...document.querySelectorAll('.ws-occurrence')]; const purchaseDone=noShip||!!document.querySelector('input[name="purchaseTier"]:checked');
  const complete=Math.round(((occurrences.length?1:0)+(purchaseDone?1:0)+(currentEditingEvalId?1:0))/3*100);set('wsCompleteness',`${complete}%`);document.getElementById('wsCompletenessBar').style.width=`${complete}%`;
  document.getElementById('f_quality').value=x.q;document.getElementById('f_delivery').value=x.d;document.getElementById('f_purchase').value=x.purchase;document.getElementById('f_qcomment').value=document.getElementById('ws_qcomment')?.value||'';document.getElementById('f_dcomment').value=document.getElementById('ws_dcomment')?.value||'';
}
async function openOrCreateWorksheet(){
  const supplierId=document.getElementById('f_supplier').value, year=toNum(document.getElementById('f_year').value),month=toNum(document.getElementById('f_month').value);
  if(!supplierId)return;
  let ev=evaluations.find(e=>e.supplier?.id===supplierId&&e.year===year&&e.month===month);
  if(!ev){
    const shipment=document.getElementById('f_shipment').value,reason=document.getElementById('f_noship_reason').value.trim();
    if(shipment==='no_shipment'&&!reason){alert(t('noShipReasonRequired','Please enter a reason for No Shipment'));return;}
    const {data,error}=await sb.from('evaluations').upsert({supplier_id:supplierId,year,month,quality_score:50,delivery_score:40,purchase_score:0,status:'draft',shipment_status:shipment,no_shipment_reason:shipment==='no_shipment'?reason:null,scoring_mode:'itemized'},{onConflict:'supplier_id,year,month'}).select().single();
    if(error){alert('Open worksheet failed: '+error.message);return;} currentEditingEvalId=data.id; await loadEvaluations(); ev=evaluations.find(e=>e.id===data.id);
  } else currentEditingEvalId=ev.id;
  await loadEvaluationItemsFor(currentEditingEvalId); await loadEvaluationAttachments(currentEditingEvalId); renderOfficialWorksheet();
}
function renderOfficialWorksheet(){
  const ev=evaluations.find(e=>e.id===currentEditingEvalId);if(!ev)return;
  document.getElementById('worksheetEmpty').style.display='none';document.getElementById('worksheetBody').style.display='block';
  const picker=document.getElementById('evalPickerSection');if(picker)picker.style.display='none';
  const headerCard=document.getElementById('evalHeaderCard');if(headerCard)headerCard.style.display='none';
  document.getElementById('f_supplier').value=ev.supplier?.id||'';document.getElementById('f_year').value=ev.year;document.getElementById('f_month').value=ev.month;document.getElementById('f_shipment').value=ev.shipment_status||'normal';document.getElementById('f_noship_reason').value=ev.no_shipment_reason||'';
  document.getElementById('ws_qcomment').value=ev.quality_comment||'';document.getElementById('ws_dcomment').value=ev.delivery_comment||'';
  // Which supplier/period/status this worksheet is for is otherwise only
  // visible in the small dropdowns above — easy to lose track of while
  // scrolling a long form. Surfaces it at the top of the Action Bar
  // instead, right above the live score (re-set here rather than
  // setPageHeadTitle so it also stays correct across language switches).
  const asideTitle = document.getElementById('asideEvalTitle');
  if (asideTitle) asideTitle.innerHTML = `<div>${ymLabel(ev.year, ev.month)} <span class="pht-status badge status">${statusLabel(ev.status)}</span></div><div class="pht-sub">${ev.supplier?.name || ev.supplier?.short_name || ''}</div>`;
  setPageHeadTitle();
  const active=evaluationCriteria.filter(c=>c.is_active!==false), quality=active.filter(c=>c.category==='quality'), env=quality.filter(isEnvironmentCriteria),a1=quality.filter(c=>!isEnvironmentCriteria(c)),delivery=active.filter(c=>c.category==='delivery'),purchase=active.filter(c=>c.category==='purchase');
  renderOccurrenceRows(document.getElementById('qualityProblemRows'),a1,'quality');renderOccurrenceRows(document.getElementById('environmentRows'),env,'environment');renderOccurrenceRows(document.getElementById('deliveryRows'),delivery,'delivery');renderPurchaseTiers(purchase);
  const noShip=ev.shipment_status==='no_shipment';document.getElementById('deliveryNoShipment').style.display=noShip?'block':'none';document.getElementById('purchaseNoShipment').style.display=noShip?'block':'none';document.getElementById('deliveryRows').style.display=noShip?'none':'block';document.getElementById('purchaseTierRows').style.display=noShip?'none':'grid';
  document.querySelectorAll('.ws-occurrence').forEach(x=>x.addEventListener('input',updateWorksheetPreview));document.getElementById('ws_qcomment').oninput=updateWorksheetPreview;document.getElementById('ws_dcomment').oninput=updateWorksheetPreview;

  // Default collapse state per section: a role that can't edit a section
  // AND isn't approving (Supervisor/Manager still need to see everything
  // to make that call) gets it collapsed, showing only flagged items.
  const approverRole = isApproverRole();
  const qualitySection = document.getElementById('qualityWorksheet');
  const deliverySection = document.getElementById('deliveryPurchaseWorksheet');
  const qualityCollapsed = !worksheetRoleAccess('quality') && !approverRole;
  const deliveryCollapsed = !worksheetRoleAccess('delivery') && !approverRole;
  setSectionCollapsed(qualitySection, qualityCollapsed);
  setSectionCollapsed(deliverySection, deliveryCollapsed);
  renderFlaggedSummary('qualityFlaggedSummary', a1.concat(env), 'quality');
  if (noShip) {
    document.getElementById('deliveryFlaggedSummary').innerHTML = `<div class="flagged-summary-empty">${L('No shipment this month — Delivery & Purchase are N/A','เดือนนี้ไม่มีการส่งมอบ — Delivery และ Purchase เป็น N/A')}</div>`;
  } else {
    renderFlaggedSummary('deliveryFlaggedSummary', delivery, 'delivery');
    renderPurchaseFlaggedSummary('deliveryFlaggedSummary', purchase);
  }

  // Data-safety: this evaluation still has its ORIGINAL manually-entered
  // scores (quality_score/delivery_score/purchase_score typed by hand,
  // never touched by the checklist). The checklist below currently shows
  // all-zero occurrences because no evaluation_items exist for it yet —
  // that is NOT the real history. Saving anything on this screen will ask
  // for explicit confirmation before it's allowed to overwrite those real
  // numbers (see saveOfficialWorksheet).
  const legacyBanner = document.getElementById('manualLegacyWarning');
  if (ev.scoring_mode === 'manual') {
    legacyBanner.style.display = 'block';
    legacyBanner.innerHTML = `<b>${L('This evaluation was manually scored','ผลประเมินนี้กรอกคะแนนแบบ Manual')}</b><br>${L(
      `Original scores — Quality ${ev.quality_score}/50, Delivery ${ev.shipment_status==='no_shipment'?'N/A':ev.delivery_score+'/40'}, Purchase ${ev.shipment_status==='no_shipment'?'N/A':ev.purchase_score+'/10'}. The checklist below starts empty and does NOT reflect these numbers. Saving on this screen will ask you to confirm before switching this evaluation to itemized scoring and replacing the numbers above.`,
      `คะแนนเดิม — Quality ${ev.quality_score}/50, Delivery ${ev.shipment_status==='no_shipment'?'N/A':ev.delivery_score+'/40'}, Purchase ${ev.shipment_status==='no_shipment'?'N/A':ev.purchase_score+'/10'} รายการ checklist ด้านล่างเริ่มจากว่างเปล่า ยังไม่ตรงกับตัวเลขเดิม การบันทึกจากหน้านี้จะมีการถามยืนยันก่อนเปลี่ยนเป็นระบบ checklist และแทนที่ตัวเลขข้างต้น`
    )}`;
  } else {
    legacyBanner.style.display = 'none';
  }

  // Action bar: only render the button(s) that are actually actionable
  // for this role, at this workflow stage, right now — instead of always
  // showing all five and disabling most of them (which is what overflowed
  // the sidebar). At most 2 buttons show at once (an approve + its
  // matching reject); when none apply, a one-line status hint explains
  // whose turn it is instead of a wall of greyed-out buttons.
  const canSupApprove = hasPerm('eval_sup_approve');
  const canMgrApprove = hasPerm('eval_mgr_approve');
  const bothSubmitted = !!(ev.quality_submitted_at && ev.delivery_submitted_at);
  const btnSave = document.getElementById('btnSave');
  const btnSupApprove = document.getElementById('btnSupApprove');
  const btnMgrApprove = document.getElementById('btnMgrApprove');
  const btnReject = document.getElementById('btnReject');
  const btnMarkSent = document.getElementById('btnMarkSent');
  const evalActionHint = document.getElementById('evalActionHint');
  const readyForSupReview = bothSubmitted && !['sup_approved','mgr_approved','sent_to_supplier','acknowledged'].includes(ev.status);
  const readyForMgrReview = ev.status === 'sup_approved';
  const readyForMarkSent = ev.status === 'mgr_approved';

  const showSave = btnSave.dataset.mode !== 'none';
  const showSupStage = canSupApprove && readyForSupReview;
  const showMgrStage = canMgrApprove && readyForMgrReview;
  // Reject is scoped to whoever's turn it actually is — a Supervisor
  // can only reject while it's still awaiting Supervisor review, a
  // Manager only once it's awaiting Manager review (matches the
  // database's own per-stage check in migration 34).
  const showReject = showSupStage || showMgrStage;
  const showMarkSent = hasPerm('eval_mark_sent') && readyForMarkSent;

  btnSave.style.display = showSave ? 'block' : 'none';
  btnSupApprove.style.display = showSupStage ? 'block' : 'none';
  btnMgrApprove.style.display = showMgrStage ? 'block' : 'none';
  btnReject.style.display = showReject ? 'block' : 'none';
  btnMarkSent.style.display = showMarkSent ? 'block' : 'none';

  const anyActionShown = showSave || showSupStage || showMgrStage || showReject || showMarkSent;
  if (!anyActionShown) {
    let waitingOn = L('Nothing to do here right now','ยังไม่มีขั้นตอนที่ต้องทำตอนนี้');
    if (!bothSubmitted) waitingOn = L('Waiting on QA / CS-MP to submit','รอ QA / CS-MP ส่งผล');
    else if (readyForSupReview) waitingOn = L('Waiting on Supervisor Approve','รอ Supervisor Approve');
    else if (readyForMgrReview) waitingOn = L('Waiting on Manager Approve','รอ Manager Approve');
    else if (readyForMarkSent) waitingOn = L('Waiting to be marked sent to supplier','รอบันทึกว่าส่งผลแล้ว');
    evalActionHint.textContent = waitingOn;
    evalActionHint.style.display = 'block';
  } else {
    evalActionHint.style.display = 'none';
  }

  renderEvalAttachList();renderSubmitStatusNote();updateWorksheetPreview();
}

async function supervisorApproveEvaluation(){
  if (!currentEditingEvalId) return;
  const { error } = await sb.from('evaluations').update({ status: 'sup_approved' }).eq('id', currentEditingEvalId);
  if (error) { alert(L('Supervisor Approve failed: ','Supervisor Approve ไม่สำเร็จ: ') + error.message); console.error(error); return; }
  await loadEvaluations();
  alert(L('Supervisor approval recorded','บันทึก Supervisor Approve แล้ว'));
  resetForm();
  showTab('list');
}

async function managerApproveEvaluation(){
  if (!currentEditingEvalId) return;
  const { error } = await sb.from('evaluations').update({ status: 'mgr_approved' }).eq('id', currentEditingEvalId);
  if (error) { alert(L('Manager Approve failed: ','Manager Approve ไม่สำเร็จ: ') + error.message); console.error(error); return; }
  await loadEvaluations(); await loadCorrectiveActions(); renderAll(); renderOfficialWorksheet();
  alert(L('Manager approval recorded','บันทึก Manager Approve แล้ว'));
}

// Reject opens a small modal instead of a single prompt() — it needs
// two pieces of input now (which section(s) actually need redoing,
// and why), not just a reason string. See confirmRejectFromModal for
// the actual update; the database enforces the same per-stage
// permission and per-section scoping (see migration 34).
function rejectEvaluation(){
  const ev = evaluations.find(e => e.id === currentEditingEvalId);
  if (!ev) return;
  const mgrStage = ev.status === 'sup_approved';
  if (mgrStage && !hasPerm('eval_mgr_approve')) {
    alert(L('Only a Manager can reject at this stage','ขั้นนี้ Manager เท่านั้นที่ Reject ได้')); return;
  }
  if (!mgrStage && !hasPerm('eval_sup_approve')) {
    alert(L('Only a Supervisor can reject at this stage','ขั้นนี้ Supervisor เท่านั้นที่ Reject ได้')); return;
  }
  const qOk = !!ev.quality_submitted_at, dOk = !!ev.delivery_submitted_at;
  const cbQ = document.getElementById('reject_q'), cbD = document.getElementById('reject_d');
  cbQ.checked = qOk; cbQ.disabled = !qOk;
  cbD.checked = dOk; cbD.disabled = !dOk;
  document.getElementById('reject_reason').value = '';
  document.getElementById('rejectModal').style.display = 'flex';
}
async function confirmRejectFromModal(){
  const ev = evaluations.find(e => e.id === currentEditingEvalId);
  if (!ev) return;
  const rejectQ = document.getElementById('reject_q').checked && !!ev.quality_submitted_at;
  const rejectD = document.getElementById('reject_d').checked && !!ev.delivery_submitted_at;
  const reason = document.getElementById('reject_reason').value.trim();
  if (!rejectQ && !rejectD) { alert(L('Select at least one section to reject','เลือกอย่างน้อยหนึ่งฝั่งที่ต้องการ Reject')); return; }
  if (!reason) { alert(L('A reason is required.','กรุณากรอกเหตุผล')); return; }
  const payload = { rejection_reason: reason };
  if (rejectQ) payload.quality_submitted_at = null;
  if (rejectD) payload.delivery_submitted_at = null;
  if (ev.status === 'sup_approved') payload.status = 'draft';
  const { error } = await sb.from('evaluations').update(payload).eq('id', currentEditingEvalId);
  if (error) { alert(L('Reject failed: ','Reject ไม่สำเร็จ: ') + error.message); console.error(error); return; }
  document.getElementById('rejectModal').style.display = 'none';
  await loadEvaluations();
  alert(L('Evaluation rejected — the selected section(s) must be resubmitted','Reject แล้ว — ฝั่งที่เลือกต้อง submit ใหม่'));
  resetForm();
  showTab('list');
}
function closeRejectModal(){
  document.getElementById('rejectModal').style.display = 'none';
}

async function markSentToSupplier(){
  if (!currentEditingEvalId) return;
  if (!hasPerm('eval_mark_sent')) { alert(L("You don't have permission to mark this as sent","คุณไม่มีสิทธิ์ทำรายการนี้")); return; }
  const ev = evaluations.find(e => e.id === currentEditingEvalId);
  // Grade A/B needs no corrective action, so there's nothing left to
  // wait on — but it still genuinely passes through sent_to_supplier
  // first (two real, separate transitions, each checked by the DB
  // trigger) rather than jumping straight to acknowledged in one
  // update. That earlier one-step version let a grade A/B evaluation
  // reach "closed" without the DB ever recording that it was sent —
  // fixed in 28_mark_sent_and_ca_close_sync.sql, which now also
  // rejects any attempt to skip straight to acknowledged.
  const autoClose = ev && ['A','B'].includes(ev.grade);

  const { error: sendErr } = await sb.from('evaluations').update({ status: 'sent_to_supplier', sent_at: new Date().toISOString() }).eq('id', currentEditingEvalId);
  if (sendErr) { alert('Failed: ' + sendErr.message); return; }

  if (autoClose) {
    const { error: closeErr } = await sb.from('evaluations').update({ status: 'acknowledged', acknowledged_at: new Date().toISOString() }).eq('id', currentEditingEvalId);
    if (closeErr) { alert('Failed: ' + closeErr.message); return; }
  }

  await loadEvaluations(); renderAll(); renderOfficialWorksheet();
  alert(autoClose
    ? L('Marked as sent — grade passed, case closed automatically','บันทึกว่าส่งผลแล้ว — เกรดผ่านเกณฑ์ ปิดเคสอัตโนมัติ')
    : L('Marked as sent to supplier — waiting on the Corrective Action to close this case','บันทึกว่าส่งผลให้ Supplier แล้ว — รอปิด Corrective Action เพื่อปิดเคส'));
}

async function saveOfficialWorksheet(scope='all', silent){
  if(!currentEditingEvalId){await openOrCreateWorksheet();if(!currentEditingEvalId)return false;}
  const ev=evaluations.find(e=>e.id===currentEditingEvalId); if(!ev)return false;

  // Data-safety gate: never silently convert a manually-scored evaluation
  // to itemized scoring. See renderOfficialWorksheet's legacy banner.
  if (ev.scoring_mode === 'manual') {
    const msg = L(
      `This evaluation currently has manually-entered scores (Quality ${ev.quality_score}/50, Delivery ${ev.delivery_score}/40, Purchase ${ev.purchase_score}/10). Saving now will switch it to itemized/checklist scoring and REPLACE those numbers based on what's ticked in the checklist. This cannot be undone. Continue?`,
      `ผลประเมินนี้ตอนนี้เป็นคะแนนแบบกรอกเอง (Quality ${ev.quality_score}/50, Delivery ${ev.delivery_score}/40, Purchase ${ev.purchase_score}/10) การบันทึกตอนนี้จะเปลี่ยนเป็นคะแนนแบบ checklist และแทนที่ตัวเลขเดิมตามที่ติ๊กไว้ ย้อนกลับไม่ได้ ดำเนินการต่อหรือไม่?`
    );
    if (!confirm(msg)) return false;
  }

  const allowedCats=scope==='quality'?['quality','environment']:scope==='delivery'?['delivery','purchase']:['quality','environment','delivery','purchase'];
  let rows=[];document.querySelectorAll('.ws-occurrence').forEach(x=>{if(allowedCats.includes(x.dataset.category))rows.push({evaluation_id:currentEditingEvalId,criteria_id:x.dataset.criteriaId,occurrence:toNum(x.value)});});
  if(allowedCats.includes('purchase')){const selected=document.querySelector('input[name="purchaseTier"]:checked');evaluationCriteria.filter(c=>c.category==='purchase').forEach(c=>rows.push({evaluation_id:currentEditingEvalId,criteria_id:c.id,occurrence:selected?.value===c.id?1:0}));}
  if(rows.length){const {error}=await sb.from('evaluation_items').upsert(rows,{onConflict:'evaluation_id,criteria_id'});if(error){alert('Save checklist failed: '+error.message);return false;}}
  const shipment=document.getElementById('f_shipment').value,reason=document.getElementById('f_noship_reason').value.trim();if(shipment==='no_shipment'&&!reason){alert(t('noShipReasonRequired','Please enter a reason for No Shipment'));return false;}
  const comments={};if(scope==='quality'||scope==='all')comments.quality_comment=document.getElementById('ws_qcomment').value.trim()||null;if(scope==='delivery'||scope==='all')comments.delivery_comment=document.getElementById('ws_dcomment').value.trim()||null;
  const {error}=await sb.from('evaluations').update({...comments,shipment_status:shipment,no_shipment_reason:shipment==='no_shipment'?reason:null,scoring_mode:'itemized'}).eq('id',currentEditingEvalId);if(error){alert('Save failed: '+error.message);return false;}
  const rpcScope = scope==='quality' ? 'quality' : scope==='delivery' ? 'delivery' : null;
  const { error: rpcError } = await sb.rpc('recompute_evaluation_scores',{p_evaluation_id:currentEditingEvalId,p_scope:rpcScope});
  if (rpcError) { alert('Score recalculation failed: ' + rpcError.message); return false; }
  await loadEvaluations();await loadEvaluationItemsFor(currentEditingEvalId);renderAll();renderOfficialWorksheet();if(!silent)alert(L('Draft saved and score recalculated','บันทึกร่างและคำนวณคะแนนใหม่แล้ว'));
  return true;
}
// resetForm / editEvaluation / handleMainSubmitClick for the Official Worksheet.
function editEvaluation(id){const e=evaluations.find(x=>x.id===id);if(!e)return;currentEditingEvalId=id;showTab('input');const picker=document.getElementById('evalPickerSection');if(picker)picker.style.display='none';attachHistoryId(id);loadEvaluationItemsFor(id).then(()=>loadEvaluationAttachments(id)).then(renderOfficialWorksheet);}
// Drives the single consolidated submit button — mode was already set
// by applyRoleGating() based on Permission Matrix rules. Now opens a
// preview modal first (see buildSubmitPreviewHtml) instead of saving
// immediately — actualSubmit() below does the real work once the
// person confirms there.
// IMPORTANT: saveOfficialWorksheet() returns true/false — if the
// score save genuinely fails (its own alert already explains why), we
// stop right there rather than showing a false "saved and submitted".
function handleMainSubmitClick(){
  const mode = document.getElementById('btnSave')?.dataset.mode;
  if (mode === 'none') return;
  pendingSubmitMode = mode;
  const { html, purchaseOk } = buildSubmitPreviewHtml(mode);
  document.getElementById('submitPreviewBody').innerHTML = html;
  document.getElementById('btnSubmitPreviewConfirm').disabled = !purchaseOk;
  document.getElementById('submitPreviewModal').style.display = 'flex';
}
let pendingSubmitMode = null;
// Reads the checklist straight from the DOM (not evaluationItemsCache)
// so the preview reflects whatever is currently typed/ticked, even if
// it hasn't been saved yet.
function currentDeductionSummary(categories){
  const rows = [];
  document.querySelectorAll('.ws-occurrence').forEach(x => {
    if (!categories.includes(x.dataset.category)) return;
    const val = toNum(x.value);
    if (val <= 0) return;
    const c = evaluationCriteria.find(cc => cc.id === x.dataset.criteriaId);
    if (!c) return;
    const pts = toNum(x.dataset.points) * val;
    rows.push(`<div class="preview-row"><span>${c.item_no ? c.item_no+' — ' : ''}${officialDescription(c)} (×${val})</span><b>-${pts} ${L('pts','คะแนน')}</b></div>`);
  });
  return rows;
}
function buildSubmitPreviewHtml(mode){
  let html = '';
  let purchaseOk = true;
  const noShip = document.getElementById('f_shipment').value === 'no_shipment';
  if (mode === 'quality' || mode === 'all') {
    const rows = currentDeductionSummary(['quality','environment']);
    html += `<div class="preview-section"><b>${L('Quality (A1/A2)','คุณภาพ (A1/A2)')}</b>${
      rows.length ? rows.join('') : `<div class="preview-row muted">${L('No deductions','ไม่มีรายการที่ถูกหักคะแนน')}</div>`
    }</div>`;
  }
  if (mode === 'delivery' || mode === 'all') {
    const dRows = currentDeductionSummary(['delivery']);
    html += `<div class="preview-section"><b>${L('Delivery (B1)','การส่งมอบ (B1)')}</b>${
      noShip ? `<div class="preview-row muted">N/A — ${L('no shipment','ไม่มีการส่งมอบ')}</div>`
             : (dRows.length ? dRows.join('') : `<div class="preview-row muted">${L('No deductions','ไม่มีรายการที่ถูกหักคะแนน')}</div>`)
    }</div>`;
    html += `<div class="preview-section"><b>${L('Purchase Amount (B2)','ยอดซื้อ (B2)')}</b>`;
    if (noShip) {
      html += `<div class="preview-row muted">N/A</div>`;
    } else {
      const tierChecked = document.querySelector('input[name="purchaseTier"]:checked');
      if (tierChecked) {
        const c = evaluationCriteria.find(x => x.id === tierChecked.value);
        html += `<div class="preview-row"><span>${c ? officialDescription(c) : ''}</span></div>`;
      } else {
        html += `<div class="preview-row" style="color:var(--danger);font-weight:600">${L('No purchase tier selected yet — required before submitting','ยังไม่ได้เลือก Purchase Tier — ต้องเลือกก่อน submit')}</div>`;
        purchaseOk = false;
      }
    }
    html += `</div>`;
  }
  return { html, purchaseOk };
}
function closeSubmitPreviewModal(){
  document.getElementById('submitPreviewModal').style.display = 'none';
  pendingSubmitMode = null;
}
async function confirmSubmitFromPreview(){
  const mode = pendingSubmitMode;
  document.getElementById('submitPreviewModal').style.display = 'none';
  if (mode === 'quality') {
    if (!await saveOfficialWorksheet('quality', true)) return;
    await submitQualitySection(true);
    alert(L('Quality section saved and submitted','บันทึกและส่งผล Quality แล้ว'));
  } else if (mode === 'delivery') {
    if (!await saveOfficialWorksheet('delivery', true)) return;
    await submitDeliverySection(true);
    alert(L('Delivery/Purchase section saved and submitted','บันทึกและส่งผล Delivery/Purchase แล้ว'));
  } else if (mode === 'all') {
    if (!await saveOfficialWorksheet('all', true)) return;
    await submitQualitySection(true);
    await submitDeliverySection(true);
    alert(L('Saved and submitted — both sections','บันทึกและส่งผลแล้ว — ทั้งสองส่วน'));
  } else {
    return;
  }
  pendingSubmitMode = null;
  // Submit succeeded — this evaluation is done for this role, close it
  // out and return to the list instead of leaving the just-submitted
  // worksheet sitting open on screen.
  resetForm();
  showTab('list');
}
function resetForm(){currentEditingEvalId=null;const picker=document.getElementById('evalPickerSection');if(picker)picker.style.display='block';const headerCard=document.getElementById('evalHeaderCard');if(headerCard)headerCard.style.display='block';const y=document.getElementById('f_year');if(!y)return;y.value=new Date().getFullYear();document.getElementById('f_month').value=String(new Date().getMonth()+1);document.getElementById('f_shipment').value='normal';document.getElementById('f_noship_reason').value='';document.getElementById('noShipRow').style.display='none';document.getElementById('f_status').value='draft';document.getElementById('f_scoring_mode').value='itemized';document.getElementById('worksheetEmpty').style.display='block';document.getElementById('worksheetBody').style.display='none';evalAttachments=[];renderEvalAttachList();}

/* ============================================================
   Master render + wiring
   ============================================================ */
function renderAll(){
  applyLang();
  populateDashboardFilters();
  populateSupplierSelect();
  populateProfileSelect();
  refreshReportCascade();
  populateCaEvalSelect();
  renderDashboardCommandCenter();
  renderEvalTable();
  renderProfile();
  renderReport();
  renderMasterSupplierTable();
  renderMasterCriteriaTable();
  renderMasterUsersTable();
  if (document.getElementById('masterPermissions')?.style.display === 'block') renderPermissionMatrix();
  if (document.getElementById('masterHolidays')?.style.display === 'block') renderHolidaysTable();
  renderSubmitStatusNote();
  applyRoleGating();
  applyCaRoleGating();
  populateYearlyCategoryFilter();
  renderYearlySummary();
  calcPreview();
}

function wireEvents(){
  document.querySelectorAll('.rail-link').forEach(btn => {
    btn.addEventListener('click', () => showTab(btn.dataset.tab));
  });
  document.getElementById('btnLoadWorksheet')?.addEventListener('click', openOrCreateWorksheet);
  document.getElementById('f_shipment')?.addEventListener('change', () => { const ns=document.getElementById('f_shipment').value==='no_shipment'; document.getElementById('noShipRow').style.display=ns?'grid':'none'; if(currentEditingEvalId){ document.getElementById('deliveryNoShipment').style.display=ns?'block':'none'; document.getElementById('purchaseNoShipment').style.display=ns?'block':'none'; document.getElementById('deliveryRows').style.display=ns?'none':'block'; document.getElementById('purchaseTierRows').style.display=ns?'none':'grid'; updateWorksheetPreview(); } });
  ['dashPeriod','dashCategory','dashShipment','dashRisk'].forEach(id => document.getElementById(id)?.addEventListener('change', refreshDashboard));
  document.getElementById('btnDashReset')?.addEventListener('click', () => { document.getElementById('dashCategory').value=''; document.getElementById('dashShipment').value=''; document.getElementById('dashRisk').value=''; refreshDashboard(); });
  document.getElementById('btnViewAllRisk')?.addEventListener('click', () => showTab('list'));
  document.querySelectorAll('.kpi.click[data-go]').forEach(k=>k.addEventListener('click',()=>showTab(k.dataset.go)));
  document.getElementById('actionTabs')?.addEventListener('click',(ev)=>{ const b=ev.target.closest('[data-role]'); if(!b) return; actionTabSel=b.dataset.role; renderActionTabs(); });
  document.getElementById('actionList')?.addEventListener('click',(ev)=>{ if(ev.target.closest('[data-more]')) showTab('list'); });
  const stepPeriod=(dir)=>{ const keys=dashPeriodKeys(), i=keys.indexOf(selectedDashPeriod()); const k=keys[i+dir]; if(k) setDashPeriod(k); };
  document.getElementById('dashPrev')?.addEventListener('click',()=>stepPeriod(-1));
  document.getElementById('dashNext')?.addEventListener('click',()=>stepPeriod(1));
  document.getElementById('dashMonthBtn')?.addEventListener('click',(ev)=>{
    ev.stopPropagation(); const pop=document.getElementById('dashMonthPop'); const open=pop.style.display==='none';
    if(open){ dashPopYear=null; renderMonthPopover(); }
    pop.style.display=open?'block':'none';
  });
  document.getElementById('dashMonthPop')?.addEventListener('click',(ev)=>{
    ev.stopPropagation();
    const cell=ev.target.closest('[data-key]'), yr=ev.target.closest('[data-yr]'), latest=ev.target.closest('[data-latest]');
    if(cell && !cell.disabled){ document.getElementById('dashMonthPop').style.display='none'; setDashPeriod(cell.dataset.key); }
    else if(yr && !yr.disabled){ dashPopYear+=parseInt(yr.dataset.yr,10); renderMonthPopover(); }
    else if(latest){ const keys=dashPeriodKeys(); document.getElementById('dashMonthPop').style.display='none'; setDashPeriod(keys[keys.length-1]); }
  });
  document.addEventListener('click',()=>{ const p=document.getElementById('dashMonthPop'); if(p) p.style.display='none'; });
  document.getElementById('trendSeg')?.addEventListener('click',(ev)=>{ const b=ev.target.closest('[data-metric]'); if(!b) return; trendMetric=b.dataset.metric; document.querySelectorAll('#trendSeg button').forEach(x=>x.classList.toggle('on',x===b)); renderPerformanceTrend(); });
  document.getElementById('paretoSeg')?.addEventListener('click',(ev)=>{ const b=ev.target.closest('[data-mode]'); if(!b) return; paretoMode=b.dataset.mode; document.querySelectorAll('#paretoSeg button').forEach(x=>x.classList.toggle('on',x===b)); renderIssuePareto(); });
  document.getElementById('btnDashPrint')?.addEventListener('click',()=>window.print());
  document.getElementById('dashOverview')?.addEventListener('toggle',()=>{ if(document.getElementById('dashOverview').open) requestAnimationFrame(renderPerformanceTrend); });
  document.getElementById('langToggle').addEventListener('click', () => {
    lang = lang === 'th' ? 'en' : 'th';
    renderAll();
  });
  document.getElementById('btnNavBack').addEventListener('click', () => history.back());
  document.getElementById('btnNavForward').addEventListener('click', () => history.forward());
  ['f_quality','f_delivery','f_purchase'].forEach(id =>
    document.getElementById(id).addEventListener('input', calcPreview)
  );
  document.getElementById('f_shipment').addEventListener('change', toggleShipmentFields);
  document.getElementById('f_scoring_mode').addEventListener('change', updateScoringModeUI);
  document.getElementById('btnSave').addEventListener('click', handleMainSubmitClick);
  document.getElementById('btnReset').addEventListener('click', resetForm);
  document.getElementById('btnSaveItems').addEventListener('click', saveItemizedChecklist);
  document.getElementById('btnSupApprove').addEventListener('click', supervisorApproveEvaluation);
  document.getElementById('btnMgrApprove').addEventListener('click', managerApproveEvaluation);
  document.getElementById('btnReject').addEventListener('click', rejectEvaluation);
  document.getElementById('btnRejectConfirm').addEventListener('click', confirmRejectFromModal);
  document.getElementById('btnRejectCancel').addEventListener('click', closeRejectModal);
  document.getElementById('btnSubmitPreviewConfirm').addEventListener('click', confirmSubmitFromPreview);
  document.getElementById('btnSubmitPreviewCancel').addEventListener('click', closeSubmitPreviewModal);
  document.getElementById('btnMarkSent').addEventListener('click', markSentToSupplier);
  document.getElementById('qualityToggle').addEventListener('click', () => {
    const s = document.getElementById('qualityWorksheet');
    setSectionCollapsed(s, !s.classList.contains('collapsed'));
  });
  document.getElementById('deliveryToggle').addEventListener('click', () => {
    const s = document.getElementById('deliveryPurchaseWorksheet');
    setSectionCollapsed(s, !s.classList.contains('collapsed'));
  });
  document.getElementById('btnYearlyRefresh').addEventListener('click', renderYearlySummary);
  document.getElementById('btnYearlyPrint').addEventListener('click', () => window.print());
  ['ys_year','ys_category'].forEach(id => document.getElementById(id).addEventListener('input', renderYearlySummary));
  document.getElementById('btnAttachUpload').addEventListener('click', uploadEvaluationAttachment);
  document.getElementById('btnCaSave').addEventListener('click', saveCorrectiveAction);
  document.getElementById('btnCaReset').addEventListener('click', resetCaForm);
  document.getElementById('btnCaMarkReceived').addEventListener('click', markCaCountermeasureReceived);
  document.getElementById('btnCaAddSet').addEventListener('click', addCaSet);
  document.getElementById('btnCaNew').addEventListener('click', () => { resetCaForm(); showTab('ca'); });
  document.getElementById('btnCaBackToList').addEventListener('click', () => showTab('list'));
  document.getElementById('btnRefreshList').addEventListener('click', () => loadEvaluations().then(renderAll));
  ['filterText','filterYear','filterMonth','filterGrade','filterWorkflowStatus','filterOpenOnly','filterHasCaOnly'].forEach(id =>
    document.getElementById(id).addEventListener('input', renderEvalTable)
  );
  document.getElementById('filterGroup')?.addEventListener('change', () => { document.getElementById('filterSupplier').value = ''; populateListSupplierFilter(); renderEvalTable(); });
  document.getElementById('filterSupplier')?.addEventListener('change', renderEvalTable);
  document.querySelectorAll('[data-mastertab]').forEach(b => b.addEventListener('click', () => setMasterTab(b.dataset.mastertab)));
  document.querySelectorAll('[data-reporttab]').forEach(b => b.addEventListener('click', () => setReportTab(b.dataset.reporttab)));
  document.querySelectorAll('[data-profiletab]').forEach(b => b.addEventListener('click', () => setProfileTab(b.dataset.profiletab)));
  document.querySelectorAll('[data-settingtab]').forEach(b => b.addEventListener('click', () => setSettingTab(b.dataset.settingtab)));
  document.getElementById('btnTranslationSaveAll').addEventListener('click', saveAllTranslationChanges);
  document.getElementById('tr_search').addEventListener('input', renderTranslationTable);
  document.getElementById('tr_category').addEventListener('change', (e) => { translationActiveCategory = e.target.value; renderTranslationTable(); });
  document.getElementById('btnSupplierSave').addEventListener('click', saveSupplier);
  document.getElementById('ms_code').addEventListener('input', (e) => {
    document.getElementById('ms_category').value = supplierGroupFromCode(e.target.value);
  });
  document.getElementById('btnSupplierReset').addEventListener('click', resetSupplierForm);
  document.getElementById('btnCriteriaSave').addEventListener('click', saveCriteria);
  document.getElementById('btnCriteriaReset').addEventListener('click', resetCriteriaForm);
  document.getElementById('btnHolidaySave').addEventListener('click', saveHoliday);
  document.getElementById('btnCreateUser').addEventListener('click', createUser);
  document.getElementById('btnHolidayReset').addEventListener('click', resetHolidayForm);
  document.getElementById('btnActivityLogRefresh').addEventListener('click', () => loadActionLog().then(renderActionLogTable));
  document.getElementById('btnParseImportFiles').addEventListener('click', parseImportFiles);
  document.getElementById('btnConfirmImport').addEventListener('click', confirmImport);
  document.getElementById('btnExportSelected').addEventListener('click', exportSelectedEvaluations);
  document.getElementById('btnNewEvaluation').addEventListener('click', () => { resetForm(); showTab('input'); });
  document.getElementById('btnBackToListFromInput').addEventListener('click', () => showTab('list'));
  ['ca_ev_filter_supplier','ca_ev_filter_year','ca_ev_filter_month'].forEach(id =>
    document.getElementById(id).addEventListener('input', populateCaEvalSelect)
  );
  document.getElementById('ca_ev_filter_allgrades').addEventListener('change', populateCaEvalSelect);
  document.getElementById('btnGoToListForExport').addEventListener('click', () => showTab('list'));
  ['alFilterTable','alFilterAction','alRevertableOnly'].forEach(id =>
    document.getElementById(id).addEventListener('input', () => loadActionLog().then(renderActionLogTable))
  );
  document.getElementById('btnOpenCycle').addEventListener('click', openMonthlyCycle);
  document.getElementById('profileSupplier').addEventListener('change', (e) => { renderProfile(); attachHistoryId(e.target.value); });
  document.getElementById('profileGroup').addEventListener('change', () => { document.getElementById('profileSupplier').value = ''; populateProfileSelect(); renderProfile(); });
  document.getElementById('rp_category').addEventListener('change', () => { document.getElementById('rp_supplier').value=''; populateReportSupplierFilter(); populateReportYearFilter(); populateReportSelect(); renderReport(); });
  document.getElementById('rp_supplier').addEventListener('change', () => { populateReportYearFilter(); populateReportSelect(); renderReport(); });
  document.getElementById('rp_year').addEventListener('change', () => { populateReportSelect(); renderReport(); });
  document.getElementById('reportSelect').addEventListener('change', (e) => { renderReport(); attachHistoryId(e.target.value); });
  document.getElementById('btnPrint').addEventListener('click', () => window.print());
  window.addEventListener('resize', renderCharts);

  document.querySelectorAll('.login-tab').forEach(b => b.addEventListener('click', () => setAuthMode(b.dataset.mode)));
  document.getElementById('btnAuthSubmit').addEventListener('click', handleAuthSubmit);
  document.getElementById('btnLogout').addEventListener('click', () => sb.auth.signOut());
  const authEmailInput = document.getElementById('auth_email');
  authEmailInput.addEventListener('input', renderIdSuggestions);
  authEmailInput.addEventListener('focus', renderIdSuggestions);
  // Delay hiding on blur so a click/mousedown on a suggestion row (or its
  // remove button) below still registers before the list disappears.
  authEmailInput.addEventListener('blur', () => setTimeout(() => {
    const box = document.getElementById('authIdSuggestions');
    if (box) box.style.display = 'none';
  }, 150));
  document.getElementById('authIdSuggestions').addEventListener('mousedown', (e) => {
    e.preventDefault(); // keep focus on the input instead of triggering its blur first
    const removeBtn = e.target.closest('[data-remove-id]');
    if (removeBtn) { removeSavedId(removeBtn.dataset.removeId); return; }
    const row = e.target.closest('[data-saved-id]');
    if (row) {
      authEmailInput.value = row.dataset.savedId;
      document.getElementById('authIdSuggestions').style.display = 'none';
      document.getElementById('auth_password').focus();
    }
  });
}

document.addEventListener('DOMContentLoaded', async () => {
  wireEvents();
  resetForm();
  resetCaForm();
  applyLang();
  if (!SELF_SIGNUP_ENABLED) {
    const signupTab = document.querySelector('.login-tab[data-mode="signup"]');
    if (signupTab) signupTab.style.display = 'none';
  }
  setAuthMode('signin');
  restoreRememberedLogin();
  await preLoginConnectionCheck();
  if (!sb || SUPABASE_URL.includes('YOUR-PROJECT')) {
    document.getElementById('loginGate').style.display = 'flex';
    setLoginMsg(t('notConfigured','Supabase is not configured — see app.js'));
    return;
  }
  await bootAuth();
});
