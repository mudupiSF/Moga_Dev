@IsTest
private class KYCDetailsControllerTest {

    @TestSetup
    static void setupData() {
        Application__c individualApp = new Application__c(
            Name = 'KYC Individual Test App',
            Stage__c = 'DDE',
            Sub_Stage__c = 'KYC Details',
            Product__c = '2W'
        );
        Application__c entityApp = new Application__c(
            Name = 'KYC Entity Test App',
            Stage__c = 'DDE',
            Sub_Stage__c = 'KYC Details',
            Product__c = 'CV'
        );
        insert new List<Application__c>{ individualApp, entityApp };

        insert new Applicant__c(
            Application__c = individualApp.Id,
            Applicant_Type__c = 'Borrower',
            Type__c = 'Individual',
            Customer_First_Name__c = 'Ind',
            Customer_Last_Name__c = 'Tester',
            In_Active_Applicant__c = false,
            Loan_Stage__c = 'KYC Details'
        );

        insert new Applicant__c(
            Application__c = entityApp.Id,
            Applicant_Type__c = 'Borrower',
            Type__c = 'Non-Individual',
            Entity_Type__c = '55',
            Customer_First_Name__c = 'HUF',
            Customer_Last_Name__c = 'Entity',
            In_Active_Applicant__c = false,
            Loan_Stage__c = 'KYC Details'
        );
    }

    private static Map<String, Object> call(String action, Map<String, Object> args) {
        return (Map<String, Object>) new KYCDetailsController().call(action, args);
    }

