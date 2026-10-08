public without sharing class AccountNotificationHandler {

    private static final String RT_COURT = 'Court';
    private static final String RT_FACILITY = 'Facility';
    private static final String RT_PROF_ASSOC = 'Professional_Association';
    private static final String RT_VENDOR = 'Vendor';
    private static final String RT_CUSTOMER = 'Customer';

    private static final String GROUP_BUSINESS_ADMIN = 'BuisnessAdmin';
    private static final String GROUP_FACILITY = 'FacilityManagement';
    private static final String GROUP_MARKETING = 'MarketingGroup';
    private static final String NOTIFICATION_TYPE = 'Account_Notification';

    public static void handleAfterInsert(List<Account> newAccounts) {
        List<Account> nonCustomerAccounts = new List<Account>();
        List<Account> customerAccounts = new List<Account>();
        Set<String> nonCustomerRtSet = new Set<String>{RT_COURT, RT_FACILITY, RT_PROF_ASSOC, RT_VENDOR};
        Map<Id, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Account.getRecordTypeInfosById();

        for (Account acc : newAccounts) {
            if (acc.RecordTypeId != null && rtMap.containsKey(acc.RecordTypeId)) {
                String rtDevName = rtMap.get(acc.RecordTypeId).getDeveloperName();
                if (nonCustomerRtSet.contains(rtDevName)) nonCustomerAccounts.add(acc);
                else if (rtDevName == RT_CUSTOMER) customerAccounts.add(acc);
            }
        }

        if (!nonCustomerAccounts.isEmpty()) sendNonCustomerNotifications(nonCustomerAccounts);
        if (!customerAccounts.isEmpty()) createCustomerAccountTickets(customerAccounts);
    }

    public static void handleAfterUpdate(List<Account> newAccounts, Map<Id, Account> oldAccountMap) {
        List<Account> updatedSlaAccounts = new List<Account>();
        Map<Id, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Account.getRecordTypeInfosById();

        for (Account acc : newAccounts) {
            Account oldAcc = oldAccountMap.get(acc.Id);
            if (acc.RecordTypeId != null && rtMap.containsKey(acc.RecordTypeId) && rtMap.get(acc.RecordTypeId).getDeveloperName() == RT_CUSTOMER) {
                Boolean slaTierChanged = acc.SLA_Tier__c != oldAcc.SLA_Tier__c;
                Boolean slaDueDateChanged = acc.SLA_Due_Date__c != oldAcc.SLA_Due_Date__c;
                if ((slaTierChanged || slaDueDateChanged) && acc.SLA_Breach_DateTime__c == null) updatedSlaAccounts.add(acc);
            }
        }

        if (!updatedSlaAccounts.isEmpty()) updateCustomerAccountTickets(updatedSlaAccounts);
    }

    private static void sendNonCustomerNotifications(List<Account> accounts) {
        Id notificationTypeId;
        List<CustomNotificationType> notificationTypes = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE LIMIT 1];
        if (!notificationTypes.isEmpty()) notificationTypeId = notificationTypes[0].Id;
        if (notificationTypeId == null) return;

        Set<String> groupNames = new Set<String>{GROUP_BUSINESS_ADMIN, GROUP_FACILITY, GROUP_MARKETING};
        Map<String, Id> groupNameToIdMap = new Map<String, Id>();

        for (Group grp : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN :groupNames AND Type = 'Regular']) groupNameToIdMap.put(grp.DeveloperName, grp.Id);

        Set<String> businessAdminUserIds = getGroupUserIds(groupNameToIdMap.get(GROUP_BUSINESS_ADMIN));
        Set<String> facilityUserIds = getGroupUserIds(groupNameToIdMap.get(GROUP_FACILITY));
        Set<String> marketingUserIds = getGroupUserIds(groupNameToIdMap.get(GROUP_MARKETING));
        Map<Id, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Account.getRecordTypeInfosById();

        for (Account acc : accounts) {
            if (acc.RecordTypeId == null || !rtMap.containsKey(acc.RecordTypeId)) continue;

            String rtDevName = rtMap.get(acc.RecordTypeId).getDeveloperName();
            Set<String> recipients = new Set<String>();

            if (rtDevName == RT_COURT) recipients.addAll(businessAdminUserIds);
            else if (rtDevName == RT_FACILITY) recipients.addAll(facilityUserIds);
            else if (rtDevName == RT_PROF_ASSOC || rtDevName == RT_VENDOR) recipients.addAll(marketingUserIds);

            if (!recipients.isEmpty()) {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setNotificationTypeId(notificationTypeId);
                notification.setTitle('New ' + rtDevName + ' Account Created');
                notification.setBody('A new ' + rtDevName + ' Account has been created. Please verify/update the Account and related Contact records as needed, and set the Account status to Active when ready. Until the Account status is set to Active, it cannot be used in First Legal processes or synced to Systems of Record.');
                notification.setTargetId(acc.Id);
                notification.send(recipients);
            }
        }
    }

    private static Set<String> getGroupUserIds(Id groupId) {
        Set<String> userIds = new Set<String>();
        if (groupId == null) return userIds;

        Set<Id> currentGroupIds = new Set<Id>{groupId};

        while (!currentGroupIds.isEmpty()) {
            Set<Id> nextGroupIds = new Set<Id>();

            for (GroupMember gm : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId IN :currentGroupIds]) {
                String idStr = String.valueOf(gm.UserOrGroupId);
                if (idStr.startsWith('005')) userIds.add(idStr);
                else nextGroupIds.add(gm.UserOrGroupId);
            }

            currentGroupIds = nextGroupIds;
        }

        return userIds;
    }

    private static void createCustomerAccountTickets(List<Account> customerAccounts) {
        Id caseAccountingRtId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Accounting').getRecordTypeId();
        List<Case> ticketsToInsert = new List<Case>();

        for (Account acc : customerAccounts) {
            String subTypeOrTerms = String.isNotBlank(acc.Sub_Type__c) ? acc.Sub_Type__c : 'Terms';
            Case ticket = new Case();
            ticket.RecordTypeId = caseAccountingRtId;
            ticket.AccountId = acc.Id;
            ticket.Type = 'New Customer Account';
            ticket.Origin = 'SFDC';
            ticket.Status = 'New';
            ticket.Priority = acc.SLA_Tier__c == 'S1' ? 'Immediate' : 'Standard';
            ticket.SLA_Start_Date__c = acc.SLA_Start_Date__c;
            ticket.SLA_Stop_Date__c = acc.SLA_Due_Date__c;
            ticket.Subject = 'A New ' + subTypeOrTerms + ' Customer Account was created with SLA ' + (acc.SLA_Tier__c != null ? acc.SLA_Tier__c : '') + '.';
            ticket.Internal_Notes__c = 'A new Customer Account has been created and needs to verified by an Account Admin. Please verify/update the Account and related Contact records as needed. To break the SLA, update and save the record with in the SLA time.\n\n' +
                'If the new Account is COD or Opposing Council, the account does not require Terms. Set the Status to Prospect when complete.\n\n' +
                'If the new Account is Terms, set the Status to Active when complete.\n\n' +
                'Until the Account status is set to Prospect or Active, it cannot be used in First Legal processes or synced to Systems of Record.';
            ticketsToInsert.add(ticket);
        }

        if (!ticketsToInsert.isEmpty()) insert ticketsToInsert;
    }

    private static void updateCustomerAccountTickets(List<Account> customerAccounts) {
        Map<Id, Account> accMap = new Map<Id, Account>(customerAccounts);
        List<Case> openTickets = [
            SELECT Id, AccountId, Subject, Priority, SLA_Stop_Date__c
            FROM Case
            WHERE AccountId IN :accMap.keySet()
            AND IsClosed = false
            AND Type IN ('New Customer Account', 'Customer Account Update')
        ];

        List<Case> ticketsToUpdate = new List<Case>();

        for (Case ticket : openTickets) {
            Account parentAcc = accMap.get(ticket.AccountId);
            String subTypeOrTerms = String.isNotBlank(parentAcc.Sub_Type__c) ? parentAcc.Sub_Type__c : 'Terms';
            ticket.Subject = 'A New ' + subTypeOrTerms + ' Customer Account Created with SLA ' + (parentAcc.SLA_Tier__c != null ? parentAcc.SLA_Tier__c : '') + '.';
            ticket.Priority = parentAcc.SLA_Tier__c == 'S1' ? 'Immediate' : 'Standard';
            ticket.SLA_Stop_Date__c = parentAcc.SLA_Due_Date__c;
            ticketsToUpdate.add(ticket);
        }

        if (!ticketsToUpdate.isEmpty()) update ticketsToUpdate;
    }
}