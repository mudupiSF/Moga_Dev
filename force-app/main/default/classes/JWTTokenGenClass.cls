/*
 * Created By : Ajay Bharathan
 * Purpose    : Generate JWT + Salesforce Access Token for Admin / Other personas.
 *              Also exposes encrypt/decrypt JSON utilities used by the
 *              IBL_JWTTokenGenerator Aura component (Encrypt / Decrypt tabs).
 * Reference  : JWTTokenResponseWrapper
 *
 * ─────────────────────────────────────────────────────────────────────────────
 *  ENCRYPTION PATH NOTE (MOGA DEV)
 * ─────────────────────────────────────────────────────────────────────────────
 *  The Encrypt / Decrypt tabs of the IBL_JWTTokenGenerator Aura component
 *  exercise `encryptJSON` and `decryptJSON` below. Two encryption strategies
 *  are available in `IntegrationUtility` — only ONE is active at a time:
 *
 *  [ACTIVE]  IntegrationUtility.getEncryptedRequest(json, 'pkey', 'iv')
 *            IntegrationUtility.getDecryptedResponse(json, 'pkey', 'iv')
 *            ──────────────────────────────────────────────────────────
 *            Uses Crypto.encrypt('AES256', privateKey, ivkey, data) — an
 *            EXPLICIT-IV scheme. Keys come from `Encryption_Setting__mdt.Keys`
 *            (`Private_Key__c` + `IV_Key__c`) via the `getAPIKeys(label)`
 *            helper. Label comparison in `getAPIKeys` is CASE-SENSITIVE
 *            (`'pkey'.equals(label)`) — callers MUST pass lowercase 'pkey'
 *            and 'iv'. Mirrors the IBL_SIT implementation so ciphertext can
 *            be exchanged between orgs when keys are kept in sync.
 *
 *  [DORMANT] IntegrationUtility.encryptMessage(json)
 *            IntegrationUtility.decryptMessage(json)
 *            ──────────────────────────────────────────────────────────
 *            Uses Crypto.encryptWithManagedIV('AES256', keyBlob, data) — a
 *            MANAGED-IV scheme (IV is prepended to ciphertext by the
 *            platform). Keys come from `Encryption_Setting__mdt.Default`
 *            (`Outgoing_Key__c` + `Incoming_Key__c`). Null/blank-safe.
 *            Simpler call surface (no key-label arguments). Ciphertext is
 *            NOT byte-compatible with IBL_SIT's explicit-IV output.
 *
 *  See the commented-out lines in `encryptJSON` / `decryptJSON` below for
 *  the exact swap if you ever want to flip strategies.
 * ─────────────────────────────────────────────────────────────────────────────
 */