    private static Application__c individualApp() {
        return [
            SELECT Id
            FROM Application__c
            WHERE Product__c = '2W'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    private static Application__c entityApp() {
        return [
            SELECT Id
            FROM Application__c
            WHERE Product__c = 'CV'
              AND Id IN (SELECT Application__c FROM Applicant__c WHERE Type__c = 'Non-Individual')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    private static Applicant__c individualApplicant() {
        Application__c app = individualApp();
        return [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :app.Id
            LIMIT 1
        ];
    }

    private static Applicant__c entityApplicant() {
        Application__c app = entityApp();
        return [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :app.Id
            LIMIT 1
        ];
    }

    private static Map<String, Object> baseArgs(Id recordId, Id applicantId) {
        return new Map<String, Object>{
            'recordId' => recordId,
            'applicantId' => applicantId
        };
    }

    private static Document_CheckList__c insertChecklist(
        Id applicationId,
        Id applicantId,
        String documentType,
        String addressType
    ) {
        ContentVersion version = insertContentVersion();
        Document_CheckList__c row = new Document_CheckList__c(
            Applicant__c = applicantId,
            Application__c = applicationId,
            Document_Type__c = documentType,
            Address_Type__c = addressType,
            Is_Active__c = true,
            ContentVersionId__c = version.Id
        );
        insert row;
        return row;
    }

    private static String stubContentVersionId() {
        return insertContentVersion().Id;
    }

    private static String earningIncomeCategoryValue() {
        for (Schema.PicklistEntry entry : Applicant__c.Income_Category__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && !'Non-Earning'.equalsIgnoreCase(entry.getValue())) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static void markApplicantAsEarning(Id applicantId) {
        String earningCategory = earningIncomeCategoryValue();
        if (String.isBlank(earningCategory)) {
            return;
        }
        update new Applicant__c(
            Id = applicantId,
            Income_Category__c = earningCategory
        );
    }

    private static String failMessage(Object resultOrMessage) {
        return resultOrMessage == null ? 'Assertion failed.' : String.valueOf(resultOrMessage);
    }

    private static ContentVersion insertContentVersion() {
        ContentVersion version = new ContentVersion(
            Title = 'KYC Test File',
            PathOnClient = 'kyc-test.pdf',
            VersionData = Blob.valueOf('kyc-test-content')
        );
        insert version;
        return [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];
    }

    @IsTest
    static void call_unknownAction_returnsFailure() {
        Map<String, Object> result = call('notARealAction', new Map<String, Object>());
        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void getKYCInfoPageData_missingRecordId_throws() {
        Boolean thrown = false;
        try {
            call('getKYCInfoPageData', new Map<String, Object>());
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void getKYCInfoPageData_individual_success() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();

        Test.startTest();
        Map<String, Object> result = call(
            'getKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );
        Test.stopTest();

        System.assertEquals('Individual', result.get('customerType'));
    }

    @IsTest
    static void getNonIndividualKYCInfoPageData_loadsConstitutionAndValidation() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();

        Test.startTest();
        Map<String, Object> result = call(
            'getNonIndividualKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );
        Test.stopTest();

        List<String> requiredDocs = (List<String>) ((Map<String, Object>) result.get('entityKyc')).get('requiredDocuments');
        System.assert(requiredDocs.contains('List of Co-Parceners'));
    }

    @IsTest
    static void saveNonIndividualKycPageData_blocksWhenDocumentsIncomplete() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();

        Test.startTest();
        Map<String, Object> result = call('saveKYCInfoPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'gstIsRegisteredAddress' => 'Yes',
            'officeSameAsRegistered' => 'Yes',
            'gst' => new Map<String, Object>{
                'gstNumber' => '27AABCU9603R1ZM',
                'kycAddressLine1' => 'Line 1',
                'kycAddressLine2' => 'Line 2',
                'state' => 'Maharashtra',
                'district' => 'Mumbai',
                'city' => 'Mumbai',
                'kycPinCode' => '400001'
            },
            'registered' => new Map<String, Object>(),
            'office' => new Map<String, Object>(),
            'additionalDocuments' => new List<Object>()
        });
        Test.stopTest();

        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void saveNonIndividualKycPageData_succeedsWhenRequiredDocsPresent() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();

        insertChecklist(app.Id, applicant.Id, 'GST', null);
        Document_CheckList__c coParceners = insertChecklist(
            app.Id,
            applicant.Id,
            'List of Co-Parceners',
            null
        );
        insertChecklist(app.Id, applicant.Id, 'MSME Registration Certificate', null);

        Test.startTest();
        Map<String, Object> result = call('saveKYCInfoPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'gstIsRegisteredAddress' => 'Yes',
            'officeSameAsRegistered' => 'Yes',
            'gst' => new Map<String, Object>{
                'gstNumber' => '27AABCU9603R1ZM',
                'kycAddressLine1' => 'Line 1',
                'kycAddressLine2' => 'Line 2',
                'state' => 'Maharashtra',
                'district' => 'Mumbai',
                'city' => 'Mumbai',
                'kycPinCode' => '400001'
            },
            'registered' => new Map<String, Object>(),
            'office' => new Map<String, Object>(),
            'additionalDocuments' => new List<Object>{
                new Map<String, Object>{
                    'documentType' => 'List of Co-Parceners',
                    'checklistRecordId' => coParceners.Id,
                    'proofFile' => new Map<String, Object>{
                        'contentVersionId' => stubContentVersionId()
                    }
                }
            }
        });
        Test.stopTest();

        System.assertEquals('KYC Details', [
            SELECT Current_Loan_Stage_Complete__c
            FROM Applicant__c
            WHERE Id = :applicant.Id
        ].Current_Loan_Stage_Complete__c);
    }

    @IsTest
    static void createEntityChecklists_createRows() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();
        Map<String, Object> args = baseArgs(app.Id, applicant.Id);

        Test.startTest();
        call('createCinChecklist', args);
        call('createGstChecklist', args);
        call('createRegisteredAddressChecklist', args);
        call('createEntityOfficeAddressChecklist', args);
        Test.stopTest();

        System.assertEquals(
            4,
            [SELECT COUNT() FROM Document_CheckList__c WHERE Applicant__c = :applicant.Id]
        );
    }

    @IsTest
    static void stampEntityAddressChecklist_stampsRegisteredBucketAndReloadsProof() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();
        Document_CheckList__c uploadRow = insertChecklist(
            app.Id,
            applicant.Id,
            'Electricity Bill (within 2 months)',
            null
        );

        Test.startTest();
        Map<String, Object> stampResult = call('stampEntityAddressChecklist', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'checklistRecordId' => uploadRow.Id,
            'addressType' => 'Registered Address',
            'addressProof' => 'Electricity Bill (within 2 months)'
        });
        Map<String, Object> loadResult = call(
            'getNonIndividualKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );
        Test.stopTest();

        System.assertEquals(true, stampResult.get('isSuccess'));
        uploadRow = [
            SELECT Address_Type__c, Is_Active__c
            FROM Document_CheckList__c
            WHERE Id = :uploadRow.Id
        ];
        System.assertEquals('Registered Address', uploadRow.Address_Type__c);
        System.assertEquals(true, uploadRow.Is_Active__c);

        Map<String, Object> entityKyc = (Map<String, Object>) loadResult.get('entityKyc');
        System.assertEquals(uploadRow.Id, entityKyc.get('registeredChecklistRecordId'));
        Map<String, Object> registeredAddress = (Map<String, Object>) entityKyc.get('registeredAddress');
        System.assertNotEquals(null, registeredAddress);
        System.assertNotEquals(null, registeredAddress.get('proofFile'));
    }

    @IsTest
    static void deleteCurrentAddressKycFile_inactivatesEntityRegisteredProofChecklist() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();
        Document_CheckList__c row = insertChecklist(
            app.Id,
            applicant.Id,
            'Electricity Bill (within 2 months)',
            'Registered Address'
        );

        ContentVersion version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :row.ContentVersionId__c
            LIMIT 1
        ];
        insert new ContentDocumentLink(
            LinkedEntityId = row.Id,
            ContentDocumentId = version.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Test.startTest();
        Map<String, Object> deleteResult = call('deleteCurrentAddressKycFile', new Map<String, Object>{
            'checklistRecordId' => row.Id,
            'contentDocumentId' => version.ContentDocumentId
        });
        Test.stopTest();

        System.assertEquals(true, deleteResult.get('isSuccess'));
        row = [
            SELECT Is_Active__c, ContentVersionId__c
            FROM Document_CheckList__c
            WHERE Id = :row.Id
        ];
        System.assertEquals(false, row.Is_Active__c);
        System.assertEquals(null, row.ContentVersionId__c);
    }

    @IsTest
    static void getEntityDocumentMasterConfig_usesFallbackWhenMasterMissing() {
        Test.startTest();
        Map<String, Object> result = call('getEntityDocumentMasterConfig', new Map<String, Object>{
            'documentName' => 'Board Resolution',
            'documentCategory' => 'KYC - Entity Additional Document'
        });
        Test.stopTest();

        System.assertEquals(true, result.get('fromFallback'));
    }

    @IsTest
    static void getEntityDocumentMasterConfig_missingParams_throws() {
        Boolean thrown = false;
        try {
            call('getEntityDocumentMasterConfig', new Map<String, Object>());
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void saveNonIndividualKycDoc_persistsCinAndGstNumbers() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();
        Document_CheckList__c cinRow = insertChecklist(app.Id, applicant.Id, 'CIN', null);

        Test.startTest();
        call('saveNonIndividualKycDoc', new Map<String, Object>{
            'applicantId' => applicant.Id,
            'docType' => 'CIN',
            'kycNumber' => 'U72900TN2008PTC069413',
            'checklistRecordId' => cinRow.Id
        });
        call('saveNonIndividualKycDoc', new Map<String, Object>{
            'applicantId' => applicant.Id,
            'docType' => 'GST',
            'kycNumber' => '27AABCU9603R1ZM',
            'kycState' => 'Maharashtra',
            'checklistRecordId' => insertChecklist(app.Id, applicant.Id, 'GST', null).Id
        });
        Test.stopTest();

        System.assertEquals(
            'U72900TN2008PTC069413',
            [
                SELECT Applicant_KYC__r.KYC_No__c
                FROM Document_CheckList__c
                WHERE Id = :cinRow.Id
            ].Applicant_KYC__r.KYC_No__c
        );
    }

    @IsTest
    static void resolveContentDocumentId_returnsDocumentId() {
        ContentVersion version = insertContentVersion();

        Test.startTest();
        Map<String, Object> result = call('resolveContentDocumentId', new Map<String, Object>{
            'contentVersionId' => version.Id
        });
        Test.stopTest();

        System.assertEquals(version.ContentDocumentId, result.get('contentDocumentId'));
    }

    @IsTest
    static void createCurrentAddressChecklist_createsRow() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();

        Test.startTest();
        call('createCurrentAddressChecklist', baseArgs(app.Id, applicant.Id));
        Test.stopTest();

        System.assertNotEquals(
            0,
            [
                SELECT COUNT()
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicant.Id
                  AND Address_Type__c = 'Current Residential Address'
            ]
        );
    }

    @IsTest
    static void getIntegrationMaster_missingName_returnsFailure() {
        Map<String, Object> result = call('getIntegrationMaster', new Map<String, Object>());
        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void getNonIndividualPageDataViaIndividualAction_routesCorrectly() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();

        Map<String, Object> result = call(
            'getKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        System.assertEquals('Non-Individual', result.get('customerType'));
    }

    @IsTest
    static void individualSavePageData_marksStageComplete() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();

        Test.startTest();
        Map<String, Object> result = call('saveKYCInfoPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'isCurrentAddrSameAsPermanent' => 'Yes',
            'isOfficeAddrSameAsCurrent' => 'Yes'
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), failMessage(result));
    }

    @IsTest
    static void createPermanentAndOfficeChecklists_success() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();
        markApplicantAsEarning(applicant.Id);
        Map<String, Object> args = baseArgs(app.Id, applicant.Id);

        Test.startTest();
        call('createPermanentAddressChecklist', args);
        Map<String, Object> officeResult = call('createOfficeAddressChecklist', args);
        Test.stopTest();

        System.assertEquals(true, officeResult.get('isSuccess'));
    }

