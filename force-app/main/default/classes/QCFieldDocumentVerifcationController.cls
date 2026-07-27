/**
 * @description Core controller for field/document verification.
 * Keeps mandatory/core logic and shared wrapper classes.
 */
public with sharing class QCFieldDocumentVerifcationController {
    
    // ========== PERFORMANCE OPTIMIZATION: STATIC CACHES ==========
    // These caches last for the transaction and prevent redundant metadata queries
    private static Map<String, List<Field_Verification_Config__mdt>> cachedFieldConfigs;
    private static Map<String, Schema.SObjectType> globalDescribeCache;
    private static Map<String, Map<String, Schema.SObjectField>> fieldDescribeCache = new Map<String, Map<String, Schema.SObjectField>>();
    // Cache for loan application queries to avoid duplicate queries in isQCNeeded flow
    private static Map<Id, Application__c> cachedLoanApplications = new Map<Id, Application__c>();

    /**
     * @description Get comprehensive verification status for all fields in a loan application
     * @param loanApplicationId The ResidentialLoanApplication ID
     * @param queryDocumentChecklist Whether to query Document_Checklist__c (true from LWC, false from isQCNeeded)
     * @return List of verification status results grouped by object
     */
    @AuraEnabled(cacheable=false)
    public static List<VerificationStatusResult> getVerificationStatusForLoan(Id loanApplicationId, Boolean queryDocumentChecklist) {
        List<VerificationStatusResult> results = new List<VerificationStatusResult>();
        
        Long startTime = System.currentTimeMillis();
        System.debug('⏱️ START: getVerificationStatusForLoan');
        
        try {
            
            // Step 0: Get the Loan Application with all required fields (cached for reuse)
            Application__c cachedLoanApp = getLoanApplicationForQC(loanApplicationId);
            if (cachedLoanApp == null) {
                System.debug('❌ Loan Application not found: ' + loanApplicationId);
                return results;
            }
            
            // Get the RecordType for this loan (for filtering sections) - reuse cached loan app
            String recordTypeName = getRecordTypeForLoan(loanApplicationId, cachedLoanApp);
           
            // Step 1: Query all QC_Verification_Parent__mdt records
            String parentConfigQuery = 'SELECT Id, SectionName__c, ObjectName__c, ObjectLevel__c,' +
                ' QueryType__c, RelationshipQueryName__c, ParentObjectParameter__c,' +
                ' ParentLookupField__c, WhereClause__c, ColumnsUsedInWhereClause__c,' +
                ' FieldNametoShowas_Label__c, Active__c, DocumentCheckListLookfield__c,' +
                ' Verification_Fields_Lookup_Mapping__c, Parent_QC_Section_Name__c,' +
                ' ParentDocumentCheckListLookfield__c,' +
                ' Product__c , Order_By_Clause__c, LIMIT__c';
    
            parentConfigQuery += ' FROM QC_Verification_Parent__mdt WHERE Active__c = true ORDER BY ObjectLevel__c, ObjectName__c';
            List<QC_Verification_Parent__mdt> allParents = Database.query(parentConfigQuery);
            
            // Step 1.5: Filter by record type (Product__c field contains comma-separated RecordType values like "HL,EL")
            List<QC_Verification_Parent__mdt> filteredParents = new List<QC_Verification_Parent__mdt>();
            for (QC_Verification_Parent__mdt parent : allParents) {
                // If Product__c is blank, include for all products
                // If Product__c has value (comma-separated RecordTypes), check if current RecordType is included
                if (String.isBlank(parent.Product__c) || 
                    parent.Product__c.contains(recordTypeName)) {
                    filteredParents.add(parent);
                    System.debug('   ✅ Including section: ' + parent.SectionName__c + ' (Product__c: ' + parent.Product__c + ')');
                } 
            }
            
            allParents = filteredParents;
            
            // Step 2: Group metadata by QueryType and Parent Section + Parent Object
            List<QC_Verification_Parent__mdt> dedicatedQueries = new List<QC_Verification_Parent__mdt>();
            Map<String, List<QC_Verification_Parent__mdt>> childQueriesByParentGroup = new Map<String, List<QC_Verification_Parent__mdt>>();
            
            for (QC_Verification_Parent__mdt parent : allParents) {
                if (parent.QueryType__c == 'DedicatedQuery') {
                    dedicatedQueries.add(parent);
                } else if (parent.QueryType__c == 'ChildQuery') {
                    // Group by Parent_QC_Section_Name__c instead of ParentObjectParameter__c
                    String parentSectionName = parent.Parent_QC_Section_Name__c;
                    if (String.isBlank(parentSectionName)) {
                        // Fallback to old logic for backward compatibility
                        parentSectionName = parent.ParentObjectParameter__c;
                    }
                    
                    String parentObjectName = parent.ParentObjectParameter__c;
                    String parentGroupKey = parentSectionName + '||' + (parentObjectName != null ? parentObjectName : '');
                    if (!childQueriesByParentGroup.containsKey(parentGroupKey)) {
                        childQueriesByParentGroup.put(parentGroupKey, new List<QC_Verification_Parent__mdt>());
                    }
                    childQueriesByParentGroup.get(parentGroupKey).add(parent);
                }
            }
            
            
            // Step 3: Get all field configs - Group by Parent Metadata ID to handle multiple sections
            Map<String, List<Field_Verification_Config__mdt>> fieldConfigsByParentId = new Map<String, List<Field_Verification_Config__mdt>>();
            
            // Build dynamic query to handle fields that may not exist yet
            String fieldConfigQuery = 'SELECT Id, MasterLabel, Field_Name__c, isPickList__c, ' +
                                     'QC_Verification_Parent__c, ' +
                                     'QC_Verification_Parent__r.ObjectName__c, ' +
                                     'QC_Verification_Parent__r.SectionName__c, ' +
                                     'Document_Master_Name__c, Integration_Master__c, Exact_Match__c';
            
            // Add isJson__c and Json_Field_Value__c if they exist
            if (hasField('Field_Verification_Config__mdt', 'isJson__c')) {
                fieldConfigQuery += ', isJson__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Json_Field_Value__c')) {
                fieldConfigQuery += ', Json_Field_Value__c';
            }
            
            // Add optional fields if they exist
            // Try both possible field names for Child Section
            Boolean hasChildSection = false;
            if (hasField('Field_Verification_Config__mdt', 'Child_Section__c')) {
                fieldConfigQuery += ', Child_Section__c';
                hasChildSection = true;
            } else if (hasField('Field_Verification_Config__mdt', 'Child_Section_Name__c')) {
                fieldConfigQuery += ', Child_Section_Name__c';
                hasChildSection = true;
            }
            if (hasField('Field_Verification_Config__mdt', 'WhereClause__c')) {
                fieldConfigQuery += ', WhereClause__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'AdditionalColumnsToQuery__c')) {
                fieldConfigQuery += ', AdditionalColumnsToQuery__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Additional_Doc_Field_Check__c')) {
                fieldConfigQuery += ', Additional_Doc_Field_Check__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Additional_Document_API_Name_To_Filter__c')) {
                fieldConfigQuery += ', Additional_Document_API_Name_To_Filter__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Additional_Document_Value_To_Filter__c')) {
                fieldConfigQuery += ', Additional_Document_Value_To_Filter__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Checklist_Mapping_Field__c')) {
                fieldConfigQuery += ', Checklist_Mapping_Field__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Fallback_To_Parent_Document__c')) {
                fieldConfigQuery += ', Fallback_To_Parent_Document__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Reference_Object_Name__c')) {
                fieldConfigQuery += ', Reference_Object_Name__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Is_Date_Field__c')) {
                fieldConfigQuery += ', Is_Date_Field__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Date_Field_Format__c')) {
                fieldConfigQuery += ', Date_Field_Format__c';
            }
            
            fieldConfigQuery += ' FROM Field_Verification_Config__mdt ' +
                              'WHERE QC_Verification_Parent__r.Active__c = true AND Active__c = true';
            
            System.debug('📝 Field Config Query: ' + fieldConfigQuery);
            
            List<Field_Verification_Config__mdt> allFieldConfigs = Database.query(fieldConfigQuery);
            System.debug('⏱️ Step 3 (Field Configs): ' + (System.currentTimeMillis() - startTime) + 'ms');
            
            for (Field_Verification_Config__mdt config : allFieldConfigs) {
                String parentId = config.QC_Verification_Parent__c;
                if (!fieldConfigsByParentId.containsKey(parentId)) {
                    fieldConfigsByParentId.put(parentId, new List<Field_Verification_Config__mdt>());
                }
                fieldConfigsByParentId.get(parentId).add(config);
            }
            
            // Step 4: Query all Verified_Fields__c for this loan (dynamically based on metadata)
            Map<String, Verified_Fields__c> verifiedFieldsMap = getLatestVerifiedFieldsForLoan(loanApplicationId, allParents);
            
            // Step 4.5: Query all Document_Checklist__c for this loan ONCE (dynamically based on metadata)
            // Only query documents if requested (skip for isQCNeeded to improve performance)
            Map<String, Map<String, List<Document_Checklist__c>>> documentsByRecordId = new Map<String, Map<String, List<Document_Checklist__c>>>();
            List<Document_Checklist__c> allDocumentsList = new List<Document_Checklist__c>();
            Set<String> documentLookupFields = new Set<String>();
            if (queryDocumentChecklist) {
                Map<String, Object> documentResults = getDocumentsForLoan(loanApplicationId, allParents, allFieldConfigs);
                documentsByRecordId = (Map<String, Map<String, List<Document_Checklist__c>>>) documentResults.get('documentsByRecordId');
                allDocumentsList = (List<Document_Checklist__c>) documentResults.get('allDocumentsList');
                documentLookupFields = (Set<String>) documentResults.get('documentLookupFields');
            }
            
            // Step 5: Process Dedicated Queries
            Long step5Start = System.currentTimeMillis();
            
            for (QC_Verification_Parent__mdt parent : dedicatedQueries) {
                Long queryStart = System.currentTimeMillis();
                List<VerificationStatusResult> dedicatedResults = processDedicatedQuery(
                    parent, loanApplicationId, fieldConfigsByParentId, verifiedFieldsMap, documentsByRecordId, allDocumentsList, allFieldConfigs, documentLookupFields
                );
                System.debug('   ⏱️ ' + parent.ObjectName__c + ': ' + (System.currentTimeMillis() - queryStart) + 'ms');
                
                // If no results returned, create an empty placeholder section
                if (dedicatedResults.isEmpty()) {
                    VerificationStatusResult emptySection = new VerificationStatusResult();
                    emptySection.recordId = null;
                    emptySection.recordLabel = 'No records';
                    emptySection.sectionName = parent.SectionName__c;
                    emptySection.objectName = parent.ObjectName__c;
                    emptySection.objectLevel = parent.ObjectLevel__c != null ? Integer.valueOf(parent.ObjectLevel__c) : null;
                    emptySection.fields = new List<FieldVerificationStatus>();
                    emptySection.isEmpty = true;
                    dedicatedResults.add(emptySection);
                }
                
                results.addAll(dedicatedResults);
            }
            
            // Step 6: Process Child Queries - grouped by Parent Section Name
            Long step6Start = System.currentTimeMillis();
            
            for (String parentGroupKey : childQueriesByParentGroup.keySet()) {
                Long queryStart = System.currentTimeMillis();
                List<QC_Verification_Parent__mdt> childMetaList = childQueriesByParentGroup.get(parentGroupKey);
                if (childMetaList == null || childMetaList.isEmpty()) {
                    continue;
                }
                QC_Verification_Parent__mdt firstChildMeta = childMetaList[0];
                String parentSectionName = firstChildMeta.Parent_QC_Section_Name__c;
                if (String.isBlank(parentSectionName)) {
                    parentSectionName = firstChildMeta.ParentObjectParameter__c;
                }
                
                List<VerificationStatusResult> childResults = processChildQueries(
                    parentSectionName, 
                    childMetaList, 
                    loanApplicationId, 
                    fieldConfigsByParentId, 
                    verifiedFieldsMap,
                    documentsByRecordId,
                    allDocumentsList,
                    allFieldConfigs,
                    documentLookupFields
                );
                System.debug('   ⏱️ Parent Group ' + parentGroupKey + ': ' + (System.currentTimeMillis() - queryStart) + 'ms');
                
                // If no child results returned, create an empty placeholder for the parent section
                // Use the first child metadata to get the parent section info
                if (childResults.isEmpty()) {
                    if (!childMetaList.isEmpty()) {
                        QC_Verification_Parent__mdt firstChild = childMetaList[0];
                        VerificationStatusResult emptySection = new VerificationStatusResult();
                        emptySection.recordId = null;
                        emptySection.recordLabel = 'No records';
                        emptySection.sectionName = firstChild.SectionName__c;
                        emptySection.objectName = firstChild.ObjectName__c;
                        emptySection.objectLevel = firstChild.ObjectLevel__c != null ? Integer.valueOf(firstChild.ObjectLevel__c) : null;
                        emptySection.parentSectionName = parentSectionName;
                        emptySection.fields = new List<FieldVerificationStatus>();
                        emptySection.isEmpty = true;
                        childResults.add(emptySection);
                    }
                }
                
                results.addAll(childResults);
            }
            
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CPC Controller Error: ' + e.getMessage() + ' | RecordId: ' + loanApplicationId);
            throw new AuraHandledException('Error getting verification status: ' + e.getMessage());
        }
        System.debug('⏱️ TOTAL TIME: ' + (System.currentTimeMillis() - startTime) + 'ms');
        return results;
    }

    @AuraEnabled(cacheable=false)
    public static QCValidationCallbackResult runOnLoadValidationCallback(Id recordId) {
        QCValidationCallbackResult response = new QCValidationCallbackResult();

        if (recordId == null) {
            response.hasWErrors = true;
            response.validationMessages.add(
                new QCValidationCallbackResult.QCValidationMessage(
                    'Validation Configuration',
                    'Record Id is required.',
                    'ERROR'
                )
            );
            return response;
        }

        try {
            String sourceObjectName = recordId.getSObjectType().getDescribe().getName();

            List<QC_Admin_Console__mdt> callbackConfigs = [
                SELECT ValidateActionCallback__c
                FROM QC_Admin_Console__mdt
                WHERE SourceObject__c = :sourceObjectName
                AND isActive__c = true
                LIMIT 1
            ];

            if (callbackConfigs.isEmpty() || String.isBlank(callbackConfigs[0].ValidateActionCallback__c)) {
                return response;
            }

            String callbackClassName = callbackConfigs[0].ValidateActionCallback__c.trim();
            Type callbackType = Type.forName(callbackClassName);
            if (callbackType == null) {
                response.hasWErrors = true;
                response.validationMessages.add(
                    new QCValidationCallbackResult.QCValidationMessage(
                        'Validation Configuration',
                        'Validation callback class not found: ' + callbackClassName,
                        'ERROR'
                    )
                );
                return response;
            }

            Object callbackObj = callbackType.newInstance();
            if (!(callbackObj instanceof QCValidationCallback)) {
                response.hasWErrors = true;
                response.validationMessages.add(
                    new QCValidationCallbackResult.QCValidationMessage(
                        'Validation Configuration',
                        'Validation callback must implement QCValidationCallback: ' + callbackClassName,
                        'ERROR'
                    )
                );
                return response;
            }

            QCValidationCallback callback = (QCValidationCallback) callbackObj;
            Map<String, Object> context = new Map<String, Object>{
                'recordId' => recordId,
                'sourceObject' => sourceObjectName
            };

            QCValidationCallbackResult callbackResult = callback.onLoad(context);
            if (callbackResult != null) {
                response = callbackResult;
                if (response.validationMessages == null) {
                    response.validationMessages = new List<QCValidationCallbackResult.QCValidationMessage>();
                }
            }
        } catch (Exception ex) {
            response.hasWErrors = true;
            response.validationMessages = new List<QCValidationCallbackResult.QCValidationMessage>{
                new QCValidationCallbackResult.QCValidationMessage(
                    'Validation Execution',
                    'Validation callback execution failed: ' + ex.getMessage(),
                    'ERROR'
                )
            };
        }

        return response;
    }

    @AuraEnabled(cacheable=false)
    public static QCActionCallbackResult runActionCallback(Id recordId, String methodName, String inputData, String outputData, Boolean isEventAction) {
        QCActionCallbackResult response = new QCActionCallbackResult();

        if (recordId == null) {
            response.success = false;
            response.message = 'Record Id is required.';
            return response;
        }

        try {
            String sourceObjectName = recordId.getSObjectType().getDescribe().getName();
            List<QC_Admin_Console__mdt> callbackConfigs = [
                SELECT CustomActionCallback__c
                FROM QC_Admin_Console__mdt
                WHERE SourceObject__c = :sourceObjectName
                AND isActive__c = true
                LIMIT 1
            ];

            String callbackClassName = 'QCActionCallback1';
            if (!callbackConfigs.isEmpty() && String.isNotBlank(callbackConfigs[0].CustomActionCallback__c)) {
                callbackClassName = callbackConfigs[0].CustomActionCallback__c.trim();
            }

            Type callbackType = Type.forName(callbackClassName);
            if (callbackType == null) {
                response.success = false;
                response.message = 'Action callback class not found: ' + callbackClassName;
                return response;
            }

            Object callbackObj = callbackType.newInstance();
            if (!(callbackObj instanceof QCActionCallbackInterface)) {
                response.success = false;
                response.message = 'Action callback must implement QCActionCallbackInterface: ' + callbackClassName;
                return response;
            }

            QCActionCallbackInterface callback = (QCActionCallbackInterface) callbackObj;

            String effectiveInputData = inputData;
            if (String.isBlank(effectiveInputData)) {
                effectiveInputData = '{}';
            }
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(effectiveInputData);
            payload.put('recordId', recordId);
            effectiveInputData = JSON.serialize(payload);

            String callbackJson;
            if (isEventAction == true) {
                callbackJson = callback.executeHandleEventAction(methodName, effectiveInputData, outputData);
            } else {
                callbackJson = callback.executeOnClickAction(methodName, effectiveInputData, outputData);
            }

            if (!String.isBlank(callbackJson)) {
                response = (QCActionCallbackResult) JSON.deserialize(callbackJson, QCActionCallbackResult.class);
            }
        } catch (Exception ex) {
            response.success = false;
            response.message = 'Action callback execution failed: ' + ex.getMessage();
        }

        return response;
    }


