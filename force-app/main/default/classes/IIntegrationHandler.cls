/**
* @author        	  : Ritika Dhandia
* @description        : Interface for Integration Handler.
*/
public interface IIntegrationHandler {
    
    /**
     * @description        : Prepare Record for Integration. Query all fields required for the validation
     *                       and request
     * @param recordIds    : List of Record IDs.
     * @return             : List of sObjects.
     */
    List<sObject> prepareRecordForIntegration(List<Id> recordIds);
    
    /**
     * @description        : Validate Input Data. The recordList passed should already have all the fields
     *                       required for the validation, no query again.      
     * @param recordList   : List of Records.
     * @return             : List of Objects. Typically IntegrationResponseWrapper
     */
    List<Object> validateInputData(List<Object> recordList);

    /**
     * @description        : Generate Request. The recordList passed should already have all the fields
     *                       required for the request, no query again.
     * @param recordList   : List of Records.
     * @return             : List of Objects. Typically IntegrationRequestWrapper
     */
    List<Object> generateRequest(List<Object> recordList);

    /**
     * @description        : Process Response.
     * @param recordList   : List of Records.
     * @return             : List of Objects.
     */
    List<Object> processResponse(List<Object> recordList);

    

}