/* ============================================================
   config.js — the ONLY file to edit when the app moves to another
   Supabase (cloud project, or self-hosted on the company server).
   Do not put a service_role key here — only the public/anon key.
   ============================================================ */
window.APP_CONFIG = {
  // Cloud test project (current). Replace with the company server's API URL, e.g. 'https://eval.eht.local'
  SUPABASE_URL: 'https://pddxmsjprhdleheqsxgd.supabase.co',
  // Public "publishable"/anon key. Safe to expose in the browser — Row Level Security protects the data.
  SUPABASE_ANON_KEY: 'sb_publishable_zzhls9FcLJFVKuHksXMfpA_xar2__MU'
};
