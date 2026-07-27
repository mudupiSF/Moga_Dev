# Application Creation Requirements

## Source Basis

- Live Salesforce Create Application page reviewed on 10 July 2026 from the Applications list.
- Every visible Primary Product, Vehicle Type, Vehicle Sub Category, Segment, and Sub Product option was selected during the live review.
- Reset Selection and Cancel behavior were exercised; Create was not submitted, so no test application was created.
- Salesforce LOS source under `force-app/main/default`, including `createApplication` and `CreateApplicationController`.
- Field metadata for `Application__c.Product__c`, `Application_Line_Item__c.Sub_Product__c`, `Asset__c.Vehicle_type__c`, `Asset__c.Vehicle_SubCategory__c`, and `Asset__c.Product_Segment__c`.
- Structure and formatting reference from `Commercial_Vehicle_QDE_Requirements_V2.md`.

### Source Interpretation

- The live page is treated as authoritative for visible labels, available choices, default selections, conditional display, and Create-button gating.
- The reviewed local source and metadata are treated as authoritative for object/API mapping and implemented record creation where the deployed page and local source agree.
- The live page renders selectable cards rather than conventional dropdowns. Values are nevertheless listed in the `Drop down values` column to match the supplied field-mapping format.
- Product and Sub Product choices are metadata-driven. Vehicle Type, Vehicle Sub Category, and Two Wheeler Segment behavior are presented as configured UI rules.
- The live page and reviewed local source are not fully aligned. Differences affecting Vehicle Sub Category capture and validation are documented under Implementation Discrepancies.

## Live Interaction Coverage

- **Initial state:** No product is selected; only Primary Product is displayed; Create is disabled.
- **Personal Loan:** Balance Transfer and Top Up were each selected. Either selection enables Create.
- **Two Wheeler / New:** Motorcycle, Scooter, Moped, E-Scooter, Hi-Street, and Hi-End were each selected. Every Segment enables Create.
- **Two Wheeler / Refinance:** Top-up (on External Loan) and Top-up (on Internal Loan) were each selected. Either Vehicle Sub Category enables Create.
- **Four Wheeler / New:** Vehicle Type and Vehicle Sub Category default to New. Create is enabled without another selection.
- **Four Wheeler / Refinance:** Both Top-up Vehicle Sub Categories were selected. Either selection enables Create.
- **Four Wheeler / Used:** New Loan, BT External, BT External and Top-up, and BT Internal Vehicle Sub Categories were each selected. Each selection enables Create.
- **Commercial Vehicles / New:** LCV, SCV, MHCV, and CE were each selected. Each Sub Product enables Create.
- **Commercial Vehicles / Refinance:** Both Top-up Vehicle Sub Categories were selected; a CV Sub Product is also required.
- **Commercial Vehicles / Used:** All four Used Vehicle Sub Categories were selected; a CV Sub Product is also required.
- **State changes:** Product changes clear all dependent selections. Vehicle Type changes clear Vehicle Sub Category. A Two Wheeler Segment is cleared when leaving New. A selected CV Sub Product remains selected when Vehicle Type changes within CV.
- **Reset:** Clears the entire form, hides dependent sections, and disables Create.
- **Cancel:** Returns to the Applications Recently Viewed list.

## Excel Field Details Table

The table below contains only user-facing data-entry fields and follows the same headers as `Field Details.xlsx`. Actions, navigation, loading states, and system-created record details are covered in the User Stories.

