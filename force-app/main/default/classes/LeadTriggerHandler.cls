public class LeadTriggerHandler {

    public static void beforeInsert(List<Lead> newLeads) {
        LeadService.assignNewLeadsToBDRQueue(newLeads);
    }

    public static void afterInsert(List<Lead> newLeads) {
        System.debug('LeadTriggerHandler.afterInsert START');

        LeadService.sendQueueWelcomeEmails(newLeads);

        // Run the matched account email engine
        LeadService.checkAndSendMatchedAccountEmails(newLeads, null);

        System.debug('LeadTriggerHandler.afterInsert END');
    }

    public static void afterUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        List<Lead> convertedLeads = new List<Lead>();

        for (Lead leadRec : newLeads) {
            if (!oldMap.get(leadRec.Id).IsConverted && leadRec.IsConverted) {
                convertedLeads.add(leadRec);
            }
        }

        if (!convertedLeads.isEmpty()) {
            LeadService.updateAccountType(convertedLeads);
            LeadService.createAccountContactRelationships(convertedLeads);
            LeadService.updateOpportunityRevenueType(convertedLeads);
        }

        // Run the matched account email engine
        LeadService.checkAndSendMatchedAccountEmails(newLeads, oldMap);
    }
}