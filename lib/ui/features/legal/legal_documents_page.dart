import 'package:flutter/material.dart';

const String kOfficialAppVersion = '1.1.0';
const String kLegalPolicyVersion = '1.1.0';
const String kSupportContactEmail = 'seishikun8@gmail.com';

enum LegalDocumentType { privacyPolicy, termsOfService }

/// Offline-accessible viewer for SeiReminds' Privacy Policy and Terms of Service.
class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.type});

  const LegalDocumentPage.privacyPolicy({super.key})
      : type = LegalDocumentType.privacyPolicy;

  const LegalDocumentPage.termsOfService({super.key})
      : type = LegalDocumentType.termsOfService;

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPrivacy = type == LegalDocumentType.privacyPolicy;
    final sections = isPrivacy ? _privacySections : _termsSections;

    return Scaffold(
      appBar: AppBar(
        title: Text(isPrivacy ? 'Privacy Policy' : 'Terms of Service'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Card(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.65),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isPrivacy
                        ? 'SeiReminds Privacy Policy'
                        : 'SeiReminds Terms of Service',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version $kLegalPolicyVersion · Effective November 25, 2026 · Contact: $kSupportContactEmail',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Independent, unofficial student productivity app. Not affiliated with, endorsed by, or operated by Instructure, Inc. (Canvas LMS) or Holy Name University.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final section in sections)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      section.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      section.body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const List<({String title, String body})> _privacySections =
    <({String title, String body})>[
  (
    title: '1. Offline Local Data (Stays on Your Device)',
    body:
        'Your class schedules, school events, reminder settings, and history logs are stored strictly on your device in SQLite. Canvas announcements stay in memory for the current day only and are never saved to SQLite. Only temporary Canvas activity deadlines are cached in SQLite until their due date passes, then automatically deleted.',
  ),
  (
    title: '2. Encrypted Canvas API Token Storage',
    body:
        'If you connect a Canvas Personal Access Token while signed in and online, it is stored locally using hardware-backed Android Keystore encryption. Tokens are never saved in plain-text SQLite, never printed in logs, masked in the interface, and excluded from Android cloud backups and device transfers.',
  ),
  (
    title: '3. Optional Online Account & 6-Digit Email Verification',
    body:
        'An account is optional and only required to access Canvas features online. When you sign up, Supabase stores your email, optional display name, hashed password, and legal consent version/timestamp. 6-digit signup and password-recovery codes are stored only as salted SHA-256 hashes, expire after 10 minutes, and are sent directly via Gmail.',
  ),
  (
    title: '4. No Ads, No Tracking, HTTPS Only',
    body:
        'SeiReminds contains zero advertising SDKs and zero behavioral analytics trackers, never sells or shares personal data, never records audio, and enforces TLS/HTTPS on all network connections.',
  ),
  (
    title: '5. Your Data Privacy Rights (RA 10173, GDPR & Store Policies)',
    body:
        'You may export a secret-free JSON copy of your data anytime under Settings → Privacy, Legal & Security → Export My Data, and permanently delete your Supabase account, profile, OTP rows, and local Canvas token anytime via Delete Account Permanently. For inquiries, email $kSupportContactEmail.',
  ),
];

const List<({String title, String body})> _termsSections =
    <({String title, String body})>[
  (
    title: '1. Unofficial Student Tool Notice',
    body:
        'SeiReminds is an independent student productivity app and is not affiliated with, endorsed by, or operated by Instructure, Inc. (Canvas LMS) or Holy Name University. All third-party trademarks belong to their respective owners.',
  ),
  (
    title: '2. Acceptable Use & Canvas Tokens',
    body:
        'You may only connect a Canvas API token belonging to your own account in compliance with your school IT policies and Canvas Terms of Use. Keep your password, verification codes, and Canvas token confidential.',
  ),
  (
    title: '3. Alarm & Reminder Reliability Disclaimer',
    body:
        'Mobile alarms depend on Android OS battery rules, OEM firmware, device power state, and granted notification/exact-alarm permissions. SeiReminds is a study aid and does not guarantee uninterrupted alarm delivery; keep a backup alarm for critical exams.',
  ),
  (
    title: '4. Account Verification & Permanent Deletion',
    body:
        'One verified account is allowed per email address. You can permanently delete your account and server data at any time in Settings → Privacy, Legal & Security → Delete Account Permanently.',
  ),
  (
    title: '5. Warranty Disclaimer & Limitation of Liability',
    body:
        'SeiReminds is provided "AS IS" and "AS AVAILABLE" without warranties of any kind to the fullest extent permitted by law. The developer is not liable for missed classes, missed deadlines, or device data loss. Open source notices are available offline in Settings → Open Source Licenses.',
  ),
];
