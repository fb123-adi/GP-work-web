# SIDADI Workspace — going live

**Before anything else:** open `sidadi-config.js` and fill in every `business` field: address, state, GSTIN, CIN, contact email and phone, grievance email, and court city. These appear on invoices, payslips, the sign-in page and the legal pages. The Legal page lists any fields that are still missing.

Setup takes about 20 minutes. Until you finish step 4, the app shows a "not connected yet" screen to everyone who opens it.

## 1. Create the backend (Supabase, free)
1. Sign up at https://supabase.com, then click **New project**. Pick the **Mumbai** region.
2. Open **SQL Editor → New query**, paste everything from `supabase/setup.sql`, and click **Run**. It also creates the private `documents` file bucket. Re-run it whenever this file changes; it is safe to run again.

## 2. Turn on sign-in methods
Go to **Authentication → Sign In / Providers**.
- **Email**: on by default. You can leave "Confirm email" on.
- **Google**: in Google Cloud Console, go to APIs & Services → Credentials and create an OAuth client ID of type "Web". Set the authorised redirect URI to `https://<your-project>.supabase.co/auth/v1/callback`, then paste the Client ID and Secret into Supabase.
- **Facebook**: create an app at developers.facebook.com and add "Facebook Login". Use the same callback URL.
- **Apple**: needs a paid Apple Developer account. You can skip it for now; the button will show a "not set up" message.

## 3. Create the admin login
1. Go to **Authentication → Users → Add user → Create new user**. Enter the admin's email and a strong password, and tick **Auto confirm**.
2. In the **SQL Editor**, run the following with your admin email in place of the example:
   ```sql
   insert into public.members (user_id, emp_id, is_admin)
     select id, 'ADMIN', true from auth.users where email = 'admin@greenprintech.com'
     on conflict (user_id) do update set is_admin = true;
   ```
The admin then signs in on the **Admin** tab with that email and password. You can change the password later from **Admin login** in the sidebar.

## 4. Connect the app
Go to **Project Settings → API**. Copy the **Project URL** and the **anon public** key into `sidadi-config.js`.

## 5. Publish on GitHub Pages
1. Push this repository to GitHub. The included workflow (`.github/workflows/pages.yml`) copies the `project/` folder to the `gh-pages` branch on every push to `main`.
2. GitHub Pages serves the `gh-pages` branch (Settings → Pages → Deploy from a branch → gh-pages / root). The workflow keeps that branch up to date.
3. Your app will be live at `https://<username>.github.io/<repo>/`.
4. In Supabase, go to **Authentication → URL Configuration**. Set the **Site URL** to that address and add it under **Redirect URLs** as `https://<username>.github.io/<repo>/**`.

## 6. Email alerts for new sign-ups (optional)
1. Create a free account at https://resend.com and copy your API key.
2. Install the Supabase CLI and run:
   ```
   supabase login
   supabase link --project-ref <your-project-ref>
   supabase secrets set RESEND_API_KEY=re_xxx ADMIN_EMAIL=admin@greenprintech.com WEBHOOK_SECRET=<long-random-text> UNSUBSCRIBE_TOKEN=<another-long-random-text>
   supabase functions deploy notify-new-signup --no-verify-jwt
   ```
3. To send from your own address (otherwise Resend only delivers to your own account email), verify your domain in Resend, then also set `ALERT_FROM="SIDADI <alerts@yourdomain.com>"`.
4. In Supabase, go to **Database → Webhooks → Create**. Set table to `records`, event to **Insert**, and type to **Supabase Edge Function** → `notify-new-signup`. Add the HTTP header `x-webhook-secret` with the same secret you set above.

## 7. Moving to Vercel later
In Vercel, choose **Add New → Project** and import the GitHub repo. Set the framework preset to **Other**; no build step is needed. Then add the Vercel URL to the Supabase **Redirect URLs** list.

## Install on phones
Open the live URL on the phone.
- **Android (Chrome)**: menu → **Install app**.
- **iPhone (Safari)**: Share → **Add to Home Screen**.

## How it works
- **Who can join**: anyone can sign up with Google, Facebook, Apple, or email. They're active immediately and the admin sees them under **Sign-ins**.
- **Pre-created profiles**: if the admin adds a person with an email first, that person is linked to the profile automatically when they sign in.
- **Staying signed in**: sessions persist on each device. Recent accounts are offered on the sign-in screen for one-tap return.
- **Live view**: the admin sees who is online right now, every sign-in and sign-out, and all activity as it happens.
- **Data access**: employees can only read their own data. This is enforced by the database, not just the app.
- **Excel export**: **Sign-ins → Export to Excel** downloads sign-ins, activity, assignments, daily updates and people.

## Roles
In **People**, edit a person to set their role:
- **Staff**: their own work, leave, documents and payslips.
- **Manager**: also orders and job cards, customers, inventory and purchases.
- **Accounts**: also invoices, customers, inventory and purchases.

The admin sees everything, including payroll, attendance, leave approvals and privacy requests. The database enforces these limits, not just the screens.

## Your compliance duties
- **Privacy requests**: act on them under **Privacy requests** without undue delay, then tell the person when it's done.
- **Payroll**: confirm PF, ESI, professional tax and TDS with your accountant. The app's figures follow `sidadi-config.js` and don't calculate income tax.
- **Legal pages**: have a lawyer review `Legal.dc.html` before launch. It is written for India's DPDP Act 2023, but it is a starting point, not legal advice.

## Plan limits
The Supabase free plan pauses a project after 7 days without use and has no automatic backups. Move to Pro ($25/month) once staff rely on the app daily.
