public class DemoClass {
    public static void demoMethod() {
        List<Document_Checklist__c> documentChecklists = [
            SELECT Id, Application__c, Application_Line_Items__c, Applicant__c, Applicant__r.Name
            FROM Document_Checklist__c
            WHERE Id = 'a0hIn000000SJkyIAG'
            LIMIT 1
        ];

        if (documentChecklists != null && !documentChecklists.isEmpty()) {
            Document_Checklist__c documentChecklist = documentChecklists[0];
            String applicantName = null;
            if (documentChecklist.Applicant__c != null && documentChecklist.Applicant__r != null) {
                applicantName = documentChecklist.Applicant__r.Name;
            }

            Applicant__c applicantRecord = null;
            if (documentChecklist.Applicant__c != null) {
                List<Applicant__c> applicants = [
                    SELECT Id, Name
                    FROM Applicant__c
                    WHERE Id = :documentChecklist.Applicant__c
                    LIMIT 1
                ];
                if (!applicants.isEmpty()) {
                    applicantRecord = applicants[0];
                }
            }

            System.debug('Document Checklist Id: ' + documentChecklist.Id);
            System.debug('Applicant Id: ' + documentChecklist.Applicant__c);
            System.debug('Applicant Name from Applicant__r.Name: ' + applicantName);
            System.debug('Applicant Name from direct Applicant__c query: ' + (applicantRecord != null ? applicantRecord.Name : null));
        }
    }
}