public with sharing class AccountPlanQuarterlyReviewTaskService {

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

        Set<Id> ownerIds = new Set<Id>();
        for (AccountPlan plan : activePlans) {
            if (String.valueOf(plan.OwnerId).startsWith('005')) {
                ownerIds.add(plan.OwnerId);
            }
        }

        Map<Id, User> userMap = new Map<Id, User>([
            SELECT Id, Name, ManagerId, Manager.Name 
            FROM User 
            WHERE Id IN :ownerIds
        ]);

        Set<Id> accountIds = new Set<Id>();
        Set<Id> targetUserIds = new Set<Id>();
        for (AccountPlan plan : activePlans) {
            accountIds.add(plan.AccountId);
            if (userMap.containsKey(plan.OwnerId)) {
                User u = userMap.get(plan.OwnerId);
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
            WHERE Subject = 'Quarterly Account Plan Review' 
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
            if (!userMap.containsKey(plan.OwnerId)) {
                continue;
            }
            User ownerUser = userMap.get(plan.OwnerId);

            String ownerTaskKey = plan.AccountId + '_' + plan.OwnerId;
            if (!existingTaskKeys.contains(ownerTaskKey)) {
                tasksToInsert.add(buildReviewTask(plan.AccountId, plan.OwnerId, instructions));
            }

            if (ownerUser.ManagerId != null) {
                String managerTaskKey = plan.AccountId + '_' + ownerUser.ManagerId;
                if (!existingTaskKeys.contains(managerTaskKey)) {
                    tasksToInsert.add(buildReviewTask(plan.AccountId, ownerUser.ManagerId, instructions));
                }
            } else {
                missingManagerLogs.add('Account Plan: "' + plan.Name + '" | Owner: ' + ownerUser.Name);
            }
        }

        if (!tasksToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(tasksToInsert, false);
            
            List<CustomNotificationType> notificationTypes = [
                SELECT Id, DeveloperName 
                FROM CustomNotificationType 
                WHERE DeveloperName = 'Account_Plan_Notification' 
                LIMIT 1
            ];
            
            if (!notificationTypes.isEmpty()) {
                Id notificationTypeId = notificationTypes[0].Id;
                
                for (Integer i = 0; i < results.size(); i++) {
                    Database.SaveResult sr = results[i];
                    
                    if (sr.isSuccess()) {
                        Task createdTask = tasksToInsert[i];
                        
                        Messaging.CustomNotification notification = new Messaging.CustomNotification();
                        notification.setTitle('New Task Assigned: Quarterly Account Plan Review');
                        notification.setBody('A quarterly review task has been assigned to you. Please complete the review within 30 days.');
                        notification.setNotificationTypeId(notificationTypeId);
                        notification.setTargetId(sr.getId());
                        
                        try {
                            notification.send(new Set<String>{ createdTask.OwnerId });
                        } catch (Exception e) {
                            System.debug('Error sending custom notification: ' + e.getMessage());
                        }
                    }
                }
            }
        }

        if (!missingManagerLogs.isEmpty()) {
            notifySalesOpsOfMissingManagers(missingManagerLogs);
        }
    }

    public static void monitorInactivityAndNotify() {
        Date twoMonthsAgo = System.today().addMonths(-2);

        List<AccountPlan> stalePlans = [
            SELECT Id, Name, Status, OwnerId, AccountId, Account.Name, LastModifiedDate 
            FROM AccountPlan 
            WHERE Status = 'Active' 
            AND AccountId != null
            AND LastModifiedDate < :twoMonthsAgo
        ];

        if (stalePlans.isEmpty()) {
            return;
        }

        Set<Id> ownerIds = new Set<Id>();
        for (AccountPlan plan : stalePlans) {
            if (String.valueOf(plan.OwnerId).startsWith('005')) {
                ownerIds.add(plan.OwnerId);
            }
        }

        Map<Id, User> userMap = new Map<Id, User>([
            SELECT Id, Name, ManagerId, Manager.Email, Manager.Name 
            FROM User 
            WHERE Id IN :ownerIds
        ]);

        List<AccountPlan> plansToUpdate = new List<AccountPlan>();
        Map<Id, List<AccountPlan>> managerPlansMap = new Map<Id, List<AccountPlan>>();
        List<AccountPlan> orphanPlans = new List<AccountPlan>();

        for (AccountPlan plan : stalePlans) {
            plan.Status = 'Inactive';
            plansToUpdate.add(plan);

            if (userMap.containsKey(plan.OwnerId)) {
                User ownerUser = userMap.get(plan.OwnerId);
                if (ownerUser.ManagerId != null) {
                    if (!managerPlansMap.containsKey(ownerUser.ManagerId)) {
                        managerPlansMap.put(ownerUser.ManagerId, new List<AccountPlan>());
                    }
                    managerPlansMap.get(ownerUser.ManagerId).add(plan);
                } else {
                    orphanPlans.add(plan);
                }
            } else {
                orphanPlans.add(plan);
            }
        }

        if (!plansToUpdate.isEmpty()) {
            Database.update(plansToUpdate, false);
        }

        // Create Escalation Tasks
        List<Task> escalationTasks = new List<Task>();
        for (AccountPlan plan : stalePlans) {
            User owner = userMap.get(plan.OwnerId);

            // Task for Account Owner
            escalationTasks.add(new Task(
                Subject = 'Inactive Account Plan Escalation',
                Status = 'New',
                Priority = 'High',
                WhatId = plan.AccountId,
                OwnerId = plan.OwnerId,
                ActivityDate = System.today().addDays(7),
                Description = 'This Account Plan has been automatically marked Inactive because there has been no activity for more than two months. ' +
                              'Please review and reactivate it if required.'
            ));

            // Task for Reporting Manager
            if (owner != null && owner.ManagerId != null) {
                escalationTasks.add(new Task(
                    Subject = 'Inactive Account Plan Escalation',
                    Status = 'New',
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

        // Prepare Email Notifications
        List<Messaging.SingleEmailMessage> alerts = new List<Messaging.SingleEmailMessage>();
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        // Manager Notifications
        for (Id managerId : managerPlansMap.keySet()) {
            List<AccountPlan> managedPlans = managerPlansMap.get(managerId);
            User firstPlanOwner = userMap.get(managedPlans[0].OwnerId);
            
            if (firstPlanOwner == null || firstPlanOwner.Manager == null || String.isBlank(firstPlanOwner.Manager.Email)) {
                continue;
            }
            String managerEmail = firstPlanOwner.Manager.Email;

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { managerEmail });
            mail.setSubject('Management Alert: Stale Account Plans Marked Inactive');
            
            String body = 'The following Account Plans managed under your hierarchy have been automatically ' +
                          'marked as "Inactive" due to 2+ months of system inactivity:\n\n';
            for (AccountPlan p : managedPlans) {
                User owner = userMap.get(p.OwnerId);
                String recordLink = baseUrl + '/lightning/r/AccountPlan/' + p.Id + '/view';
                String accountNameStr = (p.Account != null) ? p.Account.Name : 'No Account Associated';
                String ownerNameStr = (owner != null) ? owner.Name : 'Unknown Owner';
                
                body += '  Plan Name: ' + p.Name + '\n';
                body += '  Account Name: ' + accountNameStr + '\n';
                body += '  Account Owner: ' + ownerNameStr + '\n';
                body += '  Date of Last Activity: ' + p.LastModifiedDate.format() + '\n';
                body += '  Account Plan Status: Inactive\n';
                body += '  Link to Record: ' + recordLink + '\n\n';
            }
            body += 'Please review with your team members to reactivate if necessary.';
            mail.setPlainTextBody(body);
            alerts.add(mail);
        }

        // Sales Ops Notifications
        if (!orphanPlans.isEmpty()) {
            User opsUser = fetchSalesOpsUser();
            if (opsUser != null && String.isNotBlank(opsUser.Email)) {
                Messaging.SingleEmailMessage opsMail = new Messaging.SingleEmailMessage();
                opsMail.setToAddresses(new String[] { opsUser.Email });
                opsMail.setSubject('Sales Ops Alert: Stale Account Plans with No Active Manager');
                
                String body = 'The following Account Plans have been set to Inactive due to inactivity, but ' +
                              'their owners do not have a standard reporting manager assigned:\n\n';
                for (AccountPlan p : orphanPlans) {
                    User owner = userMap.get(p.OwnerId);
                    String ownerName = owner != null ? owner.Name : 'Unknown Owner';
                    String recordLink = baseUrl + '/lightning/r/AccountPlan/' + p.Id + '/view';
                    String accountNameStr = (p.Account != null) ? p.Account.Name : 'No Account Associated';
                    
                    body += '- Plan Name: ' + p.Name + '\n';
                    body += '  Account Name: ' + accountNameStr + '\n';
                    body += '  Account Owner: ' + ownerName + '\n';
                    body += '  Date of Last Activity: ' + p.LastModifiedDate.format() + '\n';
                    body += '  Account Plan Status: Inactive\n';
                    body += '  Link to Record: ' + recordLink + '\n\n';
                }
                opsMail.setPlainTextBody(body);
                opsMail.setSaveAsActivity(false);
                alerts.add(opsMail);
            }
        }

        if (!alerts.isEmpty()) {
            Messaging.sendEmail(alerts, false);
        }
    }

    private static Task buildReviewTask(Id accountId, Id assigneeId, String instructions) {
        return new Task(
            Subject = 'Quarterly Account Plan Review',
            Status = 'Open',
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
        
        String body = 'The quarterly generation routine created owner tasks, but could not ' +
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
        List<User> opsUsers = [
            SELECT Id, Email 
            FROM User 
            WHERE Name = 'Sales Operations User' 
            AND IsActive = true 
            LIMIT 1
        ];
        return opsUsers.isEmpty() ? null : opsUsers[0];
    }
}