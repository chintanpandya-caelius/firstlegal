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