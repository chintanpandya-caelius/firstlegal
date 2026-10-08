public class LeadTriggerHandler {

    public static void beforeInsert(List<Lead> newLeads) {
        LeadService.assignNewLeadsToBDRQueue(newLeads);

        // NOVA-4844(Make Qualification Required in Nurturing Stage)
        LeadService.validateQualificationForNurturing(newLeads);
    }

    public static void beforeUpdate(List<Lead> newLeads) {
        // NOVA-4844(Make Qualification Required in Nurturing Stage)
        LeadService.validateQualificationForNurturing(newLeads);
    }

    public static void afterInsert(List<Lead> newLeads) {
        System.debug('LeadTriggerHandler.afterInsert START');

        LeadDuplicateHandler.process(newLeads, null);

        LeadService.sendQueueWelcomeEmails(newLeads);

        // Run the matched account email engine
        LeadService.checkAndSendMatchedAccountEmails(newLeads, null);

        System.debug('LeadTriggerHandler.afterInsert END');
    }

    public static void afterUpdate(
        List<Lead> newLeads,
        Map<Id, Lead> oldMap
    ) {
        System.debug('LeadTriggerHandler.afterUpdate START');

        // Re-check Account match and queue assignment on every update
        LeadDuplicateHandler.process(newLeads, oldMap);

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

        System.debug('LeadTriggerHandler.afterUpdate END');
    }
}