public class ReminderService {

    private static final String OWEA_FCP      = 'First Class Program';
    private static final String OWEA_STANDARD = 'First Legal Services';

    private static Map<String, OrgWideEmailAddress> oweaCache;

    // ── Mirrors TicketController.loadOrgWideAddresses() ──────────────────────
    private static void loadOrgWideAddresses() {
        System.debug(LoggingLevel.DEBUG, 'ReminderService.loadOrgWideAddresses() - ENTRY');
        if (oweaCache != null) {
            System.debug(LoggingLevel.DEBUG, 'ReminderService.loadOrgWideAddresses() - Cache already loaded: ' + oweaCache.keySet());
            return;
        }

        oweaCache = new Map<String, OrgWideEmailAddress>();

        for (OrgWideEmailAddress owea : [
            SELECT Id, Address, DisplayName
            FROM OrgWideEmailAddress
            WHERE DisplayName IN :new Set<String>{ OWEA_FCP, OWEA_STANDARD }
            WITH SYSTEM_MODE
        ]) {
            oweaCache.put(owea.DisplayName, owea);
        }
        System.debug(LoggingLevel.DEBUG, 'ReminderService.loadOrgWideAddresses() - EXIT, loaded: ' + oweaCache.keySet());
    }

    private static OrgWideEmailAddress getSenderAddress(Boolean isFCP) {
        System.debug(LoggingLevel.DEBUG, 'ReminderService.getSenderAddress() - ENTRY, isFCP: ' + isFCP);
        loadOrgWideAddresses();

        String preferred = isFCP ? OWEA_FCP : OWEA_STANDARD;
        String secondary = isFCP ? OWEA_STANDARD : OWEA_FCP;

        OrgWideEmailAddress selected;
        if (oweaCache.containsKey(preferred)) {
            selected = oweaCache.get(preferred);
        } else if (oweaCache.containsKey(secondary)) {
            selected = oweaCache.get(secondary);
        }

        System.debug(LoggingLevel.DEBUG, 'ReminderService.getSenderAddress() - EXIT, selected: ' + (selected != null ? selected.DisplayName : 'null'));
        return selected;
    }

    // ── Convenience: resolves isFCP from the Case field ──────────────────────
    private static Boolean isFcpCase(Case c) {
        System.debug(LoggingLevel.DEBUG, 'ReminderService.isFcpCase() - ENTRY for Case Id: ' + c?.Id);
        Boolean isFcp = c?.Account != null && c.Account.Is_FCP_Customer__c == true;
        System.debug(LoggingLevel.DEBUG, 'ReminderService.isFcpCase() - EXIT, result: ' + isFcp);
        return isFcp;
    }

