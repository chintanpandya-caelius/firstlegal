global class OpportunitySLABreachScheduler
    implements Schedulable {

    global void execute(SchedulableContext sc) {

        Datetime currentTime = System.now();

        /*
         * Find Opportunities where SLA Breached
         * needs to be recalculated.
         */
        List<Opportunity> opportunities = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Opportunity
            WHERE SLA_Due_Date__c != NULL
            AND (
                /*
                 * Condition 1:
                 *
                 * SLA is incomplete
                 * Due Date has passed
                 * Breached is FALSE
                 *
                 * FALSE → TRUE
                 */
                (
                    SLA_Completion_Date__c = NULL
                    AND SLA_Due_Date__c < :currentTime
                    AND SLA_Breached__c = FALSE
                )

                OR

                /*
                 * Condition 2:
                 *
                 * SLA is incomplete
                 * Due Date is in the future
                 * Breached is TRUE
                 *
                 * TRUE → FALSE
                 */
                (
                    SLA_Completion_Date__c = NULL
                    AND SLA_Due_Date__c >= :currentTime
                    AND SLA_Breached__c = TRUE
                )
            )
        ];

        /*
         * Pass the records to the Handler.
         */
        if (!opportunities.isEmpty()) {

            OpportunitySLABreachHandler.handleScheduledBreach(
                opportunities
            );
        }
    }
}