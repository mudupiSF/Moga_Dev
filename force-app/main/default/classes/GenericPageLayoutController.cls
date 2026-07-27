public with sharing class GenericPageLayoutController {
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getFieldConfig(
        String apexClassName,
        String apexMethodName,
        String recordId,
        Map<String, Object> params
    ) {
        if (String.isBlank(apexClassName) || String.isBlank(apexMethodName)) {
            throw new AuraHandledException('apexClassName and apexMethodName are required.');
        }
        try {
            Callable provider = (Callable) Type.forName(apexClassName).newInstance();
            Map<String, Object> args = params != null ? new Map<String, Object>(params) : new Map<String, Object>();
            if (String.isNotBlank(recordId)) {
                args.put('recordId', recordId);
            }
            Object result = provider.call(apexMethodName, args);
            if (result instanceof Map<String, Object>) {
                return (Map<String, Object>) result;
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error invoking ' + apexClassName + '.' + apexMethodName + ': ' + e.getMessage()
            );
        }
        return new Map<String, Object>{
            'loanBasicInfo' => new List<Map<String, Object>>(),
            'loanDetail' => new List<Map<String, Object>>(),
            'professionalDetail' => new List<Map<String, Object>>()
        };
    }
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> savePageData(
        String apexClassName,
        String apexMethodName,
        String recordId,
        Map<String, Object> params
    ) {
        if (String.isBlank(apexClassName) || String.isBlank(apexMethodName)) {
            throw new AuraHandledException('apexClassName and apexMethodName are required.');
        }
        try {
            Callable provider = (Callable) Type.forName(apexClassName).newInstance();
            Map<String, Object> args = params != null ? new Map<String, Object>(params) : new Map<String, Object>();
            if (String.isNotBlank(recordId)) {
                args.put('recordId', recordId);
            }
            Object result = provider.call(apexMethodName, args);
            if (result instanceof Map<String, Object>) {
                return (Map<String, Object>) result;
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error invoking ' + apexClassName + '.' + apexMethodName + ': ' + e.getMessage()
            );
        }
        return new Map<String, Object>{ 'isSuccess' => false, 'message' => 'Error saving data' };
    }
}