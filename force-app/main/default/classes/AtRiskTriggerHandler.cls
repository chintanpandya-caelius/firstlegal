public with sharing class AtRiskTriggerHandler {
    private static Boolean isRunning = false;

    public static void handle(List<At_Risk__c> newRecords, List<At_Risk__c> oldRecords, Boolean isInsert, Boolean isUpdate, Boolean isDelete, Boolean isUndelete) {
        if (isRunning) {
            return;
        }

        isRunning = true;

        try {
            if (isInsert && newRecords != null && !newRecords.isEmpty()) {
                Set<Id> atRiskIds = new Set<Id>();

                for (At_Risk__c risk : newRecords) {
                    if (risk.Id != null) {
                        atRiskIds.add(risk.Id);
                    }
                }

                if (!atRiskIds.isEmpty()) {
                    sendInitialNotifications(atRiskIds);
                }
            }
        } finally {
            isRunning = false;
        }
    }

    private static void sendInitialNotifications(Set<Id> atRiskIds) {
        List<At_Risk__c> risks = [
            SELECT Id, Account__c, Risk_Level__c, Risk_Indicators__c, Reported_Date__c, IsActive__c,
                   Account__r.Name, Account__r.OwnerId, Account__r.Owner.Name, Account__r.Risk_Level__c,
                   Account__r.Service_Line__c, Account__r.Account_Tenure_Date__c
            FROM At_Risk__c
            WHERE Id IN :atRiskIds
        ];

        if (risks.isEmpty()) {
            return;
        }

        Set<Id> ownerIds = new Set<Id>();

        for (At_Risk__c risk : risks) {
            if (risk.Account__r != null && risk.Account__r.OwnerId != null) {
                ownerIds.add(risk.Account__r.OwnerId);
            }
        }

        Map<Id, User> ownerMap = new Map<Id, User>([
            SELECT Id, Name, ManagerId
            FROM User
            WHERE Id IN :ownerIds
        ]);

        Set<Id> managerIds = new Set<Id>();

        for (User owner : ownerMap.values()) {
            if (owner.ManagerId != null) {
                managerIds.add(owner.ManagerId);
            }
        }

        Map<Id, User> managerMap = new Map<Id, User>([
            SELECT Id, Name, Email
            FROM User
            WHERE Id IN :managerIds
        ]);

        List<User> vpUsers = [
            SELECT Id, Email
            FROM User
            WHERE IsActive = true
            AND Title = 'VP of Sales'
        ];

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Task> tasks = new List<Task>();

        for (At_Risk__c risk : risks) {
            if (risk.Account__c == null || risk.Account__r == null) {
                continue;
            }

            User owner = ownerMap.get(risk.Account__r.OwnerId);

            if (owner == null || owner.ManagerId == null) {
                continue;
            }

            User manager = managerMap.get(owner.ManagerId);

            if (manager == null || String.isBlank(manager.Email)) {
                continue;
            }

            List<String> recipients = new List<String>();
            recipients.add(manager.Email);

            for (User vp : vpUsers) {
                if (String.isNotBlank(vp.Email) && !recipients.contains(vp.Email)) {
                    recipients.add(vp.Email);
                }
            }

            String serviceLineCode = getServiceLineCode(risk.Account__r.Service_Line__c);

            String accountTenure = risk.Account__r.Account_Tenure_Date__c != null
                ? String.valueOf(risk.Account__r.Account_Tenure_Date__c)
                : 'N/A';

            String atRiskUrl = URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/At_Risk__c/' + risk.Id + '/view';

            String subject = risk.Account__r.Name + ' assigned to ' + owner.Name + ' has been identified as At Risk based on customer health indicators.';

            String body = '<p><strong>At Risk Customer Health Alert</strong></p>' +
                '<p><strong>At Risk:</strong> <a href="' + atRiskUrl + '" target="_blank">View At Risk Record</a></p>' +
                '<ul>' +
                '<li><strong>Risk Score:</strong> ' + String.valueOf(risk.Account__r.Risk_Level__c) + '</li>' +
                '<li><strong>Primary Reason(s):</strong> ' + String.valueOf(risk.Risk_Indicators__c) + '</li>' +
                '<li><strong>Service Line:</strong> ' + serviceLineCode + '</li>' +
                '<li><strong>Account Tenure:</strong> ' + accountTenure + '</li>' +
                '</ul>' +
                '<p><strong>Recommended Manager Actions:</strong></p>' +
                '<ul>' +
                '<li>Review the account details and recent customer activity.</li>' +
                '<li>Meet with the sales representative to develop an account recovery plan.</li>' +
                '<li>Confirm customer outreach is completed within <strong>2 business days</strong>.</li>' +
                '<li>Ensure all customer interactions, risks, and next steps are documented in Salesforce.</li>' +
                '<li>Escalate to Customer Success, Sales Leadership, or other cross-functional partners if additional support is needed.</li>' +
                '</ul>' +
                '<p><strong>Manager Follow-Up Required:</strong> Please review this alert and confirm that an action plan has been established. Timely intervention improves customer retention and protects revenue.</p>';

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(recipients);
            email.setSubject(subject);
            email.setHtmlBody(body);
            email.setSaveAsActivity(false);
            emails.add(email);

            Date startDate = risk.Reported_Date__c != null ? risk.Reported_Date__c : Date.today();
            tasks.add(createFollowUpTask(risk, manager.Id, startDate));
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }

        if (!tasks.isEmpty()) {
            insert tasks;
        }
    }

    public static void processOverdueRisks() {
        List<At_Risk__c> risks = [
            SELECT Id, Account__c, Risk_Level__c, Risk_Indicators__c, Resolved_Date__c, IsActive__c,
                   Account__r.Name, Account__r.Owner.Name, Account__r.Owner.ManagerId,
                   Account__r.Owner.Manager.Email, Account__r.Risk_Level__c, Account__r.Service_Line__c
            FROM At_Risk__c
            WHERE IsActive__c = true
            AND Resolved_Date__c = null
            AND Account__c != null
        ];

        if (risks.isEmpty()) {
            return;
        }

        Set<Id> riskIds = new Set<Id>();

        for (At_Risk__c risk : risks) {
            riskIds.add(risk.Id);
        }

        Map<Id, Task> overdueTasksMap = getOverdueTasksByRisk(riskIds);

        List<User> vpUsers = [
            SELECT Id, Email
            FROM User
            WHERE IsActive = true
            AND Title = 'VP of Sales'
        ];

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Task> newTasks = new List<Task>();
        List<Task> tasksToClose = new List<Task>();

        for (At_Risk__c risk : risks) {
            if (risk.Account__r.Owner.ManagerId == null || !overdueTasksMap.containsKey(risk.Id)) {
                continue;
            }

            Task oldTask = overdueTasksMap.get(risk.Id);
            List<String> recipients = getNotificationRecipients(risk, vpUsers);

            if (recipients.isEmpty()) {
                continue;
            }

            String serviceLineCode = getServiceLineCode(risk.Account__r.Service_Line__c);
            String atRiskUrl = URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/At_Risk__c/' + risk.Id + '/view';

            String subject = 'Follow-Up Required: ' + risk.Account__r.Name + ' remains At Risk.';

            String body = '<p><strong>At Risk Follow-Up Alert</strong></p>' +
                '<p><strong>At Risk:</strong> <a href="' + atRiskUrl + '" target="_blank">At Risk</a></p>' +
                '<ul>' +
                '<li><strong>Risk Score:</strong> ' + String.valueOf(risk.Account__r.Risk_Level__c) + '</li>' +
                '<li><strong>Primary Reason(s):</strong> ' + String.valueOf(risk.Risk_Indicators__c) + '</li>' +
                '<li><strong>Service Line:</strong> ' + serviceLineCode + '</li>' +
                '</ul>' +
                '<p><strong>Manager Follow-Up Required:</strong> The previous At Risk follow-up task was not completed by its due date. Please review the account and establish or update the recovery plan.</p>';

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(recipients);
            email.setSubject(subject);
            email.setHtmlBody(body);
            emails.add(email);

            oldTask.Status = 'Closed';
            tasksToClose.add(oldTask);

            newTasks.add(createFollowUpTask(risk, risk.Account__r.Owner.ManagerId, Date.today()));
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }

        if (!tasksToClose.isEmpty()) {
            update tasksToClose;
        }

        if (!newTasks.isEmpty()) {
            insert newTasks;
        }
    }

    private static Map<Id, Task> getOverdueTasksByRisk(Set<Id> riskIds) {
        Map<Id, Task> results = new Map<Id, Task>();

        for (Task task : [
            SELECT Id, WhatId, ActivityDate, Status, CreatedDate, Description
            FROM Task
            WHERE ActivityDate < :Date.today()
            AND Status NOT IN ('Completed', 'Closed')
            AND Subject LIKE 'At Risk Follow-Up - %'
            ORDER BY CreatedDate DESC
        ]) {
            for (Id riskId : riskIds) {
                if (task.Description != null && task.Description.contains((String)riskId)) {
                    if (!results.containsKey(riskId)) {
                        results.put(riskId, task);
                    }
                    break;
                }
            }
        }

        return results;
    }

    private static List<String> getNotificationRecipients(At_Risk__c risk, List<User> vpUsers) {
        List<String> recipients = new List<String>();

        if (risk.Account__r.Owner.Manager != null && String.isNotBlank(risk.Account__r.Owner.Manager.Email)) {
            recipients.add(risk.Account__r.Owner.Manager.Email);
        }

        for (User vp : vpUsers) {
            if (String.isNotBlank(vp.Email) && !recipients.contains(vp.Email)) {
                recipients.add(vp.Email);
            }
        }

        return recipients;
    }

    private static Task createFollowUpTask(At_Risk__c risk, Id managerId, Date startDate) {
        Task task = new Task();
        task.Subject = 'At Risk Follow-Up - ' + risk.Account__r.Name;
        task.Status = 'Not Started';
        task.Priority = 'High';
        task.WhatId = risk.Account__c;
        task.OwnerId = managerId;
        task.ActivityDate = addBusinessDays(startDate, 5);
        task.Description = 'At Risk Record: ' + risk.Id + '\n\nPlease review the At Risk record and establish an account recovery/action plan.';
        return task;
    }

    private static String getServiceLineCode(String serviceLine) {
        if (String.isBlank(serviceLine)) {
            return 'N/A';
        }

        Map<String, String> serviceLineMap = new Map<String, String>{
            'Court & Process' => 'FLCP',
            'Depositions' => 'FLDS',
            'Digital' => 'FLD',
            'E-Discovery' => 'FLED',
            'Investigations' => 'FLI',
            'Records' => 'FR'
        };

        return serviceLineMap.containsKey(serviceLine) ? serviceLineMap.get(serviceLine) : 'N/A';
    }

    public static Date addBusinessDays(Date startDate, Integer numberOfBusinessDays) {
        Date result = startDate;
        Integer addedDays = 0;

        while (addedDays < numberOfBusinessDays) {
            result = result.addDays(1);
            Date referenceSunday = Date.newInstance(1970, 1, 4);
            Integer dayOfWeek = Math.mod(Math.abs(referenceSunday.daysBetween(result)), 7);

            if (dayOfWeek != 0 && dayOfWeek != 6) {
                addedDays++;
            }
        }

        return result;
    }
}