| Field Name | Object | Field Type | Drop down values | Display Stage | Display Sub Stage | Display Section | Validation | Error Message | Controlling field | Controlling Expression |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Primary Product | `Application__c.Product__c` | Picklist presented as product tiles | Personal Loan (`PL`); Two Wheeler (`2W`); Four Wheeler (`4W`); Commercial Vehicles (`CV`) | Pre-QDE | Create Application | Select Primary Product | Required. No default. Selecting a product clears all prior dependent selections. | Please complete all required selections to continue. |  | Selection determines whether Vehicle Type, Vehicle Sub Category, Segment, and/or Sub Product are displayed. |
| Vehicle Type | `Asset__c.Vehicle_type__c` | Text presented as single-select cards | 2W: New; Refinance. 4W/CV: New; Refinance; Used. | Pre-QDE | Create Application | Vehicle Type | Required for 2W, 4W, and CV. Defaults to New when a vehicle product is selected. Not displayed for PL. Changing Vehicle Type clears the prior Vehicle Sub Category; leaving 2W New also clears Segment. | Please complete all required selections to continue. | Primary Product | PL → hidden; 2W → New or Refinance; 4W/CV → New, Refinance, or Used. |
| Vehicle Sub Category | `Asset__c.Vehicle_SubCategory__c` | Picklist presented as single-select cards | New; Top-up (on External Loan); Top-up (on Internal Loan); New Loan (Change of Owner); BT External (Change / No Change of Owner); BT External and Top-up (Change / No Change of Owner); BT Internal (Change of Owner) | Pre-QDE | Create Application | Vehicle Sub Category | Required for every vehicle product. Defaults to New when Vehicle Type = New. No default for Refinance or Used. | Please complete all required selections to continue. | Vehicle Type | New → New; Refinance → two Top-up options; Used → four New Loan/BT options. Used is available only for 4W and CV. |
| Segment | `Asset__c.Product_Segment__c` | Text presented as single-select cards | Motorcycle (`MOTORCYC`); Scooter (`SCOOTER`); Moped (`MOPEDS`); E-Scooter (`ESCOOTER`); Hi-Street (`HISTREET`); Hi-End (`HIENDBIKE`) | Pre-QDE | Create Application | Segment | Required only for 2W with Vehicle Type = New. No default. Hidden and cleared for 2W Refinance and all other products. | Please complete all required selections to continue. | Primary Product + Vehicle Type | Displayed only when Primary Product = 2W and Vehicle Type = New. |
| Sub Product | `Application_Line_Item__c.Sub_Product__c` | Dependent picklist presented as single-select cards | PL: Balance Transfer; Top Up. CV: Light Commercial Vehicles (`LCV`); Small Commercial Vehicles (`SCV`); Medium & Heavy Commercial Vehicles (`MHCV`); Construction Equipments (`CE`) | Pre-QDE | Create Application | Sub Product | Required whenever the selected product has configured dependent Sub Product values. No default. Not displayed for 2W or 4W. A selected CV Sub Product persists when Vehicle Type changes within CV. | Please complete all required selections to continue. | Primary Product | PL → Balance Transfer or Top Up; CV → LCV, SCV, MHCV, or CE; 2W/4W → hidden. |

## Product Validation Matrix

- **PL**
  - Required: Primary Product + Sub Product.
  - Valid combinations: PL + Balance Transfer; PL + Top Up.
  - Vehicle Type, Vehicle Sub Category, and Segment are hidden.
- **2W / New**
  - Vehicle Type defaults to New.
  - Vehicle Sub Category defaults to New.
  - Required: one Segment from Motorcycle, Scooter, Moped, E-Scooter, Hi-Street, or Hi-End.
- **2W / Refinance**
  - Required: one Vehicle Sub Category from Top-up (on External Loan) or Top-up (on Internal Loan).
  - Segment is hidden and cleared.
- **4W / New**
  - Vehicle Type defaults to New and Vehicle Sub Category defaults to New.
  - The defaulted route is immediately valid.
- **4W / Refinance**
  - Required: one of the two Top-up Vehicle Sub Categories.
- **4W / Used**
  - Required: one of New Loan (Change of Owner), BT External, BT External and Top-up, or BT Internal.
- **CV / New**
  - Vehicle Type and Vehicle Sub Category default to New.
  - Required: one CV Sub Product from LCV, SCV, MHCV, or CE.
- **CV / Refinance**
  - Required: one Top-up Vehicle Sub Category + one CV Sub Product.
- **CV / Used**
  - Required: one Used Vehicle Sub Category + one CV Sub Product.

## Agile Requirements Hierarchy

### Epic: Application Creation

Enable a Sales Officer to create a correctly initialized loan application by selecting an eligible product configuration, validating all product-specific dependencies, creating the required Salesforce records, and opening the new application at QDE Basic Details.

### Feature: Product-Driven Create Application Page

Provide a guided Create Application page that loads active Product and dependent Sub Product configuration, applies vehicle-specific rules, prevents incomplete submissions, and creates the Application, Borrower, Application Line Item, and initial Asset records needed to begin QDE.

## User Stories

### US-APP-CREATE-001: Load the Create Application Page

**User Story Description:** As a Sales Officer, I want the Create Application page to load the active product catalog and dependent options so that I can begin from valid configuration data.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given the user opens New from the Applications list
  - When form options load successfully
  - Then the system displays Personal Loan, Two Wheeler, Four Wheeler, and Commercial Vehicles as Primary Product tiles
