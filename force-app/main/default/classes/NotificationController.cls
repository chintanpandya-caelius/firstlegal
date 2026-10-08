public with sharing class NotificationController {

    @AuraEnabled(cacheable=true)
    public static List<NotificationWrapper> getNotifications() {
        Id contactId = getCurrentContactId();
        if (contactId == null) {
            return new List<NotificationWrapper>();
        }

        List<Shared_Note_Link__c> links = [
            SELECT Id, Is_Read__c, CreatedDate, Ticket__c, Ticket__r.CaseNumber,
                   Shared_Note__r.Body__c, CreatedBy.Name
            FROM Shared_Note_Link__c
            WHERE Ticket__r.ContactId = :contactId
            AND Shared_Note__r.Note_Type__c = :SharedNoteConstants.NOTE_TYPE_EXTERNAL
            AND Is_Contact_Added__c = false
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];

        List<NotificationWrapper> results = new List<NotificationWrapper>();
        for (Shared_Note_Link__c link : links) {
            results.add(new NotificationWrapper(link));
        }
        return results;
    }

    @AuraEnabled
    public static void markAsRead(Id notificationId) {
        Id contactId = getCurrentContactId();
        if (contactId == null || notificationId == null) {
            return;
        }

        List<Shared_Note_Link__c> links = [
            SELECT Id, Is_Read__c
            FROM Shared_Note_Link__c
            WHERE Id = :notificationId
            AND Ticket__r.ContactId = :contactId
            LIMIT 1
        ];

        if (links.isEmpty()) {
            // Either it doesn't exist, or it doesn't belong to this user - don't leak which.
            throw new AuraHandledException('Notification not found.');
        }

        Shared_Note_Link__c link = links[0];
        if (!link.Is_Read__c) {
            link.Is_Read__c = true;
            update link;
        }
    }

    @AuraEnabled
    public static void markAllAsRead() {
        Id contactId = getCurrentContactId();
        if (contactId == null) {
            return;
        }

        List<Shared_Note_Link__c> unread = [
            SELECT Id, Is_Read__c
            FROM Shared_Note_Link__c
            WHERE Ticket__r.ContactId = :contactId
            AND Is_Read__c = false
            AND Shared_Note__r.Note_Type__c = :SharedNoteConstants.NOTE_TYPE_EXTERNAL
        ];

        if (unread.isEmpty()) {
            return;
        }

        for (Shared_Note_Link__c link : unread) {
            link.Is_Read__c = true;
        }
        update unread;
    }

    private static Id getCurrentContactId() {
        List<User> users = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return users.isEmpty() ? null : users[0].ContactId;
    }

    public class NotificationWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String icon;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String timestamp;
        @AuraEnabled public Boolean unread;
        @AuraEnabled public Id ticketId;

        public NotificationWrapper(Shared_Note_Link__c link) {
            this.id = link.Id;
            this.title = (link.CreatedBy.Name != null ? link.CreatedBy.Name : 'A User') + ' updated on your ticket ' + (link.Ticket__r.CaseNumber != null ? link.Ticket__r.CaseNumber : '');
            this.description = truncate(link.Shared_Note__r.Body__c, 140);
            this.timestamp = formatTimestamp(link.CreatedDate);
            this.unread = !link.Is_Read__c;
            this.ticketId = link.Ticket__c;
        }

        private String truncate(String text, Integer maxLen) {
            if (String.isBlank(text)) {
                return '';
            }
            return text.length() > maxLen ? text.substring(0, maxLen) + '…' : text;
        }

        private String formatTimestamp(DateTime dt) {
            if (dt == null) {
                return '';
            }
            return dt.format('MMM d, yyyy, h:mm a');
        }
    }
}