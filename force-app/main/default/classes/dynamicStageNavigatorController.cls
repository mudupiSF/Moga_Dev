/**
 * @description  Builds the hierarchical navigation menu for a given portfolio + application.
 *               Returns a NavigationPanelState (inner class defined below) that is structurally
 *               identical to SFLOS_DynamicStageNavigator.NavigationPanelState, so the LWC trio
 *               stageMenu / stageMenuItems / stageMenuItem can consume it without any changes.
 *
 *               All inner classes are self-contained here – no dependency on
 *               SFLOS_DynamicStageNavigator.
 *
 * Data source:  Dynamic_Stage_Gate__mdt  (Custom Metadata Type)
 *
 * Menu structure produced
 * ─────────────────────────────────────────────────────────────────────────────
 * Each metadata record becomes one NavigationMenuItem:
 *   • groupName  = Main_Stage_Name__c   → LWC groups items into a collapsible section
 *   • tab/label  = Steps_Sub_Menu_Name__c
 *   • ordering   = Current_Main_Stage_Order__c ASC, then Current_Step_Order__c ASC
 *
 * For steps where is_Current_Step_Applicant_based__c = true, the item has no
 * currentView itself; instead a child NavigationMenuItem is created for each
 * active Applicant__c in order: Borrower → CoBo1..3 → G1..3 → B1..10.
 * When 2+ applicants of the same type exist at this step they are collapsed
 * into a single Multi-Grid (isGroupItem = true) entry.
 *
 * Status per item (compared against app's current Stage__c + Sub_Stage__c):
 *   completed  – item comes before the current step
 *   active     – item IS the current step (currentView = true)
 *   disabled   – item comes after the current step
 *
 * Product-type filtering
 *   Wheels:      include when is_Current_Stage_common_for_Wheels__c = true
 *                OR Product_Type__c matches app.Sub_Product__c
 *   All others:  include when Product_Type__c is blank
 *                OR Product_Type__c matches app.Sub_Product__c
 *
 * Parallel steps (is_Current_Step_Parallel__c = true) are excluded from the
 * navigation menu – they are background/waiting steps.
 */
