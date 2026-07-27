public with sharing class BorrowerMasterPageController implements Callable {
    
    private static final String ACTION_GET_FIELDS = 'getFieldConfig';
    private static final String ACTION_GET_BORROWER_PAGE = 'getBorrowerPageData';
    private static final String ACTION_SAVE_BORROWER_PAGE = 'saveBorrowerPageData';
    private static final String BORROWER = 'Borrower';

    private SObject cachedOpp;
    private SObject cachedBorrower;
    private SObject cachedVehicle;
    private SObject cachedDocumentChecklist;

    private static final String APPLICATION_SELECT = 'Id,Name,Stage__c,Product__c,Application_number__c,' +
        'Sub_Stage__c,Loan_Source__c,Sub_Product__c,Branch__c,' +
        'Branch__r.Name,Total_Loan_Amount__c,Sanction_Date__c,Sanction_Status__c';
    private static final String APPLICANT_SELECT = 'Id,Applicant_Type__c,Profile__c,Company_Name__c,' +
        'Is_Income_Available__c,Declared_income__c,Is_PAN_Available__c,' +
        'Customer_First_Name__c,Customer_Last_Name__c,PAN_Number__c,Date_of_Birth__c,Gender__c,Marital_status__c,' +
        'Phone__c,Email__c,Phone_Verified__c,Email_Verified__c,Type__c,Residence_country__c,' +
        '(SELECT Id FROM Assets__r)';
    private static final String VEHICLE_SELECT = 'Id,Vehicle_type__c,' +
        'Variant__c,Purpose_of_purchase__c,Product_Segment__c';

    private static final Map<String, String> OPP_FIELD_MAP = new Map<String, String>{
        'productType' => 'Product__c',
        'applicationNumber' => 'Application_number__c',
        'agentBranchName' => 'Account.Name',
        'requiredLoanAmount' => 'Total_Loan_Amount__c',
        'sanctionDate' => 'Sanction_Date__c',
        'sanctionStatus' => 'Sanction_Status__c',
        'accountId' => 'Branch__c'
    };

    private static final Map<String, String> APPLICANT_FIELD_MAP = new Map<String, String>{
        'applicantType' => 'Applicant_Type__c',        
        'profileType' => 'Profile__c',
        'entityName' => 'Company_Name__c',        
        'incomeAvailable' => 'Is_Income_Available__c',
        'annualIncome' => 'Declared_income__c',
        'isPanAvailable' => 'Is_PAN_Available__c',
        'extractedFirstName' => 'Customer_First_Name__c',
        'extractedLastName' => 'Customer_Last_Name__c',
        'extractedPanCardNumber' => 'PAN_Number__c',
        'extractedDateOfBirth' => 'Date_of_Birth__c',
        'applicationType' => 'Type__c',
        'maritalStatus' => 'Marital_status__c',
        'residenceCountry' => 'Residence_Country__c',
        'contactNumber' => 'Phone__c',
        'email' => 'Email__c',
        'phoneVerified' => 'Phone_Verified__c',
        'emailVerified' => 'Email_Verified__c'
    };

    //private static final Set<String> ENCRYPTED_FIELDS = new Set<String>{ 'extractedPanCardNumber' };
    private static final Set<String> ENCRYPTED_FIELDS = new Set<String>();

    private static final Map<String, String> VEHICLE_FIELD_MAP = new Map<String, String>{
        'vehicleType' => 'Vehicle_type__c',
        'segment' => 'Product_Segment__c',
        'purposeOfPurchase' => 'Purpose_of_purchase__c'
    };
    private static final Map<String,String> DOCUMENT_CHECKLIST_MAP = new Map<String,String>{
        'contentVersionId' => 'ContentVersionId__c',
        'documentName' => 'Name'
        //'docType'=>'Retail_File_Type__c'
    };

    private static final String DEFAULT_PRODUCT_TYPE_OPTIONS = '[{"label":"Two Wheeler","value":"Two Wheeler"},{"label":"Four Wheeler","value":"Four Wheeler"}]';


    public Object call(String action, Map<String, Object> args) {
        if (ACTION_GET_BORROWER_PAGE.equalsIgnoreCase(action)) {
            return getBorrowerPageDataInternal(args);
        }
        if (ACTION_SAVE_BORROWER_PAGE.equalsIgnoreCase(action)) {
            return saveBorrowerPageDataInternal(args);
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> savePANDetails(String recordId, String panCardNumber, String dateOfBirth, String firstName, String lastName) {
        try {
            List<Applicant__c> applicants = [SELECT Id, PAN_Number__c, Date_of_Birth__c, Customer_First_Name__c, Customer_Last_Name__c FROM Applicant__c WHERE Application__c = :recordId AND Applicant_Type__c = 'Borrower'];
            if(applicants != NULL && !applicants.isEmpty()) {
                Applicant__c applicant = applicants[0];
                applicant.PAN_Number__c = panCardNumber;
                applicant.Date_of_Birth__c = Date.valueOf(dateOfBirth);
                applicant.Customer_First_Name__c = firstName;
                applicant.Customer_Last_Name__c = lastName;
                update applicant;
                return new Map<String, Object>{ 'isSuccess' => true, 'message' => 'PAN details saved successfully' };
            }
            else {
                return new Map<String, Object>{ 'isSuccess' => false, 'message' => 'Borrower not found' };
            }
        }
        catch (Exception e) {
            return new Map<String, Object>{ 'isSuccess' => false, 'message' => e.getMessage()};
        }
    }

    /**
     * AuraEnabled entry point. Returns Map with loanBasicInfo, loanDetail, professionalDetail as separate JSON elements.
     * @param recordId Opportunity/Loan Id
     * @return Map with keys: loanBasicInfo, loanDetail, professionalDetail (each List of field config maps)
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getBorrowerPageData(String recordId) {
        Map<String, Object> result = new Map<String, Object>{
            'loanBasicInfo' => new List<Map<String, Object>>(),
            'loanDetail' => new List<Map<String, Object>>(),
            'professionalDetail' => new List<Map<String, Object>>()
        };
        if (String.isBlank(recordId)) {
            return result;
        }
        try {
            BorrowerMasterPageController instance = new BorrowerMasterPageController();
            Map<String, Object> args = new Map<String, Object>{ 'recordId' => recordId };
            Object callResult = instance.call(ACTION_GET_BORROWER_PAGE, args);
            if (callResult instanceof Map<String, Object>) {
                return (Map<String, Object>) callResult;
            }
        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'getBorrowerPageData'+ 'Apex'+ '----> '+ e + '----> '+ recordId); 
            //ErrorLoggerUtil.logErrorEvent(
            //    'sfLOSLoanBasicInfoController',
            //    'getBorrowerPageData',
            //    'Apex',
            //    e,
            //    recordId
            //);
            throw new AuraHandledException('Error loading borrower page data: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Returns derived Agent Branch Name for the given account and product type from UI.
     * Call when Account lookup is populated to refresh the display.
     * Formula: Account.BranchCode__c + '_' + Account.Branch_IFSC_Code__c + '_' + productType + '_' + Account.Product_Type__c
     * @param recordId Opportunity/Loan Id (for error logging)
     * @param accountId Selected Account Id from lookup
     * @param productType Product Type from UI (Application Details) - not queried from Opportunity
     */
    @AuraEnabled(cacheable=false)
    public static String getAgentBranchName(String recordId, String accountId, String productType) {
        if (String.isBlank(recordId)) {
            return 'N/A';
        }
        if (String.isBlank(accountId)) {
            return 'N/A';
        }
        try {
            BorrowerMasterPageController instance = new BorrowerMasterPageController();
            String derived = instance.deriveAgentBranchName(productType, accountId);
            return String.isNotBlank(derived) ? derived : 'N/A';
        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'getBorrowerPageDataInternal'+ 'Apex'+ '----> '+ e + '----> '+ recordId); 
            /*ErrorLoggerUtil.logErrorEvent(
                'sfLOSLoanBasicInfoController',
                'getAgentBranchName',
                'Apex',
                e,
                recordId
            );*/
            return 'N/A';
        }
    }

    /**
     * Returns Map with loanBasicInfo, loanDetail, professionalDetail as separate JSON elements.
     */
    private Map<String, Object> getBorrowerPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'applicantTypeOptionsMap' => getApplicantTypeOptionsByCustomerType()
        };
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return result;
        }
        try {
            loadCachedData(recordId);
            flattenFields(result, getApplicationDetailsConfig(args));
            flattenFields(result, getLoanBasicInfoConfig(args));
            flattenFields(result, getLoanDetailConfig(args));
            flattenFields(result, getProfessionalDetailConfig(args));
            flattenFields(result, getDocumentVerificationConfig(args));
            flattenFields(result, getContactInfoConfig(args));
            if (cachedBorrower != null && cachedOpp != null) {
                String appType = (String) cachedBorrower.get('Applicant_Type__c');
                Boolean isNIBorrower = String.isNotBlank(appType) &&
                    ('Non Individual'.equalsIgnoreCase(appType.trim()) || 'Non-Individual'.equalsIgnoreCase(appType.trim()));
                String companyName = (String) cachedBorrower.get('Company_Name__c');
                if (isNIBorrower && String.isNotBlank(companyName)) {
                    result.put('entityName', companyName);
                }
            }
        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'getBorrowerPageDataInternal'+ 'Apex'+ '----> '+ e + '----> '+ recordId); 
            /*ErrorLoggerUtil.logErrorEvent(
                'sfLOSLoanBasicInfoController',
                'getBorrowerPageDataInternal',
                'Apex',
                e,
                recordId
            );*/
            throw new AuraHandledException('Error loading borrower page data: ' + e.getMessage());
        }
        return result;
    }

    private static void flattenFields(Map<String, Object> result, List<Map<String, Object>> fields) {
        if (fields == null) return;
        for (Map<String, Object> field : fields) {
            String key = (String) field.get('key');
            if (String.isNotBlank(key)) {
                result.put(key, field.get('value'));
            }
        }
    }

    private List<Map<String, Object>> getApplicationDetailsConfig(Map<String, Object> args) {
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return new List<Map<String, Object>>();
        }
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        try {
            SObject opp      = cachedOpp;
            SObject borrower = cachedBorrower;
            SObject vehicle  = (cachedVehicle != null) ? (SObject) cachedVehicle : (SObject) new Asset__c();
            if (opp == null) {
                return fields;
            }
             
            fields.add(new Map<String, Object>{
                'key' => 'productType',
                'value' => opp != null ? opp.get('Product__c') : null
            });
            fields.add(new Map<String, Object>{
                'key' => 'numberOfVehicles',
                'value' => vehicle != null ? '1' : null
            });
            fields.add(new Map<String, Object>{
                'key' => 'vehicleType',
                'value' => cachedVehicle != null ? cachedVehicle.get('Vehicle_Type__c') : null
            });
            
            fields.add(new Map<String, Object>{
                'key' => 'applicantType',
                'value' => borrower != null ? borrower.get('Applicant_Type__c') : ''
            });
            fields.add(new Map<String, Object>{
                'key' => 'entityName',
                'value' => borrower != null ? borrower.get('Company_Name__c') : ''
            });
            fields.add(new Map<String, Object>{
                'key' => 'applicationType',
                'value' => borrower != null ? borrower.get('Type__c') : ''
            });
            /*
            fields.add(new Map<String, Object>{
                'key' => 'segment',
                'value' => vehicle != null ? vehicle.get('Product_Segment__c') : null
            });*/
            fields.add(new Map<String, Object>{
                'key' => 'loanStage',
                'value' => opp != null ? opp.get('Sub_Stage__c') : null
            });
        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'getApplicationDetailsConfig'+ 'Apex'+ '----> '+ e + '----> '+ recordId); 
            /*ErrorLoggerUtil.logErrorEvent('sfLOSLoanBasicInfoController', 'getApplicationDetailsConfig', 'Apex', e, recordId);*/
            throw new AuraHandledException('Error loading application details: ' + e.getMessage());
        }
        return fields;
    }

    private List<Map<String, Object>> getContactInfoConfig(Map<String, Object> args) {
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return new List<Map<String, Object>>();
        }
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        try {
            SObject borrower = cachedBorrower;
            if (borrower == null) {
                return fields;
            }
            fields.add(new Map<String, Object>{
                'key' => 'maritalStatus',
                'value' => borrower != null ? (String)borrower.get('Marital_status__c') : ''
            });
            fields.add(new Map<String, Object>{
                'key' => 'residenceCountry',
                'value' => borrower != null ? (String) borrower.get('Residence_Country__c') : ''
            });
            fields.add(new Map<String, Object>{
                'key' => 'contactNumber',
                'value' => borrower != null ? (String) borrower.get('Phone__c') : ''
            });
            fields.add(new Map<String, Object>{
                'key' => 'email',
                'value' => borrower != null ? (String) borrower.get('Email__c') : ''
            });
            fields.add(new Map<String, Object>{
                'key' => 'phoneVerified',
                'value' => borrower != null ?  borrower.get('Phone_Verified__c') : ''
            });
            fields.add(new Map<String, Object>{
                'key' => 'emailVerified',
                'value' => borrower != null ?  borrower.get('Email_Verified__c') : ''
            });

        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'getContactInfoConfig'+ 'Apex'+ '----> '+ e + '----> '+ recordId); 
            /*ErrorLoggerUtil.logErrorEvent('sfLOSLoanBasicInfoController', 'getContactInfoConfig', 'Apex', e, recordId);*/
            throw new AuraHandledException('Error loading contact info: ' + e.getMessage());
        }
        return fields;
    }

    private void loadCachedData(Id recordId) {
        cachedOpp = queryApplication(recordId);
        cachedBorrower = queryBorrowerApplicant(recordId);
        Set<Id> assetIds = new Set<Id>();
        if (cachedBorrower != null) {
            List<SObject> assets = cachedBorrower.getSObjects('Assets__r');
            if (assets != null) {
                for (SObject asset : assets) {
                    assetIds.add((Id) asset.get('Id'));
                }
            }
        }
        cachedVehicle = assetIds.isEmpty() ? null : queryVehicleDetail(assetIds);
        Id borrowerId = cachedBorrower != null ? (Id) cachedBorrower.get('Id') : null;
        cachedDocumentChecklist = borrowerId != null ? queryDocumentChecklist(borrowerId) : null;
    }

    private List<Map<String, Object>> getLoanBasicInfoConfig(Map<String, Object> args) {
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return new List<Map<String, Object>>();
        }

        List<Map<String, Object>> fields = new List<Map<String, Object>>();

        try {
            SObject opp      = cachedOpp;
            SObject borrower = cachedBorrower;
            SObject vehicle  = cachedVehicle;

            String productType       = opp != null ? (String) opp.get('Product__c') : null;
            String vehicleType       = vehicle != null ? (String) vehicle.get('Vehicle_type__c') : null;
            Object accountIdObj      = opp != null ? opp.get('Branch__c') : null;
            String accountId         = accountIdObj != null ? String.valueOf(accountIdObj) : null;
            SObject relatedAccount   = opp != null ? opp.getSObject('Branch__r') : null;
            String accountName       = relatedAccount != null ? (String) relatedAccount.get('Name') : null;
            String agentBranchName   = deriveAgentBranchName(productType, accountId);
            String purposeOfPurchase = vehicle != null ? (String) vehicle.get('Purpose_of_purchase__c') : null;
            String leadNumber        = opp != null ? (String) opp.get('Application_number__c') : null;
            

            fields.add(new Map<String, Object>{
                'key' => 'accountId',
                'value' => accountId
            });
            fields.add(new Map<String, Object>{
                'key' => 'accountName',
                'value' => accountName
            });
            fields.add(new Map<String, Object>{
                'key' => 'leadNumber',
                'value' => leadNumber
            });
            fields.add(new Map<String, Object>{
                'key' => 'vehicleType',
                'value' => vehicleType
            });
            fields.add(new Map<String, Object>{
                'key' => 'agentBranchName',
                'value' => String.isNotBlank(agentBranchName) ? agentBranchName : 'N/A'
            });
            fields.add(new Map<String, Object>{
                'key' => 'purposeOfPurchase',
                'value' => purposeOfPurchase
            });
            
            /*
            // visibleWhen supports AND, OR, NOT and nested combinations. Sample complex conditions:
            // AND:  'visibleWhen' => Map{ 'operator'=>'AND', 'conditions'=>List{ Map{'field'=>'a','value'=>'x'}, Map{'field'=>'b','value'=>'y'} } }
            // OR:   'visibleWhen' => Map{ 'operator'=>'OR', 'conditions'=>List{ Map{'field'=>'a','value'=>'x'}, Map{'field'=>'a','value'=>'y'} } }
            // NOT:  'visibleWhen' => Map{ 'operator'=>'NOT', 'condition'=>Map{'field'=>'a','value'=>'x'} }
            // NE:   Leaf Map{ 'field'=>'a', 'value'=>'x', 'operator'=>'NE' }  -- field != value
            // In:   Leaf Map{ 'field'=>'a', 'value'=>List{'x','y','z'} }  -- field in array
            // hasValue: Map{ 'field'=>'a', 'operator'=>'hasValue' }  -- field has any value
            // Combined (A AND B) OR (C AND D): Map{ 'operator'=>'OR', 'conditions'=>List{ Map{operator=>AND,conditions=>...}, Map{operator=>AND,conditions=>...} } }
            // Combined NOT (A OR B): Map{ 'operator'=>'NOT', 'condition'=>Map{ 'operator'=>'OR', 'conditions'=>List{...} } }
            */

        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'getFieldConfig'+ 'Apex'+ '----> '+ e + '----> '+ recordId);   
            /*ErrorLoggerUtil.logErrorEvent(
                'sfLOSLoanBasicInfoController',
                'getFieldConfig',
                'Apex',
                e,
                recordId
            );*/
            throw new AuraHandledException('Error loading loan basic info: ' + e.getMessage());
        }

        return fields;
    }

    private List<Map<String, Object>> getLoanDetailConfig(Map<String, Object> args) {
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return new List<Map<String, Object>>();
        }
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        try {
            SObject opp     = cachedOpp;
            SObject vehicle = cachedVehicle;

            Object segmentObj        = vehicle != null ? vehicle.get('Product_Segment__c') : null;
            String segment           = (segmentObj != null && String.isNotBlank(String.valueOf(segmentObj)))
                                        ? String.valueOf(segmentObj) : 'Motorcycle';
            Object reqLoanObj        = opp != null ? opp.get('Total_Loan_Amount__c') : null;
            String requiredLoanAmount = reqLoanObj != null ? String.valueOf(reqLoanObj) : '';

            fields.add(new Map<String, Object>{
                'key' => 'segment',
                'value' => segment
            });
            fields.add(new Map<String, Object>{
                'key' => 'requiredLoanAmount',
                'value' => requiredLoanAmount
            });
            
        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'getLoanDetailConfig'+ 'Apex'+ '----> '+ e + '----> '+ recordId); 
            /*ErrorLoggerUtil.logErrorEvent('sfLOSLoanBasicInfoController', 'getLoanDetailConfig', 'Apex', e, recordId);*/
            throw new AuraHandledException('Error loading loan detail: ' + e.getMessage());
        }
        return fields;
    }

    private List<Map<String, Object>> getProfessionalDetailConfig(Map<String, Object> args) {
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return new List<Map<String, Object>>();
        }
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        try {
            SObject borrower = cachedBorrower;
            if (borrower == null) {
                return fields;
            }

            String profileType      = borrower != null ? (String) borrower.get('Profile__c') : null;
            String incomeAvailable  = borrower != null ? (String) borrower.get('Is_Income_Available__c') : null;
            Object annualIncomeObj  = borrower != null ? borrower.get('Declared_income__c') : null;
            String annualIncome     = annualIncomeObj != null ? String.valueOf(annualIncomeObj) : '';

            fields.add(new Map<String, Object>{
                'key' => 'profileType',
                'value' => profileType
            });
            fields.add(new Map<String, Object>{
                'key' => 'incomeAvailable',
                'value' => incomeAvailable
            });
            fields.add(new Map<String, Object>{
                'key' => 'annualIncome',
                'value' => annualIncome
            });
            

        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'getProfessionalDetailConfig'+ 'Apex'+ '----> '+ e + '----> '+ recordId); 
            /*ErrorLoggerUtil.logErrorEvent('sfLOSLoanBasicInfoController', 'getProfessionalDetailConfig', 'Apex', e, recordId);*/
            throw new AuraHandledException('Error loading professional detail: ' + e.getMessage());
        }
        return fields;
    }

    private List<Map<String, Object>> getDocumentUploadConfig(Map<String, Object> args) {
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return new List<Map<String, Object>>();
        }
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        try {
            SObject opp = cachedOpp;
            if (opp == null) {
                return fields;
            }

            fields.add(new Map<String, Object>{ 
                'key' => 'panCardUploadElement',
                'value' => null
            });

        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'getDocumentUploadConfig'+ 'Apex'+ '----> '+ e + '----> '+ recordId); 
            /*ErrorLoggerUtil.logErrorEvent('sfLOSLoanBasicInfoController', 'getDocumentUploadConfig', 'Apex', e, recordId);*/
            throw new AuraHandledException('Error loading document upload: ' + e.getMessage());
        }
        return fields;
    }

    private List<Map<String, Object>> getDocumentVerificationConfig(Map<String, Object> args) {
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return new List<Map<String, Object>>();
        }
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        try {
            SObject opp = cachedOpp;
            if (opp == null) {
                return fields;
            }
            SObject borrower            = cachedBorrower;
            SObject documentChecklist   = cachedDocumentChecklist;

            String contentVersionId = documentChecklist != null ? (String) documentChecklist.get('ContentVersionId__c') : null;
            String documentName     = documentChecklist != null ? (String) documentChecklist.get('Name') : null;

            String isPanAvailable       = borrower != null ? (String) borrower.get('Is_PAN_Available__c') : null;
            String extractedFirstName   = borrower != null ? (String) borrower.get('Customer_First_Name__c') : null;
            String extractedLastName    = borrower != null ? (String) borrower.get('Customer_Last_Name__c') : null;
            Object dobObj               = borrower != null ? borrower.get('Date_of_Birth__c') : null;
            String extractedDateOfBirth = dobObj != null ? String.valueOf(dobObj) : null;
            String extractedPanCardNumber = '';
            
            if (borrower != null) {
                String panNumber = (String) borrower.get('PAN_Number__c');
                if (String.isNotBlank(panNumber)) {
                    try {
                        extractedPanCardNumber =panNumber;/* SFLOS_IntegrationUtilities.getDecryptedResponse(
                            panNumber, System.Label.privateKey, System.Label.ivkey
                        );*/
                    } catch (Exception decEx) {
                        extractedPanCardNumber = panNumber;
                    }
                }
            }

            fields.add(new Map<String, Object>{ 
                'key' => 'isPanAvailable',
                'value' => isPanAvailable
            });

            fields.add(new Map<String, Object>{ 
                'key' => 'panCardUploadElement',
                'value' => contentVersionId != null ? new Map<String, Object>{ 'fileName' => documentName, 'contentVersionId' => contentVersionId } : null
            });

            fields.add(new Map<String, Object>{ 
                'key' => 'form60UploadElement',
                'value' => null
            });

            fields.add(new Map<String, Object>{ 
                'key' => 'extractedFirstName',
                'value' => extractedFirstName
            });
            fields.add(new Map<String, Object>{ 
                'key' => 'extractedLastName',
                'value' => extractedLastName
            });
            Boolean hasExtractedPanCardNumber = extractedPanCardNumber != null && extractedPanCardNumber.length() == 10;
            fields.add(new Map<String, Object>{ 
                'key' => 'extractedPanCardNumber',
                'value' => extractedPanCardNumber
            });
            fields.add(new Map<String, Object>{ 
                'key' => 'extractedDateOfBirth',
                'value' => extractedDateOfBirth
            });
            fields.add(new Map<String, Object>{ 
                'key' => 'pancardVerificationStatus',
                'value' => (hasExtractedPanCardNumber ? 'success' : 'idle')
            });

        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'getDocumentVerificationConfig'+ 'Apex'+ '----> '+ e + '----> '+ recordId);
            //ErrorLoggerUtil.logErrorEvent('sfLOSLoanBasicInfoController', 'getDocumentVerificationConfig', 'Apex', e, recordId);
            throw new AuraHandledException('Error loading document verification: ' + e.getMessage());
        }
        return fields;
    }

    private SObject queryApplication(Id recordId) {
        List<SObject> listApplication = Database.query(
            'SELECT ' + APPLICATION_SELECT + ' FROM Application__c WHERE Id = :recordId WITH SECURITY_ENFORCED LIMIT 1'
        );
        return listApplication.isEmpty() ? null : listApplication[0];
    }

    private SObject queryBorrowerApplicant(Id recordId) {
        List<SObject> listApp = Database.query(
            'SELECT ' + APPLICANT_SELECT + ' FROM Applicant__c WHERE Application__c = :recordId AND Applicant_Type__c = :BORROWER WITH SECURITY_ENFORCED LIMIT 1'
        );
        return listApp.isEmpty() ? null : listApp[0];
    }

    /**
     * Returns Applicant_Type__c options mapped by Customer_Type__c (controlling field) from schema.
     * Delegates to GenericUtility.fetchControlledByDependentToSchema for dynamic schema derivation.
     */
    private static Map<String, List<Map<String, String>>> getApplicantTypeOptionsByCustomerType() {
        return GenericUtility.fetchControlledByDependentToSchema('Applicant__c', 'Applicant_Type__c');
    }

    private SObject queryVehicleDetail(Set<Id> recordIds) {
        List<SObject> listVd = Database.query(
            'SELECT ' + VEHICLE_SELECT + ' FROM Asset__c WHERE Id = :recordIds WITH SECURITY_ENFORCED LIMIT 1'
        );
        return listVd.isEmpty() ? null : listVd[0];
    }

    /**
     * Derives Agent Branch Name from Account + product type.
     * Formula: Account.BranchCode__c + '_' + Account.Branch_IFSC_Code__c + '_' + productType + '_' + Account.Product_Type__c
     * @param productType Product Type (from UI or Opportunity.Product_Type__c)
     * @param accountId Selected Account Id
     */
    private String deriveAgentBranchName(String productType, String accountId) {
        if (String.isBlank(accountId)) {
            return 'N/A';
        }
        try {
            List<SObject> accounts = Database.query(
                'SELECT BranchCode__c, Branch_IFSC_Code__c, Product_Type__c FROM Account WHERE Id = :accountId WITH SECURITY_ENFORCED LIMIT 1'
            );
            if (accounts.isEmpty()) {
                return 'N/A';
            }
            SObject acc = accounts[0];
            String branchCode    = String.isNotBlank((String) acc.get('BranchCode__c'))      ? (String) acc.get('BranchCode__c')      : '';
            String branchIfsc    = String.isNotBlank((String) acc.get('Branch_IFSC_Code__c')) ? (String) acc.get('Branch_IFSC_Code__c') : '';
            String oppProductType = GenericUtility.getProductTypeShortForm(productType);
            String accProductType = GenericUtility.getProductTypeShortForm((String) acc.get('Product_Type__c'));
            List<String> parts = new List<String>{ branchCode, branchIfsc, oppProductType, accProductType };
            String derived = String.join(parts, '_');
            return String.isNotBlank(derived) ? derived : 'N/A';
        } catch (Exception e) {
            return 'N/A';
        }
    }

    private Map<String, Object> saveBorrowerPageDataInternal(Map<String, Object> args) {
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return new Map<String, Object>{ 'isSuccess' => false, 'message' => 'Record ID is required' };
        }
        try {
            loadCachedData(recordId);
            List<SObject> toUpdate = new List<SObject>();

            String applicationType = args.containsKey('applicationType') ? String.valueOf(args.get('applicationType')) : null;
            Boolean isNI = String.isNotBlank(applicationType) &&
                ('Non Individual'.equalsIgnoreCase(applicationType.trim()) || 'Non-Individual'.equalsIgnoreCase(applicationType.trim()));

            if (!isNI) {
                args.put('customerType', 'Individual');
            }

            if (cachedOpp != null) {
                applyFieldValues(cachedOpp, args, OPP_FIELD_MAP, 'Application__c');
                toUpdate.add(cachedOpp);
            }
            if (cachedBorrower != null) {
                if (isNI && args.containsKey('entityName') && String.isNotBlank(String.valueOf(args.get('entityName')))) {
                    cachedBorrower.put('Company_Name__c', String.valueOf(args.get('entityName')));
                }
                applyFieldValues(cachedBorrower, args, APPLICANT_FIELD_MAP, 'Applicant__c');
                cachedBorrower.put('Applicant_Type__c', 'Borrower');
                toUpdate.add(cachedBorrower);
            }
            if (cachedVehicle != null) {
                applyFieldValues(cachedVehicle, args, VEHICLE_FIELD_MAP, 'Asset__c');
                toUpdate.add(cachedVehicle);
            }

            if (cachedDocumentChecklist != null) {
                extractFileFieldsToArgs(args, 'panCardUploadElement');
                applyFieldValues(cachedDocumentChecklist, args, DOCUMENT_CHECKLIST_MAP, 'Document_Checklist__c');
                toUpdate.add(cachedDocumentChecklist);
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        } catch (Exception e) {
            System.debug('BorrowerMasterPageController'+ 'saveBorrowerPageDataInternal'+ 'Apex'+ '----> '+ e + '----> '+ recordId); 
            //ErrorLoggerUtil.logErrorEvent('sfLOSLoanBasicInfoController', 'saveBorrowerPageDataInternal', 'Apex', e, recordId);
            return new Map<String, Object>{ 'isSuccess' => false, 'message' =>  e.getMessage() };
        }
        return new Map<String, Object>{ 'isSuccess' => true, 'message' => 'Borrower page data saved successfully' };
    }

    /**
     * Extracts contentVersionId and documentName from a file field object (e.g. panCardUploadElement).
     * Handles both Map<String, Object> (direct) and JSON-deserialized representations from LWC params.
     */
    private void extractFileFieldsToArgs(Map<String, Object> args, String fileFieldKey) {
        Object fileVal = args.get(fileFieldKey);
        if (fileVal == null) return;
        Map<String, Object> fileMap = null;
        if (fileVal instanceof Map<String, Object>) {
            fileMap = (Map<String, Object>) fileVal;
        } else {
            try {
                String jsonStr = fileVal instanceof String ? (String) fileVal : JSON.serialize(fileVal);
                fileMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
            } catch (Exception e) {
                return;
            }
        }
        if (fileMap != null) {
            Object cvId = fileMap.get('contentVersionId');
            if (cvId != null && String.isNotBlank(String.valueOf(cvId))) {
                args.put('contentVersionId', String.valueOf(cvId));
            }
            Object fName = fileMap.get('fileName');
            if (fName != null && String.isNotBlank(String.valueOf(fName))) {
                args.put('documentName', String.valueOf(fName));
            }
        }
    }

    private void applyFieldValues(SObject record, Map<String, Object> args, Map<String, String> fieldMap, String objectName) {
        if (record == null || args == null || fieldMap == null) return;
        Map<String, Schema.SObjectField> schemaFields = Schema.getGlobalDescribe()
            .get(objectName).getDescribe().fields.getMap();

        for (String jsonKey : fieldMap.keySet()) {
            if (!args.containsKey(jsonKey)) continue;
            String fieldApiName = fieldMap.get(jsonKey);
            Schema.SObjectField sField = schemaFields.get(fieldApiName.toLowerCase());
            if (sField == null) continue;
            Schema.DescribeFieldResult dfr = sField.getDescribe();
            if (!dfr.isUpdateable()) continue;

            Object rawValue = args.get(jsonKey);
            if (ENCRYPTED_FIELDS.contains(jsonKey) && rawValue != null && String.isNotBlank(String.valueOf(rawValue))) {
                rawValue = '';/*SFLOS_IntegrationUtilities.getEncryptedRequest(
                    String.valueOf(rawValue),
                    System.Label.privateKey,
                    System.Label.ivkey
                );*/
            }
            record.put(dfr.getName(), convertValue(rawValue, dfr.getType()));
        }
    }

    private SObject queryDocumentChecklist(Id recordId) {
        List<SObject> listDoc = Database.query(
            'SELECT Id, ContentVersionId__c, Name FROM Document_Checklist__c WHERE Applicant__c = :recordId AND Document_Type__c  =\'Initial_DOC_Verification\' LIMIT 1'
        );
        cachedDocumentChecklist = listDoc.isEmpty() ? null : listDoc[0];
        return cachedDocumentChecklist;
    }

    private Object convertValue(Object rawValue, Schema.DisplayType fieldType) {
        if (rawValue == null) return null;
        String strValue = String.valueOf(rawValue);
        if (String.isBlank(strValue)) return null;

        switch on fieldType {
            when CURRENCY, DOUBLE, PERCENT {
                return Decimal.valueOf(strValue);
            }
            when INTEGER {
                return Integer.valueOf(strValue);
            }
            when DATE {
                return GenericUtility.parseDateValue(strValue);
            }
            when DATETIME {
                return Datetime.valueOf(strValue);
            }
            when BOOLEAN {
                return Boolean.valueOf(strValue);
            }
            when else {
                return strValue;
            }
        }
    }
}