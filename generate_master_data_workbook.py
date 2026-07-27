from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Iterable

from openpyxl import Workbook, load_workbook
from openpyxl.comments import Comment
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter, quote_sheetname
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.table import Table, TableStyleInfo


ROOT = Path(__file__).resolve().parent
METADATA_ROOT = ROOT / "force-app" / "main" / "default"
OBJECTS_ROOT = METADATA_ROOT / "objects"
CUSTOM_METADATA_ROOT = METADATA_ROOT / "customMetadata"
OUTPUT = ROOT / "Moga_Dev_Master_Data_Client_Template.xlsx"

NS = {"sf": "http://soap.sforce.com/2006/04/metadata"}


BUSINESS_MASTERS = {
    "Mitigant_Master__c",
    "Employer_Master__c",
    "Document_Master__c",
    "ROI_Master__c",
    "Insurance_Master__c",
    "Industry_Code_and_Type__c",
    "Agency_Pincode__c",
    "Dealer_Master__c",
    "Agency_Master__c",
    "City_Master__c",
    "Bank_Master__c",
    "Schemes__c",
    "District_Master__c",
    "MMV_Product_Master__c",
    "Deviation_Master__c",
    "State_Master__c",
    "Pincode_Master__c",
    "NIC_Master__c",
    "Manufacturer__c",
    "Corporate_Probe42_Entity__c",
    "Product2",
    "Account",
}

CONFIG_OBJECTS = {
    "Dashboard_Configuration__c",
    "PDFforceConfig__c",
    "Integration_Master__c",
}

CUSTOM_SETTINGS = {
    "TriggerDeactivationSettings__c",
}

PURPOSES = {
    "Mitigant_Master__c": "Approved mitigants used against credit deviations.",
    "Employer_Master__c": "Employer directory and employer classification for salaried applicants.",
    "Document_Master__c": "Document catalogue, upload rules, verification attributes, and file constraints.",
    "ROI_Master__c": "Rate-of-interest ranges by product, segment, customer, vehicle, and tenure.",
    "Insurance_Master__c": "Insurance companies and plan catalogue.",
    "Industry_Code_and_Type__c": "Industry names and codes used for non-individual applicants.",
    "Agency_Pincode__c": "Agency service-area mapping by pincode.",
    "Dealer_Master__c": "Vehicle dealer directory and dealer eligibility/configuration.",
    "Agency_Master__c": "External agency directory and agency configuration.",
    "City_Master__c": "City reference data linked to state.",
    "Bank_Master__c": "Bank directory used in repayment mandate capture.",
    "Schemes__c": "Loan scheme eligibility, pricing, charges, product, geography, and validity rules.",
    "District_Master__c": "District reference data linked to state.",
    "MMV_Product_Master__c": "Make-model-variant product catalogue used for vehicle selection.",
    "Deviation_Master__c": "Deviation definitions, classification, and approval routing inputs.",
    "State_Master__c": "State reference data.",
    "Pincode_Master__c": "Pincode reference data and geography mapping.",
    "Integration_Master__c": "Integration endpoints, handlers, retry, encryption, and UI component configuration.",
    "NIC_Master__c": "NIC industry/activity code catalogue used in credit assessment.",
    "Manufacturer__c": "Vehicle manufacturer reference data.",
    "Corporate_Probe42_Entity__c": "Probe42 company/LLP/partnership catalogue and report-control reference.",
    "Product2": "Supporting Salesforce product catalogue referenced by scheme and ROI masters.",
    "Account": "Branch catalogue represented by Salesforce Account records with branch code and state.",
    "Dashboard_Configuration__c": "Dashboard widget/query configuration by persona and display area.",
    "PDFforceConfig__c": "PDF template and wrapper-class configuration.",
    "TriggerDeactivationSettings__c": "Hierarchy custom setting for disabling selected trigger processing.",
    "QC_Verification_Parent__mdt": "Parent object/section query configuration for quality-control verification.",
    "QC_Admin_Console__mdt": "Quality-control admin console actions and source-object configuration.",
    "Field_Verification_Config__mdt": "Field-level verification, document, integration, and comparison rules.",
    "Dynamic_Stage_Gate__mdt": "Product-specific stage, sub-stage, page, sequence, and visibility configuration.",
    "User_Product_Record_Tyoe_Mapping__mdt": "User/profile-to-product and record-type mapping.",
    "Encryption_Setting__mdt": "Encryption/decryption algorithm, key reference, and transformation settings.",
    "Document_Manager__mdt": "Document manager display and behavior configuration.",
    "Search_Config__mdt": "Search source, filters, fields, and result display configuration.",
    "Stage_reversal_configuration__mdt": "Rules governing allowed stage reversals.",
    "Non_Individual_Constitution__mdt": "Constitution-specific beneficiary and non-individual applicant rules.",
    "QLabs__mdt": "Q-Labs integration or feature configuration.",
    "Query_Configuration__mdt": "Query/affidavit/document text and generation configuration.",
    "Deviation_Level_Skip_Metadata__mdt": "Deviation approval levels that may be skipped under configured conditions.",
    "Committee_Deviation__mdt": "Committee routing and mandatory-role rules by product.",
    "Committee_Role_Level__mdt": "Committee role-to-level configuration.",
    "Committee_Role_Hierarchy__mdt": "Committee role hierarchy and progression configuration.",
    "JWT_Mapping__mdt": "JWT claim and integration-field mapping.",
}

MANAGED_PREFIXES = ("privacycenter__", "datadetect__")

ACTIVE_USAGE = {
    "MMV_Product_Master__c",
    "Schemes__c",
    "Industry_Code_and_Type__c",
    "NIC_Master__c",
    "State_Master__c",
    "District_Master__c",
    "City_Master__c",
    "Pincode_Master__c",
    "Bank_Master__c",
    "Document_Master__c",
    "Integration_Master__c",
    "Dashboard_Configuration__c",
    "TriggerDeactivationSettings__c",
    "PDFforceConfig__c",
    "Account",
    "Dynamic_Stage_Gate__mdt",
    "QC_Verification_Parent__mdt",
    "Field_Verification_Config__mdt",
    "QC_Admin_Console__mdt",
    "Document_Manager__mdt",
    "Search_Config__mdt",
    "Non_Individual_Constitution__mdt",
    "Query_Configuration__mdt",
    "Encryption_Setting__mdt",
    "JWT_Mapping__mdt",
    "User_Product_Record_Tyoe_Mapping__mdt",
}

RELATIONSHIP_BACKED = {
    "Manufacturer__c",
    "ROI_Master__c",
    "Employer_Master__c",
    "Dealer_Master__c",
    "Agency_Master__c",
    "Insurance_Master__c",
    "Corporate_Probe42_Entity__c",
    "Product2",
}

CONFIRM_RUNTIME = {
    "Deviation_Master__c",
    "Mitigant_Master__c",
    "Deviation_Level_Skip_Metadata__mdt",
    "Committee_Deviation__mdt",
    "Committee_Role_Level__mdt",
    "Committee_Role_Hierarchy__mdt",
}

RESTRICTED_CONFIG = {
    "Encryption_Setting__mdt",
    "JWT_Mapping__mdt",
}

DORMANT_OR_OPTIONAL = {
    "Agency_Pincode__c",
    "Stage_reversal_configuration__mdt",
    "QLabs__mdt",
}

# Salesforce omits type declarations for several standard Product2 fields in
# retrieved object metadata. These platform field types are stable and are
# supplied here so the client dictionary does not present them as unknown.
STANDARD_FIELD_TYPE_OVERRIDES = {
    ("Account", "Name"): "Text",
    ("Product2", "CanUseQuantitySchedule"): "Checkbox",
    ("Product2", "CanUseRevenueSchedule"): "Checkbox",
    ("Product2", "Description"): "LongTextArea",
    ("Product2", "DisplayUrl"): "Url",
    ("Product2", "ExternalId"): "Text",
    ("Product2", "IsActive"): "Checkbox",
    ("Product2", "Name"): "Text",
    ("Product2", "NumberOfQuantityInstallments"): "Number",
    ("Product2", "NumberOfRevenueInstallments"): "Number",
    ("Product2", "ProductCode"): "Text",
    ("Product2", "QuantityInstallmentPeriod"): "Picklist",
    ("Product2", "QuantityScheduleType"): "Picklist",
    ("Product2", "RevenueInstallmentPeriod"): "Picklist",
    ("Product2", "RevenueScheduleType"): "Picklist",
    ("Product2", "StockKeepingUnit"): "Text",
}

OBJECT_FIELD_ALLOWLIST = {
    "Account": {"Name", "Branch_Code__c", "State__c"},
}

DISPLAY_LABEL_OVERRIDES = {
    "Account": "Branch (Account)",
}

