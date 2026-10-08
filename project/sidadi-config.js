// SIDADI Workspace settings. Edit this one file before publishing.

export default {
  // Supabase → Project Settings → API. The anon key is safe to publish; access is enforced by supabase/setup.sql.
  // Leave both empty to run in demo mode (data stays in this browser only).
  supabaseUrl: '',
  supabaseAnonKey: '',

  // Shown on invoices, payslips, the sign-in page and the legal pages. Fill every field before going live.
  business: {
    legalName: 'Green Printing Solutions Pvt Ltd',
    brand: 'SIDADI',
    address: '',            // registered office address
    state: '',              // e.g. 'Delhi' — used to decide CGST+SGST vs IGST on invoices
    gstin: '',
    cin: '',
    email: '',              // general contact email
    phone: '',
    grievanceOfficer: 'Pradeep Kumar Aggarwal',
    grievanceEmail: '',     // privacy / data-request contact (required under India's DPDP Act)
    jurisdiction: '',       // city whose courts handle disputes, e.g. 'New Delhi'

    // HR & payroll
    leavePolicy: { Casual: 12, Sick: 12, Earned: 15 },   // days per calendar year
    workDaysPerWeek: 6,     // 5 = Mon–Fri, 6 = Mon–Sat
    pfEnabled: true,        // employee PF 12% of basic (capped at ₹15,000 basic)
    esiEnabled: true,       // employee ESI 0.75% when gross ≤ ₹21,000
    professionalTax: 200,   // per month; set 0 if your state has none
  },
};
