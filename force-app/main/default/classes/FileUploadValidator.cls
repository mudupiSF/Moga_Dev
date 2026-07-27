/**
 * Implement this interface in any Apex class and point the component's
 * "Validator Apex Class" property to that class name.
 * validate() must return an empty list to allow the upload.
 * Any strings returned are shown to the user as error messages.
 */
public interface FileUploadValidator {
    List<String> validate(Id recordId);
}