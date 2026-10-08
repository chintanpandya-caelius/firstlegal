public with sharing class SharedNoteLinkTriggerHandler {
    
    public static Set<Id> suppressAutoReopenTicketIds = new Set<Id>();

    public static void handleAfterSave(List<Shared_Note_Link__c> newLinks) {
        if (newLinks == null || newLinks.isEmpty()) {
            return;
        }

        Set<Id> linkIds = new Set<Id>();
        for (Shared_Note_Link__c link : newLinks) {
            linkIds.add(link.Id);
        }

        List<Shared_Note_Link__c> qualifying = [
            SELECT Id, Ticket__c, Ticket__r.IsClosed, Ticket__r.CaseNumber
            FROM Shared_Note_Link__c
            WHERE Id IN :linkIds
            AND Shared_Note__r.Note_Type__c = :SharedNoteConstants.NOTE_TYPE_EXTERNAL
            AND Ticket__r.IsClosed = true
        ];

        if (!suppressAutoReopenTicketIds.isEmpty()) {
            List<Shared_Note_Link__c> filtered = new List<Shared_Note_Link__c>();
            for (Shared_Note_Link__c link : qualifying) {
                if (!suppressAutoReopenTicketIds.contains(link.Ticket__c)) {
                    filtered.add(link);
                }
            }
            qualifying = filtered;
        }

        if (qualifying.isEmpty()) {
            return;
        }

        Map<Id, Case> ticketsToReopen = new Map<Id, Case>();
        for (Shared_Note_Link__c link : qualifying) {
            ticketsToReopen.put(
                link.Ticket__c,
                new Case(Id = link.Ticket__c, Status = SharedNoteConstants.CASE_STATUS_IN_PROGRESS)
            );
        }

        update ticketsToReopen.values();
    }
}