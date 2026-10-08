/**
 * EDiscoveryEmailHandler
 * ─────────────────────────────────────────────────────────────────────────────
 * NOVA-9004: Handles inbound email responses on eDiscovery cases.
 * 
 * When a client replies to a Resolved/Closed eDiscovery ticket:
 *   - The ticket is reopened (status set back to 'In Progress')
 *   - The assigned agent is notified via in-app notification
 *
 * Called from: EmailMessageTrigger (after insert)
 * ─────────────────────────────────────────────────────────────────────────────
 */
public without sharing class EDiscoveryEmailHandler {

    private static final String EDISCOVERY_RT = 'eDiscovery';
    private static final String STATUS_RESOLVED = 'Resolved';
    private static final String STATUS_CLOSED = 'Closed';
    private static final String STATUS_IN_PROGRESS = 'In Progress';
    private static final String NOTIF_TYPE_DEV_NAME = 'eDiscovery_Ticket_Alert';

    /**
     * Process inbound emails on eDiscovery cases.
     * If the case is in Resolved or Closed status, reopen it and notify the agent.
     */
    public static void handleInboundEmail(List<EmailMessage> emailMessages) {
        // Collect parent Case Ids from inbound emails
        Set<Id> caseIds = new Set<Id>();
        for (EmailMessage em : emailMessages) {
            if (em.Incoming == true && em.ParentId != null && String.valueOf(em.ParentId).startsWith('500')) {
                caseIds.add(em.ParentId);
            }
        }
        if (caseIds.isEmpty()) return;

        // Query eDiscovery cases that are Resolved or Closed
        Id edRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
            .get(EDISCOVERY_RT)?.getRecordTypeId();
        if (edRecordTypeId == null) return;

        List<Case> casesToReopen = [
            SELECT Id, CaseNumber, Subject, OwnerId, Status
            FROM Case
            WHERE Id IN :caseIds
              AND RecordTypeId = :edRecordTypeId
              AND Status IN (:STATUS_RESOLVED, :STATUS_CLOSED)
        ];

        if (casesToReopen.isEmpty()) return;

        // Reopen cases
        List<Case> updates = new List<Case>();
        for (Case c : casesToReopen) {
            updates.add(new Case(
                Id = c.Id,
                Status = STATUS_IN_PROGRESS
            ));
        }
        update updates;

        // Notify agent that ticket was reopened
        sendReopenedNotifications(casesToReopen);
    }

    /**
     * Send in-app notification to the agent when a resolved/closed ticket is reopened
     * due to a client reply.
     */
    private static void sendReopenedNotifications(List<Case> cases) {
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType
            WHERE DeveloperName = :NOTIF_TYPE_DEV_NAME LIMIT 1
        ];
        if (types.isEmpty()) return;

        CustomNotificationType notifType = types[0];

        for (Case c : cases) {
            if (c.OwnerId == null || !String.valueOf(c.OwnerId).startsWith('005')) continue;

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('Ticket Reopened – Client Replied');
            notification.setBody('Case #' + c.CaseNumber + ' was reopened after a client reply. Subject: ' + (c.Subject != null ? c.Subject : '(No Subject)'));
            notification.setNotificationTypeId(notifType.Id);
            notification.setTargetId(c.Id);

            try {
                notification.send(new Set<String>{ c.OwnerId });
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'eDiscovery Reopened notification failed for Case ' + c.Id + ': ' + e.getMessage());
            }
        }
    }
}