public interface QCValidationCallback {
    QCValidationCallbackResult onLoad(Map<String, Object> context);
    QCValidationCallbackResult onSave(Map<String, Object> context);
}