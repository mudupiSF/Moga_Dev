# Reusable Stage/Sub-Stage Requirements Prompt

Copy the prompt below and replace all values inside `<...>` before running it.

---

## Prompt

I need client-facing requirements documentation and Excel entries for the following screen. The output will be submitted to the client for sign-off, so write in clear business and functional language.

- **Stage:** `<STAGE>`
- **Sub Stage:** `<SUB_STAGE>`
- **Page/Screen Name:** `<PAGE_NAME>`
- **Page Key:** `<PAGE_KEY, for example Page 0 or QDE_Basic Details>`
- **Starting URL or navigation path:** `<URL_OR_NAVIGATION_STEPS>`
- **User persona:** `<PERSONA, for example Sales Officer>`
- **Reference requirements Markdown:** `<REFERENCE_MD_PATH>`
- **Output requirements Markdown:** `<OUTPUT_MD_PATH>`
- **Target Excel workbook:** `<WORKBOOK_PATH>`
- **Fields worksheet:** `<FIELDS_SHEET_NAME>`
- **User Stories worksheet:** `<USER_STORIES_SHEET_NAME>`
- **Workbook update mode:** `<REPLACE_TARGET_PAGE_ROWS or APPEND>`
- **Applicability columns and rules:** `<EXACT_MAPPING_OR_NOT_APPLICABLE>`
- **Permission to submit/create test records:** `<YES or NO>`

Use the browser to inspect the live screen and use the repository code and Salesforce metadata to confirm the implementation. Do not rely on screenshots or source code alone.

### Mandatory clarification gate

Before changing any file, inspect the supplied paths and workbook structure. Ask focused questions and wait for my answer if any of the following is missing or ambiguous:

1. The exact Stage, Sub Stage, page, or starting navigation path.
2. Which existing Excel rows should be replaced versus retained.
3. The target worksheet names or starting row.
4. The meaning of product/applicability columns and the values to enter.
5. Whether you may submit the form or create test records.
6. Whether the live screen, deployed behavior, or repository should take precedence when they differ.

Never silently overwrite populated worksheet rows or invent an applicability mapping.

### 1. Inspect the reference files and workbook

1. Read the reference Markdown and follow its hierarchy, headings, table structure, terminology, and user-story format.
2. Inspect the target workbook before editing:
   - Sheet names.
   - Existing headers and merged cells.
   - Existing populated rows.
   - Column meanings.
   - Styles, widths, filters, frozen panes, and row formatting.
3. Preserve workbook formulas, merged headers, formatting, validations, and unrelated sheets.
4. Confirm whether the target rows are empty, should be replaced, or should be appended.

### 2. Inspect the live screen comprehensively

Start from a clean initial state and record:

- Screen title, Stage, Sub Stage, sections, tabs, and persona.
- Empty, populated, error, disabled, read-only, and submission states.
- Loading behavior only when it has a material business impact, such as preventing duplicate submission, protecting entered data, or blocking a required action.
- Every user-entered or user-selectable field.
- Field labels, control types, defaults, placeholders, help text, and visible error messages.
- Every dropdown, tile, radio button, checkbox, lookup, date, text, numeric, upload, and conditional field option.
- Requiredness, format rules, min/max values, length limits, and cross-field validations.
- Controlling fields and exact controlling expressions.
- Fields that appear, disappear, enable, disable, default, clear, or retain values after another selection changes.
- Button actions, reset/cancel behavior, save/create behavior, navigation, success behavior, and failure behavior.

Exercise every available choice and every meaningful dependency branch. For multi-level dependencies, test all valid routes, not only one example from each level.

After every interaction, inspect the current page state again. Do not reuse stale browser elements. Normalize displayed labels when comparing values so whitespace and line breaks do not create false differences.

Do not submit, save, create, delete, or modify a real record unless permission is explicitly set to YES. If submission is not permitted, inspect button gating and source logic without performing the mutation, and clearly state that successful submission was not exercised.

### 3. Inspect implementation and metadata

Locate and review all relevant:

- Lightning Web Components, Aura components, Flow definitions, Visualforce, or other UI code.
- JavaScript/controller event handlers and validation functions.
- Apex controllers, service classes, wrappers, and DML logic.
- Salesforce object and field metadata.
- Picklist values, dependent picklists, record types, custom labels, permissions, and navigation logic.
- Tests that reveal expected behavior.

Map each live field to its Salesforce object and API field where evidence exists. Do not invent an API mapping. Mark an unresolved mapping as `TBD` and add a clarifying question.

Use API names only in the field table’s Object column or in internal implementation evidence where necessary. Do not include object names, API field names, class names, component names, event names, record IDs, or storage implementation details in client-facing user stories.

Never hardcode a test application number, applicant number, Salesforce record ID, or other environment-specific identifier in the requirements or user stories. Refer to the record generically, such as “a newly created Commercial Vehicle application.”

Treat the live screen as authoritative for observed labels, values, visibility, defaults, and interaction behavior unless I specify otherwise. Treat code and metadata as authoritative for persistence and backend processing where they align with the deployed screen.

Document every material discrepancy between the live screen, repository, metadata, and reference document. Do not silently choose one implementation or rewrite the requirement to hide the difference.

### 4. Build the field details table

Use exactly these columns unless the workbook has an explicitly approved different schema:

| Field Name | Object | Field Type | Drop down values | Display Stage | Display Sub Stage | Display Section | Validation | Error Message | Controlling field | Controlling Expression |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

The field table must contain only user-entered or user-selectable data fields on this screen, including conditionally displayed input fields.

