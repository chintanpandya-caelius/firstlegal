/**
 * ReminderService
 * Main engine for the unified email reminder system.
 * Handles initialization, processing, cancellation, auto-close, and email sending.
 * All methods are bulkified.
 */
public class ReminderService {

    // ─── CUSTOM FIELD API NAMES ON CASE ───
    // Reminder_Count__c          (Number)     — How many reminders sent so far
    // Next_Reminder_DateTime__c  (DateTime)   — When next action should fire
    // WoC_Entry_DateTime__c      (DateTime)   — When stage entered WoC
    // Auto_Close_Date__c         (Date)       — Calculated auto-close date
    // Calculated_Remaining_Closure_Date__c (Date) — Read-only, shown to agents
    // Reminder_Active__c         (Checkbox)   — TRUE when series is running
    // Reminder_Stream_Name__c    (Text 100)   — Which stream matched (for debugging)
    // Suppress_Reminders__c      (Checkbox)   — Manual override to stop reminders

    // ═══════════════════════════════════════════════════════════════════════════════
    // INITIALIZE REMINDERS — Called when stage changes TO "Waiting on Customer"
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void initializeReminders(List<Case> cases, Map<Id, Case> oldMap) {
        if (cases == null || cases.isEmpty()) return;

        // Gather RecordType and Queue info
        Set<Id> recordTypeIds = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();
        for (Case c : cases) {
            recordTypeIds.add(c.RecordTypeId);
            ownerIds.add(c.OwnerId);
        }

        // Query RecordType DeveloperNames
        Map<Id, RecordType> rtMap = new Map<Id, RecordType>(
            [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :recordTypeIds]
        );

        // Query Queue DeveloperNames (Owner could be User or Queue)
        Map<Id, Group> queueMap = new Map<Id, Group>(
            [SELECT Id, DeveloperName FROM Group WHERE Id IN :ownerIds AND Type = 'Queue']
        );

        List<Case> casesToUpdate = new List<Case>();
        List<FeedItem> feedItems = new List<FeedItem>();

        for (Case c : cases) {
            // Get RecordType DeveloperName
            RecordType rt = rtMap.get(c.RecordTypeId);
            if (rt == null) continue;

            // Get Queue DeveloperName (if owner is a queue)
            String queueDevName = null;
            Group q = queueMap.get(c.OwnerId);
            if (q != null) {
                queueDevName = q.DeveloperName;
            }

            // Get source email (SuppliedEmail = the email address that created the case)
            String sourceEmail = c.SuppliedEmail;

            // Find matching stream
            ReminderStreamConfig.StreamDef stream = ReminderStreamConfig.findStream(
                rt.DeveloperName, queueDevName, sourceEmail
            );

            if (stream == null) continue; // No stream matches — do nothing

            // Calculate dates
            DateTime now = DateTime.now();
            DateTime nextReminder = BusinessDayCalculator.calculateNextReminderDateTime(
                now, 0, stream
            );
            Date autoCloseDate = BusinessDayCalculator.calculateAutoCloseDate(now.date(), stream);

            // Update Case fields
            Case toUpdate = new Case(Id = c.Id);
            toUpdate.Reminder_Count__c = 0;
            toUpdate.Next_Reminder_DateTime__c = nextReminder;
            toUpdate.WoC_Entry_DateTime__c = now;
            toUpdate.Auto_Close_Date__c = autoCloseDate;
            toUpdate.Calculated_Remaining_Closure_Date__c = autoCloseDate;
            toUpdate.Reminder_Active__c = true;
            toUpdate.Reminder_Stream_Name__c = stream.streamName;
            casesToUpdate.add(toUpdate);

            // Log activity
            FeedItem fi = new FeedItem();
            fi.ParentId = c.Id;
            fi.Body = '[Reminder Automation] Series initiated for stream: ' + stream.streamName +
                      '. Reminder 1 scheduled for: ' + nextReminder.format('yyyy-MM-dd HH:mm') +
                      (autoCloseDate != null ? '. Auto-close date: ' + String.valueOf(autoCloseDate) : '. No auto-close.') ;
            feedItems.add(fi);
        }

        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
        if (!feedItems.isEmpty()) {
            insert feedItems;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CANCEL REMINDERS — Called when stage changes AWAY FROM "Waiting on Customer"
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void cancelReminders(List<Case> cases) {
        if (cases == null || cases.isEmpty()) return;

        List<Case> casesToUpdate = new List<Case>();
        List<FeedItem> feedItems = new List<FeedItem>();

        for (Case c : cases) {
            // Only cancel if reminders are active
            if (c.Reminder_Active__c != true) continue;

            Case toUpdate = new Case(Id = c.Id);
            toUpdate.Reminder_Count__c = 0;
            toUpdate.Next_Reminder_DateTime__c = null;
            toUpdate.WoC_Entry_DateTime__c = null;
            toUpdate.Auto_Close_Date__c = null;
            toUpdate.Calculated_Remaining_Closure_Date__c = null;
            toUpdate.Reminder_Active__c = false;
            toUpdate.Reminder_Stream_Name__c = null;
            casesToUpdate.add(toUpdate);

            FeedItem fi = new FeedItem();
            fi.ParentId = c.Id;
            fi.Body = '[Reminder Automation] Series cancelled — stage changed to: ' + c.Status;
            feedItems.add(fi);
        }

        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
        if (!feedItems.isEmpty()) {
            insert feedItems;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CANCEL ON RESPONSE — Called when inbound EmailMessage is received
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void cancelOnResponse(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) return;

        List<Case> activeCases = [
            SELECT Id, Status, Reminder_Active__c, Reminder_Stream_Name__c
            FROM Case
            WHERE Id IN :caseIds
              AND Reminder_Active__c = true
              AND Status = :ReminderStreamConfig.STAGE_WAITING_ON_CUSTOMER
        ];

        if (activeCases.isEmpty()) return;

        List<Case> casesToUpdate = new List<Case>();
        List<FeedItem> feedItems = new List<FeedItem>();

        for (Case c : activeCases) {
            Case toUpdate = new Case(Id = c.Id);
            toUpdate.Status = ReminderStreamConfig.STAGE_IN_PROGRESS;
            toUpdate.Reminder_Count__c = 0;
            toUpdate.Next_Reminder_DateTime__c = null;
            toUpdate.WoC_Entry_DateTime__c = null;
            toUpdate.Auto_Close_Date__c = null;
            toUpdate.Calculated_Remaining_Closure_Date__c = null;
            toUpdate.Reminder_Active__c = false;
            toUpdate.Reminder_Stream_Name__c = null;
            casesToUpdate.add(toUpdate);

            FeedItem fi = new FeedItem();
            fi.ParentId = c.Id;
            fi.Body = '[Reminder Automation] Client responded — series cancelled, stage set to In Progress.';
            feedItems.add(fi);
        }

        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
        if (!feedItems.isEmpty()) {
            insert feedItems;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PROCESS DUE REMINDERS — Called by ReminderSchedulable every 30 min
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void processDueReminders() {
        DateTime now = DateTime.now();

        List<Case> dueCases = [
            SELECT Id, CaseNumber, Status, RecordTypeId, RecordType.DeveloperName,
                   OwnerId, SuppliedEmail, ContactId, Contact.Email, Contact.Name,
                   Reminder_Count__c, Next_Reminder_DateTime__c, WoC_Entry_DateTime__c,
                   Auto_Close_Date__c, Reminder_Active__c, Reminder_Stream_Name__c,
                   Suppress_Reminders__c, Subject
            FROM Case
            WHERE Reminder_Active__c = true
              AND Next_Reminder_DateTime__c <= :now
              AND Suppress_Reminders__c != true
            ORDER BY Next_Reminder_DateTime__c ASC
            LIMIT 200
        ];

        if (dueCases.isEmpty()) return;

        // Get Queue info for all owners
        Set<Id> ownerIds = new Set<Id>();
        for (Case c : dueCases) {
            ownerIds.add(c.OwnerId);
        }
        Map<Id, Group> queueMap = new Map<Id, Group>(
            [SELECT Id, DeveloperName FROM Group WHERE Id IN :ownerIds AND Type = 'Queue']
        );

        // Get all Lightning Email Template Ids by Name
        Set<String> templateNames = new Set<String>();
        templateNames.add(ReminderStreamConfig.TPL_REMINDER_1);
        templateNames.add(ReminderStreamConfig.TPL_REMINDER_2);
        templateNames.add(ReminderStreamConfig.TPL_REMINDER_3);
        templateNames.add(ReminderStreamConfig.TPL_AUTO_CLOSE);
        templateNames.add(ReminderStreamConfig.TPL_SLA_WARNING);
        templateNames.add(ReminderStreamConfig.TPL_SLA_BREACH);
        templateNames.add(ReminderStreamConfig.TPL_WO3P_DELAY);

        Map<String, Id> templateIdByName = new Map<String, Id>();
        for (EmailTemplate et : [SELECT Id, Name FROM EmailTemplate WHERE Name IN :templateNames]) {
            templateIdByName.put(et.Name, et.Id);
        }

        // Get reassign queue Ids
        Set<String> reassignQueueNames = new Set<String>();
        for (ReminderStreamConfig.StreamDef s : ReminderStreamConfig.getStreams()) {
            if (String.isNotBlank(s.reassignQueueDeveloperName)) {
                reassignQueueNames.add(s.reassignQueueDeveloperName);
            }
        }
        Map<String, Id> reassignQueueIdByName = new Map<String, Id>();
        if (!reassignQueueNames.isEmpty()) {
            for (Group g : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN :reassignQueueNames AND Type = 'Queue']) {
                reassignQueueIdByName.put(g.DeveloperName, g.Id);
            }
        }

        List<Case> casesToUpdate = new List<Case>();
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        List<FeedItem> feedItems = new List<FeedItem>();

        for (Case c : dueCases) {
            // Find stream
            String queueDevName = null;
            Group q = queueMap.get(c.OwnerId);
            if (q != null) queueDevName = q.DeveloperName;

            ReminderStreamConfig.StreamDef stream = ReminderStreamConfig.findStream(
                c.RecordType.DeveloperName, queueDevName, c.SuppliedEmail
            );

            if (stream == null) {
                // Stream no longer matches (queue changed?) — deactivate
                Case toUpdate = new Case(Id = c.Id);
                toUpdate.Reminder_Active__c = false;
                casesToUpdate.add(toUpdate);
                continue;
            }

            Integer reminderCount = (c.Reminder_Count__c != null) ? c.Reminder_Count__c.intValue() : 0;
            Integer totalReminders = stream.reminderIntervals.size();

            // ─── DETERMINE WHAT ACTION TO TAKE ───
            if (reminderCount < totalReminders) {
                // ─── SEND NEXT REMINDER TO CLIENT ───
                String templateName = stream.reminderTemplates[reminderCount];
                Id templateId = templateIdByName.get(templateName);

                if (templateId != null && c.ContactId != null) {
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setTemplateId(templateId);
                    email.setTargetObjectId(c.ContactId);
                    email.setWhatId(c.Id);
                    email.setSaveAsActivity(true);
                    email.setTreatTargetObjectAsRecipient(true);
                    emailsToSend.add(email);
                }

                // Calculate next reminder date
                DateTime nextDT = BusinessDayCalculator.calculateNextReminderDateTime(
                    DateTime.now(), reminderCount + 1, stream
                );

                Case toUpdate = new Case(Id = c.Id);
                toUpdate.Reminder_Count__c = reminderCount + 1;
                toUpdate.Next_Reminder_DateTime__c = nextDT;
                casesToUpdate.add(toUpdate);

                // Log
                FeedItem fi = new FeedItem();
                fi.ParentId = c.Id;
                fi.Body = '[Reminder Automation] Reminder ' + (reminderCount + 1) + ' sent to ' +
                          (c.Contact != null ? c.Contact.Name : 'Contact') +
                          '. Template: ' + templateName +
                          (nextDT != null ? '. Next action: ' + nextDT.format('yyyy-MM-dd HH:mm') : '. Series complete.');
                feedItems.add(fi);

            } else if (stream.hasAgentNotify && reminderCount == totalReminders) {
                // ─── SEND AGENT NOTIFICATION ───
                Id templateId = templateIdByName.get(stream.agentNotifyTemplate);

                if (templateId != null) {
                    // Send to case owner (agent)
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setTemplateId(templateId);
                    email.setTargetObjectId(c.OwnerId);
                    email.setWhatId(c.Id);
                    email.setSaveAsActivity(true);
                    emailsToSend.add(email);
                }

                // After agent notify, series is done (no auto-close for these streams)
                Case toUpdate = new Case(Id = c.Id);
                toUpdate.Reminder_Count__c = reminderCount + 1;
                toUpdate.Next_Reminder_DateTime__c = null;
                toUpdate.Reminder_Active__c = false;
                casesToUpdate.add(toUpdate);

                FeedItem fi = new FeedItem();
                fi.ParentId = c.Id;
                fi.Body = '[Reminder Automation] Agent notification sent (SLA Breach Warning). Reminder series complete.';
                feedItems.add(fi);

            } else if (stream.hasAutoClose) {
                // ─── AUTO-CLOSE THE CASE ───
                Id templateId = templateIdByName.get(stream.autoCloseTemplate);

                // Send auto-close email to Contact (Requestor only)
                if (templateId != null && c.ContactId != null) {
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setTemplateId(templateId);
                    email.setTargetObjectId(c.ContactId);
                    email.setWhatId(c.Id);
                    email.setSaveAsActivity(true);
                    email.setTreatTargetObjectAsRecipient(true);
                    emailsToSend.add(email);
                }

                Case toUpdate = new Case(Id = c.Id);
                toUpdate.Status = ReminderStreamConfig.STAGE_CLOSED;
                toUpdate.Reminder_Active__c = false;
                toUpdate.Next_Reminder_DateTime__c = null;

                // Reassign to queue if configured
                if (String.isNotBlank(stream.reassignQueueDeveloperName)) {
                    Id reassignQueueId = reassignQueueIdByName.get(stream.reassignQueueDeveloperName);
                    if (reassignQueueId != null) {
                        toUpdate.OwnerId = reassignQueueId;
                    }
                }
                casesToUpdate.add(toUpdate);

                // Log
                String logMsg = '[Reminder Automation] Auto-closed. Email sent to ' +
                    (c.Contact != null ? c.Contact.Name : 'Contact') + '.';
                if (String.isNotBlank(stream.reassignQueueDeveloperName)) {
                    logMsg += ' Reassigned to queue: ' + stream.reassignQueueDeveloperName + '.';
                }
                FeedItem fi = new FeedItem();
                fi.ParentId = c.Id;
                fi.Body = logMsg;
                feedItems.add(fi);

                // Depo Calendar: also add internal CaseComment
                if (stream.streamName == 'Depo Calendar') {
                    FeedItem depoNote = new FeedItem();
                    depoNote.ParentId = c.Id;
                    depoNote.Body = 'No Response from the Client — ticket auto-closed by system.';
                    feedItems.add(depoNote);
                }

            } else {
                // ─── SERIES COMPLETE (no auto-close, no agent notify left) ───
                Case toUpdate = new Case(Id = c.Id);
                toUpdate.Reminder_Active__c = false;
                toUpdate.Next_Reminder_DateTime__c = null;
                casesToUpdate.add(toUpdate);

                FeedItem fi = new FeedItem();
                fi.ParentId = c.Id;
                fi.Body = '[Reminder Automation] All reminders sent. Series complete (no auto-close configured).';
                feedItems.add(fi);
            }
        }

        // ─── DML ───
        if (!emailsToSend.isEmpty()) {
            Messaging.sendEmail(emailsToSend, false); // false = don't throw on partial failure
        }
        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
        if (!feedItems.isEmpty()) {
            insert feedItems;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PROCESS WO3P REMINDERS — For Court & Process, Client Care (Waiting on 3rd Party)
    // ═══════════════════════════════════════════════════════════════════════════════
    public static void processWo3pReminders() {
        DateTime now = DateTime.now();

        List<Case> wo3pCases = [
            SELECT Id, CaseNumber, Status, RecordTypeId, RecordType.DeveloperName,
                   OwnerId, SuppliedEmail, ContactId, Contact.Email, Contact.Name,
                   Next_Reminder_DateTime__c, Reminder_Active__c, Reminder_Stream_Name__c,
                   Subject
            FROM Case
            WHERE Reminder_Active__c = true
              AND Status = :ReminderStreamConfig.STAGE_WAITING_ON_3RD_PARTY
              AND Next_Reminder_DateTime__c <= :now
              AND Suppress_Reminders__c != true
            LIMIT 200
        ];

        if (wo3pCases.isEmpty()) return;

        Set<Id> ownerIds = new Set<Id>();
        for (Case c : wo3pCases) ownerIds.add(c.OwnerId);
        Map<Id, Group> queueMap = new Map<Id, Group>(
            [SELECT Id, DeveloperName FROM Group WHERE Id IN :ownerIds AND Type = 'Queue']
        );

        // Get Wo3P template
        Id wo3pTemplateId = null;
        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE Name = :ReminderStreamConfig.TPL_WO3P_DELAY LIMIT 1];
        if (!templates.isEmpty()) wo3pTemplateId = templates[0].Id;

        List<Case> casesToUpdate = new List<Case>();
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        List<FeedItem> feedItems = new List<FeedItem>();

        for (Case c : wo3pCases) {
            String queueDevName = null;
            Group q = queueMap.get(c.OwnerId);
            if (q != null) queueDevName = q.DeveloperName;

            ReminderStreamConfig.StreamDef stream = ReminderStreamConfig.findStream(
                c.RecordType.DeveloperName, queueDevName, c.SuppliedEmail
            );

            if (stream == null || !stream.hasWo3pReminder) continue;

            // Send Wo3P email to Contact
            if (wo3pTemplateId != null && c.ContactId != null) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTemplateId(wo3pTemplateId);
                email.setTargetObjectId(c.ContactId);
                email.setWhatId(c.Id);
                email.setSaveAsActivity(true);
                email.setTreatTargetObjectAsRecipient(true);
                emailsToSend.add(email);
            }

            // Schedule next Wo3P reminder
            DateTime nextWo3p = DateTime.newInstance(
                BusinessDayCalculator.addBusinessDays(now.date(), stream.wo3pIntervalDays),
                Time.newInstance(9, 0, 0, 0)
            );

            Case toUpdate = new Case(Id = c.Id);
            toUpdate.Next_Reminder_DateTime__c = nextWo3p;
            casesToUpdate.add(toUpdate);

            FeedItem fi = new FeedItem();
            fi.ParentId = c.Id;
            fi.Body = '[Reminder Automation] Waiting on 3rd Party reminder sent. Next reminder: ' + nextWo3p.format('yyyy-MM-dd HH:mm');
            feedItems.add(fi);
        }

        if (!emailsToSend.isEmpty()) {
            Messaging.sendEmail(emailsToSend, false);
        }
        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
        if (!feedItems.isEmpty()) {
            insert feedItems;
        }
    }
}