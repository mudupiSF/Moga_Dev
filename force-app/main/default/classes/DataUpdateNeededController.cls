/**
 * Controller for displaying Verified_Fields__c records with status "Data Update Needed"
 * @author System Generated
 * @date 2026-01-28
 */
public without sharing class DataUpdateNeededController {
    
    /**
     * Wrapper class for Verified_Fields__c records to be sent to LWC
     */
    public class VerifiedFieldWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String objectName;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public String fieldName;
        @AuraEnabled public String fieldValue;
        @AuraEnabled public String comments;
        @AuraEnabled public String lookupFieldName;
        @AuraEnabled public String recordReference;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String addressName;
        @AuraEnabled public String employmentName;
        @AuraEnabled public String incomeName;
        @AuraEnabled public String productName;
        @AuraEnabled public String bankName;
        @AuraEnabled public DateTime verifiedDate;
        @AuraEnabled public DateTime createdDate;
    }
    
    /**
     * Check if there are any fields with "Data Update Needed" status for a given loan application
     * Returns only the latest record for each field based on Manually_Verified_Date__c
     * 
     * @param loanApplicationId The Loan Application ID
     * @return True if there are any fields requiring data updates, false otherwise
     */
    @AuraEnabled(cacheable=false)
    public static Boolean hasDataUpdateNeeded(String loanApplicationId) {
        try {
            // Validate input
            if (String.isBlank(loanApplicationId)) {
                return false;
            }
            
            Id loanAppId = Id.valueOf(loanApplicationId);
            
            // Query to check if any records exist with "Data Update Needed" status
            List<Verified_Fields__c> allRecords = [
                SELECT Id, 
                       Field_Name__c, 
                       Manually_Verified_Date__c, 
                       CreatedDate,
                       Loan_Application__c,
                       Loan_Applicant__c
                FROM Verified_Fields__c
                WHERE Loan_Application__c = :loanAppId
                AND Status__c = 'Data Update Needed'
                ORDER BY Field_Name__c, Manually_Verified_Date__c DESC NULLS LAST, CreatedDate DESC
                LIMIT 1000
            ];
            
            // If no records at all, return false
            if (allRecords.isEmpty()) {
                System.debug('No records with "Data Update Needed" status found');
                return false;
            }
            
            // Apply same deduplication logic - keep only latest for each field
            Set<String> uniqueKeys = new Set<String>();
            Integer latestRecordCount = 0;
            
            for (Verified_Fields__c vf : allRecords) {
                String recordId = getRecordIdFromVerifiedFieldSimple(vf);
                String uniqueKey = recordId + '_' + vf.Field_Name__c;
                
                // Only count if this is the first occurrence (already ordered by date DESC)
                if (!uniqueKeys.contains(uniqueKey)) {
                    uniqueKeys.add(uniqueKey);
                    latestRecordCount++;
                }
            }
            
            System.debug('Found ' + latestRecordCount + ' unique latest fields with "Data Update Needed" status');
            return latestRecordCount > 0;
            
        } catch (Exception e) {
            System.debug('ERROR in hasDataUpdateNeeded: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Return false on error to avoid breaking the UI
            return false;
        }
    }
    
    /**
     * Simple version to get record ID from Verified_Fields__c for the boolean check method
     * @param vf The Verified_Fields__c record
     * @return The record ID from the first non-null lookup field
     */
    private static String getRecordIdFromVerifiedFieldSimple(Verified_Fields__c vf) {
        // Check lookup fields in priority order
       
        if (vf.Loan_Applicant__c != null) {
            return String.valueOf(vf.Loan_Applicant__c);
        }
        // Default to Loan_Application__c
        return vf.Loan_Application__c != null ? String.valueOf(vf.Loan_Application__c) : '';
    }
    
    /**
     * Get all Verified_Fields__c records with status "Data Update Needed" for a given loan application
     * Returns only the latest record for each field based on Manually_Verified_Date__c
     * 
     * @param loanApplicationId The Loan Application ID
     * @return List of VerifiedFieldWrapper records
     */
    @AuraEnabled(cacheable=true)
    public static List<VerifiedFieldWrapper> getDataUpdateNeededFields(String loanApplicationId) {
        List<VerifiedFieldWrapper> wrapperList = new List<VerifiedFieldWrapper>();
        
        try {
            // Validate input
            if (String.isBlank(loanApplicationId)) {
                throw new AuraHandledException('Loan Application ID is required');
            }
            
            Id loanAppId = Id.valueOf(loanApplicationId);
            
            // Query Field Verification Config metadata to get Display Names
            Map<String, String> fieldDisplayNames = getFieldDisplayNames();
            
            // Static query with specific fields including related record names
            List<Verified_Fields__c> allRecords = [
                SELECT Id, 
                       Object_Name__c,
                       Field_Name__c, 
                       Field_Value__c, 
                       Status__c,
                       Manually_Verification_Comments__c,
                       Recommended_Value__c,
                       Manually_Verified_Date__c, 
                       CreatedDate,
                       Loan_Application__c
                FROM Verified_Fields__c
                WHERE Loan_Application__c = :loanAppId
                AND Status__c = 'Data Update Needed'
                ORDER BY Field_Name__c, Manually_Verified_Date__c DESC NULLS LAST, CreatedDate DESC
            ];
            
            System.debug('Query returned: ' + allRecords.size() + ' records');
            
            // Keep only the latest record for each field
            Map<String, Verified_Fields__c> latestByFieldName = new Map<String, Verified_Fields__c>();
            
            for (Verified_Fields__c vf : allRecords) {
                Map<String, Object> lookupInfo = getLookupFieldInfo(vf);
                String recordId = (String)lookupInfo.get('recordId');
                String uniqueKey = recordId + '_' + vf.Field_Name__c;
                
                // Only add if this is the first occurrence (already ordered by date DESC)
                if (!latestByFieldName.containsKey(uniqueKey)) {
                    latestByFieldName.put(uniqueKey, vf);
                }
            }
            
            // Convert to wrapper objects
            for (Verified_Fields__c vf : latestByFieldName.values()) {
                VerifiedFieldWrapper wrapper = new VerifiedFieldWrapper();
                wrapper.id = vf.Id;
                wrapper.objectName = vf.Object_Name__c;
                wrapper.fieldName = vf.Field_Name__c;
                wrapper.fieldValue = vf.Field_Value__c;
                wrapper.comments = vf.Manually_Verification_Comments__c;
                wrapper.verifiedDate = vf.Manually_Verified_Date__c;
                wrapper.createdDate = vf.CreatedDate;
                
                // Get field label - use Display Name from metadata if available, otherwise use schema label
                String displayName = fieldDisplayNames.get(vf.Field_Name__c);
                if (String.isNotBlank(displayName)) {
                    wrapper.fieldLabel = displayName;
                } else {
                    wrapper.fieldLabel = getFieldLabel(vf.Object_Name__c, vf.Field_Name__c);
                }
                
                // Get record reference and which lookup field is populated
                Map<String, Object> lookupInfo = getLookupFieldInfo(vf);
                wrapper.recordReference = (String)lookupInfo.get('recordId');
                wrapper.lookupFieldName = (String)lookupInfo.get('lookupFieldName');
            
                wrapperList.add(wrapper);
            }
            
            System.debug('Returning ' + wrapperList.size() + ' unique records with "Data Update Needed" status');
            
        } catch (Exception e) {
            System.debug('ERROR in getDataUpdateNeededFields: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving data: ' + e.getMessage());
        }
        
        return wrapperList;
    }
    
    /**
     * Get display names from Field Verification Config metadata
     * @return Map of Field_Name__c to MasterLabel
     */
    private static Map<String, String> getFieldDisplayNames() {
        Map<String, String> displayNames = new Map<String, String>();
        
        try {
            // Query metadata for Display Names (using MasterLabel as display name)
            List<Field_Verification_Config__mdt> configs = [
                SELECT Field_Name__c, MasterLabel
                FROM Field_Verification_Config__mdt
                WHERE Active__c = true
                AND MasterLabel != null
            ];
            
            for (Field_Verification_Config__mdt config : configs) {
                if (String.isNotBlank(config.MasterLabel)) {
                    displayNames.put(config.Field_Name__c, config.MasterLabel);
                }
            }
            
            System.debug('Loaded ' + displayNames.size() + ' display names from metadata');
            
        } catch (Exception e) {
            System.debug('ERROR loading field display names: ' + e.getMessage());
        }
        
        return displayNames;
    }
    
    /**
     * Get lookup field information from Verified_Fields__c record
     * Returns record ID and lookup field name
     * @param vf The Verified_Fields__c record
     * @return Map with 'recordId' and 'lookupFieldName'
     */
    private static Map<String, Object> getLookupFieldInfo(Verified_Fields__c vf) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('recordId', '');
        result.put('lookupFieldName', '');
        
        // Check lookup fields in priority order
        
        
        if (vf.Loan_Applicant__c != null) {
            result.put('recordId', String.valueOf(vf.Loan_Applicant__c));
            result.put('lookupFieldName', 'Loan Applicant');
            return result;
        }
       
        // Default to Loan_Application__c if nothing else is found
        if (vf.Loan_Application__c != null) {
            result.put('recordId', String.valueOf(vf.Loan_Application__c));
            result.put('lookupFieldName', 'Loan Application');
        }
        
        return result;
    }
    
    /**
     * Get field label from object and field API name
     * @param objectName The object API name
     * @param fieldName The field API name
     * @return Field label or field name if label not found
     */
    private static String getFieldLabel(String objectName, String fieldName) {
        if (String.isBlank(objectName) || String.isBlank(fieldName)) {
            return fieldName;
        }
        
        try {
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            if (objectType == null) {
                return fieldName;
            }
            
            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
            Schema.SObjectField field = fieldMap.get(fieldName);
            
            if (field != null) {
                return field.getDescribe().getLabel();
            }
        } catch (Exception e) {
            System.debug('Error getting field label: ' + e.getMessage());
        }
        
        return fieldName;
    }
    
    /**
     * Get friendly label for lookup field names
     * @param lookupFieldName The lookup field API name
     * @return Friendly label
     */
    private static String getLookupFieldLabel(String lookupFieldName) {
        if (String.isBlank(lookupFieldName)) {
            return '';
        }
        
        // Remove __c and format nicely
        String label = lookupFieldName.replace('__c', '').replace('_', ' ');
        
        // Capitalize each word
        List<String> words = label.split(' ');
        List<String> capitalizedWords = new List<String>();
        for (String word : words) {
            if (word.length() > 0) {
                capitalizedWords.add(word.substring(0, 1).toUpperCase() + word.substring(1).toLowerCase());
            }
        }
        
        return String.join(capitalizedWords, ' ');
    }
}