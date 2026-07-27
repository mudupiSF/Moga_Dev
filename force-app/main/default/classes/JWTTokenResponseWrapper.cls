/*
* Created By : Ajay Bharathan
* Purpose : To generate JWT and Access Token for Admin (Or) Other Users
* Main Class : JWTTokenGenClass
* Reference : JWTTokenResponseWrapper
*/
public class JWTTokenResponseWrapper {
    public String sfdc_community_url;
    public String sfdc_community_id;
    public String scope;
    public String instance_url;
    public String id;
    public String token_type;
    
    @AuraEnabled public Boolean jwtSignedAndVerified;
    @AuraEnabled public String sfErrMsg;
    @AuraEnabled public String jwtToken;
    @AuraEnabled public String access_token;
    
    public static JWTTokenResponseWrapper parse(String json) {
        return (JWTTokenResponseWrapper) System.JSON.deserialize(json, JWTTokenResponseWrapper.class);
    }
}