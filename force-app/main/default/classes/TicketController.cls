public with sharing class TicketController {

    @AuraEnabled(cacheable=true)
    public static String getCurrentUserEmail() {
        return [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email;
    }

    @AuraEnabled
    public static Id createDraftTicket(String contactEmail) {
        Case draft = new Case(
            SuppliedEmail = contactEmail,
            Is_Draft__c = true,
            Origin = 'Web'
        );
        insert draft;
        return draft.Id;
    }

    @AuraEnabled
    public static void deleteDraftTicket(Id recordId) {
        if (recordId == null) {
            return;
        }
        Case toDelete = new Case(Id = recordId);
        delete toDelete;
    }

    @AuraEnabled
    public static String submitTicket(
        Id recordId,
        String contactEmail,
        String ticketType,
        String subType,
        String priority,
        String subject,
        String description,
        String matterNumber,
        String caseNumber
    ) {
        if (String.isBlank(ticketType) || String.isBlank(subType) ||
            String.isBlank(priority) || String.isBlank(subject) || String.isBlank(description)) {
            throw new AuraHandledException('Please fill in all required fields.');
        }

        Case ticket = (recordId != null)
            ? new Case(Id = recordId)
            : new Case();

        ticket.SuppliedEmail = contactEmail;
        ticket.Type = ticketType;
        ticket.Ticket_SubType__c = subType;
        ticket.Priority = priority;
        ticket.Subject = subject;
        ticket.Description = description;
        ticket.Matter_Number__c = matterNumber;
        ticket.Court_Case_Number__c = caseNumber;
        ticket.Status = 'New';
        ticket.Is_Draft__c = false;

        upsert ticket;

        Case saved = [SELECT CaseNumber FROM Case WHERE Id = :ticket.Id LIMIT 1];
        return saved.CaseNumber;
    }
}