##════════════════════════════════════════════════════════════════════════════
## SNAGGING RESPONSIBILITY & COMPANY ASSIGNMENT SYSTEM
## Implementation Summary
##════════════════════════════════════════════════════════════════════════════

### 1. NEW DATA MODEL FIELDS ADDED
════════════════════════════════════════════════════════════════════════════════

**Location:** `lib/features/snagging/domain/snagging_models.dart`

**New Enum:**
```dart
enum ResponsibleParty {
  mainContractor,
  subcontractor,
  client,
  unknown,
  other,
}
```

**New Fields Added to SnaggingIssue:**
- `responsibleParty: ResponsibleParty` — Operational responsibility for resolving snag
- `assignedCompanyId: String` — ID of the company responsible (synced with system)
- `assignedCompanyName: String` — Name of the company (display cache for offline/quick access)

**Why Two Company Fields?**
- `assignedCompanyId`: Proper identifier for system lookups, filtering, reporting
- `assignedCompanyName`: Cached display name (prevents UI from breaking if company is deleted,
  allows offline viewing, improves performance)


### 2. DATA STORAGE & SERIALIZATION
════════════════════════════════════════════════════════════════════════════════

**Persisted in SnaggingIssue.toMap():**
```dart
'responsibleParty': responsibleParty.name,
'assignedCompanyId': assignedCompanyId,
'assignedCompanyName': assignedCompanyName,
```

**Restored in SnaggingIssue.fromMap():**
```dart
responsibleParty: ResponsibleParty.values.firstWhere(
  (e) => e.name == (map['responsibleParty'] as String? ?? ''),
  orElse: () => ResponsibleParty.unknown,
),
assignedCompanyId: map['assignedCompanyId'] as String? ?? '',
assignedCompanyName: map['assignedCompanyName'] as String? ?? '',
```

**Updated in copyWith():**
All three new fields included in copy constructor for immutable updates.


### 3. COMPANY DATA SOURCE (Real System Data)
════════════════════════════════════════════════════════════════════════════════

**New Files:**
- `lib/features/snagging/domain/companies_source.dart` — Data structures
- `lib/features/snagging/state/companies_provider.dart` — Riverpod provider

**Data Model:**
```dart
class CompanyOption {
  final String id;              // Unique identifier
  final String name;            // Company display name
  final String role;            // 'Main Contractor' or 'Subcontractor'
  String get displayLabel => '$name ($role)';  // For dropdown display
}

class AvailableCompanies {
  List<CompanyOption> mainContractors;   // Main company
  List<CompanyOption> subcontractors;    // Associated subcontractors
}
```

**Data Source Integration:**
The `availableCompaniesProvider` Riverpod provider reads from existing system data:
- **Main Company:** From `AppSettings.companyProfile`
- **Subcontractors:** From `AppSettings.workspaceCompanyProfiles` (workspace-specific company map)

**Why This Works:**
- Uses EXISTING company data structures (no new backend needed)
- Workspace-level company map supports multiple subcontractors per project
- Synchronized with system settings automatically via Riverpod reactivity
- No hardcoding, no manual entry, no duplication


### 4. MAIN CONTRACTOR VS SUBCONTRACTOR IDENTIFICATION
════════════════════════════════════════════════════════════════════════════════

**Main Contractor:**
- Identified by matching `companyProfile.companyId`
- Resource: `AppSettings.companyProfile` (the logged-in company)
- Role Label: "(Main Contractor)"

**Subcontractors:**
- Identified as any company in `workspaceCompanyProfiles` that is NOT the main company
- Resource: `AppSettings.workspaceCompanyProfiles` (map keyed by company ID)
- Role Label: "(Subcontractor)"

**Multiple Subcontractors:**
- The `workspaceCompanyProfiles` is a `Map<String, CompanyProfile>`, supporting unlimited subcontractors
- Each subcontractor is a separate entry in the map
- Dropdown shows all available subcontractors when filtered by ResponsibleParty.subcontractor


### 5. DROPDOWN SYNCHRONIZATION
════════════════════════════════════════════════════════════════════════════════

