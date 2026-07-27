public without sharing class ApplicationFormController {

    // ── Applicant details ─────────────────────────────────────────────────────
    public String applicantName       { get; private set; }
    public String applicationNumber   { get; private set; }
    public String applicantDOB        { get; private set; }
    public String applicantPAN        { get; private set; }
    public String applicantAadhaar    { get; private set; }
    public String applicantMobile     { get; private set; }
    public String applicantEmail      { get; private set; }
    public String applicantAddress    { get; private set; }
    public String applicantCity       { get; private set; }
    public String applicantState      { get; private set; }
    public String applicantPincode    { get; private set; }

    // ── Co-applicant details ──────────────────────────────────────────────────
    public String coApplicantName     { get; private set; }
    public String coApplicantRelation { get; private set; }
    public String coApplicantMobile   { get; private set; }

    // ── Loan details ──────────────────────────────────────────────────────────
    public String loanAmount          { get; private set; }
    public String loanTenure          { get; private set; }
    public String loanPurpose         { get; private set; }
    public String vehicleType         { get; private set; }
    public String vehicleMake         { get; private set; }
    public String vehicleModel        { get; private set; }
    public String vehicleYear         { get; private set; }
    public String onRoadPrice         { get; private set; }
    public String downPayment         { get; private set; }

    // ── Employment details ────────────────────────────────────────────────────
    public String employmentType      { get; private set; }
    public String employerName        { get; private set; }
    public String monthlyIncome       { get; private set; }
    public String annualIncome        { get; private set; }

    // ── Bank details ──────────────────────────────────────────────────────────
    public String bankName            { get; private set; }
    public String accountNumber       { get; private set; }
    public String ifscCode            { get; private set; }
    public String accountType         { get; private set; }

    // ── State ─────────────────────────────────────────────────────────────────
    public String  consentStatus      { get; private set; }
    public Boolean renderAsPdf        { get; private set; }

    public ApplicationFormController() {
        consentStatus   = 'initial';
        renderAsPdf     = ApexPages.currentPage().getParameters().get('pdf') == 'true';

        // ── Dummy applicant data ──────────────────────────────────────────────
        applicantName     = 'RAJESH RAMDIN GUPTA MANIKANDAN';
        applicationNumber = 'L29122500033';
        applicantDOB      = '15-Aug-1985';
        applicantPAN      = 'ABCDE1234F';
        applicantAadhaar  = 'XXXX XXXX 4321';
        applicantMobile   = '+91 98765 43210';
        applicantEmail    = 'rajesh.manikandan@email.com';
        applicantAddress  = '12, Shivaji Nagar, Near Post Office';
        applicantCity     = 'Pune';
        applicantState    = 'Maharashtra';
        applicantPincode  = '411005';

        // ── Dummy co-applicant data ───────────────────────────────────────────
        coApplicantName     = 'PRIYA RAMDIN MANIKANDAN';
        coApplicantRelation = 'Spouse';
        coApplicantMobile   = '+91 98765 11111';

        // ── Dummy loan data ───────────────────────────────────────────────────
        loanAmount   = '₹3,50,000';
        loanTenure   = '36 Months';
        loanPurpose  = 'Vehicle Purchase';
        vehicleType  = 'Two Wheeler';
        vehicleMake  = 'Honda';
        vehicleModel = 'Activa 6G';
        vehicleYear  = '2024';
        onRoadPrice  = '₹85,000';
        downPayment  = '₹15,000';

        // ── Dummy employment data ─────────────────────────────────────────────
        employmentType = 'Salaried';
        employerName   = 'ABC Technologies Pvt. Ltd.';
        monthlyIncome  = '₹45,000';
        annualIncome   = '₹5,40,000';

        // ── Dummy bank data ───────────────────────────────────────────────────
        bankName      = 'Bandhan Bank';
        accountNumber = 'XXXXXXXX7890';
        ifscCode      = 'BDBL0001234';
        accountType   = 'Savings';
    }

    public PageReference doAgree() {
        consentStatus = 'agreed';
        return null;
    }

    public PageReference doDisagree() {
        consentStatus = 'disagreed';
        return null;
    }
}