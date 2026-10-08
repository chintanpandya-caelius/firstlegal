public without sharing class TicketFspFcpNotificationService {

    private static final String STATUS_NEW = 'New';
    private static final String STATUS_ASSIGNED = 'Assigned';
    private static final String STATUS_ESCALATED = 'Escalated';
    private static final String STATUS_SLA_BREACH = 'SLA Breach';
    private static final String STATUS_WAITING_ON_3RD_PARTY = 'Waiting on 3rd Party';

    private static final String TICKET_NOTIFICATION_TYPE = 'FSP_FCP_Ticket_Notifications';

    private static final String REQUESTOR_PERSONA = 'Requestor';
    private static final String OWNER_PERSONA = 'Owner';
    private static final String SUPERVISOR_PERSONA = 'Supervisor';

    private static final String FSP_RECORD_TYPE_DEVELOPER_NAME = 'Client_Care';
    private static final String FSP_OWA_DISPLAY_NAME = 'First Legal Services';
    private static final String FCP_RECORD_TYPE_DEVELOPER_NAME = 'CCT';
    private static final String FCP_OWA_DISPLAY_NAME = 'First Class Program';

    private class RecipientContext {
        Id whoId;
        Id notificationUserId;
        String email;
        Boolean useDirectEmail;

        RecipientContext() {
            useDirectEmail = false;
        }
    }

    private class NotificationRequest {
        Id notificationTypeId;
        Id targetId;
        String title;
        String body;
        Set<String> recipientIds = new Set<String>();
    }

    public static void process(List<Case> newCases, Map<Id, Case> oldMap, Boolean isInsert, Boolean isUpdate) {
        if (newCases == null || newCases.isEmpty()) {
            return;
        }
        List<Ticket_Notification_Rule__mdt> rules = [
            SELECT
                DeveloperName,
                Record_Type_Developer_Name__c,
                Status__c,
                Recipient__c,
                Template_Developer_Name__c,
                Send_Email_Notification__c,
                Send_Custom_Notification__c,
                Active__c
            FROM Ticket_Notification_Rule__mdt
            WHERE Active__c = true
        ];

        if (rules.isEmpty()) {
            return;
        }

        Set<String> configuredRecordTypeNames = new Set<String>();

        for (Ticket_Notification_Rule__mdt rule : rules) {

            if (String.isNotBlank(rule.Record_Type_Developer_Name__c)) {
                configuredRecordTypeNames.add(
                    rule.Record_Type_Developer_Name__c
                );
            }
        }

        if (configuredRecordTypeNames.isEmpty()) {
            return;
        }

        Map<Id, String> recordTypeDeveloperNameById = new Map<Id, String>();

        for (RecordType rt : [
            SELECT
                Id,
                DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Case'
            AND DeveloperName IN :configuredRecordTypeNames
        ]) {

            recordTypeDeveloperNameById.put(rt.Id, rt.DeveloperName);
        }

        if (recordTypeDeveloperNameById.isEmpty()) {
            return;
        }

        Set<Id> ownerIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();

        for (Case c : newCases) {

            if (c.OwnerId != null && c.OwnerId.getSObjectType() == User.SObjectType) {
                ownerIds.add(c.OwnerId);
            }

            if (c.ContactId != null) {
                contactIds.add(c.ContactId);
            }
        }

        Map<Id, User> usersById = new Map<Id, User>();

        if (!ownerIds.isEmpty()) {
            usersById.putAll([
                SELECT
                    Id,
                    Email,
                    ManagerId,
                    IsActive
                FROM User
                WHERE Id IN :ownerIds
            ]);
        }

        Set<Id> managerIds = new Set<Id>();

        for (User owner : usersById.values()) {
            if (owner.ManagerId != null) {
                managerIds.add(owner.ManagerId);
            }
        }

        if (!managerIds.isEmpty()) {
            usersById.putAll([
                SELECT
                    Id,
                    Email,
                    ManagerId,
                    IsActive
                FROM User
                WHERE Id IN :managerIds
            ]);
        }

        Map<Id, Contact> contactsById = new Map<Id, Contact>();

        if (!contactIds.isEmpty()) {
            contactsById.putAll([
                SELECT
                    Id,
                    Email
                FROM Contact
                WHERE Id IN :contactIds
            ]);
        }

        Set<String> templateNames = new Set<String>();

        for (Ticket_Notification_Rule__mdt rule : rules) {

            if (rule.Send_Email_Notification__c &&
                String.isNotBlank(rule.Template_Developer_Name__c)) {

                templateNames.add(
                    rule.Template_Developer_Name__c
                );
            }
        }

        Map<String, Id> templateIdByDeveloperName = new Map<String, Id>();

        if (!templateNames.isEmpty()) {

            for (EmailTemplate template : [
                SELECT
                    Id,
                    DeveloperName
                FROM EmailTemplate
                WHERE DeveloperName IN :templateNames
            ]) {

                templateIdByDeveloperName.put(template.DeveloperName, template.Id);
            }
        }

        Id ticketNotificationTypeId;

        List<CustomNotificationType> notificationTypes = [
            SELECT
                Id,
                DeveloperName
            FROM CustomNotificationType
            WHERE DeveloperName = :TICKET_NOTIFICATION_TYPE
            LIMIT 1
        ];

        if (!notificationTypes.isEmpty()) {

            ticketNotificationTypeId = notificationTypes[0].Id;
        }

        Set<String> oweaDisplayNames =
            new Set<String>{FSP_OWA_DISPLAY_NAME, FCP_OWA_DISPLAY_NAME};

        Map<String, Id> oweaIdByDisplayName =
            new Map<String, Id>();

        for (OrgWideEmailAddress owea : [
            SELECT
                Id,
                DisplayName
            FROM OrgWideEmailAddress
            WHERE DisplayName IN :oweaDisplayNames
        ]) {

            oweaIdByDisplayName.put(owea.DisplayName, owea.Id);
        }

        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        Map<String, NotificationRequest> notificationsByKey = new Map<String, NotificationRequest>();

        for (Case c : newCases) {
            String recordTypeDeveloperName =
                recordTypeDeveloperNameById.get(
                    c.RecordTypeId
                );

            if (String.isBlank(recordTypeDeveloperName)) {
                continue;
            }

            Case oldCase = isUpdate && oldMap != null ? oldMap.get(c.Id) : null;

            for (Ticket_Notification_Rule__mdt rule : rules) {
                if (rule.Record_Type_Developer_Name__c !=
                    recordTypeDeveloperName) {

                    continue;
                }

                if (!eventMatches(
                    c,
                    oldCase,
                    rule.Status__c,
                    isInsert,
                    isUpdate
                )) {
                    continue;
                }

                RecipientContext recipient =
                    resolveRecipient(c, rule.Recipient__c, usersById, contactsById);

                if (recipient == null) {
                    continue;
                }

                if (rule.Send_Email_Notification__c) {

                    Id templateId = templateIdByDeveloperName.get(rule.Template_Developer_Name__c);

                    if (templateId == null) {

                        System.debug(LoggingLevel.ERROR, 'Ticket Notification: Email template not found: ' + rule.Template_Developer_Name__c);

                    } else {

                        Id oweaId = getOrgWideEmailAddressId(recordTypeDeveloperName, oweaIdByDisplayName);

                        Messaging.SingleEmailMessage email;

                        if (!recipient.useDirectEmail) {

                            email = new Messaging.SingleEmailMessage();
                            email.setTemplateId(templateId);
                            email.setTargetObjectId(recipient.whoId);
                            email.setWhatId(c.Id);
                            email.setTreatTargetObjectAsRecipient(true);

                        } else {
                            try {
                                email = Messaging.renderStoredEmailTemplate(templateId, null, c.Id);
                                email.setToAddresses(new List<String>{recipient.email});

                            } catch (Exception e) {
                                System.debug(LoggingLevel.ERROR,'Ticket Notification: Unable to render ' + 'email template ' + rule.Template_Developer_Name__c + ' for Case ' + c.Id + '. Error=' + e.getMessage());
                                email = null;
                            }
                        }

                        if (email != null) {
                            email.setSaveAsActivity(false);
                            if (oweaId != null) {
                                email.setOrgWideEmailAddressId(oweaId);
                            }
                            emailsToSend.add(email);
                        }
                    }
                }

                if (rule.Send_Custom_Notification__c && recipient.notificationUserId != null) {

                    if (ticketNotificationTypeId == null) {

                        System.debug(LoggingLevel.ERROR, 'Ticket Notification: Custom Notification Type ' + TICKET_NOTIFICATION_TYPE + ' was not found.');

                    } else {

                        String title = 'Ticket ' + c.CaseNumber;
                        String body = buildNotificationBody(c);
                        String key = String.valueOf(ticketNotificationTypeId) + '|' + String.valueOf(c.Id);

                        if (!notificationsByKey.containsKey(key)) {

                            NotificationRequest request = new NotificationRequest();
                            request.notificationTypeId = ticketNotificationTypeId;
                            request.targetId = c.Id;
                            request.title = title;
                            request.body = body;
                            notificationsByKey.put(key, request);
                        }

                        notificationsByKey.get(key).recipientIds.add(String.valueOf(recipient.notificationUserId));
                    }
                }
            }
        }

        if (!emailsToSend.isEmpty()) {
            try {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(emailsToSend, false);

                for (Messaging.SendEmailResult result : results) {
                    if (!result.isSuccess()) {
                        for (Messaging.SendEmailError error : result.getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Ticket Notification: Email failed: ' + error.getMessage());
                        }
                    }
                }

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Ticket Notification: Email send failed: ' + e.getMessage());
            }
        }

        for (NotificationRequest request : notificationsByKey.values()) {

            if (request.recipientIds.isEmpty()) {
                continue;
            }

            try {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setNotificationTypeId(request.notificationTypeId);
                notification.setTitle(request.title);
                notification.setBody(request.body);
                notification.setTargetId(request.targetId);
                notification.setSenderId(UserInfo.getUserId());
                notification.send(request.recipientIds);

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Ticket Notification: Custom Notification failed: ' + e.getMessage());
            }
        }
    }

    private static Boolean eventMatches(Case currentCase, Case oldCase, String ruleStatus, Boolean isInsert, Boolean isUpdate) {
        if (ruleStatus == STATUS_NEW) {
            return isInsert && currentCase.Status == STATUS_NEW;
        }

        if (!isUpdate || oldCase == null) {
            return false;
        }

        if (ruleStatus == STATUS_ASSIGNED) {
            return currentCase.Status == STATUS_ASSIGNED && oldCase.Status != STATUS_ASSIGNED && currentCase.OwnerId != null && currentCase.OwnerId.getSObjectType() == User.SObjectType;
        }

        if (ruleStatus == STATUS_ESCALATED) {
            return currentCase.IsEscalated == true && oldCase.IsEscalated != true;
        }

        if (ruleStatus == STATUS_SLA_BREACH) {
            return currentCase.Is_SLA_Breached__c == true && oldCase.Is_SLA_Breached__c != true;
        }

        if (ruleStatus == STATUS_WAITING_ON_3RD_PARTY) {
            return currentCase.Status == STATUS_WAITING_ON_3RD_PARTY && oldCase.Status != STATUS_WAITING_ON_3RD_PARTY;
        }

        return false;
    }

    private static RecipientContext resolveRecipient(
        Case c,
        String recipientType,
        Map<Id, User> usersById,
        Map<Id, Contact> contactsById
    ) {

        RecipientContext result = new RecipientContext();

        if (recipientType == REQUESTOR_PERSONA) {

            if (c.ContactId != null && contactsById.containsKey(c.ContactId)) {

                Contact contact = contactsById.get(c.ContactId);

                if (String.isNotBlank(contact.Email)) {

                    result.whoId = contact.Id;
                    result.email = contact.Email;
                    result.useDirectEmail = false;

                    return result;
                }
            }

            if (String.isNotBlank(c.SuppliedEmail)) {

                result.email = c.SuppliedEmail;
                result.useDirectEmail = true;
                return result;
            }

            System.debug(LoggingLevel.WARN, 'Ticket Notification: No Requestor email available. ' + 'Case=' + c.Id);
            return null;
        }

        if (recipientType == OWNER_PERSONA) {
            if (c.OwnerId == null || c.OwnerId.getSObjectType() != User.SObjectType || !usersById.containsKey(c.OwnerId)) {
                return null;
            }

            User owner = usersById.get(c.OwnerId);

            if (!owner.IsActive || String.isBlank(owner.Email)) {
                return null;
            }

            result.whoId = owner.Id;
            result.notificationUserId = owner.Id;
            result.email = owner.Email;

            return result;
        }

        if (recipientType == SUPERVISOR_PERSONA) {

            if (c.OwnerId == null || c.OwnerId.getSObjectType() != User.SObjectType || !usersById.containsKey(c.OwnerId)) {
                return null;
            }

            User owner = usersById.get(c.OwnerId);

            if (owner.ManagerId == null || !usersById.containsKey(owner.ManagerId)) {
                System.debug(LoggingLevel.WARN, 'Ticket Notification: Owner has no Manager. ' + 'Case=' + c.Id + ', Owner=' + c.OwnerId);
                return null;
            }

            User supervisor = usersById.get(owner.ManagerId);

            if (!supervisor.IsActive || String.isBlank(supervisor.Email)) {
                return null;
            }

            result.whoId = supervisor.Id;
            result.notificationUserId = supervisor.Id;
            result.email = supervisor.Email;

            return result;
        }

        return null;
    }

    private static Id getOrgWideEmailAddressId(String recordTypeDeveloperName, Map<String, Id> oweaIdByDisplayName) {

        String displayName;
        if (recordTypeDeveloperName == FSP_RECORD_TYPE_DEVELOPER_NAME) {
            displayName = FSP_OWA_DISPLAY_NAME;

        } else if (recordTypeDeveloperName == FCP_RECORD_TYPE_DEVELOPER_NAME) {
            displayName = FCP_OWA_DISPLAY_NAME;

        } else {
            return null;
        }

        return oweaIdByDisplayName.get(displayName);
    }

    private static String buildNotificationBody(Case c) {

        String messageTemplate = Label.Internal_Notification_Message;

        if (String.isBlank(messageTemplate)) {
            messageTemplate = 'Ticket {0} is currently {1}';
        }

        return String.format(messageTemplate, new List<String>{c.CaseNumber, c.Status});
    }
}