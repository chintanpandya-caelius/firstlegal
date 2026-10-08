public without sharing class AccountSLABreachHandler {
    
    public static void handleScheduledBreach(
    List<Account> accounts
) {

    if (accounts == null || accounts.isEmpty()) {
        return;
    }

    Datetime currentTime = System.now();

    List<Account> recordsToUpdate =
        new List<Account>();

    for (Account account : accounts) {

        Boolean expectedBreached =
            calculateBreached(
                account,
                currentTime
            );

        if (
            account.SLA_Breached__c !=
            expectedBreached
        ) {

            recordsToUpdate.add(
                new Account(
                    Id = account.Id,
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

    private static Boolean isRunning = false;

    public static void handleAfterUpdate(
        List<Account> newRecords,
        Map<Id, Account> oldMap
    ) {

        if (isRunning) {
            return;
        }

        isRunning = true;

        try {

            Datetime currentTime = System.now();

            List<Account> recordsToUpdate =
                new List<Account>();

            /*
             * Get the Customer Account Record Type.
             */
            Id customerRecordTypeId = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('Customer')
                .getRecordTypeId();

            for (Account account : newRecords) {

                Account oldAccount = oldMap.get(account.Id);

                if (oldAccount == null) {
                    continue;
                }

                /*
                 * Only Customer Record Type Accounts
                 * participate in SLA processing.
                 */
                if (account.RecordTypeId != customerRecordTypeId) {
                    continue;
                }

                if (!shouldRecalculate(account, oldAccount)) {
                    continue;
                }

                Boolean expectedBreached =
                    calculateBreached(
                        account,
                        currentTime
                    );

                /*
                 * SLA_Breached__c is a Checkbox,
                 * therefore this is a Boolean comparison.
                 */
                if (
                    account.SLA_Breached__c !=
                    expectedBreached
                ) {

                    recordsToUpdate.add(
                        new Account(
                            Id = account.Id,
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
        Account newAccount,
        Account oldAccount
    ) {

        /*
         * SLA Due Date changed.
         */
        if (
            newAccount.SLA_Due_Date__c !=
            oldAccount.SLA_Due_Date__c
        ) {
            return true;
        }

        /*
         * SLA Completion Date changed.
         */
        if (
            newAccount.SLA_Completion_Date__c !=
            oldAccount.SLA_Completion_Date__c
        ) {
            return true;
        }

        /*
         * SLA Breached checkbox changed.
         */
        if (
            newAccount.SLA_Breached__c !=
            oldAccount.SLA_Breached__c
        ) {
            return true;
        }

        return false;
    }


    public static Boolean calculateBreached(
        Account account,
        Datetime currentTime
    ) {

        /*
         * No SLA Due Date = not breached.
         */
        if (account.SLA_Due_Date__c == null) {
            return false;
        }

        /*
         * SLA completed.
         *
         * Breached if Completion Date
         * is after Due Date.
         */
        if (account.SLA_Completion_Date__c != null) {

            return
                account.SLA_Completion_Date__c >
                account.SLA_Due_Date__c;
        }

        /*
         * SLA not completed.
         *
         * Breached if current time
         * is after Due Date.
         */
        return
            currentTime >
            account.SLA_Due_Date__c;
    }
}