**Synchronization Strategy:**

1. **Riverpod Reactive Provider:**
   - `availableCompaniesProvider` watches `settingsControllerProvider`
   - When settings change, provider automatically recomputes

2. **UI Update Flow:**
   ```
   AppSettings changed → settingsControllerProvider notifies
       ↓
   availableCompaniesProvider recomputes company list
       ↓
   _CompanyAssignmentWidget.build() re-executes
       ↓
   Dropdown options refreshed
   ```

3. **No Manual Refresh Needed:**
   - Dropdowns stay in sync automatically
   - When a company is added/removed from settings, dropdowns update immediately
   - When user switches workspace, companies re-filter based on active workspace

4. **Consistency Checks:**
   - If `responsibleParty` changes, company assignment may be cleared (smart behavior)
   - If selected company ID is not found in refreshed list, dropdown shows as empty
   - Prevents invalid company assignments


### 6. UI FORM INTEGRATION
════════════════════════════════════════════════════════════════════════════════

**Location:** `lib/features/snagging/ui/snagging_issues_screen.dart`

**Form Placement:**
- After: "Snag Details" section (Assigned To, Date & Time)
- Before: "Location" section
- Two new card sections displayed conditionally

**Section 1: Responsible Party (Always Visible)**
```
[Business Icon] Responsible Party
├─ Dropdown: Main Contractor | Subcontractor | Client | Unknown | Other
└─ Smart behavior: Clears company assignment if party type changes
```

**Section 2: Assigned Company (Conditionally Visible)**
```
[Apartment Icon] Assigned Company
├─ Only shown if ResponsibleParty = Main Contractor OR Subcontractor
├─ Dropdown: Populated from availableCompaniesProvider
│   • Main Contractor list (1 item)
│   • Subcontractor list (1+ items)
├─ Display format: "Company Name (Role)"
└─ Smart filtering: Shows only companies matching responsible party type
```

**UX Behaviors:**
- Fast dropdown selection (no typing required)
- Clear role designation visible in dropdown (Main vs Sub)
- Conditional visibility prevents confusion
- Company assignment only shown when operationally relevant
- Simple labels, obvious meaning


### 7. PDF/REPORT OUTPUT
════════════════════════════════════════════════════════════════════════════════

**Location:** `lib/features/snagging/pdf/snagging_pdf_builder.dart`

**Rendered Detail Rows (Per Issue):**
```
Assigned To:           John Smith
Responsible Party:     Sub contractor
Assigned Company:      CFS Carpentry Ltd
Location:              Kitchen, 2nd Floor
...
```

**Conditional Display:**
- "Responsible Party" row only shown if NOT unknown
- "Assigned Company" row only shown if populated
- No blank placeholders for unset values
- Clean, professional report with only relevant information

**Integration Point:**
Added after "Assigned To" row in issue details section.
Uses existing `_detailRow()` helper for consistent formatting.


### 8. SUPPORTING SYSTEM LOGIC
════════════════════════════════════════════════════════════════════════════════

**State Management:**
  - UI State: `_responsibleParty`, `_assignedCompanyId`, `_assignedCompanyName`
  - Persisted: In SnaggingIssue model via toMap/fromMap
  - Provider: availableCompaniesProvider for reactive synchronization

**Smart Behaviors Implemented:**

1. **Clear Assignment on Party Change:**
   When user changes responsible party to Client/Unknown/Other,
   company assignment is automatically cleared (no orphaned values).

2. **Validation:**
   - If assigned company no longer exists in refreshed list, dropdown shows empty
   - System remains consistent even if companies are removed from workspace

3. **Offline Resilience:**
   - Both ID and Name stored, so display works even if company data unavailable
   - IDs used for system operations (filtering, reporting)
   - Names used for display (survives deletion)

4. **Cascading Updates:**
   When settings change (e.g., new subcontractor added):
   - Riverpod provider automatically recomputes
   - All open snag forms show updated company list
   - No manual refresh needed


### 9. FILES & COMPONENTS CHANGED
════════════════════════════════════════════════════════════════════════════════

