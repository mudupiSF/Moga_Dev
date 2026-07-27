public without sharing class InsuranceConsentController {

    public String  applicantName    { get; private set; }
    public String  applicationNumber { get; private set; }
    public List<ProductItem>  products  { get; private set; }
    public List<InsurerItem>  insurers  { get; private set; }
    public List<PremiumRow>   premiumRows { get; private set; }
    public Integer totalPremium     { get; private set; }
    public String  consentStatus    { get; private set; } // 'initial' | 'agreed' | 'disagreed'
    public Boolean renderAsPdf      { get; private set; }

    public InsuranceConsentController() {
        consentStatus    = 'initial';
        renderAsPdf      = ApexPages.currentPage().getParameters().get('pdf') == 'true';

        // ── Dummy data ────────────────────────────────────────────────────────
        applicantName     = 'RAJESH RAMDIN GUPTA MANIKANDAN';
        applicationNumber = 'L29122500033';

        products = new List<ProductItem>{
            new ProductItem('Motor',                       false),
            new ProductItem('Group Personal Accident',     false),
            new ProductItem('Health',                      false),
            new ProductItem('Group Credit Life Insurance', true),
            new ProductItem('EMI',                         true)
        };

        insurers = new List<InsurerItem>{
            new InsurerItem('Chola MS',         false),
            new InsurerItem('ICICI Prudential', true),
            new InsurerItem('TATA',             false),
            new InsurerItem('Reliance',         true)
        };

        premiumRows = new List<PremiumRow>{
            new PremiumRow('ICICI Prudential', 'Group Credit Life Insurance', 20000),
            new PremiumRow('Reliance',         'EMI',                         5000)
        };

        totalPremium = 0;
        for (PremiumRow r : premiumRows) {
            totalPremium += r.premium;
        }
    }

    public PageReference doAgree() {
        consentStatus = 'agreed';
        return null;
    }

    public PageReference doDisagree() {
        consentStatus = 'disagreed';
        return null;
    }

    // ── Inner wrappers ────────────────────────────────────────────────────────
    public class ProductItem {
        public String  label   { get; set; }
        public Boolean checked { get; set; }
        public ProductItem(String label, Boolean checked) {
            this.label   = label;
            this.checked = checked;
        }
    }

    public class InsurerItem {
        public String  label   { get; set; }
        public Boolean checked { get; set; }
        public InsurerItem(String label, Boolean checked) {
            this.label   = label;
            this.checked = checked;
        }
    }

    public class PremiumRow {
        public String  insurer { get; set; }
        public String  product { get; set; }
        public Integer premium { get; set; }
        public PremiumRow(String insurer, String product, Integer premium) {
            this.insurer = insurer;
            this.product = product;
            this.premium = premium;
        }
    }
}