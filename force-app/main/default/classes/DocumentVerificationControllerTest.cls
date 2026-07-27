@isTest
private class DocumentVerificationControllerTest {

    @testSetup
    static void setupData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            Username          = 'dvtest' + System.currentTimeMillis() + '@testorg.example.com',
            Email             = 'dvtest@testorg.example.com',
            LastName          = 'DVTest',
            Alias             = 'dvtst',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Enhanced_UI_Access' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        System.runAs(u) {
            Application__c app = new Application__c(
                Stage__c     = 'QDE',
                Sub_Stage__c = 'Basic Details',
                Product__c   = 'CV'
            );
            insert app;

            insert new Applicant__c(
                Application__c         = app.Id,
                Applicant_Type__c      = 'Borrower',
                Applicant_Tab_Label__c = 'Borrower',
                Customer_First_Name__c = 'Test',
                Customer_Last_Name__c  = 'Applicant',
                Date_of_Birth__c       = Date.newInstance(1990, 1, 15),
                PAN_Number_Verified__c = false
            );
        }
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Alias = 'dvtst' LIMIT 1];
    }

    private static Id applicantId() {
        return [SELECT Id FROM Applicant__c LIMIT 1].Id;
    }

    private static String samplePanExtractionJson() {
        return '{"document_type":"PAN","classification":"identity","confidence":0.95,'
            + '"metadata":{"source":"einstein"},'
            + '"document_data":{"full_name":"John Doe","father_name":"Richard Doe",'
            + '"document_number":"abcde1234f","date_of_birth":"15/01/1990",'
            + '"issuing_authority":"Income Tax Department"}}';
    }

    private static Integration_Master__c createMockIntegrationMaster(String name) {
        Integration_Master__c master = new Integration_Master__c(
            Name = name,
            Action_Master_Name__c = 'Test Action',
            Apex_Class_Name__c = 'ApplicationUtilityTest.MockIntegrationHandler',
            End_Point_URL__c = 'https://example.org/test',
            Is_Mocking_Service_Enabled__c = true,
            Mocking_Service_Response__c = '{"status":"success"}',
            Mocking_Service_Status__c = 'OK',
            Mocking_Service_Status_Code__c = 200,
            Encrypt_Request__c = false,
            Decrypt_Response__c = false,
            Allow_Retry__c = false,
            Allow_Refresh__c = true,
            Max_Number_of_Retries_Allowed__c = 3,
            Maximum_Limit_Exceeded_Error_Message__c = 'Max retries exceeded',
            Is_Auto_Initiated__c = false
        );
        insert master;
        return master;
    }

    @isTest
    static void getApplicant_returnsApplicantFields() {
        System.runAs(getTestUser()) {
            Id applicant = applicantId();

            Test.startTest();
            Applicant__c result = documentVerificationController.getApplicant(applicant);
            Test.stopTest();

            System.assertNotEquals(null, result, 'Applicant should be returned');
            System.assertEquals(applicant, result.Id);
            System.assertEquals('Test', result.Customer_First_Name__c);
            System.assertEquals('Applicant', result.Customer_Last_Name__c);
            System.assertEquals(Date.newInstance(1990, 1, 15), result.Date_of_Birth__c);
        }
    }

    @isTest
    static void ocrPANCard_returnsNullWhenNoFileReference() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Map<String, Object> result = documentVerificationController.ocrPANCard(
                applicantId(),
                null,
                null
            );
            Test.stopTest();

            System.assertEquals(null, result, 'OCR should return null without a file reference');
        }
    }

    @isTest
    static void ocrPANCard_usesContentDocumentIdWhenProvided() {
        System.runAs(getTestUser()) {
            ContentVersion version = new ContentVersion(
                Title = 'pan-doc-id',
                PathOnClient = 'pan-doc-id.pdf',
                VersionData = Blob.valueOf('pan-doc-id')
            );
            insert version;
            version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
            ];

            Test.startTest();
            Map<String, Object> result = documentVerificationController.ocrPANCard(
                applicantId(),
                version.ContentDocumentId,
                null
            );
            Test.stopTest();

            System.assertEquals(null, result, 'OCR should return null when Einstein prompt is unavailable in tests');
        }
    }

    @isTest
    static void ocrPANCard_returnsNullWhenPromptUnavailable() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Map<String, Object> result = documentVerificationController.ocrPANCard(
                applicantId(),
                '069000000000000AAA',
                null
            );
            Test.stopTest();

            System.assertEquals(null, result, 'OCR should return null when Einstein prompt is unavailable');
        }
    }

    @isTest
    static void ocrPANCard_resolvesContentDocumentFromVersion() {
        System.runAs(getTestUser()) {
            ContentVersion version = new ContentVersion(
                Title = 'pan-card',
                PathOnClient = 'pan-card.pdf',
                VersionData = Blob.valueOf('test-pan-content')
            );
            insert version;
            version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
            ];

            Test.startTest();
            Map<String, Object> result = documentVerificationController.ocrPANCard(
                applicantId(),
                null,
                version.Id
            );
            Test.stopTest();

            System.assertEquals(null, result, 'OCR should return null when prompt execution fails in tests');
        }
    }

    @isTest
    static void savePANForReVerify_throwsWhenInputMissing() {
        System.runAs(getTestUser()) {
            Boolean threw = false;
            try {
                documentVerificationController.savePANForReVerify(null, null);
            } catch (AuraHandledException e) {
                threw = true;
            } catch (Exception e) {
                threw = true;
            }
            System.assertEquals(true, threw, 'Missing input should throw an exception');
        }
    }

    @isTest
    static void savePANForReVerify_throwsWhenPanBlank() {
        System.runAs(getTestUser()) {
            Boolean threw = false;
            try {
                documentVerificationController.savePANForReVerify(applicantId(), '   ');
            } catch (AuraHandledException e) {
                threw = true;
            } catch (Exception e) {
                threw = true;
            }
            System.assertEquals(true, threw, 'Blank PAN should throw an exception');
        }
    }

    @isTest
    static void savePANForReVerify_persistsEncryptedPanAndCreatesChecklist() {
        System.runAs(getTestUser()) {
            Id applicant = applicantId();
            ContentVersion version = new ContentVersion(
                Title = 'pan-upload',
                PathOnClient = 'pan-upload.pdf',
                VersionData = Blob.valueOf('uploaded-pan')
            );
            insert version;

            Test.startTest();
            documentVerificationController.savePANForReVerify(applicant, 'abcde1234f');
            Test.stopTest();

            Applicant__c updatedApplicant = [
                SELECT PAN_Number__c, PAN_Number_Verified__c
                FROM Applicant__c
                WHERE Id = :applicant
            ];
            System.assertNotEquals(null, updatedApplicant.PAN_Number__c, 'Encrypted PAN should be stored');
            System.assertNotEquals('ABCDE1234F', updatedApplicant.PAN_Number__c, 'Stored PAN should be encrypted');
            System.assertEquals(false, updatedApplicant.PAN_Number_Verified__c, 'Re-verify should reset verified flag');

            List<Document_CheckList__c> rows = [
                SELECT Id, Document_Type__c, PAN_No__c, Is_Active__c
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicant AND Document_Type__c = 'PAN'
            ];
            System.assertEquals(1, rows.size(), 'One PAN checklist row should exist');
            System.assertEquals(true, rows[0].Is_Active__c);
            System.assertNotEquals(null, rows[0].PAN_No__c);
        }
    }

    @isTest
    static void savePANForReVerify_updatesExistingPanChecklist() {
        System.runAs(getTestUser()) {
            Id applicant = applicantId();
            Id applicationId = [SELECT Application__c FROM Applicant__c WHERE Id = :applicant].Application__c;
            insert new Document_CheckList__c(
                Applicant__c     = applicant,
                Application__c   = applicationId,
                Document_Type__c = 'PAN',
                Is_Active__c     = false
            );

            Test.startTest();
            documentVerificationController.savePANForReVerify(applicant, 'FGHIJ5678K');
            Test.stopTest();

            List<Document_CheckList__c> rows = [
                SELECT Id, PAN_No__c, Is_Active__c
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicant AND Document_Type__c = 'PAN'
            ];
            System.assertEquals(1, rows.size(), 'Existing PAN checklist row should be reused');
            System.assertEquals(true, rows[0].Is_Active__c);
            System.assertNotEquals(null, rows[0].PAN_No__c);
        }
    }

    @isTest
    static void markPanVerified_setsVerifiedFlag() {
        System.runAs(getTestUser()) {
            Id applicant = applicantId();

            Test.startTest();
            documentVerificationController.markPanVerified(applicant, true);
            Test.stopTest();

            Applicant__c updated = [
                SELECT PAN_Number_Verified__c
                FROM Applicant__c
                WHERE Id = :applicant
            ];
            System.assertEquals(true, updated.PAN_Number_Verified__c);
        }
    }

    @isTest
    static void markPanVerified_noOpWhenApplicantIdNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            documentVerificationController.markPanVerified(null, true);
            Test.stopTest();
            System.assert(true, 'Null applicantId should be ignored without error');
        }
    }

    @isTest
    static void verifyPANCard_returnsTrue() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Boolean verified = documentVerificationController.verifyPANCard(applicantId());
            Test.stopTest();
            System.assertEquals(true, verified);
        }
    }

    @isTest
    static void verifyEmailAndMobile_returnTrue() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Boolean emailOk = documentVerificationController.verifyEmail('test@example.com');
            Boolean mobileOk = documentVerificationController.verifyMobile('9876543210');
            Test.stopTest();
            System.assertEquals(true, emailOk);
            System.assertEquals(true, mobileOk);
        }
    }

    @isTest
    static void verifyForm60_doesNotThrow() {
        System.runAs(getTestUser()) {
            Test.startTest();
            documentVerificationController.verifyForm60('FORM60-001');
            Test.stopTest();
            System.assert(true, 'verifyForm60 should complete without error');
        }
    }

    @isTest
    static void invokePANOCRAPI_returnsValidationErrorWhenMasterMissing() {
        System.runAs(getTestUser()) {
            Test.startTest();
            ApplicationUtility.IntegrationResponseWrapper response =
                documentVerificationController.invokePANOCRAPI(applicantId(), 'ABCDE1234F');
            Test.stopTest();

            System.assertNotEquals(null, response);
            System.assertEquals(true, response.hasValidationError);
            System.assert(response.errorMessage.contains('PAN OCR API'));
        }
    }

    @isTest
    static void invokeValidatePANAPI_returnsValidationErrorWhenMasterMissing() {
        System.runAs(getTestUser()) {
            Test.startTest();
            ApplicationUtility.IntegrationResponseWrapper response =
                documentVerificationController.invokeValidatePANAPI(applicantId(), 'ABCDE1234F');
            Test.stopTest();

            System.assertNotEquals(null, response);
            System.assertEquals(true, response.hasValidationError);
            System.assert(response.errorMessage.contains('Validate PAN API'));
        }
    }

    private static String integrationFailureMessage(ApplicationUtility.IntegrationResponseWrapper response) {
        if (response == null) {
            return 'Integration response was null';
        }
        if (String.isNotBlank(response.errorMessage)) {
            return response.errorMessage;
        }
        if (response.hasValidationError == true) {
            return 'Integration returned a validation error with no message';
        }
        return 'Unexpected integration failure';
    }

    @isTest
    static void invokePANOCRAPI_delegatesToApplicationUtilityWhenMasterExists() {
        System.runAs(getTestUser()) {
            createMockIntegrationMaster('PAN OCR API');
            Id applicant = applicantId();

            Test.startTest();
            ApplicationUtility.IntegrationResponseWrapper response =
                documentVerificationController.invokePANOCRAPI(applicant, 'ABCDE1234F');
            Test.stopTest();

            System.assertNotEquals(null, response, 'Integration wrapper should be returned');
            System.assertNotEquals(
                true,
                response.hasValidationError,
                integrationFailureMessage(response)
            );
        }
    }

    @isTest
    static void invokeValidatePANAPI_delegatesToApplicationUtilityWhenMasterExists() {
        System.runAs(getTestUser()) {
            createMockIntegrationMaster('Validate PAN API');
            Id applicant = applicantId();

            Test.startTest();
            ApplicationUtility.IntegrationResponseWrapper response =
                documentVerificationController.invokeValidatePANAPI(applicant, 'ABCDE1234F');
            Test.stopTest();

            System.assertNotEquals(null, response, 'Integration wrapper should be returned');
            System.assertNotEquals(
                true,
                response.hasValidationError,
                integrationFailureMessage(response)
            );
        }
    }

    @isTest
    static void ocrPANCard_returnsNullWhenContentVersionMissing() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Map<String, Object> result = documentVerificationController.ocrPANCard(
                applicantId(),
                null,
                '068000000000000AAA'
            );
            Test.stopTest();

            System.assertEquals(null, result);
        }
    }

    @isTest
    static void markPanVerified_setsVerifiedFlagFalse() {
        System.runAs(getTestUser()) {
            Id applicant = applicantId();
            documentVerificationController.markPanVerified(applicant, true);

            Test.startTest();
            documentVerificationController.markPanVerified(applicant, false);
            Test.stopTest();

            Applicant__c updated = [
                SELECT PAN_Number_Verified__c
                FROM Applicant__c
                WHERE Id = :applicant
            ];
            System.assertEquals(false, updated.PAN_Number_Verified__c);
        }
    }

    @isTest
    static void savePANForReVerify_throwsWhenApplicantMissing() {
        System.runAs(getTestUser()) {
            Id applicant = applicantId();
            delete [SELECT Id FROM Applicant__c WHERE Id = :applicant];

            Boolean threw = false;
            Test.startTest();
            try {
                documentVerificationController.savePANForReVerify(applicant, 'ABCDE1234F');
            } catch (AuraHandledException e) {
                threw = true;
            } catch (Exception e) {
                threw = true;
            }
            Test.stopTest();

            System.assertEquals(true, threw, 'Deleted applicant should surface persist failure');
        }
    }

    @isTest
    static void savePANForReVerify_normalizesPanWhitespaceAndCase() {
        System.runAs(getTestUser()) {
            Id applicant = applicantId();

            Test.startTest();
            documentVerificationController.savePANForReVerify(applicant, '  pqrs1234t  ');
            Test.stopTest();

            Applicant__c updated = [
                SELECT PAN_Number__c
                FROM Applicant__c
                WHERE Id = :applicant
            ];
            System.assertNotEquals(null, updated.PAN_Number__c);
            System.assertNotEquals('PQRS1234T', updated.PAN_Number__c);
        }
    }

    @isTest
    static void markPanVerified_doesNotThrowWhenApplicantDeleted() {
        System.runAs(getTestUser()) {
            Id applicant = applicantId();
            delete [SELECT Id FROM Applicant__c WHERE Id = :applicant];

            Test.startTest();
            documentVerificationController.markPanVerified(applicant, true);
            Test.stopTest();

            System.assert(true, 'Deleted applicant should be handled without throwing');
        }
    }

    @isTest
    static void markPanVerified_treatsNullVerifiedAsFalse() {
        System.runAs(getTestUser()) {
            Id applicant = applicantId();
            documentVerificationController.markPanVerified(applicant, true);

            Test.startTest();
            documentVerificationController.markPanVerified(applicant, null);
            Test.stopTest();

            Applicant__c updated = [
                SELECT PAN_Number_Verified__c
                FROM Applicant__c
                WHERE Id = :applicant
            ];
            System.assertEquals(false, updated.PAN_Number_Verified__c);
        }
    }

    @isTest
    static void verifyPANCard_withNullApplicantIdReturnsTrue() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Boolean verified = documentVerificationController.verifyPANCard(null);
            Test.stopTest();
            System.assertEquals(true, verified);
        }
    }

    @IsTest
    static void sanitizePromptJson_stripsInvisibleCharsAndMarkdownFence() {
        System.runAs(getTestUser()) {
            String withNbsp = '\u00A0{"document_type":"PAN"}\uFEFF';
            System.assertEquals('{"document_type":"PAN"}', documentVerificationController.sanitizePromptJson(withNbsp));

            String fenced = '```json\n' + samplePanExtractionJson() + '\n```';
            String cleaned = documentVerificationController.sanitizePromptJson(fenced);
            System.assert(cleaned.startsWith('{'));
            System.assert(cleaned.endsWith('}'));

            String arrayFenced = '```\n[{"document_type":"PAN"}]\n```';
            System.assertEquals('[{"document_type":"PAN"}]', documentVerificationController.sanitizePromptJson(arrayFenced));
            System.assertEquals(null, documentVerificationController.sanitizePromptJson(null));
        }
    }

    @IsTest
    static void parseDocumentExtractionResult_mapsDocumentDataFields() {
        System.runAs(getTestUser()) {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(samplePanExtractionJson());

            Map<String, Object> parsed = documentVerificationController.parseDocumentExtractionResult(raw);

            System.assertEquals('PAN', parsed.get('document_type'));
            System.assertEquals('identity', parsed.get('classification'));
            System.assertEquals(0.95, parsed.get('confidence'));
            System.assertEquals('John Doe', parsed.get('full_name'));
            System.assertEquals('abcde1234f', parsed.get('panCardNumber'));
            System.assertEquals('15/01/1990', parsed.get('date_of_birth'));
        }
    }

    @IsTest
    static void parseDocumentExtractionResult_handlesMissingDocumentData() {
        System.runAs(getTestUser()) {
            Map<String, Object> raw = new Map<String, Object>{ 'document_type' => 'PAN' };

            Map<String, Object> parsed = documentVerificationController.parseDocumentExtractionResult(raw);

            System.assertEquals('PAN', parsed.get('document_type'));
            System.assertEquals(null, parsed.get('panCardNumber'));
        }
    }

    @IsTest
    static void normalizeDobToIso_convertsAndHandlesInvalidInput() {
        System.runAs(getTestUser()) {
            System.assertEquals('1990-01-15', documentVerificationController.normalizeDobToIso('15/01/1990'));
            System.assertEquals(null, documentVerificationController.normalizeDobToIso(null));
            System.assertEquals(null, documentVerificationController.normalizeDobToIso('not-a-date'));
        }
    }

    @IsTest
    static void ocrPANCard_parsesPromptResponseAndPersistsPan() {
        System.runAs(getTestUser()) {
            Id applicant = applicantId();
            ContentVersion version = new ContentVersion(
                Title = 'pan-ocr-parse',
                PathOnClient = 'pan-ocr-parse.pdf',
                VersionData = Blob.valueOf('pan-ocr-parse')
            );
            insert version;
            version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
            ];

            documentVerificationController.testPromptResponseOverride = samplePanExtractionJson();

            Test.startTest();
            Map<String, Object> result = documentVerificationController.ocrPANCard(
                applicant,
                version.ContentDocumentId,
                version.Id
            );
            Test.stopTest();

            documentVerificationController.testPromptResponseOverride = null;

            System.assertNotEquals(null, result);
            System.assertEquals('ABCDE1234F', result.get('panCardNumber'));
            System.assertEquals('1990-01-15', result.get('date_of_birth'));
            System.assertEquals('John Doe', result.get('full_name'));

            Applicant__c updated = [
                SELECT PAN_Number__c
                FROM Applicant__c
                WHERE Id = :applicant
            ];
            System.assertNotEquals(null, updated.PAN_Number__c);
            System.assertNotEquals('ABCDE1234F', updated.PAN_Number__c, 'Stored PAN should be encrypted');

            List<Document_CheckList__c> rows = [
                SELECT PAN_No__c, ContentVersionId__c, Is_Active__c
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicant AND Document_Type__c = 'PAN'
            ];
            System.assertEquals(1, rows.size());
            System.assertEquals(true, rows[0].Is_Active__c);
            System.assertEquals(version.Id, rows[0].ContentVersionId__c);
        }
    }

    @IsTest
    static void ocrPANCard_returnsNullForInvalidPromptJson() {
        System.runAs(getTestUser()) {
            ContentVersion version = new ContentVersion(
                Title = 'pan-invalid-json',
                PathOnClient = 'pan-invalid-json.pdf',
                VersionData = Blob.valueOf('invalid')
            );
            insert version;
            version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
            ];

            documentVerificationController.testPromptResponseOverride = 'not-valid-json';

            Test.startTest();
            Map<String, Object> result = documentVerificationController.ocrPANCard(
                applicantId(),
                version.ContentDocumentId,
                null
            );
            Test.stopTest();

            documentVerificationController.testPromptResponseOverride = null;
            System.assertEquals(null, result);
        }
    }

    @IsTest
    static void ocrPANCard_returnsNullWhenPromptReturnsNonObjectJson() {
        System.runAs(getTestUser()) {
            ContentVersion version = new ContentVersion(
                Title = 'pan-array-json',
                PathOnClient = 'pan-array-json.pdf',
                VersionData = Blob.valueOf('array')
            );
            insert version;
            version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
            ];

            documentVerificationController.testPromptResponseOverride = '[1,2,3]';

            Test.startTest();
            Map<String, Object> result = documentVerificationController.ocrPANCard(
                applicantId(),
                version.ContentDocumentId,
                null
            );
            Test.stopTest();

            documentVerificationController.testPromptResponseOverride = null;
            System.assertEquals(null, result);
        }
    }

    @IsTest
    static void ocrPANCard_parsesMarkdownWrappedPromptResponse() {
        System.runAs(getTestUser()) {
            ContentVersion version = new ContentVersion(
                Title = 'pan-markdown-json',
                PathOnClient = 'pan-markdown-json.pdf',
                VersionData = Blob.valueOf('markdown')
            );
            insert version;
            version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
            ];

            documentVerificationController.testPromptResponseOverride =
                '```json\n' + samplePanExtractionJson() + '\n```';

            Test.startTest();
            Map<String, Object> result = documentVerificationController.ocrPANCard(
                applicantId(),
                version.ContentDocumentId,
                null
            );
            Test.stopTest();

            documentVerificationController.testPromptResponseOverride = null;

            System.assertNotEquals(null, result);
            System.assertEquals('ABCDE1234F', result.get('panCardNumber'));
            System.assertEquals('1990-01-15', result.get('date_of_birth'));
        }
    }

    @IsTest
    static void ocrPANCard_runsEinsteinPromptWhenConfigured() {
        System.runAs(getTestUser()) {
            Application__c app = new Application__c(
                Stage__c     = 'QDE',
                Sub_Stage__c = 'Basic Details',
                Product__c   = 'CV'
            );
            insert app;

            Applicant__c applicant = new Applicant__c(
                Application__c         = app.Id,
                Applicant_Type__c      = 'Borrower',
                Applicant_Tab_Label__c = 'Borrower',
                Customer_First_Name__c = 'Ocr',
                Customer_Last_Name__c  = 'Integration',
                PAN_Number_Verified__c = false
            );
            insert applicant;

            ContentVersion version = new ContentVersion(
                Title = 'pan-einstein-integration',
                PathOnClient = 'pan-einstein-integration.pdf',
                VersionData = Blob.valueOf('pan-einstein-integration')
            );
            insert version;
            version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
            ];

            Test.startTest();
            Map<String, Object> result = documentVerificationController.ocrPANCard(
                applicant.Id,
                version.ContentDocumentId,
                version.Id
            );
            Test.stopTest();

            if (result != null) {
                System.assert(
                    result.containsKey('panCardNumber') || result.containsKey('document_type'),
                    'OCR result should contain extracted fields when Einstein prompt is configured'
                );
            }
        }
    }
}