public class SetLoyaltyDetails {

    @InvocableMethod (label='Update Contact with Loyalty Details')
    public static void setLoyaltyParams(List<String> payload) {
        System.debug(LoggingLevel.DEBUG, '... payload : ' + payload[0]);
        Map<Set<string>, Loyalty> loyaltyParams = new Map<Set<string>, Loyalty>();
        JSONParser parser = JSON.createParser(payload[0]);
        Set<string> loyaltyId = new Set<string>();
        Loyalty loyaltyObj = new Loyalty();
        integer points;
        date birthdate;
        id contactId;
        string category;
        string loyalty_id;
        while (parser.nextToken() != null) {
            if( (parser.getCurrentToken() == JSONToken.FIELD_NAME) ) {
                System.debug(LoggingLevel.DEBUG, '... key ' + parser.getText());
                if(parser.getText() == 'id_card__c') {
                // get the value
                parser.nextToken();
                    loyalty_id = parser.getText();
                    loyaltyId.add(loyalty_id);
                System.debug(LoggingLevel.DEBUG, '... id_card__c : ' + loyalty_id);            
                }else if( parser.getText() == 'points__c') {
                parser.nextToken();
                    points = parser.getIntegerValue();
                System.debug(LoggingLevel.DEBUG, '... points__c : ' + points);
                }else if( parser.getText() == 'birthdate__c') {
                parser.nextToken();
                    birthdate = Date.valueOf(parser.getText());
                System.debug(LoggingLevel.DEBUG, '... birthdate__c : ' + birthdate);
                }else if( parser.getText() == 'contact__c') {
                parser.nextToken();
                    contactId = (Id) parser.getText();
                System.debug(LoggingLevel.DEBUG, '... contact__c : ' + contactId);                    
                }else if( parser.getText() == 'category__c') {
                parser.nextToken();
                    category = parser.getText();
                System.debug(LoggingLevel.DEBUG, '... category__c : ' + category);                    
                }
            }
            System.debug(LoggingLevel.DEBUG, '... go back to while loop again');
        }
        //create the data set to update contact record.
		loyaltyObj.points = points;
        loyaltyObj.birthdate = birthdate;
        loyaltyObj.contactId = contactId;
        loyaltyObj.category = category;
        loyaltyObj.loyalty_id = loyalty_id;
        loyaltyParams.put(loyaltyId, loyaltyObj);
        for(set<string> lId : loyaltyParams.keyset()) {
            set<string> loyaltySetId = lId;
            for(string s : loyaltySetId) {
                system.debug(LoggingLevel.DEBUG, '... key ' + s);
            }
            Loyalty loyaltyObject = loyaltyParams.get(loyaltySetId);
            Contact con = new Contact();
            con.Id = loyaltyObject.contactId;
            con.Loyalty_Points__c = loyaltyObject.points;
            try{
            	update con;
            }catch(exception ex) {
                System.debug(LoggingLevel.ERROR, '... error ' + ex.getMessage());
            }        
        }

        
    }
    
    
	class Loyalty {
        integer points {get; set;}
        date birthdate {get; set;}
        id contactId {get; set;}
        string category {get; set;}
        string loyalty_id {get; set;}
		// empty constructor;
        Loyalty(){}
        // constructor w/ contract
        Loyalty(integer vPoints, date vBdate, id vContact, string vCategory, string vLoyaltyId) {
            points = vPoints;
            birthdate = vBdate;
            contactId = vContact;
            category = vCategory;
            loyalty_id = vLoyaltyId;
        }
    }    
}