- **Positive Scenario**
  - Given the form options are loading
  - When the request is in progress
  - Then the system displays “Loading product catalog...” and does not allow submission
- **Negative Scenario**
  - Given product setup data cannot be loaded
  - When the page finishes the failed request
  - Then the system displays an actionable error and does not expose a usable Create action
- **Edge Case Scenario**
  - Given a Product or Sub Product value is inactive
  - When options are loaded
  - Then the inactive value is not displayed
- **Field Mapping Scenario**
  - Given the page renders successfully
  - When Primary Product and dependent options are displayed
  - Then their labels and stored values match the Excel Field Details Table

**Assumptions:**

- Active Product values are sourced from `Application__c.Product__c`.
- PL and CV Sub Product options are sourced from the `Application_Line_Item__c.Product__c` to `Sub_Product__c` field dependency.

**Integrations:**

- Internal Apex form-options service only; no external API.

**In Scope:**

- Loading state.
- Active Product and dependent Sub Product retrieval.
- Load-error presentation.

**Out of Scope:**

- Product catalog administration.
- Creating new Product or Sub Product values from this page.

### US-APP-CREATE-002: Select a Primary Product and Reset Dependent State

**User Story Description:** As a Sales Officer, I want the form to adapt to the selected Primary Product so that I see only the fields required for that product.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given no product is selected
  - When the user selects a Primary Product
  - Then the selected tile is visually marked and the applicable dependent sections appear
- **Positive Scenario**
  - Given a product and dependent values are already selected
  - When the user selects another Primary Product
  - Then the system clears Vehicle Type, Vehicle Sub Category, Segment, and Sub Product values from the prior product before applying the new product defaults
- **Negative Scenario**
  - Given no Primary Product is selected
  - When the page is in its initial state
  - Then Create remains disabled
- **Edge Case Scenario**
  - Given the user selects the currently selected Product tile again
  - When product rules are reapplied
  - Then dependent selections are reset and only the new defaults remain
- **Field Mapping Scenario**
  - Given a product is selected
  - When dependent fields render
  - Then the displayed fields match the Excel Field Details Table for that product

**Assumptions:**

- Exactly one Primary Product may be selected.
- Customer Type is captured later in QDE Basic Details and is not part of this page.

**Integrations:**

- None.

**In Scope:**

- Product-tile selection.
- Product-specific section visibility.
- Clearing stale dependent values.

**Out of Scope:**

- Multi-product applications.
- Changing Primary Product from this page after application creation.

### US-APP-CREATE-003: Configure a Personal Loan Application

**User Story Description:** As a Sales Officer, I want to select the applicable Personal Loan Sub Product so that the created line item represents the intended PL transaction.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given Primary Product = PL
  - When the product is selected
  - Then the page displays Sub Product values Balance Transfer and Top Up
- **Positive Scenario**
  - Given Primary Product = PL
  - When the user selects either Balance Transfer or Top Up
  - Then Create becomes enabled
- **Negative Scenario**
  - Given Primary Product = PL and no Sub Product is selected
  - When validation is evaluated
  - Then Create remains disabled
- **Edge Case Scenario**
  - Given a PL Sub Product is selected
  - When the user changes to a vehicle product
  - Then the PL Sub Product is cleared
- **Field Mapping Scenario**
  - Given a PL application is created
  - When the Application Line Item is persisted
  - Then `Sub_Product__c` stores the selected PL value

**Assumptions:**

- PL does not create an initial Asset.
- PL has no Vehicle Type, Vehicle Sub Category, or Segment on this page.

**Integrations:**

- None.

**In Scope:**

- Balance Transfer and Top Up selection.
- PL submission gating.

**Out of Scope:**

- PL loan amount and borrower details.
- PL balance-transfer account validation.

### US-APP-CREATE-004: Configure a Two Wheeler Application

**User Story Description:** As a Sales Officer, I want the Two Wheeler route to distinguish New and Refinance transactions so that the correct Segment or Vehicle Sub Category is captured.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given Primary Product = 2W
  - When the product is selected
  - Then Vehicle Type defaults to New and Vehicle Sub Category defaults to New
- **Positive Scenario**
  - Given 2W Vehicle Type = New
  - When the user selects any configured Segment
  - Then Create becomes enabled and the internal Segment code is retained for persistence
- **Positive Scenario**
  - Given 2W Vehicle Type = Refinance
  - When the user selects either Top-up Vehicle Sub Category
  - Then Create becomes enabled without requiring Segment
