public without sharing class TicketController {

    private static final String OWEA_FCP        = 'First Class Program';
    private static final String OWEA_STANDARD   = 'First Legal Services';

    private static final String FALLBACK_QUEUE_DEV_NAME = 'FSP_General_POD';

    private static final String TEMPLATE_BUSINESS_HOURS =
        'Ticket Created \u2013 First Response Email during Business Hours';
    private static final String TEMPLATE_AFTER_HOURS =
        'Ticket Created \u2013 First Response Email during AfterHours';

    private static final String BH_FCP      = 'First Class Program - All';
    private static final String BH_STANDARD = 'First Service Program - All';

    private static Map<String, User> userCache = new Map<String, User>();
    private static Map<String, OrgWideEmailAddress> oweaCache;
    private static Map<String, Id> emailTemplateCache;
    private static Map<String, BusinessHours> businessHoursCache;

    @AuraEnabled(cacheable=true)
    public static String getCurrentUserEmail() {
        List<User> users = [
            SELECT Email
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].Email;
    }

    @AuraEnabled
    public static Case submitTicket(
        String contactEmail,
        String ticketType,
        String subType,
        String priority,
        String subject,
        String description,
        String matterNumber,
        String courtCaseNumber,
        List<Id> cDocumentIds
    ) {
        if (String.isBlank(ticketType) || String.isBlank(subType) ||
            String.isBlank(priority) || String.isBlank(subject) || String.isBlank(description)) {
            throw new AuraHandledException('Please fill in all required fields.');
        }

        if (String.isBlank(contactEmail)) {
            contactEmail = getCurrentUserEmail();
        }

        User routingUser = resolveUser(contactEmail);
        Boolean isFCP = isFcpUser(routingUser);

        Case ticket = new Case();
        ticket.SuppliedEmail          = contactEmail;
        ticket.Source__c              = 'Portal';
        ticket.Type                   = ticketType;
        ticket.Ticket_SubType__c      = subType;
        ticket.Priority               = priority;
        ticket.Subject                = subject;
        ticket.Description            = description;
        ticket.Matter_Number__c       = matterNumber;
        ticket.Court_Case_Number__c   = courtCaseNumber;
        ticket.Status                 = 'New';
        ticket.RecordTypeId           = resolveRecordTypeId(isFCP);
        ticket.OwnerId                = resolveOwnerId(routingUser, isFCP);
        ticket.ContactId              = routingUser != null ? routingUser.ContactId : getContactId();

        insert ticket;

        List<Case> saved = [
            SELECT Id, CaseNumber
            FROM Case
            WHERE Id = :ticket.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (saved.isEmpty()) {
            throw new AuraHandledException('The ticket was created but could not be retrieved. Please contact support.');
        }

        String caseNumber = saved[0].CaseNumber;

        linkDocuments(ticket.Id, cDocumentIds);

        sendConfirmation(contactEmail, ticket.Id, ticket.ContactId, caseNumber, subject, priority, isFCP);

        return saved[0];
    }

    private static void linkDocuments(Id caseId, List<Id> cDocumentIds) {
        if (cDocumentIds == null || cDocumentIds.isEmpty()) {
            return;
        }

        Set<Id> alreadyLinked = new Set<Id>();
        for (ContentDocumentLink existing : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :caseId
            WITH SYSTEM_MODE
        ]) {
            alreadyLinked.add(existing.ContentDocumentId);
        }

        List<ContentDocumentLink> cdlsToCreate = new List<ContentDocumentLink>();
        for (Id cDocumentId : cDocumentIds) {
            if (cDocumentId == null || alreadyLinked.contains(cDocumentId)) {
                continue;
            }
            cdlsToCreate.add(new ContentDocumentLink(
                ContentDocumentId = cDocumentId,
                LinkedEntityId    = caseId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            ));
            alreadyLinked.add(cDocumentId);
        }

        if (cdlsToCreate.isEmpty()) {
            return;
        }

        for (Database.SaveResult sr : Database.insert(cdlsToCreate, false)) {
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(LoggingLevel.ERROR,
                        'ContentDocumentLink failed for Case ' + caseId + ': ' + err.getMessage());
                }
            }
        }
    }

    private static void sendConfirmation(
        String contactEmail,
        Id caseId,
        Id targetContactId,
        String caseNumber,
        String subject,
        String priority,
        Boolean isFCP
    ) {
        if (String.isBlank(contactEmail)) {
            System.debug(LoggingLevel.WARN,
                'No contact email available - confirmation skipped for Case ' + caseNumber);
            return;
        }

        try {
            OrgWideEmailAddress sender = getSenderAddress(isFCP);
            Boolean withinBusinessHours = isWithinBusinessHours(isFCP);
            Id templateId = getEmailTemplateId(withinBusinessHours);

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ contactEmail });
            mail.setSaveAsActivity(false);

            if (sender != null) {
                mail.setOrgWideEmailAddressId(sender.Id);
            } else {
                System.debug(LoggingLevel.WARN,
                    'No Org-Wide Email Address found for "' + (isFCP ? OWEA_FCP : OWEA_STANDARD) +
                    '" - falling back to the running user address.');
            }

            if (templateId != null && targetContactId != null) {
                mail.setTemplateId(templateId);
                mail.setTargetObjectId(targetContactId);
                mail.setWhatId(caseId);
            } 
            else {
                if (templateId == null) {
                    System.debug(LoggingLevel.WARN,
                        'Email template "' +
                        (withinBusinessHours ? TEMPLATE_BUSINESS_HOURS : TEMPLATE_AFTER_HOURS) +
                        '" was not found - sending fallback plain-text confirmation.');
                }
                mail.setSubject('Your Support Ticket Has Been Created - Case #' + caseNumber);
                mail.setPlainTextBody(buildBody(caseNumber, subject, priority, sender));
            }

            // allOrNone = false: an email failure must not roll back the ticket.
            List<Messaging.SendEmailResult> results =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);

            for (Messaging.SendEmailResult res : results) {
                if (!res.isSuccess()) {
                    for (Messaging.SendEmailError err : res.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'Confirmation email failed for Case ' + caseNumber + ': ' +
                            err.getStatusCode() + ' - ' + err.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Unexpected error sending confirmation for Case ' + caseNumber + ': ' + e.getMessage());
        }
    }

    private static String buildBody(
        String caseNumber,
        String subject,
        String priority,
        OrgWideEmailAddress sender
    ) {
        String teamName = (sender != null && String.isNotBlank(sender.DisplayName))
                        ? sender.DisplayName
                        : 'First Legal Support';

        return 'Thank you for reaching out. Your support ticket has been successfully created.\n\n' +
               'Case Number: ' + caseNumber + '\n' +
               'Subject: ' + subject + '\n' +
               'Priority: ' + priority + '\n\n' +
               'Our team will be in touch shortly.\n\n' +
               teamName + ' Team';
    }

    private static OrgWideEmailAddress getSenderAddress(Boolean isFCP) {
        loadOrgWideAddresses();

        String preferred = isFCP ? OWEA_FCP : OWEA_STANDARD;
        String secondary = isFCP ? OWEA_STANDARD : OWEA_FCP;

        if (oweaCache.containsKey(preferred)) {
            return oweaCache.get(preferred);
        }
        if (oweaCache.containsKey(secondary)) {
            return oweaCache.get(secondary);
        }
        return null;
    }

    private static void loadOrgWideAddresses() {
        if (oweaCache != null) {
            return;
        }

        oweaCache = new Map<String, OrgWideEmailAddress>();

        Set<String> displayNames = new Set<String>{ OWEA_FCP, OWEA_STANDARD };

        for (OrgWideEmailAddress owea : [
            SELECT Id, Address, DisplayName, IsAllowAllProfiles
            FROM OrgWideEmailAddress
            WHERE DisplayName IN :displayNames
            WITH SYSTEM_MODE
        ]) {
            oweaCache.put(owea.DisplayName, owea);
        }
    }

    private static Boolean isWithinBusinessHours(Boolean isFCP) {
        Id businessHoursId = getBusinessHoursId(isFCP);

        if (businessHoursId == null) {
            System.debug(LoggingLevel.WARN,
                'No BusinessHours record found for "' + (isFCP ? BH_FCP : BH_STANDARD) +
                '" - defaulting to after-hours email.');
            return false;
        }

        return BusinessHours.isWithin(businessHoursId, Datetime.now());
    }

    private static Id getBusinessHoursId(Boolean isFCP) {
        loadBusinessHours();

        String preferred = isFCP ? BH_FCP : BH_STANDARD;
        String secondary = isFCP ? BH_STANDARD : BH_FCP;

        if (businessHoursCache.containsKey(preferred)) {
            return businessHoursCache.get(preferred).Id;
        }
        if (businessHoursCache.containsKey(secondary)) {
            return businessHoursCache.get(secondary).Id;
        }
        return null;
    }

    private static void loadBusinessHours() {
        if (businessHoursCache != null) {
            return;
        }

        businessHoursCache = new Map<String, BusinessHours>();

        Set<String> names = new Set<String>{ BH_FCP, BH_STANDARD };

        for (BusinessHours bh : [
            SELECT Id, Name
            FROM BusinessHours
            WHERE Name IN :names
            WITH SYSTEM_MODE
        ]) {
            businessHoursCache.put(bh.Name, bh);
        }
    }

    private static Id getEmailTemplateId(Boolean withinBusinessHours) {
        loadEmailTemplates();
        String templateName = withinBusinessHours ? TEMPLATE_BUSINESS_HOURS : TEMPLATE_AFTER_HOURS;
        return emailTemplateCache.get(templateName);
    }

    private static void loadEmailTemplates() {
        if (emailTemplateCache != null) {
            return;
        }

        emailTemplateCache = new Map<String, Id>();

        Set<String> templateNames = new Set<String>{ TEMPLATE_BUSINESS_HOURS, TEMPLATE_AFTER_HOURS };

        for (EmailTemplate et : [
            SELECT Id, Name
            FROM EmailTemplate
            WHERE Name IN :templateNames
            WITH SYSTEM_MODE
        ]) {
            emailTemplateCache.put(et.Name, et.Id);
        }
    }

    @AuraEnabled(cacheable=true)
    public static Id getRecordTypeId() {
        return getRecordTypeId(null);
    }

    public static Id getRecordTypeId(String contactEmail) {
        User routingUser = resolveUser(contactEmail);
        return resolveRecordTypeId(isFcpUser(routingUser));
    }

    private static Id resolveRecordTypeId(Boolean isFCP) {
        String devName = isFCP ? 'CCT' : 'Client_Care';

        Schema.RecordTypeInfo info =
            Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get(devName);

        if (info == null) {
            throw new AuraHandledException('Case record type "' + devName + '" was not found.');
        }
        return info.getRecordTypeId();
    }

    public static Id getOwnerId() {
        return getOwnerId(null);
    }

    public static Id getOwnerId(String contactEmail) {
        User routingUser = resolveUser(contactEmail);
        return resolveOwnerId(routingUser, isFcpUser(routingUser));
    }

    private static Id resolveOwnerId(User routingUser, Boolean isFCP) {
        String podName = (routingUser != null && routingUser.Account != null)
                       ? routingUser.Account.Assigned_POD__c
                       : null;

        if (isFCP && String.isNotBlank(podName)) {
            List<Group> queues = [
                SELECT Id
                FROM Group
                WHERE Type = 'Queue' AND Name = :podName
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!queues.isEmpty()) {
                return queues[0].Id;
            }
        }

        List<Group> generalQueues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :FALLBACK_QUEUE_DEV_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        return generalQueues.isEmpty() ? null : generalQueues[0].Id;
    }

    private static Boolean isFcpUser(User routingUser) {
        return routingUser != null
            && routingUser.Account != null
            && routingUser.Account.Is_FCP_Customer__c == true;
    }

    private static User resolveUser(String contactEmail) {
        String cacheKey = String.isBlank(contactEmail) ? 'CURRENT_USER' : contactEmail.toLowerCase();

        if (userCache.containsKey(cacheKey)) {
            return userCache.get(cacheKey);
        }

        User resolved;

        if (String.isNotBlank(contactEmail)) {
            List<User> byEmail = [
                SELECT Id, Email, ContactId, Account.Is_FCP_Customer__c, Account.Assigned_POD__c
                FROM User
                WHERE Email = :contactEmail AND IsActive = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!byEmail.isEmpty()) {
                resolved = byEmail[0];
            }
        }

        if (resolved == null) {
            Id currentUserId = UserInfo.getUserId();
            List<User> byId = [
                SELECT Id, Email, ContactId, Account.Is_FCP_Customer__c, Account.Assigned_POD__c
                FROM User
                WHERE Id = :currentUserId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!byId.isEmpty()) {
                resolved = byId[0];
            }
        }

        userCache.put(cacheKey, resolved);
        return resolved;
    }

    public static Id getContactId() {
        List<User> users = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].ContactId;
    }
}