public with sharing class dynamicStageNavigatorController {

    // ── Status constants (must match the values the LWC checks) ──────────────
    private static final String STATUS_COMPLETED = 'completed';
    private static final String STATUS_ACTIVE    = 'active';
    private static final String STATUS_DISABLED  = 'disabled';
    private static final String MAIN_STAGE_QDE   = 'QDE';
    private static final String STEP_BASIC_DETAILS = 'Basic Details';
    private static final String STEP_KYC_DETAILS = 'KYC Details';
    private static final String STEP_OCCUPATION_DETAILS = 'Occupation Details';
    private static final String STEP_DEDUPE_AND_ELIGIBILITY = 'Dedupe and Eligibility';
    private static final String TYPE_NON_INDIVIDUAL = 'Non-Individual';

    // =========================================================================
    // Inner classes
    // =========================================================================

    public class NavigationPanelState {
        @AuraEnabled public Boolean                  isSuccess;
        @AuraEnabled public String                   message;
        @AuraEnabled public String                   currentStagePhrase;
        @AuraEnabled public List<NavigationMenuItem> menuItems;
        @AuraEnabled public String                   preferredApplicantTabLabel;
        @AuraEnabled public Id                       preferredApplicantId;
        @AuraEnabled public String                   preferredApplicantName;
        /** Step to open for preferred applicant without resetting menu status (Customer Dedupe). */
        @AuraEnabled public String                   preferredViewStepName;
        /** Main stage for preferredViewStepName — disambiguates duplicate step names (PSS vs Operations). */
        @AuraEnabled public String                   preferredViewMainStageName;

        public NavigationPanelState() {
            this.isSuccess          = false;
            this.message            = '';
            this.currentStagePhrase = '';
            this.menuItems          = new List<NavigationMenuItem>();
        }
    }

    public class NavigationMenuItem {
        @AuraEnabled public String                   id;
        @AuraEnabled public String                   label;
        @AuraEnabled public String                   tab;
        @AuraEnabled public String                   status;
        @AuraEnabled public String                   stagePhrase;
        @AuraEnabled public Boolean                  hasApplicantSubstage;
        @AuraEnabled public List<NavigationMenuItem> subItems;
        @AuraEnabled public String                   applicantType;
        @AuraEnabled public Id                       applicantId;
        @AuraEnabled public Boolean                  currentView;
        @AuraEnabled public String                   groupName;
        @AuraEnabled public Boolean                  isGroupItem;
        @AuraEnabled public List<ApplicantInfo>      applicants;
        /** LWC component name to render when this stage is selected (Override_LWC__c). */
        @AuraEnabled public String                   overrideLwc;
        /** SUB toggle : present on a single-NI role sub-item to add IN sub-applicants. */
        @AuraEnabled public Boolean                  showSubToggle;
        @AuraEnabled public Boolean                  subToggleEnabled;
        @AuraEnabled public Id                       subParentApplicantId;
        /** When a sub of this role is mid-edit, the toggle jumps straight to it instead of adding. */
        @AuraEnabled public Boolean                  subInProgress;
        @AuraEnabled public Id                       subInProgressId;
        @AuraEnabled public String                   subInProgressTabLabel;
        /** Clean step phrase (Step_MainStage) used to build the sub-applicant drill-down phrase. */
        @AuraEnabled public String                   subBaseStagePhrase;
        /** Single-in-progress lock: disables the grid "+" add-sub tile while a journey is open. */
        @AuraEnabled public Boolean                  subCreationLocked;

        public NavigationMenuItem() {
            this.subItems    = new List<NavigationMenuItem>();
            this.currentView = false;
            this.showSubToggle = false;
            this.subToggleEnabled = false;
        }
    }

    public class ApplicantInfo {
        @AuraEnabled public Id      applicantId;
        @AuraEnabled public String  tabLabel;
        @AuraEnabled public String  applicantName;
        @AuraEnabled public String  customerType;
        @AuraEnabled public String  loanStages;
        @AuraEnabled public String  currentLoanStageComplete;
        @AuraEnabled public Boolean inActiveApplicant;
        /**
         * Per-applicant menu status for this step (completed | active | disabled).
         * Populated only on Multi-Grid group rows; uses computeApplicantSubItemStatus.
         */
        @AuraEnabled public String stepMenuStatus;
        /** Nested Individual sub-applicants under a Non-Individual top-level tile. */
        @AuraEnabled public Boolean hasSubApplicants;
        @AuraEnabled public List<ApplicantInfo> subApplicants;
        /** True when this applicant is itself an IN sub-applicant of an NI parent. */
        @AuraEnabled public Boolean isSubApplicant;
        // primary picker (effective flags computed per role in applyPrimaryFlags)
        @AuraEnabled public Boolean isPrimary;          // effective primary (field value, or sole leaf)
        @AuraEnabled public Boolean primaryEligible;    // is a selectable leaf
        @AuraEnabled public Boolean primarySelectable;  // leaf AND role has >1 leaf (clickable)
    }
    public interface IStageOverride {

        /**
         * Called by processNextStageRequest when the user clicks Next on this stage.
         * Decides the target step; framework handles DML, applicant routing, nav rebuild.
         * See class-level javadoc for full contract.
         */
        StageNavigationResult execute(
            Id                      applicationId,
            String                  currentStagePhrase,
            String                  currentLoanStageName,
            Application__c          app,
            Dynamic_Stage_Gate__mdt currentRec,
            String                  effectivePortfolio
        );

        /**
         * Called by getMenuForPortfolio while building the navigation menu.
         * Return true  → this stage is shown in the menu as normal.
         * Return false → this stage is hidden from the menu entirely.
         *
         * Evaluated ONLY for stages whose status is 'completed' or 'active'
         * (i.e. stages already in the journey path behind or at the current step).
         * Future disabled stages are not evaluated — they use the optional-step
         * filter instead.
         *
         * Use case: a stage was conditionally bypassed by an execute() override
         * on a previous step (e.g. the journey jumped from A → C skipping B).
         * B's isVisible() can inspect the application state and return false so
         * B never appears as "completed" in the navigation path even though it
         * exists in the Custom Metadata.
         *
         * The app SObject includes Applicants__r so applicant-level conditions
         * can also be evaluated here.
         */
        Boolean isVisible(
            Application__c          app,
            Dynamic_Stage_Gate__mdt currentRec,
            String                  effectivePortfolio
        );
    }

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * @param portfolio     Portfolio value (e.g. 'Wheels', 'Personal Loan').
     *                      Optional – derived from Application__c.Product__c when blank.
     * @param applicationId Id of the Application__c record.
     * @return              NavigationPanelState compatible with stageMenu LWC.
     */
    @AuraEnabled(cacheable=false)
    public static NavigationPanelState getMenuForPortfolio(
            String portfolio, Id applicationId) {
                System.debug('@@@@ portfolio'+ portfolio);
                System.debug('@@@@ applicationId'+ applicationId);
        NavigationPanelState state = new NavigationPanelState();

        try {
            if (applicationId == null) {
                state.isSuccess = false;
                state.message   = 'applicationId is required.';
                return state;
            }

            // ── 1. Load application + related applicants ──────────────────────
            //      Product__c     = portfolio  (e.g. "Wheels")
            //      Sub_Product__c = product type for CMT filtering (e.g. "Four Wheeler")
            Application__c app = queryApplication(applicationId);
            System.debug('@@@@ app'+ app);
            String effectivePortfolio = String.isNotBlank(portfolio) ? portfolio : resolvePortfolio(app);

            if (String.isBlank(effectivePortfolio)) {
                state.isSuccess = false;
                state.message   = 'Portfolio could not be determined. Set Product__c on the Application or pass portfolio explicitly.';
                return state;
            }

            String currentMainStage = String.isNotBlank(app.Stage__c) ? app.Stage__c : '';
            String currentStep      = String.isNotBlank(app.Sub_Stage__c)  ? app.Sub_Stage__c  : '';
            String productType      = app.Sub_Product__c;

            // ── 2. Build applicant lookup used by sub-item generation ─────────
            Map<String, Applicant__c> applicantsByTabLabel = indexApplicantsByTabLabel(app.Applicants__r);
            journeyInProgressTx = ApplicantSubService.isJourneyInProgress(app.Applicants__r);
            inProgressSubTx     = ApplicantSubService.getInProgressSub(app.Applicants__r);
            System.debug('@@@@ applicantsByTabLabel'+ applicantsByTabLabel);

            // ── 3. Fetch CMT records for portfolio ────────────────────────────
            List<Dynamic_Stage_Gate__mdt> rawRecords = queryStageNavigator(effectivePortfolio);
            System.debug('@@@@ rawRecords'+ rawRecords);
            List<Dynamic_Stage_Gate__mdt> records    = filterByProductType(rawRecords, effectivePortfolio, productType);
            System.debug('@@@@ records'+ records);
            if (records.isEmpty()) {
                state.isSuccess = true;
                state.message   = 'No active stages found for portfolio: ' + effectivePortfolio;
                return state;
            }

            Map<String, Decimal> stepOrderByKey = buildStepOrderMap(records);
            String currentViewApplicantType = resolveCurrentViewApplicantType(
                applicantsByTabLabel, currentStep, currentMainStage, stepOrderByKey);

            // ── 4. Resolve current position order values ───────────────────────
            Decimal currentMainOrder = resolveMainStageOrder(records, currentMainStage);
            Decimal currentStepOrder = resolveStepOrder(records, currentMainStage, currentStep);

            // ── 5. Build menu items ────────────────────────────────────────────
            state.menuItems = buildMenuItems(
                records, currentMainStage, currentStep, currentMainOrder, currentStepOrder,
                applicantsByTabLabel, currentViewApplicantType, app, effectivePortfolio
            );
            System.debug('@@@@ state.menuItems'+ state.menuItems);
            state.isSuccess          = true;
            state.currentStagePhrase = toStagePhrase(currentStep, currentMainStage);

        } catch (Exception e) {
            state.isSuccess = false;
            state.message   = 'Error building navigation menu: ' + e.getMessage();
        }

        return state;
    }

    // =========================================================================
    // Data-access helpers
    // =========================================================================

    private static Application__c queryApplication(Id applicationId) {
        return [
            SELECT Id, Stage__c, Sub_Stage__c, Product__c, Sub_Product__c,
                   (SELECT Id, Applicant_Tab_Label__c, Name,
                           Applicant_Type__c, Type__c, Loan_Stage__c, Current_Loan_Stage_Complete__c,
                           Customer_First_Name__c, Customer_Last_Name__c, Company_Name__c,
                           Customer_Code__c, Invalid_Customer_Code__c,
                           In_Active_Applicant__c, Parent_Applicant__c, Is_Sub_Applicant__c,
                           Is_Primary__c
                    FROM   Applicants__r WHERE In_Active_Applicant__c = false
                    ORDER BY Applicant_Type__c ASC, Applicant_Tab_Label__c ASC)
            FROM   Application__c
            WHERE  Id = :applicationId
            LIMIT  1
        ];
    }

    private static List<Dynamic_Stage_Gate__mdt> queryStageNavigator(String portfolio) {
        return [
            SELECT DeveloperName, MasterLabel,
                   Portfolio__c, Product_Type__c,
                   Main_Stage_Name__c, Steps_Sub_Menu_Name__c,
                   Current_Main_Stage_Order__c, Current_Step_Order__c,
                   is_Current_Stage_common_for_Wheels__c,
                   is_Current_Step_Parallel__c,
                   is_Current_Step_Optional__c,
                   is_Current_Step_Applicant_based__c,
                   Forward_Main_Stage_Name__c, Forward_Steps_Name__c,
                   Override_Apex__c, Override_LWC__c,
                   Backward_Path__c, Is_Active__c
            FROM   Dynamic_Stage_Gate__mdt
            WHERE  Portfolio__c                = :portfolio
              AND  Is_Active__c                = true
              AND  is_Current_Step_Parallel__c = false
            ORDER BY Current_Main_Stage_Order__c ASC NULLS LAST,
                     Current_Step_Order__c       ASC NULLS LAST
        ];
    }

    // =========================================================================
    // Product-type filter
    // =========================================================================

    private static List<Dynamic_Stage_Gate__mdt> filterByProductType(
            List<Dynamic_Stage_Gate__mdt> records, String portfolio, String productType) {

        Boolean isWheels = 'Wheels'.equalsIgnoreCase(portfolio);
        List<Dynamic_Stage_Gate__mdt> filtered = new List<Dynamic_Stage_Gate__mdt>();

        for (Dynamic_Stage_Gate__mdt rec : records) {
            if (isWheels) {
                if (rec.is_Current_Stage_common_for_Wheels__c == true || matchesProductType(rec, productType)) {
                    filtered.add(rec);
                }
            } else if (String.isBlank(rec.Product_Type__c) || matchesProductType(rec, productType)) {
                filtered.add(rec);
            }
        }
        return filtered;
    }

    private static Boolean matchesProductType(Dynamic_Stage_Gate__mdt rec, String productType) {
        return String.isNotBlank(rec.Product_Type__c) && rec.Product_Type__c.equalsIgnoreCase(productType);
    }

    // =========================================================================
    // Order-resolution helpers
    // =========================================================================

    private static Decimal resolveMainStageOrder(
            List<Dynamic_Stage_Gate__mdt> records, String mainStageName) {
        if (String.isBlank(mainStageName)) return 0;
        for (Dynamic_Stage_Gate__mdt rec : records) {
            if (mainStageName.equals(rec.Main_Stage_Name__c)
                && rec.Current_Main_Stage_Order__c != null) {
                return rec.Current_Main_Stage_Order__c;
            }
        }
        return 0;
    }

    private static Decimal resolveStepOrder(
            List<Dynamic_Stage_Gate__mdt> records, String mainStageName, String stepName) {
        if (String.isBlank(mainStageName) || String.isBlank(stepName)) return 0;
        for (Dynamic_Stage_Gate__mdt rec : records) {
            if (mainStageName.equals(rec.Main_Stage_Name__c)
                && stepName.equals(rec.Steps_Sub_Menu_Name__c)
                && rec.Current_Step_Order__c != null) {
                return rec.Current_Step_Order__c;
            }
        }
        return 0;
    }

    /** Composite order key: mainStage::stepName (lowercase). */
    private static String stepOrderKey(String mainStage, String stepName) {
        return (String.valueOf(mainStage) + '::' + String.valueOf(stepName)).toLowerCase();
    }

    /** Builds a lookup of composite step order (mainOrder * 10000 + stepOrder) from CMT records. */
    private static Map<String, Decimal> buildStepOrderMap(List<Dynamic_Stage_Gate__mdt> records) {
        Map<String, Decimal> stepOrderByKey = new Map<String, Decimal>();
        if (records == null) return stepOrderByKey;
        for (Dynamic_Stage_Gate__mdt rec : records) {
            if (rec == null || String.isBlank(rec.Steps_Sub_Menu_Name__c)) continue;
            Decimal mainOrder = rec.Current_Main_Stage_Order__c != null ? rec.Current_Main_Stage_Order__c : 0;
            Decimal stepOrder = rec.Current_Step_Order__c        != null ? rec.Current_Step_Order__c        : 0;
            stepOrderByKey.put(
                stepOrderKey(rec.Main_Stage_Name__c, rec.Steps_Sub_Menu_Name__c),
                mainOrder * 10000 + stepOrder
            );
        }
        return stepOrderByKey;
    }

    private static Decimal getStepCompositeOrder(
            Map<String, Decimal> stepOrderByKey, String mainStageName, String stepName) {
        if (stepOrderByKey == null || stepOrderByKey.isEmpty() || String.isBlank(stepName)) return null;
        if (String.isNotBlank(mainStageName)) {
            Decimal order = stepOrderByKey.get(stepOrderKey(mainStageName, stepName));
            if (order != null) return order;
        }
        String suffix = '::' + stepName.trim().toLowerCase();
        for (String key : stepOrderByKey.keySet()) {
            if (key != null && key.endsWith(suffix)) return stepOrderByKey.get(key);
        }
        return null;
    }

    /** Strict lookup: step must exist under the given main stage (no cross-stage suffix match). */
    private static Decimal getStepCompositeOrderForMainStage(
            Map<String, Decimal> stepOrderByKey, String mainStageName, String stepName) {
        if (stepOrderByKey == null || stepOrderByKey.isEmpty()
                || String.isBlank(mainStageName) || String.isBlank(stepName)) {
            return null;
        }
        return stepOrderByKey.get(stepOrderKey(mainStageName, stepName));
    }

    /** True when this menu row is the application's current Stage__c + Sub_Stage__c position. */
    private static Boolean isMenuStepCurrentForApplication(
            String stepName,
            String mainStageName,
            String currentStep,
            String currentMainStage) {
        return String.isNotBlank(stepName)
            && stepName.equals(currentStep)
            && String.isNotBlank(mainStageName)
            && mainStageName.equalsIgnoreCase(currentMainStage);
    }

    /** Resolves which main stage owns a step name in CMT (first match). */
    private static String resolveMainStageForStepName(
            Map<String, Decimal> stepOrderByKey, String stepName) {
        if (stepOrderByKey == null || String.isBlank(stepName)) return null;
        String suffix = '::' + stepName.trim().toLowerCase();
        for (String key : stepOrderByKey.keySet()) {
            if (key != null && key.endsWith(suffix)) {
                return key.substring(0, key.length() - suffix.length());
            }
        }
        return null;
    }

    /**
     * Applicant Loan_Stage__c / Current_Loan_Stage_Complete__c only apply within the
     * given main stage and must not be ahead of the application's current Sub_Stage__c
     * in that same main stage (Option 1 — plain step names, main-stage interpretation).
     */
    private static Boolean applicantStageValueAppliesToMainStage(
            String applicantStepValue,
            String mainStageName,
            String applicationSubStage,
            Map<String, Decimal> stepOrderByKey) {
        if (String.isBlank(applicantStepValue) || String.isBlank(mainStageName) || stepOrderByKey == null) {
            return false;
        }
        String trimmedValue = applicantStepValue.trim();
        // Interpret duplicate step names in the context main stage (Operations vs PSS), not first CMT match.
        if (getStepCompositeOrderForMainStage(stepOrderByKey, mainStageName, trimmedValue) == null) {
            return false;
        }
        if (String.isNotBlank(applicationSubStage)
                && getStepCompositeOrderForMainStage(
                    stepOrderByKey, mainStageName, applicationSubStage.trim()) != null) {
            Decimal appOrder = getStepCompositeOrderForMainStage(
                stepOrderByKey, mainStageName, applicationSubStage.trim());
            Decimal valueOrder = getStepCompositeOrderForMainStage(
                stepOrderByKey, mainStageName, trimmedValue);
            if (appOrder != null && valueOrder != null && valueOrder > appOrder) {
                return false;
            }
        }
        return true;
    }

    /** True when the applicant has finished stepName or progressed to a later step. */
    private static Boolean hasApplicantPassedStep(
            Applicant__c app, String stepName, String mainStageName, Map<String, Decimal> stepOrderByKey) {
        return hasApplicantPassedStep(app, stepName, mainStageName, stepOrderByKey, null);
    }

    private static Boolean hasApplicantPassedStep(
            Applicant__c app,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey,
            String applicationSubStage) {
        if (app == null || String.isBlank(stepName) || stepOrderByKey == null || stepOrderByKey.isEmpty()) {
            return false;
        }
        Decimal targetOrder = getStepCompositeOrderForMainStage(stepOrderByKey, mainStageName, stepName);
        if (targetOrder == null) return false;
        if (String.isNotBlank(app.Loan_Stage__c)) {
            String loanStage = app.Loan_Stage__c.trim();
            if (applicantStageValueAppliesToMainStage(
                    loanStage, mainStageName, applicationSubStage, stepOrderByKey)) {
                Decimal loanOrder = getStepCompositeOrderForMainStage(
                    stepOrderByKey, mainStageName, loanStage);
                if (loanOrder != null && loanOrder > targetOrder) return true;
            }
        }
        if (String.isNotBlank(app.Current_Loan_Stage_Complete__c)) {
            String completeStep = app.Current_Loan_Stage_Complete__c.trim();
            if (applicantStageValueAppliesToMainStage(
                    completeStep, mainStageName, applicationSubStage, stepOrderByKey)) {
                Decimal completeOrder = getStepCompositeOrderForMainStage(
                    stepOrderByKey, mainStageName, completeStep);
                if (completeOrder != null && completeOrder > targetOrder) return true;
            }
        }
        return false;
    }

    /**
     * Expanded applicant menu / routing (queued-from-prior-step, add-from-dedupe) applies only
     * to multi-applicant QDE steps — not DDE Income, Credit Processing, Operations, etc.
     */
    private static Boolean useExpandedQdeApplicantMenuScope(
            String stepName,
            String mainStageName) {
        if (!MAIN_STAGE_QDE.equalsIgnoreCase(mainStageName) || String.isBlank(stepName)) {
            return false;
        }
        return STEP_BASIC_DETAILS.equals(stepName)
            || STEP_KYC_DETAILS.equals(stepName)
            || STEP_DEDUPE_AND_ELIGIBILITY.equals(stepName);
    }

    private static Boolean isNavigatorBorrowerApplicant(Applicant__c app) {
        return app != null && 'Borrower'.equalsIgnoreCase(String.valueOf(app.Applicant_Type__c));
    }

    /**
     * True when applicant completed stepName exactly or progressed past it. Dedupe completion for
     * non-Borrowers is driven by real step completion (Current_Loan_Stage_Complete__c set on NEXT),
     * not by a CIF-on-PAN Customer_Code__c, so the green tick only appears after the applicant
     * clicks NEXT on their Dedupe and Eligibility screen.
     */
    private static Boolean hasApplicantFinishedStep(
            Applicant__c app, String stepName, String mainStageName, Map<String, Decimal> stepOrderByKey) {
        return hasApplicantFinishedStep(app, stepName, mainStageName, stepOrderByKey, null);
    }

    private static Boolean hasApplicantFinishedStep(
            Applicant__c app,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey,
            String applicationSubStage) {
        return isApplicantCompletedForStep(
                app, stepName, mainStageName, applicationSubStage, stepOrderByKey)
            || hasApplicantPassedStep(
                app, stepName, mainStageName, stepOrderByKey, applicationSubStage);
    }

    /**
     * Backend marked an earlier step complete (Current_Loan_Stage_Complete__c) but not this one —
     * show on the next step menu as pending (active), not completed. Same main stage only.
     */
    private static Boolean isApplicantQueuedForStep(
            Applicant__c app,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey) {
        if (!useExpandedQdeApplicantMenuScope(stepName, mainStageName)) {
            return false;
        }
        if (app == null || String.isBlank(stepName) || hasApplicantFinishedStep(
                app, stepName, mainStageName, stepOrderByKey)) {
            return false;
        }
        if (String.isBlank(app.Current_Loan_Stage_Complete__c)) {
            return false;
        }
        String completeStep = app.Current_Loan_Stage_Complete__c.trim();
        String completeMainStage = resolveMainStageForStepName(stepOrderByKey, completeStep);
        if (String.isBlank(completeMainStage)
                || !completeMainStage.equalsIgnoreCase(mainStageName)) {
            return false;
        }
        Decimal targetOrder = getStepCompositeOrderForMainStage(
            stepOrderByKey, mainStageName, stepName);
        Decimal completeOrder = getStepCompositeOrderForMainStage(
            stepOrderByKey, mainStageName, completeStep);
        return targetOrder != null && completeOrder != null && completeOrder < targetOrder;
    }

    /** Add-from-dedupe: Loan_Stage__c still before Dedupe while borrower is on dedupe journey. */
    private static Boolean isApplicantPendingOnDedupeFromPreQde(
            Applicant__c app,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey) {
        if (app == null || !STEP_DEDUPE_AND_ELIGIBILITY.equals(stepName)
                || hasApplicantFinishedStep(app, stepName, mainStageName, stepOrderByKey)) {
            return false;
        }
        Decimal dedupeOrder = getStepCompositeOrderForMainStage(
            stepOrderByKey, mainStageName, stepName);
        if (dedupeOrder == null || String.isBlank(app.Loan_Stage__c)) {
            return false;
        }
        String loanStage = app.Loan_Stage__c.trim();
        String loanMainStage = resolveMainStageForStepName(stepOrderByKey, loanStage);
        if (String.isBlank(loanMainStage) || !loanMainStage.equalsIgnoreCase(mainStageName)) {
            return false;
        }
        Decimal loanOrder = getStepCompositeOrderForMainStage(
            stepOrderByKey, mainStageName, loanStage);
        return loanOrder != null && loanOrder < dedupeOrder;
    }

    /** True when a co-applicant should appear on the Dedupe and Eligibility menu row. */
    private static Boolean isApplicantInScopeForDedupeStep(
            Applicant__c app,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey) {
        if (app == null || isNavigatorBorrowerApplicant(app)) {
            return true;
        }
        if (!CustomerDedupeController.hasApplicantCompletedPriorStagesForDedupe(app)) {
            return false;
        }
        if (isApplicantRelevantForStep(
                app, STEP_DEDUPE_AND_ELIGIBILITY, mainStageName, null, stepOrderByKey)) {
            return true;
        }
        if (hasApplicantPassedStep(
                app, STEP_DEDUPE_AND_ELIGIBILITY, mainStageName, stepOrderByKey, null)) {
            return true;
        }
        return isApplicantQueuedForStep(
            app, STEP_DEDUPE_AND_ELIGIBILITY, mainStageName, stepOrderByKey);
    }

    /** True when applicant is at stepName, queued for it, just finished it, or has moved past it. */
    private static Boolean isApplicantInScopeForStep(
            Applicant__c app,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey,
            String applicationCurrentStep) {
        // Customer Dedupe only: co-applicants on Dedupe menu after prior QDE stages (not while still on Basic).
        if (STEP_DEDUPE_AND_ELIGIBILITY.equals(stepName) && !isNavigatorBorrowerApplicant(app)) {
            return isApplicantInScopeForDedupeStep(app, mainStageName, stepOrderByKey);
        }
        if (isApplicantRelevantForStep(
                app, stepName, mainStageName, applicationCurrentStep, stepOrderByKey)
                || hasApplicantPassedStep(
                    app, stepName, mainStageName, stepOrderByKey, applicationCurrentStep)) {
            return true;
        }
        if (!useExpandedQdeApplicantMenuScope(stepName, mainStageName)
                && String.isNotBlank(applicationCurrentStep)
                && !isNavigatorBorrowerApplicant(app)
                && isApplicationAtOrPastStep(
                    applicationCurrentStep, stepName, mainStageName, stepOrderByKey)
                && CustomerDedupeController.hasApplicantClearedQdeJourney(app)) {
            return true;
        }
        if (!useExpandedQdeApplicantMenuScope(stepName, mainStageName)) {
            return false;
        }
        return isApplicantQueuedForStep(app, stepName, mainStageName, stepOrderByKey)
            || isApplicantPendingOnDedupeFromPreQde(app, stepName, mainStageName, stepOrderByKey);
    }

    // =========================================================================
    // Menu-item builder
    // =========================================================================

    private static List<NavigationMenuItem> buildMenuItems(
            List<Dynamic_Stage_Gate__mdt> records,
            String currentMainStage,
            String currentStep,
            Decimal currentMainOrder,
            Decimal currentStepOrder,
            Map<String, Applicant__c> applicantsByTabLabel,
            String currentViewApplicantType,
            Application__c app,
            String effectivePortfolio) {

        List<NavigationMenuItem> items = new List<NavigationMenuItem>();

        // Cache of resolved IStageOverride instances keyed by Override_Apex__c class name.
        // Avoids repeated Type.forName() + newInstance() calls when multiple stages
        // reference the same override class within a single menu-build operation.
        Map<String, IStageOverride> overrideCache = new Map<String, IStageOverride>();
        Map<String, Decimal> stepOrderByKey = buildStepOrderMap(records);
                System.debug('@@@@ records size'+ records.size());
        for (Dynamic_Stage_Gate__mdt rec : records) {

            NavigationMenuItem item = new NavigationMenuItem();
            item.id          = rec.DeveloperName;
            item.label       = rec.Steps_Sub_Menu_Name__c;
            item.tab         = rec.Steps_Sub_Menu_Name__c;
            item.groupName   = rec.Main_Stage_Name__c;
            item.stagePhrase = toStagePhrase(rec.Steps_Sub_Menu_Name__c, rec.Main_Stage_Name__c);
            item.overrideLwc = rec.Override_LWC__c;

            Boolean hasApplicantSubstage = rec.is_Current_Step_Applicant_based__c == true;
            item.hasApplicantSubstage    = hasApplicantSubstage;
            item.isGroupItem             = false;
            item.applicants              = new List<ApplicantInfo>();

            // ── Status computation ────────────────────────────────────────────
            Decimal recMainOrder = rec.Current_Main_Stage_Order__c != null ? rec.Current_Main_Stage_Order__c : 0;
            Decimal recStepOrder = rec.Current_Step_Order__c        != null ? rec.Current_Step_Order__c        : 0;

            Boolean isThisExactStep =
                rec.Main_Stage_Name__c     == currentMainStage &&
                rec.Steps_Sub_Menu_Name__c == currentStep;

            String itemStatus;
            if (recMainOrder < currentMainOrder) {
                itemStatus = STATUS_COMPLETED;
            } else if (recMainOrder == currentMainOrder) {
                if      (recStepOrder < currentStepOrder) itemStatus = STATUS_COMPLETED;
                else if (isThisExactStep)                 itemStatus = STATUS_ACTIVE;
                else                                      itemStatus = STATUS_DISABLED;
            } else {
                itemStatus = STATUS_DISABLED;
            }

            item.status = itemStatus;

           

            // ── Override_Apex__c visibility check ─────────────────────────────
            // Only evaluated for stages already in the journey path (completed or
            // active).  Future disabled stages are not checked — they may not yet
            // be reachable and the application state cannot determine their
            // relevance until the journey reaches them.
            //
            // A stage is hidden when its override class returns isVisible() = false.
            // Typical use: a stage was conditionally bypassed by a previous
            // execute() override; isVisible() detects this and removes it from the
            // completed path so the navigation panel stays consistent with the
            // actual journey taken by the application.
            // if (String.isNotBlank(rec.Override_Apex__c)
            //         && (itemStatus == STATUS_COMPLETED || itemStatus == STATUS_ACTIVE)) {

            if (String.isNotBlank(rec.Override_Apex__c)) {
                IStageOverride visibilityChecker = resolveOverrideInstance(
                    rec.Override_Apex__c, overrideCache
                );

                if (visibilityChecker != null) {
                    try {
                        Boolean visible = visibilityChecker.isVisible(app, rec, effectivePortfolio);
                        if (visible == false) continue;
                    } catch (Exception visErr) {
                        // Treat exceptions as "visible = true" so a broken
                        // isVisible() never silently empties the menu.
                    }
                }
            }


             // ── Optional step: hide if not yet reached in the forward journey ──
            // An optional step that is still 'disabled' (future) is excluded from
            // the menu entirely.  Once the application reaches it (active) or has
            // passed through it (completed) it appears normally.
            // if (rec.is_Current_Step_Optional__c == true && itemStatus == STATUS_DISABLED) {
            //     continue;
            // }

            // ── Optional step: hide future steps unless Override_Apex governs them ──
            if (rec.is_Current_Step_Optional__c == true
                    && itemStatus == STATUS_DISABLED
                    && String.isBlank(rec.Override_Apex__c)) {
                continue;
            }

            // ── Applicant substage: build child items ─────────────────────────
            if (hasApplicantSubstage) {
                // Parent is never the current view when it has sub-items
                item.currentView = false;
                item.subItems = buildApplicantSubItems(
                    rec, applicantsByTabLabel,
                    isThisExactStep ? currentViewApplicantType : null,
                    itemStatus, currentStep, currentMainStage, stepOrderByKey
                );
                // Rail status rolls up from the tiles: green only when every applicant that has
                // reached this step is complete; active while any applicant is in-flight here.
                item.status = rollUpStatusFromSubItems(item.subItems);
            } else {
                item.currentView = isThisExactStep;
                item.subItems    = new List<NavigationMenuItem>();
            }

            items.add(item);
        }
        return items;
    }

    // =========================================================================
    // Applicant sub-item builders
    // =========================================================================

    /**
     * Creates one sub-menu item per applicant role under a given applicant-based step.
     * Order: Borrower → CoBo1..3 → G1..3 → B1..10.
     * 2+ applicants of the same type at this step are collapsed into a single Multi-Grid entry.
     */
    private static List<NavigationMenuItem> buildApplicantSubItems(
            Dynamic_Stage_Gate__mdt rec,
            Map<String, Applicant__c> applicantsByTabLabel,
            String currentViewApplicantType,
            String stageStatus,
            String currentStep,
            String currentMainStage,
            Map<String, Decimal> stepOrderByKey) {
                System.debug('@@@@ buildApplicantSubItems');
        List<NavigationMenuItem> subItems = new List<NavigationMenuItem>();
        String stepName      = rec.Steps_Sub_Menu_Name__c;
        String mainStageName = rec.Main_Stage_Name__c;
                System.debug('@@@@ applicantsByTabLabel containsKey Borrower'+ applicantsByTabLabel.containsKey('Borrower'));
        if (applicantsByTabLabel.containsKey('Borrower')) {
            Applicant__c borrower = applicantsByTabLabel.get('Borrower');
            subItems.add(createApplicantSubItem(
                rec, 'Borrower', borrower,
                'Borrower'.equals(currentViewApplicantType),
                computeApplicantSubItemStatus(
                    borrower, stepName, mainStageName, stageStatus, currentStep, currentMainStage, stepOrderByKey)));
        }

        appendRoleSubItems(subItems, rec, applicantsByTabLabel, 'CoBo', 'Co-Borrower', 'CoBorrower',
            currentViewApplicantType, stageStatus, currentStep, currentMainStage, stepName, mainStageName, stepOrderByKey);
        appendRoleSubItems(subItems, rec, applicantsByTabLabel, 'G', 'Guarantor', 'Guarantor',
            currentViewApplicantType, stageStatus, currentStep, currentMainStage, stepName, mainStageName, stepOrderByKey);
        appendRoleSubItems(subItems, rec, applicantsByTabLabel, 'B', 'Beneficiary', 'Beneficiary',
            currentViewApplicantType, stageStatus, currentStep, currentMainStage, stepName, mainStageName, stepOrderByKey);

        return subItems;
    }

    private static void appendRoleSubItems(
            List<NavigationMenuItem> subItems,
            Dynamic_Stage_Gate__mdt rec,
            Map<String, Applicant__c> applicantsByTabLabel,
            String prefix,
            String displayLabel,
            String currentViewAlias,
            String currentViewApplicantType,
            String stageStatus,
            String currentStep,
            String currentMainStage,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey) {

        List<Applicant__c> roleApplicants = getRoleApplicantsForStep(
            applicantsByTabLabel, prefix, displayLabel, stepName, mainStageName, stepOrderByKey, currentStep);
        if (roleApplicants.isEmpty()) return;

        // The role submenu always carries the role name ("Guarantor"/"Beneficiary"/"Co-Borrower").
        // 2+ applicants of a role → one Multi-Grid row (listOfApplicants tiles).
        // A single Non-Individual applicant that has Individual sub-applicants also renders as a
        // grid (top-level + nested sub-level tiles).
        // A single applicant with no sub-applicants → drill straight into that applicant's screen.
        Boolean anyHasSubs = false;
        for (Applicant__c app : roleApplicants) {
            if (hasActiveSubApplicants(app.Id)) {
                anyHasSubs = true;
                break;
            }
        }
        if (roleApplicants.size() > 1 || anyHasSubs) {
            NavigationMenuItem groupItem = createGroupSubItem(
                rec, displayLabel, roleApplicants, currentViewApplicantType,
                stageStatus, stepName, currentStep, currentMainStage, stepOrderByKey);
            applySubToggle(groupItem, roleApplicants, rec);
            subItems.add(groupItem);
            return;
        }

        for (Applicant__c app : roleApplicants) {
            String tabLabel = String.isNotBlank(app.Applicant_Tab_Label__c)
                ? app.Applicant_Tab_Label__c
                : displayLabel;
            NavigationMenuItem leaf = createApplicantSubItem(
                rec, displayLabel, app,
                isApplicantCurrentView(app, tabLabel, currentViewAlias, currentViewApplicantType),
                computeApplicantSubItemStatus(
                    app, stepName, mainStageName, stageStatus, currentStep, currentMainStage, stepOrderByKey));
            applySubToggle(leaf, roleApplicants, rec);
            subItems.add(leaf);
        }
    }

    /**
     * Attaches SUB-toggle metadata to a role sub-item. Shown only on the Basic Details
     * step when the role has exactly one active NI top-level applicant; ON-capable once that NI
     * applicant has cleared Dedupe & Eligibility. Multi-NI roles add subs via the grid "+" tile.
     */
    private static void applySubToggle(
            NavigationMenuItem item, List<Applicant__c> roleApplicants, Dynamic_Stage_Gate__mdt rec) {
        if (item == null || rec == null || !STEP_BASIC_DETAILS.equals(rec.Steps_Sub_Menu_Name__c)) {
            return;
        }
        // A sub of this role is mid-edit → toggle is ON and jumps straight to that in-progress sub
        // (works for single- or multi-NI roles). Takes precedence over the add-sub behaviour.
        if (inProgressSubTx != null && !roleApplicants.isEmpty()
                && String.valueOf(inProgressSubTx.Applicant_Type__c).equalsIgnoreCase(
                       String.valueOf(roleApplicants[0].Applicant_Type__c))) {
            item.showSubToggle         = true;
            item.subToggleEnabled      = true;
            item.subInProgress         = true;
            item.subInProgressId       = inProgressSubTx.Id;
            item.subInProgressTabLabel = inProgressSubTx.Applicant_Tab_Label__c;
            item.subParentApplicantId  = inProgressSubTx.Parent_Applicant__c;
            item.subBaseStagePhrase    = toStagePhrase(rec.Steps_Sub_Menu_Name__c, rec.Main_Stage_Name__c);
            return;
        }
        Applicant__c niParent = null;
        Integer niCount = 0;
        for (Applicant__c app : roleApplicants) {
            if (app == null || app.In_Active_Applicant__c == true) continue;
            if (TYPE_NON_INDIVIDUAL.equalsIgnoreCase(String.valueOf(app.Type__c))) {
                niCount++;
                niParent = app;
            }
        }
        if (niCount != 1 || niParent == null) {
            return;
        }
        item.showSubToggle = true;
        item.subParentApplicantId = niParent.Id;
        item.subBaseStagePhrase = toStagePhrase(rec.Steps_Sub_Menu_Name__c, rec.Main_Stage_Name__c);
        // ON-capable once the NI parent cleared Dedupe & Eligibility AND no other journey is open.
        item.subToggleEnabled = !journeyInProgressTx
            && STEP_DEDUPE_AND_ELIGIBILITY.equalsIgnoreCase(
                String.valueOf(niParent.Current_Loan_Stage_Complete__c));
    }

    private static Boolean isApplicantCurrentView(
            Applicant__c app,
            String displayLabel,
            String currentViewAlias,
            String currentViewApplicantType) {
        if (String.isBlank(currentViewApplicantType)) return false;
        if (currentViewApplicantType.equals(displayLabel)
                || currentViewApplicantType.equals(currentViewAlias)) {
            return true;
        }
        return app != null
            && app.Applicant_Tab_Label__c != null
            && app.Applicant_Tab_Label__c.equals(currentViewApplicantType);
    }

    /** Single-applicant leaf sub-item (Borrower or sole CoBo/G/B at this step). */
    private static NavigationMenuItem createApplicantSubItem(
            Dynamic_Stage_Gate__mdt rec,
            String displayLabel,
            Applicant__c applicant,
            Boolean currentView,
            String stageStatus) {

        // Token used in stagePhrase: Borrower stays "Borrower"; others use their TabLabel
        String token = displayLabel;
        if (applicant != null
            && String.isNotBlank(applicant.Applicant_Tab_Label__c)
            && !'Borrower'.equalsIgnoreCase(displayLabel)) {
            token = applicant.Applicant_Tab_Label__c;
        }
        String basePhrase = toStagePhrase(rec.Steps_Sub_Menu_Name__c, rec.Main_Stage_Name__c);
        String stagePhrase = basePhrase + '_' + token.replaceAll('\\s+', '_');
        String itemId      = stagePhrase + (applicant != null ? '_' + applicant.Id : '');

        NavigationMenuItem sub = new NavigationMenuItem();
        sub.id                = itemId;
        sub.label             = displayLabel;
        sub.tab               = rec.Steps_Sub_Menu_Name__c;
        sub.stagePhrase       = stagePhrase;
        sub.applicantType     = token;
        sub.applicantId       = applicant != null ? applicant.Id : null;
        sub.hasApplicantSubstage = false;
        sub.currentView       = currentView;
        sub.status            = stageStatus;
        sub.isGroupItem       = false;
        sub.subItems          = new List<NavigationMenuItem>();
        sub.applicants        = new List<ApplicantInfo>();
        sub.overrideLwc       = rec.Override_LWC__c;
        return sub;
    }

    /** Multi-Grid sub-item used when 2+ applicants of the same type exist at this step. */
    private static NavigationMenuItem createGroupSubItem(
            Dynamic_Stage_Gate__mdt rec,
            String groupLabel,
            List<Applicant__c> applicants,
            String currentViewApplicantType,
            String stageStatus,
            String stepName,
            String currentStep,
            String currentMainStage,
            Map<String, Decimal> stepOrderByKey) {

        String basePhrase = toStagePhrase(rec.Steps_Sub_Menu_Name__c, rec.Main_Stage_Name__c);
        String stagePhrase = basePhrase + '_' + groupLabel.replaceAll('\\s+', '_');
        String itemId      = stagePhrase;

        List<ApplicantInfo> infos = new List<ApplicantInfo>();
        Boolean currentView = String.isNotBlank(currentViewApplicantType)
                              && groupLabel.equals(currentViewApplicantType);

        for (Applicant__c app : applicants) {
            if (app.In_Active_Applicant__c == true) continue;

            infos.add(toApplicantInfo(
                app, stepName, rec.Main_Stage_Name__c, stageStatus, currentStep, currentMainStage, stepOrderByKey));
            if (app.Applicant_Tab_Label__c != null
                    && app.Applicant_Tab_Label__c.equals(currentViewApplicantType)) {
                currentView = true;
            }
        }

        // Role row rolls up from member tiles (top-level + nested subs): active while any member
        // is in-flight, green once every member that has reached the step is complete.
        String subStatus = rollUpStatusFromApplicantInfos(infos);

        applyPrimaryFlags(infos);   // mark leaf eligibility + effective primary per role

        NavigationMenuItem sub = new NavigationMenuItem();
        sub.id                = itemId;
        sub.label             = groupLabel;
        sub.tab               = rec.Steps_Sub_Menu_Name__c;
        sub.stagePhrase       = stagePhrase;
        sub.applicantType     = groupLabel;
        sub.applicantId       = null;
        sub.hasApplicantSubstage = false;
        sub.currentView       = currentView;
        sub.status            = subStatus;
        sub.isGroupItem       = true;
        sub.subItems          = new List<NavigationMenuItem>();
        sub.applicants        = infos;
        sub.overrideLwc       = rec.Override_LWC__c;
        sub.subCreationLocked = journeyInProgressTx;
        return sub;
    }

    /**
     * two-level primary flags for one role group's applicant infos.
     *  - Top level: every active top-level member of the role is eligible (NI or IN).
     *    Selectable when 2+ members; a sole member is the implicit Primary.
     *  - Sub level: within each NI parent, every active IN sub is eligible.
     *    Selectable when the parent has 2+ subs; a sole sub is the implicit Primary sub.
     * "Effective" isPrimary = the persisted Is_Primary__c, or true when it is the only one in scope.
     */
    private static void applyPrimaryFlags(List<ApplicantInfo> infos) {
        if (infos == null || infos.isEmpty()) return;
        Integer topCount = infos.size();   // already filtered to active top-level members
        for (ApplicantInfo top : infos) {
            top.primaryEligible   = true;
            top.primarySelectable = (topCount > 1);
            top.isPrimary = (topCount == 1) ? true : (top.isPrimary == true);

            if (top.subApplicants != null && !top.subApplicants.isEmpty()) {
                List<ApplicantInfo> subs = new List<ApplicantInfo>();
                for (ApplicantInfo s : top.subApplicants) {
                    if (s.inActiveApplicant == true) continue;
                    subs.add(s);
                }
                Integer subCount = subs.size();
                for (ApplicantInfo s : subs) {
                    s.primaryEligible   = true;
                    s.primarySelectable = (subCount > 1);
                    s.isPrimary = (subCount == 1) ? true : (s.isPrimary == true);
                }
            }
        }
    }

    // =========================================================================
    // Applicant status helpers
    // =========================================================================

    /**
     * Per-applicant tile status, derived only from the applicant's own progress:
     *   completed – applicant finished stepName or moved past it
     *   active    – applicant is currently on stepName (its in-flight leaf)
     *   disabled  – applicant has not reached stepName yet
     */
    private static String computeApplicantTileStatus(
            Applicant__c app,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey) {
        if (app == null) return STATUS_DISABLED;
        if (hasApplicantFinishedStep(app, stepName, mainStageName, stepOrderByKey, null)) {
            return STATUS_COMPLETED;
        }
        if (stepName != null
                && stepName.equals(app.Loan_Stage__c)
                && applicantStageValueAppliesToMainStage(
                    app.Loan_Stage__c, mainStageName, null, stepOrderByKey)) {
            return STATUS_ACTIVE;
        }
        return STATUS_DISABLED;
    }

    /**
     * Roll-up status for an applicant-based step from its member tile statuses:
     *   active    – any member is in-flight
     *   completed – no member in-flight and at least one member finished (not-yet-reached tiles ignored)
     *   disabled  – no member finished or in-flight
     */
    private static String rollUpStatus(List<String> tileStatuses) {
        Boolean anyActive = false;
        Boolean anyCompleted = false;
        if (tileStatuses != null) {
            for (String st : tileStatuses) {
                if (STATUS_ACTIVE == st) {
                    anyActive = true;
                } else if (STATUS_COMPLETED == st) {
                    anyCompleted = true;
                }
            }
        }
        if (anyActive) return STATUS_ACTIVE;
        if (anyCompleted) return STATUS_COMPLETED;
        return STATUS_DISABLED;
    }

    /** Roll-up over rendered sub-menu items (leaf tiles and Multi-Grid role rows). */
    private static String rollUpStatusFromSubItems(List<NavigationMenuItem> subItems) {
        List<String> statuses = new List<String>();
        if (subItems != null) {
            for (NavigationMenuItem sub : subItems) {
                statuses.add(sub.status);
            }
        }
        return rollUpStatus(statuses);
    }

    /** Roll-up over a Multi-Grid role row's members (top-level applicants and nested subs). */
    private static String rollUpStatusFromApplicantInfos(List<ApplicantInfo> infos) {
        List<String> statuses = new List<String>();
        if (infos != null) {
            for (ApplicantInfo info : infos) {
                statuses.add(info.stepMenuStatus);
                if (info.subApplicants != null) {
                    for (ApplicantInfo sub : info.subApplicants) {
                        statuses.add(sub.stepMenuStatus);
                    }
                }
            }
        }
        return rollUpStatus(statuses);
    }

    /** Per-applicant status for a leaf sub-item. */
    private static String computeApplicantSubItemStatus(
            Applicant__c app,
            String stepName,
            String mainStageName,
            String stageStatus,
            String currentStep,
            String currentMainStage,
            Map<String, Decimal> stepOrderByKey) {
        return computeApplicantTileStatus(app, stepName, mainStageName, stepOrderByKey);
    }

    /** True when applicant's Current_Loan_Stage_Complete__c matches the step name (main-stage scoped). */
    private static Boolean isApplicantCompletedForStep(Applicant__c app, String stepName) {
        return isApplicantCompletedForStep(app, stepName, null, null, null);
    }

    private static Boolean isApplicantCompletedForStep(
            Applicant__c app,
            String stepName,
            String mainStageName,
            String applicationSubStage,
            Map<String, Decimal> stepOrderByKey) {
        if (app == null || String.isBlank(app.Current_Loan_Stage_Complete__c)) return false;
        if (!stepName.equals(app.Current_Loan_Stage_Complete__c.trim())) return false;
        if (String.isBlank(mainStageName) || stepOrderByKey == null) return true;
        return applicantStageValueAppliesToMainStage(
            app.Current_Loan_Stage_Complete__c, mainStageName, applicationSubStage, stepOrderByKey);
    }

    /** Display name for Multi-Grid cards and nav hints — first/last name, not Applicant__c.Name (SF Id). */
    private static String formatApplicantDisplayName(Applicant__c app) {
        if (app == null) {
            return '';
        }
        List<String> nameParts = new List<String>();
        if (String.isNotBlank(app.Customer_First_Name__c)) {
            nameParts.add(app.Customer_First_Name__c.trim());
        }
        if (String.isNotBlank(app.Customer_Last_Name__c)) {
            nameParts.add(app.Customer_Last_Name__c.trim());
        }
        String fullName = String.join(nameParts, ' ').trim();
        if (String.isNotBlank(fullName)) {
            return fullName;
        }
        if (String.isNotBlank(app.Company_Name__c)) {
            return app.Company_Name__c.trim();
        }
        if (String.isNotBlank(app.Applicant_Tab_Label__c)) {
            return app.Applicant_Tab_Label__c.trim();
        }
        return '';
    }

    private static ApplicantInfo toApplicantInfo(
            Applicant__c app,
            String stepName,
            String mainStageName,
            String stageStatus,
            String currentStep,
            String currentMainStage,
            Map<String, Decimal> stepOrderByKey) {
        ApplicantInfo info = new ApplicantInfo();
        info.applicantId              = app.Id;
        info.tabLabel                 = app.Applicant_Tab_Label__c;
        info.applicantName            = formatApplicantDisplayName(app);
        info.customerType             = String.isNotBlank(app.Type__c) ? app.Type__c : 'Individual';
        info.loanStages               = app.Loan_Stage__c;
        info.currentLoanStageComplete = app.Current_Loan_Stage_Complete__c;
        info.inActiveApplicant        = app.In_Active_Applicant__c == true;
        info.isSubApplicant           = app.Is_Sub_Applicant__c == true;
        info.isPrimary                = app.Is_Primary__c == true;   // raw; refined in applyPrimaryFlags
        info.primaryEligible          = false;
        info.primarySelectable        = false;
        info.stepMenuStatus           = computeApplicantSubItemStatus(
            app, stepName, mainStageName, stageStatus, currentStep, currentMainStage, stepOrderByKey);
        info.hasSubApplicants         = false;
        List<Applicant__c> subs = subApplicantsByParentId.get(app.Id);
        if (subs != null && !subs.isEmpty()) {
            info.subApplicants = new List<ApplicantInfo>();
            for (Applicant__c sub : subs) {
                if (sub.In_Active_Applicant__c == true) continue;
                info.subApplicants.add(toApplicantInfo(
                    sub, stepName, mainStageName, stageStatus, currentStep, currentMainStage, stepOrderByKey));
            }
            info.hasSubApplicants = !info.subApplicants.isEmpty();
        }
        return info;
    }

    // =========================================================================
    // Applicant lookup / ordering helpers
    // =========================================================================

    /**
     * Indexes active applicants by Applicant_Tab_Label__c.
     * Falls back to 'Borrower' key for records that have Applicant_Type__c = 'Borrower' but no tab label.
     */
    private static Map<String, Applicant__c> indexApplicantsByTabLabel(List<Applicant__c> applicants) {
        Map<String, Applicant__c> byTabLabel = new Map<String, Applicant__c>();
        subApplicantsByParentId = new Map<Id, List<Applicant__c>>();
        if (applicants == null) return byTabLabel;
        for (Applicant__c app : applicants) {
            if (app.In_Active_Applicant__c == true) continue;
            if (app.Is_Sub_Applicant__c == true && app.Parent_Applicant__c != null) {
                if (!subApplicantsByParentId.containsKey(app.Parent_Applicant__c)) {
                    subApplicantsByParentId.put(app.Parent_Applicant__c, new List<Applicant__c>());
                }
                subApplicantsByParentId.get(app.Parent_Applicant__c).add(app);
            }
            if (String.isNotBlank(app.Applicant_Tab_Label__c)) {
                byTabLabel.put(app.Applicant_Tab_Label__c.trim(), app);
            } else if (String.isNotBlank(app.Applicant_Type__c) && 'Borrower'.equalsIgnoreCase(app.Applicant_Type__c.trim())) {
                byTabLabel.put('Borrower', app);
            }
        }
        return byTabLabel;
    }

    /** Transaction-scoped index of active Individual sub-applicants keyed by their parent NI applicant Id. */
    private static Map<Id, List<Applicant__c>> subApplicantsByParentId = new Map<Id, List<Applicant__c>>();

    /** Transaction-scoped single-in-progress flag, recomputed on each menu build. */
    private static Boolean journeyInProgressTx = false;

    /** Transaction-scoped mid-edit sub-applicant (if any), recomputed on each menu build. */
    private static Applicant__c inProgressSubTx = null;

    private static Boolean hasActiveSubApplicants(Id applicantId) {
        List<Applicant__c> subs = applicantId == null ? null : subApplicantsByParentId.get(applicantId);
        return subs != null && !subs.isEmpty();
    }

    /**
     * Returns applicants with a given prefix in numeric order (CoBo1, CoBo2 … or G1, G2 …).
     * Prefix 'B' checks up to B10; all others up to 3.
     */
    private static List<Applicant__c> getApplicantsWithPrefix(
            Map<String, Applicant__c> byTabLabel, String prefix) {
        Integer maxIdx = 'B'.equals(prefix) ? 10 : 3;
        List<Applicant__c> result = new List<Applicant__c>();
        for (Integer i = 1; i <= maxIdx; i++) {
            String key = prefix + i;
            if (byTabLabel.containsKey(key)) result.add(byTabLabel.get(key));
        }
        return result;
    }

    /**
     * Returns active (non-soft-deleted) applicants with the given prefix that are
     * relevant for the given step:
     *   – Loan_Stage__c = stepName  (currently at this step)
     *   – OR Current_Loan_Stage_Complete__c = stepName  (just completed it)
     *   – OR Current_Loan_Stage_Complete__c is an earlier step in same main stage (backend mark)
     *   – OR Loan_Stage__c is blank  (backward-compat: no stage set yet)
     *   – OR applicant has progressed past stepName in the journey
     */
    private static List<Applicant__c> getActiveApplicantsWithPrefixForStep(
            Map<String, Applicant__c> byTabLabel,
            String prefix,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey,
            String applicationCurrentStep) {
        List<Applicant__c> all = getApplicantsWithPrefix(byTabLabel, prefix);
        if (String.isBlank(stepName)) return all;

        List<Applicant__c> result = new List<Applicant__c>();
        for (Applicant__c app : all) {
            if (app == null || app.In_Active_Applicant__c == true) continue;
            if (isApplicantInScopeForStep(
                    app, stepName, mainStageName, stepOrderByKey, applicationCurrentStep)) {
                result.add(app);
            }
        }
        return result;
    }

    /**
     * Resolves which applicant type is currently being viewed (for setting currentView = true
     * on the correct sub-item at initial load).
     * Returns the tab-label of the first applicant in order who is at the current step
     * and has not yet completed it.  Falls back to 'Borrower' if present, then null.
     */
    private static String resolveCurrentViewApplicantType(
            Map<String, Applicant__c> applicantsByTabLabel,
            String currentStep,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey) {

        List<String> ordered = getOrderedApplicantTabLabels(applicantsByTabLabel);

       
        if (String.isNotBlank(currentStep)
                && STEP_DEDUPE_AND_ELIGIBILITY.equals(currentStep)) {
            for (String tabLabel : ordered) {
                Applicant__c app = applicantsByTabLabel.get(tabLabel);
                if (app == null || app.In_Active_Applicant__c == true) continue;
                if (isNavigatorBorrowerApplicant(app)) continue;
                if (!hasApplicantFinishedStep(
                        app, currentStep, mainStageName, stepOrderByKey, currentStep)
                    && isApplicantInScopeForStep(
                        app, currentStep, mainStageName, stepOrderByKey, currentStep)) {
                    return tabLabel;
                }
            }
        }

        // First: applicant at or queued on the current step and not finished it
        for (String tabLabel : ordered) {
            Applicant__c app = applicantsByTabLabel.get(tabLabel);
            if (app == null || app.In_Active_Applicant__c == true) continue;
            if (String.isNotBlank(currentStep)
                && !hasApplicantFinishedStep(
                    app, currentStep, mainStageName, stepOrderByKey, currentStep)
                && isApplicantInScopeForStep(
                    app, currentStep, mainStageName, stepOrderByKey, currentStep)) {
                return tabLabel;
            }
        }
        // Fallback: Borrower, then first in ordered list
        if (applicantsByTabLabel.containsKey('Borrower')) return 'Borrower';
        return ordered.isEmpty() ? null : ordered[0];
    }

    /** Returns all active tab-labels in display order: Borrower → CoBo1..3 → G1..3 → B1..10, then any others. */
    private static List<String> getOrderedApplicantTabLabels(Map<String, Applicant__c> byTabLabel) {
        List<String> ordered = new List<String>();
        Set<String> seen = new Set<String>();
        if (byTabLabel.containsKey('Borrower')) {
            ordered.add('Borrower');
            seen.add('Borrower');
        }
        for (Integer i = 1; i <= 3;  i++) {
            String k = 'CoBo' + i;
            if (byTabLabel.containsKey(k)) { ordered.add(k); seen.add(k); }
        }
        for (Integer i = 1; i <= 3;  i++) {
            String k = 'G' + i;
            if (byTabLabel.containsKey(k)) { ordered.add(k); seen.add(k); }
        }
        for (Integer i = 1; i <= 10; i++) {
            String k = 'B' + i;
            if (byTabLabel.containsKey(k)) { ordered.add(k); seen.add(k); }
        }
        for (String key : byTabLabel.keySet()) {
            if (key != null && !seen.contains(key)) ordered.add(key);
        }
        return ordered;
    }

    /** True when the applicant is in scope for the given step (at, queued, or completed it). */
    private static Boolean isApplicantRelevantForStep(Applicant__c app, String stepName) {
        return isApplicantRelevantForStep(app, stepName, null, null, null);
    }

    private static Boolean isApplicantRelevantForStep(
            Applicant__c app,
            String stepName,
            String mainStageName,
            String applicationSubStage,
            Map<String, Decimal> stepOrderByKey) {
        if (app == null || app.In_Active_Applicant__c == true) return false;
        if (String.isBlank(stepName)) return true;
        if (String.isBlank(app.Loan_Stage__c)) return true;
        if (stepName.equalsIgnoreCase(app.Loan_Stage__c.trim())) {
            if (String.isBlank(mainStageName) || stepOrderByKey == null) return true;
            return applicantStageValueAppliesToMainStage(
                app.Loan_Stage__c, mainStageName, applicationSubStage, stepOrderByKey);
        }
        if (String.isNotBlank(app.Current_Loan_Stage_Complete__c)
                && stepName.equalsIgnoreCase(app.Current_Loan_Stage_Complete__c.trim())) {
            if (String.isBlank(mainStageName) || stepOrderByKey == null) return true;
            return applicantStageValueAppliesToMainStage(
                app.Current_Loan_Stage_Complete__c, mainStageName, applicationSubStage, stepOrderByKey);
        }
        return false;
    }

    /** First applicant tab label (in display order) who has not yet finished stepName. */
    private static String getFirstIncompleteApplicantTabLabel(
            Map<String, Applicant__c> byTabLabel,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey,
            String applicationCurrentStep) {
        if (byTabLabel == null || byTabLabel.isEmpty()) return null;
        for (String tabLabel : getOrderedApplicantTabLabels(byTabLabel)) {
            Applicant__c app = byTabLabel.get(tabLabel);
            if (app != null && app.In_Active_Applicant__c != true
                    && isApplicantInScopeForStep(
                        app, stepName, mainStageName, stepOrderByKey, applicationCurrentStep)
                    && !hasApplicantFinishedStep(
                        app, stepName, mainStageName, stepOrderByKey, applicationCurrentStep)) {
                return tabLabel;
            }
        }
        return null;
    }

    /** Case-insensitive lookup of an applicant by tab-label token from stagePhrase. */
    private static Applicant__c findApplicantByTabLabel(
            Map<String, Applicant__c> byTabLabel, String token) {
        if (String.isBlank(token) || byTabLabel == null) return null;
        if (byTabLabel.containsKey(token)) return byTabLabel.get(token);
        for (String key : byTabLabel.keySet()) {
            if (key != null && key.equalsIgnoreCase(token.trim())) return byTabLabel.get(key);
        }
        return null;
    }

    /**
     * Resolves applicants for a role at a step: standard G1/CoBo1/B1 prefix keys first,
     * then falls back to Applicant_Type__c when tab labels use a non-standard format.
     * Only applicants at, on, or past this step are included (same rule as Dedupe and Eligibility).
     */
    private static List<Applicant__c> getRoleApplicantsForStep(
            Map<String, Applicant__c> byTabLabel,
            String prefix,
            String applicantTypeFallback,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey,
            String applicationCurrentStep) {

        List<Applicant__c> result = getActiveApplicantsWithPrefixForStep(
            byTabLabel, prefix, stepName, mainStageName, stepOrderByKey, applicationCurrentStep);
        if (!result.isEmpty() || String.isBlank(applicantTypeFallback)) return result;
        for (Applicant__c app : byTabLabel.values()) {
            if (app == null || app.In_Active_Applicant__c == true) continue;
            if (app.Is_Sub_Applicant__c == true) continue;
            if (!CustomerDedupeController.isApplicantTypeMatch(
                    String.valueOf(app.Applicant_Type__c), applicantTypeFallback)) continue;
            if (isApplicantInScopeForStep(
                    app, stepName, mainStageName, stepOrderByKey, applicationCurrentStep)) {
                result.add(app);
            }
        }
        return result;
    }

    // =========================================================================
    // Stage-phrase helper
    // =========================================================================

    /**
     * Format: StepName_MainStageName  (spaces → underscores)
     * Example: "Basic Details" + "QDE" → "Basic_Details_QDE"
     */
    private static String toStagePhrase(String stepName, String mainStageName) {
        if (String.isBlank(stepName) || String.isBlank(mainStageName)) return '';
        return stepName.replaceAll('\\s+', '_') + '_' + mainStageName.replaceAll('\\s+', '_');
    }

    // =========================================================================
    // processNextStageRequest – advance the application to the next step
    // =========================================================================

    /**
     * Result envelope returned by processNextStageRequest.
     * Shape mirrors SFLOS_DynamicStageNavigator.StageNavigationResult so that
     * stageMenu.js can consume it identically (isSuccess + navigationState.menuItems).
     */
    public class StageNavigationResult {
        @AuraEnabled public Boolean              isSuccess;
        @AuraEnabled public String               message;
        @AuraEnabled public String               newMainStage;
        @AuraEnabled public String               newStep;
        @AuraEnabled public Boolean              renderGuarantorScreen;
        @AuraEnabled public NavigationPanelState navigationState;

        /**
         * Optional applicant tab label set by an Override_Apex__c class to hint
         * which applicant should be highlighted after navigation.
         *
         * When an IStageOverride.execute() implementation sets this field and leaves
         * navigationState null, the framework auto-rebuilds the NavigationPanelState
         * and passes this label into buildNavStateWithHint so stageMenu.js can
         * perform a drill-down to the right applicant automatically.
         *
         * Example values: 'Borrower', 'CoBo1', 'G1', 'B1'
         */
        @AuraEnabled public String               preferredApplicantTabLabel;

        public StageNavigationResult() {
            this.isSuccess             = false;
            this.message               = '';
            this.renderGuarantorScreen = false;
        }
    }

    /**
     * Advances the loan application to the next stage step and returns a
     * fresh NavigationPanelState so the LWC can re-render immediately.
     *
     * stagePhrase format  (built by toStagePhrase):
     *   StepName_MainStageName                  – non-applicant step
     *   StepName_MainStageName_ApplicantToken   – applicant sub-step (e.g. _Borrower, _CoBo1)
     *
     * @param applicationId       Application__c record Id
     * @param currentStagePhrase  stagePhrase of the step the user just completed
     * @param currentLoanStageName  Applicant's Current_Loan_Stage_Complete__c override (optional)
     */
    @AuraEnabled(cacheable=false)
    public static StageNavigationResult processNextStageRequest(Id applicationId, String currentStagePhrase, String currentLoanStageName) {
        System.debug('@@@@ currentStagePhrase: ' + currentStagePhrase);
        System.debug('@@@@ currentLoanStageName: ' + currentLoanStageName);
        System.debug('@@@@ applicationId: ' + applicationId);
        StageNavigationResult result = new StageNavigationResult();
        if (applicationId == null || String.isBlank(currentStagePhrase)) {
            result.message = 'applicationId and currentStagePhrase are required.';
            return result;
        }

        try {
            Application__c app = queryApplication(applicationId);
            String effectivePortfolio = resolvePortfolio(app);
            if (String.isBlank(effectivePortfolio)) {
                result.message = 'Portfolio could not be determined from Application__c.Product__c.';
                return result;
            }

            List<Dynamic_Stage_Gate__mdt> raw     = queryStageNavigator(effectivePortfolio);
            List<Dynamic_Stage_Gate__mdt> records = filterByProductType(raw, effectivePortfolio, app.Sub_Product__c);

            // ── Resolve current CMT record + optional applicant token ─────────
            Dynamic_Stage_Gate__mdt currentRec = null;
            String applicantToken = null;
            for (Dynamic_Stage_Gate__mdt rec : records) {
                String recPhrase = toStagePhrase(rec.Steps_Sub_Menu_Name__c, rec.Main_Stage_Name__c);
                System.debug('@@@@ recPhrase: ' + recPhrase);
                if (currentStagePhrase.equals(recPhrase)) {
                    currentRec = rec;
                    break;
                }
                if (currentStagePhrase.startsWith(recPhrase + '_')) {
                    currentRec     = rec;
                    applicantToken = currentStagePhrase.substring(recPhrase.length() + 1);
                    break;
                }
            }

            if (currentRec == null) {
                result.message = 'No CMT record matched stagePhrase: ' + currentStagePhrase;
                return result;
            }

            // ── Override_Apex__c: let the named class decide the target step ────
            // The override class only returns newMainStage + newStep.
            // All post-routing logic (DML, applicant-based routing, nav-state
            // rebuild) is handled by the framework inside invokeOverrideApex.
            if (String.isNotBlank(currentRec.Override_Apex__c)) {
                return invokeOverrideApex(
                    currentRec.Override_Apex__c,
                    applicationId, currentStagePhrase, currentLoanStageName,
                    app, currentRec, effectivePortfolio, records
                );
            }

            Map<String, Applicant__c> byTabLabel = indexApplicantsByTabLabel(app.Applicants__r);
            Boolean hasApplicantSubstage = currentRec.is_Current_Step_Applicant_based__c == true;
            String  stepName             = currentRec.Steps_Sub_Menu_Name__c;
            String  completedStep        = String.isNotBlank(currentLoanStageName) ? currentLoanStageName : stepName;

            // Peek at the next record to know whether it also needs applicant sub-stages
            String resolvedForwardStep = resolveForwardStepAfterCurrentStage(app, currentRec);
            Dynamic_Stage_Gate__mdt nextRec = findRecordByStepAndMainStage(
                records, currentRec.Forward_Main_Stage_Name__c, resolvedForwardStep);
            Boolean nextHasApplicantSubstage = nextRec != null && nextRec.is_Current_Step_Applicant_based__c == true;

            System.debug('@@@@ nextHasApplicantSubstage: ' + nextHasApplicantSubstage);
            // ── Non-applicant step: advance straight away ─────────────────────
            if (!hasApplicantSubstage) {
                Map<String, Decimal> stepOrderByKey = buildStepOrderMap(records);
                System.debug('@@@@ stepOrderByKey: ' + stepOrderByKey);
                StageNavigationResult advanceResult = advanceApplicationStep(
                    app, currentRec, stepOrderByKey);
                if (!advanceResult.isSuccess) {
                    return advanceResult;
                }
                advanceResult.navigationState = buildNavStateAfterStepAdvance(
                    applicationId,
                    effectivePortfolio,
                    resolvedForwardStep,
                    nextHasApplicantSubstage,
                    app.Applicants__r);
                if (nextHasApplicantSubstage == true && String.isNotBlank(resolvedForwardStep)) {
                    advanceResult.renderGuarantorScreen = true;
                    advanceResult.preferredApplicantTabLabel = resolveFirstPreferredApplicantTabLabel(
                        indexApplicantsByTabLabel(app.Applicants__r));
                }
                System.debug('@@@@ advanceResult: ' + advanceResult);
                return advanceResult;
            }
            System.debug('@@@@ applicantToken: ' + applicantToken);

            // ── Applicant-based step ──────────────────────────────────────────
            if (String.isBlank(applicantToken)) {
                result.message = 'Applicant token required for an applicant-based step (Borrower, CoBo1, G1 …).';
                return result;
            }

            Applicant__c currentApplicant = 'Borrower'.equalsIgnoreCase(applicantToken)
                ? byTabLabel.get('Borrower')
                : findApplicantByTabLabel(byTabLabel, applicantToken);

            String completedApplicantTabLabel = resolveApplicantTabLabelFromToken(
                byTabLabel, applicantToken, currentApplicant);
            if (currentApplicant != null) {
                currentApplicant.Current_Loan_Stage_Complete__c = completedStep;
                if (nextHasApplicantSubstage && String.isNotBlank(resolvedForwardStep)) {
                    currentApplicant.Loan_Stage__c = resolvedForwardStep;
                }
                update currentApplicant;
            }
            app = queryApplication(applicationId);
            byTabLabel = indexApplicantsByTabLabel(app.Applicants__r);
            Map<String, Decimal> stepOrderByKey = buildStepOrderMap(records);

            // Sub-applicants route like a top-level non-Borrower applicant: NEXT pins the same
            // applicant forward to its own next step, producing a leaf-to-leaf journey.
            return routeToNextIncompleteApplicantOrAdvance(
                byTabLabel, completedStep, app, currentRec, applicationId,
                effectivePortfolio, stepOrderByKey, completedApplicantTabLabel);

        } catch (Exception e) {
            result.isSuccess = false;
            result.message   = 'processNextStageRequest error: ' + e.getMessage();
        }
        return result;
    }

    // ── Private helpers for processNextStageRequest ───────────────────────────

    /**
     * Framework handler for Override_Apex__c deviation steps.
     *
     * Responsibility split
     * ────────────────────────────────────────────────────────────────────────
     * Override class  →  deviation logic only:
     *                    • custom DML on related records, callouts, decisions
     *                    • sets result.newStep (required)
     *                    • sets result.newMainStage (optional, blank = same group)
     *                    • sets result.isSuccess = true on success
     *                    • may set result.preferredApplicantTabLabel to pin a
     *                      specific applicant (e.g. 'CoBo1') when the target step
     *                      is applicant-based; leave null for auto-detect.
     *
     * This method (framework) →  everything after the decision:
     *   1. DML  – advances Application__c.Sub_Stage__c (and Stage__c) to the
     *             override-specified target step.
     *   2. Bulk-update applicants sitting at the old step (same as default path).
     *   3. Applicant-based routing  – if the target CMT record has
     *             is_Current_Step_Applicant_based__c = true, resolves the first
     *             active applicant (Borrower → CoBo → G → B) and sets
     *             renderGuarantorScreen + preferredApplicantTabLabel so
     *             stageMenu.js drills down automatically.
     *   4. Nav-state rebuild  – calls buildNavStateWithHint() to return a fully
     *             populated NavigationPanelState with menuItems so stageMenu.js
     *             can re-render the menu immediately.
     *
     * Returns isSuccess = false when:
     *   • Type.forName() cannot resolve the class name
     *   • The class does not implement IStageOverride
     *   • The override class itself returns isSuccess = false
     *   • result.newStep is blank after the override call
     *   • Any unexpected exception occurs
     */
    private static StageNavigationResult invokeOverrideApex(
            String                        className,
            Id                            applicationId,
            String                        currentStagePhrase,
            String                        currentLoanStageName,
            Application__c                app,
            Dynamic_Stage_Gate__mdt       currentRec,
            String                        effectivePortfolio,
            List<Dynamic_Stage_Gate__mdt> records) {

        StageNavigationResult result = new StageNavigationResult();
        try {

            // ── 1. Resolve and validate the override class ────────────────────
            Map<String, IStageOverride> singleUseCache = new Map<String, IStageOverride>();
            IStageOverride handler = resolveOverrideInstance(className, singleUseCache);
            if (handler == null) {
                result.message = 'Override_Apex__c: class not found or does not implement '
                               + 'IStageOverride – "' + className + '". '
                               + 'Ensure the class is deployed and the API name is correct.';
                return result;
            }

            // ── 2. Ask the override class: where should we go next? ───────────
            StageNavigationResult decision = handler.execute(
                applicationId, currentStagePhrase, currentLoanStageName,
                app, currentRec, effectivePortfolio
            );

            if (decision == null || decision.isSuccess != true) {
                result.message = (decision != null && String.isNotBlank(decision.message))
                                 ? decision.message
                                 : 'Override_Apex__c "' + className + '" returned failure.';
                return result;
            }

            String targetStep      = decision.newStep;
            String targetMainStage = String.isNotBlank(decision.newMainStage)
                                     ? decision.newMainStage
                                     : currentRec.Forward_Main_Stage_Name__c;

            if (String.isBlank(targetStep)) {
                result.message = 'Override_Apex__c "' + className
                               + '" did not set newStep. Set result.newStep to the target step name.';
                return result;
            }

            Map<String, Decimal> stepOrderByKey = buildStepOrderMap(records);
            String compareMainStage = String.isNotBlank(targetMainStage)
                ? targetMainStage
                : currentRec.Main_Stage_Name__c;

            // Late-added applicants (e.g. Individual beneficiary from Dedupe) may route to an
            // earlier QDE step (Occupation) while the application already sits on Dedupe.
            // Advance only the current applicant — do not regress Application__c.Sub_Stage__c.
            if (shouldRouteOverrideToApplicantOnly(app, currentRec, targetStep, compareMainStage, stepOrderByKey)) {
                System.debug('DEBUG_61f25c|route=applicant-only|source=' + currentRec.Steps_Sub_Menu_Name__c
                    + '|target=' + targetStep + '|app=' + app.Sub_Stage__c);
                return routeOverrideToApplicantWhenAppAlreadyPastTarget(
                    applicationId,
                    effectivePortfolio,
                    currentStagePhrase,
                    app,
                    currentRec,
                    records,
                    decision,
                    targetStep,
                    compareMainStage);
            }

            System.debug('DEBUG_61f25c|route=full-override|source=' + currentRec.Steps_Sub_Menu_Name__c
                + '|target=' + targetStep + '|app=' + app.Sub_Stage__c
                + '|token=' + resolveApplicantTokenFromStagePhrase(currentStagePhrase, currentRec));

            // ── 3. DML: advance Application__c to the override target ─────────
            String previousStep = app.Sub_Stage__c;
            app.Sub_Stage__c    = targetStep;
            if (String.isNotBlank(targetMainStage)) app.Stage__c = targetMainStage;
            update app;

            // ── 4. Bulk-advance any applicants sitting at the old step ────────
            updateApplicantsForStepAdvance(
                app.Applicants__r, previousStep, targetStep,
                currentRec.Main_Stage_Name__c, stepOrderByKey,
                currentRec.is_Current_Step_Applicant_based__c == true);

            // ── 5. Find the target CMT record to detect applicant-based routing ─
            Dynamic_Stage_Gate__mdt targetRec =
                findRecordByStepAndMainStage(records, targetMainStage, targetStep);

            // ── 6. Applicant-based routing for the target step ────────────────
            String preferredTabLabel = decision.preferredApplicantTabLabel; // honour override hint
            Boolean routeToApplicant = false;

            if (targetRec != null && targetRec.is_Current_Step_Applicant_based__c == true) {
                routeToApplicant = true;
                if (String.isBlank(preferredTabLabel)) {
                    preferredTabLabel = resolveFirstPreferredApplicantTabLabel(
                        indexApplicantsByTabLabel(app.Applicants__r));
                }
            }

            // ── 7. Build fresh NavigationPanelState with optional hint ────────
            result.isSuccess             = true;
            result.newStep               = targetStep;
            result.newMainStage          = targetMainStage;
            result.renderGuarantorScreen = routeToApplicant;
            result.navigationState       = buildNavStateWithHint(
                applicationId, effectivePortfolio, preferredTabLabel
            );
            result.message = 'Override_Apex__c "' + className + '" advanced to: ' + targetStep;
            return result;

        } catch (Exception e) {
            result.isSuccess = false;
            result.message   = 'Override_Apex__c invocation error for "' + className
                             + '": ' + e.getMessage();
            return result;
        }
    }

    /**
     * Resolves an IStageOverride instance for the given class name, using the
     * supplied cache to avoid repeated Type.forName() + newInstance() calls.
     * Returns null (silently) when the class cannot be found or does not implement
     * IStageOverride, so the caller can treat a null as "no override available".
     */
    private static IStageOverride resolveOverrideInstance(
            String className, Map<String, IStageOverride> cache) {

        if (String.isBlank(className)) return null;
        if (cache.containsKey(className)) return cache.get(className);

        IStageOverride instance = null;
        try {
            Type t = Type.forName(className);
            if (t != null) {
                Object obj = t.newInstance();
                if (obj instanceof IStageOverride) {
                    instance = (IStageOverride) obj;
                }
            }
        } catch (Exception e) {
            // Leave instance null — caller treats null as "no visibility check"
        }
        cache.put(className, instance);  // cache null too, avoids retrying bad class names
        return instance;
    }

    /**
     * True when an override from an applicant-based step should advance only the current
     * applicant because the application has already moved past the override target
     * (e.g. app on Dedupe, Individual beneficiary KYC → Occupation).
     */
    private static Boolean shouldRouteOverrideToApplicantOnly(
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            String targetStep,
            String compareMainStage,
            Map<String, Decimal> stepOrderByKey) {
        if (currentRec == null
                || currentRec.is_Current_Step_Applicant_based__c != true
                || app == null
                || String.isBlank(app.Sub_Stage__c)
                || String.isBlank(targetStep)) {
            return false;
        }
        // CustomerDedupeNavigationOverride owns Dedupe hub routing — keep full override path.
        if (STEP_DEDUPE_AND_ELIGIBILITY.equalsIgnoreCase(currentRec.Steps_Sub_Menu_Name__c)) {
            return false;
        }
        if (targetStep.equalsIgnoreCase(app.Sub_Stage__c)) {
            // B1 finishing Occupation while the app is already on Dedupe — advance applicant only.
            if (STEP_OCCUPATION_DETAILS.equalsIgnoreCase(currentRec.Steps_Sub_Menu_Name__c)
                    && currentRec.is_Current_Step_Applicant_based__c == true) {
                return true;
            }
            return false;
        }
        Decimal appOrder = resolveStepCompositeOrder(stepOrderByKey, compareMainStage, app.Sub_Stage__c);
        Decimal targetOrder = resolveStepCompositeOrder(stepOrderByKey, compareMainStage, targetStep);
        if (appOrder == null || targetOrder == null) {
            return false;   
        }
        return appOrder > targetOrder;
    }

    private static Decimal resolveStepCompositeOrder(
            Map<String, Decimal> stepOrderByKey,
            String mainStageName,
            String stepName) {
        Decimal order = getStepCompositeOrderForMainStage(stepOrderByKey, mainStageName, stepName);
        return order != null ? order : getStepCompositeOrder(stepOrderByKey, mainStageName, stepName);
    }

    /**
     * Override path when the application has already reached or passed the target step
     * (e.g. app on Dedupe, Individual beneficiary KYC → Occupation). Updates only the
     * current applicant's Loan_Stage__c / Current_Loan_Stage_Complete__c.
     */
    private static StageNavigationResult routeOverrideToApplicantWhenAppAlreadyPastTarget(
            Id applicationId,
            String effectivePortfolio,
            String currentStagePhrase,
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            List<Dynamic_Stage_Gate__mdt> records,
            StageNavigationResult decision,
            String targetStep,
            String targetMainStage) {

        StageNavigationResult result = new StageNavigationResult();
        String completedStep = currentRec.Steps_Sub_Menu_Name__c;
        Map<String, Applicant__c> byTabLabel = indexApplicantsByTabLabel(app.Applicants__r);
        String applicantToken = resolveApplicantTokenFromStagePhrase(currentStagePhrase, currentRec);
        Applicant__c currentApplicant = resolveApplicantFromToken(byTabLabel, applicantToken);
        String preferredTabLabel = String.isNotBlank(decision.preferredApplicantTabLabel)
            ? decision.preferredApplicantTabLabel
            : resolveApplicantTabLabelFromToken(byTabLabel, applicantToken, currentApplicant);

        Dynamic_Stage_Gate__mdt targetRec =
            findRecordByStepAndMainStage(records, targetMainStage, targetStep);
        Boolean nextHasApplicantSubstage = targetRec != null
            && targetRec.is_Current_Step_Applicant_based__c == true;

        if (currentApplicant != null) {
            markApplicantStepComplete(
                currentApplicant, completedStep, nextHasApplicantSubstage, targetStep);
        }

        result.isSuccess = true;
        result.newStep = targetStep;
        result.newMainStage = targetMainStage;
        result.renderGuarantorScreen = nextHasApplicantSubstage;
        result.preferredApplicantTabLabel = preferredTabLabel;
        result.navigationState = buildNavStateWithApplicantAndStepHint(
            applicationId, preferredTabLabel, targetStep);
        result.message = String.isNotBlank(preferredTabLabel)
            ? 'Applicant ' + preferredTabLabel + ' advanced to ' + targetStep + '.'
            : 'Applicant advanced to ' + targetStep + '.';
        return result;
    }

    private static Applicant__c resolveApplicantFromToken(
            Map<String, Applicant__c> byTabLabel,
            String applicantToken) {
        if (byTabLabel == null || String.isBlank(applicantToken)) {
            return null;
        }
        if ('Borrower'.equalsIgnoreCase(applicantToken.trim())) {
            return byTabLabel.get('Borrower');
        }
        return findApplicantByTabLabel(byTabLabel, applicantToken);
    }

    private static String resolveApplicantTokenFromStagePhrase(
            String currentStagePhrase,
            Dynamic_Stage_Gate__mdt currentRec) {
        if (String.isBlank(currentStagePhrase) || currentRec == null) {
            return null;
        }
        String recPhrase = toStagePhrase(
            currentRec.Steps_Sub_Menu_Name__c,
            currentRec.Main_Stage_Name__c
        );
        if (currentStagePhrase.startsWith(recPhrase + '_')) {
            return currentStagePhrase.substring(recPhrase.length() + 1);
        }
        return null;
    }

    /** Maps Application__c.Product__c API values to the portfolio string used by CMT. */
    private static String resolvePortfolio(Application__c app) {
        if (String.isBlank(app.Product__c)) return null;
        
        Map<String, String> valueToPortfolio = new Map<String, String>{
            '2W'     => 'Wheels',
            '4W'     => 'Wheels',
            'CV'     => 'Wheels',
            'Wheels' => 'Wheels',
            'PL'     => 'Personal Loan'
        };
        String mapped = valueToPortfolio.get(app.Product__c);
        return String.isNotBlank(mapped) ? mapped : app.Product__c;
    }

    /** Finds a CMT record by exact Main_Stage_Name__c + Steps_Sub_Menu_Name__c (case-insensitive). */
    private static Dynamic_Stage_Gate__mdt findRecordByStepAndMainStage(
            List<Dynamic_Stage_Gate__mdt> records, String mainStageName, String stepName) {
        if (String.isBlank(mainStageName) || String.isBlank(stepName)) return null;
        for (Dynamic_Stage_Gate__mdt rec : records) {
            if (mainStageName.equalsIgnoreCase(rec.Main_Stage_Name__c)
                    && stepName.equalsIgnoreCase(rec.Steps_Sub_Menu_Name__c)) {
                return rec;
            }
        }
        return null;
    }

    /**
     * Stamps Current_Loan_Stage_Complete__c on the applicant.
     * When the next step also has applicant sub-stages, also advances Loan_Stage__c.
     */
    private static void markApplicantStepComplete(
            Applicant__c app, String completedStep,
            Boolean nextHasApplicantSubstage, String nextStepName) {
        if (app == null) return;
        app.Current_Loan_Stage_Complete__c = completedStep;
        if (nextHasApplicantSubstage && String.isNotBlank(nextStepName)) {
            app.Loan_Stage__c = nextStepName;
        }
        update app;
    }

    /**
     * Advances Application__c.Sub_Stage__c (and Stage__c) using the CMT forward fields.
     * Journey applicants are bulk-synced via updateApplicantsForStepAdvance.
     */
    private static StageNavigationResult advanceApplicationStep(
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            Map<String, Decimal> stepOrderByKey) {
        StageNavigationResult result = new StageNavigationResult();
        String nextStep      = resolveForwardStepAfterCurrentStage(app, currentRec);
        String nextMainStage = currentRec.Forward_Main_Stage_Name__c;

        if (String.isBlank(nextStep)) {
            result.message = 'No Forward_Steps_Name__c defined for: ' + currentRec.Steps_Sub_Menu_Name__c;
            return result;
        }

        String previousStep = app.Sub_Stage__c;
        app.Sub_Stage__c   = nextStep;
        if (String.isNotBlank(nextMainStage)) app.Stage__c = nextMainStage;
        update app;

        updateApplicantsForStepAdvance(
            app.Applicants__r, previousStep, nextStep,
            currentRec.Main_Stage_Name__c, stepOrderByKey,
            false);

        result.isSuccess    = true;
        result.newStep      = nextStep;
        result.newMainStage = String.isNotBlank(nextMainStage) ? nextMainStage : app.Stage__c;
        result.message      = 'Advanced to: ' + nextStep;
        return result;
    }

    /**
     * Bulk-syncs journey applicants when a non-applicant step advances.
     * Sets Current_Loan_Stage_Complete__c to the step just completed and, when scoped
     * appropriately, advances Loan_Stage__c to the forward step.
     */
    private static Boolean isJourneyApplicantForStageSync(Applicant__c a) {
        if (a == null || a.In_Active_Applicant__c == true) return false;
        return !'Reference'.equalsIgnoreCase(String.valueOf(a.Applicant_Type__c));
    }

    private static void updateApplicantsForStepAdvance(
            List<Applicant__c> applicants,
            String previousStep,
            String nextStep,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey,
            Boolean skipForApplicantBasedStep) {
        if (skipForApplicantBasedStep == true) return;
        if (applicants == null || String.isBlank(previousStep) || String.isBlank(nextStep)) return;
        if (previousStep.equalsIgnoreCase(nextStep)) return;

        List<Applicant__c> toUpdate = new List<Applicant__c>();
        for (Applicant__c a : applicants) {
            if (!isJourneyApplicantForStageSync(a)) continue;

            Boolean changed = false;
            String currentComplete = a.Current_Loan_Stage_Complete__c != null
                ? a.Current_Loan_Stage_Complete__c.trim() : '';
            if (!previousStep.equalsIgnoreCase(currentComplete)) {
                a.Current_Loan_Stage_Complete__c = previousStep;
                changed = true;
            }

            Boolean shouldAdvanceLoanStage = String.isBlank(a.Loan_Stage__c)
                || previousStep.equalsIgnoreCase(a.Loan_Stage__c)
                || (String.isNotBlank(a.Loan_Stage__c)
                    && applicantStageValueAppliesToMainStage(
                        a.Loan_Stage__c, mainStageName, previousStep, stepOrderByKey)
                    && !hasApplicantPassedStep(
                        a, previousStep, mainStageName, stepOrderByKey, previousStep));

            if (shouldAdvanceLoanStage && !nextStep.equalsIgnoreCase(a.Loan_Stage__c)) {
                a.Loan_Stage__c = nextStep;
                changed = true;
            }

            if (changed) toUpdate.add(a);
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    /** Returns the first tab-label with the given prefix that exists in byTabLabel. */
    private static String getFirstApplicantLabelWithPrefix(
            Map<String, Applicant__c> byTabLabel, String prefix) {
        Integer max = 'B'.equals(prefix) ? 10 : 3;
        for (Integer i = 1; i <= max; i++) {
            String key = prefix + i;
            if (byTabLabel.containsKey(key)) return key;
        }
        return null;
    }

    /** Borrower → CoBo → G → B, first present tab label. */
    private static String resolveFirstPreferredApplicantTabLabel(Map<String, Applicant__c> byTabLabel) {
        if (byTabLabel == null || byTabLabel.isEmpty()) return null;
        if (byTabLabel.containsKey('Borrower')) return 'Borrower';
        for (String prefix : new List<String>{ 'CoBo', 'G', 'B' }) {
            String label = getFirstApplicantLabelWithPrefix(byTabLabel, prefix);
            if (String.isNotBlank(label)) return label;
        }
        return null;
    }

    /**
     * Builds a fresh NavigationPanelState (via getMenuForPortfolio) and stamps the
     * preferred-applicant hint fields so the LWC can auto-drill-down.
     */
    private static NavigationPanelState buildNavStateWithHint(
            Id applicationId, String portfolio, String preferredTabLabel) {
        NavigationPanelState state = getMenuForPortfolio(portfolio, applicationId);
        if (String.isBlank(preferredTabLabel) || !state.isSuccess) return state;
        state.preferredApplicantTabLabel = preferredTabLabel;
        Application__c fresh = queryApplication(applicationId);
        Map<String, Applicant__c> freshMap = indexApplicantsByTabLabel(fresh.Applicants__r);
        Applicant__c preferred = findApplicantByTabLabel(freshMap, preferredTabLabel);
        if (preferred != null) {
            state.preferredApplicantId   = preferred.Id;
            state.preferredApplicantName = formatApplicantDisplayName(preferred);
        }
        if (String.isNotBlank(state.preferredViewStepName)) {
            applyPreferredNavigationHints(state);
        }
        return state;
    }

    /**
     * Public bridge for external callers (e.g. CustomerDedupeNavigationOverride).
     * Builds a NavigationPanelState with an applicant hint and, optionally, pins the
     * currentView to a specific step.  Equivalent to:
     *   1. buildNavStateWithHint(applicationId, portfolio, preferredTabLabel)
     *   2. state.preferredViewStepName = preferredViewStep
     *   3. applyPreferredNavigationHints(state)
     */
    public static NavigationPanelState buildNavStateWithApplicantAndStepHint(
            Id applicationId, String preferredTabLabel, String preferredViewStep) {
        Application__c app  = queryApplication(applicationId);
        String portfolio    = resolvePortfolio(app);
        NavigationPanelState state = buildNavStateWithHint(applicationId, portfolio, preferredTabLabel);
        if (state != null && state.isSuccess && String.isNotBlank(preferredViewStep)) {
            state.preferredViewStepName = preferredViewStep;
            state.preferredViewMainStageName = app.Stage__c;
            applyPreferredNavigationHints(state);
        }
        return state;
    }

    /**
     * Route to an existing role's Multi-Grid (listOfApplicants) WITHOUT creating a
     * new top-level applicant. Used by the Dedupe "+ Add Sub-<Role>" button so the user can add
     * sub-applicants against existing NI tiles. roleLabel = 'Guarantor' | 'Co-Borrower' | 'Beneficiary'.
     */
    @AuraEnabled(cacheable=false)
    public static StageNavigationResult routeToRoleGrid(Id applicationId, String roleLabel, String stepName) {
        StageNavigationResult result = new StageNavigationResult();
        try {
            String step = String.isNotBlank(stepName) ? stepName : 'Basic Details';
            NavigationPanelState navState = buildNavStateWithGroupRoleAndStepHint(applicationId, roleLabel, step);
            if (navState == null || navState.isSuccess != true) {
                result.isSuccess = false;
                result.message = 'Could not resolve the ' + roleLabel + ' applicant group.';
                return result;
            }
            result.isSuccess                  = true;
            result.renderGuarantorScreen      = false;
            result.preferredApplicantTabLabel = roleLabel;
            result.navigationState            = navState;
            result.message                    = 'Routing to applicant group: ' + roleLabel;
        } catch (Exception e) {
            result.isSuccess = false;
            result.message   = 'routeToRoleGrid: ' + e.getMessage();
        }
        return result;
    }

    /**
     * Pins currentView to a Multi-Grid role group (e.g. Guarantor) without an applicant drill-down hint.
     * Used when NEXT on a grouped step should land on listOfApplicants, not a specific G1/G2 screen.
     */
    private static NavigationPanelState buildNavStateWithGroupRoleAndStepHint(
            Id applicationId, String groupRoleLabel, String preferredViewStep) {
        Application__c app  = queryApplication(applicationId);
        String portfolio      = resolvePortfolio(app);
        NavigationPanelState state = getMenuForPortfolio(portfolio, applicationId);
        if (state == null || !state.isSuccess || String.isBlank(groupRoleLabel)) {
            return state;
        }
        state.preferredApplicantTabLabel = groupRoleLabel;
        if (String.isNotBlank(preferredViewStep)) {
            state.preferredViewStepName = preferredViewStep;
            state.preferredViewMainStageName = app.Stage__c;
            applyPreferredNavigationHints(state);
        }
        return state;
    }

    /**
     * Pins currentView to preferredViewStepName + preferredApplicantTabLabel (e.g. Basic Details + G2).
     */
    private static void applyPreferredNavigationHints(NavigationPanelState state) {
        if (state == null || !state.isSuccess || state.menuItems == null) {
            return;
        }
        String stepName = state.preferredViewStepName;
        String tabLabel = state.preferredApplicantTabLabel;
        String mainStageName = state.preferredViewMainStageName;
        if (String.isBlank(stepName) || String.isBlank(tabLabel)) {
            return;
        }

        clearMenuCurrentViews(state.menuItems);

        for (NavigationMenuItem parent : state.menuItems) {
            if (!menuItemMatchesStepName(parent, stepName, mainStageName)) {
                continue;
            }
            if (parent.subItems == null || parent.subItems.isEmpty()) {
                parent.currentView = true;
                if (String.isNotBlank(parent.stagePhrase)) {
                    state.currentStagePhrase = parent.stagePhrase;
                }
                return;
            }
            for (NavigationMenuItem sub : parent.subItems) {
                // Multi-Grid group (2+ guarantors/co-borrowers): open listOfApplicants, not a leaf applicant.
                if (sub.isGroupItem == true && state.preferredApplicantId == null
                        && (tabLabel.equalsIgnoreCase(sub.label)
                            || tabLabel.equalsIgnoreCase(sub.applicantType))) {
                    sub.currentView = true;
                    parent.status = STATUS_ACTIVE;
                    if (String.isNotBlank(sub.stagePhrase)) {
                        state.currentStagePhrase = sub.stagePhrase;
                    }
                    return;
                }
                if (sub.isGroupItem == true && groupSubItemContainsApplicant(sub, tabLabel, state.preferredApplicantId)) {
                    sub.currentView = true;
                    parent.status = STATUS_ACTIVE;
                    if (String.isNotBlank(sub.stagePhrase)) {
                        state.currentStagePhrase = sub.stagePhrase;
                    }
                    return;
                }
                if (applicantSubItemMatchesTab(sub, tabLabel, state.preferredApplicantId)) {
                    sub.currentView = true;
                    parent.status = STATUS_ACTIVE;
                    if (String.isNotBlank(sub.stagePhrase)) {
                        state.currentStagePhrase = sub.stagePhrase;
                    }
                    return;
                }
            }
        }
    }

    private static Boolean groupSubItemContainsApplicant(
            NavigationMenuItem groupItem,
            String tabLabel,
            Id preferredApplicantId) {
        if (groupItem == null || groupItem.applicants == null) {
            return false;
        }
        for (ApplicantInfo info : groupItem.applicants) {
            if (info == null || info.inActiveApplicant == true) {
                continue;
            }
            if (applicantInfoMatches(info, tabLabel, preferredApplicantId)) {
                return true;
            }
            // Recurse into nested IN sub-applicants so a sub drill-down still pins the role grid.
            if (info.subApplicants != null) {
                for (ApplicantInfo sub : info.subApplicants) {
                    if (sub == null || sub.inActiveApplicant == true) continue;
                    if (applicantInfoMatches(sub, tabLabel, preferredApplicantId)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    private static Boolean applicantInfoMatches(
            ApplicantInfo info, String tabLabel, Id preferredApplicantId) {
        if (info == null) {
            return false;
        }
        if (preferredApplicantId != null && info.applicantId == preferredApplicantId) {
            return true;
        }
        return String.isNotBlank(tabLabel) && String.isNotBlank(info.tabLabel)
            && tabLabel.equalsIgnoreCase(info.tabLabel.trim());
    }

    /** Soft-delete (inactivate) an applicant — used from multi-applicant card grid. */
    @AuraEnabled
    public static Map<String, Object> softDeleteApplicant(Id applicantId) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);
        if (applicantId == null) {
            result.put('message', 'applicantId is required.');
            return result;
        }
        try {
            List<Applicant__c> apps = [
                SELECT Id, In_Active_Applicant__c
                FROM Applicant__c
                WHERE Id = :applicantId
                LIMIT 1
            ];
            if (apps.isEmpty()) {
                result.put('message', 'Applicant not found.');
                return result;
            }
            apps[0].In_Active_Applicant__c = true;
            update apps[0];
            result.put('isSuccess', true);
            result.put('message', 'Applicant removed successfully.');
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }
        return result;
    }

    private static void clearMenuCurrentViews(List<NavigationMenuItem> items) {
        if (items == null) {
            return;
        }
        for (NavigationMenuItem item : items) {
            item.currentView = false;
            if (item.subItems != null && !item.subItems.isEmpty()) {
                clearMenuCurrentViews(item.subItems);
            }
        }
    }

    private static Boolean menuItemMatchesStepName(
            NavigationMenuItem item, String stepName, String mainStageName) {
        if (item == null || String.isBlank(stepName)) {
            return false;
        }
        Boolean stepMatch = stepName.equalsIgnoreCase(item.tab) || stepName.equalsIgnoreCase(item.label);
        if (!stepMatch) {
            return false;
        }
        if (String.isBlank(mainStageName)) {
            return true;
        }
        return String.isNotBlank(item.groupName) && mainStageName.equalsIgnoreCase(item.groupName);
    }

    private static Boolean applicantSubItemMatchesTab(
            NavigationMenuItem sub,
            String tabLabel,
            Id preferredApplicantId) {
        if (sub == null || String.isBlank(tabLabel)) {
            return false;
        }
        if (preferredApplicantId != null && sub.applicantId == preferredApplicantId) {
            return true;
        }
        if (String.isNotBlank(sub.applicantType) && sub.applicantType.equalsIgnoreCase(tabLabel.trim())) {
            return true;
        }
        if (String.isNotBlank(sub.label) && sub.label.equalsIgnoreCase(tabLabel.trim())) {
            return true;
        }
        if (String.isNotBlank(sub.stagePhrase)) {
            String token = tabLabel.trim().replaceAll('\\s+', '_');
            return sub.stagePhrase.contains('_' + token);
        }
        return false;
    }

  /**
     * When 2+ applicants share a role at a non-QDE step, NEXT should open the Multi-Grid
     * (listOfApplicants), not drill into the first incomplete leaf (e.g. G1).
     */
    private static String resolveGroupedRoleLabelAtStep(
            Map<String, Applicant__c> byTabLabel,
            Applicant__c nextApplicant,
            String stepName,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey,
            String applicationCurrentStep) {
        if (nextApplicant == null || useExpandedQdeApplicantMenuScope(stepName, mainStageName)) {
            return null;
        }
        String prefix = resolveRolePrefixForApplicant(nextApplicant);
        String displayLabel = resolveRoleDisplayLabelForPrefix(prefix);
        if (String.isBlank(prefix) || String.isBlank(displayLabel)) {
            return null;
        }
        List<Applicant__c> roleApplicants = getRoleApplicantsForStep(
            byTabLabel, prefix, displayLabel, stepName, mainStageName, stepOrderByKey, applicationCurrentStep);
        return roleApplicants.size() > 1 ? displayLabel : null;
    }

    private static String resolveRolePrefixForApplicant(Applicant__c app) {
        if (app == null) {
            return null;
        }
        String tab = String.isNotBlank(app.Applicant_Tab_Label__c) ? app.Applicant_Tab_Label__c.trim() : '';
        if (tab.startsWith('CoBo')) {
            return 'CoBo';
        }
        if (tab.length() >= 2 && tab.startsWith('G') && tab.substring(1).isNumeric()) {
            return 'G';
        }
        if (tab.length() >= 2 && tab.startsWith('B') && tab.substring(1).isNumeric()) {
            return 'B';
        }
        String applicantType = String.valueOf(app.Applicant_Type__c);
        if (CustomerDedupeController.isApplicantTypeMatch(applicantType, 'Co-Borrower')) {
            return 'CoBo';
        }
        if (CustomerDedupeController.isApplicantTypeMatch(applicantType, 'Guarantor')) {
            return 'G';
        }
        if (CustomerDedupeController.isApplicantTypeMatch(applicantType, 'Beneficiary')) {
            return 'B';
        }
        return null;
    }

    private static String resolveRoleDisplayLabelForPrefix(String prefix) {
        if ('CoBo'.equals(prefix)) {
            return 'Co-Borrower';
        }
        if ('G'.equals(prefix)) {
            return 'Guarantor';
        }
        if ('B'.equals(prefix)) {
            return 'Beneficiary';
        }
        return null;
    }

    /** Routes to the next applicant who has not completed stepName, or advances the application when all are done. */
    private static StageNavigationResult routeToNextIncompleteApplicantOrAdvance(
            Map<String, Applicant__c> byTabLabel,
            String stepName,
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            Id applicationId,
            String effectivePortfolio,
            Map<String, Decimal> stepOrderByKey,
            String completedApplicantTabLabel) {

        StageNavigationResult result = new StageNavigationResult();
        String nextTab = getFirstIncompleteApplicantTabLabel(
            byTabLabel, stepName, currentRec.Main_Stage_Name__c, stepOrderByKey, app.Sub_Stage__c);
        if (String.isNotBlank(nextTab)) {
            Applicant__c nextApplicant = findApplicantByTabLabel(byTabLabel, nextTab);
            String groupRoleLabel = resolveGroupedRoleLabelAtStep(
                byTabLabel, nextApplicant, stepName, currentRec.Main_Stage_Name__c,
                stepOrderByKey, app.Sub_Stage__c);
            result.isSuccess = true;
            if (String.isNotBlank(groupRoleLabel)) {
                result.renderGuarantorScreen = false;
                result.message               = 'Routing to applicant group: ' + groupRoleLabel;
                result.navigationState       = buildNavStateWithGroupRoleAndStepHint(
                    applicationId, groupRoleLabel, stepName);
            } else {
                result.renderGuarantorScreen = true;
                result.message               = 'Routing to next applicant: ' + nextTab;
                result.navigationState       = buildNavStateWithApplicantAndStepHint(
                    applicationId, nextTab, stepName);
            }
            return result;
        }

        String forwardStep = resolveForwardStepAfterCurrentStage(app, currentRec);
        if (isApplicationAtOrPastStep(
                app.Sub_Stage__c, forwardStep, currentRec.Main_Stage_Name__c, stepOrderByKey)) {
            result.isSuccess    = true;
            result.newStep      = String.isNotBlank(forwardStep) ? forwardStep : app.Sub_Stage__c;
            result.newMainStage = app.Stage__c;
            result.message      = 'All applicants completed: ' + stepName;

            if (String.isNotBlank(forwardStep) && String.isNotBlank(completedApplicantTabLabel)) {
                NavigationPanelState navState = buildNavStateWithHint(
                    applicationId, effectivePortfolio, completedApplicantTabLabel);
                if (navState != null && navState.isSuccess == true) {
                    navState.preferredViewStepName = forwardStep;
                    navState.preferredViewMainStageName = app.Stage__c;
                    applyPreferredNavigationHints(navState);
                    result.renderGuarantorScreen      = true;
                    result.preferredApplicantTabLabel   = completedApplicantTabLabel;
                    result.navigationState              = navState;
                    result.message                      = 'Continue ' + forwardStep
                        + ' for ' + completedApplicantTabLabel + '.';
                    return result;
                }
            }
            result.navigationState = getMenuForPortfolio(effectivePortfolio, applicationId);
            return result;
        }
        return doAdvanceAndReturn(
            app, currentRec, applicationId, effectivePortfolio, stepOrderByKey);
    }

    /**
     * Resolves the next step when advancing from the current CMT row.
     * Additional Documents uses vehicle type (Invoice vs Vehicle Inspection);
     * all other steps use Forward_Steps_Name__c from metadata.
     */
    private static String resolveForwardStepAfterCurrentStage(
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec) {
        if (currentRec == null) {
            return null;
        }
        if ('Additional Documents'.equalsIgnoreCase(currentRec.Steps_Sub_Menu_Name__c)
                && app != null) {
            return AssetDetailsStageNavigationHandler.resolveTargetStepAfterAdditionalDocuments(app.Id);
        }
        return currentRec.Forward_Steps_Name__c;
    }

    private static String resolveApplicantTabLabelFromToken(
            Map<String, Applicant__c> byTabLabel,
            String applicantToken,
            Applicant__c currentApplicant) {
        if (currentApplicant != null && String.isNotBlank(currentApplicant.Applicant_Tab_Label__c)) {
            return currentApplicant.Applicant_Tab_Label__c;
        }
        if (String.isBlank(applicantToken) || byTabLabel == null) {
            return applicantToken;
        }
        Applicant__c resolved = findApplicantByTabLabel(byTabLabel, applicantToken);
        if (resolved != null && String.isNotBlank(resolved.Applicant_Tab_Label__c)) {
            return resolved.Applicant_Tab_Label__c;
        }
        return applicantToken;
    }

    /** True when Application__c.Sub_Stage__c is already at or beyond targetStep. */
    private static Boolean isApplicationAtOrPastStep(
            String appSubStage,
            String targetStep,
            String mainStageName,
            Map<String, Decimal> stepOrderByKey) {
        if (String.isBlank(targetStep)) return true;
        if (String.isBlank(appSubStage)) return false;
        if (targetStep.equalsIgnoreCase(appSubStage)) return true;
        if (stepOrderByKey == null || stepOrderByKey.isEmpty()) {
            return false;
        }
        Decimal targetOrder = getStepCompositeOrder(stepOrderByKey, mainStageName, targetStep);
        Decimal appOrder    = getStepCompositeOrder(stepOrderByKey, mainStageName, appSubStage);
        if (targetOrder == null || appOrder == null) return false;
        return appOrder >= targetOrder;
    }

    /**
     * Builds navigation state after Application__c advances to forwardStepName.
     * When the forward step is applicant-based, pins currentView to the first present
     * applicant in display order (Borrower → CoBo → G → B); otherwise rebuilds the default menu.
     */
    private static NavigationPanelState buildNavStateAfterStepAdvance(
            Id applicationId,
            String portfolio,
            String forwardStepName,
            Boolean forwardStepIsApplicantBased,
            List<Applicant__c> applicants) {
        if (forwardStepIsApplicantBased == true && String.isNotBlank(forwardStepName)) {
            String preferredTabLabel = resolveFirstPreferredApplicantTabLabel(
                indexApplicantsByTabLabel(applicants));
            return buildNavStateWithApplicantAndStepHint(
                applicationId, preferredTabLabel, forwardStepName);
        }
        return getMenuForPortfolio(portfolio, applicationId);
    }

    /** Convenience: advance the step and return a fresh nav state pinned to the forward step. */
    private static StageNavigationResult doAdvanceAndReturn(
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            Id applicationId,
            String portfolio,
            Map<String, Decimal> stepOrderByKey) {
        StageNavigationResult result = advanceApplicationStep(app, currentRec, stepOrderByKey);
        if (result.isSuccess) {
            Application__c fresh = queryApplication(applicationId);
            String effectivePortfolio = String.isNotBlank(portfolio)
                ? portfolio : resolvePortfolio(fresh);
            List<Dynamic_Stage_Gate__mdt> records = filterByProductType(
                queryStageNavigator(effectivePortfolio), effectivePortfolio, fresh.Sub_Product__c);
            Dynamic_Stage_Gate__mdt nextRec = findRecordByStepAndMainStage(
                records, result.newMainStage, result.newStep);
            Boolean nextApplicantBased = nextRec != null
                && nextRec.is_Current_Step_Applicant_based__c == true;
            result.navigationState = buildNavStateAfterStepAdvance(
                applicationId, effectivePortfolio, result.newStep,
                nextApplicantBased, fresh.Applicants__r);
            if (nextApplicantBased == true) {
                result.renderGuarantorScreen = true;
                result.preferredApplicantTabLabel = resolveFirstPreferredApplicantTabLabel(
                    indexApplicantsByTabLabel(fresh.Applicants__r));
            }
        }
        return result;
    }

    /**
     * First applicant sub-step under QDE (typically Basic Details) from stage navigator CMT.
     */
    public static Map<String, String> getInitialQdeStepForApplication(Id applicationId) {
        Map<String, String> out = new Map<String, String>{
            'targetStep'      => STEP_BASIC_DETAILS,
            'targetMainStage' => MAIN_STAGE_QDE
        };
        if (applicationId == null) {
            return out;
        }

        Application__c app = queryApplication(applicationId);
        String portfolio = resolvePortfolio(app);
        if (String.isBlank(portfolio)) {
            return out;
        }

        List<Dynamic_Stage_Gate__mdt> records = filterByProductType(
            queryStageNavigator(portfolio), portfolio, app.Sub_Product__c
        );
        for (Dynamic_Stage_Gate__mdt rec : records) {
            if (MAIN_STAGE_QDE.equals(rec.Main_Stage_Name__c)
                    && rec.is_Current_Step_Applicant_based__c == true
                    && String.isNotBlank(rec.Steps_Sub_Menu_Name__c)) {
                out.put('targetStep', rec.Steps_Sub_Menu_Name__c);
                out.put('targetMainStage', rec.Main_Stage_Name__c);
                break;
            }
        }
        return out;
    }

}