    @IsTest
    static void deleteCurrentAddressKycFile_removesLinkedFile() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();
        ContentVersion version = insertContentVersion();

        Document_CheckList__c row = new Document_CheckList__c(
            Applicant__c = applicant.Id,
            Application__c = app.Id,
            Document_Type__c = 'Current Address Proof',
            Address_Type__c = 'Current Residential Address',
            Is_Active__c = true,
            ContentVersionId__c = version.Id
        );
        insert row;
        insert new ContentDocumentLink(
            ContentDocumentId = version.ContentDocumentId,
            LinkedEntityId = row.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Test.startTest();
        Map<String, Object> result = call('deleteCurrentAddressKycFile', new Map<String, Object>{
            'checklistRecordId' => row.Id,
            'contentDocumentId' => version.ContentDocumentId
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void saveNonIndividual_registeredAddressPath() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();

        insertChecklist(app.Id, applicant.Id, 'GST', null);
        insertChecklist(app.Id, applicant.Id, 'List of Co-Parceners', null);
        insertChecklist(app.Id, applicant.Id, 'MSME Registration Certificate', null);
        insertChecklist(
            app.Id,
            applicant.Id,
            'Electricity Bill (within 2 months)',
            'Registered Address'
        );

        Test.startTest();
        Map<String, Object> result = call('saveKYCInfoPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'gstIsRegisteredAddress' => 'No',
            'officeSameAsRegistered' => 'Yes',
            'gst' => new Map<String, Object>{
                'gstNumber' => '27AABCU9603R1ZM',
                'kycAddressLine1' => 'GST Line 1',
                'kycAddressLine2' => 'GST Line 2',
                'state' => 'Maharashtra',
                'district' => 'Mumbai',
                'city' => 'Mumbai',
                'kycPinCode' => '400001'
            },
            'registered' => new Map<String, Object>{
                'addressProof' => 'Electricity Bill (within 2 months)',
                'kycAddressLine1' => 'Reg Line 1',
                'kycAddressLine2' => 'Reg Line 2',
                'state' => 'Maharashtra',
                'district' => 'Mumbai',
                'city' => 'Mumbai',
                'kycPinCode' => '400002',
                'proofFile' => new Map<String, Object>{ 'contentVersionId' => stubContentVersionId() }
            },
            'office' => new Map<String, Object>(),
            'additionalDocuments' => new List<Object>()
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), failMessage(result));

        Applicant_Address__c registeredAddr = [
            SELECT Address_Proof__c
            FROM Applicant_Address__c
            WHERE Applicant__c = :applicant.Id
              AND Address_Type__c = 'Registered Address'
            LIMIT 1
        ];
        System.assertEquals(true, registeredAddr.Address_Proof__c);
    }

    @IsTest
    static void entityPageLoad_hydratesUploadedRows() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();

        insertChecklist(app.Id, applicant.Id, 'CIN', null);
        insertChecklist(app.Id, applicant.Id, 'GST', null);
        insertChecklist(app.Id, applicant.Id, 'MSME Registration Certificate', null);

        Map<String, Object> result = call(
            'getNonIndividualKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );
        List<Object> additionalDocs = (List<Object>) ((Map<String, Object>) result.get('entityKyc')).get('additionalDocuments');

        System.assert(!additionalDocs.isEmpty());
    }

    @IsTest
    static void individualSavePageData_withPermanentSection() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();

        Test.startTest();
        Map<String, Object> result = call('saveKYCInfoPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'isCurrentAddrSameAsPermanent' => 'No',
            'isOfficeAddrSameAsCurrent' => 'Yes',
            'permanent' => new Map<String, Object>{
                'addressProof' => 'Passport',
                'kycAddressLine1' => 'Perm Line 1',
                'kycAddressLine2' => 'Perm Line 2',
                'state' => 'Maharashtra',
                'district' => 'Mumbai',
                'city' => 'Mumbai',
                'kycPinCode' => '400001'
            }
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), failMessage(result));
    }

    @IsTest
    static void saveNonIndividual_officeAddressPath() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();

        insertChecklist(app.Id, applicant.Id, 'GST', null);
        insertChecklist(app.Id, applicant.Id, 'List of Co-Parceners', null);
        insertChecklist(app.Id, applicant.Id, 'MSME Registration Certificate', null);
        insertChecklist(
            app.Id,
            applicant.Id,
            'Electricity Bill (within 2 months)',
            'Registered Address'
        );
        insertChecklist(
            app.Id,
            applicant.Id,
            'Electricity Bill (within 2 months)',
            'Office Address'
        );

        Test.startTest();
        Map<String, Object> result = call('saveKYCInfoPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'gstIsRegisteredAddress' => 'No',
            'officeSameAsRegistered' => 'No',
            'gst' => new Map<String, Object>{
                'gstNumber' => '27AABCU9603R1ZM',
                'kycAddressLine1' => 'GST Line 1',
                'kycAddressLine2' => 'GST Line 2',
                'state' => 'Maharashtra',
                'district' => 'Mumbai',
                'city' => 'Mumbai',
                'kycPinCode' => '400001'
            },
            'registered' => new Map<String, Object>{
                'addressProof' => 'Electricity Bill (within 2 months)',
                'kycAddressLine1' => 'Reg Line 1',
                'kycAddressLine2' => 'Reg Line 2',
                'state' => 'Maharashtra',
                'district' => 'Mumbai',
                'city' => 'Mumbai',
                'kycPinCode' => '400002'
            },
            'office' => new Map<String, Object>{
                'addressProof' => 'Electricity Bill (within 2 months)',
                'kycAddressLine1' => 'Office Line 1',
                'kycAddressLine2' => 'Office Line 2',
                'state' => 'Maharashtra',
                'district' => 'Mumbai',
                'city' => 'Mumbai',
                'kycPinCode' => '400003'
            },
            'additionalDocuments' => new List<Object>()
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), failMessage(result));
    }

    @IsTest
    static void getIntegrationMaster_returnsRecordWhenConfigured() {
        List<Integration_Master__c> masters = [
            SELECT Name
            FROM Integration_Master__c
            WHERE Name = 'PAN TO CIN'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (masters.isEmpty()) {
            return;
        }

        Map<String, Object> result = call('getIntegrationMaster', new Map<String, Object>{
            'integrationName' => 'PAN TO CIN'
        });
        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void getNonIndividual_pvtLtdEntity_setsCinRequired() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();
        applicant.Entity_Type__c = '11';
        update applicant;

        Map<String, Object> result = call(
            'getNonIndividualKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        System.assertEquals(true, ((Map<String, Object>) result.get('entityKyc')).get('cinRequired'));
    }

    @IsTest
    static void getNonIndividual_4wProduct_usesPvConstitution() {
        Application__c app = new Application__c(
            Name = 'KYC Entity 4W Test App',
            Stage__c = 'DDE',
            Sub_Stage__c = 'KYC Details',
            Product__c = '4W'
        );
        insert app;

        Applicant__c applicant = new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower',
            Type__c = 'Non-Individual',
            Entity_Type__c = '50',
            Customer_First_Name__c = 'Trust',
            Customer_Last_Name__c = 'Entity',
            In_Active_Applicant__c = false,
            Loan_Stage__c = 'KYC Details'
        );
        insert applicant;

        Map<String, Object> result = call(
            'getNonIndividualKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );
        Map<String, Object> entityKyc = (Map<String, Object>) result.get('entityKyc');

        System.assertEquals(true, result.get('isSuccess'));
        System.assertEquals(true, entityKyc.get('gstRequired'));
        System.assertEquals(false, entityKyc.get('cinRequired'));
    }

    @IsTest
    static void saveNonIndividualKycDoc_invalidDocType_throws() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();
        Boolean thrown = false;
        try {
            call('saveNonIndividualKycDoc', new Map<String, Object>{
                'applicantId' => applicant.Id,
                'docType' => 'PAN',
                'kycNumber' => 'ABCDE1234F'
            });
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void resolveContentDocumentId_missingParam_throws() {
        Boolean thrown = false;
        try {
            call('resolveContentDocumentId', new Map<String, Object>());
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void createCinChecklist_secondCallReusesRow() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();
        Map<String, Object> args = baseArgs(app.Id, applicant.Id);

        Map<String, Object> first = call('createCinChecklist', args);
        Map<String, Object> second = call('createCinChecklist', args);

        System.assertEquals(first.get('checklistId'), second.get('checklistId'));
    }

    @IsTest
    static void individualPageLoad_withExistingCurrentRow() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();
        insertChecklist(
            app.Id,
            applicant.Id,
            'Current Address Proof',
            'Current Residential Address'
        );

        Map<String, Object> result = call(
            'getKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        System.assertNotEquals(null, result.get('kycInfoFileUploadRecordId'));
    }

    @IsTest
    static void individualPageLoad_withoutCurrentRow_keepsChecklistIdNull() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();

        Map<String, Object> result = call(
            'getKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        Integer currentRows = [
            SELECT count()
            FROM Document_CheckList__c
            WHERE Applicant__c = :applicant.Id
              AND Address_Type__c = 'Current Residential Address'
        ];
        System.assertEquals(null, result.get('kycInfoFileUploadRecordId'));
        System.assertEquals(0, currentRows);
    }

    @IsTest
    static void individualPageLoad_officeRequiredForEarningApplicant() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();
        markApplicantAsEarning(applicant.Id);

        Map<String, Object> result = call(
            'getKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        System.assertEquals(true, result.get('officeAddressRequired'));
    }

    @IsTest
    static void individualPageLoad_stageCompleteSetsReadOnly() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();
        applicant.Current_Loan_Stage_Complete__c = 'KYC Details';
        update applicant;

        Map<String, Object> result = call(
            'getKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        System.assertEquals(true, result.get('extractedDetailsIsReadOnly'));
    }

    @IsTest
    static void individualSave_withOfficeAddressSection() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();
        markApplicantAsEarning(applicant.Id);

        Test.startTest();
        Map<String, Object> result = call('saveKYCInfoPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'isCurrentAddrSameAsPermanent' => 'Yes',
            'isOfficeAddrSameAsCurrent' => 'No',
            'officeAddress' => new Map<String, Object>{
                'addressProof' => 'Passport',
                'kycAddressLine1' => 'Office Line 1',
                'kycAddressLine2' => 'Office Line 2',
                'state' => 'Maharashtra',
                'district' => 'Mumbai',
                'city' => 'Mumbai',
                'kycPinCode' => '400003'
            }
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), failMessage(result));
    }

    @IsTest
    static void individualSave_withApplicantAnswerFields() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();

        Test.startTest();
        call('saveKYCInfoPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'isCurrentAddrSameAsPermanent' => 'Yes',
            'isOfficeAddrSameAsCurrent' => 'Yes',
            'isDirectorDeclaration' => 'No',
            'isSeniorOfficerRelative' => 'No',
            'isPep' => 'No',
            'isBankAccountCheck' => 'Yes',
            'isOpenSavingsAccount' => 'No',
            'bankAccountNo' => '1234567890'
        });
        Test.stopTest();

        System.assertEquals(
            '1234567890',
            [SELECT Bank_Account_No__c FROM Applicant__c WHERE Id = :applicant.Id].Bank_Account_No__c
        );
    }

    @IsTest
    static void individualPageLoad_withCustomerImageRow() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();
        insertChecklist(app.Id, applicant.Id, 'Customer Image', null);

        Map<String, Object> result = call(
            'getKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        System.assertNotEquals(null, result.get('customerImageCapture'));
    }

    @IsTest
    static void deleteCurrentAddressKycFile_missingChecklistId_throws() {
        Boolean thrown = false;
        try {
            call('deleteCurrentAddressKycFile', new Map<String, Object>());
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void individualPageLoad_withAddressBucketsAndExtractedDetails() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();
        markApplicantAsEarning(applicant.Id);

        Applicant_KYC__c kyc = new Applicant_KYC__c(
            Applicant__c = applicant.Id,
            KYC_name__c = 'TEST USER',
            Masked_KYC_No__c = 'ABCD1234',
            KYC_Address_Line_1__c = 'KYC Line 1'
        );
        insert kyc;

        Applicant_Address__c currentAddr = new Applicant_Address__c(
            Applicant__c = applicant.Id,
            Address_Type__c = 'Current Residential Address',
            Address_Line_1__c = 'Current Line 1',
            Is_Current_Address_Same_As_Permanent__c = 'No',
            Is_Office_Address_Same_As_Current__c = 'Yes'
        );
        insert currentAddr;

        Applicant_Address__c officeAddr = new Applicant_Address__c(
            Applicant__c = applicant.Id,
            Address_Type__c = 'Office Address',
            Address_Line_1__c = 'Office Line 1',
            Email__c = 'test@example.com',
            Email_Verified__c = true
        );
        insert officeAddr;

        insert new Document_CheckList__c(
            Applicant__c = applicant.Id,
            Application__c = app.Id,
            Document_Type__c = 'Current Address Proof',
            Address_Type__c = 'Current Residential Address',
            Applicant_KYC__c = kyc.Id,
            Applicant_Address__c = currentAddr.Id,
            First_Name__c = 'Test',
            Last_Name__c = 'User',
            Is_Active__c = true
        );
        insert new Document_CheckList__c(
            Applicant__c = applicant.Id,
            Application__c = app.Id,
            Document_Type__c = 'Permanent Address Proof',
            Address_Type__c = 'Permanent Residential Address',
            Applicant_KYC__c = kyc.Id,
            Is_Active__c = true
        );
        insert new Document_CheckList__c(
            Applicant__c = applicant.Id,
            Application__c = app.Id,
            Document_Type__c = 'Office Address Proof',
            Address_Type__c = 'Office Address',
            Applicant_Address__c = officeAddr.Id,
            Is_Active__c = true
        );

        Map<String, Object> result = call(
            'getKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        System.assertNotEquals(null, result.get('extractedDetails'));
    }

    @IsTest
    static void individualSave_clearsPermanentBucketWhenSameAsCurrentYes() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();
        insertChecklist(
            app.Id,
            applicant.Id,
            'Permanent Address Proof',
            'Permanent Residential Address'
        );

        Test.startTest();
        call('saveKYCInfoPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'isCurrentAddrSameAsPermanent' => 'Yes',
            'isOfficeAddrSameAsCurrent' => 'Yes'
        });
        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicant.Id
                  AND Address_Type__c = 'Permanent Residential Address'
            ]
        );
    }

    @IsTest
    static void getNonIndividualKYCInfoPageData_missingRecordId_throws() {
        Boolean thrown = false;
        try {
            call('getNonIndividualKYCInfoPageData', new Map<String, Object>());
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void individualPageLoad_nonEarningApplicantOfficeNotRequired() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();
        update new Applicant__c(
            Id = applicant.Id,
            Income_Category__c = 'Non-Earning'
        );

        Map<String, Object> result = call(
            'getKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        System.assertEquals(false, result.get('officeAddressRequired'));
    }

    @IsTest
    static void entityPageLoad_hydratesRegisteredAndOfficeAddresses() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();

        Applicant_Address__c registeredAddr = new Applicant_Address__c(
            Applicant__c = applicant.Id,
            Address_Type__c = 'Registered Address',
            Address_Line_1__c = 'Registered Line 1',
            Address_Line_2__c = 'Registered Line 2',
            State__c = 'Maharashtra',
            District__c = 'Mumbai',
            City__c = 'Mumbai',
            PinCode__c = '400001'
        );
        Applicant_Address__c officeAddr = new Applicant_Address__c(
            Applicant__c = applicant.Id,
            Address_Type__c = 'Office Address',
            Address_Line_1__c = 'Office Line 1',
            Address_Line_2__c = 'Office Line 2',
            State__c = 'Maharashtra',
            District__c = 'Mumbai',
            City__c = 'Mumbai',
            PinCode__c = '400002'
        );
        insert new List<Applicant_Address__c>{ registeredAddr, officeAddr };

        ContentVersion version = insertContentVersion();
        insert new Document_CheckList__c(
            Applicant__c = applicant.Id,
            Application__c = app.Id,
            Document_Type__c = 'Electricity Bill (within 2 months)',
            Address_Type__c = 'Registered Address',
            Applicant_Address__c = registeredAddr.Id,
            ContentVersionId__c = version.Id,
            Is_Active__c = true
        );
        insert new Document_CheckList__c(
            Applicant__c = applicant.Id,
            Application__c = app.Id,
            Document_Type__c = 'Electricity Bill (within 2 months)',
            Address_Type__c = 'Office Address',
            Applicant_Address__c = officeAddr.Id,
            ContentVersionId__c = version.Id,
            Is_Active__c = true
        );

        Map<String, Object> result = call(
            'getNonIndividualKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        System.assertNotEquals(
            null,
            ((Map<String, Object>) result.get('entityKyc')).get('registeredAddress')
        );
    }

    @IsTest
    static void entityValidation_cinRequiredWhenFileWithoutNumber() {
        Application__c app = entityApp();
        Applicant__c applicant = entityApplicant();
        applicant.Entity_Type__c = '11';
        update applicant;

        insertChecklist(app.Id, applicant.Id, 'CIN', null);
        insertChecklist(app.Id, applicant.Id, 'GST', null);

        Map<String, Object> result = call(
            'getNonIndividualKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );
        List<String> missing = (List<String>) ((Map<String, Object>) result.get('entityKyc')).get('missingRequiredDocuments');

        System.assert(missing.contains('CIN Certificate'));
    }

    @IsTest
    static void individualPageLoad_aadhaarVerifyStateFromKyc() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();

        Applicant_KYC__c kyc = new Applicant_KYC__c(
            Applicant__c = applicant.Id,
            KYC_URL__c = 'https://example.com/aadhaar',
            Aadhar_Verified__c = true,
            AadhaarConsentReceived__c = System.now(),
            KYC_Verification_Method__c = 'eKYC OTP Verification'
        );
        insert kyc;

        insert new Document_CheckList__c(
            Applicant__c = applicant.Id,
            Application__c = app.Id,
            Document_Type__c = 'Current Address Proof',
            Address_Type__c = 'Current Residential Address',
            Applicant_KYC__c = kyc.Id,
            Is_Active__c = true
        );

        Map<String, Object> result = call(
            'getKYCInfoPageData',
            baseArgs(app.Id, applicant.Id)
        );

        System.assertEquals(
            true,
            ((Map<String, Object>) result.get('aadhaarVerifyState')).get('aadhaarVerified')
        );
    }

    @IsTest
    static void individualSave_withCurrentAddressFields() {
        Application__c app = individualApp();
        Applicant__c applicant = individualApplicant();

        Test.startTest();
        Map<String, Object> result = call('saveKYCInfoPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id,
            'isCurrentAddrSameAsPermanent' => 'Yes',
            'isOfficeAddrSameAsCurrent' => 'Yes',
            'addressProof' => 'Passport',
            'kycAddressLine1' => 'Current Line 1',
            'kycAddressLine2' => 'Current Line 2',
            'state' => 'Maharashtra',
            'district' => 'Mumbai',
            'city' => 'Mumbai',
            'kycPinCode' => '400001'
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), failMessage(result));
    }
}