- **Negative Scenario**
  - Given 2W Vehicle Type = New and no Segment is selected
  - When validation is evaluated
  - Then Create remains disabled
- **Negative Scenario**
  - Given 2W Vehicle Type = Refinance and no Vehicle Sub Category is selected
  - When validation is evaluated
  - Then Create remains disabled
- **Edge Case Scenario**
  - Given a Segment is selected for 2W New
  - When Vehicle Type changes to Refinance
  - Then Segment is hidden and cleared
- **Edge Case Scenario**
  - Given the user returns from Refinance to New
  - When New is selected again
  - Then Vehicle Sub Category defaults to New but Segment must be selected again
- **Field Mapping Scenario**
  - Given a 2W application is created
  - When the Asset is persisted
  - Then Vehicle Type, Vehicle Sub Category, and Product Segment match the selected route

**Assumptions:**

- Used is not an available Two Wheeler Vehicle Type.
- Segment is applicable only to 2W New.

**Integrations:**

- None.

**In Scope:**

- New and Refinance routing.
- Six New Segment values.
- Two Refinance Vehicle Sub Categories.

**Out of Scope:**

- Vehicle make, model, dealer, and quotation capture.
- Used Two Wheeler transactions.

### US-APP-CREATE-005: Configure a Four Wheeler Application

**User Story Description:** As a Sales Officer, I want to select New, Refinance, or Used Four Wheeler configuration so that the transaction category is established before QDE.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given Primary Product = 4W
  - When the product is selected
  - Then Vehicle Type and Vehicle Sub Category default to New and Create is enabled
- **Positive Scenario**
  - Given 4W Vehicle Type = Refinance
  - When either Top-up Vehicle Sub Category is selected
  - Then Create becomes enabled
- **Positive Scenario**
  - Given 4W Vehicle Type = Used
  - When one of the four Used Vehicle Sub Categories is selected
  - Then Create becomes enabled
- **Negative Scenario**
  - Given 4W Vehicle Type = Refinance or Used and no Vehicle Sub Category is selected
  - When validation is evaluated
  - Then Create remains disabled
- **Edge Case Scenario**
  - Given a Refinance or Used Vehicle Sub Category is selected
  - When Vehicle Type changes
  - Then the prior Vehicle Sub Category is cleared and only choices valid for the new Vehicle Type are displayed
- **Field Mapping Scenario**
  - Given a 4W application is created
  - When the initial Asset is persisted
  - Then Vehicle Type and Vehicle Sub Category match the selected route

**Assumptions:**

- Four Wheeler does not require Segment or Sub Product on this page.
- The default 4W New route may be submitted without an additional click.

**Integrations:**

- None.

**In Scope:**

- New, Refinance, and Used Vehicle Types.
- Vehicle Sub Category dependency and defaulting.

**Out of Scope:**

- Vehicle valuation and asset inspection.
- Dealer and quotation capture.

### US-APP-CREATE-006: Configure a Commercial Vehicle Application

**User Story Description:** As a Sales Officer, I want to select the Commercial Vehicle transaction category and Sub Product so that the application is initialized for the correct CV business line.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given Primary Product = CV
  - When the product is selected
  - Then Vehicle Type and Vehicle Sub Category default to New and the page displays LCV, SCV, MHCV, and CE Sub Products
- **Positive Scenario**
  - Given CV Vehicle Type = New
  - When one CV Sub Product is selected
  - Then Create becomes enabled
- **Positive Scenario**
  - Given CV Vehicle Type = Refinance or Used
  - When one valid Vehicle Sub Category and one CV Sub Product are selected
  - Then Create becomes enabled
- **Negative Scenario**
  - Given no CV Sub Product is selected
  - When validation is evaluated for any CV Vehicle Type
  - Then Create remains disabled
- **Negative Scenario**
  - Given CV Vehicle Type = Refinance or Used and no Vehicle Sub Category is selected
  - When validation is evaluated
  - Then Create remains disabled even if a Sub Product is selected
- **Edge Case Scenario**
  - Given a CV Sub Product is selected
  - When Vehicle Type changes within CV
  - Then the Sub Product remains selected but the prior Vehicle Sub Category is cleared
- **Edge Case Scenario**
  - Given a CV Sub Product is selected
  - When Primary Product changes away from CV
  - Then the CV Sub Product is cleared
