public without sharing class AccountOtherRecordHandler {

    // ---- Bypass ----
    public static Boolean bypassForTransaction = false;
    private static Boolean bypassCached = null;

    private static final Map<String, Schema.SObjectField> ACCOUNT_FIELDS = Schema.SObjectType.Account.fields.getMap();

    // ---- Record Types ----
    private static final String RT_COURT = 'Court';
    private static final String RT_FACILITY = 'Facility';
    private static final String RT_PROFESSIONAL_ASSOCIATION = 'Professional_Association';
    private static final String RT_VENDOR = 'Vendor';
    private static final Set<String> APPLICABLE_RECORD_TYPES = new Set<String>{ RT_COURT, RT_FACILITY, RT_PROFESSIONAL_ASSOCIATION, RT_VENDOR };

    // ---- Permission Sets (one per Record Type, ASSUMED dev names) ----
    private static final String PS_COURT = 'PS_Account_RT_Court';
    private static final String PS_FACILITY = 'PS_Account_RT_Facility';
    private static final String PS_PROFESSIONAL_ASSOCIATION = 'PS_Account_RT_Professional_Association';
    private static final String PS_VENDOR = 'PS_Account_RT_Vendor';

    // ---- Messages ----
    private static final String MSG_NEW_ADDRESS = 'Before Save, ensure Local Address fields are complete.';
    private static final String MSG_NEW_REQUIRED = 'Complete the required New Account fields.';
    private static final String MSG_ACTIVE_SHIPPING_ADDRESS = 'Before Save, ensure Local (Shipping) Address fields are complete.';
    private static final String MSG_ACTIVE_BILLING_ADDRESS = 'Before Save, ensure Billing Address fields are complete.';
    private static final String MSG_ACTIVE_DETAILS = 'Complete the required Details fields.';
    private static final String MSG_COMMON_SOR = 'Complete the required Common SOR fields.';
    private static final String MSG_DATATRAC = 'Complete the required Datatrac fields.';
    private static final String MSG_SOLARIA = 'Complete the required Solaria fields.';
    private static final String MSG_CONTACT = 'Missing Contact: Ensure the account has at minimum one contact Account Contact Relationship related list that is Active, has one or more Roles selected, and an email address.';
    private static final String MSG_STATUS_FROM_NEW = 'You can only select Active as a status.';
    private static final String MSG_STATUS_TO_NEW = 'You cannot select New as a status.';
    private static final String MSG_DENY_COURT = 'Only a Business Admin can change the status. Please contact a Business Admin to update.';
    private static final String MSG_DENY_FACILITY = 'Only a Vendor Management Team member can change the status. Please contact a Vendor Management Team member to update.';
    private static final String MSG_DENY_MARKETING = 'Only a VP of Marketing or Marketing Manager can change the status. Please contact a VP of Marketing or Marketing Manager to update.';

    // ---- Field groups ----
    private static final List<String> NEW_REQUIRED_FIELDS = new List<String>{ 'Name', 'Shipping_Email__c' };

    // Removed Local_County__c and Billing_County__c per request
    private static final List<String> ACTIVE_DETAIL_REQUIRED_FIELDS = new List<String>{
        'Name', 'Email__c', 'Fax', 'Phone', 'Shipping_Email__c', 'Shipping_Fax__c', 'Shipping_Name__c',
        'Shipping_Phone__c', 'Service_Line__c', 'Type'
    };

    // Facility-only groups
    private static final List<String> COMMON_SOR_FIELDS = new List<String>{
        'Custodian__c', 'Default_Date_Weekdays__c', 'Default_Service_Date_Friday__c', 'Default_Service_Date_Monday__c',
        'Default_Service_Date_Thursday__c', 'Default_Service_Date_Tuesday__c', 'Default_Service_Date_Wednesday__c',
        'Default_Service_Time_Friday__c', 'Default_Service_Time_Monday__c', 'Default_Service_Time_Thursday__c',
        'Default_Service_Time_Tuesday__c', 'Default_Service_Time_Wednesday__c', 'Default_Time_Weekdays__c',
        'Effective_Date__c', 'Expiry_Date__c', 'Facility_Code__c', 'Offsite_Comments__c', 'Source_Customer_ID__c',
        'Source_System__c', 'Visiting_Days__c', 'Visiting_Hours__c'
    };

    private static final List<String> DATATRAC_FIELDS = new List<String>{
        'Addon_Billing_Amount__c', 'Address_Is_On_Map__c', 'Alternate_Lookup_Key__c', 'Earliest_Delivery_Time__c',
        'Expected_Axis_Delivery_Date__c', 'Last_Used_Date__c', 'Latest_Delivery_Time__c', 'Latest_Service_Time__c',
        'Maximum_Daily_Pieces__c', 'Phone_Extension__c', 'Reference__c', 'Special_Instruction_1__c',
        'Special_Instruction_2__c', 'Special_Instruction_3__c', 'Special_Instruction_4__c', 'Usage_Count__c',
        'Offsite_Comments__c', 'Source_Customer_ID__c', 'Source_System__c', 'Visiting_Days__c', 'Visiting_Hours__c'
    };

    private static final List<String> SOLARIA_FIELDS = new List<String>{ 'Location_Rate__c' };

    // ---- Allowed Status transitions ----
    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        'New' => new Set<String>{ 'Active' },
        'Active' => new Set<String>{ 'Inactive', 'Archived' },
        'Inactive' => new Set<String>{ 'Active', 'Archived' },
        'Archived' => new Set<String>{ 'Active', 'Inactive' }
    };

    // Caches one PermissionSet membership result per PS per transaction
    private static Map<String, Boolean> permSetCache = new Map<String, Boolean>();

    // ---- Entry Point ----
    public static void runValidation(List<Account> newList, Map<Id, Account> oldMap) {
        if (isBypassed()) return;

        Map<Id, Schema.RecordTypeInfo> rtInfoById = Account.SObjectType.getDescribe().getRecordTypeInfosById();
        List<Account> scoped = new List<Account>();
        Set<Id> idsNeedingContactCheck = new Set<Id>();

        for (Account acc : newList) {
            String rtDevName = recordTypeDevName(rtInfoById, acc);
            if (!APPLICABLE_RECORD_TYPES.contains(rtDevName)) continue; // out of scope record type

            if (oldMap == null && acc.Status__c == 'New') continue; // fresh New insert (also keeps Lead conversion safe)

            Account oldAcc = (oldMap == null) ? null : oldMap.get(acc.Id);

            if (oldAcc != null) {
                // UPDATE
                Boolean isRecordTypeChanged = acc.RecordTypeId != oldAcc.RecordTypeId;

                // Bypass status transition and permission checks if Record Type is changed
                if (!isRecordTypeChanged) {
                    if (!validateStatusTransition(oldAcc.Status__c, acc.Status__c, acc)) continue; // invalid transition
                    
                    // Editing any validated field on a record already past New requires the record type's Permission Set
                    if (oldAcc.Status__c != 'New' && !enforceEditPermission(rtDevName, acc)) continue;
                }

                if (!shouldValidate(acc, oldAcc)) continue; // nothing relevant changed

            } else {
                // INSERT
                if (String.isBlank(acc.Status__c)) acc.Status__c = 'New'; // guard against blank Status__c from API/Data Loader

                if (acc.Status__c != 'New') {
                    // Direct insert into a non-New status = implicit New -> X transition
                    if (!validateStatusTransition('New', acc.Status__c, acc)) continue;
                    if (!enforceEditPermission(rtDevName, acc)) continue;
                }
            }

            scoped.add(acc); // only fully valid, authorized records reach here
            if (acc.Status__c == 'Active' && acc.Id != null) idsNeedingContactCheck.add(acc.Id);
        }

        if (scoped.isEmpty()) return;

        Map<Id, Boolean> hasValidContact = queryValidContacts(idsNeedingContactCheck, null);

        for (Account acc : scoped) {
            String rtDevName = recordTypeDevName(rtInfoById, acc);
            if (acc.Status__c == 'New') validateNewStatus(acc);
            else if (acc.Status__c == 'Active') validateActiveStatus(acc, rtDevName, hasValidContact);
        }
    }

    private static String recordTypeDevName(Map<Id, Schema.RecordTypeInfo> rtInfoById, Account acc) {
        Schema.RecordTypeInfo rtInfo = rtInfoById.get(acc.RecordTypeId);
        return (rtInfo == null) ? null : rtInfo.getDeveloperName();
    }

    // ---- Status Transition Validation ----
    private static Boolean validateStatusTransition(String oldStatus, String newStatus, Account acc) {
        if (String.isBlank(oldStatus) || oldStatus == newStatus) return true; // no change, always ok

        if (oldStatus == 'New' && newStatus != 'Active') {
            acc.Status__c.addError(MSG_STATUS_FROM_NEW);
            return false;
        }
        if (oldStatus != 'New' && newStatus == 'New') {
            acc.Status__c.addError(MSG_STATUS_TO_NEW);
            return false;
        }
        if (ALLOWED_TRANSITIONS.containsKey(oldStatus) && !ALLOWED_TRANSITIONS.get(oldStatus).contains(newStatus)) {
            acc.Status__c.addError('Status cannot be changed from "' + oldStatus + '" to "' + newStatus + '".');
            return false;
        }
        return true;
    }

    // ---- Permission Set enforcement ----
    private static Boolean enforceEditPermission(String rtDevName, Account acc) {
        String psName;
        String deniedMessage;

        if (rtDevName == RT_COURT) { psName = PS_COURT; deniedMessage = MSG_DENY_COURT; }
        else if (rtDevName == RT_FACILITY) { psName = PS_FACILITY; deniedMessage = MSG_DENY_FACILITY; }
        else if (rtDevName == RT_PROFESSIONAL_ASSOCIATION) { psName = PS_PROFESSIONAL_ASSOCIATION; deniedMessage = MSG_DENY_MARKETING; }
        else if (rtDevName == RT_VENDOR) { psName = PS_VENDOR; deniedMessage = MSG_DENY_MARKETING; }
        else return true; // not reachable, record type already scoped above

        Boolean authorized = userHasPermissionSet(psName);
        if (!authorized) acc.Status__c.addError(deniedMessage);
        return authorized;
    }

    private static Boolean userHasPermissionSet(String psDeveloperName) {
        if (String.isBlank(psDeveloperName)) return false;
        if (permSetCache.containsKey(psDeveloperName)) return permSetCache.get(psDeveloperName);

        Boolean hasIt = false;
        try {
            Integer count = [
                SELECT COUNT() FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.Name = :psDeveloperName
            ];
            hasIt = count > 0;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking Permission Set ' + psDeveloperName + ': ' + e.getMessage());
        }

        permSetCache.put(psDeveloperName, hasIt);
        return hasIt;
    }

    // ---- Change Detection ----
    private static Boolean shouldValidate(Account newAcc, Account oldAcc) {
        if (newAcc.RecordTypeId != oldAcc.RecordTypeId) return true; // record type change triggers validation
        if (newAcc.Status__c != oldAcc.Status__c) return true; // status change always triggers validation
        return hasRequiredFieldChanged(newAcc, oldAcc);
    }

    private static Boolean hasRequiredFieldChanged(Account newAcc, Account oldAcc) {
        List<String> fields = new List<String>();
        fields.addAll(NEW_REQUIRED_FIELDS);
        fields.addAll(ACTIVE_DETAIL_REQUIRED_FIELDS);
        fields.addAll(COMMON_SOR_FIELDS);
        fields.addAll(DATATRAC_FIELDS);
        fields.addAll(SOLARIA_FIELDS);

        Set<String> processed = new Set<String>();
        for (String fieldApi : fields) {
            if (processed.contains(fieldApi)) continue;
            processed.add(fieldApi);

            if (!ACCOUNT_FIELDS.containsKey(fieldApi.toLowerCase())) {
                System.debug(LoggingLevel.ERROR, 'Invalid Account field in Change Detection: ' + fieldApi); // bulletproof against typo'd/deleted fields
                continue;
            }
            if (valuesDiffer(oldAcc.get(fieldApi), newAcc.get(fieldApi))) return true;
        }

        for (String prefix : new List<String>{ 'Shipping', 'Billing' }) {
            for (String suffix : new List<String>{ 'Street', 'City', 'State', 'StateCode', 'PostalCode', 'Country', 'CountryCode' }) {
                if (valuesDiffer(oldAcc.get(prefix + suffix), newAcc.get(prefix + suffix))) return true;
            }
        }
        return false;
    }

    private static Boolean valuesDiffer(Object oldValue, Object newValue) {
        if (oldValue == null && newValue == null) return false;
        if (oldValue == null || newValue == null) return true;
        return String.valueOf(oldValue) != String.valueOf(newValue);
    }

    // ---- Status-specific validation ----
    private static void validateNewStatus(Account acc) {
        flagIncompleteAddress(acc, 'Shipping', MSG_NEW_ADDRESS);
        flagMissingFields(acc, NEW_REQUIRED_FIELDS, MSG_NEW_REQUIRED);
    }

    private static void validateActiveStatus(Account acc, String rtDevName, Map<Id, Boolean> contactMap) {
        flagIncompleteAddress(acc, 'Shipping', MSG_ACTIVE_SHIPPING_ADDRESS);
        flagIncompleteAddress(acc, 'Billing', MSG_ACTIVE_BILLING_ADDRESS);
        flagMissingFields(acc, ACTIVE_DETAIL_REQUIRED_FIELDS, MSG_ACTIVE_DETAILS);

        if (rtDevName == RT_FACILITY) {
            flagMissingFields(acc, COMMON_SOR_FIELDS, MSG_COMMON_SOR);
            flagMissingFields(acc, DATATRAC_FIELDS, MSG_DATATRAC);
            flagMissingFields(acc, SOLARIA_FIELDS, MSG_SOLARIA);
        }

        Boolean hasValidContact = (acc.Id != null) && contactMap.get(acc.Id) == true;
        if (!hasValidContact) acc.addError(MSG_CONTACT);
    }

    // ---- Field / Address helpers ----
    private static Boolean flagMissingFields(Account acc, List<String> fieldApiNames, String message) {
        Boolean anyMissing = false;
        Set<String> processed = new Set<String>();

        for (String fieldApi : fieldApiNames) {
            if (processed.contains(fieldApi)) continue;
            processed.add(fieldApi);

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

    // Returns missing address fields for a prefix ('Shipping'/'Billing'); supports State/Country picklists
    private static List<String> missingAddressFields(Account acc, String prefix) {
        List<String> missing = new List<String>();
        String street = (String) acc.get(prefix + 'Street');
        String city = (String) acc.get(prefix + 'City');
        String postal = (String) acc.get(prefix + 'PostalCode');
        String state = (String) acc.get(prefix + 'State');
        String stateCode = (String) acc.get(prefix + 'StateCode');
        String country = (String) acc.get(prefix + 'Country');
        String countryCode = (String) acc.get(prefix + 'CountryCode');

        if (String.isBlank(street)) missing.add(prefix + 'Street');
        if (String.isBlank(city)) missing.add(prefix + 'City');
        if (String.isBlank(postal)) missing.add(prefix + 'PostalCode');
        if (String.isBlank(state) && String.isBlank(stateCode)) missing.add(prefix + 'State');
        if (String.isBlank(country) && String.isBlank(countryCode)) missing.add(prefix + 'Country');
        return missing;
    }

    private static Boolean flagIncompleteAddress(Account acc, String prefix, String message) {
        List<String> missingFields = missingAddressFields(acc, prefix);
        for (String fieldApi : missingFields) {
            Schema.SObjectField token = ACCOUNT_FIELDS.get(fieldApi.toLowerCase());
            if (token != null) acc.addError(token, message);
        }
        return !missingFields.isEmpty();
    }

    // Active AccountContactRelation with role(s) selected + Contact email populated, per accountId
    private static Map<Id, Boolean> queryValidContacts(Set<Id> accountIds, String requiredRole) {
        Map<Id, Boolean> result = new Map<Id, Boolean>();
        if (accountIds.isEmpty()) return result;

        List<AccountContactRelation> relations = String.isBlank(requiredRole)
            ? [SELECT AccountId FROM AccountContactRelation WHERE AccountId IN :accountIds AND IsActive = true AND Roles != null AND Contact.Email != null]
            : [SELECT AccountId FROM AccountContactRelation WHERE AccountId IN :accountIds AND IsActive = true AND Roles INCLUDES (:requiredRole) AND Contact.Email != null];

        for (AccountContactRelation acr : relations) result.put(acr.AccountId, true);
        return result;
    }

    // ---- Emergency Validation Bypass ----
    private static Boolean isBypassed() {
        if (bypassForTransaction) return true;
        if (bypassCached != null) return bypassCached;

        try {
            bypassCached = System.Label.Bypass_Account_Lifecycle_Validation.trim().equalsIgnoreCase('true');
        } catch (Exception e) {
            bypassCached = false;
        }
        return bypassCached;
    }
}