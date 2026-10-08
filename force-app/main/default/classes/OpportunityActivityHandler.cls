public with sharing class OpportunityActivityHandler {

    public static void resetStaleOpportunities(
        List<SObject> activities
    ) {
        Set<Id> opportunityIds = new Set<Id>();

        for (SObject activity : activities) {
            Id whatId;

            if (activity instanceof Task) {
                whatId = ((Task) activity).WhatId;
            } else if (activity instanceof Event) {
                whatId = ((Event) activity).WhatId;
            }

            if (whatId != null &&
                whatId.getSObjectType() == Opportunity.SObjectType) {
                opportunityIds.add(whatId);
            }
        }

        if (opportunityIds.isEmpty()) {
            return;
        }

        List<Opportunity> opportunitiesToUpdate = [
            SELECT Id,
                   IsStale__c,
                   Stale_Date__c,
                   Last_Activity_Date__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];

        Date activityDate = Date.today();

        for (Opportunity opp : opportunitiesToUpdate) {
            opp.Last_Activity_Date__c = activityDate;

            if (opp.IsStale__c) {
                opp.IsStale__c = false;
                opp.Stale_Date__c = null;
            }
        }

        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }
    }
}