Include:

- Text, number, currency, percentage, date, picklist, radio, checkbox, lookup, upload, and other editable controls.
- Exact selectable values and stored codes when known.
- Defaults only when they apply to an editable field.
- Field-level and cross-field validation.
- Visibility and dependency logic.

Do not include:

- Buttons or actions such as Create, Save, Next, Back, Reset, Cancel, Add, Delete, or Upload action controls.
- Tabs, accordions, section headers, cards, status indicators, progress indicators, or navigation elements.
- Loading messages, page errors, success messages, or button enabled/disabled states.
- System-generated identifiers, names, dates, stages, sub-stages, record links, or audit fields.
- Derived, calculated, mirrored, auto-populated, or read-only display-only values.
- Backend-created records such as Application, Applicant, Line Item, Asset, or related records.

Capture those excluded behaviors in the user stories instead.

### 5. Build the user stories

Create an Epic and Feature followed by atomic user stories. Give each story a stable ID using this pattern:

`US-<PAGE_KEY>-<3-digit sequence>`

For each story include:

- Title.
- User Story Description in “As a…, I want…, so that…” format.
- Acceptance Criteria organized into clearly labelled scenarios where applicable:
  - Positive Scenario.
  - Negative Scenario.
  - Validation Scenario.
  - Edge Case Scenario.
  - Integration Scenario.
  - Persistence or Review Scenario.
- Assumptions.
- Integrations.
- In Scope.

Do not add an Out of Scope section to user stories.

Write acceptance criteria entirely in functional business language. Describe what the user enters, sees, validates, saves, verifies, or navigates to. For persistence, state that saved values are retained and displayed when revisited; do not describe internal objects, fields, records, DML, handlers, or event names.

For every integration that is relevant to a story:

- Name the business integration or service.
- Describe what triggers it.
- Describe the expected successful result.
- Describe failure behavior and whether progression is blocked.
- Include retry, resend, timeout, expiry, or skip-path behavior where applicable.

User stories must cover more than editable fields. Include all applicable:

- Empty and error states when they affect the business journey.
- Conditional display and dependency resets.
- Defaults and retained/cleared values.
- Validation and exact errors.
- Button gating and duplicate-submit prevention.
- Save/Create/Next/Back/Reset/Cancel actions.
- Permission failures and transaction rollback.
- System-created or system-derived records and values.
- Post-save navigation and stage/sub-stage transitions.
- Read-only and system-generated information excluded from the field table.

Do not create a generic user story only for screen loading, component initialization, or a specific test record. Include loading behavior within the relevant functional story only when it materially affects the user or transaction.

Avoid duplicating identical acceptance criteria across stories unless the behavior genuinely applies independently.

### 6. Create the requirements Markdown

Follow the reference Markdown structure and include at minimum:

1. Source Basis.
2. Source Interpretation.
3. Live Interaction Coverage.
4. Excel Field Details Table.
5. Validation/dependency matrix where useful.
6. Agile Requirements Hierarchy.
7. User Stories.
8. Implementation Discrepancies Requiring Resolution.
9. Clarifying Questions.

Clearly distinguish:

- Behavior exercised in the browser.
- Behavior inferred from code or metadata.
- Behavior not tested because submission permission was not granted.

### 7. Populate the Excel workbook

Only edit the approved worksheets and rows.

For the Fields worksheet:

- Copy the final field table exactly.
- Do not add actions, tabs, loading states, system-generated fields, derived values, or backend records.
- Preserve the existing header and column order.

For the User Stories worksheet:

- Map IDs, titles, descriptions, acceptance criteria, stage, persona, assumptions, dependencies, feedback, and applicability to the existing columns.
- Keep acceptance criteria complete and readable using line breaks within cells.
- In the Acceptance Criteria cell, include the labelled Scenarios, Assumptions, Integrations, and In Scope sections so the complete sign-off requirement is visible in one place.
- If the worksheet has dedicated Assumptions or Dependencies/Integrations columns, populate those columns as well.
- Do not add or populate an Out of Scope section.
- Leave Sprint, Signoff Status, Feedback, or other governance columns blank unless a value is supplied or explicitly approved.
- Populate applicability only from the approved mapping. Do not infer product applicability from the workbook name.

Preserve all unrelated workbook content and save to the requested path. Do not create a second workbook unless requested.

### 8. Final verification

Before reporting completion, verify:

- Every visible editable field is in the field table exactly once.
- No action, tab, status, loading message, derived value, system-generated field, or backend record appears in the field table.
- Every dropdown/selectable value was exercised or explicitly identified as untested.
- Every dependency branch, default, reset, validation, and navigation path is covered.
- All user stories from the Markdown were copied into Excel.
- Every user story contains applicable labelled scenarios plus Assumptions, Integrations, and In Scope.
- No user story contains an Out of Scope section.
- No user story contains API field names, Salesforce object names, class/component names, event names, internal persistence details, or environment-specific record identifiers.
- No standalone story exists only for generic screen loading or component initialization.
- Every applicable integration has trigger, success, failure/gating, and retry or skip behavior documented.
- Field and story counts match between Markdown and Excel.
- Worksheet names, headers, merged cells, formulas, styles, and unrelated sheets remain intact.
- The workbook reopens successfully after saving.
- Discrepancies and unresolved mappings are documented rather than guessed.

Finish with a concise summary containing:

- Output files updated.
- Number of fields and user stories written.
- Browser paths and branches tested.
- Any submission paths not exercised.
- Any discrepancies, assumptions, or questions still requiring a decision.

---