public with sharing class JWTTokenGenClass {

    @AuraEnabled
    public static JWTTokenResponseWrapper fetchToken(String personaName)
    {
        JWTTokenResponseWrapper wrp = new JWTTokenResponseWrapper();
        Http httpObj = new Http();
        HttpRequest req = new HttpRequest();
        HttpResponse res;
        
        if(String.isBlank(personaName)){
            wrp.sfErrMsg = 'Please fill in Persona Name';
            wrp.jwtSignedAndVerified = false;
            return wrp;
        }
        else 
        {
            JWT_Mapping__mdt jwt = JWT_Mapping__mdt.getInstance(personaName);
            if(jwt?.DeveloperName == personaName)
            {
                Long exp = DateTime.now().addMinutes(5).getTime();
                //system.debug('exp$$$ '+exp);

                String jwtHeader = '{"typ":"JWT","alg":"RS256"}';
                String jwtClaims = '{"iss":"' + jwt?.Issuer__c + '","sub":"' + jwt?.Subject__c + '","aud":"' + jwt?.Audience__c + '","exp":' + exp + '}';
                //system.debug('jwtClaims$$$ '+jwtClaims);

                String jwtRequest = base64URLSafeEncode(Blob.valueOf(jwtHeader)) + '.' + base64URLSafeEncode(Blob.valueOf(jwtClaims));   
                String signature = base64URLSafeEncode(Crypto.signWithCertificate('RSA-SHA256', Blob.valueOf(jwtRequest), 'JWT_SS_Cert'));
                Boolean verified_signature = Crypto.verify('RSA-SHA256', Blob.valueOf(jwtRequest), base64URLSafeDecode(signature),'JWT_SS_Cert');
                
                String signedJwtRequest = jwtRequest + '.' + signature;
                
                //String payload = 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer';
                String payload = 'grant_type=' + System.EncodingUtil.urlEncode('urn:ietf:params:oauth:grant-type:jwt-bearer', 'UTF-8');
                payload += '&assertion=' + signedJwtRequest;
                
                req.setEndpoint(jwt?.Audience__c + '/services/oauth2/token');
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
                req.setBody(payload);

                res = httpObj.send(req);
                system.debug('response received$$$'+res.getBody());

                wrp = JWTTokenResponseWrapper.parse(res.getBody()); 
                system.debug('token$$$ '+wrp);
                wrp.jwtToken = signedJwtRequest;
                wrp.jwtSignedAndVerified = verified_signature;
                wrp.sfErrMsg = null;
                return wrp;
            }       
            else{
                wrp.sfErrMsg = 'Persona is invalid/does not exist';
                wrp.jwtSignedAndVerified = false;
                return wrp;
            }
        }
    }

    public static String base64URLSafeEncode(Blob input){
        String output = encodingUtil.base64Encode(input);
        output = output.replace('+', '-');
        output = output.replace('/', '_');
        while ( output.endsWith('=')){
            output = output.subString(0,output.length()-1);
        }
        return output;
    }

    public static Blob base64URLSafeDecode(String input){
        String outputString = input.replace('-','+').replace('_','/').rightPad(math.mod(input.length()+(math.mod(4 - input.length(),4)),4)).replace(' ','=');
        return EncodingUtil.base64Decode(outputString); 
    }

    /*
    * @Method:      encryptJSON
    * @Created by:  Ajay Bharathan
    * @Description: Method to encrypt JSON after removing comments
    * @Param:       String - plainJSON
    * @Return:      String - encryptedJSON with JData wrapper
    */
    @AuraEnabled
    public static String encryptJSON(String plainJSON){
        try {
            // Remove comments from JSON
            String cleanJSON = removeJSONComments(plainJSON);
            
            // ─── [ACTIVE] Explicit-IV AES256 — mirrors IBL_SIT ────────────────
            // Keys: Encryption_Setting__mdt.Keys.Private_Key__c + IV_Key__c
            // Labels MUST be lowercase ('pkey', 'iv') — getAPIKeys uses
            // case-sensitive String.equals.
            String encryptedString = IntegrationUtility.getEncryptedRequest(cleanJSON,'pkey','iv');

            // ─── [DORMANT] Managed-IV AES256 alternative ──────────────────────
            // Uncomment the line below and comment the line above to switch.
            // Keys: Encryption_Setting__mdt.Default.Outgoing_Key__c (32-byte
            // base64). Null/blank-safe. Ciphertext NOT byte-compatible with
            // IBL_SIT explicit-IV output.
            //
            // String encryptedString = IntegrationUtility.encryptMessage(cleanJSON);
            
            // Wrap in JData format
            String finalJSON = '{"JData":"' + encryptedString + '"}';
            return finalJSON;
        } catch (Exception e) {
            throw new AuraHandledException('Encryption Error: ' + e.getMessage());
        }
    }

    /*
    * @Method:      decryptJSON
    * @Created by:  Ajay Bharathan
    * @Description: Method to decrypt encrypted JSON
    * @Param:       String - encryptedJSON
    * @Return:      String - decryptedJSON
    */
    @AuraEnabled
    public static String decryptJSON(String encryptedJSON){
        try {
            String cleanedInput = encryptedJSON.replaceAll('\\s+', '');
            
            String encryptedData = cleanedInput;
            
            if(cleanedInput.startsWith('{"JData":"') && cleanedInput.endsWith('"}')){
                encryptedData = cleanedInput.substring(10, cleanedInput.length()-2);
            } else if(cleanedInput.startsWith('{"JData":"')){
                Integer startIndex = cleanedInput.indexOf('"JData":"') + 9;
                Integer endIndex = cleanedInput.lastIndexOf('"');
                encryptedData = cleanedInput.substring(startIndex, endIndex);
            }
            
            encryptedData = encryptedData.trim();
            
            // ─── [ACTIVE] Explicit-IV AES256 — mirrors IBL_SIT ────────────────
            // Keys: Encryption_Setting__mdt.Keys.Private_Key__c + IV_Key__c
            // Labels MUST be lowercase ('pkey', 'iv') — getAPIKeys uses
            // case-sensitive String.equals.
            String decryptedString = IntegrationUtility.getDecryptedResponse(encryptedData,'pkey','iv');

            // ─── [DORMANT] Managed-IV AES256 alternative ──────────────────────
            // Uncomment the line below and comment the line above to switch.
            // Keys: Encryption_Setting__mdt.Default.Incoming_Key__c (32-byte
            // base64). Null/blank-safe. Will only decrypt ciphertext that was
            // also produced via encryptMessage() — NOT IBL_SIT output.
            //
            // String decryptedString = IntegrationUtility.decryptMessage(encryptedData);
            
            return decryptedString;
        } catch (Exception e) {
            throw new AuraHandledException('Decryption Error: ' + e.getMessage());
        }
    }

    /*
    * @Method:      removeJSONComments
    * @Created by:  Ajay Bharathan
    * @Description: Method to remove comments from JSON string
    * @Param:       String - jsonWithComments
    * @Return:      String - cleanJSON
    */
    private static String removeJSONComments(String jsonWithComments){
        if(String.isBlank(jsonWithComments)){
            return '';
        }
        
        String cleanJSON = jsonWithComments;
        
        // Remove single-line comments (// ...)
        cleanJSON = cleanJSON.replaceAll('//[^\\n]*', '');
        
        // Remove multi-line comments (/* ... */)
        cleanJSON = cleanJSON.replaceAll('/\\*[\\s\\S]*?\\*/', '');
        
        // Remove extra whitespaces and newlines
        cleanJSON = cleanJSON.replaceAll('\\s+', ' ').trim();
        
        return cleanJSON;
    }
}