    // ── Apply sender to any outbound email — single place, mirrors TC ────────
    private static void applySender(Messaging.SingleEmailMessage email, Case c) {
        System.debug(LoggingLevel.DEBUG, 'ReminderService.applySender() - ENTRY for Case Id: ' + c?.Id);
        OrgWideEmailAddress sender = getSenderAddress(isFcpCase(c));
        if (sender != null) {
            email.setOrgWideEmailAddressId(sender.Id);
            System.debug(LoggingLevel.DEBUG, 'ReminderService.applySender() - Applied OWEA: ' + sender.DisplayName + ' (' + sender.Id + ')');
        } else {
            System.debug(LoggingLevel.WARN,
                'ReminderService.applySender() - No Org-Wide Email Address found for Case ' + c?.Id +
                ' (isFCP=' + isFcpCase(c) + ') — falling back to running-user address.');
        }
        System.debug(LoggingLevel.DEBUG, 'ReminderService.applySender() - EXIT');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Main Service Methods
    // ─────────────────────────────────────────────────────────────────────────

    public static void initializeReminders(List<Case> cases, Map<Id, Case> oldMap) {
        System.debug(LoggingLevel.DEBUG, 'ReminderService.initializeReminders() - ENTRY with ' + (cases != null ? cases.size() : 0) + ' cases');
        if (cases == null || cases.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'ReminderService.initializeReminders() - No cases to process. EXIT');
            return;
        }

        Set<Id> recordTypeIds = new Set<Id>();
        Set<Id> ownerIds      = new Set<Id>();
        for (Case c : cases) {
            recordTypeIds.add(c.RecordTypeId);
            ownerIds.add(c.OwnerId);
        }

        Map<Id, RecordType> rtMap = new Map<Id, RecordType>(
            [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :recordTypeIds]
        );
        Map<Id, Group> queueMap = new Map<Id, Group>(
            [SELECT Id, DeveloperName FROM Group WHERE Id IN :ownerIds AND Type = 'Queue']
        );

        List<Case>     casesToUpdate = new List<Case>();
        List<FeedItem> feedItems     = new List<FeedItem>();
        Id initiatingUserId = UserInfo.getUserId();

        for (Case c : cases) {
            RecordType rt = rtMap.get(c.RecordTypeId);
            if (rt == null) continue;

            String queueDevName = null;
            Group q = queueMap.get(c.OwnerId);
            if (q != null) queueDevName = q.DeveloperName;

            ReminderStreamConfig.StreamDef stream = ReminderStreamConfig.findStream(
                rt.DeveloperName, queueDevName, c.SuppliedEmail
            );
            if (stream == null) continue;

            DateTime now           = DateTime.now();
            DateTime nextReminder  = BusinessDayCalculator.calculateNextReminderDateTime(now, 0, stream);
            Date     autoCloseDate = BusinessDayCalculator.calculateAutoCloseDate(now.date(), stream);

            Case toUpdate = new Case(Id = c.Id);
            toUpdate.Reminder_Count__c                    = 0;
            toUpdate.Next_Reminder_DateTime__c            = nextReminder;
            toUpdate.WoC_Entry_DateTime__c                = now;
            toUpdate.Auto_Close_Date__c                   = autoCloseDate;
            toUpdate.Calculated_Remaining_Closure_Date__c = autoCloseDate;
            toUpdate.Reminder_Active__c                   = true;
            toUpdate.Reminder_Stream_Name__c              = stream.streamName;
            toUpdate.Reminder_Initiated_By__c             = initiatingUserId;
            casesToUpdate.add(toUpdate);

            FeedItem fi = new FeedItem();
            fi.ParentId    = c.Id;
            fi.CreatedById = initiatingUserId;
            fi.Body = '[Reminder Automation] Series initiated for stream: ' + stream.streamName +
                      '. Reminder 1 scheduled for: ' +
                      (nextReminder != null ? nextReminder.format('yyyy-MM-dd HH:mm') : 'N/A') +
                      (autoCloseDate != null
                          ? '. Auto-close date: ' + String.valueOf(autoCloseDate)
                          : '. No auto-close.');
            feedItems.add(fi);
        }

        if (!casesToUpdate.isEmpty()) update casesToUpdate;
        if (!feedItems.isEmpty())     insert feedItems;

        System.debug(LoggingLevel.DEBUG, 'ReminderService.initializeReminders() - EXIT. Updated cases: ' + casesToUpdate.size() + ', FeedItems: ' + feedItems.size());
    }

    public static void cancelReminders(List<Case> cases) {
        System.debug(LoggingLevel.DEBUG, 'ReminderService.cancelReminders() - ENTRY with ' + (cases != null ? cases.size() : 0) + ' cases');
        if (cases == null || cases.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'ReminderService.cancelReminders() - No cases to process. EXIT');
            return;
        }

        Set<Id> caseIds = new Map<Id, Case>(cases).keySet();
        Map<Id, Case> caseWithInitiator = new Map<Id, Case>(
            [SELECT Id, Reminder_Active__c, Status, Reminder_Initiated_By__c
             FROM Case WHERE Id IN :caseIds]
        );

        List<Case>     casesToUpdate = new List<Case>();
        List<FeedItem> feedItems     = new List<FeedItem>();

        for (Case c : cases) {
            if (c.Reminder_Active__c != true) continue;

            Case queried    = caseWithInitiator.get(c.Id);
            Id feedAuthorId = queried?.Reminder_Initiated_By__c;

            Case toUpdate = new Case(Id = c.Id);
            toUpdate.Reminder_Count__c                    = 0;
            toUpdate.Next_Reminder_DateTime__c            = null;
            toUpdate.WoC_Entry_DateTime__c                = null;
            toUpdate.Auto_Close_Date__c                   = null;
            toUpdate.Calculated_Remaining_Closure_Date__c = null;
            toUpdate.Reminder_Active__c                   = false;
            toUpdate.Reminder_Stream_Name__c              = null;
            toUpdate.Reminder_Initiated_By__c             = null;
            casesToUpdate.add(toUpdate);

            if (feedAuthorId != null) {
                FeedItem fi = new FeedItem();
                fi.ParentId    = c.Id;
                fi.CreatedById = feedAuthorId;
                fi.Body = '[Reminder Automation] Series cancelled — stage changed to: ' + c.Status;
                feedItems.add(fi);
            }
        }

