# BW Atlas Project Architecture

## Flutter Frontend
BW Atlas is implemented as a Flutter multi-platform application with modular feature folders for Fire Door, Fire Stopping, Snagging, Installation, Remedials, and shared Survey workflows. The UI layer is organized by feature, with state managed through Riverpod providers and route-based navigation.

## Firebase Authentication
Authentication is handled with Firebase Auth where available, combined with role-aware application state and guarded routes. The app supports email/password and invitation-driven onboarding flows.

## Firestore
Cloud persistence is primarily implemented with Cloud Firestore collections scoped by company/workspace context. Firestore is used for surveys, project records, invites, status transitions, and approvals.

## Firebase Storage
Firebase Storage is used for media and report assets such as photos and generated files linked to inspections and workflow records.

## Hive Local Storage
Hive is used for local/offline-friendly persistence including session data and environment-scoped cached domain state. Namespaced local boxes reduce staging/production data collisions.

## PDF Reporting
PDF generation is implemented in dedicated feature builders to produce operational and assessment documents (inspection reports, installation/pre-install documents, remedial reports, snagging outputs).

## Role-Based Permissions
The application enforces role-based permissions (for example manager, worker, owner/super-admin contexts). Access to navigation modules, data actions, and approval steps is controlled through user role and workspace assignment.

## Public Repository Security Note
This public version intentionally removes sensitive secrets, production endpoints, and private Firebase credentials. Placeholder values are used where required to preserve architecture visibility.
