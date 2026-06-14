class InfoSection {
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;

  const InfoSection({
    required this.title,
    this.paragraphs = const [],
    this.bullets = const [],
  });
}

class InfoPageContent {
  final String title;
  final String subtitle;
  final List<InfoSection> sections;

  const InfoPageContent({
    required this.title,
    required this.subtitle,
    required this.sections,
  });
}

const String defaultSupportEmail = 'support@bw-atlas.example';
const String defaultSupportPhone = '+44 (0)20 0000 0000';

const InfoPageContent aboutAppContent = InfoPageContent(
  title: 'About App',
  subtitle:
      'BW Atlas Construction Compliance Platform is a professional platform for inspection, remediation, installation workflows, and compliance reporting.',
  sections: [
    InfoSection(
      title: 'Professional Fire Door Management System',
      paragraphs: [
        'This application is designed for professional fire door management, covering inspections, maintenance actions, compliance reporting, and installation workflows in one operational platform.',
        'It supports clear evidence capture, structured approvals, and project-level records so teams can manage work consistently across sites.',
      ],
    ),
    InfoSection(
      title: 'Core Operational Modules',
      bullets: [
        'Fire door inspections',
        'Remedial works tracking',
        'Pre-installation surveys',
        'Installation and handover',
        'Report and certificate generation',
        'Manager and worker team workflows',
      ],
    ),
    InfoSection(
      title: 'Branding and Presentation',
      paragraphs: [
        'BW Atlas branding is used as the default presentation profile across the application and generated documentation where customer branding is not configured.',
      ],
    ),
  ],
);

const InfoPageContent howItWorksContent = InfoPageContent(
  title: 'How the App Works',
  subtitle:
      'End-to-end workflow from project creation to certification and export, designed for manager and worker collaboration.',
  sections: [
    InfoSection(
      title: '1. Create Project',
      bullets: [
        'Manager creates a project with client and site details.',
      ],
    ),
    InfoSection(
      title: '2. Add Doors',
      bullets: [
        'Doors are added with ID, location, type, rating, and related details.',
      ],
    ),
    InfoSection(
      title: '3. Fire Door Inspection',
      bullets: [
        'Inspector checks each door.',
        'Outcomes are recorded as Pass / Fail / Critical.',
        'Inspection photos are uploaded as evidence.',
        'Failed items are converted to remedial tasks automatically.',
      ],
    ),
    InfoSection(
      title: '4. Remedial Works',
      bullets: [
        'Worker opens assigned/problem doors.',
        'Worker sees defect-focused items only.',
        'Worker uploads repair evidence photos.',
        'Worker submits work for approval.',
      ],
    ),
    InfoSection(
      title: '5. Manager Review',
      bullets: [
        'Manager reviews worker evidence.',
        'Manager approves or rejects each item.',
        'Manager can add comments and review photos.',
        'Approved work feeds certificate/report outputs.',
      ],
    ),
    InfoSection(
      title: '6. Final Certification',
      bullets: [
        'Manager confirms completion.',
        'Final PDF output is generated for records and delivery.',
      ],
    ),
    InfoSection(
      title: '7. Pre-Installation Survey',
      bullets: [
        'Manager creates the factory/order specification for new doors.',
      ],
    ),
    InfoSection(
      title: '8. Installation and Handover',
      bullets: [
        'Worker installs and uploads completion evidence photos.',
        'Manager reviews and approves before handover completion.',
      ],
    ),
    InfoSection(
      title: '9. Drawings / Plans (DRW)',
      bullets: [
        'Manager uploads project drawings/plans.',
        'Door pins can be used for navigation.',
        'Workers can view plans in-field.',
      ],
    ),
    InfoSection(
      title: '10. Reports and Export',
      bullets: [
        'Single-door export as PDF.',
        'Multi-door export as ZIP/PDF package.',
      ],
    ),
    InfoSection(
      title: '11. Company Settings and Branding',
      bullets: [
        'Company logo can be uploaded.',
        'If no logo is uploaded, BW Atlas branding is used by default.',
      ],
    ),
  ],
);

