public without sharing class EmailMessageTriggerHandler {

    // BEFORE INSERT
    public static void handleBeforeInsert(List<EmailMessage> newEmails) {
        // If the related Case is closed, create a new child Case and reparent the EmailMessage to it.
        reparentEmailsOnClosedCases(newEmails);
    }

    // AFTER INSERT
    public static void handleAfterInsert(List<EmailMessage> newEmails) {
        // EmailRouting for Tier1(FCP, GCC)
        EmailRoutingService.routeEmails(newEmails);

        // If the customer replies while a reminder series is active and the
        // Case is Waiting on Customer, cancel the series and move it back to In Progress.
        cancelRemindersOnIncomingReply(newEmails);
    }

    private static void cancelRemindersOnIncomingReply(List<EmailMessage> newEmails) {
        Set<Id> caseIds = new Set<Id>();
        for (EmailMessage em : newEmails) {
            if (em.Incoming == true &&
                em.RelatedToId != null &&
                em.RelatedToId.getSObjectType() == Case.getSObjectType()) {
                    caseIds.add(em.RelatedToId);
                }
        }
        if (caseIds.isEmpty()) return;

        // cancelOnResponse() already scopes itself to Reminder_Active__c = true
        // AND Status = Waiting_On_Customer, so it's safe to pass every incoming Case Id here.
        ReminderService.cancelOnResponse(caseIds);
    }

    private static void reparentEmailsOnClosedCases(List<EmailMessage> newEmails) {

        List<EmailMessage> caseEmails = new List<EmailMessage>();
        Set<Id> caseIds = new Set<Id>();
        for (EmailMessage em : newEmails) {
            if (em.Incoming == true &&
                em.RelatedToId != null &&
                em.RelatedToId.getSObjectType() == Case.getSObjectType()) {
                    caseEmails.add(em);
                    caseIds.add(em.RelatedToId);
                }
        }
        if (caseEmails.isEmpty()) return;

        Map<Id, Case> closedCaseMap = new Map<Id, Case>([
            SELECT Id
            FROM Case
            WHERE Id IN :caseIds
            AND IsClosed = true
            WITH SYSTEM_MODE
        ]);
        if (closedCaseMap.isEmpty()) return;

        List<EmailMessage> emailsNeedingChildCase = new List<EmailMessage>();
        List<Case> childCasesToInsert = new List<Case>();

        for (EmailMessage em : caseEmails) {
            Case closedCase = closedCaseMap.get(em.RelatedToId);
            if (closedCase == null) continue;

            emailsNeedingChildCase.add(em);
            childCasesToInsert.add(new Case(
                ParentId    = closedCase.Id,
                Subject     = em.Subject,
                Origin      = 'Email',
                Description = em.TextBody
            ));
        }
        if (childCasesToInsert.isEmpty()) return;

        insertChildCasesAndReparent(emailsNeedingChildCase, childCasesToInsert);
    }

    private static void insertChildCasesAndReparent(List<EmailMessage> emailsNeedingChildCase, List<Case> childCasesToInsert) {
        try {
            Database.insert(childCasesToInsert, AccessLevel.SYSTEM_MODE);
        } catch (DmlException ex) {
            for (EmailMessage em : emailsNeedingChildCase) {
                em.addError('Unable to create the follow-up Case for this email: ' + ex.getMessage());
            }
            return;
        }

        for (Integer i = 0; i < emailsNeedingChildCase.size(); i++) {
            Id childCaseId = childCasesToInsert[i].Id;
            emailsNeedingChildCase[i].RelatedToId = childCaseId;
            emailsNeedingChildCase[i].ParentId    = childCaseId;
        }
    }
}