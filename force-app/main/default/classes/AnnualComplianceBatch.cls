global with sharing class AnnualComplianceBatch implements Database.Batchable<SObject> {

    private Id accountId;

    // Constants
    private static final String ACCOUNT_STATUS = 'Active';
    private static final String TASK_SUBJECT = 'Annual Compliance Review';
    private static final String TASK_STATUS = 'Not Started';
    private static final String TASK_PRIORITY = 'High';
    private static final Integer DUE_IN_DAYS = 30;

    public AnnualComplianceBatch() {
    }

    public AnnualComplianceBatch(Id accountId) {
        this.accountId = accountId;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {

        if (accountId != null) {
            return Database.getQueryLocator([
                SELECT Id, Name, OwnerId, Owner.Name, Owner.Email, Owner.ManagerId
                FROM Account
                WHERE Id = :accountId
            ]);
        }

        return Database.getQueryLocator([
            SELECT Id, Name, OwnerId, Owner.Name, Owner.Email, Owner.ManagerId
            FROM Account
            WHERE Status__c = :ACCOUNT_STATUS
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Account> scope) {

        List<Task> tasks = new List<Task>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        Set<Id> managerIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();

        for (Account acc : scope) {
            accountIds.add(acc.Id);

            if (acc.Owner.ManagerId != null) {
                managerIds.add(acc.Owner.ManagerId);
            }
        }

        // Query Managers
        List<User> managers = [SELECT Id, Name, Email FROM User WHERE Id IN :managerIds AND IsActive = true];
        Map<Id, User> managerMap = new Map<Id, User>();

        for (User manager : managers) {
            managerMap.put(manager.Id, manager);
        }

        // Duplicate Check
        Integer currentYear = Date.today().year();
        Set<Id> processedAccounts = new Set<Id>();

        List<Task> existingTasks = [SELECT Id, WhatId FROM Task WHERE WhatId IN :accountIds 
            AND Subject LIKE :TASK_SUBJECT + '%'
            AND CALENDAR_YEAR(CreatedDate) = :currentYear];

        for (Task existingTask : existingTasks) {
            processedAccounts.add(existingTask.WhatId);
        }

        for (Account acc : scope) {

            // Skip if compliance task already exists
            if (processedAccounts.contains(acc.Id)) {
                continue;
            }

            User owner = acc.Owner;
            User manager = managerMap.get(owner.ManagerId);

            // Owner Task
            tasks.add(new Task(
                Subject = TASK_SUBJECT + ' - ' + acc.Name,
                WhatId = acc.Id,
                OwnerId = owner.Id,
                Status = TASK_STATUS,
                Priority = TASK_PRIORITY,
                ActivityDate = Date.today().addDays(DUE_IN_DAYS),
                Description = 'Please complete the Annual Compliance Review for this Account.'
            ));

            // Manager Task
            if (manager != null) {
                tasks.add(new Task(
                    Subject = TASK_SUBJECT + ' - ' + acc.Name,
                    WhatId = acc.Id,
                    OwnerId = manager.Id,
                    Status = TASK_STATUS,
                    Priority = TASK_PRIORITY,
                    ActivityDate = Date.today().addDays(DUE_IN_DAYS),
                    Description = 'Please monitor the Annual Compliance Review for your team member.'
                ));
            }

            // Generate Account record URL
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();
            String accountUrl = baseUrl + '/' + acc.Id;

            // Owner Email
            if (owner.Email != null) {
                Messaging.SingleEmailMessage ownerMail = new Messaging.SingleEmailMessage();
                ownerMail.setToAddresses(new String[]{ owner.Email });
                ownerMail.setSubject(TASK_SUBJECT + ' - ' + acc.Name);

                String ownerBody = '<p>Dear ' + owner.Name + ',</p>' +
                    '<p>Please complete the <b>Annual Compliance Review</b> for the following Account:</p>' +
                    '<p><b>Account:</b> ' + acc.Name + '</p>' +
                    '<p><a href="' + accountUrl + '">View Account Record</a></p>' +
                    '<p>A task has been assigned to you in Salesforce.</p>' +
                    '<br/><p>Thank you.</p>';

                ownerMail.setHtmlBody(ownerBody);
                emails.add(ownerMail);
            }

            // Manager Email
            if (manager != null && manager.Email != null) {
                Messaging.SingleEmailMessage managerMail = new Messaging.SingleEmailMessage();
                managerMail.setToAddresses(new String[]{ manager.Email });
                managerMail.setSubject('Manager Notification - ' + TASK_SUBJECT + ' - ' + acc.Name);

                String managerBody = '<p>Dear ' + manager.Name + ',</p>' +
                    '<p>Please monitor the <b>Annual Compliance Review</b> for the following Account:</p>' +
                    '<p><b>Account:</b> ' + acc.Name + '</p>' +
                    '<p><a href="' + accountUrl + '">View Account Record</a></p>' +
                    '<p>The review task has been assigned to your team member.</p>' +
                    '<br/><p>Thank you.</p>';

                managerMail.setHtmlBody(managerBody);
                emails.add(managerMail);
            }
        }

        if (!tasks.isEmpty()) {
            Database.insert(tasks, false);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception ex) {
            }
        }
    }

    global void finish(Database.BatchableContext bc) {
    }
}