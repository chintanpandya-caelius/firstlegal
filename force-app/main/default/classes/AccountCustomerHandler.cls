public without sharing class AccountCustomerHandler {

    // Bypass switch for background/automated transactions
    public static Boolean bypassForTransaction = false;

    // Cached result of the custom label bypass check
    private static Boolean bypassCached = null;

    // Cache of Permission Set membership results per name, avoids repeat SOQL
    private static Map<String, Boolean> permissionSetCache = new Map<String, Boolean>();

    // Record Type developer name this handler applies to
    private static final String RT_CUSTOMER = 'Customer';

    // Permission Set required to change Status (per ticket, replaces old Permission Set Group)
    private static final String PERM_ACCOUNT_ADMIN = 'PS_Account_RT_Customer';

    // Cached describe of Account fields, used for addError field tokens
    private static final Map<String, Schema.SObjectField> ACCOUNT_FIELDS =
        Schema.SObjectType.Account.fields.getMap();

    // Error message constants
    private static final String MSG_LOCAL_ADDRESS = 'Complete the required Local Address fields.';
    private static final String MSG_BILLING_ADDRESS = 'Complete the required Billing Address fields.';
    private static final String MSG_DETAILS = 'Complete the required Details fields on the Details tab.';
    private static final String MSG_COMMON_SOR = 'Complete the required Common SOR fields on the SOR tab.';
    private static final String MSG_DATATRAC = 'Complete the required Datatrac fields on the SOR tab.';
    private static final String MSG_SOLARIA = 'Complete the required Solaria fields on the SOR tab.';
    private static final String MSG_TERMS = 'Complete the required Terms & Conditions fields.';
    private static final String MSG_SUB_TYPE_PROSPECT = 'Sub Type must be either "COD" or "Opposing Council" when Status is Prospect.';
    private static final String MSG_SUB_TYPE_ACTIVE = 'Sub Type cannot be "COD" or "Opposing Council" when Status is Active.';
    private static final String MSG_STATUS_PERMISSION_DENIED = 'Only Account Admin can change the status. Please contact an Account Admin or submit a ticket requesting an update.';
    private static final String MSG_NEW_TO_INVALID = 'You can only select Prospect or Active as a status.';
    private static final String MSG_TO_NEW_INVALID = 'You cannot select New as a status.';

    // Fields required when Status = New
    private static final List<String> NEW_REQUIRED_FIELDS = new List<String>{
        'Name',
        'Shipping_Email__c',
        'Service_Line__c'
    };

    // Fields required on the Details tab for Prospect/Active
    private static final List<String> DETAIL_REQUIRED_FIELDS = new List<String>{
        'Name',
        'Email__c',
        'Fax',
        'Phone',
        'Shipping_Email__c',
        'Shipping_Fax__c',
        'Shipping_Name__c',
        'Shipping_Phone__c',
        'Service_Line__c',
        'Sub_Type__c',
        'Type'
    };

    // Common SOR fields required for Prospect/Active
    private static final List<String> COMMON_SOR_FIELDS = new List<String>{
        'Administration_Fee__c',
        'ARS_Sales_Territory_Code__c',
        'Carrying_Fee__c',
        'Check_Charge_Percentage__c',
        'Limit_Advance_Fee__c',
        'Collection_Owner__c',
        'Credit_Card_Charge_Description__c',
        'Credit_Card_Charge_Income_Account__c',
        'Credit_Card_Charge_Percent__c',
        'Default_Messenger_Zone__c',
        'Default_Office_Code__c',
        'Default_Ship_Records_Method__c',
        'File_Number_Mask__c',
        'Finance_Charge_Interest_Rate__c',
        'Finance_Charges__c',
        'Receives_Statements__c',
        'Source_Customer_ID__c',
        'Source_System__c',
        'Statement_Model__c'
    };

    // Datatrac fields required for Prospect/Active
    private static final List<String> DATATRAC_FIELDS = new List<String>{
        'Billing_Cycle__c',
        'Credit_Status__c',
        'Group_Invoices__c',
        'Invoice_Master_Account__c',
        'Manual_Rate__c',
        'New_Order_Alert__c',
        'New_Order_Alert_Email__c',
        'New_Order_Alert_Template__c',
        'Online_Order_Adjustment_Method__c',
        'Reference_Required__c',
        'Single_Job_Invoice_Option__c',
        'Special_Rate__c',
        'Statement_Email_Address__c',
        'Statement_Print_Option__c',
        'Surcharge__c',
        'Validate_Reference__c'
    };

    // Solaria fields required for Prospect/Active
    private static final List<String> SOLARIA_FIELDS = new List<String>{
        'Delegate_To_All_Contacts__c',
        'Last_Statement_Sent__c',
        'Need_To_Send__c'
    };

    // Terms & Conditions fields required for Active only
    private static final List<String> TERMS_AND_CONDITIONS_FIELDS = new List<String>{
        'Firm_Name__c',
        'Invoicing_Delivery_Method__c',
        'Invoicing_Delivery_Method_Email__c',
        'Invoicing_Format__c',
        'Invoicing_Frequency__c',
        'Invoicing_Receival_Method__c',
        'Invoicing_Receival_Method_Detail__c',
        'Invoicing_Special_Instructions__c',
        'Payment_Method__c',
        'Signatory_Date__c',
        'Signatory_Name__c',
        'Signatory_Title__c',
        'Tax_ID__c',
        'Terms__c',
        'Terms_Date__c'
    };

    // Sub Type values that force Prospect and block Active
    private static final Set<String> COD_OPPOSING_COUNCIL = new Set<String>{
        'COD',
        'Opposing Council'
    };

    // Entry Point

    public static void runValidation(List<Account> newList, Map<Id, Account> oldMap) {

        if (isBypassed()) {
            return; // validation explicitly bypassed
        }

        Id customerRtId = getCustomerRecordTypeId();

        if (customerRtId == null) {
            return; // Customer record type not found
        }

        Set<Id> idsNeedingContactCheck = new Set<Id>();
        List<Account> scoped = new List<Account>();

        for (Account acc : newList) {

            Account oldAcc = (oldMap != null) ? oldMap.get(acc.Id) : null;

            Boolean isCurrentCustomerRt = (acc.RecordTypeId == customerRtId);
            Boolean wasCustomerRt = (oldAcc != null && oldAcc.RecordTypeId == customerRtId);

            // Skip if neither current nor old record belongs to the Customer Record Type
            if (!isCurrentCustomerRt && !wasCustomerRt) {
                continue;
            }

            // Allow Record Type change when Status is New
            if (oldAcc != null && wasCustomerRt && !isCurrentCustomerRt) {
                if (oldAcc.Status__c == 'New') {
                    continue; // Allowed Record Type change from 'New' status, bypass Customer validation logic
                } else {
                    acc.addError('Record Type cannot be changed away from Customer once Status is past New.');
                    continue;
                }
            }

            if (oldMap == null && acc.Status__c != 'New') {
                acc.Status__c.addError('New Accounts must be created with Status = New. Please save as New first, then transition the status afterward.');
                continue;
            }

            if (oldMap == null && ( acc.Status__c == 'New' || String.isBlank(acc.Status__c) ) ) {
                continue; // valid insert with Status = New, nothing else to check
            }

            if (oldMap != null) {

                validateStatusTransition(oldAcc.Status__c, acc.Status__c, acc); // validate allowed transition first

                Boolean hasPermission = enforceStatusChangePermission(acc, oldAcc); // Account Admin permission check
                if (!hasPermission) {
                    continue; // short-circuit further field validation on permission denial
                }

                if (!shouldValidate(acc, oldAcc)) {
                    continue; // no relevant field changed, skip field validation
                }
            }

            scoped.add(acc);

            if ((acc.Status__c == 'Prospect' || acc.Status__c == 'Active') && acc.Id != null) {
                idsNeedingContactCheck.add(acc.Id);
            }
        }

        if (scoped.isEmpty()) {
            return; // nothing left to validate
        }

        Map<Id, Boolean> hasValidContact = queryValidContacts(idsNeedingContactCheck, 'Billing Manager');

        for (Account acc : scoped) {

            if (acc.Status__c == 'New') {
                validateNewStatus(acc);
            } else if (acc.Status__c == 'Prospect') {
                validateProspectStatus(acc, hasValidContact);
            } else if (acc.Status__c == 'Active') {
                validateActiveStatus(acc, hasValidContact);
            }
        }
    }

   

    private static void validateStatusTransition(String oldStatus, String newStatus, Account acc) {

        if (String.isBlank(oldStatus) || oldStatus == newStatus) {
            return; // no status change to validate
        }

        if (newStatus == 'New') {
            acc.Status__c.addError(MSG_TO_NEW_INVALID); // ticket rule: no status can move back to New
            return;
        }

        if (oldStatus == 'New' && newStatus != 'Prospect' && newStatus != 'Active') {
            acc.Status__c.addError(MSG_NEW_TO_INVALID); // ticket rule: New can only move to Prospect or Active
            return;
        }

        Map<String, Set<String>> allowedTransitions = new Map<String, Set<String>>{
            'New' => new Set<String>{'Prospect', 'Active'},
            'Prospect' => new Set<String>{'Active', 'Inactive', 'Credit Hold', 'Suspended', 'Archived'},
            'Active' => new Set<String>{'Inactive', 'Credit Hold', 'Suspended', 'Archived'},
            'Inactive' => new Set<String>{'Credit Hold', 'Suspended', 'Archived'},
            'Credit Hold' => new Set<String>{'Inactive', 'Suspended', 'Archived'},
            'Suspended' => new Set<String>{'Inactive', 'Credit Hold', 'Archived'},
            'Archived' => new Set<String>{'Inactive', 'Credit Hold', 'Suspended'}
        };

        if (!allowedTransitions.containsKey(oldStatus)) {
            return; // unrecognized prior status, nothing further to check
        }

        if (!allowedTransitions.get(oldStatus).contains(newStatus)) {
            acc.Status__c.addError('Status cannot be changed from "' + oldStatus + '" to "' + newStatus + '".'); // fallback message, see note on hold-state return transitions below
        }
    }

    // Only a user holding PERM_ACCOUNT_ADMIN may change Status; returns false if denied
    private static Boolean enforceStatusChangePermission(Account acc, Account oldAcc) {

        if (acc.Status__c == oldAcc.Status__c) {
            return true; // no status change, nothing to enforce
        }

        if (userHasPermissionSet(PERM_ACCOUNT_ADMIN)) {
            return true;
        }

        acc.Status__c.addError(MSG_STATUS_PERMISSION_DENIED);
        return false;
    }


    private static void validateNewStatus(Account acc) {
        flagIncompleteAddress(acc, 'Shipping', MSG_LOCAL_ADDRESS); // Local Address complete check
        flagMissingFields(acc, NEW_REQUIRED_FIELDS, 'Complete the required New Account fields.');
    }

    private static void validateProspectStatus(Account acc, Map<Id, Boolean> contactMap) {
        validateSubTypeForProspect(acc);
        runSharedProspectActiveChecks(acc, contactMap);
    }

    private static void validateActiveStatus(Account acc, Map<Id, Boolean> contactMap) {

        if (acc.Terms__c != true) {
            acc.Terms__c.addError('Terms must be selected before the Account can be set to Active.');
        }

        flagMissingFields(acc, TERMS_AND_CONDITIONS_FIELDS, MSG_TERMS);
        validateSubTypeForActive(acc);
        runSharedProspectActiveChecks(acc, contactMap);
    }


    private static void validateSubTypeForProspect(Account acc) {

        String subType = acc.Sub_Type__c;

        if (String.isBlank(subType) || !COD_OPPOSING_COUNCIL.contains(subType)) {
            addSubTypeError(acc, MSG_SUB_TYPE_PROSPECT);
        }
    }

    private static void validateSubTypeForActive(Account acc) {

        String subType = acc.Sub_Type__c;

        if (!String.isBlank(subType) && COD_OPPOSING_COUNCIL.contains(subType)) {
            addSubTypeError(acc, MSG_SUB_TYPE_ACTIVE);
        }
    }

    private static void addSubTypeError(Account acc, String message) {

        Schema.SObjectField token = ACCOUNT_FIELDS.get('sub_type__c');

        if (token != null) {
            acc.addError(token, message);
        } else {
            acc.addError(message);
        }
    }

    // Shared validation for Prospect & Active

    private static void runSharedProspectActiveChecks(Account acc, Map<Id, Boolean> contactMap) {

        flagIncompleteAddress(acc, 'Shipping', MSG_LOCAL_ADDRESS); // Local Address
        flagIncompleteAddress(acc, 'Billing', MSG_BILLING_ADDRESS); // Billing Address

        flagMissingFields(acc, DETAIL_REQUIRED_FIELDS, MSG_DETAILS);
        flagMissingFields(acc, COMMON_SOR_FIELDS, MSG_COMMON_SOR);
        flagMissingFields(acc, DATATRAC_FIELDS, MSG_DATATRAC);
        flagMissingFields(acc, SOLARIA_FIELDS, MSG_SOLARIA);

        Boolean hasValidContact = (acc.Id != null) && contactMap.get(acc.Id) == true;

        if (!hasValidContact) {
            acc.addError('Missing Contact: Ensure the Account has at least one Active Account Contact Relationship with the Billing Manager role and a Contact Email Address.');
        }
    }

 
    // Change Detection

    private static Boolean shouldValidate(Account newAcc, Account oldAcc) {

        if (newAcc.Status__c != oldAcc.Status__c) {
            return true; // always validate when Status changes
        }

        return hasRequiredFieldChanged(newAcc, oldAcc);
    }

    private static Boolean hasRequiredFieldChanged(Account newAcc, Account oldAcc) {

        if (valuesDiffer(oldAcc.RecordTypeId, newAcc.RecordTypeId)) {
            return true; // evaluate if RecordType changes
        }

        List<String> fields = new List<String>();
        fields.addAll(NEW_REQUIRED_FIELDS);
        fields.addAll(DETAIL_REQUIRED_FIELDS);
        fields.addAll(COMMON_SOR_FIELDS);
        fields.addAll(DATATRAC_FIELDS);
        fields.addAll(SOLARIA_FIELDS);
        fields.addAll(TERMS_AND_CONDITIONS_FIELDS);

        Set<String> processedFields = new Set<String>();

        for (String fieldApi : fields) {

            if (processedFields.contains(fieldApi)) {
                continue; // already checked
            }

            processedFields.add(fieldApi);

            if (!ACCOUNT_FIELDS.containsKey(fieldApi.toLowerCase())) {
                System.debug(LoggingLevel.ERROR, 'Invalid Account field in Change Detection: ' + fieldApi);
                continue;
            }

            if (valuesDiffer(oldAcc.get(fieldApi), newAcc.get(fieldApi))) {
                return true;
            }
        }

        if (valuesDiffer(oldAcc.ShippingStreet, newAcc.ShippingStreet)) return true;
        if (valuesDiffer(oldAcc.ShippingCity, newAcc.ShippingCity)) return true;
        if (valuesDiffer(oldAcc.ShippingState, newAcc.ShippingState)) return true;
        if (valuesDiffer(oldAcc.ShippingStateCode, newAcc.ShippingStateCode)) return true;
        if (valuesDiffer(oldAcc.ShippingPostalCode, newAcc.ShippingPostalCode)) return true;
        if (valuesDiffer(oldAcc.ShippingCountry, newAcc.ShippingCountry)) return true;
        if (valuesDiffer(oldAcc.ShippingCountryCode, newAcc.ShippingCountryCode)) return true;

        if (valuesDiffer(oldAcc.BillingStreet, newAcc.BillingStreet)) return true;
        if (valuesDiffer(oldAcc.BillingCity, newAcc.BillingCity)) return true;
        if (valuesDiffer(oldAcc.BillingState, newAcc.BillingState)) return true;
        if (valuesDiffer(oldAcc.BillingStateCode, newAcc.BillingStateCode)) return true;
        if (valuesDiffer(oldAcc.BillingPostalCode, newAcc.BillingPostalCode)) return true;
        if (valuesDiffer(oldAcc.BillingCountry, newAcc.BillingCountry)) return true;
        if (valuesDiffer(oldAcc.BillingCountryCode, newAcc.BillingCountryCode)) return true;

        return false;
    }

    // Safely compares two generic field values without relying on reference equality
    private static Boolean valuesDiffer(Object oldValue, Object newValue) {

        if (oldValue == null && newValue == null) {
            return false;
        }

        if (oldValue == null || newValue == null) {
            return true;
        }

        return String.valueOf(oldValue) != String.valueOf(newValue);
    }


    // Adds a clickable field error for each blank/null field in the list
    private static Boolean flagMissingFields(Account acc, List<String> fieldApiNames, String message) {

        Boolean anyMissing = false;
        Set<String> processedFields = new Set<String>();

        for (String fieldApi : fieldApiNames) {

            if (processedFields.contains(fieldApi)) {
                continue; // already processed
            }

            processedFields.add(fieldApi);

            Schema.SObjectField token = ACCOUNT_FIELDS.get(fieldApi.toLowerCase());

            if (token == null) {
                System.debug(LoggingLevel.ERROR, 'Invalid Account field configured: ' + fieldApi);
                continue;
            }

            Object value = acc.get(fieldApi);
            Boolean missing = value == null || (value instanceof String && String.isBlank((String) value));

            if (missing) {
                anyMissing = true;
                acc.addError(token, message);
            }
        }

        return anyMissing;
    }

    // Returns the missing address fields for a prefix ('Shipping' or 'Billing'), State/Country picklist safe
    private static List<String> missingAddressFields(Account acc, String prefix) {

        List<String> missing = new List<String>();

        String street = (String) acc.get(prefix + 'Street');
        String city = (String) acc.get(prefix + 'City');
        String postal = (String) acc.get(prefix + 'PostalCode');
        String state = (String) acc.get(prefix + 'State');
        String stateCode = (String) acc.get(prefix + 'StateCode');
        String country = (String) acc.get(prefix + 'Country');
        String countryCode = (String) acc.get(prefix + 'CountryCode');

        if (String.isBlank(street)) {
            missing.add(prefix + 'Street');
        }

        if (String.isBlank(city)) {
            missing.add(prefix + 'City');
        }

        if (String.isBlank(postal)) {
            missing.add(prefix + 'PostalCode');
        }

        if (String.isBlank(state) && String.isBlank(stateCode)) {
            missing.add(prefix + 'State');
        }

        if (String.isBlank(country) && String.isBlank(countryCode)) {
            missing.add(prefix + 'Country');
        }

        return missing;
    }

    // Adds a clickable error to each incomplete address field for the given prefix
    private static Boolean flagIncompleteAddress(Account acc, String prefix, String message) {

        List<String> missingFields = missingAddressFields(acc, prefix);

        for (String fieldApi : missingFields) {

            Schema.SObjectField token = ACCOUNT_FIELDS.get(fieldApi.toLowerCase());

            if (token != null) {
                acc.addError(token, message);
            }
        }

        return !missingFields.isEmpty();
    }

    // Returns Account Ids that have at least one Active Contact Relation with the required role and an email
    private static Map<Id, Boolean> queryValidContacts(Set<Id> accountIds, String requiredRole) {

        Map<Id, Boolean> result = new Map<Id, Boolean>();

        if (accountIds.isEmpty()) {
            return result;
        }

        List<AccountContactRelation> relations;

        if (String.isBlank(requiredRole)) {
            relations = [
                SELECT AccountId
                FROM AccountContactRelation
                WHERE AccountId IN :accountIds
                AND IsActive = true
                AND Roles != null
                AND Contact.Email != null
            ];
        } else {
            relations = [
                SELECT AccountId
                FROM AccountContactRelation
                WHERE AccountId IN :accountIds
                AND IsActive = true
                AND Roles INCLUDES (:requiredRole)
                AND Contact.Email != null
            ];
        }

        for (AccountContactRelation acr : relations) {
            result.put(acr.AccountId, true);
        }

        return result;
    }

    private static Id getCustomerRecordTypeId() {

        Map<String, Schema.RecordTypeInfo> rtInfos = Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo customerRt = rtInfos.get(RT_CUSTOMER);

        return customerRt == null ? null : customerRt.getRecordTypeId();
    }



    private static Boolean isBypassed() {

        if (bypassForTransaction) {
            return true; // transaction-scoped bypass flag set
        }

        if (bypassCached != null) {
            return bypassCached;
        }

        try {
            bypassCached = System.Label.Bypass_Account_Validation.trim().equalsIgnoreCase('true');
        } catch (Exception e) {
            bypassCached = false;
        }

        return bypassCached;
    }

    // Checks whether the running user holds the given Permission Set (cached per transaction)
    private static Boolean userHasPermissionSet(String permissionSetName) {

        if (String.isBlank(permissionSetName)) {
            return false;
        }

        if (permissionSetCache.containsKey(permissionSetName)) {
            return permissionSetCache.get(permissionSetName);
        }

        Boolean hasIt = false;

        try {
            Integer count = [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSet.Name = :permissionSetName
            ];

            hasIt = count > 0;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking Permission Set ' + permissionSetName + ': ' + e.getMessage());
            hasIt = false;
        }

        permissionSetCache.put(permissionSetName, hasIt);
        return hasIt;
    }
}