STATIC_UI_REFERENCE_GROUPS = [
    (
        "Occupation",
        "Employment Type",
        ["Full-Time", "Part-Time", "Contract", "Intern"],
        "Implemented UI/workbook reference",
        "Confirm against approved occupation rules",
        "CV_QDE_Occupation_Details_Requirements.md",
    ),
    (
        "Occupation",
        "Profession",
        ["Doctor", "CA", "Advocate", "Architect", "Independent Consultant", "Other"],
        "Implemented UI/workbook reference",
        "Confirm and extend if required",
        "CV_QDE_Occupation_Details_Requirements.md",
    ),
    (
        "Occupation",
        "Professional Body",
        ["ICAI", "ICSI", "Medical Councils", "Bar Councils", "Council of Architecture"],
        "Implemented UI/workbook reference",
        "Confirm exact stored codes and labels",
        "CV_QDE_Occupation_Details_Requirements.md",
    ),
    (
        "Occupation",
        "Industry / Sector",
        [
            "Agriculture",
            "Automotive",
            "Banking & Finance",
            "Construction",
            "Education",
            "Government",
            "Healthcare",
            "IT",
            "Manufacturing",
            "Retail",
            "Transport",
        ],
        "Implemented UI/workbook reference",
        "Reconcile with Industry Code and Type master",
        "CV_QDE_Occupation_Details_Requirements.md",
    ),
    (
        "Occupation",
        "Nature of Business",
        ["Trading", "Manufacturing", "Retail", "Wholesale", "Services", "Agriculture"],
        "Implemented UI/workbook reference",
        "Confirm canonical values",
        "CV_QDE_Occupation_Details_Requirements.md",
    ),
    (
        "Occupation",
        "Business Constitution",
        ["Proprietorship", "Partnership", "Private Limited", "Public Limited", "LLP"],
        "Implemented UI/workbook reference",
        "Reconcile with Non-Individual Constitution metadata",
        "CV_QDE_Occupation_Details_Requirements.md",
    ),
    (
        "Credit / PSL",
        "Financial Statement Basis",
        ["Audited", "Unaudited", "Projected"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/captureCreditAssessment/captureCreditAssessmentConstants.js",
    ),
    (
        "Credit / PSL",
        "PSL Classification",
        ["PSL", "Non-PSL"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/captureCreditAssessment/captureCreditAssessmentConstants.js",
    ),
    (
        "Credit / PSL",
        "Business Category",
        ["Manufacturing", "Services", "Trading"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/captureCreditAssessment/captureCreditAssessmentConstants.js",
    ),
    (
        "Credit / PSL",
        "Enterprise Size",
        ["Micro", "Small", "Medium"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/captureCreditAssessment/captureCreditAssessmentConstants.js",
    ),
    (
        "Credit / PSL",
        "GST Status",
        ["Available", "Applied For", "Exempted"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/captureCreditAssessment/captureCreditAssessmentConstants.js",
    ),
    (
        "Field Investigation",
        "FI Decision",
        ["Accepted", "Rejected"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/residenceFI/residenceFIHelper.js",
    ),
    (
        "Field Investigation",
        "Residence Ownership",
        ["Owned", "Rented", "Company Provided", "Parental"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/residenceFI/residenceFIHelper.js",
    ),
    (
        "Field Investigation",
        "FI Recommendation",
        ["Positive", "Negative", "Refer to Credit", "Inconclusive"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/residenceFI/residenceFIHelper.js",
    ),
    (
        "Field Investigation",
        "Premises Zone",
        ["Commercial", "Residential", "Industrial", "Mixed"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/residenceFI/residenceFIHelper.js",
    ),
    (
        "Income",
        "Income Source",
        ["GST", "ITR", "Financials", "Agricultural Income", "Property Income", "Banking"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/incomeSourceCapture/incomeSourceCapture.js",
    ),
    (
        "Income",
        "Property Area Unit",
        ["Acre", "Sq Ft", "Cent"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/incomeSourceCapture/incomeSourceCapture.js",
    ),
    (
        "Income",
        "Property Type",
        ["Residential", "Commercial", "Agricultural"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/incomeSourceCapture/incomeSourceCapture.js",
    ),
    (
        "Income",
        "Property Ownership",
        ["Self", "Joint", "Family"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/incomeSourceCapture/incomeSourceCapture.js",
    ),
    (
        "Repayment",
        "Repayment Party",
        ["Borrower", "Co-borrower", "Beneficiary"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/repaymentMandate/repaymentMandate.js",
    ),
    (
        "Repayment",
        "Repayment Method",
        ["e-NACH", "e-SIGN", "SI", "IES", "UPI Autopay", "Cash"],
        "Hardcoded UI reference",
        "Confirm canonical values and product applicability",
        "force-app/main/default/lwc/repaymentMandate/repaymentMandate.js",
    ),
    (
        "Repayment",
        "Authentication Method",
        ["OTP", "Bio-Metric"],
        "Hardcoded UI reference",
        "Confirm canonical labels",
        "force-app/main/default/lwc/repaymentMandate/repaymentMandate.js",
    ),
    (
        "Repayment",
        "Bank Account Type",
        ["Savings", "Current", "Cash Credit", "NRE", "NRO"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/repaymentMandate/repaymentMandate.js",
    ),
    (
        "Viability",
        "Usage Basis",
        ["Hourly", "KMS"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/viabilityCheck/picklistValuesHelper.js",
    ),
    (
        "Viability",
        "Equipment Segment",
        ["Earth Moving", "Material Handling", "Road Construction"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/viabilityCheck/picklistValuesHelper.js",
    ),
    (
        "Viability",
        "Route Type",
        ["Inter State", "Within State", "Local"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/viabilityCheck/picklistValuesHelper.js",
    ),
    (
        "Personal Discussion",
        "PD Mode",
        ["Residence", "Office", "Telephone", "Video"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/pdScreen/pdScreenConstants.js",
    ),
    (
        "Personal Discussion",
        "PD Status",
        ["Initiated", "In Progress", "Completed", "Rejected", "Accepted"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/pdScreen/pdScreenConstants.js",
    ),
    (
        "Personal Discussion",
        "PD Recommendation",
        ["Recommended", "Not Recommended", "Conditional"],
        "Hardcoded UI reference",
        "Confirm canonical values",
        "force-app/main/default/lwc/pdScreen/pdScreenConstants.js",
    ),
    (
        "Valuation",
        "Valuer Company Fallback",
        ["Empanelled", "MFC", "Adroit", "TVS Credit", "Car Dekho"],
        "Fallback/sample UI data; not a proven master",
        "Provide authoritative valuer master or approve fallback",
        "force-app/main/default/lwc/valuation/valuation.js",
    ),
    (
        "Valuation",
        "Valuer Fallback",
        ["Valuer A", "Valuer B"],
        "Fallback/sample UI data; not a proven master",
        "Provide authoritative valuer list",
        "force-app/main/default/lwc/valuation/valuation.js",
    ),
    (
        "Vehicle",
        "Dealer Fallback Examples",
        ["ABC Motors", "City Auto Hub", "Prime Wheels"],
        "Fallback/sample UI data; not proven Dealer Master records",
        "Replace with Dealer Master data",
        "force-app/main/default/lwc/vehicleDetailsMasterPage/picklistValuesHelper.js",
    ),
    (
        "Vehicle",
        "MMV Make Fallback Examples",
        ["Tata", "Ashok Leyland", "Mahindra"],
        "Fallback/sample UI data; not proven MMV records",
        "Replace with MMV Product Master data",
        "force-app/main/default/lwc/mmvMasterData/mmvMasterData.js",
    ),
]


@dataclass
class Choice:
    value: str
    label: str
    is_default: bool = False
    active: bool = True
    controlling_values: list[str] = field(default_factory=list)


@dataclass
class FieldDef:
    object_api: str
    api_name: str
    label: str
    field_type: str
    required: bool
    length: str = ""
    precision: str = ""
    scale: str = ""
    external_id: bool = False
    unique: bool = False
    default_value: str = ""
    description: str = ""
    help_text: str = ""
    formula: str = ""
    reference_to: str = ""
    relationship_name: str = ""
    value_set_name: str = ""
    restricted: str = ""
    controlling_field: str = ""
    choices: list[Choice] = field(default_factory=list)
    source_path: str = ""

    @property
    def client_supplies(self) -> bool:
        return self.field_type not in {
            "AutoNumber",
            "Formula",
            "RollUpSummary",
            "Summary",
        } and not bool(self.formula)

    @property
    def allowed_or_format(self) -> str:
        if self.choices:
            return "; ".join(
                f"{choice.label} [{choice.value}]"
                if choice.label != choice.value
                else choice.value
                for choice in self.choices
                if choice.active
            )
        if self.value_set_name:
            return f"Global value set: {self.value_set_name}"
        if self.field_type in {"Text", "EncryptedText", "Email", "Phone", "Url"} and self.length:
            return f"Maximum {self.length} characters"
        if self.field_type in {"Number", "Currency", "Percent"}:
            precision_scale = "/".join(filter(None, [self.precision, self.scale]))
            return f"Precision/scale: {precision_scale}" if precision_scale else ""
        if self.field_type in {"Lookup", "MasterDetail", "MetadataRelationship"}:
            return f"Reference to {self.reference_to}" if self.reference_to else "Reference value"
        if self.field_type == "Checkbox":
            return "TRUE or FALSE"
        if self.field_type == "Date":
            return "YYYY-MM-DD"
        if self.field_type == "DateTime":
            return "ISO 8601 date-time"
        return ""


@dataclass
class ObjectDef:
    api_name: str
    label: str
    plural_label: str
    category: str
    owner: str
    client_action: str
    purpose: str
    fields: list[FieldDef]
    name_label: str = "Name"
    name_type: str = "Text"
    repo_record_count: int = 0
    source_path: str = ""
    sheet_name: str = ""

    @property
    def is_custom_metadata(self) -> bool:
        return self.api_name.endswith("__mdt")

    @property
    def usage_status(self) -> str:
        if self.api_name in ACTIVE_USAGE:
            return "Active runtime usage found"
        if self.api_name in RELATIONSHIP_BACKED:
            return "Relationship-backed / indirect usage"
        if self.api_name in CONFIRM_RUNTIME:
            return "Definition present; runtime/ownership confirmation required"
        if self.api_name in DORMANT_OR_OPTIONAL:
            return "Apparently dormant, incomplete, or optional"
        return "Repository definition present"

    @property
    def handling(self) -> str:
        if self.api_name in RESTRICTED_CONFIG:
            return "Restricted: do not populate or transmit values in this workbook"
        if self.category == "Business master":
            return "Client data-supply sheet"
        if self.api_name in CONFIRM_RUNTIME:
            return "Client confirmation before use"
        if self.api_name in DORMANT_OR_OPTIONAL:
            return "Optional; confirm scope before use"
        return "Technical/admin review"


def text(element: ET.Element | None, path: str, default: str = "") -> str:
    if element is None:
        return default
    found = element.find(path, NS)
    if found is None or found.text is None:
        return default
    return found.text.strip()


def texts(element: ET.Element | None, path: str) -> list[str]:
    if element is None:
        return []
    return [
        node.text.strip()
        for node in element.findall(path, NS)
        if node.text is not None and node.text.strip()
    ]


def as_bool(value: str) -> bool:
    return value.lower() == "true"


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def parse_field(path: Path, object_api: str) -> FieldDef:
    root = ET.parse(path).getroot()
    api_name = text(root, "sf:fullName", path.name.replace(".field-meta.xml", ""))
    field_type = text(root, "sf:type")
    formula = text(root, "sf:formula")
    if formula and not field_type:
        field_type = "Formula"
    if not field_type:
        field_type = STANDARD_FIELD_TYPE_OVERRIDES.get(
            (object_api, api_name),
            "Unknown",
        )

    value_set = root.find("sf:valueSet", NS)
    choices: list[Choice] = []
    controlling_field = ""
    value_set_name = ""
    restricted = ""

    if value_set is not None:
        controlling_field = text(value_set, "sf:controllingField")
        value_set_name = text(value_set, "sf:valueSetName")
        restricted = text(value_set, "sf:restricted")

        controls_by_value: dict[str, list[str]] = defaultdict(list)
        for setting in value_set.findall("sf:valueSettings", NS):
            value_name = text(setting, "sf:valueName")
            controls_by_value[value_name].extend(
                texts(setting, "sf:controllingFieldValue")
            )

        for item in value_set.findall("sf:valueSetDefinition/sf:value", NS):
            api_value = text(item, "sf:fullName")
            choices.append(
                Choice(
                    value=api_value,
                    label=text(item, "sf:label", api_value),
                    is_default=as_bool(text(item, "sf:default")),
                    active=not text(item, "sf:isActive")
                    or as_bool(text(item, "sf:isActive")),
                    controlling_values=controls_by_value.get(api_value, []),
                )
            )

    return FieldDef(
        object_api=object_api,
        api_name=api_name,
        label=text(root, "sf:label", path.stem.replace(".field-meta", "")),
        field_type=field_type,
        required=as_bool(text(root, "sf:required")),
        length=text(root, "sf:length"),
        precision=text(root, "sf:precision"),
        scale=text(root, "sf:scale"),
        external_id=as_bool(text(root, "sf:externalId")),
        unique=as_bool(text(root, "sf:unique")),
        default_value=text(root, "sf:defaultValue"),
        description=text(root, "sf:description"),
        help_text=text(root, "sf:inlineHelpText"),
        formula=formula,
        reference_to=", ".join(texts(root, "sf:referenceTo")),
        relationship_name=text(root, "sf:relationshipName"),
        value_set_name=value_set_name,
        restricted=restricted,
        controlling_field=controlling_field,
        choices=choices,
        source_path=relative(path),
    )


def parse_object(api_name: str, category: str, owner: str, action: str) -> ObjectDef:
    object_dir = OBJECTS_ROOT / api_name
    object_path = object_dir / f"{api_name}.object-meta.xml"
    root = ET.parse(object_path).getroot()
    allowlist = OBJECT_FIELD_ALLOWLIST.get(api_name)
    fields = [
        parse_field(path, api_name)
        for path in sorted((object_dir / "fields").glob("*.field-meta.xml"))
        if allowlist is None
        or path.name.replace(".field-meta.xml", "") in allowlist
    ] if (object_dir / "fields").exists() else []

    return ObjectDef(
        api_name=api_name,
        label=DISPLAY_LABEL_OVERRIDES.get(
            api_name,
            text(root, "sf:label", api_name),
        ),
        plural_label=DISPLAY_LABEL_OVERRIDES.get(
            api_name,
            text(root, "sf:pluralLabel", text(root, "sf:label", api_name)),
        ),
        category=category,
        owner=owner,
        client_action=action,
        purpose=PURPOSES.get(api_name, f"Reference/configuration structure for {api_name}."),
        fields=fields,
        name_label=text(root, "sf:nameField/sf:label", "Name"),
        name_type=text(root, "sf:nameField/sf:type", "Text"),
        source_path=relative(object_path),
    )


def custom_metadata_record_counts(valid_types: set[str]) -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    if not CUSTOM_METADATA_ROOT.exists():
        return counts
    for path in CUSTOM_METADATA_ROOT.glob("*.md-meta.xml"):
        type_name = path.name.split(".", 1)[0] + "__mdt"
        if type_name in valid_types:
            counts[type_name] += 1
    return counts


def collect_objects() -> list[ObjectDef]:
    result: list[ObjectDef] = []

    for api_name in sorted(BUSINESS_MASTERS):
        if (OBJECTS_ROOT / api_name / f"{api_name}.object-meta.xml").exists():
            result.append(
                parse_object(
                    api_name,
                    "Business master",
                    "Client business/data owner",
                    "Provide and validate records",
                )
            )

    for api_name in sorted(CONFIG_OBJECTS):
        if (OBJECTS_ROOT / api_name / f"{api_name}.object-meta.xml").exists():
            result.append(
                parse_object(
                    api_name,
                    "Configuration object",
                    "Client administrator + Moga technical team",
                    "Review and provide only environment-specific configuration",
                )
            )

    for api_name in sorted(CUSTOM_SETTINGS):
        if (OBJECTS_ROOT / api_name / f"{api_name}.object-meta.xml").exists():
            result.append(
                parse_object(
                    api_name,
                    "Hierarchy custom setting",
                    "Moga technical administrator",
                    "Review; do not treat as routine business master upload",
                )
            )

    metadata_types = {
        path.parent.name
        for path in OBJECTS_ROOT.glob("*__mdt/*__mdt.object-meta.xml")
        if not path.parent.name.startswith(MANAGED_PREFIXES)
    }
    counts = custom_metadata_record_counts(metadata_types)
    for api_name in sorted(metadata_types):
        if api_name in RESTRICTED_CONFIG:
            category = "Custom metadata — Restricted technical"
            owner = "Moga security/technical administrator"
            action = "Do not populate values in this workbook; use an approved secure channel"
        elif api_name in CONFIRM_RUNTIME:
            category = "Custom metadata — Confirm runtime"
            owner = "Client functional owner + Moga technical team"
            action = "Confirm ownership and consuming runtime before supplying values"
        elif api_name in DORMANT_OR_OPTIONAL:
            category = "Custom metadata — Optional/dormant"
            owner = "Moga technical administrator"
            action = "Confirm scope; do not treat as authoritative until runtime use is established"
        elif api_name in {
            "Search_Config__mdt",
            "QC_Admin_Console__mdt",
            "User_Product_Record_Tyoe_Mapping__mdt",
        }:
            category = "Custom metadata — Technical configuration"
            owner = "Client administrator + Moga technical team"
            action = "Review/confirm with API-name validation"
        else:
            category = "Custom metadata — Core business configuration"
            owner = "Client functional administrator + Moga technical team"
            action = "Provide/review configuration under controlled deployment"
        item = parse_object(
            api_name,
            category,
            owner,
            action,
        )
        item.repo_record_count = counts.get(api_name, 0)
        result.append(item)

    return result


def is_moga_field(path: Path, object_api: str) -> bool:
    api_name = path.name.replace(".field-meta.xml", "")
    if object_api in BUSINESS_MASTERS | CONFIG_OBJECTS | CUSTOM_SETTINGS:
        return True
    if object_api.endswith(("__c", "__mdt")):
        return True
    return api_name.endswith("__c") and "__" not in api_name[:-3]


def collect_picklists() -> list[FieldDef]:
    fields: list[FieldDef] = []
    for object_dir in sorted(path for path in OBJECTS_ROOT.iterdir() if path.is_dir()):
        object_api = object_dir.name
        if object_api.startswith(MANAGED_PREFIXES):
            continue
        fields_dir = object_dir / "fields"
        if not fields_dir.exists():
            continue
        allowlist = OBJECT_FIELD_ALLOWLIST.get(object_api)
        for path in sorted(fields_dir.glob("*.field-meta.xml")):
            api_name = path.name.replace(".field-meta.xml", "")
            if allowlist is not None and api_name not in allowlist:
                continue
            if not is_moga_field(path, object_api):
                continue
            parsed = parse_field(path, object_api)
            if parsed.field_type in {"Picklist", "MultiselectPicklist"}:
                fields.append(parsed)
    return fields


def safe_sheet_name(prefix: str, label: str, used: set[str]) -> str:
    base = re.sub(r"[\[\]:*?/\\]", " ", label)
    base = re.sub(r"\s+", " ", base).strip()
    candidate = f"{prefix}_{base}"[:31]
    if candidate not in used:
        used.add(candidate)
        return candidate
    counter = 2
    while True:
        suffix = f"_{counter}"
        candidate = f"{prefix}_{base}"[: 31 - len(suffix)] + suffix
        if candidate not in used:
            used.add(candidate)
            return candidate
        counter += 1


def sample_value(field_def: FieldDef, row_number: int = 1) -> object:
    api = field_def.api_name.lower()
    label = field_def.label.lower()
    field_type = field_def.field_type

    if not field_def.client_supplies:
        return ""
    if field_def.choices:
        active = [choice for choice in field_def.choices if choice.active]
        if active:
            default = next((choice for choice in active if choice.is_default), None)
            return (default or active[(row_number - 1) % len(active)]).value
    if field_type == "Checkbox":
        return row_number == 1
    if field_type == "Date":
        return date(2026, 4, min(row_number, 28))
    if field_type == "DateTime":
        return f"2026-04-{row_number:02d}T09:00:00Z"
    if field_type in {"Number", "Currency"}:
        return 1000 * row_number
    if field_type == "Percent":
        return 10 * row_number
    if field_type in {"Lookup", "MasterDetail", "MetadataRelationship"}:
        target = field_def.reference_to or "parent"
        return f"<{target} external key>"
    if field_type == "Email" or "email" in api:
        return f"sample{row_number}@example.com"
    if field_type == "Phone" or any(token in api for token in ("phone", "mobile")):
        return f"99999999{row_number:02d}"
    if field_type == "Url" or "url" in api or "endpoint" in api:
        return f"https://example.invalid/service/{row_number}"
    if field_type == "EncryptedText" or any(
        token in api for token in ("secret", "password", "private_key")
    ):
        return "<provide through approved secure channel>"
    if "pincode" in api or "postal" in api:
        return f"4000{row_number:02d}"
    if "ifsc" in api:
        return f"EXAMP00000{row_number}"
    if "email" in label:
        return f"sample{row_number}@example.com"
    if any(token in api for token in ("code", "key", "external_id", "developername")):
        return f"SAMPLE{row_number:03d}"
    if "name" in api or "name" in label:
        return f"Sample {field_def.label} {row_number}"
    if "address" in api or "address" in label:
        return f"{row_number} Sample Road, Example City"
    if field_type in {"LongTextArea", "Html"}:
        return f"Sample {field_def.label} for client replacement."
    if field_type == "TextArea":
        return f"Sample {field_def.label}"
    return f"Sample {field_def.label} {row_number}"


def synthetic_columns(obj: ObjectDef) -> list[tuple[str, str, FieldDef | None]]:
    columns: list[tuple[str, str, FieldDef | None]] = []
    field_api_names = {item.api_name for item in obj.fields}
    if obj.is_custom_metadata:
        columns.extend(
            [
                ("DeveloperName", "Developer Name", None),
                ("MasterLabel", "Master Label", None),
            ]
        )
    elif obj.category == "Hierarchy custom setting":
        columns.append(("SetupOwner", "Setup Owner (Org/Profile/User)", None))
    elif obj.name_type not in {"AutoNumber"} and "Name" not in field_api_names:
        columns.append(("Name", obj.name_label, None))

    for item in obj.fields:
        if item.client_supplies:
            columns.append((item.api_name, item.label, item))
    return columns


THIN_GREY = Side(style="thin", color="B7B7B7")
BORDER = Border(left=THIN_GREY, right=THIN_GREY, top=THIN_GREY, bottom=THIN_GREY)
NAVY = "17365D"
BLUE = "D9EAF7"
LIGHT_BLUE = "EAF3F8"
GREY = "E7E6E6"
LIGHT_GREY = "F3F3F3"
WHITE = "FFFFFF"
YELLOW = "FFF2CC"
GREEN = "E2F0D9"
RED = "FCE4D6"


def style_header(cell, fill: str = NAVY) -> None:
    cell.fill = PatternFill("solid", fgColor=fill)
    cell.font = Font(color=WHITE, bold=True)
    cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    cell.border = BORDER


def style_body(cell, wrap: bool = True) -> None:
    cell.alignment = Alignment(vertical="top", wrap_text=wrap)
    cell.border = BORDER


def add_table(ws, ref: str, name: str) -> None:
    table = Table(displayName=re.sub(r"[^A-Za-z0-9_]", "_", name), ref=ref)
    table.tableStyleInfo = TableStyleInfo(
        name="TableStyleMedium2",
        showFirstColumn=False,
        showLastColumn=False,
        showRowStripes=True,
        showColumnStripes=False,
    )
    ws.add_table(table)


def set_widths(ws, widths: dict[int, float], default: float = 18) -> None:
    for index in range(1, ws.max_column + 1):
        ws.column_dimensions[get_column_letter(index)].width = widths.get(index, default)


def add_title(ws, title: str, subtitle: str, max_column: int) -> None:
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=max_column)
    title_cell = ws.cell(1, 1, title)
    title_cell.fill = PatternFill("solid", fgColor=NAVY)
    title_cell.font = Font(color=WHITE, bold=True, size=16)
    title_cell.alignment = Alignment(vertical="center")
    ws.row_dimensions[1].height = 28

    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=max_column)
    subtitle_cell = ws.cell(2, 1, subtitle)
    subtitle_cell.fill = PatternFill("solid", fgColor=LIGHT_BLUE)
    subtitle_cell.alignment = Alignment(wrap_text=True, vertical="top")
    ws.row_dimensions[2].height = 42


def write_readme(wb: Workbook, objects: list[ObjectDef], picklists: list[FieldDef]) -> None:
    ws = wb.active
    ws.title = "README"
    add_title(
        ws,
        "Moga Dev Master Data Client Template",
        "Repository-derived structure for client data preparation. Sample rows are synthetic and must be replaced.",
        4,
    )

    business_count = sum(item.category == "Business master" for item in objects)
    metadata_count = sum(item.is_custom_metadata for item in objects)
    config_count = len(objects) - business_count - metadata_count
    picklist_value_count = sum(len(item.choices) for item in picklists)
    static_ui_value_count = sum(
        len(values)
        for _, _, values, _, _, _ in STATIC_UI_REFERENCE_GROUPS
    )

    sections = [
        ("Purpose", "Provide the client with the repository-backed field structure, allowed values, dependencies, and safe sample rows for all Moga LOS reference-data categories requested."),
        ("Scope", "Entire Moga Dev Salesforce LOS repository: business master objects, configuration objects, hierarchy custom settings, unmanaged Moga custom metadata, and Moga custom picklist/dependent-picklist definitions."),
        ("Business master sheets", str(business_count)),
        ("Configuration/custom-setting sheets", str(config_count)),
        ("Custom metadata type sheets", str(metadata_count)),
        ("Picklist fields", str(len(picklists))),
        ("Picklist values", str(picklist_value_count)),
        ("Static/fallback UI values", str(static_ui_value_count)),
        ("Sample-data policy", "All sample rows were generated synthetically from field types and labels. No records were queried from the Moga Dev org."),
        ("How the client should use this", "1) Review Master Catalog and Open Items. 2) Populate BM_* sheets. 3) Confirm Picklist Values and Static UI References. 4) Review CFG_*/CMD_* sheets with technical owners. 5) Return the workbook without changing API-name headers."),
        ("Required columns", "Headers with yellow fill are required by Salesforce metadata. Business-requiredness may be stricter and should be confirmed by the functional owner."),
        ("Lookup/reference columns", "Replace placeholders such as <State_Master__c external key> with an agreed external key or Salesforce ID during migration design."),
        ("Sensitive configuration", "Do not place production secrets, passwords, JWT keys, or private endpoints in an emailed workbook. Supply them through an approved secure channel."),
        ("Important limitation", "The repository contains schema/configuration metadata, not business-master records. Usage evidence can show that a master exists, but it cannot prove production record completeness or current org-only values."),
    ]
    start = 4
    for row, (heading, content) in enumerate(sections, start=start):
        ws.cell(row, 1, heading)
        ws.cell(row, 2, content)
        ws.merge_cells(start_row=row, start_column=2, end_row=row, end_column=4)
        style_header(ws.cell(row, 1), NAVY if row in {start, start + 1} else GREY)
        if row not in {start, start + 1}:
            ws.cell(row, 1).font = Font(color="000000", bold=True)
        style_body(ws.cell(row, 2))
        for col in (3, 4):
            style_body(ws.cell(row, col))
        ws.row_dimensions[row].height = 34

    ws.sheet_view.showGridLines = False
    ws.freeze_panes = "A4"
    set_widths(ws, {1: 30, 2: 34, 3: 28, 4: 28})


def write_catalog(wb: Workbook, objects: list[ObjectDef], picklists: list[FieldDef]) -> None:
    ws = wb.create_sheet("Master Catalog")
    headers = [
        "Seq",
        "Master / Reference Name",
        "API Name",
        "Category",
        "Usage Status",
        "Handling",
        "Ownership",
        "Client Action",
        "Repository Record Count",
        "Field Count",
        "Required Fields",
        "Dependencies",
        "Data Sheet",
        "Purpose",
        "Source",
    ]
    add_title(
        ws,
        "Master and Reference Catalog",
        "Start here. Business masters are normal client data-supply candidates; technical configuration must be reviewed with the implementation team.",
        len(headers),
    )
    header_row = 4
    for col, header in enumerate(headers, 1):
        ws.cell(header_row, col, header)
        style_header(ws.cell(header_row, col))

    for seq, item in enumerate(objects, 1):
        dependencies = sorted(
            {
                field_def.reference_to
                for field_def in item.fields
                if field_def.reference_to
            }
        )
        required = [
            field_def.label for field_def in item.fields if field_def.required
        ]
        values = [
            seq,
            item.label,
            item.api_name,
            item.category,
            item.usage_status,
            item.handling,
            item.owner,
            item.client_action,
            item.repo_record_count
            if item.is_custom_metadata
            else "Not stored in source",
            len(item.fields),
            ", ".join(required) or "None marked required in metadata",
            ", ".join(dependencies) or "None declared",
            item.sheet_name,
            item.purpose,
            item.source_path,
        ]
        row = header_row + seq
        for col, value in enumerate(values, 1):
            ws.cell(row, col, value)
            style_body(ws.cell(row, col))
        if item.category == "Business master":
            ws.cell(row, 4).fill = PatternFill("solid", fgColor=GREEN)
        elif item.is_custom_metadata:
            ws.cell(row, 4).fill = PatternFill("solid", fgColor=BLUE)
        else:
            ws.cell(row, 4).fill = PatternFill("solid", fgColor=YELLOW)

    summary_row = header_row + len(objects) + 1
    values = [
        len(objects) + 1,
        "Moga Custom Picklists",
        "Multiple objects/fields",
        "Picklist and dependent-picklist reference",
        "Active metadata source",
        "Client confirmation",
        "Client functional owner + Moga administrator",
        "Confirm labels, stored values, defaults, and dependencies",
        "Values are stored in metadata",
        len(picklists),
        "",
        "See Picklist Dependencies",
        "Picklist Values",
        "Allowed values for Moga custom fields across custom and standard objects.",
        "force-app/main/default/objects/**/fields",
    ]
    for col, value in enumerate(values, 1):
        ws.cell(summary_row, col, value)
        style_body(ws.cell(summary_row, col))
    ws.cell(summary_row, 4).fill = PatternFill("solid", fgColor=LIGHT_BLUE)

    static_row = summary_row + 1
    static_count = sum(
        len(group_values)
        for _, _, group_values, _, _, _ in STATIC_UI_REFERENCE_GROUPS
    )
    values = [
        len(objects) + 2,
        "Static / Fallback UI References",
        "Multiple LWC and requirements sources",
        "Code-defined reference values",
        "Active UI source; some values are fallback/sample only",
        "Client confirmation",
        "Client functional owner + Moga administrator",
        "Confirm or replace with governed master data",
        "Values are stored in code/requirements",
        static_count,
        "",
        "See source and authority per row",
        "Static UI References",
        "Implemented option arrays not backed by a retrieved master or picklist definition.",
        "force-app/main/default/lwc and requirements Markdown",
    ]
    for col, value in enumerate(values, 1):
        ws.cell(static_row, col, value)
        style_body(ws.cell(static_row, col))
    ws.cell(static_row, 4).fill = PatternFill("solid", fgColor=YELLOW)

    add_table(
        ws,
        f"A{header_row}:O{static_row}",
        "Master_Catalog_Table",
    )
    ws.freeze_panes = "A5"
    ws.auto_filter.ref = f"A{header_row}:O{static_row}"
    ws.sheet_view.showGridLines = False
    set_widths(
        ws,
        {
            1: 8,
            2: 28,
            3: 37,
            4: 30,
            5: 39,
            6: 44,
            7: 31,
            8: 40,
            9: 21,
            10: 12,
            11: 34,
            12: 31,
            13: 31,
            14: 55,
            15: 55,
        },
    )


def write_field_dictionary(wb: Workbook, objects: list[ObjectDef]) -> None:
    ws = wb.create_sheet("Field Dictionary")
    headers = [
        "Master / Configuration",
        "Object API Name",
        "Category",
        "Field Label",
        "Field API Name",
        "Field Type",
        "Client Supplies?",
        "Required in Metadata?",
        "External ID?",
        "Unique?",
        "Length",
        "Precision",
        "Scale",
        "Default",
        "Allowed Values / Format",
        "Reference To",
        "Controlling Field",
        "Description / Help",
        "Formula",
        "Source",
    ]
    add_title(
        ws,
        "Master Field Dictionary",
        "Technical field structure for every included master/configuration source. Use the individual data sheets for client data entry.",
        len(headers),
    )
    header_row = 4
    for col, header in enumerate(headers, 1):
        ws.cell(header_row, col, header)
        style_header(ws.cell(header_row, col))

    row = header_row + 1
    for item in objects:
        field_api_names = {field_def.api_name for field_def in item.fields}
        if item.is_custom_metadata:
            identity = (
                "DeveloperName / MasterLabel",
                "DeveloperName / MasterLabel",
                "Text",
                True,
            )
        elif item.category == "Hierarchy custom setting":
            identity = ("Setup Owner", "SetupOwner", "Hierarchy owner", True)
        elif "Name" not in field_api_names:
            identity = (
                item.name_label,
                "Name",
                item.name_type,
                item.name_type != "AutoNumber",
            )
        else:
            identity = None

        if identity:
            ws.cell(row, 1, item.label)
            ws.cell(row, 2, item.api_name)
            ws.cell(row, 3, item.category)
            ws.cell(row, 4, identity[0])
            ws.cell(row, 5, identity[1])
            ws.cell(row, 6, identity[2])
            ws.cell(
                row,
                7,
                "No — secure channel"
                if item.api_name in RESTRICTED_CONFIG
                else ("Yes" if identity[3] else "No"),
            )
            ws.cell(row, 8, "Yes" if item.is_custom_metadata else "No")
            ws.cell(row, 18, "Salesforce record identity/owner field.")
            ws.cell(row, 20, item.source_path)
            for col in range(1, len(headers) + 1):
                style_body(ws.cell(row, col))
            row += 1

        for field_def in item.fields:
            values = [
                item.label,
                item.api_name,
                item.category,
                field_def.label,
                field_def.api_name,
                field_def.field_type,
                "No — secure channel"
                if item.api_name in RESTRICTED_CONFIG
                else ("Yes" if field_def.client_supplies else "No"),
                "Yes" if field_def.required else "No",
                "Yes" if field_def.external_id else "No",
                "Yes" if field_def.unique else "No",
                field_def.length,
                field_def.precision,
                field_def.scale,
                field_def.default_value,
                field_def.allowed_or_format,
                field_def.reference_to,
                field_def.controlling_field,
                " ".join(filter(None, [field_def.description, field_def.help_text])),
                field_def.formula,
                field_def.source_path,
            ]
            for col, value in enumerate(values, 1):
                ws.cell(row, col, value)
                style_body(ws.cell(row, col))
            if field_def.required:
                ws.cell(row, 8).fill = PatternFill("solid", fgColor=YELLOW)
            if not field_def.client_supplies:
                ws.cell(row, 7).fill = PatternFill("solid", fgColor=GREY)
            row += 1

    add_table(
        ws,
        f"A{header_row}:T{row - 1}",
        "Master_Field_Dictionary_Table",
    )
    ws.freeze_panes = "D5"
    ws.auto_filter.ref = f"A{header_row}:T{row - 1}"
    ws.sheet_view.showGridLines = False
    set_widths(
        ws,
        {
            1: 29,
            2: 37,
            3: 27,
            4: 28,
            5: 40,
            6: 20,
            7: 16,
            8: 20,
            9: 13,
            10: 10,
            11: 10,
            12: 11,
            13: 8,
            14: 23,
            15: 58,
            16: 35,
            17: 31,
            18: 55,
            19: 40,
            20: 60,
        },
    )


def write_picklists(wb: Workbook, picklists: list[FieldDef]) -> None:
    ws = wb.create_sheet("Picklist Values")
    headers = [
        "Object API Name",
        "Field Label",
        "Field API Name",
        "Field Type",
        "Restricted?",
        "Global Value Set",
        "Stored Value",
        "Display Label",
        "Default?",
        "Active?",
        "Controlling Field",
        "Allowed Controlling Value(s)",
        "Client Decision / Replacement",
        "Source",
    ]
    add_title(
        ws,
        "Moga Custom Picklist Values",
        "Repository-defined values. The client should confirm both the user-facing label and stored API value; changing stored values can affect code and integrations.",
        len(headers),
    )
    header_row = 4
    for col, header in enumerate(headers, 1):
        ws.cell(header_row, col, header)
        style_header(ws.cell(header_row, col))

    row = header_row + 1
    for item in picklists:
        if item.choices:
            for choice in item.choices:
                values = [
                    item.object_api,
                    item.label,
                    item.api_name,
                    item.field_type,
                    item.restricted,
                    item.value_set_name,
                    choice.value,
                    choice.label,
                    "Yes" if choice.is_default else "No",
                    "Yes" if choice.active else "No",
                    item.controlling_field,
                    ", ".join(choice.controlling_values),
                    "",
                    item.source_path,
                ]
                for col, value in enumerate(values, 1):
                    ws.cell(row, col, value)
                    style_body(ws.cell(row, col))
                row += 1
        else:
            values = [
                item.object_api,
                item.label,
                item.api_name,
                item.field_type,
                item.restricted,
                item.value_set_name,
                "(Values not present in retrieved field metadata)",
                "",
                "",
                "",
                item.controlling_field,
                "",
                "",
                item.source_path,
            ]
            for col, value in enumerate(values, 1):
                ws.cell(row, col, value)
                style_body(ws.cell(row, col))
            row += 1

    add_table(ws, f"A{header_row}:N{row - 1}", "Picklist_Values_Table")
    ws.freeze_panes = "G5"
    ws.auto_filter.ref = f"A{header_row}:N{row - 1}"
    ws.sheet_view.showGridLines = False
    set_widths(
        ws,
        {
            1: 33,
            2: 28,
            3: 39,
            4: 20,
            5: 12,
            6: 28,
            7: 38,
            8: 38,
            9: 11,
            10: 10,
            11: 32,
            12: 48,
            13: 40,
            14: 65,
        },
    )


def write_dependencies(
    wb: Workbook, objects: list[ObjectDef], picklists: list[FieldDef]
) -> None:
    ws = wb.create_sheet("Dependencies")
    headers = [
        "Dependency Type",
        "Child Object / Type",
        "Child Field",
        "Parent / Controller",
        "Allowed / Relationship Detail",
        "Source",
    ]
    add_title(
        ws,
        "Master and Picklist Dependencies",
        "Load parent masters before child masters. Picklist dependencies must preserve controlling-field combinations.",
        len(headers),
    )
    header_row = 4
    for col, header in enumerate(headers, 1):
        ws.cell(header_row, col, header)
        style_header(ws.cell(header_row, col))

    rows: list[list[object]] = []
    for item in objects:
        for field_def in item.fields:
            if field_def.reference_to:
                rows.append(
                    [
                        "Object relationship",
                        item.api_name,
                        field_def.api_name,
                        field_def.reference_to,
                        f"{field_def.field_type}; relationship name: {field_def.relationship_name}",
                        field_def.source_path,
                    ]
                )
            if field_def.controlling_field:
                details = []
                for choice in field_def.choices:
                    if choice.controlling_values:
                        details.append(
                            f"{choice.value} <= {', '.join(choice.controlling_values)}"
                        )
                rows.append(
                    [
                        "Dependent picklist",
                        item.api_name,
                        field_def.api_name,
                        field_def.controlling_field,
                        "; ".join(details),
                        field_def.source_path,
                    ]
                )

    object_field_keys = {
        (item.api_name, field_def.api_name)
        for item in objects
        for field_def in item.fields
    }
    for field_def in picklists:
        if (
            field_def.controlling_field
            and (field_def.object_api, field_def.api_name) not in object_field_keys
        ):
            details = []
            for choice in field_def.choices:
                if choice.controlling_values:
                    details.append(
                        f"{choice.value} <= {', '.join(choice.controlling_values)}"
                    )
            rows.append(
                [
                    "Dependent picklist",
                    field_def.object_api,
                    field_def.api_name,
                    field_def.controlling_field,
                    "; ".join(details),
                    field_def.source_path,
                ]
            )

    for row_offset, values in enumerate(rows, header_row + 1):
        for col, value in enumerate(values, 1):
            ws.cell(row_offset, col, value)
            style_body(ws.cell(row_offset, col))

    last_row = max(header_row + 1, header_row + len(rows))
    if not rows:
        ws.cell(header_row + 1, 1, "No declared dependencies found")
        for col in range(1, len(headers) + 1):
            style_body(ws.cell(header_row + 1, col))
    add_table(ws, f"A{header_row}:F{last_row}", "Dependencies_Table")
    ws.freeze_panes = "A5"
    ws.auto_filter.ref = f"A{header_row}:F{last_row}"
    ws.sheet_view.showGridLines = False
    set_widths(ws, {1: 24, 2: 37, 3: 41, 4: 37, 5: 70, 6: 65})


def write_static_ui_references(wb: Workbook) -> None:
    ws = wb.create_sheet("Static UI References")
    headers = [
        "Domain",
        "Reference Set",
        "Implemented Value",
        "Source / Authority",
        "Client Action",
        "Client Replacement / Decision",
        "Source",
    ]
    add_title(
        ws,
        "Static and Fallback UI Reference Values",
        "These values are implemented outside Salesforce master records/picklist metadata. Fallback/sample entries are not proven production master data.",
        len(headers),
    )
    header_row = 4
    for col, header in enumerate(headers, 1):
        ws.cell(header_row, col, header)
        style_header(ws.cell(header_row, col))

    row = header_row + 1
    for domain, reference_set, values, authority, action, source in STATIC_UI_REFERENCE_GROUPS:
        for value in values:
            row_values = [
                domain,
                reference_set,
                value,
                authority,
                action,
                "",
                source,
            ]
            for col, item in enumerate(row_values, 1):
                ws.cell(row, col, item)
                style_body(ws.cell(row, col))
            if "Fallback/sample" in authority:
                ws.cell(row, 4).fill = PatternFill("solid", fgColor=YELLOW)
            row += 1

    add_table(
        ws,
        f"A{header_row}:G{row - 1}",
        "Static_UI_References_Table",
    )
    ws.freeze_panes = "C5"
    ws.auto_filter.ref = f"A{header_row}:G{row - 1}"
    ws.sheet_view.showGridLines = False
    set_widths(ws, {1: 24, 2: 34, 3: 36, 4: 49, 5: 53, 6: 44, 7: 75})


def write_coverage_notes(
    wb: Workbook, objects: list[ObjectDef], picklists: list[FieldDef]
) -> None:
    ws = wb.create_sheet("Coverage Notes")
    headers = ["Topic", "Included / Excluded", "Rationale", "Client Follow-up"]
    add_title(
        ws,
        "Coverage and Assumptions",
        "These boundaries prevent Salesforce platform artifacts and transactional tables from being misrepresented as client-owned masters.",
        len(headers),
    )
    header_row = 4
    for col, header in enumerate(headers, 1):
        ws.cell(header_row, col, header)
        style_header(ws.cell(header_row, col))

    rows = [
        [
            "Business master objects",
            "Included",
            "Explicit *Master* objects plus repository-evidenced catalogues such as Industry Code and Type, Schemes, Manufacturer, Corporate Probe42 Entity, Agency Pincode, and supporting Product2.",
            "Provide data rows and confirm ownership/refresh cadence.",
        ],
        [
            "Configuration custom objects",
            "Included separately",
            "Dashboard Configuration and PDFforceConfig are reference/configuration data but are not routine business-owned masters.",
            "Review with the Moga technical team.",
        ],
        [
            "Custom metadata",
            "Included",
            "All unmanaged Moga custom metadata type schemas are included with repository record counts and synthetic examples.",
            "Confirm environment-specific values and deployment ownership.",
        ],
        [
            "Hierarchy custom settings",
            "Included",
            "TriggerDeactivationSettings is an administrator setting, not normal migration master data.",
            "Review only; do not provide production settings by email.",
        ],
        [
            "Picklists and dependent picklists",
            "Included",
            "All custom picklist fields on Moga custom objects and Moga custom fields on standard objects are included.",
            "Confirm stored values, labels, defaults, and dependency combinations.",
        ],
        [
            "Static/fallback UI reference sets",
            "Included separately",
            "Code and requirements contain implemented option arrays that are not backed by a retrieved master or picklist definition.",
            "Confirm authoritative values and replace fallback/sample options with governed master data.",
        ],
        [
            "Global value sets",
            "None retrieved",
            "No files were present under force-app/main/default/globalValueSets.",
            "Confirm whether any values exist only in the target org and were omitted from source retrieval.",
        ],
        [
            "Managed-package metadata",
            "Excluded",
            "privacycenter__ and datadetect__ custom metadata records are package-owned, not Moga client master data.",
            "Manage through the relevant installed package.",
        ],
        [
            "Standard Salesforce picklists",
            "Excluded unless represented by a Moga custom field or an included supporting master",
            "The repository contains platform/service objects unrelated to the custom LOS. Product2 is included because scheme and ROI masters reference it; unrelated standard platform objects remain excluded.",
            "Add a specific standard-object scope if needed.",
        ],
        [
            "Transactional objects",
            "Excluded from master sheets",
            "Applications, applicants, assets, incomes, documents, integrations logs/checklists, verifications, repayment, disbursement, and approval records are operational transactions.",
            "Use a separate transaction migration specification if required.",
        ],
        [
            "Current org records",
            "Not queried",
            "The requested sample policy was synthetic. Repository source contains schemas and custom metadata records but not business-master record exports.",
            "Run a separate org data extract if actual record profiling or reconciliation is required.",
        ],
        [
            "Synthetic sample rows",
            "Included",
            "Generated from field type, label, picklist default/first value, and safe placeholders. They demonstrate shape, not approved business content.",
            "Replace every sample row before migration.",
        ],
        [
            "Requiredness",
            "Metadata-required flags included",
            "Salesforce metadata requiredness does not capture every UI, validation-rule, or integration requirement.",
            "Functional owners must confirm business mandatory fields.",
        ],
    ]
    for row_index, values in enumerate(rows, header_row + 1):
        for col, value in enumerate(values, 1):
            ws.cell(row_index, col, value)
            style_body(ws.cell(row_index, col))

    add_table(
        ws,
        f"A{header_row}:D{header_row + len(rows)}",
        "Coverage_Notes_Table",
    )
    ws.freeze_panes = "A5"
    ws.sheet_view.showGridLines = False
    set_widths(ws, {1: 34, 2: 23, 3: 75, 4: 57})


def write_open_items(wb: Workbook) -> None:
    ws = wb.create_sheet("Open Items")
    headers = [
        "Priority",
        "Type",
        "Reference / Area",
        "Repository Finding",
        "Impact",
        "Client Input Required",
        "Client Decision / Response",
        "Evidence",
    ]
    add_title(
        ws,
        "Client Decisions and Repository Gaps",
        "Resolve these items before treating the workbook as an import-ready source of truth.",
        len(headers),
    )
    header_row = 4
    for col, header in enumerate(headers, 1):
        ws.cell(header_row, col, header)
        style_header(ws.cell(header_row, col))

    rows = [
        [
            "Critical",
            "Missing definition",
            "Product global value set",
            "Application__c.Product__c references global value set Product, but the definition was not retrieved.",
            "Product controls sub-products, journey routing, documents, queries, dashboards, and integrations.",
            "Provide the approved product stored values, labels, active flags, and defaults; or retrieve the global value set from the target org.",
            "",
            "force-app/main/default/objects/Application__c/fields/Product__c.field-meta.xml",
        ],
        [
            "High",
            "Missing definition",
            "Persona global value set",
            "User.Persona__c references global value set Persona, but the definition was not retrieved.",
            "Persona affects user behavior, dashboard filtering, assignment, and JWT configuration.",
            "Provide approved persona stored values/labels or retrieve the global value set.",
            "",
            "force-app/main/default/objects/User/fields/Persona__c.field-meta.xml",
        ],
        [
            "High",
            "Unretrieved external dependency",
            "BankBranchDetails__c / Geo_State_Master__c",
            "Agreement logic dynamically queries these references, but neither object definition is present under default/objects.",
            "Agreement geography cannot be fully specified from this repository.",
            "Provide schema and sample structure, or retrieve both object definitions and relevant value data.",
            "",
            "force-app/main/default/classes/AgreementController.cls",
        ],
        [
            "High",
            "Vocabulary reconciliation",
            "Product and Sub-Product",
            "Application and Application Line Item use different labels/codes; Apex normalizes variants.",
            "Unmapped values can break dependencies and stage/document rules.",
            "Approve canonical product/sub-product identifiers and an explicit mapping to each Salesforce field value.",
            "",
            "Application__c and Application_Line_Item__c product/sub-product field metadata",
        ],
        [
            "High",
            "Vocabulary reconciliation",
            "Stage / Sub-Stage",
            "Multiple stage picklists overlap with 78 Dynamic Stage Gate rows.",
            "Conflicting stage names can block navigation, parking, queries, and integrations.",
            "Approve canonical main-stage, stage, sub-stage, and stage-path identifiers plus mappings.",
            "",
            "Application__c stage fields and Dynamic_Stage_Gate__mdt",
        ],
        [
            "High",
            "Taxonomy reconciliation",
            "Query Type / Query Sub-Type",
            "Query field dependencies and Query Configuration metadata expose different type/sub-type populations; some subtype mappings are absent.",
            "Users may see unreachable or inconsistent query choices.",
            "Approve the canonical query taxonomy and all valid type/sub-type/stage/product combinations.",
            "",
            "Query__c picklist fields and Query_Configuration__mdt",
        ],
        [
            "Medium",
            "Incomplete reference shell",
            "Agency_Pincode__c",
            "The retrieved object has no custom fields and no runtime reference.",
            "No usable agency-to-pincode structure can be provided from source.",
            "Confirm whether this master is obsolete or provide the missing schema/relationship.",
            "",
            "force-app/main/default/objects/Agency_Pincode__c",
        ],
        [
            "Medium",
            "Runtime ownership confirmation",
            "Deviation and committee metadata",
            "Definitions and records exist, but static runtime use was not found in the retrieved source; some deviation logic appears hardcoded.",
            "Treating these sheets as authoritative may misstate current behavior.",
            "Identify the consuming service or confirm these are future/legacy definitions.",
            "",
            "Deviation_* and Committee_* custom metadata",
        ],
        [
            "Medium",
            "Missing/stale configuration reference",
            "Option_Visibility__mdt",
            "UI comments mention Option Visibility metadata, but no deployed type or records were retrieved and current product options are hardcoded.",
            "The intended source of product-option visibility is unclear.",
            "Confirm whether the metadata was omitted, retired, or should replace the hardcoded options.",
            "",
            "applicantBasicDetailsCapture/pickListValuesHelper.js",
        ],
        [
            "Critical",
            "Secure handling",
            "Encryption and JWT configuration",
            "Schemas are catalogued, but environment values may contain secrets or sensitive identifiers.",
            "Emailing or populating production values in this workbook would create a security exposure.",
            "Provide values only through the approved secret/configuration channel; leave workbook data sheets masked.",
            "",
            "Encryption_Setting__mdt and JWT_Mapping__mdt",
        ],
    ]

    for row_index, values in enumerate(rows, header_row + 1):
        for col, value in enumerate(values, 1):
            ws.cell(row_index, col, value)
            style_body(ws.cell(row_index, col))
        priority = ws.cell(row_index, 1).value
        fill = RED if priority == "Critical" else YELLOW if priority == "High" else BLUE
        ws.cell(row_index, 1).fill = PatternFill("solid", fgColor=fill)
        ws.cell(row_index, 1).font = Font(bold=True)

    add_table(
        ws,
        f"A{header_row}:H{header_row + len(rows)}",
        "Open_Items_Table",
    )
    ws.freeze_panes = "A5"
    ws.sheet_view.showGridLines = False
    set_widths(
        ws,
        {1: 12, 2: 27, 3: 31, 4: 67, 5: 55, 6: 68, 7: 47, 8: 65},
    )


def validation_values(field_def: FieldDef) -> list[str]:
    return [choice.value for choice in field_def.choices if choice.active]


def write_data_sheet(
    wb: Workbook,
    obj: ObjectDef,
    validation_ws,
    validation_cursor: list[int],
) -> None:
    ws = wb.create_sheet(obj.sheet_name)
    columns = synthetic_columns(obj)
    max_column = max(1, len(columns))
    add_title(
        ws,
        f"{obj.label} — Client Data Template",
        f"{obj.category} | {obj.purpose} Handling: {obj.handling}. Keep API-name headers unchanged.",
        max_column,
    )

    ws.merge_cells(start_row=3, start_column=1, end_row=3, end_column=max_column)
    note = ws.cell(
        3,
        1,
        "Delete/replace sample rows before return. Yellow headers are metadata-required. "
        "Grey headers are technical identifiers. Do not include secrets in this workbook.",
    )
    note.fill = PatternFill("solid", fgColor=LIGHT_GREY)
    note.alignment = Alignment(wrap_text=True, vertical="center")
    ws.row_dimensions[3].height = 30

    api_row = 5
    label_row = 6
    required_row = 7
    first_data_row = 8

    for col, (api_name, label, field_def) in enumerate(columns, 1):
        api_cell = ws.cell(api_row, col, api_name)
        label_cell = ws.cell(label_row, col, label)
        required = bool(field_def and field_def.required)
        required_cell = ws.cell(required_row, col, "Required" if required else "Optional")

        style_header(api_cell, YELLOW if required else NAVY)
        if required:
            api_cell.font = Font(color="000000", bold=True)
        style_header(label_cell, BLUE)
        label_cell.font = Font(color="000000", bold=True)
        style_header(required_cell, YELLOW if required else GREY)
        required_cell.font = Font(color="000000", italic=True)

        if field_def:
            comment_parts = [
                f"Label: {field_def.label}",
                f"API: {field_def.api_name}",
                f"Type: {field_def.field_type}",
                f"Required in metadata: {'Yes' if field_def.required else 'No'}",
            ]
            if field_def.allowed_or_format:
                comment_parts.append(f"Allowed/format: {field_def.allowed_or_format}")
            if field_def.description:
                comment_parts.append(f"Description: {field_def.description}")
            if field_def.help_text:
                comment_parts.append(f"Help: {field_def.help_text}")
            api_cell.comment = Comment("\n".join(comment_parts), "Cursor")

            values = (
                []
                if obj.api_name in RESTRICTED_CONFIG
                else validation_values(field_def)
            )
            if values:
                start_row = validation_cursor[0]
                validation_ws.cell(start_row, 1, f"{obj.api_name}.{field_def.api_name}")
                for offset, value in enumerate(values):
                    validation_ws.cell(start_row + offset, 2, value)
                end_row = start_row + len(values) - 1
                formula = (
                    f"{quote_sheetname(validation_ws.title)}!"
                    f"$B${start_row}:$B${end_row}"
                )
                validation = DataValidation(
                    type="list",
                    formula1=formula,
                    allow_blank=not field_def.required,
                )
                validation.error = "Choose a repository-defined value from the list."
                validation.errorTitle = "Invalid value"
                validation.prompt = "Select an allowed value."
                validation.promptTitle = field_def.label
                ws.add_data_validation(validation)
                validation.add(
                    f"{get_column_letter(col)}{first_data_row}:"
                    f"{get_column_letter(col)}{first_data_row + 101}"
                )
                validation_cursor[0] = end_row + 2

    for sample_index in (1, 2):
        row = first_data_row + sample_index - 1
        for col, (api_name, label, field_def) in enumerate(columns, 1):
            if obj.api_name in RESTRICTED_CONFIG:
                value = "<restricted — supply through approved secure channel>"
            elif field_def is None:
                if api_name == "DeveloperName":
                    value = f"Sample_{re.sub(r'[^A-Za-z0-9]', '_', obj.label)}_{sample_index}"
                elif api_name == "MasterLabel":
                    value = f"Sample {obj.label} {sample_index}"
                elif api_name == "SetupOwner":
                    value = "Organization"
                else:
                    value = f"Sample {obj.name_label} {sample_index}"
            else:
                value = sample_value(field_def, sample_index)
            cell = ws.cell(row, col, value)
            style_body(cell)
            cell.fill = PatternFill(
                "solid",
                fgColor=RED if obj.api_name in RESTRICTED_CONFIG else LIGHT_BLUE,
            )
            if isinstance(value, date):
                cell.number_format = "yyyy-mm-dd"

    for row in range(first_data_row + 2, first_data_row + 102):
        for col in range(1, max_column + 1):
            style_body(ws.cell(row, col))

    ws.auto_filter.ref = (
        f"A{api_row}:{get_column_letter(max_column)}{first_data_row + 101}"
    )
    ws.freeze_panes = f"A{first_data_row}"
    ws.sheet_view.showGridLines = False

    for col, (_, label, field_def) in enumerate(columns, 1):
        longest = max(len(label), 16)
        if field_def:
            longest = max(longest, min(len(field_def.api_name), 45))
            if field_def.field_type in {"LongTextArea", "Html", "TextArea"}:
                longest = max(longest, 34)
        ws.column_dimensions[get_column_letter(col)].width = min(max(longest + 2, 18), 42)

    required_columns = [
        get_column_letter(index)
        for index, (_, _, field_def) in enumerate(columns, 1)
        if field_def and field_def.required
    ]
    for col_letter in required_columns:
        ws.conditional_formatting.add(
            f"{col_letter}{first_data_row}:{col_letter}{first_data_row + 101}",
            FormulaRule(
                formula=[f'LEN(TRIM({col_letter}{first_data_row}&""))=0'],
                fill=PatternFill("solid", fgColor=RED),
            ),
        )


def create_workbook(objects: list[ObjectDef], picklists: list[FieldDef]) -> None:
    wb = Workbook()
    used_sheets = {
        "README",
        "Master Catalog",
        "Field Dictionary",
        "Picklist Values",
        "Dependencies",
        "Static UI References",
        "Coverage Notes",
        "Open Items",
        "_ValidationLists",
    }
    for item in objects:
        if item.category == "Business master":
            prefix = "BM"
        elif item.is_custom_metadata:
            prefix = "CMD"
        else:
            prefix = "CFG"
        item.sheet_name = safe_sheet_name(prefix, item.label, used_sheets)

    write_readme(wb, objects, picklists)
    write_catalog(wb, objects, picklists)
    write_field_dictionary(wb, objects)
    write_picklists(wb, picklists)
    write_dependencies(wb, objects, picklists)
    write_static_ui_references(wb)
    write_coverage_notes(wb, objects, picklists)
    write_open_items(wb)

    validation_ws = wb.create_sheet("_ValidationLists")
    validation_cursor = [1]
    for item in objects:
        write_data_sheet(wb, item, validation_ws, validation_cursor)
    validation_ws.sheet_state = "hidden"

    wb.calculation.fullCalcOnLoad = True
    wb.calculation.forceFullCalc = True
    wb.save(OUTPUT)


def verify_workbook(expected_objects: list[ObjectDef], picklists: list[FieldDef]) -> dict[str, int]:
    wb = load_workbook(OUTPUT, read_only=False, data_only=False)
    required_sheets = {
        "README",
        "Master Catalog",
        "Field Dictionary",
        "Picklist Values",
        "Dependencies",
        "Static UI References",
        "Coverage Notes",
        "Open Items",
        "_ValidationLists",
        *(item.sheet_name for item in expected_objects),
    }
    missing = required_sheets.difference(wb.sheetnames)
    if missing:
        raise RuntimeError(f"Workbook is missing sheets: {sorted(missing)}")

    if wb["_ValidationLists"].sheet_state != "hidden":
        raise RuntimeError("Validation list sheet is not hidden")

    field_count = sum(
        len(item.fields)
        + int(
            item.is_custom_metadata
            or item.category == "Hierarchy custom setting"
            or "Name" not in {field_def.api_name for field_def in item.fields}
        )
        for item in expected_objects
    )
    actual_field_rows = wb["Field Dictionary"].max_row - 4
    if actual_field_rows != field_count:
        raise RuntimeError(
            f"Field dictionary row mismatch: expected {field_count}, got {actual_field_rows}"
        )

    picklist_rows = sum(max(1, len(item.choices)) for item in picklists)
    actual_picklist_rows = wb["Picklist Values"].max_row - 4
    if actual_picklist_rows != picklist_rows:
        raise RuntimeError(
            f"Picklist row mismatch: expected {picklist_rows}, got {actual_picklist_rows}"
        )

    return {
        "objects": len(expected_objects),
        "business_masters": sum(
            item.category == "Business master" for item in expected_objects
        ),
        "custom_metadata_types": sum(item.is_custom_metadata for item in expected_objects),
        "field_dictionary_rows": actual_field_rows,
        "picklist_fields": len(picklists),
        "picklist_value_rows": actual_picklist_rows,
        "worksheets": len(wb.sheetnames),
    }


def main() -> int:
    if not OBJECTS_ROOT.exists():
        print(f"Metadata directory not found: {OBJECTS_ROOT}", file=sys.stderr)
        return 1

    objects = collect_objects()
    picklists = collect_picklists()
    create_workbook(objects, picklists)
    summary = verify_workbook(objects, picklists)

    print(f"Created: {OUTPUT}")
    for key, value in summary.items():
        print(f"{key}: {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
