public with sharing class AccountPlanQuarterlyReviewTaskService {

    private static final String TASK_STATUS_OPEN = 'Not Started';
    private static final String REVIEW_SUBJECT = 'Quarterly Account Plan Review';
    private static final String ESCALATION_SUBJECT = 'Inactive Account Plan Escalation';
    private static final String SALES_OPS_USER_NAME = 'Sales Operations User';

    @TestVisible private static Date cutoffDateOverride;

    private static Boolean opsUserLoaded = false;
    private static User cachedOpsUser;



    public static void generateQuarterlyReviewTasks() {
        List<AccountPlan> activePlans = [
            SELECT Id, Name, OwnerId, AccountId
            FROM AccountPlan
            WHERE Status = 'Active'
            AND AccountId != null
        ];

        if (activePlans.isEmpty()) {
            return;
        }

        Map<Id, User> userMap = new Map<Id, User>([
            SELECT Id, Name, ManagerId, Manager.Name
            FROM User
            WHERE Id IN :getUserOwnerIds(activePlans)
        ]);

        Set<Id> accountIds = new Set<Id>();
        Set<Id> targetUserIds = new Set<Id>();

        for (AccountPlan plan : activePlans) {
            accountIds.add(plan.AccountId);

            User u = userMap.get(plan.OwnerId);
            if (u != null) {
                targetUserIds.add(u.Id);

                if (u.ManagerId != null) {
                    targetUserIds.add(u.ManagerId);
                }
            }
        }

        Set<String> existingTaskKeys = new Set<String>();

        for (Task t : [
            SELECT Id, WhatId, OwnerId
            FROM Task
            WHERE Subject = :REVIEW_SUBJECT
            AND WhatId IN :accountIds
            AND OwnerId IN :targetUserIds
            AND CreatedDate = THIS_QUARTER
        ]) {
            existingTaskKeys.add(t.WhatId + '_' + t.OwnerId);
        }

        List<Task> tasksToInsert = new List<Task>();
        List<String> missingManagerLogs = new List<String>();
        String instructions = AccountPlanQuarterlyReviewTaskUtils.getReviewInstructions();

        for (AccountPlan plan : activePlans) {
            User ownerUser = userMap.get(plan.OwnerId);
            if (ownerUser == null) {
                continue;
            }

            Boolean createdOwnerTask = false;
            String ownerTaskKey = plan.AccountId + '_' + plan.OwnerId;

            if (!existingTaskKeys.contains(ownerTaskKey)) {
                tasksToInsert.add(
                    buildReviewTask(plan.AccountId, plan.OwnerId, instructions)
                );

                existingTaskKeys.add(ownerTaskKey);
                createdOwnerTask = true;
            }

            if (ownerUser.ManagerId != null) {
                String managerTaskKey = plan.AccountId + '_' + ownerUser.ManagerId;

                if (!existingTaskKeys.contains(managerTaskKey)) {
                    tasksToInsert.add(
                        buildReviewTask(plan.AccountId, ownerUser.ManagerId, instructions)
                    );
                    existingTaskKeys.add(managerTaskKey);
                }
            } else if (createdOwnerTask) {
                missingManagerLogs.add(
                    'Account Plan: "' + plan.Name + '" | Owner: ' + ownerUser.Name
                );
            }
        }

        if (!tasksToInsert.isEmpty()) {
            insertQuarterlyReviewTasks(tasksToInsert);
        }

        if (!missingManagerLogs.isEmpty()) {
            notifySalesOpsOfMissingManagers(missingManagerLogs);
        }
    }


    public static void monitorInactivityAndNotify() {
        List<AccountPlan> stalePlans = getStalePlans();

        if (stalePlans.isEmpty()) {
            return;
        }

        Map<Id, User> userMap = getOwnerUserMap(getUserOwnerIds(stalePlans));

        List<AccountPlan> updatedPlans = deactivatePlans(stalePlans);

        if (updatedPlans.isEmpty()) {
            return;
        }

        InactivityProcessingResult result = groupPlansByManager(updatedPlans, userMap);

        createEscalationTasks(updatedPlans, userMap);
        sendInactivityNotifications(
            result.managerPlansMap,
            result.orphanPlans,
            userMap
        );
    }

    private static List<AccountPlan> getStalePlans() {
        Date twoMonthsAgo = cutoffDateOverride != null
            ? cutoffDateOverride
            : System.today().addMonths(-2);

        return [
            SELECT Id, Name, Status, OwnerId, AccountId, Account.Name, LastModifiedDate
            FROM AccountPlan
            WHERE Status = 'Active'
            AND AccountId != null
            AND LastModifiedDate < :twoMonthsAgo
        ];
    }

    private static Map<Id, User> getOwnerUserMap(Set<Id> ownerIds) {
        return new Map<Id, User>([
            SELECT Id, Name, ManagerId, Manager.Email, Manager.Name
            FROM User
            WHERE Id IN :ownerIds
        ]);
    }

    private static List<AccountPlan> deactivatePlans(List<AccountPlan> stalePlans) {
        for (AccountPlan plan : stalePlans) {
            plan.Status = 'Inactive';
        }

        List<AccountPlan> updated = new List<AccountPlan>();
        Database.SaveResult[] results = Database.update(stalePlans, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                updated.add(stalePlans[i]);
            } else {
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(
                        'ACCOUNT PLAN UPDATE ERROR (' + stalePlans[i].Id + '): ' +
                        err.getMessage()
                    );
                }
            }
        }

        return updated;
    }

    private static InactivityProcessingResult groupPlansByManager(
        List<AccountPlan> plans,
        Map<Id, User> userMap
    ) {
        InactivityProcessingResult result = new InactivityProcessingResult();

        for (AccountPlan plan : plans) {
            User ownerUser = userMap.get(plan.OwnerId);

            if (ownerUser != null && ownerUser.ManagerId != null) {
                if (!result.managerPlansMap.containsKey(ownerUser.ManagerId)) {
                    result.managerPlansMap.put(
                        ownerUser.ManagerId,
                        new List<AccountPlan>()
                    );
                }
                result.managerPlansMap.get(ownerUser.ManagerId).add(plan);
            } else {
                result.orphanPlans.add(plan);
            }
        }

        return result;
    }

    private static void createEscalationTasks(
        List<AccountPlan> plans,
        Map<Id, User> userMap
    ) {
        List<Task> escalationTasks = new List<Task>();

        for (AccountPlan plan : plans) {
            User owner = userMap.get(plan.OwnerId);

            // Tasks can't be owned by queues, so only escalate to real users
            if (owner == null) {
                continue;
            }

            escalationTasks.add(new Task(
                Subject = ESCALATION_SUBJECT,
                Status = TASK_STATUS_OPEN,
                Priority = 'High',
                WhatId = plan.AccountId,
                OwnerId = plan.OwnerId,
                ActivityDate = System.today().addDays(7),
                Description = 'This Account Plan has been automatically marked Inactive because there has been no activity for more than two months. ' +
                              'Please review and reactivate it if required.'
            ));

            if (owner.ManagerId != null) {
                escalationTasks.add(new Task(
                    Subject = ESCALATION_SUBJECT,
                    Status = TASK_STATUS_OPEN,
                    Priority = 'High',
                    WhatId = plan.AccountId,
                    OwnerId = owner.ManagerId,
                    ActivityDate = System.today().addDays(7),
                    Description = 'An Account Plan owned by one of your team members has been automatically marked Inactive due to inactivity. ' +
                                  'Please review it with the Account Owner.'
                ));
            }
        }

        if (!escalationTasks.isEmpty()) {
            Database.SaveResult[] results = Database.insert(escalationTasks, false);

            for (Database.SaveResult sr : results) {
                if (!sr.isSuccess()) {
                    for (Database.Error err : sr.getErrors()) {
                        System.debug('TASK INSERT ERROR: ' + err.getMessage());
                    }
                }
            }
        }
    }


    private static void sendInactivityNotifications(
        Map<Id, List<AccountPlan>> managerPlansMap,
        List<AccountPlan> orphanPlans,
        Map<Id, User> userMap
    ) {
        List<Messaging.SingleEmailMessage> alerts = new List<Messaging.SingleEmailMessage>();

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        alerts.addAll(buildManagerNotifications(managerPlansMap, userMap, baseUrl));
        alerts.addAll(buildSalesOpsNotifications(orphanPlans, userMap, baseUrl));

        if (!alerts.isEmpty()) {
            Messaging.sendEmail(alerts, false);
        }
    }

    private static List<Messaging.SingleEmailMessage> buildManagerNotifications(
        Map<Id, List<AccountPlan>> managerPlansMap,
        Map<Id, User> userMap,
        String baseUrl
    ) {
        List<Messaging.SingleEmailMessage> alerts =
            new List<Messaging.SingleEmailMessage>();

        for (Id managerId : managerPlansMap.keySet()) {
            List<AccountPlan> managedPlans = managerPlansMap.get(managerId);
            User firstPlanOwner = userMap.get(managedPlans[0].OwnerId);

            if (
                firstPlanOwner == null ||
                firstPlanOwner.Manager == null ||
                String.isBlank(firstPlanOwner.Manager.Email)
            ) {
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

            mail.setToAddresses(new String[] { firstPlanOwner.Manager.Email });
            mail.setSubject('Management Alert: Stale Account Plans Marked Inactive');

            String body =
                'The following Account Plans managed under your hierarchy have been automatically ' +
                'marked as "Inactive" due to 2+ months of system inactivity:\n\n';

            for (AccountPlan p : managedPlans) {
                body += formatPlanDetails(p, userMap, baseUrl, '  ');
            }

            body += 'Please review with your team members to reactivate if necessary.';

            mail.setPlainTextBody(body);
            alerts.add(mail);
        }

        return alerts;
    }

    private static List<Messaging.SingleEmailMessage> buildSalesOpsNotifications(
        List<AccountPlan> orphanPlans,
        Map<Id, User> userMap,
        String baseUrl
    ) {
        List<Messaging.SingleEmailMessage> alerts =
            new List<Messaging.SingleEmailMessage>();

        if (orphanPlans.isEmpty()) {
            return alerts;
        }

        User opsUser = fetchSalesOpsUser();

        if (opsUser == null || String.isBlank(opsUser.Email)) {
            return alerts;
        }

        Messaging.SingleEmailMessage opsMail = new Messaging.SingleEmailMessage();

        opsMail.setToAddresses(new String[] { opsUser.Email });
        opsMail.setSubject('Sales Ops Alert: Stale Account Plans with No Active Manager');

        String body =
            'The following Account Plans have been set to Inactive due to inactivity, but ' +
            'their owners do not have a standard reporting manager assigned:\n\n';

        for (AccountPlan p : orphanPlans) {
            body += '- ' + formatPlanDetails(p, userMap, baseUrl, '  ').trim() + '\n\n';
        }

        opsMail.setPlainTextBody(body);
        opsMail.setSaveAsActivity(false);
        alerts.add(opsMail);

        return alerts;
    }

    private static String formatPlanDetails(
        AccountPlan p,
        Map<Id, User> userMap,
        String baseUrl,
        String indent
    ) {
        User owner = userMap.get(p.OwnerId);
        String recordLink = baseUrl + '/lightning/r/AccountPlan/' + p.Id + '/view';
        String accountName = p.Account != null ? p.Account.Name : 'No Account Associated';
        String ownerName = owner != null ? owner.Name : 'Unknown Owner';

        return indent + 'Plan Name: ' + p.Name + '\n' +
               indent + 'Account Name: ' + accountName + '\n' +
               indent + 'Account Owner: ' + ownerName + '\n' +
               indent + 'Date of Last Activity: ' + p.LastModifiedDate.format() + '\n' +
               indent + 'Account Plan Status: Inactive\n' +
               indent + 'Link to Record: ' + recordLink + '\n\n';
    }


    private static void insertQuarterlyReviewTasks(List<Task> tasksToInsert) {
        Database.SaveResult[] results = Database.insert(tasksToInsert, false);

        Boolean anySuccess = false;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                anySuccess = true;
            } else {
                for (Database.Error err : sr.getErrors()) {
                    System.debug('REVIEW TASK INSERT ERROR: ' + err.getMessage());
                }
            }
        }

        if (!anySuccess) {
            return;
        }

        List<CustomNotificationType> notificationTypes = [
            SELECT Id, DeveloperName
            FROM CustomNotificationType
            WHERE DeveloperName = 'Account_Plan_Notification'
            LIMIT 1
        ];

        if (notificationTypes.isEmpty()) {
            return;
        }

        Id notificationTypeId = notificationTypes[0].Id;

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                continue;
            }

            if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
                System.debug('Callout limit reached; skipping remaining custom notifications.');
                break;
            }

            Messaging.CustomNotification notification =
                new Messaging.CustomNotification();

            notification.setTitle('New Task Assigned: Quarterly Account Plan Review');
            notification.setBody(
                'A quarterly review task has been assigned to you. Please complete the review within 30 days.'
            );
            notification.setNotificationTypeId(notificationTypeId);
            notification.setTargetId(results[i].getId());

            try {
                notification.send(new Set<String>{ tasksToInsert[i].OwnerId });
            } catch (Exception e) {
                System.debug('Error sending custom notification: ' + e.getMessage());
            }
        }
    }

    private static Task buildReviewTask(
        Id accountId,
        Id assigneeId,
        String instructions
    ) {
        return new Task(
            Subject = REVIEW_SUBJECT,
            Status = TASK_STATUS_OPEN,
            Priority = 'Normal',
            OwnerId = assigneeId,
            WhatId = accountId,
            ActivityDate = System.today().addDays(30),
            Description = instructions
        );
    }

    private static void notifySalesOpsOfMissingManagers(List<String> missingLogs) {
        User opsUser = fetchSalesOpsUser();

        if (opsUser == null || String.isBlank(opsUser.Email)) {
            return;
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

        mail.setToAddresses(new String[] { opsUser.Email });
        mail.setSubject('Exception Alert: Missing Managers on Quarterly Account Plan Tasks');

        String body =
            'The quarterly generation routine created owner tasks, but could not ' +
            'assign corresponding review tasks to their leadership due to missing manager values:\n\n';

        for (String log : missingLogs) {
            body += '- ' + log + '\n';
        }

        body += '\nPlease address standard user reporting structures.';

        mail.setPlainTextBody(body);
        mail.setSaveAsActivity(false);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
    }

    private static User fetchSalesOpsUser() {
        if (!opsUserLoaded) {
            List<User> opsUsers = [
                SELECT Id, Email
                FROM User
                WHERE Name = :SALES_OPS_USER_NAME
                AND IsActive = true
                LIMIT 1
            ];
            cachedOpsUser = opsUsers.isEmpty() ? null : opsUsers[0];
            opsUserLoaded = true;
        }
        return cachedOpsUser;
    }

    private static Set<Id> getUserOwnerIds(List<AccountPlan> plans) {
        Set<Id> ownerIds = new Set<Id>();

        for (AccountPlan plan : plans) {
            if (plan.OwnerId != null && plan.OwnerId.getSObjectType() == User.SObjectType) {
                ownerIds.add(plan.OwnerId);
            }
        }

        return ownerIds;
    }

    private class InactivityProcessingResult {
        List<AccountPlan> plansToUpdate = new List<AccountPlan>();
        Map<Id, List<AccountPlan>> managerPlansMap =
            new Map<Id, List<AccountPlan>>();
        List<AccountPlan> orphanPlans = new List<AccountPlan>();
    }
}