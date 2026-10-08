public without sharing class LeadSLABreachHandler {

    private static Boolean isRunning = false;

    public static void handleAfterUpdate(
        List<Lead> newRecords,
        Map<Id, Lead> oldMap
    ) {

        if (isRunning) {
            return;
        }

        isRunning = true;

        try {

            Datetime currentTime = System.now();

            List<Lead> recordsToUpdate = new List<Lead>();

            for (Lead lead : newRecords) {

                Lead oldLead = oldMap.get(lead.Id);

                if (oldLead == null) {
                    continue;
                }

                if (!shouldRecalculate(lead, oldLead)) {
                    continue;
                }

                Boolean expectedBreached =
                    calculateBreached(
                        lead,
                        currentTime
                    );

                if (lead.SLA_Breached__c != expectedBreached) {

                    recordsToUpdate.add(
                        new Lead(
                            Id = lead.Id,
                            SLA_Breached__c = expectedBreached
                        )
                    );
                }
            }

            if (!recordsToUpdate.isEmpty()) {
                update recordsToUpdate;
            }

        } finally {
            isRunning = false;
        }
    }

    private static Boolean shouldRecalculate(
        Lead newLead,
        Lead oldLead
    ) {

        if (
            newLead.SLA_Due_Date__c !=
            oldLead.SLA_Due_Date__c
        ) {
            return true;
        }

        if (
            newLead.SLA_Completion_Date__c !=
            oldLead.SLA_Completion_Date__c
        ) {
            return true;
        }

        if (
            newLead.SLA_Breached__c !=
            oldLead.SLA_Breached__c
        ) {
            return true;
        }

        return false;
    }

    public static Boolean calculateBreached(
        Lead lead,
        Datetime currentTime
    ) {

        if (lead.SLA_Due_Date__c == null) {
            return false;
        }

        if (lead.SLA_Completion_Date__c != null) {

            return
                lead.SLA_Completion_Date__c >
                lead.SLA_Due_Date__c;
        }

        return
            currentTime >
            lead.SLA_Due_Date__c;
    }
}