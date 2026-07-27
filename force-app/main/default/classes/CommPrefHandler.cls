public without sharing class CommPrefHandler implements pref_center.PreferenceCenterApexHandler {
public void submit(pref_center.SubmitParameters submitParams, pref_center.SubmitFormData formData, pref_center.ValidationResult validationResult) {

}

public pref_center.LoadFormData load(pref_center.LoadParameters loadParams, pref_center.LoadFormData loadFormData, pref_center.ValidationResult validationResult) {
return loadFormData;
}
}