public class ABMMultiContactEngagementBatch
    implements Database.Batchable<SObject> {

    private static final Integer LOOKBACK_DAYS = 30;
    private static final Integer QUALIFYING_TASK_THRESHOLD = 3;
    private static final Integer HIGH_FREQUENCY_THRESHOLD = 3;

    private static final String QUALIFYING_SIGNAL_PREFIX =
        '[ABM Signal]%';

    private static final String MCLE_SUBJECT_PREFIX =
        '[ABM Signal] - Multi-Contact Account Engagement';

    private static final String HIGH_FREQUENCY_SUBJECT_PREFIX =
        '[ABM Signal] - High Frequency Signal Activity';

    private static final String REVIEW_SUBJECT_PREFIX =
        'Review Elevated ABM Behavioral Signal Activity';


    public Database.QueryLocator start(Database.BatchableContext bc) {

        return Database.getQueryLocator([
            SELECT Id, Name
            FROM Account
        ]);
    }


    public void execute(
        Database.BatchableContext bc,
        List<Account> scope
    ) {

        if (scope.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Map<Id, Account>(scope).keySet();

        Datetime thirtyDaysAgo = System.now().addDays(-LOOKBACK_DAYS);


        /*
         * ============================================================
         * PHASE 1
         * Find qualifying Tasks on Contacts
         * ============================================================
         */

        Map<Id, Id> contactToAccountMap = new Map<Id, Id>();

        for (Contact con : [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId IN :accountIds
        ]) {
            contactToAccountMap.put(con.Id, con.AccountId);
        }


        Map<Id, Integer> qualifyingTaskCountByAccount =
            new Map<Id, Integer>();

        Map<Id, Datetime> latestQualifyingTaskByAccount =
            new Map<Id, Datetime>();


        if (!contactToAccountMap.isEmpty()) {

            for (Task taskRecord : [
                SELECT Id, WhoId, Subject, CreatedDate
                FROM Task
                WHERE WhoId IN :contactToAccountMap.keySet()
                AND Subject LIKE :QUALIFYING_SIGNAL_PREFIX
                AND CreatedDate >= :thirtyDaysAgo
            ]) {

                Id accountId =
                    contactToAccountMap.get(taskRecord.WhoId);

                if (accountId == null) {
                    continue;
                }

                Integer currentCount =
                    qualifyingTaskCountByAccount.containsKey(accountId)
                    ? qualifyingTaskCountByAccount.get(accountId)
                    : 0;

                qualifyingTaskCountByAccount.put(
                    accountId,
                    currentCount + 1
                );

                if (
                    !latestQualifyingTaskByAccount.containsKey(accountId) ||
                    taskRecord.CreatedDate >
                    latestQualifyingTaskByAccount.get(accountId)
                ) {
                    latestQualifyingTaskByAccount.put(
                        accountId,
                        taskRecord.CreatedDate
                    );
                }
            }
        }


        /*
         * ============================================================
         * Get existing MCLE Tasks on Accounts
         * ============================================================
         */

        Map<Id, Datetime> latestMCLEByAccount =
            new Map<Id, Datetime>();

        for (Task taskRecord : [
            SELECT Id, WhatId, Subject, CreatedDate
            FROM Task
            WHERE WhatId IN :accountIds
            AND Subject LIKE :MCLE_SUBJECT_PREFIX + '%'
            AND CreatedDate >= :thirtyDaysAgo
        ]) {

            if (
                !latestMCLEByAccount.containsKey(taskRecord.WhatId) ||
                taskRecord.CreatedDate >
                latestMCLEByAccount.get(taskRecord.WhatId)
            ) {
                latestMCLEByAccount.put(
                    taskRecord.WhatId,
                    taskRecord.CreatedDate
                );
            }
        }


        /*
         * ============================================================
         * Create MCLE Tasks
         *
         * Conditions:
         * 1. >= 3 qualifying Contact Tasks in 30 days
         * 2. No existing MCLE Task
         *    OR
         *    A new qualifying Task exists after latest MCLE Task
         * ============================================================
         */

        List<Task> mcleTasksToInsert = new List<Task>();

        String timestamp =
            System.now().format('yyyy-MM-dd HH:mm:ss');

        for (Account acc : scope) {

            Integer qualifyingCount =
                qualifyingTaskCountByAccount.containsKey(acc.Id)
                ? qualifyingTaskCountByAccount.get(acc.Id)
                : 0;

            if (
                qualifyingCount <
                QUALIFYING_TASK_THRESHOLD
            ) {
                continue;
            }

            Datetime latestQualifyingTask =
                latestQualifyingTaskByAccount.get(acc.Id);

            Datetime latestMCLE =
                latestMCLEByAccount.get(acc.Id);

            Boolean createMCLE = false;


            if (latestMCLE == null) {

                createMCLE = true;

            } else if (
                latestQualifyingTask != null &&
                latestQualifyingTask > latestMCLE
            ) {

                createMCLE = true;
            }


            if (createMCLE) {

                Task mcleTask = new Task();

                mcleTask.Subject =
                    MCLE_SUBJECT_PREFIX +
                    ' - ' +
                    timestamp;

                mcleTask.WhatId = acc.Id;

                mcleTask.Status = 'Completed';

                mcleTask.ABM_Behavioral_Signal__c = true;

                mcleTask.Signal_Type__c =
                    'Multi-Contact Account Engagement';

                mcleTask.Engagement_Channel__c =
                    'Account Rollup';

                mcleTask.Signal_Date__c =
                    latestQualifyingTask;

                mcleTasksToInsert.add(mcleTask);
            }
        }


        /*
         * Insert MCLE Tasks first.
         *
         * This ensures that the High Frequency check below uses
         * actual Account Tasks from the database.
         */
        if (!mcleTasksToInsert.isEmpty()) {
            insert mcleTasksToInsert;
        }


        /*
         * ============================================================
         * PHASE 2
         * Re-query MCLE Tasks after insertion
         * ============================================================
         */

        Map<Id, Integer> mcleCountByAccount =
            new Map<Id, Integer>();

        Map<Id, Datetime> latestMCLEAfterInsertByAccount =
            new Map<Id, Datetime>();

        for (Task taskRecord : [
            SELECT Id, WhatId, Subject, CreatedDate, Signal_Date__c
            FROM Task
            WHERE WhatId IN :accountIds
            AND Subject LIKE :MCLE_SUBJECT_PREFIX + '%'
            AND CreatedDate >= :thirtyDaysAgo
        ]) {

            Integer currentCount =
                mcleCountByAccount.containsKey(taskRecord.WhatId)
                ? mcleCountByAccount.get(taskRecord.WhatId)
                : 0;

            mcleCountByAccount.put(
                taskRecord.WhatId,
                currentCount + 1
            );

            if (
                !latestMCLEAfterInsertByAccount.containsKey(
                    taskRecord.WhatId
                ) ||
                taskRecord.CreatedDate >
                latestMCLEAfterInsertByAccount.get(
                    taskRecord.WhatId
                )
            ) {
                latestMCLEAfterInsertByAccount.put(
                    taskRecord.WhatId,
                    taskRecord.CreatedDate
                );
            }
        }


        /*
         * ============================================================
         * Get existing High Frequency Activity Tasks
         * ============================================================
         */

        Map<Id, Datetime> latestHighFrequencyByAccount =
            new Map<Id, Datetime>();

        for (Task taskRecord : [
            SELECT Id, WhatId, Subject, CreatedDate
            FROM Task
            WHERE WhatId IN :accountIds
            AND Subject LIKE :HIGH_FREQUENCY_SUBJECT_PREFIX + '%'
            AND CreatedDate >= :thirtyDaysAgo
        ]) {

            if (
                !latestHighFrequencyByAccount.containsKey(
                    taskRecord.WhatId
                ) ||
                taskRecord.CreatedDate >
                latestHighFrequencyByAccount.get(
                    taskRecord.WhatId
                )
            ) {
                latestHighFrequencyByAccount.put(
                    taskRecord.WhatId,
                    taskRecord.CreatedDate
                );
            }
        }


        /*
         * ============================================================
         * Get Marketing Operations Lead
         * ============================================================
         */

        List<User> marketingOpsUsers = [
            SELECT Id
            FROM User
            WHERE Name = 'Marketing Operations Lead'
            AND IsActive = true
            LIMIT 1
        ];

        Id marketingOpsLeadId =
            marketingOpsUsers.isEmpty()
            ? null
            : marketingOpsUsers[0].Id;


        /*
         * ============================================================
         * Create High Frequency Tasks
         *
         * Conditions:
         * 1. >= 3 MCLE Tasks in 30 days
         * 2. No High Frequency Activity Task exists
         *    OR
         *    A new MCLE Task was created after the last
         *    High Frequency Activity Task
         * ============================================================
         */

        List<Task> highFrequencyTasksToInsert =
            new List<Task>();


        for (Account acc : scope) {

            Integer mcleCount =
                mcleCountByAccount.containsKey(acc.Id)
                ? mcleCountByAccount.get(acc.Id)
                : 0;

            if (
                mcleCount <
                HIGH_FREQUENCY_THRESHOLD
            ) {
                continue;
            }

            Datetime latestMCLE =
                latestMCLEAfterInsertByAccount.get(acc.Id);

            Datetime latestHighFrequency =
                latestHighFrequencyByAccount.get(acc.Id);

            Boolean createHighFrequency = false;


            if (latestHighFrequency == null) {

                createHighFrequency = true;

            } else if (
                latestMCLE != null &&
                latestMCLE > latestHighFrequency
            ) {

                createHighFrequency = true;
            }


            if (!createHighFrequency) {
                continue;
            }


            /*
             * --------------------------------------------------------
             * 1. High Frequency Account Activity Task
             * --------------------------------------------------------
             */

            Task frequencyTask = new Task();

            frequencyTask.Subject =
                HIGH_FREQUENCY_SUBJECT_PREFIX +
                ' - ' +
                timestamp;

            frequencyTask.WhatId = acc.Id;

            frequencyTask.Status = 'Completed';

            frequencyTask.ABM_Behavioral_Signal__c = true;

            frequencyTask.Signal_Frequency_Event__c = true;

            frequencyTask.Signal_Date__c = latestMCLE;

            highFrequencyTasksToInsert.add(frequencyTask);


            /*
             * --------------------------------------------------------
             * 2. Marketing Operations Review Task
             * --------------------------------------------------------
             */

            Task reviewTask = new Task();

            reviewTask.Subject =
                REVIEW_SUBJECT_PREFIX +
                ' - ' +
                timestamp;

            reviewTask.WhatId = acc.Id;

            if (marketingOpsLeadId != null) {
                reviewTask.OwnerId = marketingOpsLeadId;
            }

            reviewTask.Status = 'Open';

            reviewTask.Priority = 'High';

            reviewTask.Type = 'ABM Signal Review';

            reviewTask.Signal_Review_Required__c = true;


            /*
             * Due Date =
             * most recent qualifying engagement + 30 days
             */
            Datetime latestEngagement =
                latestQualifyingTaskByAccount.get(acc.Id);

            if (latestEngagement != null) {

                reviewTask.ActivityDate =
                    latestEngagement.date().addDays(LOOKBACK_DAYS);
            }


            reviewTask.Description =
                'This ABM target account has reached the elevated ' +
                'behavioral signal threshold.\n\n' +

                'Account: ' + acc.Name + '\n' +
                'Signal Type: Multi-Contact Account Engagement\n' +
                'Signal Count: ' + mcleCount + '\n' +

                'Date Range: ' +
                String.valueOf(thirtyDaysAgo.date()) +
                ' - ' +
                String.valueOf(System.today()) +
                '\n' +

                'Most Recent Signal Date: ' +
                String.valueOf(latestMCLE) +
                '\n\n' +

                'Please review whether the account should remain in ' +
                'observation, receive adjusted nurture, or be considered ' +
                'for future ABM action triggers.';

            highFrequencyTasksToInsert.add(reviewTask);
        }


        if (!highFrequencyTasksToInsert.isEmpty()) {
            insert highFrequencyTasksToInsert;
        }
    }


    public void finish(Database.BatchableContext bc) {
        // No additional processing required.
    }
}