const InfoPageContent termsConditionsContent = InfoPageContent(
  title: 'Terms and Conditions',
  subtitle:
      'Please review these terms carefully before using the application in live operational workflows.',
  sections: [
    InfoSection(
      title: '1. Introduction',
      paragraphs: [
        'This application is provided by BW Atlas for managing fire door inspections, remedial works, pre-installation surveys, installation handovers, and report generation.',
      ],
    ),
    InfoSection(
      title: '2. Purpose of the App',
      bullets: [
        'The app is a professional recording and workflow tool.',
        'It does not replace professional judgment or legal responsibility.',
      ],
    ),
    InfoSection(
      title: '3. User Responsibility',
      bullets: [
        'Users must enter accurate data.',
        'Users must upload correct evidence.',
        'Users must verify details before approval.',
      ],
    ),
    InfoSection(
      title: '4. Manager Approval Responsibility',
      paragraphs: [
        'When a manager approves a door, they confirm that work has been physically reviewed and accepted.',
      ],
    ),
    InfoSection(
      title: '5. Photo Evidence',
      paragraphs: [
        'Photos must be genuine, relevant, and linked to actual conditions/work completed.',
      ],
    ),
    InfoSection(
      title: '6. Reports and Certificates',
      paragraphs: [
        'Reports are generated from entered system data.',
        'They support documentation workflows but do not replace external legal or third-party certification unless confirmed by the responsible organisation.',
      ],
    ),
    InfoSection(
      title: '7. Branding and Logo',
      bullets: [
        'Users may upload their own company logo.',
        'If no logo is uploaded, BW Atlas branding is used by default in generated reports/PDFs.',
        'Company display name and branding may be configurable depending on version/features.',
      ],
    ),
    InfoSection(
      title: '8. Data Storage',
      paragraphs: [
        'Users are responsible for reviewing and exporting important records.',
        'The app stores workflow/report data within its configured storage system.',
      ],
    ),
    InfoSection(
      title: '9. Limitation of Liability',
      paragraphs: [
        'BW Atlas is not liable for inaccurate data entered by users, incorrect approvals, non-compliant work, or misuse of the app.',
      ],
    ),
    InfoSection(
      title: '10. Updates and Changes',
      paragraphs: [
        'Features, workflows, and terms may be updated over time.',
      ],
    ),
    InfoSection(
      title: '11. Contact',
      bullets: [
        'Support email: support@bw-atlas.example',
        'Support phone: +44 (0)20 0000 0000',
      ],
    ),
  ],
);

const InfoPageContent privacyPolicyContent = InfoPageContent(
  title: 'Privacy Policy',
  subtitle:
      'Draft privacy policy structure for product use, data handling, and support workflows.',
  sections: [
    InfoSection(
      title: 'Data Collected',
      paragraphs: [
        'The app records project, door, inspection, workflow, and approval data required for fire door operational processes.',
      ],
    ),
    InfoSection(
      title: 'Photos and Documents',
      paragraphs: [
        'Photo and document evidence uploaded by users is stored with related workflow records to support reporting, verification, and auditability.',
      ],
    ),
    InfoSection(
      title: 'User Accounts',
      paragraphs: [
        'User account data such as role, name, and contact identifiers may be used for access control, action attribution, and workflow ownership.',
      ],
    ),
    InfoSection(
      title: 'Company Information',
      paragraphs: [
        'Company profile information, including branding assets, may be used in-app and in generated documents where configured.',
      ],
    ),
    InfoSection(
      title: 'Report and Export Data',
      paragraphs: [
        'Generated reports and exported files reflect data captured in the application at the time of generation.',
      ],
    ),
    InfoSection(
      title: 'Data Retention',
      paragraphs: [
        'Retention of records depends on deployment/storage settings and organisational policy. Users should export and archive records where required by policy or regulation.',
      ],
    ),
    InfoSection(
      title: 'Contact for Privacy Queries',
      bullets: [
        'Privacy email: privacy@bw-atlas.example',
        'Support email: support@bw-atlas.example',
      ],
    ),
  ],
);

const InfoPageContent contactSupportContent = InfoPageContent(
  title: 'Contact and Support',
  subtitle:
      'For product assistance, workflow guidance, and support requests, use the channels below.',
  sections: [
    InfoSection(
      title: 'Support Channels',
      bullets: [
        'Company: BW Atlas (default)',
        'Support email: support@bw-atlas.example',
        'Support phone: +44 (0)20 0000 0000',
      ],
    ),
    InfoSection(
      title: 'Help and Assistance',
      paragraphs: [
        'Use support to request help with inspections, remedials, installation handover workflows, and report/certificate generation.',
      ],
    ),
    InfoSection(
      title: 'Branding Note',
      paragraphs: [
        'If company branding is customised, generated reports may use the customer uploaded logo. Otherwise BW Atlas branding is used by default.',
      ],
    ),
  ],
);
