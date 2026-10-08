public with sharing class TaskUnresolvedItemService {
    
    // Internal domain definition
    private static final String INTERNAL_DOMAIN = 'firstlegal.com';

    /**
     * Helper to determine if an email sender is an unknown external sender
     */
    public static Boolean isUnknownExternalSender(String emailAddress) {
        if (String.isBlank(emailAddress)) return false;
        
        // 1. Check if domain is external
        String domain = emailAddress.substringAfter('@').toLowerCase();
        if (domain == INTERNAL_DOMAIN) {
            return false; // Internal domain, skip unresolved check
        }
        
        // 2. Check if sender exists in Lead or Contact records
        List<Contact> contacts = [SELECT Id FROM Contact WHERE Email = :emailAddress LIMIT 1];
        if (!contacts.isEmpty()) return false;

        List<Lead> leads = [SELECT Id FROM Lead WHERE Email = :emailAddress LIMIT 1];
        if (!leads.isEmpty()) return false;

        return true; // External AND unknown email address
    }
}