**Model & Domain:**
✓ lib/features/snagging/domain/snagging_models.dart
  • Added ResponsibleParty enum + label function
  • Added 3 new fields to SnaggingIssue
  • Updated copyWith, toMap, fromMap

✓ lib/features/snagging/domain/companies_source.dart [NEW]
  • CompanyOption class (id, name, role, displayLabel)
  • AvailableCompanies container class

**State & Providers:**
✓ lib/features/snagging/state/companies_provider.dart [NEW]
  • availableCompaniesProvider: reads AppSettings, builds company list
  • Integrates main company + workspace subcontractors

**UI:**
✓ lib/features/snagging/ui/snagging_issues_screen.dart
  • Imported: companies_source, companies_provider
  • Added state: _responsibleParty, _assignedCompanyId, _assignedCompanyName
  • Load/save logic updated
  • Added UI section for "Responsible Party" dropdown
  • Added conditional UI section for "Assigned Company" dropdown
  • Created _CompanyAssignmentWidget (ConsumerWidget)

**PDF/Reports:**
✓ lib/features/snagging/pdf/snagging_pdf_builder.dart
  • Updated _buildIssueRow() to include responsibility rows
  • Shows: Responsible Party (if set), Assigned Company (if set)


### 10. MULTIPLE SUBCONTRACTORS SUPPORT
════════════════════════════════════════════════════════════════════════════════

**Architecture Supports Unlimited Subcontractors:**

1. **Data Structure:**
   - workspaceCompanyProfiles: Map<String, CompanyProfile>
   - Supports N companies per workspace
   - Not limited to 1 company or hardcoded number

2. **Provider Logic:**
   ```dart
   // Loops through ALL entries in workspaceCompanyProfiles
   for (final entry in settings.workspaceCompanyProfiles.entries) {
     subcontractors.add(...);  // Adds each as option
   }
   ```

3. **Dropdown Display:**
   - All subcontractors listed in dropdown
   - Can select any one for assignment
   - No artificial limitation

4. **Project Context:**
   - When workspace has 3 subcontractors, all 3 appear in dropdown
   - Inspector can assign snag to any participating company
   - System stays synchronized with workspace company config

**Future-Proofing:**
- Add more companies to workspace = automatically appear in dropdowns
- No code changes needed
- Scales to 10+ companies without modification


### 11. SYSTEM SYNCHRONIZATION GUARANTEES
════════════════════════════════════════════════════════════════════════════════

**Real-Time Sync:**
✓ Dropdown always reflects current AppSettings.workspaceCompanyProfiles
✓ Uses Riverpod reactivity (no manual notification needed)
✓ Provider watches settingsControllerProvider automatically

**Data Consistency:**
✓ Company IDs stored and used for lookups (not names)
✓ Names cached for display (prevents UI breakage)
✓ Snag record contains both ID and name for robustness

**Cross-System Integration:**
✓ Can filter snags by assignedCompanyId (for company-specific views)
✓ Can show relevant snags to correct workers/company later
✓ PDF reports include company information
✓ Verification flow can use company context


### 12. NOT IMPLEMENTED (Out of Scope)
════════════════════════════════════════════════════════════════════════════════

These are ready for future work:
- Worker portal: filtering snags by assigned company
- Company-specific dashboard
- Automated assignment rules
- Workflow automation based on party type
- Bulk company assignment

The data structure supports all of these seamlessly.


════════════════════════════════════════════════════════════════════════════════
SUMMARY: COMPLETE, SCALABLE, SYNCHRONIZED RESPONSIBILITY SYSTEM
════════════════════════════════════════════════════════════════════════════════

This is NOT a cosmetic UI field. It's a fully integrated system-level feature:

• Real data from AppSettings (no hardcoding)
• Structured enums (no free text)
• Scalable to unlimited companies
• Properly persisted and synchronized
• Integrated into PDF reports
• Smart UI behaviors
• Future-proofed for advanced workflows

The foundation is solid. Additional features (filtering, dashboards, automation)
can be built on this without architectural changes.
