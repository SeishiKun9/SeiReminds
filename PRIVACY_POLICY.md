# SeiReminds Privacy Policy

**Effective Date:** November 25, 2026  
**Version:** 1.1.0  
**Contact:** seishikun8@gmail.com

SeiReminds is an independent, unofficial student class scheduler and reminder application. SeiReminds is **not** affiliated with, endorsed by, or officially operated by Instructure, Inc. (Canvas LMS) or Holy Name University.

---

## 1. Data Stored Locally on Your Device (100% Offline Core)

All core scheduling features operate completely offline and stay strictly on your device inside a local SQLite database (`seireminds.db`):

- **Class Schedules & School Events:** Subjects, sections, days, times, and reminder preferences.
- **Settings & History Logs:** Local edit history and your History visibility preference.
- **Temporary Canvas Activities:** Only Canvas activity/assignment reminders are cached temporarily in SQLite until their deadline (`due_at`) expires, after which they are automatically deleted. Canvas announcements are kept in memory for the current day only and are **never** stored in SQLite.
- **Canvas API Token (Encrypted):** If you choose to connect Canvas while signed in and online, your personal Canvas API token is stored strictly on-device in hardware-backed Android Keystore encryption (`flutter_secure_storage`). It is **never** stored in plain-text SQLite, **never** logged, **never** displayed in full after saving, and excluded from Android cloud backups and device-to-device transfers.

## 2. Data Processed Online (Optional Account & Canvas Features)

Signing in is required **only** if you choose to access Canvas Settings and Canvas Hub while online:

- **Account Information (Supabase Auth & Database):** Your email address, optional display name, hashed password, and legal consent version/timestamp (`public.profiles`).
- **6-Digit Email Verification & Password Recovery Codes:** One-time 6-digit codes are stored only as salted SHA-256 hashes (`public.email_otp_codes`), expire in 10 minutes, lock after 5 wrong attempts, and are sent directly via Gmail solely to verify account creation or password resets.
- **Canvas LMS Requests:** When online and connected, SeiReminds makes read-only HTTPS `GET` requests directly to your configured Canvas server (default: `https://holynameuniversity.instructure.com`) using your encrypted token. SeiReminds never modifies your Canvas courses or automatically revokes your Canvas token.

## 3. What We Never Do

- We do **not** sell, rent, or share your personal data with third parties.
- We do **not** include third-party advertising SDKs or behavioral analytics trackers.
- We do **not** record microphone audio or transmit your offline class timetable to any server.
- All network traffic enforces HTTPS/TLS (`cleartextTrafficPermitted="false"`).

## 4. Your Privacy Rights (Philippine Data Privacy Act RA 10173, GDPR & Store Policies)

You retain full control over your personal data at all times:

- **Right to Access & Data Portability:** Export a secret-free JSON copy of your local schedules, events, history, and account email anytime via **Settings → Privacy, Legal & Security → Export My Data**.
- **Right to Rectification:** Edit your schedules, events, or account password at any time.
- **Right to Erasure (In-App Account Deletion):** Permanently delete your SeiReminds account, server profile, OTP records, and local encrypted Canvas token anytime via **Settings → Privacy, Legal & Security → Delete Account Permanently**. You can also clear local history or uninstall the app to remove all on-device SQLite data.
- **Right to Withdraw Consent:** Sign out or disconnect Canvas at any time while continuing to use offline schedules and alarms.

## 5. Children & Student Privacy

SeiReminds is intended for students aged 13 and above (or with parental/guardian permission where required by local law). If you believe an account was created without required consent, email **seishikun8@gmail.com** or use in-app **Delete Account Permanently** for immediate removal.

## 6. Changes & Contact

Material updates to this Privacy Policy will increment the policy version and effective date inside the app. For privacy requests or data concerns, contact **seishikun8@gmail.com**.
