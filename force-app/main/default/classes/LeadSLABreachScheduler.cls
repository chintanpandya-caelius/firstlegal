global class LeadSLABreachScheduler implements Schedulable {

    global void execute(SchedulableContext context) {

        Datetime currentTime = System.now();

        List<Lead> leadsToUpdate = new List<Lead>();

        List<Lead> leads = [
            SELECT
                Id,
                SLA_Due_Date__c,
                SLA_Completion_Date__c,
                SLA_Breached__c
            FROM Lead
            WHERE SLA_Due_Date__c != NULL
            AND (
                (
                    SLA_Completion_Date__c = NULL
                    AND SLA_Due_Date__c < :currentTime
                    AND SLA_Breached__c = FALSE
                )
                OR
                (
                    SLA_Completion_Date__c = NULL
                    AND SLA_Due_Date__c >= :currentTime
                    AND SLA_Breached__c = TRUE
                )
            )
        ];

        for (Lead lead : leads) {

            Boolean expectedBreached =
                LeadSLABreachHandler.calculateBreached(
                    lead,
                    currentTime
                );

            if (
                lead.SLA_Breached__c !=
                expectedBreached
            ) {

                leadsToUpdate.add(
                    new Lead(
                        Id = lead.Id,
                        SLA_Breached__c =
                            expectedBreached
                    )
                );
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }
}