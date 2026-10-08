/**
 * EDiscoveryNotificationHandler
 * ─────────────────────────────────────────────────────────────────────────────
 * NOVA-9004: eDiscovery Ticket Notifications
 * 
 * Handles ALL eDiscovery notification logic:
 *   1. Created    → Acknowledgment email to Requestor (Contact)
 *   2. Assigned   → In-App bell to Assignee
 *   3. Escalated  → In-App + Email to Assignee & Jay Ciccanti (OOO → Jay White)
 *   4. Resolved   → Email to Requestor (with opt-out check)
 *   5. Closed     → Email to Requestor (auto-close notification, with opt-out)
 *   6. SLA Breach Warning (20 min before) → In-App to Agent + Jay Ciccanti
 *   7. SLA Breach → Email to Agent + Jay Ciccanti (OOO → Jay White)
 *   8. Notification Suppression → Contact & Account level
 *
 * Integration:
 *   - Called from CaseTrigger (after insert, after update)
 *   - Called from EDiscoverySLASchedulable (every 10 min for SLA checks)
 *
 * Dependencies:
 *   - Custom Notification Type: eDiscovery_Ticket_Alert
 *   - Custom Labels:
 *       • eDiscovery_Supervisor_Id        (Jay Ciccanti's 18-char User Id)
 *       • eDiscovery_Supervisor_Backup_Id  (Jay White's 18-char User Id)
 *   - Email Templates:
 *       • 'eDiscovery Ticket Acknowledgment'
 *       • 'eDiscovery Ticket Escalated'
 *       • 'eDiscovery Ticket Resolved'
 *       • 'eDiscovery Ticket Closed'
 *       • 'eDiscovery SLA Breach Warning'
 *       • 'eDiscovery SLA Breach'
 *   - Case Fields: SLA_Breach_DateTime__c, SLA_Breach_Warning_Sent__c,
 *                  SLA_Breached_Notification_Sent__c
 *   - Contact/Account Field: Disable_Ticket_Notifications__c (Checkbox)
 *   - User Field: OutOfOfficeMessage (standard) or custom Is_Out_Of_Office__c
 * ─────────────────────────────────────────────────────────────────────────────
 */
