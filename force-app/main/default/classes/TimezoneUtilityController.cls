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
            SELECT BillingState, BillingCountry
            FROM   Account
            WHERE  Id = :accountId
            LIMIT  1
        ];

        if (!accounts.isEmpty()) {
            String tz = mapBillingToTimezone(accounts[0].BillingState, accounts[0].BillingCountry);
            if (String.isNotBlank(tz)) {
                res.put('accountTimezone', tz);
            }
        }
    }
    private static String mapBillingToTimezone(String state, String country) {
    if (String.isBlank(country)) return null;

    // Non-US accounts — extend as needed
    if (country != 'US' && country != 'United States') {
        // Add other country mappings here
        return null;
    }

    if (String.isBlank(state)) return null;

    Map<String, String> stateToTz = new Map<String, String>{
        // Pacific
        'CA' => 'America/Los_Angeles', 'WA' => 'America/Los_Angeles',
        'OR' => 'America/Los_Angeles', 'NV' => 'America/Los_Angeles',
        // Mountain
        'AZ' => 'America/Phoenix', 'CO' => 'America/Denver',
        'UT' => 'America/Denver', 'MT' => 'America/Denver',
        'NM' => 'America/Denver', 'WY' => 'America/Denver',
        // Central
        'TX' => 'America/Chicago', 'IL' => 'America/Chicago',
        'MN' => 'America/Chicago', 'WI' => 'America/Chicago',
        'MO' => 'America/Chicago', 'IA' => 'America/Chicago',
        'KS' => 'America/Chicago', 'NE' => 'America/Chicago',
        'OK' => 'America/Chicago', 'LA' => 'America/Chicago',
        'AR' => 'America/Chicago', 'MS' => 'America/Chicago',
        'AL' => 'America/Chicago', 'TN' => 'America/Chicago',
        // Eastern
        'NY' => 'America/New_York', 'FL' => 'America/New_York',
        'GA' => 'America/New_York', 'NC' => 'America/New_York',
        'VA' => 'America/New_York', 'PA' => 'America/New_York',
        'OH' => 'America/New_York', 'MI' => 'America/New_York',
        'NJ' => 'America/New_York', 'MA' => 'America/New_York',
        'MD' => 'America/New_York', 'SC' => 'America/New_York',
        'CT' => 'America/New_York', 'IN' => 'America/New_York',
        'DC' => 'America/New_York', 'DE' => 'America/New_York',
        'ME' => 'America/New_York', 'NH' => 'America/New_York',
        'RI' => 'America/New_York', 'VT' => 'America/New_York',
        'WV' => 'America/New_York', 'KY' => 'America/New_York',
        // Hawaii / Alaska
        'HI' => 'Pacific/Honolulu', 'AK' => 'America/Anchorage'
    };

    String abbr = state.trim().toUpperCase();
    return stateToTz.containsKey(abbr) ? stateToTz.get(abbr) : null;
}
}