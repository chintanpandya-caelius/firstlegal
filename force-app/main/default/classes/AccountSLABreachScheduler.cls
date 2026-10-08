global class AccountSLABreachScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {

        Datetime currentTime = System.now();

        /*
         * Get the Customer Account Record Type.
         */
        Id customerRecordTypeId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Customer')
            .getRecordTypeId();

        /*
         * Find Customer Accounts where SLA Breached
         * needs to be recalculated.
         */
        List<Account> accounts = [
            SELECT Id,
                   RecordTypeId,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Account
            WHERE RecordTypeId = :customerRecordTypeId
            AND SLA_Due_Date__c != NULL
            AND (
                /*
                 * SLA is incomplete,
                 * Due Date has passed,
                 * but Breached is FALSE.
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
                 * SLA is incomplete,
                 * Due Date is still in the future,
                 * but Breached is TRUE.
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
         * Send the records to the Handler.
         */
        if (!accounts.isEmpty()) {

            AccountSLABreachHandler.handleScheduledBreach(
                accounts
            );
        }
    }
}