- **Field Mapping Scenario**
  - Given a CV application is created
  - When the records are persisted
  - Then `Application__c.Product__c = CV`, the line item stores LCV/SCV/MHCV/CE, and the initial Asset stores the vehicle selections

**Assumptions:**

- One CV Sub Product is mandatory for every CV Vehicle Type.
- CV Sub Product is independent of Vehicle Type and therefore remains selected across CV Vehicle Type changes.

**Integrations:**

- None.

**In Scope:**

- New, Refinance, and Used CV transactions.
- LCV, SCV, MHCV, and CE.
- Combined Vehicle Sub Category and Sub Product validation.

**Out of Scope:**

- Number of vehicles.
- Fleet-level asset capture.
- CV asset details beyond the initial classification.

### US-APP-CREATE-007: Gate Create and Prevent Duplicate Submission

**User Story Description:** As a Sales Officer, I want Create to be enabled only for a complete valid configuration so that incomplete or duplicate applications are not submitted.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given all required selections for the active route are complete
  - When validation is evaluated
  - Then Create is enabled
- **Positive Scenario**
  - Given the user clicks Create on a valid route
  - When submission begins
  - Then the action displays “Creating...”, Create is disabled, and Cancel is disabled until the request completes
- **Negative Scenario**
  - Given any required selection is missing
  - When validation is evaluated
  - Then Create remains disabled
- **Negative Scenario**
  - Given validation is invoked on an incomplete configuration
  - When submission is attempted
  - Then the system blocks the request and displays “Please complete all required selections to continue.”
- **Edge Case Scenario**
  - Given Create has already been clicked
  - When the user attempts another click before completion
  - Then a second request is not submitted
- **Field Mapping Scenario**
  - Given the Create state changes
  - When the selected route changes
  - Then requiredness follows the Product Validation Matrix

**Assumptions:**

- Client-side button gating is supplemented by server-side validation of supplied values.
- A user cannot bypass required selection checks through supported UI interaction.

**Integrations:**

- Internal Apex Create action only.

**In Scope:**

- Route-specific requiredness.
- Disabled, enabled, and submitting action states.
- Duplicate-click prevention.

**Out of Scope:**

- Cross-application duplicate-customer detection.
- Idempotency across separate browser sessions.

### US-APP-CREATE-008: Create the Initial Application Record Graph

**User Story Description:** As a Sales Officer, I want a valid submission to create all required initial records so that QDE Basic Details can begin without manual setup.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given a valid product configuration
  - When Create succeeds
  - Then the system creates one Application at Stage = QDE and Sub Stage = Basic Details
- **Positive Scenario**
  - Given the Application is created
  - When dependent records are initialized
  - Then the system creates one Borrower and one Application Line Item linked to the Application
- **Positive Scenario**
  - Given the selected product is 2W, 4W, or CV
  - When creation succeeds
  - Then the system also creates one initial Asset linked to the Borrower and Application Line Item
- **Positive Scenario**
  - Given the selected product is PL
  - When creation succeeds
  - Then no initial Asset is created
- **Negative Scenario**
  - Given the user lacks Application creation permission
  - When Create is submitted
  - Then the request fails with “You do not have permission to create Applications.”
- **Negative Scenario**
  - Given any record insert fails
  - When the transaction is rolled back
  - Then no partial Application graph remains and the error is displayed
- **Edge Case Scenario**
  - Given an optional value does not apply to the selected route
  - When records are created
  - Then the non-applicable field is left blank rather than populated with stale data
- **Field Mapping Scenario**
  - Given creation succeeds
  - When the record graph is reviewed
  - Then every persisted value matches the Excel Field Details Table

**Assumptions:**

- All dependent inserts execute in one Salesforce transaction.
- Downstream naming automation may replace the initial `TempName`.
- One initial Borrower and one primary Application Line Item are sufficient to start QDE.

**Integrations:**

- Internal Salesforce Apex and DML only; no external API.

**In Scope:**

- Application, Borrower, Application Line Item, and initial Asset creation.
- Initial Stage/Sub Stage assignment.
- Transaction rollback on failure.

**Out of Scope:**

- QDE field capture after the record opens.
- Additional applicant creation.
- External dedupe or eligibility checks.

### US-APP-CREATE-009: Open the Created Application

**User Story Description:** As a Sales Officer, I want successful creation to open the new application so that I can immediately continue with QDE Basic Details.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given record creation succeeds
  - When the server returns the Application Id
  - Then the system navigates to the new `Application__c` record page
- **Positive Scenario**
  - Given the record opens
  - When the stage framework loads
  - Then QDE Basic Details is the active starting point
