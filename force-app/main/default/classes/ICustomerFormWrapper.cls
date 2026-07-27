/**
 * @description Contract for form-specific PDF merge-field builders used by CustomerFormController.
 */
public interface ICustomerFormWrapper {
    Map<String, Object> buildInputJson(Id applicationId, Id applicantId);
    String getDocumentType();
    String getDocumentName();
}