public without sharing class EDiscoveryNotificationHandler {

    // ─── EMAIL TEMPLATE DEVELOPER NAMES ───
    private static final String TPL_ACKNOWLEDGMENT = 'Ticket_Created_First_Response_Email_during_AfterHours_1781871007898';
    private static final String TPL_ESCALATED      = 'Ticket_Escalated_Internal_Escalation_Stage_Escalated_1782225184921';
    private static final String TPL_RESOLVED       = 'Ticket_Resolved_Resolution_Confirmation_Stage_Resolved_1782225684716';
    private static final String TPL_CLOSED         = 'Ticket_Closed_thro_Automation_Stage_Closed_1782226246845';
    private static final String TPL_SLA_WARN       = 'SLA_Breach_Warning_Internal_Alert_1782226441058';
    private static final String TPL_SLA_BREACH     = 'SLA_Breach_Internal_Alert_1782226611235';

    // ─── CUSTOM NOTIFICATION TYPE ───
    private static final String NOTIF_TYPE_DEV_NAME = 'eDiscovery_Ticket_Alert';

    // ─── RECORD TYPE ───
    private static final String EDISCOVERY_RT = 'EDiscovery';

    // ─── STATUS VALUES ───
    private static final String STATUS_NEW       = 'New';
    private static final String STATUS_ASSIGNED  = 'Assigned';
    private static final String STATUS_ESCALATED = 'Escalated';
    private static final String STATUS_RESOLVED  = 'Resolved';
    private static final String STATUS_CLOSED    = 'Closed';

    // ─── CACHES ───
    private static CustomNotificationType cachedNotifType;
    private static Map<String, EmailTemplate> cachedTemplates = new Map<String, EmailTemplate>();

    // ═══════════════════════════════════════════════════════════════════════════════
    // ENTRY POINT: AFTER INSERT
    // Story 1: Ticket Created Acknowledgment
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void handleAfterInsert(List<Case> newCases) {
        Id edRecordTypeId = getEDiscoveryRecordTypeId();
        if (edRecordTypeId == null) return;

        List<Case> acknowledgmentCases = new List<Case>();
        for (Case c : newCases) {
            if (c.RecordTypeId == edRecordTypeId && c.ContactId != null) {
                acknowledgmentCases.add(c);
            }
        }

        if (!acknowledgmentCases.isEmpty()) {
            sendAcknowledgmentEmails(acknowledgmentCases);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ENTRY POINT: AFTER UPDATE
    // Detects status transitions and fires appropriate notifications
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void handleAfterUpdate(List<Case> newCases, Map<Id, Case> oldMap) {
        Id edRecordTypeId = getEDiscoveryRecordTypeId();
        if (edRecordTypeId == null) return;

        List<Case> assignedCases  = new List<Case>();
        List<Case> escalatedCases = new List<Case>();
        List<Case> resolvedCases  = new List<Case>();
        List<Case> closedCases    = new List<Case>();

        for (Case c : newCases) {
            if (c.RecordTypeId != edRecordTypeId) continue;
            Case oldCase = oldMap.get(c.Id);

            // ASSIGNED
            if (c.Status == STATUS_ASSIGNED && oldCase.Status != STATUS_ASSIGNED) {
                assignedCases.add(c);
            }
            // ESCALATED
            if (c.Status == STATUS_ESCALATED && oldCase.Status != STATUS_ESCALATED) {
                escalatedCases.add(c);
            }
            // RESOLVED
            if (c.Status == STATUS_RESOLVED && oldCase.Status != STATUS_RESOLVED) {
                resolvedCases.add(c);
            }
            // CLOSED (Story 5 AC 5.2 — auto-close notification)
            if (c.Status == STATUS_CLOSED && oldCase.Status != STATUS_CLOSED) {
                closedCases.add(c);
            }
        }

        if (!assignedCases.isEmpty())  sendAssignedNotifications(assignedCases);
        if (!escalatedCases.isEmpty()) sendEscalatedNotifications(escalatedCases);
        if (!resolvedCases.isEmpty())  sendResolvedNotifications(resolvedCases);
        if (!closedCases.isEmpty())    sendClosedNotifications(closedCases);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // STORY 1: CREATED → Acknowledgment Email to Requestor
    // ═══════════════════════════════════════════════════════════════════════════════
    private static void sendAcknowledgmentEmails(List<Case> cases) {
        EmailTemplate tpl = getTemplate(TPL_ACKNOWLEDGMENT);
        if (tpl == null) {
            System.debug(LoggingLevel.WARN, 'eDiscovery: Acknowledgment template not found: ' + TPL_ACKNOWLEDGMENT);
            return;
        }

        // Check opt-out at Contact/Account level
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Case c : cases) {
            if (c.ContactId != null) contactIds.add(c.ContactId);
            if (c.AccountId != null) accountIds.add(c.AccountId);
        }

        Map<Id, Contact> contactMap = getContactOptOutMap(contactIds);
        Map<Id, Account> accountMap = getAccountOptOutMap(accountIds);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Case c : cases) {
            if (c.ContactId == null) continue;
            if (isNotificationSuppressed(c, contactMap, accountMap)) continue;

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTemplateId(tpl.Id);
            mail.setTargetObjectId(c.ContactId);
            mail.setWhatId(c.Id);
            mail.setSaveAsActivity(true);
            emails.add(mail);
        }

        if (!emails.isEmpty()) sendEmails(emails);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // STORY 2: ASSIGNED → In-App Bell Notification to Assignee
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void sendAssignedNotifications(List<Case> cases) {
        if (cases.isEmpty()) return;

        CustomNotificationType notifType = getNotificationType();
        if (notifType == null) return;

        for (Case c : cases) {
            if (c.OwnerId == null || !isUserId(c.OwnerId)) continue;

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('Ticket Assigned to You');
            notification.setBody('Case #' + c.CaseNumber + ' has been assigned to you. Subject: ' + safeSubject(c));
            notification.setNotificationTypeId(notifType.Id);
            notification.setTargetId(c.Id);

            trySend(notification, new Set<String>{ c.OwnerId }, c.Id, 'Assigned');
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // STORY 3: ESCALATED → In-App + Email to Assignee & Supervisor (OOO routing)
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void sendEscalatedNotifications(List<Case> cases) {
        if (cases.isEmpty()) return;

        CustomNotificationType notifType = getNotificationType();
        EmailTemplate tpl = getTemplate(TPL_ESCALATED);
        Id supervisorId = getActiveSupervisorId(); // Handles OOO fallback

        for (Case c : cases) {
            Set<String> recipients = new Set<String>();

            // Add assignee
            if (c.OwnerId != null && isUserId(c.OwnerId)) {
                recipients.add(c.OwnerId);
            }
            // Add supervisor (Jay Ciccanti or Jay White if OOO)
            if (supervisorId != null) {
                recipients.add(supervisorId);
            }

            if (recipients.isEmpty()) continue;

            // ── In-App Bell ──
            if (notifType != null) {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle('⚠️ Ticket Escalated');
                notification.setBody('Case #' + c.CaseNumber + ' has been escalated. Subject: ' + safeSubject(c));
                notification.setNotificationTypeId(notifType.Id);
                notification.setTargetId(c.Id);
                trySend(notification, recipients, c.Id, 'Escalated');
            }

            // ── Email ──
            if (tpl != null) {
                List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
                for (String userId : recipients) {
                    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                    mail.setTemplateId(tpl.Id);
                    mail.setTargetObjectId(userId);
                    mail.setWhatId(c.Id);
                    mail.setSaveAsActivity(false);
                    emails.add(mail);
                }
                sendEmails(emails);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // STORY 5 (AC 5.1): RESOLVED → Email to Requestor (with opt-out)
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void sendResolvedNotifications(List<Case> cases) {
        if (cases.isEmpty()) return;

        EmailTemplate tpl = getTemplate(TPL_RESOLVED);
        if (tpl == null) {
            System.debug(LoggingLevel.WARN, 'eDiscovery: Resolved template not found: ' + TPL_RESOLVED);
            return;
        }

        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Case c : cases) {
            if (c.ContactId != null) contactIds.add(c.ContactId);
            if (c.AccountId != null) accountIds.add(c.AccountId);
        }

        Map<Id, Contact> contactMap = getContactOptOutMap(contactIds);
        Map<Id, Account> accountMap = getAccountOptOutMap(accountIds);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Case c : cases) {
            if (c.ContactId == null) continue;
            if (isNotificationSuppressed(c, contactMap, accountMap)) continue;

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTemplateId(tpl.Id);
            mail.setTargetObjectId(c.ContactId);
            mail.setWhatId(c.Id);
            mail.setSaveAsActivity(true);
            emails.add(mail);
        }

        if (!emails.isEmpty()) sendEmails(emails);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // STORY 5 (AC 5.2): CLOSED → Email to Requestor (auto-close notification)
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void sendClosedNotifications(List<Case> cases) {
        if (cases.isEmpty()) return;

        EmailTemplate tpl = getTemplate(TPL_CLOSED);
        if (tpl == null) {
            System.debug(LoggingLevel.WARN, 'eDiscovery: Closed template not found: ' + TPL_CLOSED);
            return;
        }

        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Case c : cases) {
            if (c.ContactId != null) contactIds.add(c.ContactId);
            if (c.AccountId != null) accountIds.add(c.AccountId);
        }

        Map<Id, Contact> contactMap = getContactOptOutMap(contactIds);
        Map<Id, Account> accountMap = getAccountOptOutMap(accountIds);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Case c : cases) {
            if (c.ContactId == null) continue;
            if (isNotificationSuppressed(c, contactMap, accountMap)) continue;

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTemplateId(tpl.Id);
            mail.setTargetObjectId(c.ContactId);
            mail.setWhatId(c.Id);
            mail.setSaveAsActivity(true);
            emails.add(mail);
        }

        if (!emails.isEmpty()) sendEmails(emails);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // STORY 6: SLA BREACH WARNING → In-App to Agent + Supervisor
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void sendSLAWarningNotifications(List<Case> cases) {
        if (cases.isEmpty()) return;

        CustomNotificationType notifType = getNotificationType();
        if (notifType == null) return;

        // SLA warning goes to Agent + Jay Ciccanti (no OOO check for in-app per ticket)
        Id supervisorId = getPrimarySupervisorId();

        for (Case c : cases) {
            Set<String> recipients = new Set<String>();

            if (c.OwnerId != null && isUserId(c.OwnerId)) {
                recipients.add(c.OwnerId);
            }
            if (supervisorId != null) {
                recipients.add(supervisorId);
            }

            if (recipients.isEmpty()) continue;

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('⚠️ SLA Breach Warning – 20 Minutes');
            notification.setBody('Case #' + c.CaseNumber + ' will breach SLA in 20 minutes. Take action now.');
            notification.setNotificationTypeId(notifType.Id);
            notification.setTargetId(c.Id);

            trySend(notification, recipients, c.Id, 'SLA Warning');
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // STORY 7: SLA BREACH → Email to Agent + Supervisor (OOO routing)
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void sendSLABreachNotifications(List<Case> cases) {
        if (cases.isEmpty()) return;

        EmailTemplate tpl = getTemplate(TPL_SLA_BREACH);
        if (tpl == null) {
            System.debug(LoggingLevel.WARN, 'eDiscovery: SLA Breach template not found: ' + TPL_SLA_BREACH);
            return;
        }

        Id supervisorId = getActiveSupervisorId(); // OOO-aware
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Case c : cases) {
            Set<Id> recipientUserIds = new Set<Id>();

            // Agent
            if (c.OwnerId != null && isUserId(c.OwnerId)) {
                recipientUserIds.add(c.OwnerId);
            }
            // Supervisor (Jay Ciccanti or Jay White if OOO)
            if (supervisorId != null) {
                recipientUserIds.add(supervisorId);
            }

            for (Id userId : recipientUserIds) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTemplateId(tpl.Id);
                mail.setTargetObjectId(userId);
                mail.setWhatId(c.Id);
                mail.setSaveAsActivity(false);
                emails.add(mail);
            }
        }

        if (!emails.isEmpty()) sendEmails(emails);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PRIVATE HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════

    /**
     * Returns the active supervisor Id.
     * If Jay Ciccanti is OOO, returns Jay White's Id instead.
     * Uses a custom checkbox field Is_Out_Of_Office__c on User.
     * (Alternative: check UserAvailability or OutOfOffice standard object)
     */
    private static Id getActiveSupervisorId() {
        Id primaryId = getPrimarySupervisorId();
        Id backupId  = getBackupSupervisorId();

        if (primaryId == null) return backupId;

        // Check if primary supervisor is Out of Office
        List<User> primaryUser = [
            SELECT Id, Out_of_Office__c 
            FROM User
            WHERE Id = :primaryId
            LIMIT 1
        ];

        if (!primaryUser.isEmpty() && primaryUser[0].Out_of_Office__c  == true) {
            return backupId;
        }
        return primaryId;
    }

    /**
     * Jay Ciccanti's User Id from Custom Label
     */
    private static Id getPrimarySupervisorId() {
        try {
            String val = System.Label.eDiscovery_Supervisor_Id;
            return String.isNotBlank(val) ? Id.valueOf(val.trim()) : null;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'eDiscovery: Invalid primary supervisor Id: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Jay White's User Id from Custom Label (backup when primary is OOO)
     */
    private static Id getBackupSupervisorId() {
        try {
            String val = System.Label.eDiscovery_Supervisor_Backup_Id;
            return String.isNotBlank(val) ? Id.valueOf(val.trim()) : null;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'eDiscovery: Invalid backup supervisor Id: ' + e.getMessage());
            return null;
        }
    }

    private static Id getEDiscoveryRecordTypeId() {
        Schema.RecordTypeInfo rtInfo = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get(EDISCOVERY_RT);
        return rtInfo != null ? rtInfo.getRecordTypeId() : null;
    }

    private static CustomNotificationType getNotificationType() {
        if (cachedNotifType != null) return cachedNotifType;
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType
            WHERE DeveloperName = :NOTIF_TYPE_DEV_NAME LIMIT 1
        ];
        cachedNotifType = types.isEmpty() ? null : types[0];
        return cachedNotifType;
    }

    private static EmailTemplate getTemplate(String devName) {
        if (cachedTemplates.containsKey(devName)) return cachedTemplates.get(devName);
        List<EmailTemplate> templates = [
            SELECT Id FROM EmailTemplate
            WHERE DeveloperName = :devName AND IsActive = true LIMIT 1
        ];
        EmailTemplate tpl = templates.isEmpty() ? null : templates[0];
        cachedTemplates.put(devName, tpl);
        return tpl;
    }

    /**
     * Checks if notifications are suppressed for a case's contact/account.
     */
    private static Boolean isNotificationSuppressed(Case c, Map<Id, Contact> contactMap, Map<Id, Account> accountMap) {
        // Contact-level opt-out
        if (c.ContactId != null) {
            Contact con = contactMap.get(c.ContactId);
            if (con != null && con.Disable_Ticket_Notifications__c == true) return true;
        }
        // Account-level opt-out
        Id acctId = c.AccountId;
        if (acctId == null && c.ContactId != null) {
            Contact con = contactMap.get(c.ContactId);
            if (con != null) acctId = con.AccountId;
        }
        if (acctId != null) {
            Account acct = accountMap.get(acctId);
            if (acct != null && acct.Disable_Ticket_Notifications__c == true) return true;
        }
        return false;
    }

    private static Map<Id, Contact> getContactOptOutMap(Set<Id> contactIds) {
        if (contactIds.isEmpty()) return new Map<Id, Contact>();
        return new Map<Id, Contact>([
            SELECT Id, Disable_Ticket_Notifications__c, AccountId
            FROM Contact WHERE Id IN :contactIds
        ]);
    }

    private static Map<Id, Account> getAccountOptOutMap(Set<Id> accountIds) {
        if (accountIds.isEmpty()) return new Map<Id, Account>();
        return new Map<Id, Account>([
            SELECT Id, Disable_Ticket_Notifications__c
            FROM Account WHERE Id IN :accountIds
        ]);
    }

    private static Boolean isUserId(Id recordId) {
        return String.valueOf(recordId).startsWith('005');
    }

    private static String safeSubject(Case c) {
        return c.Subject != null ? c.Subject : '(No Subject)';
    }

    private static void trySend(Messaging.CustomNotification notification, Set<String> recipients, Id caseId, String context) {
        try {
            notification.send(recipients);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'eDiscovery ' + context + ' notification failed for Case ' + caseId + ': ' + e.getMessage());
        }
    }

    private static void sendEmails(List<Messaging.SingleEmailMessage> emails) {
        if (emails.isEmpty()) return;
        List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Messaging.SendEmailError err : results[i].getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'eDiscovery email error: ' + err.getMessage());
                }
            }
        }
    }
}