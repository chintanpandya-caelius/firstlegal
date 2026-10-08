@IsTest
private class AccPlanQuarterlyReviewServiceTest {

    private static final String REVIEW_SUBJECT = 'Quarterly Account Plan Review';
    private static final String ESCALATION_SUBJECT = 'Inactive Account Plan Escalation';

    private static User createUser(String firstName, String lastName, Id managerId) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));

        User u = new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = ('u' + uniq).left(8),
            Email = 'user' + uniq + '@example.com',
            Username = 'user' + uniq + '@aqrts.example.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ManagerId = managerId,
            IsActive = true
        );

        // Avoid MIXED_DML_ERROR between setup and non-setup objects
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    private static User createSalesOpsUser() {
        return createUser('Sales Operations', 'User', null);
    }

    private static List<Account> createAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(Name = 'Test Account ' + i));
        }
        insert accounts;
        return accounts;
    }

    private static AccountPlan buildPlan(String name, Id accountId, Id ownerId, String status) {
        return new AccountPlan(
            Name = name,
            AccountId = accountId,
            OwnerId = ownerId,
            Status = status
        );
    }

    private static List<Task> tasksFor(Id accountId, String subject) {
        return [
            SELECT Id, Subject, Status, Priority, OwnerId, WhatId, ActivityDate, Description
            FROM Task
            WHERE WhatId = :accountId
            AND Subject = :subject
        ];
    }

    private static Set<Id> ownerIdsOf(List<Task> tasks) {
        Set<Id> ids = new Set<Id>();
        for (Task t : tasks) {
            ids.add(t.OwnerId);
        }
        return ids;
    }

    @IsTest
    static void generate_createsTasksForOwnerAndManager() {
        User manager = createUser('Mgr', 'One', null);
        User owner = createUser('Own', 'One', manager.Id);
        Account acc = createAccounts(1)[0];
        insert buildPlan('Plan A', acc.Id, owner.Id, 'Active');

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        Test.stopTest();

        List<Task> tasks = tasksFor(acc.Id, REVIEW_SUBJECT);
        System.assertEquals(2, tasks.size(), 'One task each for owner and manager');
        System.assert(ownerIdsOf(tasks).contains(owner.Id), 'Owner should get a task');
        System.assert(ownerIdsOf(tasks).contains(manager.Id), 'Manager should get a task');

        for (Task t : tasks) {
            System.assertEquals('Normal', t.Priority);
            System.assertEquals(System.today().addDays(30), t.ActivityDate);
            System.assertEquals(
                AccountPlanQuarterlyReviewTaskUtils.getReviewInstructions(),
                t.Description
            );
        }
    }

    @IsTest
    static void generate_isIdempotentWithinSameQuarter() {
        User manager = createUser('Mgr', 'Two', null);
        User owner = createUser('Own', 'Two', manager.Id);
        Account acc = createAccounts(1)[0];
        insert buildPlan('Plan B', acc.Id, owner.Id, 'Active');

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        Test.stopTest();

        System.assertEquals(
            2,
            tasksFor(acc.Id, REVIEW_SUBJECT).size(),
            'Second run must not create duplicate tasks'
        );
    }

    @IsTest
    static void generate_ownerWithoutManager_createsOwnerTaskAndAlertsSalesOps() {
        createSalesOpsUser();
        User owner = createUser('Own', 'Orphan', null);
        Account acc = createAccounts(1)[0];
        insert buildPlan('Orphan Plan', acc.Id, owner.Id, 'Active');

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        List<Task> tasks = tasksFor(acc.Id, REVIEW_SUBJECT);
        System.assertEquals(1, tasks.size(), 'Only the owner task is created');
        System.assertEquals(owner.Id, tasks[0].OwnerId);
        System.assertEquals(1, emailInvocations, 'Sales Ops should be alerted about the missing manager');
    }

    @IsTest
    static void generate_ownerWithoutManager_noSalesOpsUser_doesNotThrow() {
        // Guard: make sure no active "Sales Operations User" exists in this org
        Integer existingOps = [
            SELECT COUNT() FROM User
            WHERE Name = 'Sales Operations User' AND IsActive = true
        ];
        if (existingOps > 0) {
            return; // cannot assert the "no ops user" branch in this org
        }

        User owner = createUser('Own', 'NoOps', null);
        Account acc = createAccounts(1)[0];
        insert buildPlan('No Ops Plan', acc.Id, owner.Id, 'Active');

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(1, tasksFor(acc.Id, REVIEW_SUBJECT).size());
        System.assertEquals(0, emailInvocations, 'No email when there is no Sales Ops user');
    }

    @IsTest
    static void generate_ignoresInactivePlans() {
        User manager = createUser('Mgr', 'Three', null);
        User owner = createUser('Own', 'Three', manager.Id);
        Account acc = createAccounts(1)[0];
        insert buildPlan('Inactive Plan', acc.Id, owner.Id, 'Inactive');

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        Test.stopTest();

        System.assertEquals(0, tasksFor(acc.Id, REVIEW_SUBJECT).size());
    }

    @IsTest
    static void generate_noPlans_doesNothing() {
        Account acc = createAccounts(1)[0];

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        Test.stopTest();

        System.assertEquals(0, tasksFor(acc.Id, REVIEW_SUBJECT).size());
        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void generate_bulk_createsOwnerAndManagerTaskPerAccount() {
        User manager = createUser('Mgr', 'Bulk', null);
        User owner = createUser('Own', 'Bulk', manager.Id);
        Integer count = 20;
        List<Account> accounts = createAccounts(count);

        List<AccountPlan> plans = new List<AccountPlan>();
        for (Integer i = 0; i < count; i++) {
            plans.add(buildPlan('Bulk Plan ' + i, accounts[i].Id, owner.Id, 'Active'));
        }
        insert plans;

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        Test.stopTest();

        Integer created = [
            SELECT COUNT() FROM Task
            WHERE Subject = :REVIEW_SUBJECT AND WhatId IN :accounts
        ];
        System.assertEquals(count * 2, created);
    }


    @IsTest
    static void monitor_stalePlanWithManager_marksInactiveCreatesTasksAndEmailsManager() {
        User manager = createUser('Mgr', 'Stale', null);
        User owner = createUser('Own', 'Stale', manager.Id);
        Account acc = createAccounts(1)[0];
        AccountPlan plan = buildPlan('Stale Plan', acc.Id, owner.Id, 'Active');
        insert plan;

        AccountPlanQuarterlyReviewTaskService.cutoffDateOverride = System.today().addDays(2);

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.monitorInactivityAndNotify();
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(
            'Inactive',
            [SELECT Status FROM AccountPlan WHERE Id = :plan.Id].Status
        );

        List<Task> tasks = tasksFor(acc.Id, ESCALATION_SUBJECT);
        System.assertEquals(2, tasks.size(), 'Owner and manager each get an escalation task');
        System.assert(ownerIdsOf(tasks).contains(owner.Id));
        System.assert(ownerIdsOf(tasks).contains(manager.Id));
        for (Task t : tasks) {
            System.assertEquals('High', t.Priority);
            System.assertEquals(System.today().addDays(7), t.ActivityDate);
        }

        System.assertEquals(1, emailInvocations, 'Manager notification should be sent');
    }

    @IsTest
    static void monitor_stalePlanWithoutManager_escalatesToOwnerAndAlertsSalesOps() {
        createSalesOpsUser();
        User owner = createUser('Own', 'StaleOrphan', null);
        Account acc = createAccounts(1)[0];
        AccountPlan plan = buildPlan('Stale Orphan Plan', acc.Id, owner.Id, 'Active');
        insert plan;

        AccountPlanQuarterlyReviewTaskService.cutoffDateOverride = System.today().addDays(2);

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.monitorInactivityAndNotify();
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(
            'Inactive',
            [SELECT Status FROM AccountPlan WHERE Id = :plan.Id].Status
        );

        List<Task> tasks = tasksFor(acc.Id, ESCALATION_SUBJECT);
        System.assertEquals(1, tasks.size(), 'Only the owner is escalated when there is no manager');
        System.assertEquals(owner.Id, tasks[0].OwnerId);

        System.assertEquals(1, emailInvocations, 'Sales Ops should be alerted');
    }

    @IsTest
    static void monitor_stalePlanWithoutManager_noSalesOpsUser_doesNotThrow() {
        Integer existingOps = [
            SELECT COUNT() FROM User
            WHERE Name = 'Sales Operations User' AND IsActive = true
        ];
        if (existingOps > 0) {
            return;
        }

        User owner = createUser('Own', 'StaleNoOps', null);
        Account acc = createAccounts(1)[0];
        AccountPlan plan = buildPlan('Stale No Ops Plan', acc.Id, owner.Id, 'Active');
        insert plan;

        AccountPlanQuarterlyReviewTaskService.cutoffDateOverride = System.today().addDays(2);

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.monitorInactivityAndNotify();
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(
            'Inactive',
            [SELECT Status FROM AccountPlan WHERE Id = :plan.Id].Status
        );
        System.assertEquals(0, emailInvocations);
    }

    @IsTest
    static void monitor_freshPlan_isLeftAlone() {
        User manager = createUser('Mgr', 'Fresh', null);
        User owner = createUser('Own', 'Fresh', manager.Id);
        Account acc = createAccounts(1)[0];
        AccountPlan plan = buildPlan('Fresh Plan', acc.Id, owner.Id, 'Active');
        insert plan;

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.monitorInactivityAndNotify();
        Test.stopTest();

        System.assertEquals(
            'Active',
            [SELECT Status FROM AccountPlan WHERE Id = :plan.Id].Status
        );
        System.assertEquals(0, tasksFor(acc.Id, ESCALATION_SUBJECT).size());
        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void monitor_alreadyInactivePlan_isIgnored() {
        User manager = createUser('Mgr', 'AlreadyInactive', null);
        User owner = createUser('Own', 'AlreadyInactive', manager.Id);
        Account acc = createAccounts(1)[0];
        insert buildPlan('Already Inactive', acc.Id, owner.Id, 'Inactive');

        AccountPlanQuarterlyReviewTaskService.cutoffDateOverride = System.today().addDays(2);

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.monitorInactivityAndNotify();
        Test.stopTest();

        System.assertEquals(0, tasksFor(acc.Id, ESCALATION_SUBJECT).size());
    }

    @IsTest
    static void monitor_multiplePlansSameManager_sendsSingleManagerEmail() {
        User manager = createUser('Mgr', 'Multi', null);
        User owner1 = createUser('Own', 'Multi1', manager.Id);
        User owner2 = createUser('Own', 'Multi2', manager.Id);
        List<Account> accounts = createAccounts(2);

        insert new List<AccountPlan>{
            buildPlan('Multi Plan 1', accounts[0].Id, owner1.Id, 'Active'),
            buildPlan('Multi Plan 2', accounts[1].Id, owner2.Id, 'Active')
        };

        AccountPlanQuarterlyReviewTaskService.cutoffDateOverride = System.today().addDays(2);

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.monitorInactivityAndNotify();
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(
            2,
            [SELECT COUNT() FROM AccountPlan WHERE Status = 'Inactive' AND AccountId IN :accounts]
        );
        System.assertEquals(1, emailInvocations);
    }

    @IsTest
    static void monitor_noPlans_doesNothing() {
        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.monitorInactivityAndNotify();
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations());
    }
}