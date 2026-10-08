public without sharing class AccountEngagementBatch implements Database.Batchable<SObject> {

    private static final Integer DEFAULT_THRESHOLD_DAYS = 60;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, OwnerId, Owner.Name, Owner.Email, Owner.ManagerId, Owner.Manager.Name,
                   Owner.Manager.Email, Last_Engagement_Date__c, Days_Since_Last_Engagement__c,
                   At_Risk__c, At_Risk_Notified_On__c
            FROM Account
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        Integer thresholdDays = getThresholdDays();
        List<Account> accountsToUpdate = new List<Account>();
        List<Account> newlyAtRiskAccounts = new List<Account>();
        Date today = Date.today();

        for (Account acc : scope) {
            Integer daysSince = null;

            if (acc.Last_Engagement_Date__c != null) {
                daysSince = acc.Last_Engagement_Date__c.daysBetween(today);
            }

            if (daysSince == null) {
                continue;
            }

            if (daysSince >= thresholdDays) {
                if (acc.At_Risk__c != true) {
                    acc.At_Risk__c = true;
                    acc.At_Risk_Notified_On__c = today;
                    accountsToUpdate.add(acc);
                    newlyAtRiskAccounts.add(acc);
                }
            } else if (acc.At_Risk__c == true) {
                acc.At_Risk__c = false;
                acc.At_Risk_Notified_On__c = null;
                accountsToUpdate.add(acc);
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(accountsToUpdate, false);
        }

        if (!newlyAtRiskAccounts.isEmpty()) {
            sendAtRiskNotifications(newlyAtRiskAccounts, thresholdDays);
        }
    }

    private Integer getThresholdDays() {
        Integer thresholdDays = DEFAULT_THRESHOLD_DAYS;

        try {
            String labelValue = System.Label.Account_At_Risk_Days_Threshold;
            if (String.isNotBlank(labelValue)) {
                thresholdDays = Integer.valueOf(labelValue.trim());
            }
        } catch (Exception e) {
            thresholdDays = DEFAULT_THRESHOLD_DAYS;
        }

        return thresholdDays;
    }

    private void sendAtRiskNotifications(List<Account> accounts, Integer thresholdDays) {
        Id notificationTypeId;

        List<CustomNotificationType> notificationTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = 'At_Risk_Account_Alert'
            LIMIT 1
        ];

        if (!notificationTypes.isEmpty()) {
            notificationTypeId = notificationTypes[0].Id;
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Account acc : accounts) {
            String accountUrl = URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/Account/' + acc.Id + '/view';
            String lastActivityDate = acc.Last_Engagement_Date__c != null ? String.valueOf(acc.Last_Engagement_Date__c) : 'No activity recorded';
            Integer calculatedDaysSince = acc.Last_Engagement_Date__c != null ? acc.Last_Engagement_Date__c.daysBetween(Date.today()) : null;
            String daysSince = calculatedDaysSince != null ? String.valueOf(calculatedDaysSince) : 'Unknown';

            Set<String> recipientIds = new Set<String>();
            Set<String> recipientEmails = new Set<String>();

            if (acc.OwnerId != null) {
                recipientIds.add(String.valueOf(acc.OwnerId));
            }

            if (acc.Owner != null && acc.Owner.ManagerId != null) {
                recipientIds.add(String.valueOf(acc.Owner.ManagerId));
            }

            if (acc.Owner != null && String.isNotBlank(acc.Owner.Email)) {
                recipientEmails.add(acc.Owner.Email);
            }

            if (acc.Owner != null && acc.Owner.Manager != null && String.isNotBlank(acc.Owner.Manager.Email)) {
                recipientEmails.add(acc.Owner.Manager.Email);
            }

            if (notificationTypeId != null && !recipientIds.isEmpty()) {
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setNotificationTypeId(notificationTypeId);
                    notification.setTargetId(acc.Id);
                    notification.setTitle('Account is At Risk');
                    notification.setBody('Account "' + acc.Name + '" has been inactive for ' + daysSince + ' days. Last activity: ' + lastActivityDate);
                    notification.send(recipientIds);
                } catch (Exception e) {
                }
            }

            if (!recipientEmails.isEmpty()) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>(recipientEmails));
                email.setSubject('Account At Risk: ' + acc.Name);
                email.setPlainTextBody(
                    'Account At Risk Notification\n\n' +
                    'Account Name: ' + acc.Name + '\n\n' +
                    'Last Activity Date: ' + lastActivityDate + '\n\n' +
                    'Days Since Last Activity: ' + daysSince + '\n\n' +
                    'The Account has reached the ' + thresholdDays + '-day inactivity threshold and has been marked as At Risk.\n\n' +
                    'Open Account:\n' + accountUrl + '\n\n' +
                    'This notification was generated automatically by Salesforce.'
                );
                emails.add(email);
            }
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}