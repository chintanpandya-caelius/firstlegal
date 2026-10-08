public with sharing class TimezoneUtilityController {

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getTimezoneData(Id recordId) {

        Map<String, String> response = new Map<String, String>();

        if (recordId == null) {
            return response;   // Utility bar open, no record active
        }

        String objectName = recordId.getSObjectType().getDescribe().getName();

        try {
            if (objectName == 'Case') {
                handleCase(recordId, response);

            } else if (objectName == 'Contact') {
                handleContact(recordId, response);

            } else if (objectName == 'Account') {
                handleAccount(recordId, response);
            }
            // Extend with more SObject types here as needed

        } catch (Exception e) {
            System.debug('TimezoneUtilityController error: ' + e.getMessage());
            // Return whatever was populated before the exception
        }

        return response;
    }

    // ─── Object handlers ─────────────────────────────────────────────────────

    private static void handleCase(Id caseId, Map<String, String> res) {
        Case c = [
            SELECT ContactId, AccountId
            FROM   Case
            WHERE  Id = :caseId
            LIMIT  1
        ];

        if (c.ContactId != null) {
            putContactUserTimezone(c.ContactId, res);
        }

        if (c.AccountId != null) {
            putAccountOwnerTimezone(c.AccountId, res);
        }
    }

    private static void handleContact(Id contactId, Map<String, String> res) {
        Contact con = [
            SELECT AccountId
            FROM   Contact
            WHERE  Id = :contactId
            LIMIT  1
        ];

        putContactUserTimezone(contactId, res);

        if (con.AccountId != null) {
            putAccountOwnerTimezone(con.AccountId, res);
        }
    }

    private static void handleAccount(Id accountId, Map<String, String> res) {
        putAccountOwnerTimezone(accountId, res);
    }

    // ─── Reusable lookups ────────────────────────────────────────────────────

    /**
     * Customer Timezone:
     * Finds the Experience/Community/Portal User whose ContactId links back
     * to this contact, then reads their TimeZoneSidKey.
     * Returns nothing if the contact has no associated portal user.
     */
    private static void putContactUserTimezone(Id contactId, Map<String, String> res) {
        List<User> users = [
            SELECT TimeZoneSidKey
            FROM   User
            WHERE  ContactId = :contactId
              AND  IsActive   = true
            LIMIT  1
        ];

        if (!users.isEmpty() && String.isNotBlank(users[0].TimeZoneSidKey)) {
            res.put('customerTimezone', users[0].TimeZoneSidKey);
        }
        // If no portal user exists, key is simply absent → LWC hides the row
    }

    /**
     * Account Timezone:
     * Every Account has an Owner (a User) with a TimeZoneSidKey.
     * This is the most reliable standard-field proxy for an account's
     * operating timezone without any custom fields.
     */
    private static void putAccountOwnerTimezone(Id accountId, Map<String, String> res) {
        List<Account> accounts = [
            SELECT Owner.TimeZoneSidKey
            FROM   Account
            WHERE  Id = :accountId
            LIMIT  1
        ];

        if (!accounts.isEmpty() && String.isNotBlank(accounts[0].Owner.TimeZoneSidKey)) {
            res.put('accountTimezone', accounts[0].Owner.TimeZoneSidKey);
        }
    }
}