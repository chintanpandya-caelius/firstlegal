public without sharing class AccountEngagementBatch implements Database.Batchable<SObject> {

    private static final Integer DEFAULT_THRESHOLD_DAYS = 60;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id,
                   Name,
                   OwnerId,
                   Owner.Name,
                   Owner.Email,
                   Owner.ManagerId,
                   Owner.Manager.Name,
                   Owner.Manager.Email,
                   Last_Engagement_Date__c,
                   Days_Since_Last_Engagement__c,
                   At_Risk__c,
                   At_Risk_Notified_On__c
            FROM Account
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        Integer thresholdDays = getThresholdDays();
        List<Account> accountsToUpdate = new List<Account>();
        List<Account> newlyAtRiskAccounts = new List<Account>();

        for (Account acc : scope) {
            Decimal daysSince = acc.Days_Since_Last_Engagement__c;

            if (daysSince == null) {
                continue;
            }

            if (daysSince >= thresholdDays && acc.At_Risk__c != true) {
                acc.At_Risk__c = true;
                acc.At_Risk_Notified_On__c = Date.today();
                accountsToUpdate.add(acc);
                newlyAtRiskAccounts.add(acc);
            } else if (daysSince < thresholdDays && acc.At_Risk__c == true) {
                acc.At_Risk__c = false;
                acc.At_Risk_Notified_On__c = null;
                accountsToUpdate.add(acc);
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            Database.update(accountsToUpdate, false);
        }

        if (!newlyAtRiskAccounts.isEmpty()) {
            sendAtRiskNotifications(newlyAtRiskAccounts);
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

    private void sendAtRiskNotifications(List<Account> accounts) {
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
            String lastEngagementDate = acc.Last_Engagement_Date__c != null ? String.valueOf(acc.Last_Engagement_Date__c) : 'No engagement recorded';
            String daysSince = acc.Days_Since_Last_Engagement__c != null ? String.valueOf(acc.Days_Since_Last_Engagement__c) : 'Unknown';
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
                    notification.setBody('Account "' + acc.Name + '" has been inactive for ' + daysSince + ' days. Last engagement: ' + lastEngagementDate);
                    notification.send(recipientIds);
                } catch (Exception e) {
                    // Suppress or log notification failure in test/runtime environment
                }
            }

            if (!recipientEmails.isEmpty()) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>(recipientEmails));
                email.setSubject('Account At Risk: ' + acc.Name);
                email.setPlainTextBody(
                    'Account At Risk Notification\n\n' +
                    'Account Name: ' + acc.Name + '\n\n' +
                    'Last Engagement Date: ' + lastEngagementDate + '\n\n' +
                    'Days Since Last Engagement: ' + daysSince + '\n\n' +
                    'The Account has reached the ' + thresholdText() +
                    '-day inactivity threshold and has been marked as At Risk.\n\n' +
                    'Open Account:\n' + accountUrl + '\n\n' +
                    'This notification was generated automatically by Salesforce.'
                );
                emails.add(email);
            }
        }

        // Direct list send replacing the broken subList call
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }

    private String thresholdText() {
        return String.valueOf(getThresholdDays());
    }

    public void finish(Database.BatchableContext bc) {
    }
}