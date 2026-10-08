public class LeadService {

    private static final String BDR_QUEUE_NAME = 'BDR_Queue';
    private static final String STATUS_NURTURING = 'Nurturing';
    private static final Set<String> COD_OPPOSING_COUNCIL_ORDER_TYPES = new Set<String>{'COD','Opposing Council'};
    private static final String OPP_SERVICE_LINE_FIELD = 'Service_Line__c';

    public static void assignNewLeadsToBDRQueue(List<Lead> newLeads) {
        Id bdrQueueId = getBDRQueueId();
        if (bdrQueueId == null) return;
        for (Lead leadRec : newLeads) if (leadRec.Status == 'New') leadRec.OwnerId = bdrQueueId;
    }

    public static void sendQueueWelcomeEmails(List<Lead> newLeads) {
        Group bdrQueue = getBDRQueue();
        if (bdrQueue == null) return;

        Set<Id> userIds = new Set<Id>();
        List<GroupMember> members = [SELECT GroupId, UserOrGroupId FROM GroupMember WHERE GroupId = :bdrQueue.Id];

        for (GroupMember gm : members) if (String.valueOf(gm.UserOrGroupId).startsWith('005')) userIds.add(gm.UserOrGroupId);
        if (userIds.isEmpty()) return;

        List<User> users = [SELECT Id, Name, Email, IsActive FROM User WHERE Id IN :userIds];
        List<String> recipientEmails = new List<String>();

        for (User usr : users) if (usr.IsActive && !String.isBlank(usr.Email)) recipientEmails.add(usr.Email);
        if (recipientEmails.isEmpty()) return;

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Lead leadRec : newLeads) {
            if (leadRec.Status != 'New') continue;

            String leadName = (leadRec.FirstName != null ? leadRec.FirstName + ' ' : '') + (leadRec.LastName != null ? leadRec.LastName : '');
            String startDate = leadRec.SLA_Start_Date__c != null ? leadRec.SLA_Start_Date__c.format('yyyy-MM-dd') : '';
            String dueDate = leadRec.SLA_Due_Date__c != null ? leadRec.SLA_Due_Date__c.format('yyyy-MM-dd') : '';
            String recordUrl = baseUrl + '/' + leadRec.Id;

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(recipientEmails);
            email.setSubject('New Lead ' + leadName + ' Created');

            String htmlBody = 'Hello,<br/><br/>' +
                'This is an automated notification that the lead <a href="' + recordUrl + '">' + leadName + '</a> has been created and assigned to the BDR Queue:<br/><br/>' +
                '<b>Lead Name:</b> <a href="' + recordUrl + '">' + leadName + '</a><br/><br/>' +
                '<b>Status:</b> New<br/><br/>' +
                '<b>Start Date:</b> ' + startDate + '<br/><br/>' +
                '<b>Due Date:</b> ' + dueDate + '<br/><br/>' +
                'Please update the lead or escalate if needed to avoid a delay.<br/><br/>' +
                '<i>This is an automated email. Please DO NOT respond to this email.</i>';

            email.setHtmlBody(htmlBody);
            emails.add(email);
        }

        if (emails.isEmpty()) return;

        try {
            Messaging.sendEmail(emails, false);
        } catch (Exception e) {
        }
    }

    public static void checkAndSendMatchedAccountEmails(List<Lead> leadTriggerContextList, Map<Id, Lead> oldMap) {
        Set<Id> freshLeadIds = new Set<Id>();

        for (Lead l : leadTriggerContextList) if (l.Id != null) freshLeadIds.add(l.Id);
        if (freshLeadIds.isEmpty()) return;

        List<Lead> leadsWithFreshData = [
            SELECT Id, FirstName, LastName, OwnerId, Matched_Account__c
            FROM Lead
            WHERE Id IN :freshLeadIds
        ];

        Set<Id> targetAccountIds = new Set<Id>();
        Set<Id> targetQueueIds = new Set<Id>();
        Set<Id> targetUserIds = new Set<Id>();

        for (Lead freshLead : leadsWithFreshData) {
            if (freshLead.Matched_Account__c == null) continue;

            targetAccountIds.add(freshLead.Matched_Account__c);
            String ownerIdStr = String.valueOf(freshLead.OwnerId);

            if (ownerIdStr.startsWith('00G')) targetQueueIds.add(freshLead.OwnerId);
            else if (ownerIdStr.startsWith('005')) targetUserIds.add(freshLead.OwnerId);
        }

        if (targetAccountIds.isEmpty()) return;

        Map<Id, Account> accountsMap = new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :targetAccountIds
        ]);

        Map<Id, List<String>> queueToEmailsMap = new Map<Id, List<String>>();

        if (!targetQueueIds.isEmpty()) {
            Set<Id> groupMemberUserIds = new Set<Id>();
            List<GroupMember> groupMembers = [
                SELECT GroupId, UserOrGroupId
                FROM GroupMember
                WHERE GroupId IN :targetQueueIds
            ];

            for (GroupMember gm : groupMembers) if (String.valueOf(gm.UserOrGroupId).startsWith('005')) groupMemberUserIds.add(gm.UserOrGroupId);

            if (!groupMemberUserIds.isEmpty()) {
                Map<Id, User> activeUsers = new Map<Id, User>([
                    SELECT Id, Email
                    FROM User
                    WHERE Id IN :groupMemberUserIds
                    AND IsActive = true
                    AND Email != null
                ]);

                for (GroupMember gm : groupMembers) {
                    if (!activeUsers.containsKey(gm.UserOrGroupId)) continue;
                    if (!queueToEmailsMap.containsKey(gm.GroupId)) queueToEmailsMap.put(gm.GroupId, new List<String>());
                    queueToEmailsMap.get(gm.GroupId).add(activeUsers.get(gm.UserOrGroupId).Email);
                }
            }
        }

        Map<Id, User> directUsersMap = new Map<Id, User>();

        if (!targetUserIds.isEmpty()) {
            directUsersMap = new Map<Id, User>([
                SELECT Id, Email
                FROM User
                WHERE Id IN :targetUserIds
                AND IsActive = true
                AND Email != null
            ]);
        }

        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        for (Lead leadRec : leadsWithFreshData) {
            if (leadRec.Matched_Account__c == null) continue;

            if (oldMap != null && oldMap.containsKey(leadRec.Id) && oldMap.get(leadRec.Id).Matched_Account__c == leadRec.Matched_Account__c) continue;

            String leadFullName = (leadRec.FirstName != null ? leadRec.FirstName + ' ' : '') + leadRec.LastName;
            List<String> targetRecipients = new List<String>();
            String ownerIdStr = String.valueOf(leadRec.OwnerId);

            if (ownerIdStr.startsWith('00G')) {
                if (queueToEmailsMap.containsKey(leadRec.OwnerId)) targetRecipients.addAll(queueToEmailsMap.get(leadRec.OwnerId));
            } else if (ownerIdStr.startsWith('005')) {
                if (directUsersMap.containsKey(leadRec.OwnerId)) targetRecipients.add(directUsersMap.get(leadRec.OwnerId).Email);
            }

            if (targetRecipients.isEmpty()) continue;

            String accountName = accountsMap.containsKey(leadRec.Matched_Account__c) ? accountsMap.get(leadRec.Matched_Account__c).Name : 'Unknown Account';
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(targetRecipients);
            email.setSubject('Potential Account Match Found - Lead: ' + leadFullName);

            String body = 'Hello,\n\n' +
                'A potential Account duplicate match has been found for an assigned Lead.\n\n' +
                'Lead Name: ' + leadFullName + '\n' +
                'Lead Record Link: ' + URL.getOrgDomainUrl().toExternalForm() + '/' + leadRec.Id + '\n\n' +
                'Matched Account Name: ' + accountName + '\n' +
                'Matched Account ID: ' + leadRec.Matched_Account__c + '\n\n' +
                'Please review and merge if appropriate.';

            email.setPlainTextBody(body);
            emailsToSend.add(email);
        }

        if (!emailsToSend.isEmpty()) {
            try {
                Messaging.sendEmail(emailsToSend, false);
            } catch (Exception e) {
            }
        }
    }

    public static Id getBDRQueueId() {
        Group queueGroup = getBDRQueue();
        return queueGroup != null ? queueGroup.Id : null;
    }

    public static Group getBDRQueue() {
        List<Group> queues = [
            SELECT Id, Name, Email, DeveloperName
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = :BDR_QUEUE_NAME
            LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0];
    }

    public static void updateAccountType(List<Lead> convertedLeads) {
        Set<Id> accountIds = new Set<Id>();
        Map<Id, String> accountIdToOrderType = new Map<Id, String>();

        for (Lead leadRec : convertedLeads) {
            if (leadRec.ConvertedAccountId == null) continue;

            accountIds.add(leadRec.ConvertedAccountId);

            if (COD_OPPOSING_COUNCIL_ORDER_TYPES.contains(leadRec.Order_Type__c)) {
                accountIdToOrderType.put(leadRec.ConvertedAccountId, leadRec.Order_Type__c);
            }
        }

        if (accountIds.isEmpty()) return;

        List<Account> accountsToUpdate = [
            SELECT Id, Type, Sub_Type__c, BillingStreet, BillingCity, BillingState, BillingPostalCode,
                   BillingCountry, BillingStateCode, BillingCountryCode, ShippingStreet, ShippingCity,
                   ShippingState, ShippingPostalCode, ShippingCountry, ShippingStateCode, ShippingCountryCode
            FROM Account
            WHERE Id IN :accountIds
        ];

        for (Account acc : accountsToUpdate) {
            acc.Type = 'Customer';

            if (accountIdToOrderType.containsKey(acc.Id)) acc.Sub_Type__c = accountIdToOrderType.get(acc.Id);

            Boolean shippingIsBlank = String.isBlank(acc.ShippingStreet) &&
                String.isBlank(acc.ShippingCity) &&
                String.isBlank(acc.ShippingPostalCode) &&
                String.isBlank(acc.ShippingState) &&
                String.isBlank(acc.ShippingStateCode);

            if (shippingIsBlank) {
                acc.ShippingStreet = acc.BillingStreet;
                acc.ShippingCity = acc.BillingCity;
                acc.ShippingState = acc.BillingState;
                acc.ShippingPostalCode = acc.BillingPostalCode;
                acc.ShippingCountry = acc.BillingCountry;
                acc.ShippingStateCode = acc.BillingStateCode;
                acc.ShippingCountryCode = acc.BillingCountryCode;
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            AccountCustomerHandler.bypassForTransaction = true;
            AccountOtherRecordHandler.bypassForTransaction = true;

            try {
                update accountsToUpdate;
            } finally {
                AccountCustomerHandler.bypassForTransaction = false;
                AccountOtherRecordHandler.bypassForTransaction = false;
            }
        }
    }

    public static void createAccountContactRelationships(List<Lead> convertedLeads) {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();

        for (Lead leadRec : convertedLeads) {
            if (leadRec.ConvertedAccountId != null && leadRec.ConvertedContactId != null) {
                accountIds.add(leadRec.ConvertedAccountId);
                contactIds.add(leadRec.ConvertedContactId);
            }
        }

        if (accountIds.isEmpty() || contactIds.isEmpty()) return;

        Set<String> existingRelationships = new Set<String>();

        List<AccountContactRelation> existingAcrs = [
            SELECT AccountId, ContactId
            FROM AccountContactRelation
            WHERE AccountId IN :accountIds
            AND ContactId IN :contactIds
        ];

        for (AccountContactRelation acr : existingAcrs) existingRelationships.add(acr.AccountId + '-' + acr.ContactId);

        List<AccountContactRelation> acrsToInsert = new List<AccountContactRelation>();

        for (Lead leadRec : convertedLeads) {
            if (leadRec.ConvertedAccountId == null || leadRec.ConvertedContactId == null) continue;

            String key = leadRec.ConvertedAccountId + '-' + leadRec.ConvertedContactId;

            if (!existingRelationships.contains(key)) {
                acrsToInsert.add(new AccountContactRelation(
                    AccountId = leadRec.ConvertedAccountId,
                    ContactId = leadRec.ConvertedContactId,
                    Roles = 'Primary Contact',
                    Email__c = leadRec.Email
                ));
            }
        }

        if (!acrsToInsert.isEmpty()) insert acrsToInsert;
    }

    public static void updateOpportunityRevenueType(List<Lead> convertedLeads) {
        Id convertingUserId = UserInfo.getUserId();
        Map<Id, Lead> oppIdToLead = new Map<Id, Lead>();

        for (Lead leadRec : convertedLeads) {
            if (leadRec.ConvertedOpportunityId != null) oppIdToLead.put(leadRec.ConvertedOpportunityId, leadRec);
        }

        if (oppIdToLead.isEmpty()) return;

        Set<Id> oppIds = oppIdToLead.keySet();
        String fieldList = String.join(getCreateableOpportunityFieldNames(), ', ');
        String query = 'SELECT ' + fieldList + ' FROM Opportunity WHERE Id IN :oppIds';
        List<Opportunity> masterOpps = Database.query(query);

        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        List<Opportunity> opportunitiesToInsert = new List<Opportunity>();

        for (Opportunity masterOpp : masterOpps) {
            Lead leadRec = oppIdToLead.get(masterOpp.Id);
            List<String> serviceLines = parseServiceLines(leadRec.Service_Line__c);

            Opportunity oppToUpdate = new Opportunity(Id = masterOpp.Id);
            oppToUpdate.Revenue_Type__c = 'New Logo';
            oppToUpdate.OwnerId = convertingUserId;

            if (!serviceLines.isEmpty()) oppToUpdate.put(OPP_SERVICE_LINE_FIELD, serviceLines[0]);
            opportunitiesToUpdate.add(oppToUpdate);

            for (Integer i = 1; i < serviceLines.size(); i++) {
                SObject cloneObj = masterOpp.clone(false, true, false, false);
                cloneObj.put('Revenue_Type__c', 'Cross Sell');
                cloneObj.put('OwnerId', convertingUserId);
                cloneObj.put(OPP_SERVICE_LINE_FIELD, serviceLines[i]);
                opportunitiesToInsert.add((Opportunity) cloneObj);
            }
        }

        if (!opportunitiesToUpdate.isEmpty()) {
            try {
                update opportunitiesToUpdate;
            } catch (Exception e) {
            }
        }

        if (!opportunitiesToInsert.isEmpty()) {
            try {
                insert opportunitiesToInsert;
            } catch (Exception e) {
            }
        }
    }

    private static List<String> parseServiceLines(String serviceLineRaw) {
        List<String> result = new List<String>();
        if (String.isBlank(serviceLineRaw)) return result;

        for (String val : serviceLineRaw.split(';')) if (!String.isBlank(val)) result.add(val.trim());
        result.sort();
        return result;
    }

    private static List<String> getCreateableOpportunityFieldNames() {
        List<String> fieldNames = new List<String>();

        for (Schema.SObjectField fieldToken : Schema.SObjectType.Opportunity.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (fieldDescribe.isCreateable() && fieldDescribe.isAccessible()) fieldNames.add(fieldDescribe.getName());
        }

        if (!fieldNames.contains('Id')) fieldNames.add('Id');
        return fieldNames;
    }

    public static void validateQualificationForNurturing(List<Lead> leads) {
        for (Lead leadRec : leads) {
            if (leadRec.Status == STATUS_NURTURING && leadRec.Qualification__c == null) leadRec.Qualification__c.addError('Qualification is required when Status is Nurturing.');
        }
    }
}