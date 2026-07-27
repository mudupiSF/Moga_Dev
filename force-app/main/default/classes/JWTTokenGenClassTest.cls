/*
* Created By : Ajay Bharathan
* Purpose : Test class for JWTTokenGenClass
*/
@isTest
public class JWTTokenGenClassTest {
    
    /*
    * @Method: testFetchToken_Success
    * @Description: Tests successful JWT token generation with valid persona
    */
    @isTest
    static void testFetchToken_Success() {
        // Set up mock HTTP response
        Test.setMock(HttpCalloutMock.class, new JWTTokenSuccessMock());

        Test.startTest();
        JWTTokenResponseWrapper result = JWTTokenGenClass.fetchToken('Ajay');
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.jwtSignedAndVerified, 'JWT should be signed and verified');
        System.assertNotEquals(null, result.jwtToken, 'JWT Token should not be null');
        System.assertEquals(null, result.sfErrMsg, 'Error message should be null');
    }
    
    /*
    * @Method: testFetchToken_BlankPersona
    * @Description: Tests JWT token generation with blank persona name
    */
    @isTest
    static void testFetchToken_BlankPersona() {
        Test.startTest();
        JWTTokenResponseWrapper result = JWTTokenGenClass.fetchToken('');
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Please fill in Persona Name', result.sfErrMsg, 'Should show error for blank persona');
        System.assertEquals(false, result.jwtSignedAndVerified, 'JWT should not be verified');
    }
    
    /*
    * @Method: testFetchToken_NullPersona
    * @Description: Tests JWT token generation with null persona name
    */
    @isTest
    static void testFetchToken_NullPersona() {
        Test.startTest();
        JWTTokenResponseWrapper result = JWTTokenGenClass.fetchToken(null);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Please fill in Persona Name', result.sfErrMsg, 'Should show error for null persona');
        System.assertEquals(false, result.jwtSignedAndVerified, 'JWT should not be verified');
    }
    
    /*
    * @Method: testFetchToken_InvalidPersona
    * @Description: Tests JWT token generation with invalid persona name
    */
    @isTest
    static void testFetchToken_InvalidPersona() {
        Test.startTest();
        JWTTokenResponseWrapper result = JWTTokenGenClass.fetchToken('InvalidPersona');
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Persona is invalid/does not exist', result.sfErrMsg, 'Should show error for invalid persona');
        System.assertEquals(false, result.jwtSignedAndVerified, 'JWT should not be verified');
    }
    
    /*
    * @Method: testFetchToken_HTTPError
    * @Description: Tests JWT token generation with HTTP error response
    */
    @isTest
    static void testFetchToken_HTTPError() {
        // Set up mock HTTP error response
        Test.setMock(HttpCalloutMock.class, new JWTTokenErrorMock());

        Test.startTest();
        JWTTokenResponseWrapper result = JWTTokenGenClass.fetchToken('Ajay');
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.jwtToken, 'JWT Token should be generated');
    }
    
    
    /*
    * @Method: testBase64URLSafeEncode
    * @Description: Tests base64 URL safe encoding
    */
    @isTest
    static void testBase64URLSafeEncode() {
        String testString = 'Test String for Encoding';
        Blob testBlob = Blob.valueOf(testString);
        
        Test.startTest();
        String encoded = JWTTokenGenClass.base64URLSafeEncode(testBlob);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, encoded, 'Encoded string should not be null');
        System.assert(!encoded.contains('+'), 'Encoded string should not contain +');
        System.assert(!encoded.contains('/'), 'Encoded string should not contain /');
        System.assert(!encoded.contains('='), 'Encoded string should not contain =');
    }
    
    /*
    * @Method: testBase64URLSafeDecode
    * @Description: Tests base64 URL safe decoding
    */
    @isTest
    static void testBase64URLSafeDecode() {
        String testString = 'Test String for Decoding';
        Blob testBlob = Blob.valueOf(testString);
        
        // First encode
        String encoded = JWTTokenGenClass.base64URLSafeEncode(testBlob);
        
        Test.startTest();
        Blob decoded = JWTTokenGenClass.base64URLSafeDecode(encoded);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, decoded, 'Decoded blob should not be null');
        System.assertEquals(testString, decoded.toString(), 'Decoded string should match original');
    }
    
    /*
    * @Method: testEncryptJSON_Success
    * @Description: Tests successful JSON encryption without comments
    */
    @isTest
    static void testEncryptJSON_Success() {
        String plainJSON = '{"ruleName":"DOT_WL","header":[{"name":"EntityId","value":"123"}]}';
        
        Test.startTest();
        String encrypted = JWTTokenGenClass.encryptJSON(plainJSON);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, encrypted, 'Encrypted string should not be null');
        System.assert(encrypted.contains('JData'), 'Encrypted JSON should contain JData wrapper');
        System.assert(encrypted.startsWith('{"JData":"'), 'Should start with JData format');
        System.assert(encrypted.endsWith('"}'), 'Should end with proper format');
    }
    
    /*
    * @Method: testEncryptJSON_WithComments
    * @Description: Tests JSON encryption with single-line and multi-line comments
    */
    @isTest
    static void testEncryptJSON_WithComments() {
        String plainJSONWithComments = '{"ruleName":"DOT_WL",/* comment */"header":[{"name":"EntityId","value":"123"}]}';
        
        Test.startTest();
        String encrypted = JWTTokenGenClass.encryptJSON(plainJSONWithComments);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, encrypted, 'Encrypted string should not be null');
        System.assert(encrypted.contains('JData'), 'Encrypted JSON should contain JData wrapper');
    }
    
    /*
    * @Method: testEncryptJSON_WithSingleLineComments
    * @Description: Tests JSON encryption with single-line comments
    */
    @isTest
    static void testEncryptJSON_WithSingleLineComments() {
        String plainJSONWithComments = '{"ruleName":"DOT_WL",\n// This is a comment\n"header":[]}';
        
        Test.startTest();
        String encrypted = JWTTokenGenClass.encryptJSON(plainJSONWithComments);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, encrypted, 'Encrypted string should not be null');
        System.assert(encrypted.contains('JData'), 'Encrypted JSON should contain JData wrapper');
    }
    
    /*
    * @Method: testEncryptJSON_EmptyString
    * @Description: Tests JSON encryption with empty string
    */
    @isTest
    static void testEncryptJSON_EmptyString() {
        Test.startTest();
        try {
            String encrypted = JWTTokenGenClass.encryptJSON('');
            System.assert(true, 'Should handle empty string');
        } catch (Exception e) {
            System.assert(e instanceof AuraHandledException, 'Should throw AuraHandledException');
        }
        Test.stopTest();
    }
    
    /*
    * @Method: testDecryptJSON_WithJDataWrapper
    * @Description: Tests JSON decryption with JData wrapper
    */
    @isTest
    static void testDecryptJSON_WithJDataWrapper() {
        // First encrypt a test JSON
        String plainJSON = '{"ruleName":"TEST","value":"123"}';
        String encrypted = JWTTokenGenClass.encryptJSON(plainJSON);
        
        Test.startTest();
        String decrypted = JWTTokenGenClass.decryptJSON(encrypted);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, decrypted, 'Decrypted string should not be null');
        System.assert(decrypted.contains('ruleName'), 'Decrypted JSON should contain original data');
    }
    
    /*
    * @Method: testDecryptJSON_WithWhitespace
    * @Description: Tests JSON decryption with whitespace in input
    */
    @isTest
    static void testDecryptJSON_WithWhitespace() {
        // First encrypt a test JSON
        String plainJSON = '{"ruleName":"TEST","value":"123"}';
        String encrypted = JWTTokenGenClass.encryptJSON(plainJSON);
        
        // Add whitespace to encrypted string
        String encryptedWithWhitespace = '\n  ' + encrypted + '  \n';
        
        Test.startTest();
        String decrypted = JWTTokenGenClass.decryptJSON(encryptedWithWhitespace);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, decrypted, 'Decrypted string should not be null');
        System.assert(decrypted.contains('ruleName'), 'Should handle whitespace in input');
    }
    
    /*
    * @Method: testDecryptJSON_RawEncryptedString
    * @Description: Tests JSON decryption with raw encrypted string (no JData wrapper)
    */
    @isTest
    static void testDecryptJSON_RawEncryptedString() {
        // Get just the encrypted data without wrapper
        String plainJSON = '{"test":"data"}';
        String encryptedWithWrapper = JWTTokenGenClass.encryptJSON(plainJSON);
        String rawEncrypted = encryptedWithWrapper.substring(10, encryptedWithWrapper.length()-2);
        
        Test.startTest();
        String decrypted = JWTTokenGenClass.decryptJSON(rawEncrypted);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, decrypted, 'Decrypted string should not be null');
    }
    
    /*
    * @Method: testDecryptJSON_InvalidInput
    * @Description: Tests JSON decryption with invalid input

    @isTest
    static void testDecryptJSON_InvalidInput() {
        String invalidEncrypted = 'InvalidEncryptedString';
        
        Test.startTest();
        try {
            String decrypted = JWTTokenGenClass.decryptJSON(invalidEncrypted);
            System.assert(false, 'Should throw exception for invalid input');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Decryption Error'), 'Should throw decryption error');
        }
        Test.stopTest();
    }    
    */
    
    /*
    * @Method: testDecryptJSON_FormattedJDataInput
    * @Description: Tests JSON decryption with formatted JData input (newlines and spaces)
    */
    @isTest
    static void testDecryptJSON_FormattedJDataInput() {
        // First encrypt a test JSON
        String plainJSON = '{"test":"value"}';
        String encrypted = JWTTokenGenClass.encryptJSON(plainJSON);
        
        // Format the encrypted JSON with newlines and spaces
        String formattedInput = '{\n\n    "JData": "' + 
            encrypted.substring(10, encrypted.length()-2) + 
            '"\n\n}';
        
        Test.startTest();
        String decrypted = JWTTokenGenClass.decryptJSON(formattedInput);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, decrypted, 'Should handle formatted input');
    }
    
    /*
    * @Method: testEncryptDecryptRoundTrip
    * @Description: Tests complete encrypt-decrypt round trip
    */
    @isTest
    static void testEncryptDecryptRoundTrip() {
        String originalJSON = '{"name":"TestUser","amount":"50000","type":"encryption"}';
        
        Test.startTest();
        // Encrypt
        String encrypted = JWTTokenGenClass.encryptJSON(originalJSON);
        System.assertNotEquals(null, encrypted, 'Encryption should succeed');
        
        // Decrypt
        String decrypted = JWTTokenGenClass.decryptJSON(encrypted);
        System.assertNotEquals(null, decrypted, 'Decryption should succeed');
        Test.stopTest();
        
        // Parse both JSONs and compare
        Map<String, Object> originalMap = (Map<String, Object>)JSON.deserializeUntyped(originalJSON);
        Map<String, Object> decryptedMap = (Map<String, Object>)JSON.deserializeUntyped(decrypted);
        
        System.assertEquals(originalMap.get('name'), decryptedMap.get('name'), 'Name should match');
        System.assertEquals(originalMap.get('amount'), decryptedMap.get('amount'), 'Amount should match');
    }
    
    /*
    * @Method: testComplexJSONWithComments
    * @Description: Tests encryption of complex JSON with multiple types of comments
    */
    @isTest
    static void testComplexJSONWithComments() {
        String complexJSON = '{\n' +
            '    "ruleName": "MHA_NGTVE_WL",\n' +
            '    /* Multi-line comment\n' +
            '       spanning multiple lines */\n' +
            '    "header": [\n' +
            '        {\n' +
            '            "name": "EntityId",\n' +
            '            "value": "BFEPL4646D"  /* Inline comment */\n' +
            '        },\n' +
            '        // Single line comment\n' +
            '        {\n' +
            '            "name": "EntityType",\n' +
            '            "value": "Prospect"\n' +
            '        }\n' +
            '    ]\n' +
            '}';
        
        Test.startTest();
        String encrypted = JWTTokenGenClass.encryptJSON(complexJSON);
        String decrypted = JWTTokenGenClass.decryptJSON(encrypted);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, encrypted, 'Encryption should succeed');
        System.assertNotEquals(null, decrypted, 'Decryption should succeed');
        System.assert(decrypted.contains('MHA_NGTVE_WL'), 'Should preserve data');
    }
    
    // ========== MOCK CLASSES ==========
    
    /*
    * @Class: JWTTokenSuccessMock
    * @Description: Mock class for successful HTTP response
    */
    private class JWTTokenSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"access_token":"mock_access_token_12345","instance_url":"https://test.salesforce.com","id":"https://test.salesforce.com/id/00Dxx0000001gEREAY/005xx000001Sv6AAAS","token_type":"Bearer","issued_at":"1234567890","signature":"mock_signature"}');
            res.setStatusCode(200);
            return res;
        }
    }
    
    /*
    * @Class: JWTTokenErrorMock
    * @Description: Mock class for HTTP error response
    */
    private class JWTTokenErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"invalid_grant","error_description":"user hasn\'t approved this consumer"}');
            res.setStatusCode(400);
            return res;
        }
    }
}