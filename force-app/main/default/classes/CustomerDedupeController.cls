public with sharing class CustomerDedupeController implements Callable {

    private static final String DEDUPE_STEP_NAME = 'Dedupe and Eligibility';
    private static final String CHECK_ELIGIBILITY_SUCCESS_MESSAGE = 'Check Eligibility Success';
    private static final String STEP_LEAD_DETAILS = 'Lead Details';
    private static final String STEP_BASIC_DETAILS = 'Basic Details';
    private static final String STEP_KYC_DETAILS = 'KYC Details';
    private static final Set<String> STAGES_BEFORE_DEDUPE = new Set<String>{
        STEP_LEAD_DETAILS, STEP_BASIC_DETAILS, STEP_KYC_DETAILS
    };
    private static final Set<String> ADDITIONAL_APPLICANT_TYPES = new Set<String>{
        'Guarantor', 'Co-Borrower', 'Beneficiary'
    };
    private static final String APPLICANT_TYPE_CO_BORROWER = 'Co-Borrower';

    /** True when application is Two-Wheeler (Co-Borrower path). Checks Sub_Product__c then Product__c. */
    private static Boolean resolveIsTwoWheeler(String product, String subProduct) {
        if (String.isNotBlank(subProduct)) {
            String sub = subProduct.trim().toLowerCase();
            if (sub.contains('two wheeler') || sub.contains('2w') || sub.contains('tw')) {
                return true;
            }
        }
        if (String.isNotBlank(product)) {
            String pt = product.trim().toLowerCase();
            return pt == '2w' || pt == 'tw' || pt.contains('two wheeler');
        }
        return false;
    }

    private static final String ACTION_GET_PAGE_DATA = 'getPageData';
    private static final String ACTION_SAVE_APPLICANT_SELECTIONS = 'saveApplicantSelections';
    private static final String ACTION_MARK_MATCH_AS_VALID = 'markMatchAsValid';
    private static final String ACTION_MARK_MATCH_AS_INVALID = 'markMatchAsInvalid';
    private static final String ACTION_REMOVE_APPLICANT = 'removeApplicant';
    private static final String ACTION_RUN_CHECK_ELIGIBILITY_STAGE = 'runCheckEligibilityIntegrationStage';
    private static final String ACTION_RUN_DEDUPE_FORWARD_STAGE = 'runDedupeForwardIntegrationStage';
    private static final String ACTION_GET_EXISTING_EMI = 'getExistingEmiDetails';
    private static final String ACTION_GET_EXPOSURE_DETAILS = 'getExposureDetails';
    private static final String ACTION_VALIDATE_ALL_APPLICANTS = 'validateAllApplicantsDedupeComplete';
    private static final String ACTION_VALIDATE_NI_CONSTITUTION = 'validateNiConstitutionForApplication';
    private static final String APPLICANT_TYPE_SUB_BENEFICIARY = 'Sub_Beneficiary';

    /** Integration_Master__c.Name for the mock-driven Existing EMI integration. */
    private static final String EMI_INTEGRATION_MASTER_NAME = 'Existing EMI Engine';

    /** Stub only: primary match code for Borrower dummy rows (row 1). */
    private static final String DUMMY_BORROWER_PRIMARY_CUSTOMER_CODE = '36609355';
    private static final Set<String> DUMMY_BORROWER_CUSTOMER_CODES = new Set<String>{
        '36609355', '48291736', '71930482'
    };
    
    /**
     * Callable interface implementation - routes to internal methods
     */
    public Object call(String action, Map<String, Object> args) {
        if (ACTION_GET_PAGE_DATA.equalsIgnoreCase(action)) {
            return getPageDataInternal(args);
        } else if (ACTION_SAVE_APPLICANT_SELECTIONS.equalsIgnoreCase(action)) {
            return saveApplicantSelectionsInternal(args);
        } else if (ACTION_MARK_MATCH_AS_VALID.equalsIgnoreCase(action)) {
            return markMatchAsValidInternal(args);
        } else if (ACTION_MARK_MATCH_AS_INVALID.equalsIgnoreCase(action)) {
            return markMatchAsInvalidInternal(args);
        } else if (ACTION_REMOVE_APPLICANT.equalsIgnoreCase(action)) {
            return removeApplicantInternal(args);
        } else if (ACTION_RUN_CHECK_ELIGIBILITY_STAGE.equalsIgnoreCase(action)) {
            return runCheckEligibilityIntegrationStageInternal(args);
        } else if (ACTION_RUN_DEDUPE_FORWARD_STAGE.equalsIgnoreCase(action)) {
            return runDedupeForwardIntegrationStageInternal(args);
        } else if (ACTION_GET_EXISTING_EMI.equalsIgnoreCase(action)) {
            return getExistingEmiDetailsInternal(args);
        } else if (ACTION_GET_EXPOSURE_DETAILS.equalsIgnoreCase(action)) {
            return getExposureDetailsInternal(args);
        } else if (ACTION_VALIDATE_ALL_APPLICANTS.equalsIgnoreCase(action)) {
            return validateAllApplicantsDedupeCompleteInternal(args);
        } else if (ACTION_VALIDATE_NI_CONSTITUTION.equalsIgnoreCase(action)) {
            return validateNiConstitutionForApplicationInternal(args);
        }
        return new Map<String, Object>{ 'isSuccess' => false, 'message' => 'Unknown action: ' + action };
    }
    
    /**
     * Get customer dedupe page data including matches and applicant management info
     */
    private static Map<String, Object> getPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            Id recordId = (Id) args.get('recordId');
            // Resolve defensively: a blank or stale/foreign applicant id (left over from a
            // previous tab or session) is mapped to this application's Borrower.
            Id applicantId = resolveApplicantId(args, recordId);
            result.put('currentApplicantId', applicantId);

            result.put('isApplicationPastDedupeStep', isApplicationPastDedupeStep(recordId));

            Boolean autoMatchedFromCrossSell = maybeAutoResolveDedupeFromCrossSell(recordId, applicantId);
            
            // Get matches from API/existing logic
            List<Map<String, Object>> matches = getCustomerDedupeMatches(recordId, applicantId);
            result.put('matches', matches);
            result.put('autoMatchedFromCrossSell', autoMatchedFromCrossSell);

            result.put(
                'applicantHasCustomerCode',
                applicantHasCustomerCodeFromMatches(recordId, applicantId, matches)
            );
            result.put(
                'isCustomerDedupeCompleteForApplicant',
                isCustomerDedupeCompleteForApplicant(recordId, applicantId)
            );
            result.put('currentApplicantTabLabel', getApplicantTabLabel(recordId, applicantId));
            String currentApplicantType = getApplicantTypeValue(recordId, applicantId);
            result.put('currentApplicantCustomerType', currentApplicantType);
            result.put(
                'isCurrentApplicantNonIndividual',
                isNonIndividualApplicantType(currentApplicantType)
            );

            // Applicant customer code for valid-match persistence / UI restore
            result.put('customerCode', getApplicantCustomerCode(recordId, applicantId));
            String invalidatedMatchCif = getApplicantInvalidatedMatchCif(recordId, applicantId);
            result.put('invalidatedMatchCifId', invalidatedMatchCif);
            result.put('matchConfirmedInvalid', String.isNotBlank(invalidatedMatchCif));
            result.put(
                'hasDedupeMatchResolved',
                hasApplicantResolvedDedupeMatch(recordId, applicantId)
            );
            result.put(
                'existingEmiFetched',
                isNonIndividualApplicantType(currentApplicantType)
                    || hasApplicantFetchedExistingEmi(recordId, applicantId)
            );

            // Borrower: restore eligibility completion from applicant stage fields
            Id resolvedApplicantId = applicantId != null ? applicantId : getBorrowerApplicantId(recordId);
            if (resolvedApplicantId != null && checkIfBorrowerScreen(recordId, resolvedApplicantId)) {
                List<Applicant__c> currentApplicants = [
                    SELECT Id, Applicant_Type__c, Customer_Code__c,
                           Current_Loan_Stage_Complete__c, Loan_Stage__c,
                           Check_Eligibility_Message__c
                    FROM Applicant__c
                    WHERE Id = :resolvedApplicantId
                    AND Application__c = :recordId
                    AND In_Active_Applicant__c = false
                    LIMIT 1
                ];
                if (!currentApplicants.isEmpty()) {
                    Applicant__c borrower = currentApplicants[0];
                    result.put('eligibilityChecked', isEligibilityCheckComplete(borrower));
                    result.put('checkEligibilityMessage', borrower.Check_Eligibility_Message__c);
                    result.put('isApplicantLoanStagePastDedupe', isApplicantLoanStagePastDedupe(borrower));
                }
            } else if (resolvedApplicantId != null) {
                List<Applicant__c> coApps = [
                    SELECT Id, Loan_Stage__c
                    FROM Applicant__c
                    WHERE Id = :resolvedApplicantId
                    AND Application__c = :recordId
                    AND In_Active_Applicant__c = false
                    LIMIT 1
                ];
                if (!coApps.isEmpty()) {
                    result.put('isApplicantLoanStagePastDedupe', isApplicantLoanStagePastDedupe(coApps[0]));
                }
            }

            ensureApplicantLoanStageAtDedupeWhenViewingDedupe(recordId, applicantId);

            result.put('hasApplicantsNotAtCustomerDedupe', hasApplicantsNotAtCustomerDedupe(recordId));
            result.put(
                'hasAdditionalApplicantsPendingPriorStages',
                hasAdditionalApplicantsPendingPriorStages(recordId)
            );
            result.put(
                'pendingPriorStageApplicantLabels',
                getAdditionalApplicantsPendingPriorStageLabels(recordId)
            );
            result.put(
                'hasOtherApplicantsOfSameTypeNotAtStage',
                hasOtherApplicantsOfSameTypeNotAtStage(recordId, applicantId, DEDUPE_STEP_NAME)
            );
            result.put(
                'hasOtherApplicantsReachedCustomerDedupe',
                hasOtherApplicantsReachedDedupeStage(recordId)
            );
            result.put(
                'requiresBorrowerCombinedEligibilityRecheck',
                requiresBorrowerCombinedEligibilityRecheck(recordId)
            );

            // Get applicant management data
            Map<String, Object> applicantData = getApplicantManagementData(recordId, applicantId);
            result.putAll(applicantData);

            result.put('isSuccess', true);
        } catch (Exception e) {
            result.put('isSuccess', false);
            result.put('errorMessage', e.getMessage());
            logControllerError('getPageDataInternal', e);
        }
        
        return result;
    }
    
    /**
     * Resolves dedupe match rows for the current applicant.
     * Swap fetchCustomerDedupeMatchesFromApi to a real callout when integration is live.
     */
    private static List<Map<String, Object>> getCustomerDedupeMatches(Id recordId, Id applicantId) {
        List<Map<String, Object>> apiMatches = fetchCustomerDedupeMatchesFromApi(recordId, applicantId);
        if (apiMatches != null) {
            return apiMatches;
        }
        return buildStubDedupeMatches(recordId, applicantId);
    }

    /**
     * Integration seam — return applicant-specific match rows from the dedupe API.
     * Each row should include cifId (CIF-{customerCode}) for the match table.
     * Return null to fall back to buildStubDedupeMatches during UI development.
     */
    @TestVisible
    private static List<Map<String, Object>> fetchCustomerDedupeMatchesFromApi(
            Id recordId,
            Id applicantId) {
        return null;
    }

    private static List<Map<String, Object>> buildStubDedupeMatches(Id recordId, Id applicantId) {
        Applicant__c applicant = queryApplicantForStubMatches(recordId, applicantId);
        List<String> customerCodes = resolveStubCustomerCodes(applicant, applicantId);

        List<Map<String, Object>> matches = new List<Map<String, Object>>();
        matches.add(buildStubDedupeMatchRow(
            customerCodes[0],
            'RAJESH KUMAR SHARMA', '9876543210', 'ABCDE1234F', '15-Mar-1985',
            100, 'Exact Match', 95, 'Inactive',
            new Map<String, Object>{
                'PAN' => true, 'DOB' => true, 'Mobile' => true,
                'Name' => true, 'Email' => false, 'Addr' => false
            }
        ));
        matches.add(buildStubDedupeMatchRow(
            customerCodes[1],
            'RAJESH K SHARMA', '9876543211', 'ABCDE1234F', '15-Mar-1985',
            78, 'Partial Match', 62, 'Inactive',
            new Map<String, Object>{
                'PAN' => true, 'DOB' => true, 'Mobile' => false,
                'Name' => false, 'Email' => false, 'Addr' => false
            }
        ));
        matches.add(buildStubDedupeMatchRow(
            customerCodes[2],
            'SURESH KUMAR VERMA', '8765432109', 'XYZAB5678G', '22-Jul-1990',
            55, 'Fuzzy Match', 40, 'Inactive',
            new Map<String, Object>{
                'PAN' => false, 'DOB' => true, 'Mobile' => false,
                'Name' => false, 'Email' => false, 'Addr' => true
            }
        ));
        return matches;
    }

    private static Applicant__c queryApplicantForStubMatches(Id recordId, Id applicantId) {
        Id resolvedId = applicantId;
        if (resolvedId == null && recordId != null) {
            resolvedId = getBorrowerApplicantId(recordId);
        }
        if (resolvedId == null) {
            return null;
        }
        List<Applicant__c> apps = [
            SELECT Id, Applicant_Type__c, Customer_Code__c, Bank_Account_No__c
            FROM Applicant__c
            WHERE Id = :resolvedId
            AND Application__c = :recordId
            AND In_Active_Applicant__c = false
            LIMIT 1
        ];
        return apps.isEmpty() ? null : apps[0];
    }

    /**
     * KYC Cross-Sell: applicant selected a repayment account card → Bank_Account_No__c is set.
     * Together with Customer_Code__c (CIF on PAN from Basic Details) this enables auto-match.
     * Applies to every applicant (Borrower and non-Borrower).
     */
    @TestVisible
    private static Boolean hasCrossSellRepaymentAccountSelected(Applicant__c applicant) {
        return applicant != null
            && String.isNotBlank(applicant.Bank_Account_No__c)
            && String.isNotBlank(applicant.Customer_Code__c);
    }

    /**
     * When Cross-Sell repayment account is selected, the partial-match stub row carries the
     * applicant Customer_Code__c so the UI can auto-mark the ETB row on first paint. Without a
     * repayment account selected the stub keeps only non-matching codes, leaving the rows
     * selectable for manual Valid/Invalid. Applies to every applicant type.
     */
    private static List<String> resolveStubCustomerCodes(Applicant__c applicant, Id applicantId) {
        Boolean isBorrower = applicant == null || isBorrowerApplicant(applicant);
        String applicantCode = applicant != null && String.isNotBlank(applicant.Customer_Code__c)
            ? applicant.Customer_Code__c.trim()
            : null;
        List<String> nonMatching = isBorrower
            ? buildNonMatchingStubCodes(applicantCode, applicant != null ? applicant.Id : null)
            : resolveStubCustomerCodesForAdditionalApplicant(applicantId);
        if (hasCrossSellRepaymentAccountSelected(applicant)) {
            return new List<String>{ nonMatching[0], applicantCode, nonMatching[1] };
        }
        return nonMatching;
    }

    /**
     * Auto-mark ETB when KYC repayment card was selected and CIF code already exists.
     * Skips when the user already resolved dedupe manually (Valid/Invalid).
     */
    private static Boolean maybeAutoResolveDedupeFromCrossSell(Id recordId, Id applicantId) {
        Applicant__c applicant = queryApplicantForCrossSellAutoMatch(recordId, applicantId);
        if (!hasCrossSellRepaymentAccountSelected(applicant)) {
            return false;
        }
        if (hasApplicantResolvedDedupeMatch(recordId, applicant.Id)) {
            return false;
        }
        applicant.Invalid_Customer_Code__c = null;
        applicant.Relationship_with_Bank__c = 'ETB';
        update applicant;
        return true;
    }

    private static Applicant__c queryApplicantForCrossSellAutoMatch(Id recordId, Id applicantId) {
        Id resolvedId = applicantId != null ? applicantId : getBorrowerApplicantId(recordId);
        if (resolvedId == null) {
            return null;
        }
        List<Applicant__c> apps = [
            SELECT Id, Applicant_Type__c, Customer_Code__c, Bank_Account_No__c,
                   Relationship_with_Bank__c, Invalid_Customer_Code__c
            FROM Applicant__c
            WHERE Id = :resolvedId
            AND Application__c = :recordId
            AND In_Active_Applicant__c = false
            LIMIT 1
        ];
        return apps.isEmpty() ? null : apps[0];
    }

    private static List<String> buildNonMatchingStubCodes(String avoidCode, Id applicantId) {
        String seed = applicantId != null
            ? String.valueOf(applicantId)
            : String.valueOf(Crypto.getRandomLong());
        List<String> codes = new List<String>();
        Integer attempt = 1;
        while (codes.size() < 3) {
            String candidate = deriveEightDigitCustomerCodeFromSeed(seed, attempt);
            attempt++;
            if (String.isNotBlank(avoidCode) && candidate.equalsIgnoreCase(avoidCode.trim())) {
                continue;
            }
            if (DUMMY_BORROWER_CUSTOMER_CODES.contains(candidate) || codes.contains(candidate)) {
                continue;
            }
            codes.add(candidate);
        }
        return codes;
    }

    private static Map<String, Object> buildStubDedupeMatchRow(
            String customerCode,
            String name,
            String mobile,
            String pan,
            String dob,
            Integer matchPercent,
            String matchType,
            Integer retailMatch,
            String status,
            Map<String, Object> flags) {
        Map<String, Object> row = new Map<String, Object>();
        row.put('cifId', formatStubCifId(customerCode));
        row.put('name', name);
        row.put('mobile', mobile);
        row.put('pan', pan);
        row.put('dob', dob);
        row.put('matchPercent', matchPercent);
        row.put('matchType', matchType);
        row.put('retailMatch', retailMatch);
        row.put('status', status);
        row.put('flags', flags);
        return row;
    }

    /** Integration stamps Customer_Code__c without CIF-; stub/UI rows use CIF-{code}. */
    private static String formatStubCifId(String customerCode) {
        if (String.isBlank(customerCode)) {
            return '';
        }
        String trimmed = customerCode.trim();
        String upper = trimmed.toUpperCase();
        if (upper.startsWith('CIF-') || upper.startsWith('CIF')) {
            return trimmed;
        }
        return 'CIF-' + trimmed;
    }

    private static Boolean resolveIsBorrowerApplicantForDedupe(Id recordId, Id applicantId) {
        if (applicantId == null) {
            return true;
        }
        List<Applicant__c> apps = [
            SELECT Applicant_Type__c, Applicant_Tab_Label__c
            FROM Applicant__c
            WHERE Id = :applicantId
            AND Application__c = :recordId
            AND In_Active_Applicant__c = false
            LIMIT 1
        ];
        return apps.isEmpty() || isBorrowerApplicant(apps[0]);
    }

    /**
     * Deterministic unique 8-digit customer codes per additional applicant (CoBo/G/B).
     * Never reuses Borrower stub codes so auto-match does not cross applicants.
     */
    private static List<String> resolveStubCustomerCodesForAdditionalApplicant(Id applicantId) {
        String seed = applicantId != null ? String.valueOf(applicantId) : String.valueOf(Crypto.getRandomLong());
        List<String> codes = new List<String>();
        Integer attempt = 1;
        while (codes.size() < 3) {
            String candidate = deriveEightDigitCustomerCodeFromSeed(seed, attempt);
            attempt++;
            if (DUMMY_BORROWER_CUSTOMER_CODES.contains(candidate) || codes.contains(candidate)) {
                continue;
            }
            codes.add(candidate);
        }
        return codes;
    }

    private static String deriveEightDigitCustomerCodeFromSeed(String seed, Integer index) {
        Blob digest = Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(seed + ':' + String.valueOf(index))
        );
        String hex = EncodingUtil.convertToHex(digest);
        String digits = '';
        for (Integer i = 0; i < hex.length() && digits.length() < 8; i++) {
            Integer charCode = hex.charAt(i);
            if (charCode >= 48 && charCode <= 57) {
                digits += String.fromCharArray(new List<Integer>{ charCode });
            }
        }
        while (digits.length() < 8) {
            digits += '0';
        }
        if (digits.length() > 8) {
            digits = digits.substring(0, 8);
        }
        return digits;
    }
    
    /**
     * Get applicant management data (add/remove applicants section)
     */
    private static Map<String, Object> getApplicantManagementData(Id recordId, Id applicantId) {
        Map<String, Object> result = new Map<String, Object>();
        
        if (recordId == null) {
            result.put('canAddGuarantor', false);
            result.put('canAddBeneficiary', false);
            result.put('removableApplicants', new List<Map<String, Object>>());
            result.put('isBorrowerScreen', false);
            result.put('applicationType', '');
            result.put('isNonIndividual', false);
            return result;
        }
        
        // Get Application data
        List<Application__c> apps = [
            SELECT Id, Product__c, Sub_Product__c
            FROM Application__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        Boolean isTwoWheeler = !apps.isEmpty()
            ? resolveIsTwoWheeler(apps[0].Product__c, apps[0].Sub_Product__c)
            : false;
        
        // Non-Individual is determined from Borrower Applicant.Type__c (replaces Opportunity.Application_Type__c in sfLOS)
        Applicant__c borrowerApplicant = getBorrowerApplicant(recordId);
        String borrowerType = borrowerApplicant != null ? borrowerApplicant.Type__c : '';
        Boolean isNonIndividual = isNonIndividualApplicantType(borrowerType);
        String applicationType = isNonIndividual ? 'Non-Individual' : (String.isNotBlank(borrowerType) ? borrowerType : 'Individual');
        String borrowerEntityType = borrowerApplicant != null ? borrowerApplicant.Entity_Type__c : '';
        String applicationProductType = !apps.isEmpty() ? apps[0].Product__c : '';
        
        // Reuse the borrower record already fetched above: its Id replaces getBorrowerApplicantId(),
        // and the borrower-screen check is simply "the effective applicant IS the borrower".
        Id borrowerApplicantId = borrowerApplicant != null ? borrowerApplicant.Id : null;
        Id effectiveApplicantId = applicantId != null ? applicantId : borrowerApplicantId;
        Boolean isBorrowerScreen = effectiveApplicantId != null && effectiveApplicantId == borrowerApplicantId;
        
        // Get existing applicants count
        List<Applicant__c> existingApplicants = [
            SELECT Id, Type__c, Applicant_Type__c, Applicant_Tab_Label__c, Customer_First_Name__c, Customer_Last_Name__c,
                   Loan_Stage__c, Current_Loan_Stage_Complete__c, Is_Sub_Applicant__c,
                   Customer_Code__c, Invalid_Customer_Code__c
            FROM Applicant__c
            WHERE Application__c = :recordId AND In_Active_Applicant__c = false
        ];
        
        Integer guarantorCount = 0;
        Integer coBorrowerCount = 0;
        Integer beneficiaryCount = 0;
        // drive the "+ Add Sub-<Role>" buttons: a sub can only be added under an
        // existing NI top-level applicant of that role.
        Boolean hasNonIndividualGuarantor = false;
        Boolean hasNonIndividualBeneficiary = false;
        Boolean hasPendingAdditionalApplicantStages = false;
        List<Map<String, Object>> removableApplicants = new List<Map<String, Object>>();
        
        for (Applicant__c app : existingApplicants) {
            Boolean isTopLevelNi = app.Is_Sub_Applicant__c != true
                && isNonIndividualApplicantType(app.Type__c);
            if (isGuarantorApplicantType(app.Applicant_Type__c)) {
                guarantorCount++;
                if (isTopLevelNi) { hasNonIndividualGuarantor = true; }
            } else if (isCoBorrowerApplicantType(app.Applicant_Type__c)) {
                coBorrowerCount++;
                if (isTopLevelNi) { hasNonIndividualGuarantor = true; }
            } else if (isBeneficiaryApplicantType(app.Applicant_Type__c)) {
                beneficiaryCount++;
                if (isTopLevelNi) { hasNonIndividualBeneficiary = true; }
            }

            if (!isBorrowerApplicant(app)
                    && !hasApplicantCompletedPriorStagesForDedupe(app)) {
                hasPendingAdditionalApplicantStages = true;
            }
            
            if (!isBorrowerApplicant(app)) {
                String displayLabel = String.isNotBlank(app.Customer_First_Name__c) 
                    ? app.Customer_First_Name__c + ' ' + app.Customer_Last_Name__c + ' (' + app.Applicant_Tab_Label__c + ')' 
                    : app.Applicant_Tab_Label__c;
                removableApplicants.add(new Map<String, Object>{
                    'value' => app.Id,
                    'label' => displayLabel
                });
            }
        }
        
        String borrowerLoanStage = getBorrowerLoanStage(recordId);
        Boolean canAddMore = canAddMoreApplicants(recordId, borrowerLoanStage, isTwoWheeler, isNonIndividual);

        Integer maxGuarantors = getMaxGuarantors();
        Integer maxCoBorrowers = getMaxCoBorrowers();
        Integer maxBeneficiaries = getMaxBeneficiaries();

        Boolean hasReachedMaxGuarantor = !isTwoWheeler && guarantorCount >= maxGuarantors;
        Boolean hasReachedMaxCoBorrower = isTwoWheeler && coBorrowerCount >= maxCoBorrowers;
        Boolean hasReachedMaxBeneficiary = isNonIndividual && beneficiaryCount >= maxBeneficiaries;

        Boolean slotsAvailableForGuarantor = !hasReachedMaxGuarantor && !hasReachedMaxCoBorrower;
        Boolean slotsAvailableForBeneficiary = !hasReachedMaxBeneficiary;
        Boolean canPromptAddOnBorrower = isBorrowerScreen
            && allAdditionalApplicantsDedupeResolved(recordId)
            && hasAvailableApplicantSlots(recordId, isTwoWheeler, isNonIndividual);
        Boolean showAddGuarantorQuestion = isBorrowerScreen
            && slotsAvailableForGuarantor
            && canPromptAddOnBorrower;
        Boolean showAddBeneficiaryQuestion = isBorrowerScreen
            && isNonIndividual
            && slotsAvailableForBeneficiary
            && canPromptAddOnBorrower;

        result.put('canAddGuarantor', isBorrowerScreen && showAddGuarantorQuestion);
        result.put('canAddBeneficiary', isBorrowerScreen && isNonIndividual && showAddBeneficiaryQuestion);
        result.put('canAddMoreApplicants', canAddMore);
        result.put('borrowerLoanStage', borrowerLoanStage);
        result.put('removableApplicants', removableApplicants);
        result.put('isBorrowerScreen', isBorrowerScreen);
        result.put('applicationType', applicationType);
        result.put('isNonIndividual', isNonIndividual);
        result.put('isTwoWheeler', isTwoWheeler);
        result.put('lockCurrentApplicantDedupe', isBorrowerScreen && hasPendingAdditionalApplicantStages);
        result.put('stageIsComplete', isCustomerDedupeCompleteForApplicant(recordId, applicantId));
        result.put('guarantorCount', guarantorCount);
        result.put('coBorrowerCount', coBorrowerCount);
        result.put('beneficiaryCount', beneficiaryCount);
        result.put('hasNonIndividualGuarantor', hasNonIndividualGuarantor);
        result.put('hasNonIndividualBeneficiary', hasNonIndividualBeneficiary);
        result.put('applicantEntityType', borrowerEntityType);
        result.put('productType', applicationProductType);

        return result;
    }

    /**
     * Validates NI applicant min/max counts from Non_Individual_Constitution__mdt for PV/CV applications.
     * Two-wheeler applications are skipped.
     */
    @AuraEnabled
    public static Map<String, Object> validateNiConstitutionForApplication(Id applicationId) {
        return validateNiConstitutionForApplicationInternal(new Map<String, Object>{
            'recordId' => applicationId
        });
    }

    private static Map<String, Object> validateNiConstitutionForApplicationInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'isValid' => true,
            'isSuccess' => true,
            'message' => '',
            'violations' => new List<Map<String, Object>>()
        };

        Id applicationId = (Id) args.get('recordId');
        if (applicationId == null) {
            applicationId = (Id) args.get('applicationId');
        }
        if (applicationId == null) {
            return markNiConstitutionInvalid(result, 'Application Id is required.');
        }

        List<Application__c> apps = [
            SELECT Id, Product__c, Sub_Product__c
            FROM Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return markNiConstitutionInvalid(result, 'Application not found.');
        }

        String niProductType = resolveNiProductTypeForConstitution(
            apps[0].Product__c,
            apps[0].Sub_Product__c
        );
        if (String.isBlank(niProductType)) {
            return result;
        }

        Applicant__c borrower = getBorrowerApplicant(applicationId);
        if (borrower == null || !isNonIndividualApplicantType(borrower.Type__c)) {
            return result;
        }

        List<Applicant__c> applicants = [
            SELECT Id, Applicant_Type__c, Applicant_Tab_Label__c, Type__c, Entity_Type__c,
                   Parent_Applicant__c, Is_Sub_Applicant__c, In_Active_Applicant__c,
                   Customer_First_Name__c, Customer_Last_Name__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND In_Active_Applicant__c = false
            WITH SECURITY_ENFORCED
        ];

        Integer topLevelBeneficiaryCount = 0;
        Map<Id, Integer> subBeneficiaryCountByParent = new Map<Id, Integer>();

        for (Applicant__c applicant : applicants) {
            if (isBorrowerApplicant(applicant)) {
                continue;
            }
            if (isTopLevelBeneficiaryApplicant(applicant)) {
                topLevelBeneficiaryCount++;
            }else if (isSubBeneficiaryApplicant(applicant) && applicant.Parent_Applicant__c != null) {
                Id parentId = applicant.Parent_Applicant__c;
                Integer current = subBeneficiaryCountByParent.containsKey(parentId)
                    ? subBeneficiaryCountByParent.get(parentId)
                    : 0;
                subBeneficiaryCountByParent.put(parentId, current + 1);
            }
        }

        List<Map<String, Object>> violations = new List<Map<String, Object>>();

        Non_Individual_Constitution__mdt borrowerConstitution = resolveNiConstitutionMetadata(
            borrower.Entity_Type__c,
            niProductType
        );
        if (borrowerConstitution != null) {
            Integer minBeneficiary = toIntegerOrNull(borrowerConstitution.Min_Beneficiary_Count__c);
            if (minBeneficiary != null && topLevelBeneficiaryCount < minBeneficiary) {
                String beneficiaryLabel = minBeneficiary == 1 ? 'beneficiary' : 'beneficiaries';
                violations.add(buildNiConstitutionViolation(
                    'MIN_BENEFICIARY',
                    borrower,
                    minBeneficiary,
                    topLevelBeneficiaryCount,
                    'Please add at least ' + minBeneficiary
                        + ' ' + beneficiaryLabel + ' for this Non-Individual applicant ('
                        + borrower.Applicant_Type__c + ' : ' + formatNiApplicantDisplayName(borrower) + ')'+ ' based on constitution.'
                ));
            }
        }

        for (Applicant__c parent : applicants) {
            if (!isNiTopLevelApplicant(parent) || isBorrowerApplicant(parent)) {
                continue;
            }
            if (!isTopLevelBeneficiaryApplicant(parent)) {
                continue;
            }

            Non_Individual_Constitution__mdt parentConstitution = resolveNiConstitutionMetadata(
                parent.Entity_Type__c,
                niProductType
            );
            if (parentConstitution == null) {
                continue;
            }

            Integer minRequired = toIntegerOrNull(parentConstitution.Min_Beneficiary_Count__c);
            if (minRequired == null) {
                continue;
            }

            Integer currentCount = subBeneficiaryCountByParent.containsKey(parent.Id)
                ? subBeneficiaryCountByParent.get(parent.Id)
                : 0;
            if (currentCount < minRequired) {
                violations.add(buildNiConstitutionViolation(
                    'MIN_SUB_BENEFICIARY',
                    parent,
                    minRequired,
                    currentCount,
                    'Please add at least ' + minRequired
                        + ' Sub-Beneficiary record(s) for this Non-Individual applicant ('
                        + parent.Applicant_Type__c + ' : ' + formatNiApplicantDisplayName(parent)
                        + ') based on constitution.'
                ));
            }
        }

        if (!violations.isEmpty()) {
            result.put('isValid', false);
            result.put('isSuccess', false);
            result.put('violations', violations);
            result.put('message', (String) violations[0].get('message'));
        }
        return result;
    }

    private static Map<String, Object> markNiConstitutionInvalid(Map<String, Object> result, String message) {
        result.put('isValid', false);
        result.put('isSuccess', false);
        result.put('message', message);
        return result;
    }

    private static Map<String, Object> buildNiConstitutionViolation(
            String code,
            Applicant__c applicant,
            Integer requiredCount,
            Integer currentCount,
            String message) {
        return new Map<String, Object>{
            'code' => code,
            'applicantId' => applicant.Id,
            'applicantName' => formatNiApplicantDisplayName(applicant),
            'applicantType' => applicant.Applicant_Type__c,
            'applicantTabLabel' => applicant.Applicant_Tab_Label__c,
            'requiredCount' => requiredCount,
            'currentCount' => currentCount,
            'message' => message
        };
    }

    private static Non_Individual_Constitution__mdt resolveNiConstitutionMetadata(
            String entityType,
            String productType) {
        if (String.isBlank(entityType) || String.isBlank(productType)) {
            return null;
        }
        return ApplicantBasicDetailsCaptureController.getNiConstitution(entityType, productType);
    }

    private static String resolveNiProductTypeForConstitution(String product, String subProduct) {
        if (resolveIsTwoWheeler(product, subProduct)) {
            return null;
        }
        String productValue = String.isNotBlank(product) ? product.trim().toLowerCase() : '';
        if (String.isBlank(productValue) && String.isNotBlank(subProduct)) {
            productValue = subProduct.trim().toLowerCase();
        }
        if (productValue == 'cv' || productValue == 'scv' || productValue == 'lcv' || productValue == 'mhce'
                || productValue == 'ce' || productValue.contains('commercial vehicle')
                || productValue.contains('commercial equipment')) {
            return 'CV';
        }
        if (productValue == '4w' || productValue == 'pv' || productValue.contains('passenger vehicle')) {
            return 'PV';
        }
        return null;
    }

    private static Boolean isNiTopLevelApplicant(Applicant__c applicant) {
        return applicant != null && applicant.Parent_Applicant__c == null
            && isNonIndividualApplicantType(applicant.Type__c);
    }

    private static Boolean isTopLevelBeneficiaryApplicant(Applicant__c applicant) {
        return applicant != null
            && 'Beneficiary'.equalsIgnoreCase(applicant.Applicant_Type__c)
            && applicant.Parent_Applicant__c == null;
    }

    private static Boolean isTopLevelGuarantorApplicant(Applicant__c applicant) {
        return applicant != null
            && 'Guarantor'.equalsIgnoreCase(applicant.Applicant_Type__c)
            && applicant.Parent_Applicant__c == null;
    }

    private static Boolean isSubBeneficiaryApplicant(Applicant__c applicant) {
        if (applicant == null) {
            return false;
        }
        if (APPLICANT_TYPE_SUB_BENEFICIARY.equalsIgnoreCase(applicant.Applicant_Type__c)) {
            return true;
        }
        return applicant.Is_Sub_Applicant__c == true
            && applicant.Parent_Applicant__c != null
            && 'Beneficiary'.equalsIgnoreCase(applicant.Applicant_Type__c);
    }

    private static String formatNiApplicantDisplayName(Applicant__c applicant) {
        if (applicant == null) {
            return '';
        }
        String first = applicant.Customer_First_Name__c;
        String last = applicant.Customer_Last_Name__c;
        if (String.isNotBlank(first) || String.isNotBlank(last)) {
            return ((String.isNotBlank(first) ? first.trim() : '')
                + ' '
                + (String.isNotBlank(last) ? last.trim() : '')).trim();
        }
        return String.isNotBlank(applicant.Applicant_Tab_Label__c)
            ? applicant.Applicant_Tab_Label__c
            : applicant.Applicant_Type__c;
    }

    private static Integer toIntegerOrNull(Decimal value) {
        return value == null ? null : value.intValue();
    }

    public static Integer getMaxGuarantors() {
        return Integer.valueOf(System.Label.Max_Guarantors);
    }

    public static Integer getMaxCoBorrowers() {
        return Integer.valueOf(System.Label.Max_CoBorrowers);
    }

    public static Integer getMaxBeneficiaries() {
        return Integer.valueOf(System.Label.Max_Beneficiaries);
    }

    /**
     * True when the application can still add guarantor, co-borrower, or beneficiary slots.
     * Used by CustomerDedupeNavigationOverride to decide forward vs loop-back navigation.
     */
    /**
     * True when every active applicant has finished dedupe (Valid/Invalid + eligibility for Borrower).
     */
    public static Boolean areAllApplicantsDedupeJourneyComplete(Id recordId) {
        if (recordId == null) {
            return false;
        }
        Boolean hasAdditional = hasAnyAdditionalApplicant(recordId);
        for (Applicant__c app : [
            SELECT Id, Applicant_Tab_Label__c, Applicant_Type__c,
                   Customer_Code__c, Invalid_Customer_Code__c,
                   Current_Loan_Stage_Complete__c, Loan_Stage__c,
                   Check_Eligibility_Message__c, In_Active_Applicant__c
            FROM Applicant__c
            WHERE Application__c = :recordId AND In_Active_Applicant__c = false
        ]) {
            if (!isApplicantDedupeJourneyComplete(app, null, false)) {
                return false;
            }
            if (isBorrowerApplicant(app) && hasAdditional && !isEligibilityCheckComplete(app)) {
                return false;
            }
        }
        return true;
    }

    /** Stamps Dedupe and Eligibility on every active applicant (menu completion / stage advance). */
    public static void markAllApplicantsDedupeStepComplete(Id recordId) {
        if (recordId == null) {
            return;
        }
        List<Applicant__c> toUpdate = new List<Applicant__c>();
        for (Applicant__c app : [
            SELECT Id, Current_Loan_Stage_Complete__c, Loan_Stage__c
            FROM Applicant__c
            WHERE Application__c = :recordId AND In_Active_Applicant__c = false
        ]) {
            if (String.isNotBlank(app.Current_Loan_Stage_Complete__c)
                    && DEDUPE_STEP_NAME.equalsIgnoreCase(app.Current_Loan_Stage_Complete__c.trim())) {
                continue;
            }
            app.Current_Loan_Stage_Complete__c = DEDUPE_STEP_NAME;
            if (String.isBlank(app.Loan_Stage__c)) {
                app.Loan_Stage__c = DEDUPE_STEP_NAME;
            }
            toUpdate.add(app);
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    public static Boolean canAddMoreApplicantsForApplication(Id recordId) {
        if (recordId == null) {
            return false;
        }
        List<Application__c> apps = [
            SELECT Id, Product__c, Sub_Product__c
            FROM Application__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return false;
        }
        Boolean isTwoWheeler = resolveIsTwoWheeler(apps[0].Product__c, apps[0].Sub_Product__c);
        String borrowerType = getBorrowerApplicantType(recordId);
        Boolean isNonIndividual = isNonIndividualApplicantType(borrowerType);
        String borrowerLoanStage = getBorrowerLoanStage(recordId);
        return canAddMoreApplicants(recordId, borrowerLoanStage, isTwoWheeler, isNonIndividual);
    }

    private static void logControllerError(String methodName, Exception e) {
        System.debug(
            LoggingLevel.ERROR,
            'CustomerDedupeController.' + methodName + ': ' + e.getMessage() + '\n' + e.getStackTraceString()
        );
    }

    private static String getBorrowerLoanStage(Id recordId) {
        List<Applicant__c> borrowers = [
            SELECT Loan_Stage__c
            FROM Applicant__c
            WHERE Application__c = :recordId
            AND Applicant_Type__c = 'Borrower'
            AND In_Active_Applicant__c = false
            LIMIT 1
        ];
        return borrowers.isEmpty() ? null : borrowers[0].Loan_Stage__c;
    }

    private static Boolean canAddMoreApplicants(
            Id recordId,
            String borrowerLoanStage,
            Boolean isTwoWheeler,
            Boolean isNonIndividual) {
        if (recordId == null || String.isBlank(borrowerLoanStage)) {
            return false;
        }
        List<Applicant__c> nonBorrowerApplicants = [
            SELECT Id, Loan_Stage__c, Customer_Code__c, Invalid_Customer_Code__c,
                   Current_Loan_Stage_Complete__c
            FROM Applicant__c
            WHERE Application__c = :recordId
            AND Applicant_Type__c IN :ADDITIONAL_APPLICANT_TYPES
            AND In_Active_Applicant__c = false
        ];
        for (Applicant__c applicant : nonBorrowerApplicants) {
            if (isAdditionalApplicantAlignedForAddMore(applicant, borrowerLoanStage)) {
                continue;
            }
            return false;
        }
        Map<String, Integer> countByPrefix = countApplicantsByTabPrefix(recordId);
        if (isTwoWheeler && countByPrefix.get('CoBo') < getMaxCoBorrowers()) {
            return true;
        }
        if (!isTwoWheeler && countByPrefix.get('G') < getMaxGuarantors()) {
            return true;
        }
        if (isNonIndividual && countByPrefix.get('B') < getMaxBeneficiaries()) {
            return true;
        }
        return false;
    }

    private static Boolean hasAvailableApplicantSlots(
            Id recordId,
            Boolean isTwoWheeler,
            Boolean isNonIndividual) {
        Map<String, Integer> countByPrefix = countApplicantsByTabPrefix(recordId);
        if (isTwoWheeler && countByPrefix.get('CoBo') < getMaxCoBorrowers()) {
            return true;
        }
        if (!isTwoWheeler && countByPrefix.get('G') < getMaxGuarantors()) {
            return true;
        }
        if (isNonIndividual && countByPrefix.get('B') < getMaxBeneficiaries()) {
            return true;
        }
        return false;
    }

    private static Map<String, Integer> countApplicantsByTabPrefix(Id recordId) {
        Map<String, Integer> counts = new Map<String, Integer>{
            'G' => 0, 'CoBo' => 0, 'B' => 0
        };
        for (Applicant__c app : [
            SELECT Applicant_Tab_Label__c
            FROM Applicant__c
            WHERE Application__c = :recordId AND In_Active_Applicant__c = false
        ]) {
            String tab = app.Applicant_Tab_Label__c;
            if (String.isBlank(tab)) {
                continue;
            }
            if (tab.startsWith('CoBo')) {
                counts.put('CoBo', counts.get('CoBo') + 1);
            } else if (tab.startsWith('G')) {
                counts.put('G', counts.get('G') + 1);
            } else if (tab.startsWith('B')) {
                counts.put('B', counts.get('B') + 1);
            }
        }
        return counts;
    }

    /**
     * True when any Guarantor/Co-Borrower/Beneficiary has not finished QDE stages
     * before Dedupe (uses Current_Loan_Stage_Complete__c).
     */
    public static Boolean hasAdditionalApplicantsPendingPriorStages(Id recordId) {
        if (recordId == null) {
            return false;
        }
        return !getAdditionalApplicantsPendingPriorStageLabels(recordId).isEmpty();
    }

    public static List<String> getAdditionalApplicantsPendingPriorStageLabels(Id recordId) {
        List<String> labels = new List<String>();
        if (recordId == null) {
            return labels;
        }
        for (Applicant__c app : queryActiveAdditionalApplicants(recordId)) {
            if (!hasApplicantCompletedPriorStagesForDedupe(app)) {
                labels.add(resolveApplicantDisplayLabel(app));
            }
        }
        return labels;
    }

    /** True when any additional applicant still needs Valid/Invalid on Dedupe. */
    private static Boolean hasApplicantsNotAtCustomerDedupe(Id recordId) {
        if (recordId == null) {
            return false;
        }
        for (Applicant__c app : queryActiveAdditionalApplicants(recordId)) {
            if (!hasApplicantDedupeMatchResolved(app)) {
                return true;
            }
        }
        return false;
    }

    private static List<Applicant__c> queryActiveAdditionalApplicants(Id recordId) {
        return [
            SELECT Id, Applicant_Type__c, Applicant_Tab_Label__c, Type__c,
                   Current_Loan_Stage_Complete__c, Loan_Stage__c,
                   Customer_Code__c, Invalid_Customer_Code__c
            FROM Applicant__c
            WHERE Application__c = :recordId
            AND In_Active_Applicant__c = false
            AND Applicant_Type__c IN :ADDITIONAL_APPLICANT_TYPES
            ORDER BY Applicant_Tab_Label__c
        ];
    }

    public static Boolean hasApplicantCompletedPriorStagesForDedupe(Applicant__c app) {
        if (app == null || isBorrowerApplicant(app)) {
            return true;
        }
        String completeStep = String.isNotBlank(app.Current_Loan_Stage_Complete__c)
            ? app.Current_Loan_Stage_Complete__c.trim()
            : '';
        if (String.isNotBlank(completeStep)) {
            if (STEP_LEAD_DETAILS.equalsIgnoreCase(completeStep)
                    || STEP_BASIC_DETAILS.equalsIgnoreCase(completeStep)) {
                return false;
            }
            return true;
        }
        return !isApplicantOnStageBeforeDedupe(app);
    }

    private static Boolean isApplicantOnStageBeforeDedupe(Applicant__c app) {
        if (app == null) {
            return true;
        }
        String stageValue = String.isNotBlank(app.Current_Loan_Stage_Complete__c)
            ? app.Current_Loan_Stage_Complete__c.trim()
            : '';
        if (String.isBlank(stageValue)) {
            return true;
        }
        if (DEDUPE_STEP_NAME.equalsIgnoreCase(stageValue)) {
            return false;
        }
        for (String stepName : STAGES_BEFORE_DEDUPE) {
            if (stepName.equalsIgnoreCase(stageValue)) {
                return true;
            }
        }
        return false;
    }

    public static Boolean hasApplicantDedupeMatchResolved(Applicant__c app) {
        return app != null
            && (String.isNotBlank(app.Customer_Code__c)
                || String.isNotBlank(app.Invalid_Customer_Code__c));
    }

    public static Boolean hasApplicantTrulyResolvedDedupe(Applicant__c app) {
        if (app == null) {
            return false;
        }
        if (String.isNotBlank(app.Invalid_Customer_Code__c)) {
            return true;
        }
        String rel = app.Relationship_with_Bank__c;
        if (String.isNotBlank(rel)
                && ('ETB'.equalsIgnoreCase(rel.trim()) || 'NTB'.equalsIgnoreCase(rel.trim()))) {
            return true;
        }
        return String.isNotBlank(app.Current_Loan_Stage_Complete__c)
            && DEDUPE_STEP_NAME.equalsIgnoreCase(app.Current_Loan_Stage_Complete__c.trim());
    }

    /**
     * Additional applicants (Guarantor, Co-Borrower, Beneficiary) who finished the QDE dedupe
     * path may appear on later applicant-based menu steps (DDE Income, Credit, Operations, …).
     * Used by dynamicStageNavigatorController.
     */
    public static Boolean hasApplicantClearedQdeJourney(Applicant__c app) {
        if (app == null || isBorrowerApplicant(app)) {
            return true;
        }
        if (!hasApplicantCompletedPriorStagesForDedupe(app)) {
            return false;
        }
        if (hasApplicantDedupeMatchResolved(app)) {
            return true;
        }
        String completeStep = String.isNotBlank(app.Current_Loan_Stage_Complete__c)
            ? app.Current_Loan_Stage_Complete__c.trim()
            : '';
        if (String.isBlank(completeStep)) {
            return false;
        }
        if (STEP_LEAD_DETAILS.equalsIgnoreCase(completeStep)
                || STEP_BASIC_DETAILS.equalsIgnoreCase(completeStep)
                || STEP_KYC_DETAILS.equalsIgnoreCase(completeStep)
                || DEDUPE_STEP_NAME.equalsIgnoreCase(completeStep)) {
            return false;
        }
        return true;
    }

    /** Picklist values differ by org (Co-Borrower vs Co-borrower). */
    public static Boolean isApplicantTypeMatch(String applicantType, String expectedType) {
        if (String.isBlank(applicantType) || String.isBlank(expectedType)) {
            return false;
        }
        if (applicantType.equalsIgnoreCase(expectedType)) {
            return true;
        }
        return isCoBorrowerApplicantType(applicantType) && isCoBorrowerApplicantType(expectedType);
    }

    public static Boolean hasAnyAdditionalApplicant(Id recordId) {
        return recordId != null && !queryActiveAdditionalApplicants(recordId).isEmpty();
    }

    public static Boolean allAdditionalApplicantsDedupeResolved(Id recordId) {
        if (recordId == null || !hasAnyAdditionalApplicant(recordId)) {
            return true;
        }
        return getAdditionalApplicantsMissingDedupeMatchLabels(recordId).isEmpty();
    }

    public static Boolean requiresBorrowerCombinedEligibilityRecheck(Id recordId) {
        if (recordId == null || !hasAnyAdditionalApplicant(recordId)) {
            return false;
        }
        if (!allAdditionalApplicantsDedupeResolved(recordId)) {
            return false;
        }
        return !isBorrowerCombinedEligibilitySatisfied(recordId);
    }

    private static List<String> getAdditionalApplicantsMissingDedupeMatchLabels(Id recordId) {
        List<String> labels = new List<String>();
        if (recordId == null) {
            return labels;
        }
        for (Applicant__c app : queryActiveAdditionalApplicants(recordId)) {
            if (!hasApplicantDedupeMatchResolved(app)) {
                labels.add(resolveApplicantDisplayLabel(app));
            }
        }
        return labels;
    }

    public static Boolean isBorrowerCombinedEligibilitySatisfied(Id recordId) {
        if (recordId == null) {
            return false;
        }
        Applicant__c borrower = getBorrowerApplicant(recordId);
        if (borrower == null || !isEligibilityCheckComplete(borrower)) {
            return false;
        }
        for (Applicant__c app : queryActiveAdditionalApplicants(recordId)) {
            if (!hasApplicantDedupeMatchResolved(app)) {
                return false;
            }
        }
        return true;
    }

    public static Applicant__c getBorrowerApplicant(Id recordId) {
        if (recordId == null) {
            return null;
        }
        List<Applicant__c> borrowers = [
            SELECT Id, Applicant_Type__c, Applicant_Tab_Label__c,
                   Customer_Code__c, Invalid_Customer_Code__c,
                   Current_Loan_Stage_Complete__c, Loan_Stage__c,
                   Check_Eligibility_Message__c, Type__c, Entity_Type__c,
                   Is_Sub_Applicant__c, Parent_Applicant__c, Customer_First_Name__c, Customer_Last_Name__c
            FROM Applicant__c
            WHERE Application__c = :recordId
            AND Applicant_Type__c = 'Borrower'
            AND In_Active_Applicant__c = false
            LIMIT 1
        ];
        return borrowers.isEmpty() ? null : borrowers[0];
    }

    /**
     * After Next on a co-applicant tab: mark current complete, then the next tab
     * that still needs dedupe, or Borrower when all additional applicants are done.
     */
    public static String resolveNextDedupeTabLabel(Id recordId, String completedTabLabel) {
        if (recordId == null) {
            return 'Borrower';
        }
        if (String.isNotBlank(completedTabLabel)) {
            markApplicantDedupeCompleteByTabLabel(recordId, completedTabLabel);
        }
        for (Applicant__c app : queryActiveAdditionalApplicants(recordId)) {
            if (!isAdditionalApplicantDedupeTabComplete(app)) {
                return app.Applicant_Tab_Label__c;
            }
        }
        return 'Borrower';
    }

    /**
     * Co-applicant finished dedupe on their tab, or still on the same loan stage as Borrower
     * after Valid/Invalid is resolved. Used so Borrower can show "add another applicant" only
     * after existing guarantors complete dedupe match on their tab.
     */
    private static Boolean isAdditionalApplicantAlignedForAddMore(
            Applicant__c applicant,
            String borrowerLoanStage) {
        if (applicant == null) {
            return true;
        }
        if (isAdditionalApplicantDedupeTabComplete(applicant)) {
            return true;
        }
        if (!hasApplicantDedupeMatchResolved(applicant)) {
            return false;
        }
        if (String.isBlank(borrowerLoanStage) || String.isBlank(applicant.Loan_Stage__c)) {
            return false;
        }
        return borrowerLoanStage.trim().equalsIgnoreCase(applicant.Loan_Stage__c.trim());
    }

    private static Boolean isAdditionalApplicantDedupeTabComplete(Applicant__c app) {
        if (app == null) {
            return true;
        }
        if (!hasApplicantDedupeMatchResolved(app)) {
            return false;
        }
        return String.isNotBlank(app.Current_Loan_Stage_Complete__c)
            && DEDUPE_STEP_NAME.equalsIgnoreCase(app.Current_Loan_Stage_Complete__c.trim());
    }

    /** Marks dedupe complete for tab label when Valid/Invalid saved a customer code. */
    public static void markApplicantDedupeCompleteByTabLabel(Id recordId, String tabLabel) {
        if (recordId == null || String.isBlank(tabLabel)) {
            return;
        }
        List<Applicant__c> apps = [
            SELECT Id, Applicant_Tab_Label__c, Customer_Code__c, Invalid_Customer_Code__c
            FROM Applicant__c
            WHERE Application__c = :recordId
            AND In_Active_Applicant__c = false
            AND Applicant_Tab_Label__c = :tabLabel.trim()
            LIMIT 1
        ];
        if (!apps.isEmpty() && hasApplicantDedupeMatchResolved(apps[0])) {
            markApplicantDedupeStepComplete(apps[0].Id);
        }
    }

    /** After a co-applicant finishes dedupe, Borrower must re-run combined eligibility. */
    public static void clearBorrowerEligibilityForRecheck(Id recordId) {
        if (recordId == null || !hasAnyAdditionalApplicant(recordId)) {
            return;
        }
        Applicant__c borrower = getBorrowerApplicant(recordId);
        if (borrower == null || String.isBlank(borrower.Check_Eligibility_Message__c)) {
            return;
        }
        try {
            update new Applicant__c(
                Id = borrower.Id,
                Check_Eligibility_Message__c = null
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'clearBorrowerEligibilityForRecheck: ' + e.getMessage());
        }
    }

    private static Boolean hasOtherApplicantsOfSameTypeNotAtStage(
            Id recordId,
            Id currentApplicantId,
            String stage) {
        if (recordId == null || String.isBlank(stage)) {
            return false;
        }
        List<Applicant__c> apps = [
            SELECT Id, Applicant_Tab_Label__c, Applicant_Type__c, Loan_Stage__c,
                   Current_Loan_Stage_Complete__c, Customer_Code__c, Invalid_Customer_Code__c
            FROM Applicant__c
            WHERE Application__c = :recordId
            AND In_Active_Applicant__c = false
            AND Applicant_Type__c IN :ADDITIONAL_APPLICANT_TYPES
        ];
        if (apps.isEmpty()) {
            return false;
        }
        String prefix = null;
        for (Applicant__c a : apps) {
            if (a.Id == currentApplicantId) {
                prefix = tabLabelPrefix(a.Applicant_Tab_Label__c);
                break;
            }
        }
        if (prefix == null) {
            return false;
        }
        for (Applicant__c a : apps) {
            if (a.Id == currentApplicantId) {
                continue;
            }
            if (String.isBlank(a.Applicant_Tab_Label__c) || !a.Applicant_Tab_Label__c.startsWith(prefix)) {
                continue;
            }
            if (!hasApplicantCompletedDedupeStep(a)
                    && (String.isBlank(a.Loan_Stage__c) || !stage.equalsIgnoreCase(a.Loan_Stage__c.trim()))) {
                return true;
            }
        }
        return false;
    }

    private static Boolean hasOtherApplicantsReachedDedupeStage(Id recordId) {
        if (recordId == null) {
            return false;
        }
        Integer cnt = [
            SELECT COUNT()
            FROM Applicant__c
            WHERE Application__c = :recordId
            AND In_Active_Applicant__c = false
            AND Applicant_Type__c IN :ADDITIONAL_APPLICANT_TYPES
            AND (
                Loan_Stage__c = :DEDUPE_STEP_NAME
                OR Current_Loan_Stage_Complete__c = :DEDUPE_STEP_NAME
            )
        ];
        return cnt != null && cnt > 0;
    }

    /**
     * When user opens Guarantor/CoBo/Beneficiary on Dedupe, align Loan_Stage__c to dedupe
     * (sfLOS: applicant reaches Customer Dedupe before Valid/Invalid on that tab).
     */
    private static void ensureApplicantLoanStageAtDedupeWhenViewingDedupe(Id recordId, Id applicantId) {
        if (recordId == null || applicantId == null || checkIfBorrowerScreen(recordId, applicantId)) {
            return;
        }
        List<Applicant__c> apps = [
            SELECT Id, Applicant_Type__c, Loan_Stage__c, Current_Loan_Stage_Complete__c,
                   Customer_Code__c, Invalid_Customer_Code__c
            FROM Applicant__c
            WHERE Id = :applicantId
            AND Application__c = :recordId
            AND In_Active_Applicant__c = false
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return;
        }
        Applicant__c app = apps[0];
        if (hasApplicantCompletedDedupeStep(app)) {
            return;
        }
        String loanStage = String.isNotBlank(app.Loan_Stage__c) ? app.Loan_Stage__c.trim() : '';
        if (String.isBlank(loanStage) || STAGES_BEFORE_DEDUPE.contains(loanStage)) {
            try {
                update new Applicant__c(Id = app.Id, Loan_Stage__c = DEDUPE_STEP_NAME);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'ensureApplicantLoanStageAtDedupeWhenViewingDedupe: ' + e.getMessage());
            }
        }
    }

    private static Boolean isCustomerDedupeCompleteForApplicant(Id recordId, Id applicantId) {
        if (recordId == null) {
            return false;
        }
        Applicant__c app;
        if (applicantId != null) {
            List<Applicant__c> apps = [
                SELECT Id, Applicant_Type__c, Current_Loan_Stage_Complete__c,
                       Customer_Code__c, Invalid_Customer_Code__c
                FROM Applicant__c
                WHERE Id = :applicantId AND Application__c = :recordId
                LIMIT 1
            ];
            app = apps.isEmpty() ? null : apps[0];
        } else {
            List<Applicant__c> apps = [
                SELECT Id, Applicant_Type__c, Current_Loan_Stage_Complete__c,
                       Customer_Code__c, Invalid_Customer_Code__c
                FROM Applicant__c
                WHERE Application__c = :recordId
                AND Applicant_Type__c = 'Borrower'
                AND In_Active_Applicant__c = false
                LIMIT 1
            ];
            app = apps.isEmpty() ? null : apps[0];
        }
        if (app == null
                || String.isBlank(app.Current_Loan_Stage_Complete__c)
                || !DEDUPE_STEP_NAME.equalsIgnoreCase(app.Current_Loan_Stage_Complete__c.trim())) {
            return false;
        }
        if (isBorrowerApplicant(app)) {
            return true;
        }
        return String.isNotBlank(app.Customer_Code__c) || String.isNotBlank(app.Invalid_Customer_Code__c);
    }

    private static String getApplicantTabLabel(Id recordId, Id applicantId) {
        if (recordId == null) {
            return 'Borrower';
        }
        if (applicantId == null) {
            return 'Borrower';
        }
        List<Applicant__c> apps = [
            SELECT Applicant_Tab_Label__c, Applicant_Type__c
            FROM Applicant__c
            WHERE Id = :applicantId AND Application__c = :recordId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return 'Borrower';
        }
        if (String.isNotBlank(apps[0].Applicant_Tab_Label__c)) {
            return apps[0].Applicant_Tab_Label__c.trim();
        }
        return 'Borrower'.equalsIgnoreCase(apps[0].Applicant_Type__c) ? 'Borrower' : '';
    }

    private static Boolean applicantHasCustomerCodeFromMatches(
            Id recordId,
            Id applicantId,
            List<Map<String, Object>> matches) {
        if (recordId == null || applicantId == null || matches == null || matches.isEmpty()) {
            return false;
        }
        Set<String> matchCifIds = new Set<String>();
        for (Map<String, Object> m : matches) {
            if (m == null) {
                continue;
            }
            // Normalise possible CIF keys coming back from integration so that
            // Customer_Code__c written on Applicant__c can be matched to at
            // least one row in the dedupe result table.
            List<String> cifKeys = new List<String>{
                'cifId',
                'CIFId',
                'cifID',
                'custId',
                'customerId',
                'customer_code__c',
                'customerCode',
                'Customer_Code__c',
                'customer_code'
            };
            for (String key : cifKeys) {
                if (m.containsKey(key)) {
                    Object cif = m.get(key);
                    if (cif != null && String.isNotBlank(String.valueOf(cif))) {
                        String normalizedMatchCif = normalizeCifForCompare(String.valueOf(cif));
                        if (String.isNotBlank(normalizedMatchCif)) {
                            matchCifIds.add(normalizedMatchCif);
                        }
                        break;
                    }
                }
            }
        }
        if (matchCifIds.isEmpty()) {
            return false;
        }
        List<Applicant__c> apps = [
            SELECT Customer_Code__c, Invalid_Customer_Code__c
            FROM Applicant__c
            WHERE Id = :applicantId AND Application__c = :recordId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return false;
        }
        Applicant__c app = apps[0];
        String custCode = String.isNotBlank(app.Customer_Code__c)
            ? normalizeCifForCompare(app.Customer_Code__c)
            : null;
        String invCode = String.isNotBlank(app.Invalid_Customer_Code__c)
            ? normalizeCifForCompare(app.Invalid_Customer_Code__c)
            : null;
        return (custCode != null && matchCifIds.contains(custCode))
            || (invCode != null && matchCifIds.contains(invCode));
    }

    private static String normalizeCifForCompare(String cifValue) {
        if (String.isBlank(cifValue)) {
            return null;
        }
        String normalized = cifValue.replaceAll('[^A-Za-z0-9]', '').toUpperCase();
        if (normalized.startsWith('CIF') && normalized.length() > 3) {
            return normalized.substring(3);
        }
        return normalized;
    }

    @TestVisible
    private static String normalizeCifForComparePublic(String cifValue) {
        return normalizeCifForCompare(cifValue);
    }

    private static String tabLabelPrefix(String tabLabel) {
        if (String.isBlank(tabLabel)) {
            return null;
        }
        if (tabLabel.startsWith('CoBo')) {
            return 'CoBo';
        }
        if (tabLabel.startsWith('G')) {
            return 'G';
        }
        if (tabLabel.startsWith('B')) {
            return 'B';
        }
        return null;
    }
    
    /**
     * True after the user clicks Valid (ETB) or Invalid (NTB) on the dedupe screen.
     * CIF-on-PAN alone does not set Relationship_with_Bank__c and must not restore UI state.
     */
    @TestVisible
    private static Boolean hasApplicantResolvedDedupeMatch(Id recordId, Id applicantId) {
        Id resolvedId = applicantId != null ? applicantId : getBorrowerApplicantId(recordId);
        if (resolvedId == null) {
            return false;
        }
        List<Applicant__c> apps = [
            SELECT Relationship_with_Bank__c, Invalid_Customer_Code__c
            FROM Applicant__c
            WHERE Id = :resolvedId AND Application__c = :recordId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return false;
        }
        Applicant__c app = apps[0];
        if (String.isNotBlank(app.Invalid_Customer_Code__c)) {
            return true;
        }
        String relationship = app.Relationship_with_Bank__c;
        return String.isNotBlank(relationship)
            && ('ETB'.equalsIgnoreCase(relationship.trim())
                || 'NTB'.equalsIgnoreCase(relationship.trim()));
    }

    /**
     * Returns Customer_Code__c for the current or borrower applicant.
     */
    private static String getApplicantCustomerCode(Id recordId, Id applicantId) {
        Id resolvedId = applicantId != null ? applicantId : getBorrowerApplicantId(recordId);
        if (resolvedId == null) {
            return '';
        }
        List<Applicant__c> apps = [
            SELECT Customer_Code__c
            FROM Applicant__c
            WHERE Id = :resolvedId AND Application__c = :recordId
            LIMIT 1
        ];
        return apps.isEmpty() || String.isBlank(apps[0].Customer_Code__c)
            ? ''
            : apps[0].Customer_Code__c.trim();
    }

    /**
     * True when Get Existing EMI already ran successfully for this applicant, detected via a
     * successful Integration_Checklist__c for the "Existing EMI Engine" master.
     */
    private static Boolean hasApplicantFetchedExistingEmi(Id recordId, Id applicantId) {
        Id resolvedId = applicantId != null ? applicantId : getBorrowerApplicantId(recordId);
        if (resolvedId == null) {
            return false;
        }
        return ApplicationUtility.getExistingICRecordCount(
            String.valueOf(resolvedId),
            EMI_INTEGRATION_MASTER_NAME,
            'Applicant__c',
            Constants.CHECKLIST_STATUS_SUCCESS
        ) > 0;
    }

    private static String getApplicantInvalidatedMatchCif(Id recordId, Id applicantId) {
        Id resolvedId = applicantId != null ? applicantId : getBorrowerApplicantId(recordId);
        if (resolvedId == null) {
            return '';
        }
        List<Applicant__c> apps = [
            SELECT Invalid_Customer_Code__c
            FROM Applicant__c
            WHERE Id = :resolvedId AND Application__c = :recordId
            LIMIT 1
        ];
        return apps.isEmpty() || String.isBlank(apps[0].Invalid_Customer_Code__c)
            ? ''
            : apps[0].Invalid_Customer_Code__c.trim();
    }

    private static Id getBorrowerApplicantId(Id recordId) {
        if (recordId == null) {
            return null;
        }
        List<Applicant__c> borrowers = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :recordId
            AND Applicant_Type__c = 'Borrower'
            AND In_Active_Applicant__c = false
            LIMIT 1
        ];
        return borrowers.isEmpty() ? null : borrowers[0].Id;
    }

    private static String getApplicantTypeValue(Id recordId, Id applicantId) {
        Id resolvedId = applicantId != null ? applicantId : getBorrowerApplicantId(recordId);
        if (resolvedId == null) {
            return '';
        }
        List<Applicant__c> apps = [
            SELECT Type__c
            FROM Applicant__c
            WHERE Id = :resolvedId
            AND Application__c = :recordId
            AND In_Active_Applicant__c = false
            LIMIT 1
        ];
        return apps.isEmpty() ? '' : apps[0].Type__c;
    }

    /**
     * Returns Borrower Applicant.Type__c for the application (used instead of Opportunity.Application_Type__c).
     */
    private static String getBorrowerApplicantType(Id recordId) {
        if (recordId == null) {
            return '';
        }
        List<Applicant__c> borrowers = [
            SELECT Type__c
            FROM Applicant__c
            WHERE Application__c = :recordId
            AND Applicant_Type__c = 'Borrower'
            AND In_Active_Applicant__c = false
            LIMIT 1
        ];
        return borrowers.isEmpty() ? '' : borrowers[0].Type__c;
    }

    /**
     * Matches sfLOS Non-Individual application type checks (Non Individual / Non-Individual).
     */
    private static Boolean isNonIndividualApplicantType(String typeValue) {
        if (String.isBlank(typeValue)) {
            return false;
        }
        String normalized = typeValue.trim().toLowerCase().replace(' ', '').replace('-', '');
        return normalized == 'nonindividual';
    }

    /**
     * Check if current screen is for Borrower applicant
     */
    private static Boolean checkIfBorrowerScreen(Id recordId, Id applicantId) {
        if (applicantId == null) {
            return false;
        }

        List<Applicant__c> apps = [
            SELECT Id, Applicant_Type__c
            FROM Applicant__c
            WHERE Id = :applicantId AND Application__c = :recordId
            LIMIT 1
        ];
        return !apps.isEmpty() && 'Borrower'.equalsIgnoreCase(apps[0].Applicant_Type__c);
    }
    
    /**
     * Save add applicant selections
     */
    private static Map<String, Object> saveApplicantSelectionsInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);
        
        try {
            Id recordId = (Id) args.get('recordId');
            String addGuarantorCoBorrower = (String) args.get('addGuarantorCoBorrower');
            String addBeneficiary = (String) args.get('addBeneficiary');
            String applicantCustomerType = (String) args.get('applicantCustomerType');
            String guarantorApplicantCustomerType = (String) args.get('guarantorApplicantCustomerType');
            String beneficiaryApplicantCustomerType = (String) args.get('beneficiaryApplicantCustomerType');
            List<Applicant__c> toInsert = new List<Applicant__c>();
            String createdApplicantTabLabel = null;
            Boolean isNonIndividual = isNonIndividualApplicantType(getBorrowerApplicantType(recordId));
            
            Application__c app = [
                SELECT Id, Product__c, Sub_Product__c
                FROM Application__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            Boolean isTwoWheeler = resolveIsTwoWheeler(app.Product__c, app.Sub_Product__c);

            // Get existing applicants
            List<Applicant__c> existingApplicants = [
                SELECT Id, Type__c, Applicant_Tab_Label__c 
                FROM Applicant__c
                WHERE Application__c = :recordId AND In_Active_Applicant__c = false
            ];
            
            Map<String, Integer> countByType = new Map<String, Integer>{'G' => 0, 'CoBo' => 0, 'B' => 0};
            for (Applicant__c applicant : existingApplicants) {
                if (String.isNotBlank(applicant.Applicant_Tab_Label__c)) {
                    if (applicant.Applicant_Tab_Label__c.startsWith('G')) countByType.put('G', countByType.get('G') + 1);
                    else if (applicant.Applicant_Tab_Label__c.startsWith('CoBo')) countByType.put('CoBo', countByType.get('CoBo') + 1);
                    else if (applicant.Applicant_Tab_Label__c.startsWith('B')) countByType.put('B', countByType.get('B') + 1);
                }
            }
            
            String resolvedGuarantorType = String.isNotBlank(guarantorApplicantCustomerType)
                ? guarantorApplicantCustomerType
                : applicantCustomerType;
            String resolvedBeneficiaryType = String.isNotBlank(beneficiaryApplicantCustomerType)
                ? beneficiaryApplicantCustomerType
                : applicantCustomerType;

            // Add Guarantor or Co-Borrower (Two-Wheeler uses CoBo tab + Co-Borrower type)
            if ('Yes'.equalsIgnoreCase(addGuarantorCoBorrower)) {
                String prefix = isTwoWheeler ? 'CoBo' : 'G';
                Integer maxCount = isTwoWheeler ? getMaxCoBorrowers() : getMaxGuarantors();
                Integer existingCount = countByType.get(prefix);
                if (existingCount >= maxCount) {
                    result.put('message', 'Maximum applicants reached for this type.');
                    return result;
                }
                Integer nextNum = existingCount + 1;
                String tabLabel = prefix + nextNum;
                String applicantType = isTwoWheeler ? APPLICANT_TYPE_CO_BORROWER : 'Guarantor';

                Applicant__c newApp = new Applicant__c(
                    Application__c = recordId,
                    Applicant_Type__c = applicantType,
                    Applicant_Tab_Label__c = tabLabel,
                    Type__c = String.isNotBlank(resolvedGuarantorType) ? resolvedGuarantorType : 'Individual'
                );
                toInsert.add(newApp);
                if (createdApplicantTabLabel == null) {
                    createdApplicantTabLabel = tabLabel;
                }
            }
            
            // Add Beneficiary
            if ('Yes'.equalsIgnoreCase(addBeneficiary) && isNonIndividual) {
                Integer nextNum = countByType.get('B') + 1;
                String tabLabel = 'B' + nextNum;
                
                Applicant__c newApp = new Applicant__c(
                    Application__c = recordId,
                    Applicant_Type__c = 'Beneficiary',
                    Applicant_Tab_Label__c = tabLabel,
                    Type__c = String.isNotBlank(resolvedBeneficiaryType) ? resolvedBeneficiaryType : null
                );
                toInsert.add(newApp);
                if (createdApplicantTabLabel == null) createdApplicantTabLabel = tabLabel;
            }
            
            if (!toInsert.isEmpty()) {
                insert toInsert;
                assignInitialApplicantLoanStage(toInsert);
                // PAN / Form 60 checklists are intentionally NOT pre-seeded here.
                // They are created on demand (one row, based on PAN availability)
            }

            if ('Yes'.equalsIgnoreCase(addGuarantorCoBorrower) && String.isBlank(createdApplicantTabLabel)
                && !('Yes'.equalsIgnoreCase(addBeneficiary) && isNonIndividual)) {
                result.put('message', 'Could not create guarantor/co-borrower applicant.');
                return result;
            }

            result.put('isSuccess', true);
            result.put('createdApplicantTabLabel', createdApplicantTabLabel);
            result.put('message', String.isNotBlank(createdApplicantTabLabel)
                ? 'Applicant(s) added successfully'
                : 'Saved successfully');
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }
        
        return result;
    }
    
    /**
     * Mark a match as valid (ETB customer)
     */
    private static Map<String, Object> markMatchAsValidInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);
        
        try {
            Id recordId = (Id) args.get('recordId');
            String cifId = (String) args.get('cifId');

            if (String.isBlank(cifId)) {
                result.put('message', 'Customer code (CIF) is required.');
                return result;
            }

            Applicant__c applicant = resolveApplicantForMatchAction(args, recordId);
            if (applicant == null) {
                result.put('message', 'Applicant not found. Select the applicant tab and try again.');
                return result;
            }

            applicant.Customer_Code__c = cifId.trim();
            applicant.Invalid_Customer_Code__c = null;
            applicant.Relationship_with_Bank__c = 'ETB';
            update applicant;
            if (!isBorrowerApplicant(applicant)) {
                clearBorrowerEligibilityForRecheck(recordId);
            }

            result.put('isSuccess', true);
            result.put('message', 'Customer with code ' + cifId.trim() + ' is already existing-to-bank');
            result.put('successMessage', 'Customer with code ' + cifId.trim() + ' is already existing-to-bank');
            result.put('customerCode', cifId.trim());
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }

        return result;
    }

    /**
     * Mark a match as invalid (NTB customer, generate new code)
     */
    private static Map<String, Object> markMatchAsInvalidInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);
        
        try {
            Id recordId = (Id) args.get('recordId');
            String selectedCifId = (String) args.get('cifId');

            Applicant__c applicant = resolveApplicantForMatchAction(args, recordId);
            if (applicant == null) {
                result.put('message', 'Applicant not found. Select the applicant tab and try again.');
                return result;
            }

            String newCode = generateNewCustomerCode(recordId);
            if (String.isNotBlank(selectedCifId)) {
                applicant.Invalid_Customer_Code__c = selectedCifId.trim();
            }
            applicant.Customer_Code__c = newCode;
            applicant.Relationship_with_Bank__c = 'NTB';
            update applicant;
            if (!isBorrowerApplicant(applicant)) {
                clearBorrowerEligibilityForRecheck(recordId);
            }

            String ntbMessage = 'Customer is marked as "New to Bank" and CIF ID will be generated post Sanction.';
            result.put('isSuccess', true);
            result.put('message', ntbMessage);
            result.put('successMessage', ntbMessage);
            result.put('newCustomerCode', newCode);
            result.put('customerCode', newCode);
            if (String.isNotBlank(selectedCifId)) {
                result.put('invalidatedMatchCifId', selectedCifId.trim());
            }
            result.put('matchConfirmedInvalid', true);
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }

        return result;
    }

    /**
     * Runs one Check Eligibility modal stage (NPA / CIBIL / BRE).
     * BRE persists borrower eligibility after the application-level API stub succeeds.
     */
    private static Map<String, Object> runCheckEligibilityIntegrationStageInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);

        try {
            String stageKey = (String) args.get('stageKey');
            if (String.isBlank(stageKey)) {
                result.put('message', 'Eligibility stage is required.');
                return result;
            }

            Map<String, Object> context = resolveCheckEligibilityContext(args);
            if (context.get('isSuccess') != true) {
                return context;
            }

            Id recordId = (Id) context.get('recordId');
            Id applicantId = (Id) context.get('applicantId');
            Applicant__c app = (Applicant__c) context.get('applicant');
            String cifPayload = (String) context.get('cifPayload');

            Map<String, Object> apiResult = CustomerDedupeIntegrationService.invokeCheckEligibilityStageApi(
                recordId,
                applicantId,
                cifPayload,
                stageKey.trim()
            );
            if (!CustomerDedupeIntegrationService.isIntegrationSuccess(apiResult)) {
                result.put('message', CustomerDedupeIntegrationService.getIntegrationErrorMessage(apiResult));
                return result;
            }

            if ('BRE'.equalsIgnoreCase(stageKey.trim())) {
                return persistBorrowerEligibilitySuccess(app);
            }

            result.put('isSuccess', true);
            result.put('stageKey', stageKey.trim());
            result.put('integrationResult', apiResult);
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }

        return result;
    }

    /**
     * Runs ONE Dedupe Next forward-modal stage on Borrower "Next" — AML, ScoreCard
     * (and FI Creation for CV NI). AML + ScoreCard were merged into a single
     * Integration Progress modal, so the LWC (runNextForwardIntegrationChain)
     * invokes this action once per stage with { stageKey, recordId } and the
     * stages render sequentially in the same modal.
     *
     * Delegates to CustomerDedupeIntegrationService.invokeDedupeForwardStageApi,
     * mirroring runCheckEligibilityIntegrationStageInternal. Returns
     * { isSuccess, message?, stageKey?, integrationResult? }.
     */
    private static Map<String, Object> runDedupeForwardIntegrationStageInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);

        try {
            String stageKey = (String) args.get('stageKey');
            if (String.isBlank(stageKey)) {
                result.put('message', 'Forward integration stage is required.');
                return result;
            }

            Id recordId = (Id) args.get('recordId');
            if (recordId == null) {
                result.put('message', 'Application record is required for the forward integration.');
                return result;
            }

            Map<String, Object> apiResult = CustomerDedupeIntegrationService.invokeDedupeForwardStageApi(
                recordId,
                stageKey.trim()
            );
            if (!CustomerDedupeIntegrationService.isIntegrationSuccess(apiResult)) {
                result.put('message', CustomerDedupeIntegrationService.getIntegrationErrorMessage(apiResult));
                return result;
            }

            result.put('isSuccess', true);
            result.put('stageKey', stageKey.trim());
            result.put('integrationResult', apiResult);
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }

        return result;
    }

    private static Map<String, Object> resolveCheckEligibilityContext(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);

        Id recordId = (Id) args.get('recordId');
        Id applicantId = (Id) args.get('applicantId');
        String cifId = (String) args.get('cifId');

        if (applicantId == null) {
            applicantId = getBorrowerApplicantId(recordId);
        }
        if (applicantId == null) {
            result.put('message', 'Applicant is required for eligibility check.');
            return result;
        }

        List<Applicant__c> apps = [
            SELECT Id, Applicant_Type__c, Customer_Code__c,
                   Current_Loan_Stage_Complete__c, Loan_Stage__c,
                   Check_Eligibility_Message__c
            FROM Applicant__c
            WHERE Applicant_Type__c = 'Borrower'
            AND Application__c = :recordId
            AND In_Active_Applicant__c = false
            LIMIT 1
        ];

        if (apps.isEmpty()) {
            result.put('message', 'Applicant not found');
            return result;
        }

        Applicant__c app = apps[0];
        if (!isBorrowerApplicant(app)) {
            result.put('message', 'Eligibility check is only available for the Borrower.');
            return result;
        }

        String cifPayload;
        if (allAdditionalApplicantsDedupeResolved(recordId)) {
            List<String> missingDedupeLabels = getApplicantsMissingDedupeMatchLabels(recordId);
            if (!missingDedupeLabels.isEmpty()) {
                result.put(
                    'message',
                    'Complete customer dedupe (Valid/Invalid) for '
                        + String.join(missingDedupeLabels, ', ')
                        + ' before checking eligibility.'
                );
                return result;
            }
            cifPayload = buildCombinedCustomerCodesPayload(recordId);
            result.put('eligibilityMode', 'combined');
        } else {
            if (String.isBlank(app.Customer_Code__c)) {
                result.put(
                    'message',
                    'Complete customer dedupe (Valid/Invalid) for the Borrower before checking eligibility.'
                );
                return result;
            }
            cifPayload = app.Customer_Code__c.trim();
            result.put('eligibilityMode', 'borrowerOnly');
        }

        if (String.isBlank(cifPayload)) {
            result.put('message', 'Complete customer dedupe (Valid/Invalid) before checking eligibility.');
            return result;
        }

        if (String.isNotBlank(cifId) && !cifId.equalsIgnoreCase(app.Customer_Code__c)) {
            app.Customer_Code__c = cifId.trim();
            if ('borrowerOnly'.equals(result.get('eligibilityMode'))) {
                cifPayload = app.Customer_Code__c;
            }
        }

        result.put('isSuccess', true);
        result.put('recordId', recordId);
        result.put('applicantId', applicantId);
        result.put('applicant', app);
        result.put('cifPayload', cifPayload);
        return result;
    }

    private static Map<String, Object> persistBorrowerEligibilitySuccess(Applicant__c app) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);

        app.Check_Eligibility_Message__c = CHECK_ELIGIBILITY_SUCCESS_MESSAGE;
        update app;

        result.put('isSuccess', true);
        result.put('message', CHECK_ELIGIBILITY_SUCCESS_MESSAGE);
        result.put('successMessage', CHECK_ELIGIBILITY_SUCCESS_MESSAGE);
        result.put('cifId', app.Customer_Code__c);
        result.put('eligibilityChecked', true);
        result.put('checkEligibilityMessage', CHECK_ELIGIBILITY_SUCCESS_MESSAGE);
        return result;
    }

    /**
     * Get Existing EMI – stage 1 integration (stub until live API).
     */
    private static Map<String, Object> getExistingEmiDetailsInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);

        try {
            Id recordId = (Id) args.get('recordId');
            Id applicantId = (Id) args.get('applicantId');
            if (applicantId == null) {
                applicantId = getBorrowerApplicantId(recordId);
            }
            if (applicantId == null) {
                result.put('message', 'Applicant not found. Select the applicant tab and try again.');
                return result;
            }

            // Already fetched for this applicant — never re-run.
            if (hasApplicantFetchedExistingEmi(recordId, applicantId)) {
                result.put('isSuccess', true);
                result.put('message', 'Existing EMI details already retrieved.');
                return result;
            }

            ApplicationUtility.IntegrationResponseWrapper response =
                ApplicationUtility.invokeIntegrationSync(
                    EMI_INTEGRATION_MASTER_NAME, String.valueOf(applicantId), 'Applicant__c');

            if (response != null && response.hasValidationError) {
                result.put('message', String.isNotBlank(response.displayMessage)
                    ? response.displayMessage
                    : response.errorMessage);
                return result;
            }

            result.put('isSuccess', true);
            result.put('message', response != null && String.isNotBlank(response.displayMessage)
                ? response.displayMessage
                : 'EMI details retrieved');
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }
        return result;
    }

    /**
     * Get Exposure Details – stage 2 integration (stub until live API).
     */
    private static Map<String, Object> getExposureDetailsInternal(Map<String, Object> args) {
        return runDedupeIntegrationAction(
            args,
            CustomerDedupeIntegrationService.INTEGRATION_KEY_GET_EXPOSURE_DETAILS
        );
    }

    private static Map<String, Object> runDedupeIntegrationAction(
            Map<String, Object> args,
            String integrationKey) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);

        try {
            Id recordId = (Id) args.get('recordId');
            Id applicantId = (Id) args.get('applicantId');
            String cifId = (String) args.get('cifId');

            if (applicantId == null) {
                applicantId = getBorrowerApplicantId(recordId);
            }
            if (String.isBlank(cifId) && applicantId != null) {
                cifId = getApplicantCustomerCode(recordId, applicantId);
            }
            if (String.isBlank(cifId)) {
                result.put('message', 'Customer code (CIF) is required.');
                return result;
            }

            Map<String, Object> apiResult;
            if (CustomerDedupeIntegrationService.INTEGRATION_KEY_GET_EMI_DETAILS.equals(integrationKey)) {
                apiResult = CustomerDedupeIntegrationService.invokeGetEmiDetailsApi(
                    recordId,
                    applicantId,
                    cifId
                );
            } else if (CustomerDedupeIntegrationService.INTEGRATION_KEY_GET_EXPOSURE_DETAILS.equals(integrationKey)) {
                apiResult = CustomerDedupeIntegrationService.invokeGetExposureDetailsApi(
                    recordId,
                    applicantId,
                    cifId
                );
            } else {
                result.put('message', 'Unsupported integration: ' + integrationKey);
                return result;
            }

            if (!CustomerDedupeIntegrationService.isIntegrationSuccess(apiResult)) {
                result.put('message', CustomerDedupeIntegrationService.getIntegrationErrorMessage(apiResult));
                return result;
            }

            result.put('isSuccess', true);
            result.put('message', String.valueOf(apiResult.get('message')));
            result.put('integrationKey', integrationKey);
            result.put('integrationResult', apiResult);
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }

        return result;
    }

    /**
     * Ensures every active applicant has finished the dedupe journey before application-level Next.
     */
    private static void stampActiveApplicantsDedupeComplete(
            List<Applicant__c> activeApplicants,
            Id currentApplicantId,
            Boolean currentSessionComplete) {
        if (activeApplicants == null || activeApplicants.isEmpty()) {
            return;
        }
        for (Applicant__c app : activeApplicants) {
            if (isApplicantDedupeJourneyComplete(app, currentApplicantId, currentSessionComplete)) {
                markApplicantDedupeStepComplete(app.Id);
            }
        }
    }

    /**
     * Ensures every active applicant has finished the dedupe journey before application-level Next.
     */
    private static Map<String, Object> validateAllApplicantsDedupeCompleteInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);

        try {
            Id recordId = (Id) args.get('recordId');
            Id currentApplicantId = (Id) args.get('applicantId');
            Boolean currentSessionComplete = args.get('currentApplicantSessionComplete') == true;

            if (recordId == null) {
                result.put('message', 'Application Id is required.');
                return result;
            }

            List<String> pendingPriorLabels = getAdditionalApplicantsPendingPriorStageLabels(recordId);
            if (!pendingPriorLabels.isEmpty()) {
                result.put('pendingPriorStageApplicants', pendingPriorLabels);
                result.put('message', buildPendingPriorStagesMessage(pendingPriorLabels));
                return result;
            }

            List<Applicant__c> activeApplicants = [
                SELECT Id, Applicant_Tab_Label__c, Applicant_Type__c,
                       Customer_Code__c, Invalid_Customer_Code__c,
                       Current_Loan_Stage_Complete__c, Loan_Stage__c,
                       Check_Eligibility_Message__c, In_Active_Applicant__c
                FROM Applicant__c
                WHERE Application__c = :recordId AND In_Active_Applicant__c = false
                ORDER BY Applicant_Tab_Label__c
            ];

            List<Applicant__c> incompleteApplicants = new List<Applicant__c>();
            for (Applicant__c app : activeApplicants) {
                if (!isApplicantDedupeJourneyComplete(app, currentApplicantId, currentSessionComplete)) {
                    incompleteApplicants.add(app);
                }
            }

            if (!incompleteApplicants.isEmpty()) {
                incompleteApplicants.sort(new ApplicantDedupeLabelComparator());
                List<String> incompleteLabels = new List<String>();
                for (Applicant__c app : incompleteApplicants) {
                    incompleteLabels.add(resolveApplicantDisplayLabel(app));
                }
                result.put('incompleteApplicants', incompleteLabels);
                result.put(
                    'message',
                    buildIncompleteApplicantsMessage(incompleteLabels)
                );
                return result;
            }

            // Stamp completion only when the client confirms all gates passed (persistCompletion).
            // Early validation calls must stay read-only so a later UI check (e.g. NI constitution)
            // cannot leave applicants marked complete after a rejected Next.
            Boolean persistCompletion = args.get('persistCompletion') == true;
            if (persistCompletion) {
                stampActiveApplicantsDedupeComplete(
                    activeApplicants, currentApplicantId, currentSessionComplete);
            }

            result.put('isSuccess', true);
            result.put('message', 'All applicants have completed Dedupe and Eligibility.');
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }

        return result;
    }

    private static List<String> getApplicantsMissingDedupeMatchLabels(Id recordId) {
        List<String> labels = new List<String>();
        if (recordId == null) {
            return labels;
        }
        for (Applicant__c app : [
            SELECT Applicant_Tab_Label__c, Applicant_Type__c,
                   Customer_Code__c, Invalid_Customer_Code__c
            FROM Applicant__c
            WHERE Application__c = :recordId AND In_Active_Applicant__c = false
            ORDER BY Applicant_Tab_Label__c
        ]) {
            if (!hasApplicantDedupeMatchResolved(app)) {
                labels.add(resolveApplicantDisplayLabel(app));
            }
        }
        return labels;
    }

    private static String buildCombinedCustomerCodesPayload(Id recordId) {
        List<String> codes = new List<String>();
        for (Applicant__c app : [
            SELECT Customer_Code__c
            FROM Applicant__c
            WHERE Application__c = :recordId AND In_Active_Applicant__c = false
            ORDER BY Applicant_Tab_Label__c
        ]) {
            if (String.isNotBlank(app.Customer_Code__c)) {
                codes.add(app.Customer_Code__c.trim());
            }
        }
        return codes.isEmpty() ? null : String.join(codes, ',');
    }

    private static Boolean isApplicantLoanStagePastDedupe(Applicant__c app) {
        if (app == null) {
            return false;
        }
        String loanStage = String.isNotBlank(app.Loan_Stage__c) ? app.Loan_Stage__c.trim() : '';
        if (String.isBlank(loanStage)) {
            return false;
        }
        if (DEDUPE_STEP_NAME.equalsIgnoreCase(loanStage)) {
            return false;
        }
        return !STAGES_BEFORE_DEDUPE.contains(loanStage);
    }

    /**
     * True when Application__c has moved past the Dedupe and Eligibility step
     * (uses Application Stage__c / Sub_Stage__c — same source as stage navigation).
     */
    private static Boolean isApplicationPastDedupeStep(Id recordId) {
        if (recordId == null) {
            return false;
        }
        List<Application__c> apps = [
            SELECT Stage__c, Sub_Stage__c
            FROM Application__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return false;
        }
        Application__c app = apps[0];
        String mainStage = String.isNotBlank(app.Stage__c) ? app.Stage__c.trim() : '';
        String subStage = String.isNotBlank(app.Sub_Stage__c) ? app.Sub_Stage__c.trim() : '';
        if (DEDUPE_STEP_NAME.equalsIgnoreCase(subStage)) {
            return false;
        }
        if (STAGES_BEFORE_DEDUPE.contains(subStage)) {
            return false;
        }
        if (String.isNotBlank(mainStage) && !mainStage.equalsIgnoreCase('QDE')) {
            return true;
        }
        return String.isNotBlank(subStage);
    }

    private static Boolean hasApplicantCompletedDedupeStep(Applicant__c app) {
        if (app == null) {
            return false;
        }
        if (!isBorrowerApplicant(app)) {
            return hasApplicantDedupeMatchResolved(app);
        }
        if (String.isNotBlank(app.Current_Loan_Stage_Complete__c)
                && DEDUPE_STEP_NAME.equalsIgnoreCase(app.Current_Loan_Stage_Complete__c.trim())) {
            return true;
        }
        String loanStage = String.isNotBlank(app.Loan_Stage__c) ? app.Loan_Stage__c.trim() : '';
        if (String.isBlank(loanStage)) {
            return false;
        }
        if (DEDUPE_STEP_NAME.equalsIgnoreCase(loanStage)) {
            return false;
        }
        return !STAGES_BEFORE_DEDUPE.contains(loanStage);
    }

    /**
     * True once applicant reaches Dedupe stage (or any later stage).
     * Used to lock Borrower dedupe while newly-added applicants are still in previous stages.
     */
    private static Boolean hasApplicantReachedDedupeStage(Applicant__c app) {
        if (app == null) {
            return false;
        }
        String loanStage = String.isNotBlank(app.Loan_Stage__c) ? app.Loan_Stage__c.trim() : '';
        if (String.isBlank(loanStage)) {
            return false;
        }
        return !STAGES_BEFORE_DEDUPE.contains(loanStage);
    }

    private static void markApplicantDedupeStepComplete(Id applicantId) {
        if (applicantId == null) {
            return;
        }
        List<Applicant__c> apps = [
            SELECT Id, Applicant_Type__c, Current_Loan_Stage_Complete__c, Loan_Stage__c
            FROM Applicant__c
            WHERE Id = :applicantId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return;
        }
        Applicant__c app = apps[0];
        if (String.isNotBlank(app.Current_Loan_Stage_Complete__c)
                && DEDUPE_STEP_NAME.equalsIgnoreCase(app.Current_Loan_Stage_Complete__c.trim())) {
            return;
        }
        app.Current_Loan_Stage_Complete__c = DEDUPE_STEP_NAME;
        if (!isBorrowerApplicant(app)) {
            app.Loan_Stage__c = DEDUPE_STEP_NAME;
        } else if (String.isBlank(app.Loan_Stage__c)) {
            app.Loan_Stage__c = DEDUPE_STEP_NAME;
        }
        update app;
    }

    private static Boolean hasApplicantCompletedDedupeJourney(Applicant__c app) {
        return isEligibilityCheckComplete(app);
    }

    private static Boolean isEligibilityCheckComplete(Applicant__c app) {
        if (app == null) {
            return false;
        }
        if (String.isNotBlank(app.Check_Eligibility_Message__c)
                && CHECK_ELIGIBILITY_SUCCESS_MESSAGE.equalsIgnoreCase(
                    app.Check_Eligibility_Message__c.trim())) {
            return true;
        }
        return hasApplicantCompletedDedupeStep(app);
    }

    private static Boolean isApplicantDedupeJourneyComplete(
            Applicant__c app,
            Id currentApplicantId,
            Boolean currentSessionComplete) {
        if (app == null || app.In_Active_Applicant__c == true) {
            return true;
        }
        if (isBorrowerApplicant(app)) {
            if (hasApplicantCompletedDedupeStep(app)) {
                return true;
            }
            return currentApplicantId != null
                && app.Id == currentApplicantId
                && currentSessionComplete == true
                && isEligibilityCheckComplete(app);
        }
        if (hasApplicantDedupeMatchResolved(app)) {
            return true;
        }
        return currentApplicantId != null
            && app.Id == currentApplicantId
            && currentSessionComplete == true
            && hasApplicantDedupeMatchResolved(app);
    }

    private static Boolean isBorrowerApplicant(Applicant__c app) {
        return app != null && 'Borrower'.equalsIgnoreCase(String.valueOf(app.Applicant_Type__c));
    }

    private static Boolean isCoBorrowerApplicantType(String applicantType) {
        if (String.isBlank(applicantType)) {
            return false;
        }
        String normalized = applicantType.replaceAll('[^a-zA-Z]', '').toLowerCase();
        return normalized == 'coBorrower';
    }

    private static Boolean isGuarantorApplicantType(String applicantType) {
        return String.isNotBlank(applicantType)
            && 'Guarantor'.equalsIgnoreCase(applicantType.trim());
    }

    private static Boolean isBeneficiaryApplicantType(String applicantType) {
        return String.isNotBlank(applicantType)
            && 'Beneficiary'.equalsIgnoreCase(applicantType.trim());
    }

    /** Safely parse the optional 'applicantId' arg into an Id (null when absent/blank/malformed). */
    private static Id parseApplicantIdArg(Map<String, Object> args) {
        Object raw = args != null ? args.get('applicantId') : null;
        if (raw == null) {
            return null;
        }
        String rawStr = String.valueOf(raw).trim();
        if (String.isBlank(rawStr)) {
            return null;
        }
        try {
            return (Id) rawStr;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Resolves the applicant id for read-only page data. A supplied id is trusted only when it
     * belongs to this application; a blank/stale/foreign id falls back to the Borrower so the
     * page reflects the correct applicant. Used by the GET path, where the membership check
     * (one COUNT) also lets downstream helpers skip repeated Borrower lookups.
     */
    private static Id resolveApplicantId(Map<String, Object> args, Id recordId) {
        Id candidateId = parseApplicantIdArg(args);
        if (candidateId != null && isApplicantOfApplication(candidateId, recordId)) {
            return candidateId;
        }
        return getBorrowerApplicantId(recordId);
    }

    private static Boolean isApplicantOfApplication(Id applicantId, Id recordId) {
        if (applicantId == null || recordId == null) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM Applicant__c
            WHERE Id = :applicantId
            AND Application__c = :recordId
            AND In_Active_Applicant__c = false
        ] > 0;
    }

    /**
     * Fetches the Applicant record to act on for a Valid/Invalid decision in a single query
     * (no separate membership COUNT). The supplied id is trusted only when it belongs to this
     * application; a blank/stale/foreign id falls back to the Borrower, avoiding a spurious
     * "Applicant not found". Returns null only when no resolvable applicant exists.
     */
    private static Applicant__c resolveApplicantForMatchAction(Map<String, Object> args, Id recordId) {
        Id suppliedId = parseApplicantIdArg(args);
        if (suppliedId != null) {
            List<Applicant__c> supplied = queryApplicantForMatchAction(suppliedId, recordId);
            if (!supplied.isEmpty()) {
                return supplied[0];
            }
        }
        Id borrowerId = getBorrowerApplicantId(recordId);
        if (borrowerId == null) {
            return null;
        }
        List<Applicant__c> borrower = queryApplicantForMatchAction(borrowerId, recordId);
        return borrower.isEmpty() ? null : borrower[0];
    }

    private static List<Applicant__c> queryApplicantForMatchAction(Id applicantId, Id recordId) {
        return [
            SELECT Id, Customer_Code__c, Invalid_Customer_Code__c,
                   Relationship_with_Bank__c, Applicant_Type__c
            FROM Applicant__c
            WHERE Id = :applicantId AND Application__c = :recordId
            LIMIT 1
        ];
    }

    /**
     * Display label for validation toasts: tab label (G1, CoBo1), type (Guarantor), or both.
     */
    private static String resolveApplicantDisplayLabel(Applicant__c app) {
        String tabLabel = String.isNotBlank(app.Applicant_Tab_Label__c)
            ? app.Applicant_Tab_Label__c.trim()
            : null;
        String applicantType = String.isNotBlank(app.Applicant_Type__c)
            ? app.Applicant_Type__c.trim()
            : null;

        if (tabLabel != null && applicantType != null) {
            if (tabLabel.equalsIgnoreCase(applicantType)) {
                return tabLabel;
            }
            if ('Borrower'.equalsIgnoreCase(applicantType)) {
                return 'Borrower';
            }
            return applicantType + ' (' + tabLabel + ')';
        }
        if (tabLabel != null) {
            return tabLabel;
        }
        if (applicantType != null) {
            return applicantType;
        }
        return 'Applicant';
    }

    private static String buildPendingPriorStagesMessage(List<String> pendingLabels) {
        if (pendingLabels == null || pendingLabels.isEmpty()) {
            return 'Added applicant(s) must complete Lead Details, Basic Details, and KYC Details before you can proceed from the Borrower tab.';
        }
        if (pendingLabels.size() == 1) {
            return 'Complete Lead Details, Basic Details, and KYC Details for '
                + pendingLabels[0]
                + ' before proceeding from the Borrower tab.';
        }
        return 'Complete Lead Details, Basic Details, and KYC Details for the following applicant(s) before proceeding: '
            + String.join(pendingLabels, ', ')
            + '.';
    }

    private static String buildIncompleteApplicantsMessage(List<String> incompleteLabels) {
        if (incompleteLabels == null || incompleteLabels.isEmpty()) {
            return 'Complete Dedupe and Eligibility journey for all applicants before proceeding.';
        }
        if (incompleteLabels.size() == 1) {
            return 'Dedupe and Eligibility journey is pending for '
                + incompleteLabels[0]
                + '. Please complete it before proceeding.';
        }
        return 'Dedupe and Eligibility journey is pending for the following applicant(s): '
            + String.join(incompleteLabels, ', ')
            + '. Please complete them before proceeding.';
    }

    private class ApplicantDedupeLabelComparator implements System.Comparator<Applicant__c> {
        public Integer compare(Applicant__c a, Applicant__c b) {
            Integer orderA = applicantDisplaySortOrder(a);
            Integer orderB = applicantDisplaySortOrder(b);
            if (orderA != orderB) {
                return orderA - orderB;
            }
            String labelA = a != null && a.Applicant_Tab_Label__c != null ? a.Applicant_Tab_Label__c : '';
            String labelB = b != null && b.Applicant_Tab_Label__c != null ? b.Applicant_Tab_Label__c : '';
            return labelA.compareTo(labelB);
        }
    }

    private static Integer applicantDisplaySortOrder(Applicant__c app) {
        if (app == null) {
            return 99;
        }
        if (isBorrowerApplicant(app)) {
            return 0;
        }
        String tab = app.Applicant_Tab_Label__c;
        if (String.isNotBlank(tab)) {
            if (tab.startsWith('CoBo')) {
                return 1;
            }
            if (tab.startsWith('G')) {
                return 2;
            }
            if (tab.startsWith('B')) {
                return 3;
            }
        }
        return 4;
    }

    /**
     * Remove an applicant (soft delete)
     */
    private static Map<String, Object> removeApplicantInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isSuccess', false);
        
        try {
            Id applicantId = (Id) args.get('applicantId');
            List<Applicant__c> apps = [SELECT Id FROM Applicant__c WHERE Id = :applicantId LIMIT 1];
            if (apps.isEmpty()) {
                result.put('message', 'Applicant not found');
                return result;
            }
            
            apps[0].In_Active_Applicant__c = true;
            update apps[0];
            
            result.put('isSuccess', true);
            result.put('message', 'Applicant removed successfully');
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }
        
        return result;
    }
    
    /**
     * Positions new guarantor/co-borrower on Basic Details (QDE) for menu routing.
     * Ignores picklist errors so applicant insert is not rolled back.
     */
    private static void assignInitialApplicantLoanStage(List<Applicant__c> insertedApplicants) {
        if (insertedApplicants == null || insertedApplicants.isEmpty()) {
            return;
        }
        Map<String, String> qdeStep = dynamicStageNavigatorController.getInitialQdeStepForApplication(
            insertedApplicants[0].Application__c
        );
        String stepName = qdeStep.get('targetStep');
        if (String.isBlank(stepName)) {
            stepName = 'Basic Details';
        }
        List<Applicant__c> toUpdate = new List<Applicant__c>();
        for (Applicant__c app : insertedApplicants) {
            if (app.Id != null) {
                toUpdate.add(new Applicant__c(Id = app.Id, Loan_Stage__c = stepName));
            }
        }
        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'assignInitialApplicantLoanStage: ' + e.getMessage());
            }
        }
    }

    /**
     * Generate new customer code for NTB
     */
    private static String generateNewCustomerCode(Id recordId) {
        List<Applicant__c> existing = [
            SELECT Id, Customer_Code__c 
            FROM Applicant__c
            WHERE Application__c = :recordId 
            AND Customer_Code__c != null 
            AND Customer_Code__c LIKE 'CIF-N-%'
        ];
        
        Set<Integer> used = new Set<Integer>();
        for (Applicant__c a : existing) {
            String code = a.Customer_Code__c;
            if (code != null && code.startsWith('CIF-N-')) {
                String suffix = code.substring(6);
                if (suffix.isNumeric()) {
                    used.add(Integer.valueOf(suffix));
                }
            }
        }
        
        Integer seq = 1;
        while (used.contains(seq)) {
            seq++;
        }
        
        return 'CIF-N-' + String.valueOf(seq).leftPad(8, '0');
    }
    /**
     * Gets the integration master record for the given integration name.
     * @param integrationName - The name of the integration.
     * @return - The component reference for the given integration name.
     */
    @AuraEnabled
    public static Integration_Master__c getIntegrationMaster(String integrationName) {
        return [SELECT Id, Name, Component_Reference__c FROM Integration_Master__c WHERE Name =: integrationName LIMIT 1];
    }
}