# BW Atlas

## Project Overview
BW Atlas is a Flutter-based field operations platform for fire-safety inspections and delivery workflows. It combines module-based data capture, role-based execution, approval controls, and PDF reporting.

This public repository is prepared for academic portfolio and assessment usage. Sensitive production values are removed or replaced with placeholders.

## Problem Statement
Inspection teams often use fragmented tools for capture, assignment, approvals, and reporting. BW Atlas addresses this with a unified workflow that supports project delivery from inspection to final report.

## Main Features
- Multi-module inspection workflows
- Defect capture and task progression
- Approval and status transitions
- PDF report generation
- Role-based access controls
- Environment-scoped runtime behavior

## User Roles
- Manager: creates projects, assigns work, approves outcomes
- Worker: executes assigned tasks and submits evidence
- Owner/Super Admin context: oversees platform and company-level control

## Fire Door Module
Fire door inspection, condition tracking, defect recording, and downstream remedial/installation transitions.

## Fire Stopping Module
Fire stopping inspection workflows with evidence capture and dedicated reporting paths.

## Snagging Module
Snagging issue lifecycle with verification and report-ready closure state.

## Technologies Used
- Flutter / Dart
- Riverpod
- GoRouter
- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Hive Local Storage
- Flutter PDF reporting stack

## Architecture Overview
The application follows a feature-oriented modular architecture:
- Presentation layer: module UI and reusable widgets
- State layer: Riverpod controllers/providers
- Domain layer: models and workflow business rules
- Data layer: Firebase cloud data + Hive local persistence
- Reporting layer: module-specific PDF builders

For full details see [docs/project-architecture.md](docs/project-architecture.md).

## Screenshots Section
Store assessment screenshots in [screenshots](screenshots) and reference them here.

Suggested files:
- screenshots/dashboard.png
- screenshots/fire-door-inspection.png
- screenshots/workflow-approval.png
- screenshots/pdf-report-preview.png

## Future Improvements
- CI/CD automation for build and quality gates
- Expanded unit and integration test coverage
- Improved offline sync conflict handling
- Extended analytics and observability
- Advanced audit export workflows

## Public Repository Safety Notes
Sensitive items are excluded or sanitized in this public snapshot:
- Firebase service configuration files
- Keystore/signing credentials
- Local environment secret files
- Internal default password values
- Production endpoint values

Use your own private credentials and environment values when running the project locally.