        if (!casesToUpdate.isEmpty()) update casesToUpdate;
        if (!feedItems.isEmpty())     insert feedItems;

        System.debug(LoggingLevel.DEBUG, 'ReminderService.cancelReminders() - EXIT. Cancelled cases: ' + casesToUpdate.size() + ', FeedItems: ' + feedItems.size());
    }

    public static void cancelOnResponse(Set<Id> caseIds) {
        System.debug(LoggingLevel.DEBUG, 'ReminderService.cancelOnResponse() - ENTRY with Case IDs: ' + caseIds);
        if (caseIds == null || caseIds.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'ReminderService.cancelOnResponse() - No Case IDs provided. EXIT');
            return;
        }

        List<Case> activeCases = [
            SELECT Id, Status, Reminder_Active__c, Reminder_Stream_Name__c,
                   Reminder_Initiated_By__c
            FROM Case
            WHERE Id IN :caseIds
              AND Reminder_Active__c = true
              AND Status = :ReminderStreamConfig.STAGE_WAITING_ON_CUSTOMER
        ];
        if (activeCases.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'ReminderService.cancelOnResponse() - No matching active waiting cases found. EXIT');
            return;
        }

        List<Case>     casesToUpdate = new List<Case>();
        List<FeedItem> feedItems     = new List<FeedItem>();

        for (Case c : activeCases) {
            Id feedAuthorId = c.Reminder_Initiated_By__c;

            Case toUpdate = new Case(Id = c.Id);
            toUpdate.Status                               = ReminderStreamConfig.STAGE_IN_PROGRESS;
            toUpdate.Reminder_Count__c                    = 0;
            toUpdate.Next_Reminder_DateTime__c            = null;
            toUpdate.WoC_Entry_DateTime__c                = null;
            toUpdate.Auto_Close_Date__c                   = null;
            toUpdate.Calculated_Remaining_Closure_Date__c = null;
            toUpdate.Reminder_Active__c                   = false;
            toUpdate.Reminder_Stream_Name__c              = null;
            toUpdate.Reminder_Initiated_By__c             = null;
            casesToUpdate.add(toUpdate);

            if (feedAuthorId != null) {
                FeedItem fi = new FeedItem();
                fi.ParentId    = c.Id;
                fi.CreatedById = feedAuthorId;
                fi.Body = '[Reminder Automation] Client responded — series cancelled, stage set to In Progress.';
                feedItems.add(fi);
            }
        }

        if (!casesToUpdate.isEmpty()) update casesToUpdate;
        if (!feedItems.isEmpty())     insert feedItems;

        System.debug(LoggingLevel.DEBUG, 'ReminderService.cancelOnResponse() - EXIT. Updated cases: ' + casesToUpdate.size() + ', FeedItems: ' + feedItems.size());
    }

    public static void processDueReminders() {
        DateTime now = DateTime.now();
        System.debug(LoggingLevel.DEBUG, 'ReminderService.processDueReminders() - ENTRY at ' + now);

        List<Case> dueCases = [SELECT Id, CaseNumber, Status, RecordTypeId, RecordType.DeveloperName,
                               OwnerId, SuppliedEmail, ContactId, Contact.Email, Contact.Name,
                               Reminder_Count__c, Next_Reminder_DateTime__c, WoC_Entry_DateTime__c,
                               Auto_Close_Date__c, Reminder_Active__c, Reminder_Stream_Name__c,
                               Suppress_Reminders__c, Subject,
                               Account.Is_FCP_Customer__c,
                               Reminder_Initiated_By__c
                               FROM Case
                               WHERE Reminder_Active__c = true
                               AND Next_Reminder_DateTime__c <= :now
                               AND Suppress_Reminders__c = false
                               ORDER BY Next_Reminder_DateTime__c ASC ];

        System.debug(LoggingLevel.DEBUG, 'ReminderService.processDueReminders() - Found ' + dueCases.size() + ' due cases');

        if (dueCases.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'ReminderService.processDueReminders() - No due cases to process. EXIT');
            return;
        }

        Set<Id> ownerIds = new Set<Id>();
        for (Case c : dueCases) ownerIds.add(c.OwnerId);

        Map<Id, Group> queueMap = new Map<Id, Group>([SELECT Id, DeveloperName FROM Group WHERE Id IN :ownerIds AND Type = 'Queue']);

        Set<String> templateNames = new Set<String>{ReminderStreamConfig.TPL_REMINDER_1,  ReminderStreamConfig.TPL_REMINDER_2,
                                                    ReminderStreamConfig.TPL_REMINDER_3,  ReminderStreamConfig.TPL_AUTO_CLOSE,
                                                    ReminderStreamConfig.TPL_SLA_WARNING, ReminderStreamConfig.TPL_SLA_BREACH,
                                                    ReminderStreamConfig.TPL_WO3P_DELAY };

        Map<String, Id> templateIdByName = new Map<String, Id>();
        for (EmailTemplate et : [SELECT Id, Name FROM EmailTemplate WHERE Name IN :templateNames]) {
            templateIdByName.put(et.Name, et.Id);
        }

        Set<String> reassignQueueNames = new Set<String>();
        for (ReminderStreamConfig.StreamDef s : ReminderStreamConfig.getStreams()) {
            if (String.isNotBlank(s.reassignQueueDeveloperName))
                reassignQueueNames.add(s.reassignQueueDeveloperName);
        }

        Map<String, Id> reassignQueueIdByName = new Map<String, Id>();
        if (!reassignQueueNames.isEmpty()) {
            for (Group g : [SELECT Id, DeveloperName FROM Group
                            WHERE DeveloperName IN :reassignQueueNames AND Type = 'Queue']) {
                reassignQueueIdByName.put(g.DeveloperName, g.Id);
            }
        }

        List<Case> casesToUpdate = new List<Case>();
        List<Messaging.SingleEmailMessage> emailsToSend  = new List<Messaging.SingleEmailMessage>();
        List<FeedItem> feedItems = new List<FeedItem>();

        for (Case c : dueCases) {
            String queueDevName = queueMap.containsKey(c.OwnerId) ? queueMap.get(c.OwnerId).DeveloperName : null;
            ReminderStreamConfig.StreamDef stream = ReminderStreamConfig.findStream(c.RecordType.DeveloperName, queueDevName, c.SuppliedEmail);

            Id feedAuthorId = c.Reminder_Initiated_By__c;

            if (stream == null) {
                System.debug(LoggingLevel.WARN, 'ReminderService.processDueReminders() - No stream found for Case ' + c.Id + ' (RecordType=' + c.RecordType?.DeveloperName + '). Deactivating reminder.');
                casesToUpdate.add(new Case(Id = c.Id, Reminder_Active__c = false));
                continue;
            }

            Integer reminderCount  = (c.Reminder_Count__c != null) ? c.Reminder_Count__c.intValue() : 0;
            Integer totalReminders = stream.reminderIntervals.size();

            if (reminderCount < totalReminders) {
                // ── Send reminder email ───────────────────────────────────────
                String templateName = stream.reminderTemplates[reminderCount];
                Id     templateId   = templateIdByName.get(templateName);
                if (templateId != null && c.ContactId != null) {
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setTemplateId(templateId);
                    email.setTargetObjectId(c.ContactId);
                    email.setWhatId(c.Id);
                    email.setSaveAsActivity(true);
                    email.setTreatTargetObjectAsRecipient(true);
                    applySender(email, c);
                    emailsToSend.add(email);
                }

                DateTime nextDT = BusinessDayCalculator.calculateNextReminderDateTime(
                    DateTime.now(), reminderCount + 1, stream
                );
                casesToUpdate.add(new Case(
                    Id                        = c.Id,
                    Reminder_Count__c         = reminderCount + 1,
                    Next_Reminder_DateTime__c = nextDT
                ));

                if (feedAuthorId != null) {
                    FeedItem fi = new FeedItem();
                    fi.ParentId    = c.Id;
                    fi.CreatedById = feedAuthorId;
                    fi.Body = '[Reminder Automation] Reminder ' + (reminderCount + 1) + ' sent. ' +
                              (nextDT != null
                                  ? 'Next action: ' + nextDT.format('yyyy-MM-dd HH:mm')
                                  : 'Series complete.');
                    feedItems.add(fi);
                }

            } else if (stream.hasAgentNotify && reminderCount == totalReminders) {
                // ── Agent notification ────────────────────────────────────────
                Id templateId = templateIdByName.get(stream.agentNotifyTemplate);
                if (templateId != null) {
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setTemplateId(templateId);
                    email.setTargetObjectId(c.OwnerId);
                    email.setWhatId(c.Id);
                    email.setSaveAsActivity(true);
                    applySender(email, c);
                    emailsToSend.add(email);
                }

                casesToUpdate.add(new Case(
                    Id                        = c.Id,
                    Reminder_Count__c         = reminderCount + 1,
                    Next_Reminder_DateTime__c = null,
                    Reminder_Active__c        = false
                ));

                if (feedAuthorId != null) {
                    FeedItem fi = new FeedItem();
                    fi.ParentId    = c.Id;
                    fi.CreatedById = feedAuthorId;
                    fi.Body = '[Reminder Automation] Agent notification sent. Series complete.';
                    feedItems.add(fi);
                }

            } else if (stream.hasAutoClose) {
                // ── Auto-close ────────────────────────────────────────────────
                Id templateId = templateIdByName.get(stream.autoCloseTemplate);
                if (templateId != null && c.ContactId != null) {
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setTemplateId(templateId);
                    email.setTargetObjectId(c.ContactId);
                    email.setWhatId(c.Id);
                    email.setSaveAsActivity(true);
                    email.setTreatTargetObjectAsRecipient(true);
                    applySender(email, c);
                    emailsToSend.add(email);
                }

                Case toUpdate = new Case(
                    Id                        = c.Id,
                    Status                    = ReminderStreamConfig.STAGE_CLOSED,
                    Reminder_Active__c        = false,
                    Next_Reminder_DateTime__c = null
                );
                if (String.isNotBlank(stream.reassignQueueDeveloperName)) {
                    Id qId = reassignQueueIdByName.get(stream.reassignQueueDeveloperName);
                    if (qId != null) toUpdate.OwnerId = qId;
                }
                casesToUpdate.add(toUpdate);

                if (feedAuthorId != null) {
                    FeedItem fi = new FeedItem();
                    fi.ParentId    = c.Id;
                    fi.CreatedById = feedAuthorId;
                    fi.Body = '[Reminder Automation] Auto-closed.';
                    feedItems.add(fi);
                }
            }
        }

        if (!emailsToSend.isEmpty()) {
            System.debug(emailsToSend.size());
            Messaging.SendEmailResult[] results = Messaging.sendEmail(emailsToSend, false);
            System.debug(LoggingLevel.DEBUG, 'ReminderService.processDueReminders() - Sent ' + emailsToSend.size() + ' emails. Results: ' + results);
        }
        if (!casesToUpdate.isEmpty()) update casesToUpdate;
        if (!feedItems.isEmpty())     insert feedItems;

        System.debug(LoggingLevel.DEBUG, 'ReminderService.processDueReminders() - EXIT. Updated cases: ' + casesToUpdate.size() + ', FeedItems: ' + feedItems.size());
    }

    public static void processWo3pReminders() {
        DateTime now = DateTime.now();
        System.debug(LoggingLevel.DEBUG, 'ReminderService.processWo3pReminders() - ENTRY at ' + now);

        List<Case> wo3pCases = [
            SELECT Id, RecordType.DeveloperName, OwnerId, SuppliedEmail,
                   ContactId, Reminder_Active__c, Reminder_Initiated_By__c
            FROM Case
            WHERE Reminder_Active__c = true
              AND Status = :ReminderStreamConfig.STAGE_WAITING_ON_3RD_PARTY
              AND Next_Reminder_DateTime__c <= :now
        ];
        System.debug(LoggingLevel.DEBUG, 'ReminderService.processWo3pReminders() - Found ' + wo3pCases.size() + ' WO3P cases');

        if (wo3pCases.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'ReminderService.processWo3pReminders() - No cases to process. EXIT');
            return;
        }

        List<Case> casesToUpdate = new List<Case>();
        for (Case c : wo3pCases) {
            ReminderStreamConfig.StreamDef stream = ReminderStreamConfig.findStream(
                c.RecordType.DeveloperName, null, c.SuppliedEmail
            );
            if (stream == null || !stream.hasWo3pReminder) continue;

            DateTime nextWo3p = DateTime.newInstance(
                BusinessDayCalculator.addBusinessDays(
                    now.date(), stream.wo3pIntervalDays, stream.businessHoursName
                ),
                Time.newInstance(9, 0, 0, 0)
            );
            casesToUpdate.add(new Case(Id = c.Id, Next_Reminder_DateTime__c = nextWo3p));
        }

        if (!casesToUpdate.isEmpty()) update casesToUpdate;
        System.debug(LoggingLevel.DEBUG, 'ReminderService.processWo3pReminders() - EXIT. Updated cases: ' + casesToUpdate.size());
    }
}