- **Negative Scenario**
  - Given creation fails
  - When an error is returned
  - Then the user remains on Create Application and the failed record is not opened
- **Edge Case Scenario**
  - Given the normal record-navigation event is unavailable
  - When a supported fallback navigation path exists
  - Then the system opens the created record through that fallback
- **Field Mapping Scenario**
  - Given the created record opens
  - When Application Overview is displayed
  - Then Product, Stage, and Sub Stage reflect the submitted configuration

**Assumptions:**

- The user has read access to the created Application.
- The Application record page contains the configured QDE stage framework.

**Integrations:**

- Salesforce navigation only.

**In Scope:**

- Post-create navigation.
- Failed-create stay-on-page behavior.

**Out of Scope:**

- QDE completion.
- Returning to the Create page after QDE starts.

### US-APP-CREATE-010: Reset or Cancel Application Creation

**User Story Description:** As a Sales Officer, I want to reset an in-progress selection or cancel creation so that I can recover from an incorrect route without creating records.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given one or more selections exist
  - When the user clicks Reset Selection
  - Then all selections and errors are cleared, dependent sections are hidden, and Create is disabled
- **Positive Scenario**
  - Given the form is idle
  - When the user clicks Cancel
  - Then the system returns to Applications Recently Viewed
- **Negative Scenario**
  - Given submission is in progress
  - When the action state is evaluated
  - Then Cancel is disabled to avoid leaving during an active create request
- **Edge Case Scenario**
  - Given values from several dependency levels are selected
  - When Reset Selection is clicked
  - Then no hidden value remains available for a later submission
- **Field Mapping Scenario**
  - Given Reset completes
  - When the form is inspected
  - Then every field in the Excel Field Details Table is blank or hidden as defined for the initial state

**Assumptions:**

- Reset and Cancel do not save draft data.
- Cancel does not require a confirmation because no record exists before Create succeeds.

**Integrations:**

- None.

**In Scope:**

- Full reset.
- Cancel navigation.
- Submission-state navigation lock.

**Out of Scope:**

- Draft recovery after browser closure.
- Unsaved-change confirmation.

## Implementation Discrepancies Requiring Resolution

1. **Vehicle Sub Category UI missing from local LWC:** The live page displays Vehicle Sub Category for 2W, 4W, and CV, but the reviewed local `createApplication` LWC contains no Vehicle Sub Category state, section, event handler, or submit parameter.
2. **Vehicle Sub Category not persisted by local Apex:** `CreateApplicationController.createApplication` accepts Product, Sub Product, Vehicle Type, and Segment only. It does not accept or assign `Asset__c.Vehicle_SubCategory__c`, even though the live page requires that value for Refinance and Used routes.
3. **2W Refinance validation mismatch:** The reviewed local LWC treats 2W Refinance as valid once Vehicle Type is selected. The live page keeps Create disabled until one of the two Refinance Vehicle Sub Categories is selected.
4. **Deployed and repository versions differ:** The live page includes New/Refinance/Used dependency behavior not fully represented in the reviewed local component. Deployment source must be reconciled before implementation sign-off.
5. **Initial Application Name:** The reviewed controller inserts `Application__c.Name = TempName`. Existing records suggest later naming automation may replace it, but the responsible automation and failure behavior are not defined in this requirement.
6. **Primary Borrower flag:** The reviewed controller explicitly sets `Applicant__c.Is_Primary__c = true` only for PL. The required primary-flag behavior for 2W, 4W, and CV initial Borrowers must be confirmed.
7. **Server-side value validation:** The client restricts choices, but the reviewed Apex method does not independently validate the submitted Product/Vehicle Type/Segment combination before DML.

## Clarifying Questions

1. Should `Asset__c.Vehicle_SubCategory__c` be mandatory and persisted for every vehicle application, including the default New route?
2. Is Four Wheeler New intentionally valid immediately from defaults, or must the Sales Officer explicitly confirm New?
3. Should CV Sub Product remain selected when Vehicle Type changes, as observed live, or should all downstream selections be cleared?
4. What automation replaces `Application__c.Name = TempName`, and what should happen if final naming fails?
5. Should the initial Borrower be marked Primary for every product rather than only PL?
6. Are additional PL Sub Products such as OD intentionally excluded by the current Product/Sub Product dependency?
7. Should Create Application support Number of Vehicles for CV, or is that field intentionally deferred to QDE/DDE?
