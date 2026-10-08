public without sharing class OpportunitySLABreachHandler {

    private static Boolean isRunning = false;

    public static void handleAfterUpdate(
        List<Opportunity> newRecords,
        Map<Id, Opportunity> oldMap
    ) {

        if (isRunning) {
            return;
        }

        isRunning = true;

        try {

            Datetime currentTime = System.now();

            List<Opportunity> recordsToUpdate =
                new List<Opportunity>();

            for (Opportunity opportunity : newRecords) {

                Opportunity oldOpportunity =
                    oldMap.get(opportunity.Id);

                if (oldOpportunity == null) {
                    continue;
                }

                if (!shouldRecalculate(
                    opportunity,
                    oldOpportunity
                )) {
                    continue;
                }

                Boolean expectedBreached =
                    calculateBreached(
                        opportunity,
                        currentTime
                    );

                /*
                 * SLA_Breached__c is a Checkbox,
                 * therefore this is a Boolean comparison.
                 */
                if (
                    opportunity.SLA_Breached__c !=
                    expectedBreached
                ) {

                    recordsToUpdate.add(
                        new Opportunity(
                            Id = opportunity.Id,
                            SLA_Breached__c =
                                expectedBreached
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
        Opportunity newOpportunity,
        Opportunity oldOpportunity
    ) {

        /*
         * SLA Due Date changed.
         */
        if (
            newOpportunity.SLA_Due_Date__c !=
            oldOpportunity.SLA_Due_Date__c
        ) {
            return true;
        }

        /*
         * SLA Completion Date changed.
         */
        if (
            newOpportunity.SLA_Completion_Date__c !=
            oldOpportunity.SLA_Completion_Date__c
        ) {
            return true;
        }

        /*
         * SLA Breached checkbox changed.
         */
        if (
            newOpportunity.SLA_Breached__c !=
            oldOpportunity.SLA_Breached__c
        ) {
            return true;
        }

        return false;
    }


    /*
     * ============================================================
     * SCHEDULED PROCESSING
     * ============================================================
     */
    public static void handleScheduledBreach(
        List<Opportunity> opportunities
    ) {

        if (
            opportunities == null ||
            opportunities.isEmpty()
        ) {
            return;
        }

        Datetime currentTime = System.now();

        List<Opportunity> recordsToUpdate =
            new List<Opportunity>();

        for (Opportunity opportunity : opportunities) {

            Boolean expectedBreached =
                calculateBreached(
                    opportunity,
                    currentTime
                );

            if (
                opportunity.SLA_Breached__c !=
                expectedBreached
            ) {

                recordsToUpdate.add(
                    new Opportunity(
                        Id = opportunity.Id,
                        SLA_Breached__c =
                            expectedBreached
                    )
                );
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }


    /*
     * ============================================================
     * SLA BREACH CALCULATION
     * ============================================================
     */
    public static Boolean calculateBreached(
        Opportunity opportunity,
        Datetime currentTime
    ) {

        /*
         * No SLA Due Date = not breached.
         */
        if (opportunity.SLA_Due_Date__c == null) {
            return false;
        }

        /*
         * SLA completed.
         *
         * Breached if Completion Date is
         * after the Due Date.
         */
        if (
            opportunity.SLA_Completion_Date__c != null
        ) {

            return
                opportunity.SLA_Completion_Date__c >
                opportunity.SLA_Due_Date__c;
        }

        /*
         * SLA not completed.
         *
         * Breached if current time is
         * after the Due Date.
         */
        return
            currentTime >
            opportunity.SLA_Due_Date__c;
    }
}