@AuraEnabled(cacheable=false)
public static Map<String, Object> checkUserPermissions(Id loanApplicationId) {
    Map<String, Object> result = new Map<String, Object>();
    
    try {
        Id currentUserId = UserInfo.getUserId();
        
        // Get current user's profile and persona
        User currentUser = [
            SELECT Id, Profile.Name  
            FROM User 
            WHERE Id = :currentUserId 
            LIMIT 1
        ];
        
        // Check if Admin
        Boolean isAdmin = currentUser.Profile.Name.containsIgnoreCase('System Administrator') || 
                          currentUser.Profile.Name.containsIgnoreCase('Admin');
        
        // Get loan status and owner (single query - optimized)
        Application__c loan = [
            SELECT Id, Stage__c, OwnerId 
            FROM Application__c
            WHERE Id = :loanApplicationId 
            LIMIT 1
        ];
        
        Boolean isOwner = currentUser.Id == loan.OwnerId;
 
        // Check if current user is the owner's manager (only if owner exists)
        Boolean isOwnerManager = false;
        if (loan.OwnerId != null) {
            
            User owner = [
                SELECT Id, ManagerId 
                FROM User 
                WHERE Id = :loan.OwnerId 
                LIMIT 1
            ];
            if(owner != null && owner.ManagerId == currentUserId){
                isOwnerManager = true;
            }
            
        }
        
        // Determine if user can edit
        // Allow admins, owners, and owner's manager.
        Boolean canEdit = isAdmin || isOwner || isOwnerManager;
        
        result.put('canEdit', canEdit);
        
        return result;
        
    } catch (Exception e) {
        result.put('canEdit', false);
        System.debug(LoggingLevel.ERROR, 'CPC Controller Error: ' + e.getMessage() + ' | RecordId: ' + loanApplicationId);
        return result;
    }
}


    /**
     * @description Save field verifications in batch
     * @param verificationData JSON string containing verification updates
     * @return Success message
     */
    @AuraEnabled
    public static String saveFieldVerification(String verificationData) {
        try {
            
            List<Object> updates = (List<Object>) JSON.deserializeUntyped(verificationData);
            
            List<Verified_Fields__c> recordsToUpsert = new List<Verified_Fields__c>();
            Set<Id> fieldVerificationIds = new Set<Id>();
            Set<String> objectNames = new Set<String>();
            
            // Collect existing IDs and object names
            for (Object updateObj : updates) {
                Map<String, Object> updateData = (Map<String, Object>) updateObj;
                String fieldVerificationId = (String) updateData.get('fieldVerificationId');
                String objectName = (String) updateData.get('objectName');
                
                if (String.isNotBlank(objectName)) {
                    objectNames.add(objectName);
                }
                
                if (String.isNotBlank(fieldVerificationId)) {
                    try {
                        fieldVerificationIds.add(Id.valueOf(fieldVerificationId));
                    } catch (Exception e) {
                        System.debug('⚠️ Invalid ID: ' + fieldVerificationId);
                        System.debug(LoggingLevel.ERROR, 'CPC QC Controller Error: ' + e.getMessage() + ' | RecordId: ' + fieldVerificationId);
                    }
                }
            }
            
            // Query ALL active metadata to get ALL possible lookup fields
            List<QC_Verification_Parent__mdt> allMetadata = [
                SELECT ObjectName__c, Verification_Fields_Lookup_Mapping__c, ParentObjectParameter__c
                FROM QC_Verification_Parent__mdt
                WHERE Active__c = true
            ];
            
            System.debug('📋 ALL Active Metadata ObjectNames: ');
            for (QC_Verification_Parent__mdt m : allMetadata) {
                System.debug('   - ' + m.ObjectName__c + ' → Lookup: ' + m.Verification_Fields_Lookup_Mapping__c + ' → Parent: ' + m.ParentObjectParameter__c);
            }
            
            // Build complete set of ALL lookup fields from metadata
            // CRITICAL: We need ALL possible lookup fields to avoid SOQL errors when clearing fields
            Set<String> allLookupFields = new Set<String>();
            allLookupFields.add('Loan_Application__c'); // Always include - set by populateLookupFields
            allLookupFields.add('Loan_Applicant__c');   // Always include - set by populateLookupFields for child objects
            
            for (QC_Verification_Parent__mdt meta : allMetadata) {
                if (String.isNotBlank(meta.Verification_Fields_Lookup_Mapping__c)) {
                    String fieldName = meta.Verification_Fields_Lookup_Mapping__c.trim();
                    if (String.isNotBlank(fieldName)) {
                        allLookupFields.add(fieldName);
                    }
                }
            }
            
            // Now get mappings for the specific objects being saved
            Map<String, String> objectToLookupMapping = new Map<String, String>();
            Map<String, String> objectToParentObjectName = new Map<String, String>();
            
            if (!objectNames.isEmpty()) {
                for (QC_Verification_Parent__mdt meta : allMetadata) {
                    if (objectNames.contains(meta.ObjectName__c)) {
                        objectToLookupMapping.put(meta.ObjectName__c, meta.Verification_Fields_Lookup_Mapping__c);
                        objectToParentObjectName.put(meta.ObjectName__c, meta.ParentObjectParameter__c);
                    }
                }
            }
            
            
            // Query existing records - ALWAYS include ALL lookup fields to avoid SOQL errors when clearing
            Map<Id, Verified_Fields__c> existingRecords = new Map<Id, Verified_Fields__c>();
            if (!fieldVerificationIds.isEmpty()) {
                String queryFields = 'Id, Field_Name__c, Status__c, Manually_Verification_Comments__c, ' +
                                    'Field_Value__c, ' +
                                    String.join(new List<String>(allLookupFields), ', ');
                String query = 'SELECT ' + queryFields + ' FROM Verified_Fields__c WHERE Id IN :fieldVerificationIds';
                
                System.debug('📋 Query: ' + query);
                
                List<Verified_Fields__c> existingRecordsList = (List<Verified_Fields__c>)Database.query(query);
                existingRecords = new Map<Id, Verified_Fields__c>(existingRecordsList);
            }
            
            // Process each update
            Integer updateCount = 0;
            Integer createCount = 0;
            
            for (Object updateObj : updates) {
                Map<String, Object> updateData = (Map<String, Object>) updateObj;
                String fieldVerificationId = (String) updateData.get('fieldVerificationId');
                String verificationStatus = (String) updateData.get('verificationStatus');
                String verificationComments = (String) updateData.get('verificationComments');
                String fieldName = (String) updateData.get('fieldName');
                String applicantId = (String) updateData.get('applicantId');
                String fieldValue = (String) updateData.get('fieldValue');
                String recordId = (String) updateData.get('recordId');
                String objectName = (String) updateData.get('objectName');
                String loanApplicationId = (String) updateData.get('loanApplicationId');
                String verifiedStatusDocumentNames = (String) updateData.get('verifiedStatusDocumentNames');
                String verifiedStatusDocumentIds = (String) updateData.get('verifiedStatusDocumentIds');
                
                // Get lookup mapping from metadata
                String lookupMapping = objectToLookupMapping.get(objectName);
                
                // Determine parentRecordId dynamically based on ParentObjectParameter__c
                String parentObjectName = objectToParentObjectName.get(objectName);
                String parentRecordId = null;
                
                if (isLoanApplicationObject(parentObjectName)) {
                    // Parent is ResidentialLoanApplication or no parent - use null
                    parentRecordId = null;
                } else if (isApplicantObject(parentObjectName)) {
                    // Parent is LoanApplicant - use applicantId
                    parentRecordId = applicantId; 
                } else {
                    parentRecordId = null;
                }
                
                Verified_Fields__c vf = null;
                
                if (String.isNotBlank(fieldVerificationId) && 
                    existingRecords.containsKey(Id.valueOf(fieldVerificationId))) {
                    // Update existing
                    System.debug('✏️ Updating existing record: ' + fieldVerificationId);
                    vf = existingRecords.get(Id.valueOf(fieldVerificationId));
                    vf.Field_Value__c = fieldValue;
                    vf.Status__c = verificationStatus;
                    vf.Manually_Verification_Comments__c = verificationComments;
                    vf.Manually_Verified_Date__c = System.now();
                    vf.Manually_Verified_By__c = UserInfo.getUserId();
                    vf.Verified_Status_Document_Names__c = normalizeCsvValue(verifiedStatusDocumentNames);
                    vf.Verified_Status_Document_Id__c = normalizeCsvValue(verifiedStatusDocumentIds);
                    
                    // CRITICAL: Clear all lookup fields first to avoid cross-contamination
                    // Do this dynamically for all lookup fields
                    System.debug('🧹 Clearing lookup fields: ' + allLookupFields);
                    for (String lookupField : allLookupFields) {
                        try {
                            vf.put(lookupField, null);
                        } catch (Exception e) {
                            System.debug(LoggingLevel.ERROR, 'CPC Controller Error: ' + e.getMessage() + ' | RecordId: ' + loanApplicationId);
                        }
                    }
                    
                    // populateLookupFields: parentRecordId is determined dynamically based on metadata
                    populateLookupFields(vf, lookupMapping, loanApplicationId, recordId, parentRecordId);
                    recordsToUpsert.add(vf);
                    updateCount++;
                } else {
                    // Create new
                    vf = new Verified_Fields__c();
                    vf.Field_Name__c = fieldName;
                    vf.Field_Value__c = fieldValue;
                    vf.Status__c = verificationStatus;
                    vf.Manually_Verification_Comments__c = verificationComments;
                    vf.Manually_Verified_Date__c = System.now();
                    vf.Manually_Verified_By__c = UserInfo.getUserId();
                    vf.Verified_Status_Document_Names__c = normalizeCsvValue(verifiedStatusDocumentNames);
                    vf.Verified_Status_Document_Id__c = normalizeCsvValue(verifiedStatusDocumentIds);
                    // populateLookupFields: parentRecordId is determined dynamically based on metadata
                    populateLookupFields(vf, lookupMapping, loanApplicationId, recordId, parentRecordId);
                    recordsToUpsert.add(vf);
                    createCount++;
                }
            }
            
            // Upsert all records
            if (!recordsToUpsert.isEmpty()) {
                upsert recordsToUpsert;
                System.debug('✅ Upsert completed successfully');
                
                // Query back to verify
                Set<Id> upsertedIds = new Set<Id>();
                for (Verified_Fields__c vfRecord : recordsToUpsert) {
                    if (vfRecord.Id != null) {
                        upsertedIds.add(vfRecord.Id);
                    }
                }
            }
            
            System.debug('✅ COMPLETE: saveFieldVerification');
            return 'Success';
            
        } catch (Exception e) {
            throw new AuraHandledException('Error saving verification: ' + e.getMessage());
        }
    }

    public static String normalizeCsvValue(String csvValue) {
        if (String.isBlank(csvValue)) {
            return null;
        }
        List<String> values = new List<String>();
        for (String part : csvValue.split(',')) {
            if (String.isNotBlank(part)) {
                values.add(part.trim());
            }
        }
        if (values.isEmpty()) {
            return null;
        }
        values.sort();
        return String.join(values, ',');
    }
    
    // ============================================================================
    // PRIVATE HELPER METHODS
    // ============================================================================
    
    /**
     * Get all Document_Checklist__c records for a loan (query ONCE for all related records)
     * DYNAMICALLY determines which lookup fields to query based on metadata configuration
     * 
     * Returns Map with 'documentsByRecordId' and 'allDocumentsList'
     * 
     * @param loanApplicationId The loan application ID
     * @param metadataRecords All QC_Verification_Parent__mdt records to extract DocumentCheckListLookfield__c from
     * @param allFieldConfigs All Field_Verification_Config__mdt records to extract additional filter fields from
     */
    public static Map<String, Object> getDocumentsForLoan(
        Id loanApplicationId,
        List<QC_Verification_Parent__mdt> metadataRecords,
        List<Field_Verification_Config__mdt> allFieldConfigs
    ) {
        // Map structure: Lookup Record ID → Document Sub Category → List of Document_Checklist__c records
        Map<String, Map<String, List<Document_Checklist__c>>> resultMap = new Map<String, Map<String, List<Document_Checklist__c>>>();
        List<Document_Checklist__c> allDocumentsList = new List<Document_Checklist__c>();
        Set<String> documentLookupFields = new Set<String>(); // Declare outside try block to use in return
        
        try {
            // Step 1: Extract all unique DocumentCheckListLookfield__c values from metadata
            for (QC_Verification_Parent__mdt meta : metadataRecords) {
                if (String.isNotBlank(meta.DocumentCheckListLookfield__c)) {
                    System.debug('📋 Checking metadata: ' + meta.SectionName__c + ' → DocumentCheckListLookfield__c: ' + meta.DocumentCheckListLookfield__c);
                    // Validate that the field exists on Document_Checklist__c
                    if (isValidField('Document_Checklist__c', meta.DocumentCheckListLookfield__c)) {
                        documentLookupFields.add(meta.DocumentCheckListLookfield__c);
                    } 
                }
                String parentDocumentLookupField = getOptionalMetadataString(meta, 'ParentDocumentCheckListLookfield__c');
                if (String.isNotBlank(parentDocumentLookupField) &&
                    isValidField('Document_Checklist__c', parentDocumentLookupField)) {
                    documentLookupFields.add(parentDocumentLookupField);
                }
            }
            
            // Always include the standard applicant lookup (backward compatibility)
            if (isValidField('Document_Checklist__c', 'Applicant__c')) {
                documentLookupFields.add('Applicant__c');
            }
            
            
            // Step 2: Build dynamic SOQL query only if we have valid lookup fields
            if (documentLookupFields.isEmpty()) {
                // No valid lookup fields found, return empty result
                Map<String, Object> returnMap = new Map<String, Object>();
                returnMap.put('documentsByRecordId', resultMap);
                returnMap.put('allDocumentsList', allDocumentsList);
                returnMap.put('documentLookupFields', documentLookupFields); // Pass lookup fields for filtering
                return returnMap;
            }
            
            // Step 1.5: Extract additional filter fields from Field_Verification_Config__mdt
            Set<String> additionalFilterFields = new Set<String>();
            if (allFieldConfigs != null) {
                for (Field_Verification_Config__mdt config : allFieldConfigs) {
                    try {
                        Boolean additionalDocFieldCheck = (Boolean) config.get('Additional_Doc_Field_Check__c');
                        if (additionalDocFieldCheck == true) {
                            String filterFieldApiName = (String) config.get('Additional_Document_API_Name_To_Filter__c');
                            if (String.isNotBlank(filterFieldApiName) && 
                                isValidField('Document_Checklist__c', filterFieldApiName)) {
                                additionalFilterFields.add(filterFieldApiName);
                            }
                        }
                    } catch (Exception e) {
                        system.debug('❌ ERROR in getDocumentsForLoan: ' + e.getMessage());
                        continue;
                    }
                }
            }
            
            String baseQuery = 
                'SELECT Id, Document_Type__c, CreatedDate, ';
            
            // Add all lookup fields to SELECT
            List<String> lookupFieldsList = new List<String>(documentLookupFields);
            baseQuery += String.join(lookupFieldsList, ', ');
            
            // Add additional filter fields to SELECT if any
            if (!additionalFilterFields.isEmpty()) {
                List<String> filterFieldsList = new List<String>(additionalFilterFields);
                baseQuery += ', ' + String.join(filterFieldsList, ', ');
            }
            
            // Add ContentDocumentLinks subquery
            baseQuery += ', (SELECT ContentDocumentId, ContentDocument.LatestPublishedVersionId, ' +
                        'ContentDocument.Title, ContentDocument.FileExtension, ' +
                        'ContentDocument.ContentSize ' +
                        'FROM ContentDocumentLinks ' +
                        'ORDER BY ContentDocument.CreatedDate DESC) ';
            
            baseQuery += 'FROM Document_Checklist__c ' +
                        'WHERE Application__c = :loanApplicationId ' +
                        'ORDER BY CreatedDate asc';
            
           // System.debug('🔍 Document Checklist Query: ' + baseQuery);
          //  System.debug('🔍 Loan Application ID: ' + loanApplicationId);
            
            // Step 3: Execute query
            List<Document_Checklist__c> allDocChecklists = Database.query(baseQuery);
            allDocumentsList = allDocChecklists; // Store all documents for filtering later
            
            // Step 4: Group by lookup record ID, then by Document Sub Category
            Integer processedCount = 0;
            Integer skippedCount = 0;
            
            for (Document_Checklist__c docCheck : allDocChecklists) {
                
                String docType = resolveDocumentTypeValue(docCheck);
                if (String.isNotBlank(docType)) {
                    
                    // Collect ALL non-null lookup keys for this document - group by each one
                    List<String> lookupKeys = new List<String>();
                    for (String lookupField : documentLookupFields) {
                        try {
                            Object fieldValue = docCheck.get(lookupField);
                            if (fieldValue != null && String.isNotBlank(String.valueOf(fieldValue))) {
                                String keyValue = String.valueOf(fieldValue);
                                lookupKeys.add(keyValue);
                            }
                        } catch (Exception e) {
                           system.debug('❌ ERROR in getDocumentsForLoan: ' + e.getMessage());
                           continue;
                        }
                    }
                    
                    // Group by ALL lookup keys found (document can belong to multiple objects)
                    if (!lookupKeys.isEmpty()) {
                        for (String lookupKey : lookupKeys) {
                            // Initialize inner map if needed
                            if (!resultMap.containsKey(lookupKey)) {
                                resultMap.put(lookupKey, new Map<String, List<Document_Checklist__c>>());
                            }
                            
                            // Store ALL documents with the same subcategory - keep all, not just one
                            Map<String, List<Document_Checklist__c>> docsBySubCategory = resultMap.get(lookupKey);
                            
                            if (!docsBySubCategory.containsKey(docType)) {
                                docsBySubCategory.put(docType, new List<Document_Checklist__c>());
                            }
                            
                            // Add this document to the list for this subcategory
                            docsBySubCategory.get(docType).add(docCheck);
                                processedCount++;
                        }
                    } else {
                        skippedCount++;
                    }
                } else {
                    skippedCount++;
                }
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CPC QC Controller Error: ' + e.getMessage() + ' | RecordId: ' + loanApplicationId);
        }
        
        Map<String, Object> returnMap = new Map<String, Object>();
        returnMap.put('documentsByRecordId', resultMap);
        returnMap.put('allDocumentsList', allDocumentsList);
        returnMap.put('documentLookupFields', documentLookupFields);
        return returnMap;
    }
    
    /**
     * Get all lookup (reference) fields from Verified_Fields__c object dynamically
     * This ensures we query ALL lookup fields regardless of metadata configuration
     * @return Set of lookup field API names
     */
    public static Set<String> getAllLookupFieldsFromVerifiedFields() {
        Set<String> lookupFields = new Set<String>();
        
        // Get the Verified_Fields__c object type
        Schema.SObjectType verifiedFieldsType = Schema.getGlobalDescribe().get('Verified_Fields__c');
        if (verifiedFieldsType == null) {
            return lookupFields;
        }
        
        // Get all fields on the object
        Map<String, Schema.SObjectField> fieldMap = verifiedFieldsType.getDescribe().fields.getMap();
        
        // Loop through all fields and find reference (lookup) fields
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            
            // Check if this is a reference (lookup/master-detail) field
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                String apiName = fieldDescribe.getName();
                lookupFields.add(apiName);
            }
        }
       
        return lookupFields;
    }
    
    /**
     * Get latest Verified_Fields__c records for a loan
     * DYNAMICALLY determines which lookup fields to query based on metadata configuration
     * 
     * @param loanApplicationId The loan application ID
     * @param metadataRecords All QC_Verification_Parent__mdt records to extract Verification_Fields_Lookup_Mapping__c from
     */
    public static Map<String, Verified_Fields__c> getLatestVerifiedFieldsForLoan(
        Id loanApplicationId,
        List<QC_Verification_Parent__mdt> metadataRecords
    ) {
        Map<String, Verified_Fields__c> resultMap = new Map<String, Verified_Fields__c>();
        
        try {
            // Step 1: Get ALL lookup fields dynamically from Verified_Fields__c object
            Set<String> verificationLookupFields = getAllLookupFieldsFromVerifiedFields();
            Set<String> mappedLookupFields = new Set<String>();
            if (metadataRecords != null) {
                for (QC_Verification_Parent__mdt meta : metadataRecords) {
                    if (meta != null && String.isNotBlank(meta.Verification_Fields_Lookup_Mapping__c)) {
                        mappedLookupFields.add(meta.Verification_Fields_Lookup_Mapping__c.trim());
                    }
                }
            }
            
            System.debug('📊 All lookup fields found on Verified_Fields__c: ' + verificationLookupFields);
            
            // Step 2: Build dynamic SOQL query
            String baseQuery = 'SELECT Id, Field_Name__c, Status__c, Field_Value__c, ' +
                             'Manually_Verification_Comments__c, ' +
                             'Manually_Verified_Date__c, Verified_Status_Document_Names__c, Verified_Status_Document_Id__c, CreatedDate';
            
            // Add all lookup fields to SELECT
            if (!verificationLookupFields.isEmpty()) {
                baseQuery += ', ' + String.join(new List<String>(verificationLookupFields), ', ');
            }
            // Generic link field (text) used as canonical record matcher where configured.
            if (hasField('Verified_Fields__c', 'sObjectLinkId__c')) {
                baseQuery += ', sObjectLinkId__c';
            }
            
            baseQuery += ' FROM Verified_Fields__c ' +
                        'WHERE Loan_Application__c = :loanApplicationId ' +
                        'ORDER BY Manually_Verified_Date__c DESC NULLS LAST, CreatedDate DESC, Id DESC';
            
            System.debug('📋 Verified_Fields__c Query: ' + baseQuery);
            
            // Step 3: Execute query
            List<Verified_Fields__c> allVerifiedFields = Database.query(baseQuery);
            
            System.debug('📊 Total Verified_Fields__c records queried: ' + allVerifiedFields.size());
            
            // Step 4: Group by recordId + fieldName (keep only latest)
            Map<String, Integer> duplicateCount = new Map<String, Integer>();
            for (Verified_Fields__c vf : allVerifiedFields) {
                // Primary generic key: sObjectLinkId__c when available.
                if (hasField('Verified_Fields__c', 'sObjectLinkId__c')) {
                    try {
                        Object genericLinkId = vf.get('sObjectLinkId__c');
                        addVerifiedFieldKey(resultMap, duplicateCount, vf, genericLinkId);
                    } catch (Exception e) {
                        // Continue with metadata-driven lookup keys.
                    }
                }

                // Metadata-driven lookup keys: add one key per mapped lookup field.
                for (String mappedLookupField : mappedLookupFields) {
                    if (String.isBlank(mappedLookupField)) {
                        continue;
                    }
                    try {
                        Object mappedLookupValue = vf.get(mappedLookupField);
                        addVerifiedFieldKey(resultMap, duplicateCount, vf, mappedLookupValue);
                    } catch (Exception e) {
                        // Ignore missing/unavailable fields and continue.
                    }
                }

                // Legacy fallback key to keep backward compatibility.
                String recordId = getRecordIdFromVerifiedField(vf, verificationLookupFields);
                addVerifiedFieldKey(resultMap, duplicateCount, vf, recordId);
            }
            
            Integer totalDuplicates = 0;
            for (Integer count : duplicateCount.values()) {
                if (count > 1){ totalDuplicates++;}
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CPC QC Controller Error: ' + e.getMessage() + ' | RecordId: ' + loanApplicationId);                
        }
        
        return resultMap;
    }

    private static void addVerifiedFieldKey(
        Map<String, Verified_Fields__c> resultMap,
        Map<String, Integer> duplicateCount,
        Verified_Fields__c vf,
        Object recordIdObj
    ) {
        if (vf == null || String.isBlank(vf.Field_Name__c) || recordIdObj == null) {
            return;
        }
        String recordId = String.valueOf(recordIdObj);
        if (String.isBlank(recordId)) {
            return;
        }
        String uniqueKey = recordId + '_' + vf.Field_Name__c;
        if (!resultMap.containsKey(uniqueKey)) {
            resultMap.put(uniqueKey, vf);
            duplicateCount.put(uniqueKey, 1);
        } else {
            Integer count = duplicateCount.containsKey(uniqueKey) ? duplicateCount.get(uniqueKey) : 1;
            duplicateCount.put(uniqueKey, count + 1);
        }
    }
    
    /**
     * Extract record ID from Verified_Fields__c lookup fields DYNAMICALLY
     * Checks all provided lookup fields and returns the first non-null value
     * 
     * @param vf The Verified_Fields__c record
     * @param lookupFields Set of lookup field names to check
     * @return The record ID from the first non-null lookup field
     */
    public static String getRecordIdFromVerifiedField(
        Verified_Fields__c vf,
        Set<String> lookupFields
    ) {
        // Prefer generic canonical link when present.
        if (hasField('Verified_Fields__c', 'sObjectLinkId__c')) {
            try {
                Object genericLinkId = vf.get('sObjectLinkId__c');
                if (genericLinkId != null && String.isNotBlank(String.valueOf(genericLinkId))) {
                    return String.valueOf(genericLinkId);
                }
            } catch (Exception e) {
                // Fall back to lookup-based matching.
            }
        }

        // Check in priority order
        for (String lookupField : lookupFields) {
            try {
                Object fieldValue = vf.get(lookupField);
                if (fieldValue != null) {
                    return String.valueOf(fieldValue);
                }
            } catch (Exception e) {
                continue;
            }
        }
        return ''; // No lookup field has a value
    }
    
    /**
     * Populate lookup fields on Verified_Fields__c based on object type
     * NOTE: Assumes all lookup fields have been cleared before calling this method
     */
    /**
     * Populate lookup fields dynamically based on metadata mapping
     * @param vf Verified_Fields__c record to populate
     * @param lookupMapping The field API name to populate (e.g., "Loan_Applicant__c" or "Loan_Applicant_Income__c")
     * @param loanApplicationId Loan Application ID (always set)
     * @param recordId Current record ID (based on ObjectName)
     * @param parentRecordId Parent record ID (not used anymore, kept for compatibility)
     */
    public static void populateLookupFields(Verified_Fields__c vf, String lookupMapping, 
                                            String loanApplicationId, String recordId, String parentRecordId) {
        
        
        // Always populate Loan Application
        if (String.isNotBlank(loanApplicationId)) {
            vf.Loan_Application__c = loanApplicationId;
        }
        
        // Populate parent lookup if provided (e.g., Loan_Applicant__c for child objects)
        if (String.isNotBlank(parentRecordId)) {
            vf.Loan_Applicant__c = parentRecordId;
        }
        
        // If no mapping provided, only Loan Application and parent are set
        if (String.isBlank(lookupMapping)) {
            return;
        }
        
        // We populate that ONE field with the recordId
        String fieldName = lookupMapping.trim();
        
        if (String.isNotBlank(fieldName)) {
            try {
                vf.put(fieldName, recordId);
            } catch (Exception e) {
                System.debug('   ❌ Error setting ' + fieldName + ': ' + e.getMessage());
                return;
            }
        }
    }
    
    /**
     * Process a DedicatedQuery metadata record
     */
    public static List<VerificationStatusResult> processDedicatedQuery(
        QC_Verification_Parent__mdt parent,
        Id loanApplicationId,
        Map<String, List<Field_Verification_Config__mdt>> fieldConfigsByParentId,
        Map<String, Verified_Fields__c> verifiedFieldsMap,
        Map<String, Map<String, List<Document_Checklist__c>>> documentsByRecordId,
        List<Document_Checklist__c> allDocumentsList,
        List<Field_Verification_Config__mdt> allFieldConfigs,
        Set<String> documentLookupFields
    ) {
        List<VerificationStatusResult> results = new List<VerificationStatusResult>();
        List<SObject> records = new List<SObject>();
        
        try {
            // Determine if this object's parent is ResidentialLoanApplication or something else
            String parentObjectName = parent.ParentObjectParameter__c;
            
            if (String.isBlank(parentObjectName) || parentObjectName == 'ResidentialLoanApplication') {
                // Direct child of ResidentialLoanApplication - query directly
                String whereClause = buildWhereClauseForObject(parent, loanApplicationId, null);
                String query = buildDynamicQueryForVerification(parent, whereClause, parent.ColumnsUsedInWhereClause__c);
                records = Database.query(query);
            } else {
                // Parent is another object (e.g., LoanApplicant) - need to get parent IDs first
                
                // Get parent records first
                List<SObject> parentRecords = getParentRecords(parentObjectName, loanApplicationId);
                Set<Id> parentIds = new Set<Id>();
                for (SObject parentRec : parentRecords) {
                    parentIds.add(parentRec.Id);
                }
                
                if (parentIds.isEmpty()) {
                    records = new List<SObject>();
                } else {
                    // Build WHERE clause with parent IDs
                    String whereClause = buildWhereClauseWithParentIds(parent, parentIds);
                    String query = buildDynamicQueryForVerification(parent, whereClause, parent.ColumnsUsedInWhereClause__c);
                    records = Database.query(query);
                }
            }
            
            // Apply WHERE clause filtering in Apex
            if (String.isNotBlank(parent.WhereClause__c)) {
                records = WhereClauseEvaluator.filterRecords(records, parent.WhereClause__c);
            }

            // Ensure only latest EBV record per parent is processed when metadata routes through dedicated query.
            if (parent.ObjectName__c == 'Employment_Business_Verification__c') {
                records = keepLatestEbvRecordPerParent(records, parent.ParentLookupField__c);
            }
            
        } catch (Exception queryEx) {
            records = new List<SObject>(); // Ensure we have an empty list
        }
        
        // Process each record with individual error handling
        Integer recordIndex = 0;
        for (SObject record : records) {
            
            recordIndex++;
            List<VerificationStatusResult> recordResults = buildVerificationResultsWithChildSections(
                record, 
                parent, 
                fieldConfigsByParentId.get(parent.Id),
                verifiedFieldsMap,
                documentsByRecordId,
                allDocumentsList,
                allFieldConfigs,
                documentLookupFields,
                recordIndex,
                records.size()
            );
            results.addAll(recordResults); // Add all results (main + child sections)
        }

        // Always add placeholder if no results (even if there were errors)
        if (results.isEmpty()) {
            VerificationStatusResult placeholder = new VerificationStatusResult();
            placeholder.objectName = parent.ObjectName__c;
            placeholder.sectionName = parent.SectionName__c;
            placeholder.parentSectionName = parent.Parent_QC_Section_Name__c; // Set parent section name from metadata
            placeholder.objectLevel = Integer.valueOf(parent.ObjectLevel__c);
            placeholder.recordId = null; // No record
            placeholder.recordLabel = 'No records found';
            placeholder.fields = new List<FieldVerificationStatus>();
            results.add(placeholder);
        }
        
        return results;
    }
    
    /**
     * Get parent records for a given parent object
     */
    private static List<SObject> getParentRecords(String parentObjectName, Id loanApplicationId) {
        if (isLoanApplicationObject(parentObjectName)) {
            return Database.query('SELECT Id FROM Application__c WHERE Id = :loanApplicationId');
        } else if (isApplicantObject(parentObjectName)) {
            return Database.query('SELECT Id FROM Applicant__c WHERE Application__c = :loanApplicationId');
        } else {
            // Dynamic query for other objects - assume they have Application__c field
            String query = 'SELECT Id FROM ' + parentObjectName + ' WHERE Application__c = :loanApplicationId';
            try {
                return Database.query(query);
            } catch (Exception e) {
                return new List<SObject>();
            }
        }
    }
    
    /**
     * Build WHERE clause with multiple parent IDs
     */
    private static String buildWhereClauseWithParentIds(QC_Verification_Parent__mdt parent, Set<Id> parentIds) {
        if (String.isBlank(parent.ParentLookupField__c)) {
            return '';
        }
        
        List<String> idStrings = new List<String>();
        for (Id parentId : parentIds) {
            idStrings.add('\'' + parentId + '\'');
        }
        
        String whereClause = parent.ParentLookupField__c + ' IN (' + String.join(idStrings, ',') + ')';
        
        return whereClause;
    }
    
    /**
     * Process Child Queries for a parent section
     */
    private static List<VerificationStatusResult> processChildQueries(
        String parentSectionName,
        List<QC_Verification_Parent__mdt> childMetadata,
        Id loanApplicationId,
        Map<String, List<Field_Verification_Config__mdt>> fieldConfigsByParentId,
        Map<String, Verified_Fields__c> verifiedFieldsMap,
        Map<String, Map<String, List<Document_Checklist__c>>> documentsByRecordId,
        List<Document_Checklist__c> allDocumentsList,
        List<Field_Verification_Config__mdt> allFieldConfigs,
        Set<String> documentLookupFields
    ) {
        List<VerificationStatusResult> results = new List<VerificationStatusResult>();
        
        try {
            // Get the parent object name from the first child metadata's ParentObjectParameter__c
            if (childMetadata.isEmpty()) {
                return results;
            }
            
            String parentObjName = childMetadata[0].ParentObjectParameter__c;
            
            // Build parent query with child relationships
            String parentQuery = buildParentQueryWithChildren(parentObjName, childMetadata, loanApplicationId, fieldConfigsByParentId);
            List<SObject> parentRecords = Database.query(parentQuery);
            
            // Process each parent record and its children
            for (SObject parentRecord : parentRecords) {
                for (QC_Verification_Parent__mdt childMeta : childMetadata) {
                    String relationshipName = childMeta.RelationshipQueryName__c;
                    List<SObject> childRecords = parentRecord.getSObjects(relationshipName);
                    
                    if (childRecords != null && childRecords.size() > 0) {
                        
                        // Apply WHERE clause filtering
                        if (String.isNotBlank(childMeta.WhereClause__c)) {
                            Integer beforeFilter = childRecords.size();
                            childRecords = WhereClauseEvaluator.filterRecords(childRecords, childMeta.WhereClause__c);
                        }
                        
                        // Check if we have records after filtering
                        if (childRecords.size() > 0) {
                            Integer childIndex = 0;
                            for (SObject childRecord : childRecords) {
                                childIndex++;
                                List<VerificationStatusResult> recordResults = buildVerificationResultsWithChildSections(
                                    childRecord,
                                    childMeta,
                                    fieldConfigsByParentId.get(childMeta.Id),
                                    verifiedFieldsMap,
                                    documentsByRecordId,
                                    allDocumentsList,
                                    allFieldConfigs,
                                    documentLookupFields,
                                    childIndex,
                                    childRecords.size()
                                );
                                
                                // Override parent section name for all results (main + child sections)
                                for (VerificationStatusResult result : recordResults) {
                                    result.parentSectionName = parentSectionName;
                                results.add(result);
                                }
                            }
                        } else {
                            // All records were filtered out - create empty placeholder
                            VerificationStatusResult emptySection = new VerificationStatusResult();
                            emptySection.recordId = null;
                            emptySection.recordLabel = 'No records';
                            emptySection.sectionName = childMeta.SectionName__c;
                            emptySection.objectName = childMeta.ObjectName__c;
                            emptySection.objectLevel = childMeta.ObjectLevel__c != null ? Integer.valueOf(childMeta.ObjectLevel__c) : null;
                            emptySection.parentSectionName = parentSectionName;
                            emptySection.parentRecordId = String.valueOf(parentRecord.Id);
                            emptySection.fields = new List<FieldVerificationStatus>();
                            emptySection.isEmpty = true;
                            results.add(emptySection);
                        }
                    } else {
                        // No child records found for this parent - create empty placeholder
                        VerificationStatusResult emptySection = new VerificationStatusResult();
                        emptySection.recordId = null;
                        emptySection.recordLabel = 'No records';
                        emptySection.sectionName = childMeta.SectionName__c;
                        emptySection.objectName = childMeta.ObjectName__c;
                        emptySection.objectLevel = childMeta.ObjectLevel__c != null ? Integer.valueOf(childMeta.ObjectLevel__c) : null;
                        emptySection.parentSectionName = parentSectionName;
                        emptySection.parentRecordId = String.valueOf(parentRecord.Id);
                        emptySection.fields = new List<FieldVerificationStatus>();
                        emptySection.isEmpty = true;
                        results.add(emptySection);
                    }
                }
            }
            
        } catch (Exception e) {
            // Error in processChildQueries
            System.debug(LoggingLevel.ERROR, 'CPC Controller Error: ' + e.getMessage() + ' | RecordId: ' + loanApplicationId);
        }
         return results;
    }
    
    /**
     * Build WHERE clause for an object query
     * DYNAMIC - works for any parent-child relationship, not just LoanApplication → Applicant
     * 
     * @param parent Metadata configuration
     * @param loanApplicationId Loan Application ID
     * @param parentRecordId Parent record ID (generic - could be Applicant, Education, etc.)
     */
    private static String buildWhereClauseForObject(QC_Verification_Parent__mdt parent, 
                                                   Id loanApplicationId, Id parentRecordId) {
        // Special case: Loan Application (Level 1)
        if (isLoanApplicationObject(parent.ObjectName__c)) {
            return 'Id = \'' + loanApplicationId + '\'';
        }
        
        // For all other objects, use ParentLookupField__c from metadata
        if (String.isBlank(parent.ParentLookupField__c)) {
            return '';
        }
        
        // Determine which ID to use based on what's available
        // If parentRecordId provided (e.g., specific Applicant/Education/etc.), use it
        // Otherwise fall back to loanApplicationId
        String idToUse = parentRecordId != null ? String.valueOf(parentRecordId) : String.valueOf(loanApplicationId);
        
        String whereClause = parent.ParentLookupField__c + ' = \'' + idToUse + '\'';
        
        
        return whereClause;
    }
    
    /**
     * Build dynamic SOQL query for verification
     */
    private static String buildDynamicQueryForVerification(QC_Verification_Parent__mdt parent, String whereClause,
                                                          String columnsUsedInWhereClause) {
        String objectName = parent != null ? parent.ObjectName__c : null;
        Set<String> fields = getFieldsForObject(objectName);
        
        // Add WHERE clause columns
        if (String.isNotBlank(columnsUsedInWhereClause)) {
            for (String col : columnsUsedInWhereClause.split(',')) {
                fields.add(col.trim());
            }
        }
        
        String query = 'SELECT ' + String.join(new List<String>(fields), ', ') + 
                      ' FROM ' + objectName;
        
        if (String.isNotBlank(whereClause)) {
            query += ' WHERE ' + whereClause;
        }
        
        String orderByClause = getOptionalMetadataString(parent, 'Order_By_Clause__c');
        Integer queryLimit = getOptionalMetadataInteger(parent, 'LIMIT__c');
        if (String.isNotBlank(orderByClause)) {
            query += ' ORDER BY ' + orderByClause;
        }
        if (queryLimit != null && queryLimit > 0) {
            query += ' LIMIT ' + queryLimit;
        }
        
        return query;
    }

    private static List<SObject> keepLatestEbvRecordPerParent(List<SObject> records, String parentLookupField) {
        if (records == null || records.isEmpty() || String.isBlank(parentLookupField)) {
            return records;
        }

        Map<String, SObject> latestByParent = new Map<String, SObject>();
        Map<String, Datetime> latestCreatedByParent = new Map<String, Datetime>();

        for (SObject rec : records) {
            if (rec == null) {
                continue;
            }
            Object parentLookupValue;
            try {
                parentLookupValue = rec.get(parentLookupField);
            } catch (Exception e) {
                continue;
            }
            if (parentLookupValue == null) {
                continue;
            }
            String parentKey = String.valueOf(parentLookupValue);
            if (String.isBlank(parentKey)) {
                continue;
            }

            Datetime createdDt = null;
            try {
                createdDt = (Datetime) rec.get('CreatedDate');
            } catch (Exception e) {
                createdDt = null;
            }

            Datetime existingCreatedDt = latestCreatedByParent.get(parentKey);
            if (!latestByParent.containsKey(parentKey) || existingCreatedDt == null || (createdDt != null && createdDt.getTime() > existingCreatedDt.getTime())) {
                latestByParent.put(parentKey, rec);
                latestCreatedByParent.put(parentKey, createdDt);
            }
        }

        return latestByParent.values();
    }
    
    /**
     * Get fields for an object from metadata
     */
    private static Set<String> getFieldsForObject(String objectName) {
        Set<String> fields = new Set<String>{'Id', 'Name'};
                
        try {
            // Get label field and parent lookup field
            List<QC_Verification_Parent__mdt> parents = [
                SELECT FieldNametoShowas_Label__c, ColumnsUsedInWhereClause__c, ParentLookupField__c
                FROM QC_Verification_Parent__mdt
                WHERE ObjectName__c = :objectName
                LIMIT 1
            ];
            
            if (!parents.isEmpty()) {
                if (String.isNotBlank(parents[0].FieldNametoShowas_Label__c)) {
                    fields.add(parents[0].FieldNametoShowas_Label__c);
                }
                if (String.isNotBlank(parents[0].ColumnsUsedInWhereClause__c)) {
                    for (String col : parents[0].ColumnsUsedInWhereClause__c.split(',')) {
                        fields.add(col.trim());
                    }
                }
                if (String.isNotBlank(parents[0].ParentLookupField__c)) {
                    fields.add(parents[0].ParentLookupField__c);
                }
            }
            
            // Get field configs - build dynamic query for backward compatibility
            String fieldConfigQuery = 'SELECT Field_Name__c, isPickList__c';
            if (hasField('Field_Verification_Config__mdt', 'AdditionalColumnsToQuery__c')) {
                fieldConfigQuery += ', AdditionalColumnsToQuery__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Checklist_Mapping_Field__c')) {
                fieldConfigQuery += ', Checklist_Mapping_Field__c';
            }
            if (hasField('Field_Verification_Config__mdt', 'Reference_Object_Name__c')) {
                fieldConfigQuery += ', Reference_Object_Name__c';
            }
            fieldConfigQuery += ' FROM Field_Verification_Config__mdt ' +
                              'WHERE QC_Verification_Parent__r.ObjectName__c = :objectName AND Active__c = true';
            
            List<Field_Verification_Config__mdt> configs = Database.query(fieldConfigQuery);
            
            for (Field_Verification_Config__mdt config : configs) {
                if (String.isNotBlank(config.Field_Name__c)) {
                    // Validate field exists on the object before adding
                    if (isValidField(objectName, config.Field_Name__c)) {
                        // For picklist fields, add BOTH raw field AND TOLABEL(), unless reference object is provided
                        // (for relationship-driven resolution we do not inject TOLABEL alias on parent query).
                        if (config.isPickList__c == true) {
                            String referenceObjectName = null;
                            try {
                                if (config.get('Reference_Object_Name__c') != null) {
                                    referenceObjectName = (String) config.get('Reference_Object_Name__c');
                                }
                            } catch (Exception ignore) {
                                referenceObjectName = null;
                            }
                            // Add the raw field (needed for WHERE clause evaluation)
                            fields.add(config.Field_Name__c);
                            // Only add TOLABEL when reference object is not configured.
                            if (String.isBlank(referenceObjectName)) {
                                String safeAlias = 'tolabel' + config.Field_Name__c.toLowerCase().replace('.', '_').replace('__c', '');
                                fields.add('TOLABEL(' + config.Field_Name__c + ') ' + safeAlias);
                            }
                        } else {
                            fields.add(config.Field_Name__c);
                        }
                    }
                }
                
                // Add additional columns from field config for WHERE clause evaluation (if field exists)
                
                String additionalColumns = null;
                try {
                    additionalColumns = config.get('AdditionalColumnsToQuery__c') != null
                        ? (String) config.get('AdditionalColumnsToQuery__c')
                        : null;
                } catch (Exception ignore) {
                    additionalColumns = null;
                }
                if (String.isNotBlank(additionalColumns)) {
                    for (String col : additionalColumns.split(',')) {
                        String columnName = col.trim();
                        if (String.isNotBlank(columnName) && isValidField(objectName, columnName)) {
                            fields.add(columnName);
                        }
                    }
                }

                // Add checklist mapping field so document lookup override can be resolved from the record.
            
                String checklistMappingField = null;
                try {
                    checklistMappingField = config.get('Checklist_Mapping_Field__c') != null
                        ? (String) config.get('Checklist_Mapping_Field__c')
                        : null;
                } catch (Exception ignore) {
                    checklistMappingField = null;
                }
                if (String.isNotBlank(checklistMappingField) && isValidField(objectName, checklistMappingField)) {
                    fields.add(checklistMappingField);
                }
            }
            
        } catch (Exception e) {
            return fields;
        }
        
        System.debug('🔧 getFieldsForObject returning for ' + objectName + ': ' + fields);
        return fields;
    }
    
    /**
     * Validate if a field exists on an object
     * For relationship fields (e.g., LoanApplicant.axisltd_Constitution__c), validates that the lookup exists
     * OPTIMIZATION: Uses static cache to avoid redundant describe calls
     */
    private static Boolean isValidField(String objectName, String fieldName) {
        try {
            // Use cached global describe
            if (globalDescribeCache == null) {
                globalDescribeCache = Schema.getGlobalDescribe();
            }
            
            Schema.SObjectType sobjectType = globalDescribeCache.get(objectName);
            if (sobjectType == null) {
                return false;
            }
            
            // Cache field maps per object
            Map<String, Schema.SObjectField> fieldMap = fieldDescribeCache.get(objectName);
            if (fieldMap == null) {
                fieldMap = sobjectType.getDescribe().fields.getMap();
                fieldDescribeCache.put(objectName, fieldMap);
            }
            
            // Handle relationship fields (e.g., LoanApplicant.axisltd_Constitution__c)
            if (fieldName.contains('.')) {
                String[] parts = fieldName.split('\\.');
                String relationshipName = parts[0]; // e.g., "LoanApplicant", "Account__r", "LoanApplicantEmployment"
                
                // Try different naming conventions to find the lookup field
                List<String> possibleLookupFields = new List<String>();
                
                if (relationshipName.endsWith('__r')) {
                    // Custom object relationship: Account__r → Account__c
                    possibleLookupFields.add(relationshipName.replace('__r', '__c'));
                } else if (relationshipName.endsWith('__c')) {
                    // Already has __c suffix
                    possibleLookupFields.add(relationshipName);
                } else {
                    // Standard or custom object without suffix
                    
                    // Convert PascalCase to snake_case and add __c
                    String snakeCase = relationshipName.replaceAll('([A-Z])', '_$1').toLowerCase().replaceFirst('^_', '');
                    possibleLookupFields.add(snakeCase + '__c');
                    
                    // Direct custom object
                    possibleLookupFields.add(relationshipName + '__c');
                    
                    // Standard relationship with Id suffix
                    possibleLookupFields.add(relationshipName + 'Id');
                }
                
                // Check if any of the possible lookup fields exist
                for (String lookupField : possibleLookupFields) {
                    if (fieldMap.containsKey(lookupField.toLowerCase())) {
                        System.debug('✅ Found relationship field: ' + lookupField + ' on ' + objectName + ' for ' + fieldName);
                        return true;
                    }
                }
                return false;
            } else {
                // Simple field - check case-insensitively
                return fieldMap.containsKey(fieldName.toLowerCase());
            }
        } catch (Exception e) {
            System.debug('❌ ERROR in isValidField(' + objectName + ', ' + fieldName + '): ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * Build parent query with child relationships
     */
    private static String buildParentQueryWithChildren(String parentObjName, 
                                                      List<QC_Verification_Parent__mdt> childMetadata,
                                                      Id loanApplicationId,
                                                      Map<String, List<Field_Verification_Config__mdt>> fieldConfigsByParentId) {
        Set<String> parentFields = getFieldsForObject(parentObjName);
        
        // Get parent metadata for WHERE clause
        QC_Verification_Parent__mdt parentMeta = [
            SELECT ParentLookupField__c, ParentObjectParameter__c
            FROM QC_Verification_Parent__mdt
            WHERE ObjectName__c = :parentObjName
            LIMIT 1
        ];
        
        String query = 'SELECT ' + String.join(new List<String>(parentFields), ', ');
        
        // Consolidate fields by RelationshipQueryName to avoid duplicate subqueries
        // Multiple sections can use the same relationship, so we query once with all fields
        Map<String, Set<String>> relationshipFieldsMap = new Map<String, Set<String>>();
        Map<String, String> relationshipOrderByMap = new Map<String, String>();
        Map<String, Integer> relationshipLimitMap = new Map<String, Integer>();
        
        for (QC_Verification_Parent__mdt childMeta : childMetadata) {
            String relationshipName = childMeta.RelationshipQueryName__c;
            String childObjectApiName = getChildObjectNameFromRelationship(parentObjName, relationshipName);
            List<Field_Verification_Config__mdt> childFieldConfigs =
                fieldConfigsByParentId != null ? fieldConfigsByParentId.get(childMeta.Id) : null;
            Set<String> childFields = getFieldsForChildRelationship(childMeta, childObjectApiName, childFieldConfigs);
            
            // Add WHERE clause columns
            if (String.isNotBlank(childMeta.ColumnsUsedInWhereClause__c)) {
                for (String col : childMeta.ColumnsUsedInWhereClause__c.split(',')) {
                    childFields.add(col.trim());
                }
            }
            
            // Consolidate fields for this relationship
            if (!relationshipFieldsMap.containsKey(relationshipName)) {
                relationshipFieldsMap.put(relationshipName, new Set<String>());
            }
            relationshipFieldsMap.get(relationshipName).addAll(childFields);
            String childOrderByClause = getOptionalMetadataString(childMeta, 'Order_By_Clause__c');
            Integer childLimit = getOptionalMetadataInteger(childMeta, 'LIMIT__c');
            if (!relationshipOrderByMap.containsKey(relationshipName) && String.isNotBlank(childOrderByClause)) {
                relationshipOrderByMap.put(relationshipName, childOrderByClause);
            }
            if (!relationshipLimitMap.containsKey(relationshipName) && childLimit != null && childLimit > 0) {
                relationshipLimitMap.put(relationshipName, childLimit);
            }
        }
        
        // Build one subquery per unique relationship
        // ORDER/LIMIT are metadata driven via QC_Verification_Parent__mdt (Order_By_Clause__c, LIMIT__c)
        for (String relationshipName : relationshipFieldsMap.keySet()) {
            Set<String> fields = relationshipFieldsMap.get(relationshipName);
            String relationshipOrderBy = relationshipOrderByMap.get(relationshipName);
            Integer relationshipLimit = relationshipLimitMap.get(relationshipName);
            String orderAndLimitClause = '';
            if (String.isNotBlank(relationshipOrderBy)) {
                orderAndLimitClause += ' ORDER BY ' + relationshipOrderBy;
            }
            if (relationshipLimit != null && relationshipLimit > 0) {
                orderAndLimitClause += ' LIMIT ' + relationshipLimit;
            }
            query += ', (SELECT ' + String.join(new List<String>(fields), ', ') +
                    ' FROM ' + relationshipName +
                    orderAndLimitClause + ')';
        }
        
        query += ' FROM ' + parentObjName;
        
        // Add WHERE clause to filter by loanApplicationId
        if (isLoanApplicationObject(parentObjName)) {
            // For Loan Application, filter by Id directly
            query += ' WHERE Id = \'' + loanApplicationId + '\'';
        } else if (String.isNotBlank(parentMeta.ParentLookupField__c)) {
            // For child objects, resolve parent records using ParentObjectParameter__c and filter by parent IDs.
            String parentObjectName = parentMeta.ParentObjectParameter__c;
            if (String.isNotBlank(parentObjectName) && !isLoanApplicationObject(parentObjectName)) {
                List<SObject> resolvedParents = getParentRecords(parentObjectName, loanApplicationId);
                Set<Id> resolvedParentIds = new Set<Id>();
                for (SObject parentRec : resolvedParents) {
                    if (parentRec != null && parentRec.get('Id') != null) {
                        resolvedParentIds.add((Id) parentRec.get('Id'));
                    }
                }

                if (!resolvedParentIds.isEmpty()) {
                    List<String> idStrings = new List<String>();
                    for (Id pid : resolvedParentIds) {
                        idStrings.add('\'' + String.valueOf(pid) + '\'');
                    }
                    query += ' WHERE ' + parentMeta.ParentLookupField__c + ' IN (' + String.join(idStrings, ',') + ')';
                } else {
                    // Ensure deterministic empty result when no parent ids resolve.
                    query += ' WHERE Id = null';
                }
            } else {
                // Parent is Loan Application directly
                query += ' WHERE ' + parentMeta.ParentLookupField__c + ' = \'' + loanApplicationId + '\'';
            }
        } else {
            // Fallback: assume LoanApplicationId field
            query += ' WHERE LoanApplicationId = \'' + loanApplicationId + '\'';
        }
        
        
        return query;
    }

    private static String getChildObjectNameFromRelationship(String parentObjName, String relationshipName) {
        try {
            if (String.isBlank(parentObjName) || String.isBlank(relationshipName)) {
                return null;
            }
            if (globalDescribeCache == null) {
                globalDescribeCache = Schema.getGlobalDescribe();
            }
            Schema.SObjectType parentType = globalDescribeCache.get(parentObjName);
            if (parentType == null) {
                return null;
            }
            for (Schema.ChildRelationship rel : parentType.getDescribe().getChildRelationships()) {
                if (rel != null && rel.getRelationshipName() == relationshipName && rel.getChildSObject() != null) {
                    return rel.getChildSObject().getDescribe().getName();
                }
            }
        } catch (Exception e) {
            return null;
        }
        return null;
    }

    private static Set<String> getFieldsForChildRelationship(
        QC_Verification_Parent__mdt childMeta,
        String childObjectApiName,
        List<Field_Verification_Config__mdt> fieldConfigs
    ) {
        Set<String> fields = new Set<String>{'Id', 'Name'};

        if (childMeta != null) {
            if (String.isNotBlank(childMeta.FieldNametoShowas_Label__c)) {
                fields.add(childMeta.FieldNametoShowas_Label__c);
            }
            if (String.isNotBlank(childMeta.ColumnsUsedInWhereClause__c)) {
                for (String col : childMeta.ColumnsUsedInWhereClause__c.split(',')) {
                    if (String.isNotBlank(col)) {
                        fields.add(col.trim());
                    }
                }
            }
            if (String.isNotBlank(childMeta.ParentLookupField__c)) {
                fields.add(childMeta.ParentLookupField__c);
            }
        }

        if (fieldConfigs != null) {
            for (Field_Verification_Config__mdt config : fieldConfigs) {
                if (String.isBlank(config.Field_Name__c)) {
                    continue;
                }

                Boolean canUseField = String.isBlank(childObjectApiName) || isValidField(childObjectApiName, config.Field_Name__c);
                if (!canUseField) {
                    continue;
                }

                if (config.isPickList__c == true) {
                    String referenceObjectName = null;
                    fields.add(config.Field_Name__c);
                    try {
                        referenceObjectName = config.get('Reference_Object_Name__c') != null
                            ? (String) config.get('Reference_Object_Name__c')
                            : '';
                    } catch (Exception ignore) {
                        referenceObjectName = '';
                    }
                    if (String.isBlank(referenceObjectName)) {
                        String safeAlias = 'tolabel' + config.Field_Name__c.toLowerCase().replace('.', '_').replace('__c', '');
                        fields.add('TOLABEL(' + config.Field_Name__c + ') ' + safeAlias);
                    }
                } else {
                    fields.add(config.Field_Name__c);
                }

                
                String additionalColumns = '';
                try {
                    additionalColumns = config.get('AdditionalColumnsToQuery__c') != null
                        ? (String) config.get('AdditionalColumnsToQuery__c')
                        : '';
                } catch (Exception ignore) {
                    additionalColumns = '';
                }
                if (String.isNotBlank(additionalColumns)) {
                    for (String col : additionalColumns.split(',')) {
                        String columnName = col != null ? col.trim() : '';
                        if (String.isBlank(columnName)) continue;
                        if (String.isBlank(childObjectApiName) || isValidField(childObjectApiName, columnName)) {
                            fields.add(columnName);
                        }
                    }
                }
            }
        }

        return fields;
    }
    
    /**
     * Build VerificationStatusResult(s) from a record - handles child section grouping
     * Returns a list because we still return one result per record, but fields have childSectionName
     */
    private static List<VerificationStatusResult> buildVerificationResultsWithChildSections(
        SObject record,
        QC_Verification_Parent__mdt parent,
        List<Field_Verification_Config__mdt> fieldConfigs,
        Map<String, Verified_Fields__c> verifiedFieldsMap,
        Map<String, Map<String, List<Document_Checklist__c>>> documentsByRecordId,
        List<Document_Checklist__c> allDocumentsList,
        List<Field_Verification_Config__mdt> allFieldConfigs,
        Set<String> documentLookupFields,
        Integer recordIndex,
        Integer totalRecords
    ) {
        List<VerificationStatusResult> results = new List<VerificationStatusResult>();

        
        // Build the result using the existing method (this creates all fields)
        VerificationStatusResult result = buildVerificationResult(
            record,
            parent,
            fieldConfigs,
            verifiedFieldsMap,
            documentsByRecordId,
            allDocumentsList,
            allFieldConfigs,
            documentLookupFields,
            recordIndex,
            totalRecords
        );
        
        // Now stamp childSectionName on each field based on its config
        if (result.fields != null && fieldConfigs != null) {
            // Create a map of fieldName → Child_Section__c
            Map<String, String> fieldToChildSection = new Map<String, String>();
            
            for (Field_Verification_Config__mdt config : fieldConfigs) {
                String childSection = null;
                
                try {
                    if (config.get('Child_Section__c') != null) {
                        childSection = (String) config.get('Child_Section__c');
                    }
                } catch (Exception ignore) {
                    childSection = null;
                }
                if (String.isNotBlank(config.Field_Name__c)) {
                    fieldToChildSection.put(config.Field_Name__c, childSection);
                }
            }
            
            // Stamp childSectionName on each field
            for (FieldVerificationStatus field : result.fields) {
                if (fieldToChildSection.containsKey(field.fieldName)) {
                    field.childSectionName = fieldToChildSection.get(field.fieldName);
                }
            }
        }
        
        results.add(result);
        return results;
    }

    /**
     * Resolve picklist label only for relationship fields.
     * Returns null when relation/label cannot be resolved.
     */
    @TestVisible
    private static String getPicklistDisplayValue(SObject sourceRecord, String fieldPath, String referenceObjectName) {
        if (sourceRecord == null || String.isBlank(fieldPath) || !fieldPath.contains('.')) {
            return null;
        }

        try {
            List<String> parts = fieldPath.split('\\.');
            if (parts.size() < 2) {
                return null;
            }
            String relationshipField = parts[0];
            String targetField = parts[parts.size() - 1];
            SObject targetRecord = sourceRecord.getSObject(relationshipField);
            if (targetRecord == null) {return null;}

            Object rawValueObj = targetRecord.get(targetField);
            if (rawValueObj == null) {
                return null;
            }
            String rawValue = String.valueOf(rawValueObj);

            if (globalDescribeCache == null) {
                globalDescribeCache = Schema.getGlobalDescribe();
            }

            Map<String, Schema.SObjectField> fieldMap = null;
            if (String.isNotBlank(referenceObjectName) && globalDescribeCache.containsKey(referenceObjectName)) {
                Schema.SObjectType configuredType = globalDescribeCache.get(referenceObjectName);
                if (configuredType != null) {
                    fieldMap = configuredType.getDescribe().fields.getMap();
                }
            }

            // Fallback to the runtime record's type if reference object isn't provided/valid.
            if (fieldMap == null) {
                fieldMap = targetRecord.getSObjectType().getDescribe().fields.getMap();
            }

            Schema.SObjectField fieldToken = fieldMap.get(targetField.toLowerCase());
            if (fieldToken == null) {
                fieldToken = fieldMap.get(targetField);
            }
            if (fieldToken == null) {
                return rawValue;
            }

            Schema.DescribeFieldResult describeResult = fieldToken.getDescribe();
            Schema.DisplayType dataType = describeResult.getType();
            if (dataType == Schema.DisplayType.PICKLIST) {
                for (Schema.PicklistEntry entry : describeResult.getPicklistValues()) {
                    if (entry.getValue() == rawValue) {
                        return entry.getLabel();
                    }
                }
            } else if (dataType == Schema.DisplayType.MULTIPICKLIST) {
                List<String> labels = new List<String>();
                for (String valuePart : rawValue.split(';')) {
                    String trimmed = valuePart != null ? valuePart.trim() : null;
                    if (String.isBlank(trimmed)) {
                        continue;
                    }
                    String labelToAdd = trimmed;
                    for (Schema.PicklistEntry entry : describeResult.getPicklistValues()) {
                        if (entry.getValue() == trimmed) {
                            labelToAdd = entry.getLabel();
                            break;
                        }
                    }
                    labels.add(labelToAdd);
                }
                return String.join(labels, ';');
            }

            return rawValue;
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Build VerificationStatusResult from a record
     */
    private static VerificationStatusResult buildVerificationResult(
        SObject record,
        QC_Verification_Parent__mdt parent,
        List<Field_Verification_Config__mdt> fieldConfigs,
        Map<String, Verified_Fields__c> verifiedFieldsMap,
        Map<String, Map<String, List<Document_Checklist__c>>> documentsByRecordId,
        List<Document_Checklist__c> allDocumentsList,
        List<Field_Verification_Config__mdt> allFieldConfigs,
        Set<String> documentLookupFields,
        Integer recordIndex,
        Integer totalRecords
    ) {
        VerificationStatusResult result = new VerificationStatusResult();
        result.objectName = parent.ObjectName__c;
        result.sectionName = parent.SectionName__c;
        result.parentSectionName = parent.Parent_QC_Section_Name__c; // Set parent section name from metadata
        result.objectLevel = Integer.valueOf(parent.ObjectLevel__c);
        result.recordId = (String) record.get('Id');
        
        // Get record label
        String labelField = String.isNotBlank(parent.FieldNametoShowas_Label__c) ? 
                           parent.FieldNametoShowas_Label__c : 'Name';
        String baseLabel = (String) record.get(labelField);
        
        // If there are multiple records, enhance the label with an index
        if (totalRecords > 1) {
            if (String.isNotBlank(baseLabel)) {
                result.recordLabel = parent.SectionName__c + ' ' + recordIndex + ' - ' + baseLabel;
            } else {
                result.recordLabel = parent.SectionName__c + ' ' + recordIndex;
            }
        } else {
            // Single record - use base label or section name
            result.recordLabel = String.isNotBlank(baseLabel) ? baseLabel : parent.SectionName__c;
        }
        
        // Get parent record info
        if (parent.ObjectLevel__c > 1) {
            String parentLookupField = parent.ParentLookupField__c;
            if (String.isNotBlank(parentLookupField)) {
                try {
                    // Handle relationship fields (e.g., partyIdentityVerification.axisltd_loan_applicant__c)
                    if (parentLookupField.contains('.')) {
                        String[] parts = parentLookupField.split('\\.');
                        SObject relatedRecord = record.getSObject(parts[0]);
                        if (relatedRecord != null && parts.size() > 1) {
                            result.parentRecordId = (String) relatedRecord.get(parts[1]);
                        }
                    } else {
                        // Simple field
                        result.parentRecordId = (String) record.get(parentLookupField);
                    }
                } catch (Exception e) {
                    system.debug('❌ ERROR in buildVerificationResult parent lookup: ' + e.getMessage());
                }
            }
        }
        
        // Get documents for this record from pre-queried map (NO QUERY!)
        Map<String, List<Document_Checklist__c>> docMasterToLatestChecklist = new Map<String, List<Document_Checklist__c>>();
        
        // Determine which ID to use for document lookup dynamically based on metadata
        // The DocumentCheckListLookfield__c in metadata tells us which field on Document_Checklist__c to check
        String documentLookupKey = null;
        String recordDocumentLookupField = parent.DocumentCheckListLookfield__c;
        String parentDocumentLookupField = getOptionalMetadataString(parent, 'ParentDocumentCheckListLookfield__c');
        String expectedLookupField = recordDocumentLookupField;
        
        // Dynamically determine the correct lookup key by checking which ID matches documents
        if (String.isNotBlank(expectedLookupField) && allDocumentsList != null && !allDocumentsList.isEmpty()) {
            // Check if any documents have the expectedLookupField matching recordId or parentRecordId
            Boolean recordIdHasDocs = false;
            Boolean parentRecordIdHasDocs = false;
            
            for (Document_Checklist__c doc : allDocumentsList) {
                try {
                    Object lookupFieldValue = doc.get(expectedLookupField);
                    if (lookupFieldValue != null) {
                        String lookupValueStr = String.valueOf(lookupFieldValue);
                        
                        // Check if this document's lookup field matches recordId
                        if (String.isNotBlank(result.recordId) && lookupValueStr == result.recordId) {
                            recordIdHasDocs = true;
                        }
                        // Check if this document's lookup field matches parentRecordId
                        if (String.isNotBlank(result.parentRecordId) && lookupValueStr == result.parentRecordId) {
                            parentRecordIdHasDocs = true;
                        }
                    }
                } catch (Exception e) {
                    system.debug('❌ ERROR in buildVerificationResult document lookup: ' + e.getMessage());
                    continue;
                }
            }
            
            // Use the ID that has matching documents (prioritize recordId for Level 3 objects)
            if (recordIdHasDocs) {
                documentLookupKey = result.recordId;
            } else if (parentRecordIdHasDocs) {
                documentLookupKey = result.parentRecordId;
            } else {
                // No documents found with expected lookup field - check map directly
                if (documentsByRecordId.containsKey(result.recordId)) {
                    documentLookupKey = result.recordId;
                } else if (documentsByRecordId.containsKey(result.parentRecordId)) {
                    documentLookupKey = result.parentRecordId;
                } else {
                    // Fallback to level-based logic
                    if (parent.ObjectLevel__c <= 2) {
                        documentLookupKey = result.recordId;
                    } else {
                        documentLookupKey = result.parentRecordId;
                    }
                    System.debug('⚠️ Level ' + parent.ObjectLevel__c + ' object using level-based fallback: ' + documentLookupKey);
                }
            }
        } else {
            // No expected lookup field configured - check map directly or use level-based logic
            if (documentsByRecordId.containsKey(result.recordId)) {
                documentLookupKey = result.recordId;
                System.debug('✅ Level ' + parent.ObjectLevel__c + ' object using recordId (from map, no lookup field): ' + documentLookupKey);
            } else if (documentsByRecordId.containsKey(result.parentRecordId)) {
                documentLookupKey = result.parentRecordId;
                System.debug('✅ Level ' + parent.ObjectLevel__c + ' object using parentRecordId (from map, no lookup field): ' + documentLookupKey);
            } else {
                // Fallback to level-based logic
                if (parent.ObjectLevel__c <= 2) {
                    documentLookupKey = result.recordId;
                } else {
                    documentLookupKey = result.parentRecordId;
                }
                System.debug('✅ Level ' + parent.ObjectLevel__c + ' object using level-based fallback: ' + documentLookupKey);
            }
        }
        
        // Lookup documents by the determined key
        String availableKeys = documentsByRecordId != null ? String.join(new List<String>(documentsByRecordId.keySet()), ', ') : 'null';
        
        if (String.isNotBlank(documentLookupKey) && documentsByRecordId.containsKey(documentLookupKey)) {
            docMasterToLatestChecklist = documentsByRecordId.get(documentLookupKey);
        } else {
            
            // Debug: Check if documents exist with the expected lookup field
            if (String.isNotBlank(parent.DocumentCheckListLookfield__c) && allDocumentsList != null) {
                Integer matchingDocs = 0;
                for (Document_Checklist__c doc : allDocumentsList) {
                    try {
                        Object lookupValue = doc.get(parent.DocumentCheckListLookfield__c);
                        if (lookupValue != null && String.valueOf(lookupValue) == documentLookupKey) {
                            matchingDocs++;
                        }
                    } catch (Exception e) {
                        system.debug('❌ ERROR in buildVerificationResult document lookup: ' + e.getMessage());
                    }
                }
            }
        }
        
        // Build field statuses
        result.fields = new List<FieldVerificationStatus>();
        
        if (fieldConfigs != null) {
            for (Field_Verification_Config__mdt config : fieldConfigs) {
                try {
                    // Check if field WHERE clause is met (if specified and field exists)
                    try {
                        String whereClause = (String) config.get('WhereClause__c');
                        if (String.isNotBlank(whereClause)) {
                            List<SObject> filteredRecords = WhereClauseEvaluator.filterRecords(
                                new List<SObject>{record}, 
                                whereClause
                            );
                            
                            // If record doesn't pass WHERE clause, skip this field
                            if (filteredRecords.isEmpty()) {
                                System.debug('   ⊘ Field ' + config.MasterLabel + ' excluded by WHERE clause: ' + whereClause);
                                continue; // Skip this field
                            }
                        }
                    } catch (Exception whereEx) {
                        system.debug('❌ ERROR in buildVerificationResult where clause: ' + whereEx.getMessage());
                    }
                    
                    FieldVerificationStatus fieldStatus = new FieldVerificationStatus();
                    fieldStatus.fieldName = config.Field_Name__c;
                    fieldStatus.fieldLabel = config.MasterLabel;
                    fieldStatus.objectName = parent.ObjectName__c;
                    fieldStatus.objectLevel = Integer.valueOf(parent.ObjectLevel__c);
                    fieldStatus.recordId = result.recordId;
                    fieldStatus.parentRecordId = result.parentRecordId;
                    Boolean isDateField = getOptionalMetadataBoolean(config, 'Is_Date_Field__c');
                    String dateFieldFormat = getOptionalMetadataString(config, 'Date_Field_Format__c');
                    
                    // Get current value from DB - wrap in try-catch for invalid fields
                    try {
                        Object fieldValue = null;
                        
                        // For picklist fields, use TOLABEL alias to get the label instead of API value
                        if (config.isPickList__c == true) {
                            Boolean isRelationshipPicklistField = config.Field_Name__c != null && config.Field_Name__c.contains('.');
                            String picklistReferenceObjectName = null;
                            try {
                                picklistReferenceObjectName = (String) config.get('Reference_Object_Name__c');
                            } catch (Exception picklistObjectEx) {
                                system.debug('❌ ERROR in buildVerificationResult picklist object name: ' + picklistObjectEx.getMessage());
                                // Field may not exist in some orgs/metadata versions.
                            }

                            // Try to get the label value from TOLABEL alias (same format as query)
                            String toLabelAlias = 'tolabel' + config.Field_Name__c.toLowerCase().replace('.', '_').replace('__c', '');
                            try {
                                fieldValue = record.get(toLabelAlias);
                            } catch (Exception aliasEx) {
                                // Keep direct fields as before; use custom resolution only for relationship fields.
                                if (isRelationshipPicklistField) {
                                    fieldValue = getPicklistDisplayValue(record, config.Field_Name__c, picklistReferenceObjectName);
                                } else {
                                    fieldValue = record.get(config.Field_Name__c);
                                }
                            }

                            // If alias is null/blank, keep direct behavior for non-relationship fields.
                            if (fieldValue == null || String.valueOf(fieldValue) == '') {
                                if (isRelationshipPicklistField) {
                                    fieldValue = getPicklistDisplayValue(record, config.Field_Name__c, picklistReferenceObjectName);
                                } else {
                                    fieldValue = record.get(config.Field_Name__c);
                                }
                            }
                        } else if (config.Field_Name__c.contains('.')) {
                            // Handle relationship fields (e.g., Board_University__r.Name)
                            String[] parts = config.Field_Name__c.split('\\.');
                            SObject relatedRecord = record.getSObject(parts[0]);
                            if (relatedRecord != null && parts.size() > 1) {
                                fieldValue = relatedRecord.get(parts[1]);
                            }
                        } else {
                            // Simple field
                            fieldValue = record.get(config.Field_Name__c);
                        }
                        
                        if (isDateField == true && String.isNotBlank(dateFieldFormat)) {
                            fieldStatus.currentValueInDB = formatDateFieldValue(fieldValue, dateFieldFormat);
                        } else {
                            fieldStatus.currentValueInDB = fieldValue != null ? String.valueOf(fieldValue) : '';
                        }
                    } catch (Exception fieldEx) {
                        fieldStatus.currentValueInDB = '[Field Not Available]';
                    }
                    
                    // Get verification status
                    String uniqueKey = result.recordId + '_' + config.Field_Name__c;
                    
                    if (verifiedFieldsMap.containsKey(uniqueKey)) {
                        Verified_Fields__c vf = verifiedFieldsMap.get(uniqueKey);
                        String statusValue = vf.Status__c;
                        System.debug('🔍 Found verification for ' + config.Field_Name__c + ': Status = "' + statusValue + '"');
                        
                        // Map API values to Label values (in case Status__c is a picklist storing API names)
                        // This ensures consistency with the radio button values in the UI
                        if (statusValue == 'Verified' || statusValue == 'Manually_Verified') {
                            fieldStatus.verificationStatus = 'Manually Verified';
                        } else if (statusValue == 'Digitally_Verified' || statusValue == 'DigitallyVerified') {
                            fieldStatus.verificationStatus = 'Digitally Verified';
                        } else if (statusValue == 'Data_Update_Needed' || statusValue == 'DataUpdateNeeded') {
                            fieldStatus.verificationStatus = 'Data Update Needed';
                        } else if (statusValue == 'Not_Verified' || statusValue == 'NotVerified') {
                            fieldStatus.verificationStatus = 'Not Verified';
                        } else {
                            // Use as-is if it's already in label format
                            fieldStatus.verificationStatus = statusValue;
                        }
                        String formattedVerifiedFieldValue = vf.Field_Value__c;
                        if (isDateField == true && String.isNotBlank(dateFieldFormat)) {
                            formattedVerifiedFieldValue = formatDateStringValue(vf.Field_Value__c, dateFieldFormat);
                        }
                        
                        fieldStatus.verificationComments = vf.Manually_Verification_Comments__c;
                        fieldStatus.fieldVerificationId = vf.Id;
                        fieldStatus.storedFieldValue = formattedVerifiedFieldValue; // Value at time of verification
                        fieldStatus.fieldValueFromVerifiedFields = formattedVerifiedFieldValue; // Field_Value__c from Verified_Fields__c
                        fieldStatus.manuallyVerifiedDate = vf.Manually_Verified_Date__c; // Timestamp of verification
                        fieldStatus.verifiedStatusDocumentNames = vf.Verified_Status_Document_Names__c;
                        fieldStatus.verifiedStatusDocumentIds = vf.Verified_Status_Document_Id__c;
                    } else {
                        fieldStatus.verificationStatus = 'Not Verified';
                        fieldStatus.fieldValueFromVerifiedFields = null; // No verified field record exists
                    }
                    
                    // Add JSON display configuration if available
                    try {
                        Boolean isJson = (Boolean) config.get('isJson__c');
                        if (isJson == true) {
                            fieldStatus.isJson = true;
                            String jsonFieldValue = (String) config.get('Json_Field_Value__c');
                            fieldStatus.jsonFieldValue = jsonFieldValue != null ? jsonFieldValue : '';
                        } else {
                            fieldStatus.isJson = false;
                        }
                    } catch (Exception jsonEx) {
                        // Fields don't exist yet, default to false
                        fieldStatus.isJson = false;
                    }
                    
                    // Add document info
                    // Map Document_Master_Name__c from metadata to Document_Type__c on Document Checklist
                    fieldStatus.documentMasterName = config.Document_Master_Name__c;
                    fieldStatus.additionalDocumentApiNameToFilter = config.Additional_Document_API_Name_To_Filter__c;
                    fieldStatus.additionalDocumentValueToFilter = config.Additional_Document_Value_To_Filter__c;
                    fieldStatus.documentAttachments = new List<AttachmentWrapper>();
                    fieldStatus.totalAttachments = 0;
                    
                    System.debug('🔍 Field: ' + config.Field_Name__c + ', Looking for Document Master Name: "' + config.Document_Master_Name__c + '"');
                    String checklistMappingField = null;
                    String checklistMappedLookupKey = null;
                    try {
                        checklistMappingField = (String) config.get('Checklist_Mapping_Field__c');
                        if (String.isNotBlank(checklistMappingField)) {
                            Object mappedLookupValue = record.get(checklistMappingField);
                            checklistMappedLookupKey = mappedLookupValue != null ? String.valueOf(mappedLookupValue) : null;
                            System.debug('   Checklist Mapping Field: ' + checklistMappingField + ', Resolved Value: ' + checklistMappedLookupKey);
                        }
                    } catch (Exception mappingEx) {
                        system.debug('❌ ERROR in buildVerificationResult checklist mapping field: ' + mappingEx.getMessage());
                        // Field may not exist in org yet, keep existing behavior.
                    }

                    Boolean fallbackToParentDocument = getOptionalMetadataBoolean(config, 'Fallback_To_Parent_Document__c');
                    Boolean isSelfLookupConfigured = String.isNotBlank(parent.DocumentCheckListLookfield__c);
                    Boolean isParentLookupConfigured = String.isNotBlank(parentDocumentLookupField) && String.isNotBlank(checklistMappingField);

                    Map<String, List<Document_Checklist__c>> selfDocMasterToChecklist = docMasterToLatestChecklist;
                    Map<String, List<Document_Checklist__c>> parentDocMasterToChecklist = new Map<String, List<Document_Checklist__c>>();
                    if (String.isNotBlank(checklistMappedLookupKey)) {
                        parentDocMasterToChecklist = documentsByRecordId.containsKey(checklistMappedLookupKey)
                            ? documentsByRecordId.get(checklistMappedLookupKey)
                            : new Map<String, List<Document_Checklist__c>>();
                    }

                    String effectiveDocumentLookupKey = documentLookupKey;
                    Map<String, List<Document_Checklist__c>> effectiveDocMasterToLatestChecklist = selfDocMasterToChecklist;
                    if (!isSelfLookupConfigured && isParentLookupConfigured) {
                        effectiveDocumentLookupKey = checklistMappedLookupKey;
                        effectiveDocMasterToLatestChecklist = parentDocMasterToChecklist;
                        expectedLookupField = parentDocumentLookupField;
                    } else if (isSelfLookupConfigured && isParentLookupConfigured) {
                        if (fallbackToParentDocument == true) {
                            Boolean hasSelfDocuments = hasAnyDocumentsInMasterMap(selfDocMasterToChecklist);
                            if (hasSelfDocuments) {
                                effectiveDocumentLookupKey = documentLookupKey;
                                effectiveDocMasterToLatestChecklist = selfDocMasterToChecklist;
                                expectedLookupField = recordDocumentLookupField;
                            } else {
                                effectiveDocumentLookupKey = checklistMappedLookupKey;
                                effectiveDocMasterToLatestChecklist = parentDocMasterToChecklist;
                                expectedLookupField = parentDocumentLookupField;
                            }
                        } else {
                            effectiveDocumentLookupKey = documentLookupKey;
                            effectiveDocMasterToLatestChecklist = mergeDocMasterMaps(selfDocMasterToChecklist, parentDocMasterToChecklist);
                            expectedLookupField = recordDocumentLookupField;
                        }
                    }

                    fieldStatus.fallbackToParentDocument = fallbackToParentDocument;
                    if (!isSelfLookupConfigured && isParentLookupConfigured) {
                        fieldStatus.documentSourceMode = 'PARENT_ONLY';
                    } else if (isSelfLookupConfigured && isParentLookupConfigured && fallbackToParentDocument == true) {
                        fieldStatus.documentSourceMode = 'SELF_WITH_PARENT_FALLBACK';
                    } else if (isSelfLookupConfigured && isParentLookupConfigured) {
                        fieldStatus.documentSourceMode = 'SELF_AND_PARENT';
                    } else {
                        fieldStatus.documentSourceMode = 'SELF_ONLY';
                    }
                    
                    if (String.isNotBlank(config.Document_Master_Name__c)) {
                        Document_Checklist__c matchingDoc = null;
                        
                        // Check if additional filter is configured
                        Boolean additionalDocFieldCheck = false;
                        String filterFieldApiName = null;
                        String filterValue = null;
                        try {
                            additionalDocFieldCheck = (Boolean) config.get('Additional_Doc_Field_Check__c');
                            if (additionalDocFieldCheck == true) {
                                filterFieldApiName = (String) config.get('Additional_Document_API_Name_To_Filter__c');
                                filterValue = (String) config.get('Additional_Document_Value_To_Filter__c');
                            }
                        } catch (Exception filterEx) {
                            system.debug('❌ ERROR in buildVerificationResult additional doc field check: ' + filterEx.getMessage());
                            // Additional_Doc_Field_Check__c field doesn't exist yet, continue without filtering
                        }

                        Boolean isCombinedScenarioHandled = false;
                        if (isSelfLookupConfigured && isParentLookupConfigured) {
                            Integer beforeCombinedCount = fieldStatus.documentAttachments != null ? fieldStatus.documentAttachments.size() : 0;

                            appendAttachmentsForLookupConfig(
                                fieldStatus,
                                allDocumentsList,
                                recordDocumentLookupField,
                                documentLookupKey,
                                config.Document_Master_Name__c,
                                additionalDocFieldCheck,
                                filterFieldApiName,
                                filterValue
                            );
                            Integer afterSelfCount = fieldStatus.documentAttachments != null ? fieldStatus.documentAttachments.size() : 0;
                            Boolean hasSelfDocuments = afterSelfCount > beforeCombinedCount;

                            if (String.isNotBlank(checklistMappedLookupKey) &&
                                (fallbackToParentDocument != true || !hasSelfDocuments)) {
                                appendAttachmentsForLookupConfig(
                                    fieldStatus,
                                    allDocumentsList,
                                    parentDocumentLookupField,
                                    checklistMappedLookupKey,
                                    config.Document_Master_Name__c,
                                    additionalDocFieldCheck,
                                    filterFieldApiName,
                                    filterValue
                                );
                            }
                            isCombinedScenarioHandled = true;
                        }
                        
                        // Reuse the expectedLookupField variable already declared at method level
                        // If additional filter is configured, search ALL documents with matching subcategory
                        if (!isCombinedScenarioHandled && additionalDocFieldCheck == true && String.isNotBlank(filterFieldApiName) && String.isNotBlank(filterValue)) {
                            // Search through all documents to find ALL that match both subcategory AND filter field
                            List<Document_Checklist__c> allMatchingDocs = new List<Document_Checklist__c>();
                            
                            if (allDocumentsList != null && !allDocumentsList.isEmpty()) {
                                String lookupKeyForFilter = effectiveDocumentLookupKey;
                                if (String.isBlank(lookupKeyForFilter)) {
                                    // Determine lookup key dynamically (same logic as above)
                                    String expectedLookupFieldForFilter = expectedLookupField;
                                    
                                    if (String.isNotBlank(expectedLookupFieldForFilter)) {
                                        // Check which ID matches documents with the expected lookup field
                                        Boolean recordIdHasDocs = false;
                                        Boolean parentRecordIdHasDocs = false;
                                        
                                        for (Document_Checklist__c doc : allDocumentsList) {
                                            try {
                                                Object lookupFieldValue = doc.get(expectedLookupFieldForFilter);
                                                if (lookupFieldValue != null) {
                                                    String lookupValueStr = String.valueOf(lookupFieldValue);
                                                    
                                                    if (String.isNotBlank(result.recordId) && lookupValueStr == result.recordId) {
                                                        recordIdHasDocs = true;
                                                    }
                                                    if (String.isNotBlank(result.parentRecordId) && lookupValueStr == result.parentRecordId) {
                                                        parentRecordIdHasDocs = true;
                                                    }
                                                }
                                            } catch (Exception e) {
                                                // Field doesn't exist, skip
                                                system.debug('❌ ERROR in doc filter dynamic lookup: ' + e.getMessage());
                                            }
                                        }
                                        
                                        // Use the ID that has matching documents (prioritize recordId)
                                        if (recordIdHasDocs) {
                                            lookupKeyForFilter = result.recordId;
                                        } else if (parentRecordIdHasDocs) {
                                            lookupKeyForFilter = result.parentRecordId;
                        } else if (!isCombinedScenarioHandled) {
                                            // Fallback to checking map or level-based logic
                                            if (documentsByRecordId.containsKey(result.recordId)) {
                                                lookupKeyForFilter = result.recordId;
                                            } else if (documentsByRecordId.containsKey(result.parentRecordId)) {
                                                lookupKeyForFilter = result.parentRecordId;
                                            } else {
                                                lookupKeyForFilter = parent.ObjectLevel__c <= 2 ? result.recordId : result.parentRecordId;
                                            }
                                        }
                                    } else {
                                        // No expected lookup field - check map or use level-based logic
                                        if (documentsByRecordId.containsKey(result.recordId)) {
                                            lookupKeyForFilter = result.recordId;
                                        } else if (documentsByRecordId.containsKey(result.parentRecordId)) {
                                            lookupKeyForFilter = result.parentRecordId;
                                        } else {
                                            lookupKeyForFilter = parent.ObjectLevel__c <= 2 ? result.recordId : result.parentRecordId;
                                        }
                                    }
                                }
                                
                                // Find all documents with matching subcategory and lookup key
                                for (Document_Checklist__c docCheck : allDocumentsList) {
                                    // Check if document belongs to this lookup record using the EXPECTED lookup field
                                    Boolean belongsToLookupKey = false;
                                    if (String.isNotBlank(lookupKeyForFilter) && String.isNotBlank(expectedLookupField)) {
                                        // CRITICAL FIX: Check ONLY the expected lookup field to ensure correct matching
                                        try {
                                            Object fieldValue = docCheck.get(expectedLookupField);
                                            if (fieldValue != null && String.valueOf(fieldValue) == lookupKeyForFilter) {
                                                belongsToLookupKey = true;
                                            }
                                        } catch (Exception e) {
                                            system.debug('❌ ERROR in doc filter expected lookup: ' + e.getMessage());
                                        }
                                    } else if (String.isNotBlank(lookupKeyForFilter) && documentLookupFields != null && !documentLookupFields.isEmpty()) {
                                        // Fallback: If no expected lookup field, check all lookup fields (backward compatibility)
                                        for (String lookupField : documentLookupFields) {
                                            try {
                                                Object fieldValue = docCheck.get(lookupField);
                                                if (fieldValue != null && String.valueOf(fieldValue) == lookupKeyForFilter) {
                                                    belongsToLookupKey = true;
                                                    break;
                                                }
                                            } catch (Exception e) {
                                                system.debug('❌ ERROR in doc filter expected lookup: ' + e.getMessage());
                                            }
                                        }
                                    }
                                    
                                    // Check if subcategory matches AND document belongs to correct lookup field
                                    if (belongsToLookupKey &&
                                        String.isNotBlank(resolveDocumentTypeValue(docCheck)) &&
                                        isSubCategoryInDocumentMasters(config.Document_Master_Name__c, resolveDocumentTypeValue(docCheck))) {
                                        
                                        // Check if filter field value matches (case-insensitive)
                                        try {
                                            Object docFieldValue = docCheck.get(filterFieldApiName);
                                            String docFieldValueStr = docFieldValue != null ? String.valueOf(docFieldValue) : '';
                                            
                                            if (docFieldValueStr.equalsIgnoreCase(filterValue)) {
                                                // Found matching document - add to list
                                                allMatchingDocs.add(docCheck);
                                                System.debug('   ✅ Found matching document - Field "' + filterFieldApiName + 
                                                           '" value "' + docFieldValueStr + '" matches "' + filterValue + 
                                                           '", Lookup Field: ' + expectedLookupField + ', Lookup Key: ' + lookupKeyForFilter + ', Doc ID: ' + docCheck.Id);
                                            }
                                        } catch (Exception fieldEx) {
                                            System.debug('   ⚠️ Error checking additional filter field "' + filterFieldApiName + '": ' + fieldEx.getMessage());
                                        }
                                    }
                                }
                            }
                            
                            // Set matchingDoc to first one (for backward compatibility)
                            if (!allMatchingDocs.isEmpty()) {
                                matchingDoc = allMatchingDocs[0];
                                
                                // Collect ALL attachments from ALL matching documents
                                Integer totalAttachments = 0;
                                for (Document_Checklist__c doc : allMatchingDocs) {
                                    if (doc.ContentDocumentLinks != null) {
                                        for (ContentDocumentLink cdl : doc.ContentDocumentLinks) {
                                AttachmentWrapper att = new AttachmentWrapper();
                                att.contentDocumentId = cdl.ContentDocumentId;
                                att.contentVersionId = cdl.ContentDocument.LatestPublishedVersionId;
                                att.title = cdl.ContentDocument.Title;
                                att.fileExtension = cdl.ContentDocument.FileExtension;
                                att.fileSize = cdl.ContentDocument.ContentSize;
                                att.fileSizeFormatted = formatFileSize(cdl.ContentDocument.ContentSize);
                                fieldStatus.documentAttachments.add(att);
                                            totalAttachments++;
                            }
                                    }
                                }
                                fieldStatus.totalAttachments = totalAttachments;
                                System.debug('   ✅ Collected ' + totalAttachments + ' attachments from ' + allMatchingDocs.size() + ' filtered document(s)');
                        }
                    } else {
                            // No additional filter - get ALL documents for this subcategory from map
                            // Verify all documents belong to the correct lookup field
                            // Handle comma-separated document master names
                            List<String> masterNamesList = getDocumentMasterNamesList(config.Document_Master_Name__c);
                            List<Document_Checklist__c> candidateDocs = new List<Document_Checklist__c>();
                            
                            // Collect documents from all matching master names in the map
                            for (String masterName : masterNamesList) {
                                if (effectiveDocMasterToLatestChecklist.containsKey(masterName)) {
                                    candidateDocs.addAll(effectiveDocMasterToLatestChecklist.get(masterName));
                                }
                            }
                            
                            List<Document_Checklist__c> allMatchingDocs = new List<Document_Checklist__c>();
                            
                            if (!candidateDocs.isEmpty()) {
                                System.debug('🔍 Found ' + candidateDocs.size() + ' candidate document(s) from map for subcategory(ies): ' + config.Document_Master_Name__c);
                                System.debug('   Expected Lookup Field: ' + expectedLookupField);
                                System.debug('   Document Lookup Key: ' + effectiveDocumentLookupKey);
                                
                                // Collect ALL documents with correct lookup field
                                for (Document_Checklist__c candidateDoc : candidateDocs) {
                                    System.debug('🔍 Checking candidate document:');
                                    System.debug('   Document ID: ' + candidateDoc.Id);
                                    System.debug('   Document Type: ' + resolveDocumentTypeValue(candidateDoc));
                                    
                                    // CRITICAL FIX: Verify that the document's lookup field matches the expected field from metadata
                                    Boolean isCorrectLookupField = false;
                                    if (String.isNotBlank(expectedLookupField)) {
                                        try {
                                            Object lookupFieldValue = candidateDoc.get(expectedLookupField);
                                            String lookupFieldValueStr = lookupFieldValue != null ? String.valueOf(lookupFieldValue) : null;
                                            System.debug('   Lookup Field Value: ' + lookupFieldValueStr);
                                            
                                            if (lookupFieldValue != null && lookupFieldValueStr == effectiveDocumentLookupKey) {
                                                isCorrectLookupField = true;
                                                System.debug('   ✅ Lookup field matches!');
                                            } else {
                                                System.debug('   ❌ Lookup field does NOT match. Expected: ' + effectiveDocumentLookupKey + ', Found: ' + lookupFieldValueStr);
                                            }
                                        } catch (Exception e) {
                                            System.debug('   ⚠️ Error checking expected lookup field "' + expectedLookupField + '": ' + e.getMessage());
                                        }
                                    } else {
                                        // If no expected lookup field is configured, accept the document (backward compatibility)
                                        isCorrectLookupField = true;
                                        System.debug('   ⚠️ No expected lookup field configured - accepting document (backward compatibility)');
                                    }
                                    
                                    if (isCorrectLookupField) {
                                        allMatchingDocs.add(candidateDoc);
                                        System.debug('   ✅ Added to matching docs - Lookup Field: ' + expectedLookupField);
                                    }
                                }
                                
                                // Use the first matching doc (for backward compatibility with single-doc logic)
                                // But we'll collect ALL attachments from ALL matching docs below
                                if (!allMatchingDocs.isEmpty()) {
                                    matchingDoc = allMatchingDocs[0];
                                    System.debug('   ✅ Found ' + allMatchingDocs.size() + ' matching document(s) from map');
                                }
                                
                                // If no match found in the list, try fallback search
                                if (allMatchingDocs.isEmpty()) {
                                    System.debug('   ❌ No documents from map matched expected lookup field "' + expectedLookupField + 
                                               '" for lookup key: ' + effectiveDocumentLookupKey);
                                    System.debug('   🔍 Searching allDocumentsList for correct match...');
                                    
                                    // Fallback: Search allDocumentsList for a document that matches both subcategory AND correct lookup field
                                    if (allDocumentsList != null && !allDocumentsList.isEmpty()) {
                                        Integer fallbackMatches = 0;
                                        for (Document_Checklist__c docCheck : allDocumentsList) {
                                            if (String.isNotBlank(resolveDocumentTypeValue(docCheck)) &&
                                                isSubCategoryInDocumentMasters(config.Document_Master_Name__c, resolveDocumentTypeValue(docCheck))) {
                                                try {
                                                    Object lookupFieldValue = docCheck.get(expectedLookupField);
                                                    if (lookupFieldValue != null && String.valueOf(lookupFieldValue) == effectiveDocumentLookupKey) {
                                                        allMatchingDocs.add(docCheck);
                                                        fallbackMatches++;
                                                        System.debug('   ✅ Found matching document from fallback search (' + fallbackMatches + ' matches found) - Lookup Field: ' + expectedLookupField + ', Doc ID: ' + docCheck.Id);
                                                    }
                                                } catch (Exception e) {
                                                    // Field doesn't exist, skip
                                                    system.debug('❌ ERROR in fallback document lookup: ' + e.getMessage());
                                                    continue;
                                                }
                                            }
                                        } 
                                    }
                                }
                                // Now collect ALL attachments from ALL matching documents
                                if (!allMatchingDocs.isEmpty()) {
                                    Integer totalAttachments = 0;
                                    for (Document_Checklist__c doc : allMatchingDocs) {
                                        if (doc.ContentDocumentLinks != null) {
                                            for (ContentDocumentLink cdl : doc.ContentDocumentLinks) {
                                                AttachmentWrapper att = new AttachmentWrapper();
                                                att.contentDocumentId = cdl.ContentDocumentId;
                                                att.contentVersionId = cdl.ContentDocument.LatestPublishedVersionId;
                                                att.title = cdl.ContentDocument.Title;
                                                att.fileExtension = cdl.ContentDocument.FileExtension;
                                                att.fileSize = cdl.ContentDocument.ContentSize;
                                                att.fileSizeFormatted = formatFileSize(cdl.ContentDocument.ContentSize);
                                                fieldStatus.documentAttachments.add(att);
                                                totalAttachments++;
                                            }
                                        }
                                    }
                                    fieldStatus.totalAttachments = totalAttachments;
                                    System.debug('   ✅ Collected ' + totalAttachments + ' attachments from ' + allMatchingDocs.size() + ' document(s)');
                                }
                            } else {
                                System.debug('   ❌ No document found in map for subcategory(ies): ' + config.Document_Master_Name__c);
                            }
                        }
                        
                        if (!isCombinedScenarioHandled &&
                            String.isNotBlank(recordDocumentLookupField) &&
                            String.isNotBlank(parentDocumentLookupField) &&
                            String.isNotBlank(documentLookupKey)) {
                            appendAttachmentsForLookupConfig(
                                fieldStatus,
                                allDocumentsList,
                                recordDocumentLookupField,
                                documentLookupKey,
                                config.Document_Master_Name__c,
                                additionalDocFieldCheck,
                                filterFieldApiName,
                                filterValue
                            );
                        }

                        // Legacy attachment processing (if matchingDoc was set by additional filter logic above)
                        // This handles the "additionalDocFieldCheck" path
                        if (matchingDoc != null && fieldStatus.totalAttachments == 0) {
                            System.debug('   ✅ MATCH FOUND! Document ID: ' + matchingDoc.Id + ', Has attachments: ' + (matchingDoc.ContentDocumentLinks != null && matchingDoc.ContentDocumentLinks.size() > 0));
                            if (matchingDoc.ContentDocumentLinks != null) {
                                fieldStatus.totalAttachments = matchingDoc.ContentDocumentLinks.size();
                                for (ContentDocumentLink cdl : matchingDoc.ContentDocumentLinks) {
                                AttachmentWrapper att = new AttachmentWrapper();
                                att.contentDocumentId = cdl.ContentDocumentId;
                                att.contentVersionId = cdl.ContentDocument.LatestPublishedVersionId;
                                att.title = cdl.ContentDocument.Title;
                                att.fileExtension = cdl.ContentDocument.FileExtension;
                                att.fileSize = cdl.ContentDocument.ContentSize;
                                att.fileSizeFormatted = formatFileSize(cdl.ContentDocument.ContentSize);
                                fieldStatus.documentAttachments.add(att);
                            }
                        }
                        } else if (matchingDoc == null) {
                            System.debug('   ❌ NO MATCH - Document Master Name "' + config.Document_Master_Name__c + '" not found or filtered out');
                        }
                    }
                    
                    result.fields.add(fieldStatus);
                } catch (Exception configEx) {
                    // Continue with next field instead of failing entire record
                }
            }
        }
        
        return result;
    }
    
    /**
     * Format file size for display
     */
    private static String formatFileSize(Integer bytes) {
        if (bytes == null) {return '0 B';}  
        if (bytes < 1024) {return bytes + ' B';}
        if (bytes < 1048576) {return (bytes / 1024) + ' KB';}
        return (bytes / 1048576) + ' MB';
    }

    private static Integer appendAttachmentsFromDocuments(
        FieldVerificationStatus fieldStatus,
        List<Document_Checklist__c> documents,
        Set<String> existingContentDocIds
    ) {
        if (fieldStatus == null || documents == null || documents.isEmpty()) {
            return 0;
        }
        if (fieldStatus.documentAttachments == null) {
            fieldStatus.documentAttachments = new List<AttachmentWrapper>();
        }

        Set<String> dedupeSet = existingContentDocIds != null
            ? existingContentDocIds
            : new Set<String>();
        if (existingContentDocIds == null) {
            for (AttachmentWrapper att : fieldStatus.documentAttachments) {
                if (att != null && String.isNotBlank(att.contentDocumentId)) {
                    dedupeSet.add(att.contentDocumentId);
                }
            }
        }

        Integer added = 0;
        for (Document_Checklist__c doc : documents) {
            if (doc == null || doc.ContentDocumentLinks == null) {
                continue;
            }
            for (ContentDocumentLink cdl : doc.ContentDocumentLinks) {
                if (cdl == null || cdl.ContentDocument == null || String.isBlank(cdl.ContentDocumentId) || dedupeSet.contains(cdl.ContentDocumentId)) {
                    continue;
                }
                AttachmentWrapper att = new AttachmentWrapper();
                att.contentDocumentId = cdl.ContentDocumentId;
                att.contentVersionId = cdl.ContentDocument.LatestPublishedVersionId;
                att.title = cdl.ContentDocument.Title;
                att.fileExtension = cdl.ContentDocument.FileExtension;
                att.fileSize = cdl.ContentDocument.ContentSize;
                att.fileSizeFormatted = formatFileSize(cdl.ContentDocument.ContentSize);
                fieldStatus.documentAttachments.add(att);
                dedupeSet.add(cdl.ContentDocumentId);
                added++;
            }
        }

        if (added > 0) {
            fieldStatus.totalAttachments = fieldStatus.documentAttachments.size();
        }
        return added;
    }

    private static void appendAttachmentsForLookupConfig(
        FieldVerificationStatus fieldStatus,
        List<Document_Checklist__c> allDocumentsList,
        String lookupFieldApiName,
        String lookupKey,
        String documentMasterNames,
        Boolean additionalDocFieldCheck,
        String filterFieldApiName,
        String filterValue
    ) {
        if (fieldStatus == null || String.isBlank(lookupFieldApiName) || String.isBlank(lookupKey) ||
            String.isBlank(documentMasterNames) || allDocumentsList == null || allDocumentsList.isEmpty()) {
            return;
        }

        Set<String> existingContentDocIds = new Set<String>();
        if (fieldStatus.documentAttachments != null) {
            for (AttachmentWrapper att : fieldStatus.documentAttachments) {
                if (att != null && String.isNotBlank(att.contentDocumentId)) {
                    existingContentDocIds.add(att.contentDocumentId);
                }
            }
        }

        List<Document_Checklist__c> matchingDocs = new List<Document_Checklist__c>();
        for (Document_Checklist__c docCheck : allDocumentsList) {
            if (docCheck == null || String.isBlank(resolveDocumentTypeValue(docCheck)) ||
                !isSubCategoryInDocumentMasters(documentMasterNames, resolveDocumentTypeValue(docCheck))) {
                continue;
            }

            try {
                Object lookupVal = docCheck.get(lookupFieldApiName);
                if (lookupVal == null || String.valueOf(lookupVal) != lookupKey) {
                    continue;
                }
            } catch (Exception e) {
                continue;
            }

            if (additionalDocFieldCheck == true && String.isNotBlank(filterFieldApiName) && String.isNotBlank(filterValue)) {
                try {
                    Object docFieldValue = docCheck.get(filterFieldApiName);
                    String docFieldValueStr = docFieldValue != null ? String.valueOf(docFieldValue) : '';
                    if (!docFieldValueStr.equalsIgnoreCase(filterValue)) {
                        continue;
                    }
                } catch (Exception e) {
                    continue;
                }
            }

            if (docCheck.ContentDocumentLinks == null) {
                continue;
            }
            matchingDocs.add(docCheck);
        }

        appendAttachmentsFromDocuments(fieldStatus, matchingDocs, existingContentDocIds);
    }

    private static Boolean isLoanApplicationObject(String objectApiName) {
        return String.isBlank(objectApiName) ||
            objectApiName == 'ResidentialLoanApplication' ||
            objectApiName == 'Application__c';
    }

    private static Boolean isApplicantObject(String objectApiName) {
        return objectApiName == 'Applicant__c';
    }

    private static String resolveDocumentTypeValue(Document_Checklist__c docCheck) {
        if (docCheck == null) {
            return null;
        }
        if (String.isNotBlank(docCheck.Document_Type__c)) {
            return docCheck.Document_Type__c;
        }
        return null;
    }
    
    /**
     * Check if a subcategory matches any of the comma-separated document master names
     * @param documentMasterNames Comma-separated list of document master names (e.g., "Master1,Master2,Master3")
     * @param subCategory The subcategory to check (e.g., "Master2")
     * @return True if subcategory matches any of the master names (case-insensitive), false otherwise
     */
    private static Boolean isSubCategoryInDocumentMasters(String documentMasterNames, String subCategory) {
        if (String.isBlank(documentMasterNames) || String.isBlank(subCategory)) {
            return false;
        }
        
        // Split by comma and trim each value
        List<String> masterNames = new List<String>();
        for (String masterName : documentMasterNames.split(',')) {
            String trimmed = masterName.trim();
            if (String.isNotBlank(trimmed)) {
                masterNames.add(trimmed);
            }
        }
        
        // Check if subcategory matches any master name (case-insensitive)
        for (String masterName : masterNames) {
            if (masterName.equalsIgnoreCase(subCategory)) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * Get list of document master names from comma-separated string
     * @param documentMasterNames Comma-separated list of document master names
     * @return List of trimmed master names
     */
    private static List<String> getDocumentMasterNamesList(String documentMasterNames) {
        List<String> masterNames = new List<String>();
        if (String.isBlank(documentMasterNames)) {
            return masterNames;
        }
        
        for (String masterName : documentMasterNames.split(',')) {
            String trimmed = masterName.trim();
            if (String.isNotBlank(trimmed)) {
                masterNames.add(trimmed);
            }
        }
        
        return masterNames;
    }
    
    /**
     * Common method to query ResidentialLoanApplication with all fields needed by isQCNeeded and related methods
     * This consolidates multiple queries into a single query to improve performance
     * Uses static cache to avoid duplicate queries within the same transaction
     * @param loanApplicationId The ResidentialLoanApplication ID
     * @return ResidentialLoanApplication with all required fields, or null if not found
     */
    public static Application__c getLoanApplicationForQC(Id loanApplicationId) {
        // Check cache first
        if (cachedLoanApplications.containsKey(loanApplicationId)) {
            System.debug('✅ Using cached Loan Application: ' + loanApplicationId);
            return cachedLoanApplications.get(loanApplicationId);
        }
        
        try {
            List<Application__c> loanApps = [
                SELECT Id 
                FROM Application__c
                WHERE Id = :loanApplicationId
                LIMIT 1
            ];
            
            if (loanApps.isEmpty()) {
                return null;
            }
            
            // Cache the result for reuse in the same transaction
            Application__c loanApp = loanApps[0];
            cachedLoanApplications.put(loanApplicationId, loanApp);
            System.debug('💾 Cached Loan Application: ' + loanApplicationId);
            
            return loanApp;
            
        } catch (Exception e) {
            System.debug('❌ Error querying Loan Application: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Get RecordType developer name for a loan application
     * Returns the RecordType (e.g., "HL", "EL") to match with Product__c field in metadata
     * Uses cached loan application if available, otherwise queries
     * @param loanApplicationId The ResidentialLoanApplication ID
     * @param cachedLoanApp Optional cached ResidentialLoanApplication to avoid duplicate query
     * @return RecordType developer name or empty string if not found
     */
    private static String getRecordTypeForLoan(Id loanApplicationId, Application__c cachedLoanApp) {
        try {
            Application__c loanApp = cachedLoanApp;
            
            // If cached loan app not provided, query it
            if (loanApp == null) {
                loanApp = getLoanApplicationForQC(loanApplicationId);
            }
            
            if (loanApp == null) {
                return '';
            }
            
            String recordTypeName = '';
            System.debug('🏷️ RecordType DeveloperName: ' + recordTypeName);
            return recordTypeName;
            
        } catch (Exception e) {
            System.debug('❌ Error getting RecordType: ' + e.getMessage());
            return ''; // Return empty string if error
        }
    }
    
    /**
     * Overloaded method for backward compatibility
     */
    private static String getRecordTypeForLoan(Id loanApplicationId) {
        return getRecordTypeForLoan(loanApplicationId, null);
    }
    
    /**
     * Check if a field exists on an object (for backward compatibility)
     * 
     * @param objectName The object API name
     * @param fieldName The field API name
     * @return True if field exists, false otherwise
     */
    private static Boolean hasField(String objectName, String fieldName) {
        try {
            // OPTIMIZATION: Use cached global describe
            if (globalDescribeCache == null) {
                globalDescribeCache = Schema.getGlobalDescribe();
            }
            
            Schema.SObjectType sobjectType = globalDescribeCache.get(objectName);
            if (sobjectType == null) {
                return false;
            }
            
            // OPTIMIZATION: Use cached field maps
            Map<String, Schema.SObjectField> fieldMap = fieldDescribeCache.get(objectName);
            if (fieldMap == null) {
                fieldMap = sobjectType.getDescribe().fields.getMap();
                fieldDescribeCache.put(objectName, fieldMap);
            }
            
            return fieldMap.containsKey(fieldName.toLowerCase());
        } catch (Exception e) {
            return false;
        }
    }

    private static String getOptionalMetadataString(SObject metadataRecord, String fieldApiName) {
        if (metadataRecord == null || String.isBlank(fieldApiName)) {
            return null;
        }
        try {
            Object rawValue = metadataRecord.get(fieldApiName);
            return rawValue != null ? String.valueOf(rawValue).trim() : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static Integer getOptionalMetadataInteger(SObject metadataRecord, String fieldApiName) {
        if (metadataRecord == null || String.isBlank(fieldApiName)) {
            return null;
        }
        try {
            Object rawValue = metadataRecord.get(fieldApiName);
            if (rawValue == null) {
                return null;
            }
            if (rawValue instanceof Integer) {
                return (Integer) rawValue;
            }
            if (rawValue instanceof Decimal) {
                return ((Decimal) rawValue).intValue();
            }
            return Integer.valueOf(String.valueOf(rawValue));
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean getOptionalMetadataBoolean(SObject metadataRecord, String fieldApiName) {
        if (metadataRecord == null || String.isBlank(fieldApiName)) {
            return false;
        }
        try {
            Object rawValue = metadataRecord.get(fieldApiName);
            if (rawValue == null) {
                return false;
            }
            if (rawValue instanceof Boolean) {
                return (Boolean) rawValue;
            }
            return String.valueOf(rawValue).equalsIgnoreCase('true');
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean hasAnyDocumentsInMasterMap(Map<String, List<Document_Checklist__c>> docsByMaster) {
        if (docsByMaster == null || docsByMaster.isEmpty()) {
            return false;
        }
        for (List<Document_Checklist__c> docs : docsByMaster.values()) {
            if (docs != null && !docs.isEmpty()) {
                return true;
            }
        }
        return false;
    }

    private static Map<String, List<Document_Checklist__c>> mergeDocMasterMaps(
        Map<String, List<Document_Checklist__c>> primaryMap,
        Map<String, List<Document_Checklist__c>> secondaryMap
    ) {
        Map<String, List<Document_Checklist__c>> merged = new Map<String, List<Document_Checklist__c>>();

        if (primaryMap != null) {
            for (String key : primaryMap.keySet()) {
                List<Document_Checklist__c> docs = primaryMap.get(key);
                merged.put(key, docs == null ? new List<Document_Checklist__c>() : new List<Document_Checklist__c>(docs));
            }
        }

        if (secondaryMap != null) {
            for (String key : secondaryMap.keySet()) {
                List<Document_Checklist__c> secondaryDocs = secondaryMap.get(key);
                if (!merged.containsKey(key)) {
                    merged.put(key, secondaryDocs == null ? new List<Document_Checklist__c>() : new List<Document_Checklist__c>(secondaryDocs));
                    continue;
                }
                List<Document_Checklist__c> existing = merged.get(key);
                Set<Id> existingIds = new Set<Id>();
                for (Document_Checklist__c doc : existing) {
                    if (doc != null && doc.Id != null) existingIds.add(doc.Id);
                }
                for (Document_Checklist__c doc : (secondaryDocs == null ? new List<Document_Checklist__c>() : secondaryDocs)) {
                    if (doc == null || doc.Id == null || !existingIds.contains(doc.Id)) {
                        existing.add(doc);
                        if (doc != null && doc.Id != null) existingIds.add(doc.Id);
                    }
                }
            }
        }

        return merged;
    }

    @TestVisible
    private static String formatDateFieldValue(Object fieldValue, String dateFormat) {
        if (fieldValue == null) {
            return '';
        }
        if (String.isBlank(dateFormat)) {
            return String.valueOf(fieldValue);
        }
        try {
            if (fieldValue instanceof Date) {
                Date dateValue = (Date) fieldValue;
                Datetime dtValue = Datetime.newInstance(dateValue, Time.newInstance(0, 0, 0, 0));
                return dtValue.format(dateFormat);
            }
            if (fieldValue instanceof Datetime) {
                return ((Datetime) fieldValue).format(dateFormat);
            }
        } catch (Exception e) {
            return String.valueOf(fieldValue);
        }
        return String.valueOf(fieldValue);
    }

    @TestVisible
    private static String formatDateStringValue(String rawValue, String dateFormat) {
        if (String.isBlank(rawValue)) {
            return rawValue;
        }
        if (String.isBlank(dateFormat)) {
            return rawValue;
        }

        try {
            Date dateValue = Date.valueOf(rawValue);
            Datetime dtValue = Datetime.newInstance(dateValue, Time.newInstance(0, 0, 0, 0));
            return dtValue.format(dateFormat);
        } catch (Exception dateEx) {
            // Try datetime parse if date parse fails.
        }

        try {
            Datetime dtValue = Datetime.valueOf(rawValue);
            return dtValue.format(dateFormat);
        } catch (Exception datetimeEx) {
            return rawValue;
        }
    }
    
// ============================================================================
    // WRAPPER CLASSES
    // ============================================================================
    
    public class QCNeededResult {
        @AuraEnabled public Boolean isQCNeeded;
        @AuraEnabled public List<UnverifiedFieldInfo> unverifiedFields;
        @AuraEnabled public Integer totalFields;
        @AuraEnabled public Integer verifiedFieldsCount;
        @AuraEnabled public Integer unverifiedFieldsCount;
    }
    
    public class UnverifiedFieldInfo {
        @AuraEnabled public String objectName;
        @AuraEnabled public String sectionName;
        @AuraEnabled public String recordId;
        @AuraEnabled public String fieldName;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public String currentStatus;
        @AuraEnabled public String currentValue;
    }
    
    public class VerificationStatusResult {
        @AuraEnabled public String objectName;
        @AuraEnabled public String sectionName;
        @AuraEnabled public String parentSectionName; // NEW: Which parent section this record belongs to
        @AuraEnabled public Integer objectLevel;
        @AuraEnabled public String recordId;
        @AuraEnabled public String recordLabel;
        @AuraEnabled public String parentRecordId;
        @AuraEnabled public List<FieldVerificationStatus> fields;
        @AuraEnabled public Boolean isEmpty; // Flag for empty sections with no records
    }
    
    public class FieldVerificationStatus {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public String objectName;
        @AuraEnabled public Integer objectLevel;
        @AuraEnabled public String recordId;
        @AuraEnabled public String parentRecordId;
        @AuraEnabled public String currentValueInDB;
        @AuraEnabled public String storedFieldValue; // Value stored at time of verification
        @AuraEnabled public String fieldValueFromVerifiedFields; // Field_Value__c from Verified_Fields__c object
        @AuraEnabled public String verificationStatus;
        @AuraEnabled public String verificationComments;
        @AuraEnabled public String fieldVerificationId;
        @AuraEnabled public String documentMasterName;
        @AuraEnabled public String additionalDocumentApiNameToFilter;
        @AuraEnabled public String additionalDocumentValueToFilter;
        @AuraEnabled public List<AttachmentWrapper> documentAttachments;
        @AuraEnabled public Integer totalAttachments; 
        @AuraEnabled public String childSectionName; // Child section for grouping fields in UI
        @AuraEnabled public Boolean isJson; // Flag to indicate if field value is JSON
        @AuraEnabled public String jsonFieldValue; // JSON node paths to display (e.g., "Amount__c:Value,Amount__c:Currency")
        @AuraEnabled public DateTime manuallyVerifiedDate; // Timestamp when field was manually verified
        @AuraEnabled public String verifiedStatusDocumentNames;
        @AuraEnabled public String verifiedStatusDocumentIds;
        @AuraEnabled public Boolean fallbackToParentDocument;
        @AuraEnabled public String documentSourceMode;
    }
    
    public class AttachmentWrapper {
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public Integer fileSize;
        @AuraEnabled public String fileSizeFormatted;
    }
    
}