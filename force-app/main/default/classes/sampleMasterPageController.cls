public with sharing class sampleMasterPageController implements Callable {

    public Object call(String action, Map<String, Object> args) {
        if ('savePageData'.equals(action)) {
            return new Map<String, Object>{ 'isSuccess' => true };
        }
        if ('getPageData'.equals(action)) {
            return new Map<String, Object>{
                'productType' => '2W',
                'applicantType' => 'Borrower'
            };
        }
        return null;
    }

}