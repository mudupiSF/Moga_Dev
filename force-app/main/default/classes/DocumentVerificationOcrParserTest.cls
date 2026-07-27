@IsTest
private class DocumentVerificationOcrParserTest {

    private static String samplePanJson() {
        return '{"document_type":"PAN","classification":"identity","confidence":0.95,'
            + '"metadata":{"source":"einstein"},'
            + '"document_data":{"full_name":"John Doe","father_name":"Richard Doe",'
            + '"document_number":"abcde1234f","date_of_birth":"15/01/1990",'
            + '"issuing_authority":"Income Tax Department"}}';
    }

    @IsTest
    static void sanitizePromptJson_returnsBlankUnchanged() {
        System.assertEquals(null, DocumentVerificationOcrParser.sanitizePromptJson(null));
        System.assertEquals('', DocumentVerificationOcrParser.sanitizePromptJson(''));
    }

    @IsTest
    static void sanitizePromptJson_stripsInvisibleUnicode() {
        String withNbsp = '\u00A0{"document_type":"PAN"}\uFEFF';
        String cleaned = DocumentVerificationOcrParser.sanitizePromptJson(withNbsp);
        System.assertEquals('{"document_type":"PAN"}', cleaned);
    }

    @IsTest
    static void sanitizePromptJson_extractsJsonFromMarkdownFence() {
        String fenced = '```json\n' + samplePanJson() + '\n```';
        String cleaned = DocumentVerificationOcrParser.sanitizePromptJson(fenced);
        System.assert(cleaned.startsWith('{'), 'Fenced object JSON should be extracted');
        System.assert(cleaned.endsWith('}'));
    }

    @IsTest
    static void sanitizePromptJson_extractsArrayFromMarkdownFence() {
        String fenced = '```\n[{"document_type":"PAN"}]\n```';
        String cleaned = DocumentVerificationOcrParser.sanitizePromptJson(fenced);
        System.assertEquals('[{"document_type":"PAN"}]', cleaned);
    }

    @IsTest
    static void parseDocumentExtractionResult_mapsDocumentDataFields() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(samplePanJson());

        Test.startTest();
        Map<String, Object> parsed = DocumentVerificationOcrParser.parseDocumentExtractionResult(raw);
        Test.stopTest();

        System.assertEquals('PAN', parsed.get('document_type'));
        System.assertEquals('identity', parsed.get('classification'));
        System.assertEquals(0.95, parsed.get('confidence'));
        System.assertNotEquals(null, parsed.get('metadata'));
        System.assertEquals('John Doe', parsed.get('full_name'));
        System.assertEquals('Richard Doe', parsed.get('father_name'));
        System.assertEquals('abcde1234f', parsed.get('panCardNumber'));
        System.assertEquals('15/01/1990', parsed.get('date_of_birth'));
        System.assertEquals('Income Tax Department', parsed.get('issuing_authority'));
    }

    @IsTest
    static void parseDocumentExtractionResult_handlesMissingDocumentData() {
        Map<String, Object> raw = new Map<String, Object>{
            'document_type' => 'PAN',
            'classification' => 'identity'
        };

        Map<String, Object> parsed = DocumentVerificationOcrParser.parseDocumentExtractionResult(raw);

        System.assertEquals('PAN', parsed.get('document_type'));
        System.assertEquals(null, parsed.get('panCardNumber'));
        System.assertEquals(null, parsed.get('full_name'));
    }

    @IsTest
    static void normalizeDobToIso_convertsDdMmYyyy() {
        String iso = DocumentVerificationOcrParser.normalizeDobToIso('15/01/1990');
        System.assertEquals('1990-01-15', iso);
    }

    @IsTest
    static void normalizeDobToIso_returnsNullForBlankOrInvalid() {
        System.assertEquals(null, DocumentVerificationOcrParser.normalizeDobToIso(null));
        System.assertEquals(null, DocumentVerificationOcrParser.normalizeDobToIso(''));
        System.assertEquals(null, DocumentVerificationOcrParser.normalizeDobToIso('not-a-date'));
    }

    @IsTest
    static void buildResultFromPromptText_returnsNullForBlankInput() {
        System.assertEquals(null, DocumentVerificationOcrParser.buildResultFromPromptText(null));
        System.assertEquals(null, DocumentVerificationOcrParser.buildResultFromPromptText(''));
    }

    @IsTest
    static void buildResultFromPromptText_returnsNullForInvalidJson() {
        System.assertEquals(null, DocumentVerificationOcrParser.buildResultFromPromptText('not-json'));
    }

    @IsTest
    static void buildResultFromPromptText_returnsNullForNonObjectJson() {
        System.assertEquals(null, DocumentVerificationOcrParser.buildResultFromPromptText('[1,2,3]'));
    }

    @IsTest
    static void buildResultFromPromptText_parsesPlainJsonAndNormalizesFields() {
        Test.startTest();
        Map<String, Object> result = DocumentVerificationOcrParser.buildResultFromPromptText(samplePanJson());
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('ABCDE1234F', result.get('panCardNumber'));
        System.assertEquals('1990-01-15', result.get('date_of_birth'));
        System.assertEquals('John Doe', result.get('full_name'));
    }

    @IsTest
    static void buildResultFromPromptText_parsesMarkdownWrappedJson() {
        String fenced = '```json\n' + samplePanJson() + '\n```';

        Map<String, Object> result = DocumentVerificationOcrParser.buildResultFromPromptText(fenced);

        System.assertNotEquals(null, result);
        System.assertEquals('ABCDE1234F', result.get('panCardNumber'));
        System.assertEquals('1990-01-15', result.get('date_of_birth'));
    }

    @IsTest
    static void buildResultFromPromptText_handlesMissingPanAndDob() {
        String json = '{"document_type":"PAN","document_data":{"full_name":"Jane"}}';

        Map<String, Object> result = DocumentVerificationOcrParser.buildResultFromPromptText(json);

        System.assertNotEquals(null, result);
        System.assertEquals(null, result.get('panCardNumber'));
        System.assertEquals('Jane', result.get('full_name'));
    }
}