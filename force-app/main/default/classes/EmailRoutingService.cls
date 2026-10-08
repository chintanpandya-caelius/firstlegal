public inherited sharing class EmailRoutingService {

    private static final String STATUS_RESOLVED     = 'Resolved';
    private static final String STATUS_IN_PROGRESS  = 'In Progress';
    private static final String CASE_ORIGIN_EMAIL   = 'Email';

    private static final String RT_FIRST_CLASS_PROGRAM   = 'CCT';
    private static final String RT_FIRST_SERVICE_PROGRAM = 'Client_Care';

    private static final String FALLBACK_QUEUE_DEV_NAME = 'FSP_General_POD';
    private static final String FALLBACK_QUEUE_NAME     = 'FSP General POD';

    // One per email being routed.
    private class RoutingUnit {
        EmailMessage email;
        Id routingCaseId;
        Boolean wasResolved = false;
        Id resolvedContactId;
        Id resolvedAccountId;
        Id resolvedQueueId;
        String resolvedQueueName;
        Id resolvedRecordTypeId;
        Boolean isFCP = false;
        Contact pendingNewContact;
        Id contactIdNeedingAccountBackfill;
    }

    // Bulk-resolved lookup data shared across every unit being resolved in this batch.
    private class RoutingContext {
        Map<String, Ticket_Routing_Config__mdt> routingConfigByToAddress;
        Map<String, Contact> emailToContact;
        Map<Id, Account> accountHierarchyMap;
        Map<String, Account> domainToAccount;
        Map<String, Id> queueDevNameToId;
        Map<String, String> queueDevNameToName;
        Id fallbackQueueId;
        Id firstClassProgramRecordTypeId;
        Id firstServiceProgramRecordTypeId;
        Map<String, Schema.RecordTypeInfo> recordTypeInfoByDeveloperName;
        // Cache of new Contacts already built in this batch, keyed by FromAddress. Prevents Level 3/4/6
        // from creating a second Contact when multiple units in this same batch share the same FromAddress.
        Map<String, Contact> pendingContactsByEmail = new Map<String, Contact>();
    }

    public static void routeEmails(List<EmailMessage> newEmails) {

        List<EmailMessage> caseEmails = filterIncomingCaseEmails(newEmails);
        if (caseEmails.isEmpty()) return;

        Map<Id, Case> routableCaseMap = queryRoutableCases(caseEmails);
        if (routableCaseMap.isEmpty()) return;

        List<RoutingUnit> units = buildRoutingUnits(caseEmails, routableCaseMap);
        if (units.isEmpty()) return;

        RoutingContext ctx = buildRoutingContext(units);

        for (RoutingUnit unit : units) {
            resolveRoutingForUnit(unit, ctx);
        }

        // Contact auto-creation for unmatched senders is not finalized with the business yet.
        // The resolution logic below still builds the Contact records in memory (so Case
        // AccountId/isFCP resolution behaves the same either way), but the DML that would
        // actually persist them stays disabled until the approach is confirmed.
        insertPendingContacts(ctx.pendingContactsByEmail);
        backfillOrphanContactAccounts(units);

        updateRoutedCases(units, ctx);
    }

    // Step 1: Filter only inbound emails on Cases.
    private static List<EmailMessage> filterIncomingCaseEmails(List<EmailMessage> newEmails) {
        List<EmailMessage> caseEmails = new List<EmailMessage>();
        for (EmailMessage em : newEmails) {
            if (em.Incoming == true &&
                em.RelatedToId != null &&
                em.RelatedToId.getSObjectType() == Case.getSObjectType()) {
                caseEmails.add(em);
            }
        }
        return caseEmails;
    }

    // Step 2: Collect only the needed case records.
    private static Map<Id, Case> queryRoutableCases(List<EmailMessage> caseEmails) {
        Set<Id> caseIds = new Set<Id>();
        for (EmailMessage em : caseEmails) {
            caseIds.add(em.RelatedToId);
        }
        return new Map<Id, Case>([
            SELECT Id, Email_Routed__c, Status, IsClosed
            FROM Case
            WHERE Id IN :caseIds
            AND Origin = :CASE_ORIGIN_EMAIL
            AND (Email_Routed__c = false OR Status = :STATUS_RESOLVED)
            WITH SYSTEM_MODE
        ]);
    }

    // Step 3: From each EmailMessage, collect email, routingCaseId, wasResolved.
    private static List<RoutingUnit> buildRoutingUnits(List<EmailMessage> caseEmails, Map<Id, Case> routableCaseMap) {
        List<RoutingUnit> units = new List<RoutingUnit>();

        for (EmailMessage em : caseEmails) {
            Case c = routableCaseMap.get(em.RelatedToId);
            if (c == null) continue;

            RoutingUnit unit = new RoutingUnit();
            unit.email = em;
            unit.routingCaseId = c.Id;

            if (c.Status == STATUS_RESOLVED) {
                unit.wasResolved = true;
            } else if (c.Email_Routed__c) {
                continue;
            }

            units.add(unit);
        }
        return units;
    }

    // Steps 4-10: bulk-resolve everything the per-unit routing loop needs, in one shot.
    private static RoutingContext buildRoutingContext(List<RoutingUnit> units) {

        // Step 4: Collect FromAddress/FromDomain across all units.
        // (ToAddress is intentionally not collected in bulk here - see the Level 3 note below.)
        List<String> fromAddresses = new List<String>();
        Set<String> fromDomainSet = new Set<String>();

        for (RoutingUnit unit : units) {
            EmailMessage em = unit.email;
            if (String.isNotBlank(em.FromAddress)) {
                String fromEmail = em.FromAddress.trim().toLowerCase();
                fromAddresses.add(fromEmail);
                String domain = fromEmail.substringAfter('@');
                if (String.isNotBlank(domain)) {
                    fromDomainSet.add(domain.trim().toLowerCase());
                }
            }
        }

        RoutingContext ctx = new RoutingContext();

        // NOTE: Level 3 (Account match by ToAddress / Client_Specific_Email__c) is disabled per
        // the decision to eliminate client-specific emails - see resolveRoutingForUnit(). The
        // trackingEmailToAccount lookup and ToAddress collection it depended on are disabled here
        // too, since nothing else uses them. Restore both together if Level 3 is revived.

        // Step 6: Account by Domains__c (FromAddress domain match) - root accounts only.
        ctx.domainToAccount = queryAccountsByDomain(fromDomainSet);

        // Step 7: Contact by FromAddress, then its Account hierarchy.
        ctx.emailToContact = queryContactsByEmail(fromAddresses);

        Set<Id> contactAccountIds = new Set<Id>();
        for (Contact con : ctx.emailToContact.values()) {
            if (con.AccountId != null) contactAccountIds.add(con.AccountId);
        }
        ctx.accountHierarchyMap = AccountHierarchyUtil.buildHierarchyMap(
            contactAccountIds,
            new Set<String>{ 'Client_Specific_Email__c', 'Assigned_POD__c', 'Is_FCP_Customer__c' }
        );

        // Step 8: Queues.
        ctx.queueDevNameToId = new Map<String, Id>();
        ctx.queueDevNameToName = new Map<String, String>();
        for (Group g : [SELECT Id, Name, DeveloperName FROM Group WHERE Type = 'Queue' WITH SYSTEM_MODE]) {
            ctx.queueDevNameToId.put(g.DeveloperName, g.Id);
            ctx.queueDevNameToName.put(g.DeveloperName, g.Name);
        }
        ctx.fallbackQueueId = ctx.queueDevNameToId.get(FALLBACK_QUEUE_DEV_NAME);

        // Step 9: RecordTypes.
        Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName();
        ctx.firstClassProgramRecordTypeId = rtMap.containsKey(RT_FIRST_CLASS_PROGRAM)
            ? rtMap.get(RT_FIRST_CLASS_PROGRAM).getRecordTypeId() : null;
        ctx.firstServiceProgramRecordTypeId = rtMap.containsKey(RT_FIRST_SERVICE_PROGRAM)
            ? rtMap.get(RT_FIRST_SERVICE_PROGRAM).getRecordTypeId() : null;
        ctx.recordTypeInfoByDeveloperName = rtMap;

        // Step 10: Ticket_Routing_Config__mdt (Tier-1 override).
        ctx.routingConfigByToAddress = queryRoutingConfig();

        return ctx;
    }

    private static Map<String, Account> queryAccountsByDomain(Set<String> fromDomainSet) {
        Map<String, Account> domainToAccount = new Map<String, Account>();
        for (Account acc : [
            SELECT Id, Domains__c, Assigned_POD__c
            FROM Account
            WHERE Domains__c != null
            AND Parent_Account__c = true
            AND Is_FCP_Customer__c = true
            WITH SYSTEM_MODE
        ]) {
            if (String.isBlank(acc.Domains__c)) continue;
            for (String d : acc.Domains__c.split(';')) {
                String cleanDomain = d.trim().toLowerCase();
                if (String.isBlank(cleanDomain)) continue;
                if (fromDomainSet.contains(cleanDomain)) {
                    domainToAccount.put(cleanDomain, acc);
                }
            }
        }
        return domainToAccount;
    }

    private static Map<String, Contact> queryContactsByEmail(List<String> fromAddresses) {
        Map<String, Contact> emailToContact = new Map<String, Contact>();
        for (Contact con : [
            SELECT Id, Email, AccountId
            FROM Contact
            WHERE Email IN :fromAddresses
            WITH SYSTEM_MODE
        ]) {
            if (String.isNotBlank(con.Email)) {
                emailToContact.put(con.Email.trim().toLowerCase(), con);
            }
        }
        return emailToContact;
    }

    private static Map<String, Ticket_Routing_Config__mdt> queryRoutingConfig() {
        Map<String, Ticket_Routing_Config__mdt> routingConfigByToAddress = new Map<String, Ticket_Routing_Config__mdt>();
        for (Ticket_Routing_Config__mdt cfg : Ticket_Routing_Config__mdt.getAll().values()) {
            if (String.isNotBlank(cfg.ToEmailAddress__c)) {
                routingConfigByToAddress.put(cfg.ToEmailAddress__c.trim().toLowerCase(), cfg);
            }
        }
        return routingConfigByToAddress;
    }

    // Step 11 (per unit): resolve contact/account/queue/FCP flag for a single email, in fallback order.
    private static void resolveRoutingForUnit(RoutingUnit unit, RoutingContext ctx) {
        EmailMessage em = unit.email;

        String fromEmail = em.FromAddress != null ? em.FromAddress.trim().toLowerCase() : null;
        String fromName  = String.isNotBlank(em.FromName) ? em.FromName.trim()
                            : (fromEmail != null ? fromEmail.substringBefore('@') : '');
        String toEmail   = em.ToAddress != null ? em.ToAddress.trim().toLowerCase() : null;
        String domain    = fromEmail != null ? fromEmail.substringAfter('@') : null;

        String contactFirstName = '';
        String contactLastName  = fromName;
        if (fromName.contains(' ')) {
            contactFirstName = fromName.substringBefore(' ').trim();
            contactLastName  = fromName.substringAfter(' ').trim();
        }

        // Level 1: Routing Config check.
        Ticket_Routing_Config__mdt config = ctx.routingConfigByToAddress.get(toEmail);
        if (config != null && config.RouteToTier2__c) {
            if (ctx.queueDevNameToId.containsKey(config.QueueToAssign__c)) {
                unit.resolvedQueueId   = ctx.queueDevNameToId.get(config.QueueToAssign__c);
                unit.resolvedQueueName = ctx.queueDevNameToName.get(config.QueueToAssign__c);
            }
            // Once a Tier-1 config row specifies a record type, that's final - it isn't
            // overridden by the isFCP-based record type resolution in updateRoutedCases().
            unit.resolvedRecordTypeId = resolveConfigRecordTypeOverride(config, ctx.recordTypeInfoByDeveloperName);
        }

        // Level 2: Contact by FromAddress.
        if (fromEmail != null && ctx.emailToContact.containsKey(fromEmail)) {
            Contact matchedContact = ctx.emailToContact.get(fromEmail);
            unit.resolvedContactId = matchedContact.Id;
            unit.resolvedAccountId = matchedContact.AccountId;

            Id rootParentId = AccountHierarchyUtil.getRootParentId(matchedContact.AccountId, ctx.accountHierarchyMap);
            Account rootAcc = (rootParentId != null) ? ctx.accountHierarchyMap.get(rootParentId) : null;

            if (rootAcc != null) {
                unit.isFCP = (rootAcc.Is_FCP_Customer__c == true);
                if (unit.resolvedQueueId == null && String.isNotBlank(rootAcc.Client_Specific_Email__c)) {
                    String queueDevName = podToQueueDevName(rootAcc.Assigned_POD__c);
                    unit.resolvedQueueName = ctx.queueDevNameToName.get(queueDevName);
                    unit.resolvedQueueId   = ctx.queueDevNameToId.get(queueDevName);
                }
            }
        }

        /* BASED ON Discussion we wanted to eliminate client specific emails
        // Level 3: Account by ToAddress
        if (toEmail != null && trackingEmailToAccount.containsKey(toEmail)) {
            Account matchedAcc = trackingEmailToAccount.get(toEmail);
            if (unit.resolvedContactId == null) {
                // No existing contact at all - create one (or reuse one already built for this
                // FromAddress earlier in this same batch, instead of creating a duplicate)
                if (pendingContactsByEmail.containsKey(fromEmail)) {
                    unit.pendingNewContact = pendingContactsByEmail.get(fromEmail);
                } else {
                    unit.pendingNewContact = new Contact(
                        AccountId = matchedAcc.Id, Email = fromEmail,
                        FirstName = contactFirstName, LastName = contactLastName,
                        Status__c = 'Active'
                    );
                    pendingContactsByEmail.put(fromEmail, unit.pendingNewContact);
                }
                unit.resolvedAccountId = matchedAcc.Id;
                unit.isFCP = true;
            } else if (unit.resolvedAccountId == null) {
                // Existing contact found (Level 2) but it's an orphan with no Account -
                // backfill it instead of inserting a duplicate
                unit.contactIdNeedingAccountBackfill = unit.resolvedContactId;
                unit.resolvedAccountId = matchedAcc.Id;
                unit.isFCP = true;
            }
            if (unit.resolvedQueueId == null) {
                String queueDevName = podToQueueDevName(matchedAcc.Assigned_POD__c);
                unit.resolvedQueueName = queueDevNameToName.get(queueDevName);
                unit.resolvedQueueId   = queueDevNameToId.get(queueDevName);
            }
        }
        */

        // Level 4: Account by Domain.
        if (domain != null && ctx.domainToAccount.containsKey(domain)) {
            Account matchedAcc = ctx.domainToAccount.get(domain);
            if (unit.resolvedContactId == null) {
                // No existing contact at all - create one (or reuse one already built for this
                // FromAddress earlier in this same batch, instead of creating a duplicate).
                // Not inserted yet - see insertPendingContacts().
                if (ctx.pendingContactsByEmail.containsKey(fromEmail)) {
                    unit.pendingNewContact = ctx.pendingContactsByEmail.get(fromEmail);
                } else {
                    unit.pendingNewContact = new Contact(
                        AccountId = matchedAcc.Id, Email = fromEmail,
                        FirstName = contactFirstName, LastName = contactLastName,
                        Status__c = 'Active'
                    );
                    ctx.pendingContactsByEmail.put(fromEmail, unit.pendingNewContact);
                }
                unit.resolvedAccountId = matchedAcc.Id;
                unit.isFCP = true;
            } else if (unit.resolvedAccountId == null) {
                // Existing contact found (Level 2) but it's an orphan with no Account -
                // backfill it instead of inserting a duplicate. Not persisted yet - see
                // backfillOrphanContactAccounts().
                unit.contactIdNeedingAccountBackfill = unit.resolvedContactId;
                unit.resolvedAccountId = matchedAcc.Id;
                unit.isFCP = true;
            }
            if (unit.resolvedQueueId == null) {
                String queueDevName = podToQueueDevName(matchedAcc.Assigned_POD__c);
                unit.resolvedQueueName = ctx.queueDevNameToName.get(queueDevName);
                unit.resolvedQueueId   = ctx.queueDevNameToId.get(queueDevName);
            }
        }

        // Level 5: Fallback Queue.
        if (unit.resolvedQueueId == null) {
            unit.resolvedQueueName = FALLBACK_QUEUE_NAME;
            unit.resolvedQueueId   = ctx.fallbackQueueId;
        }

        // Level 6: Temporary Contact (no account match at all). Not inserted yet - see
        // insertPendingContacts().
        if (unit.resolvedContactId == null && unit.pendingNewContact == null) {
            if (ctx.pendingContactsByEmail.containsKey(fromEmail)) {
                unit.pendingNewContact = ctx.pendingContactsByEmail.get(fromEmail);
            } else {
                unit.pendingNewContact = new Contact(
                    Email = fromEmail, FirstName = contactFirstName,
                    LastName = contactLastName, Status__c = 'New'
                );
                ctx.pendingContactsByEmail.put(fromEmail, unit.pendingNewContact);
            }
        }
    }

    // Step 12: Insert pending new Contacts.
    // Contact auto-creation is not finalized yet - the insert stays disabled until it is.
    // Built from pendingContactsByEmail (unique per FromAddress) rather than looping units, so a
    // Contact shared by multiple units only gets inserted once.
    private static void insertPendingContacts(Map<String, Contact> pendingContactsByEmail) {
        List<Contact> contactsToInsert = new List<Contact>(pendingContactsByEmail.values());
        if (contactsToInsert.isEmpty()) return;

        // Database.insert(contactsToInsert, AccessLevel.SYSTEM_MODE);
    }

    // Step 12.5: Backfill AccountId on existing orphan Contacts (instead of duplicating them).
    // Disabled for the same reason as insertPendingContacts() above.
    private static void backfillOrphanContactAccounts(List<RoutingUnit> units) {
        Map<Id, Contact> contactsToUpdateMap = new Map<Id, Contact>();
        for (RoutingUnit unit : units) {
            if (unit.contactIdNeedingAccountBackfill != null) {
                contactsToUpdateMap.put(
                    unit.contactIdNeedingAccountBackfill,
                    new Contact(Id = unit.contactIdNeedingAccountBackfill, AccountId = unit.resolvedAccountId)
                );
            }
        }
        if (contactsToUpdateMap.isEmpty()) return;

        // Database.update(contactsToUpdateMap.values(), AccessLevel.SYSTEM_MODE);
    }

    // Resolves the Case record type a Tier-1 routing config row pins, if any. Only applies for
    // rows routed to Tier 2 with a RecordType_API_Name__c that matches an actual Case record type -
    // an unrecognized/blank value here just means "no override", not an error.
    @TestVisible
    private static Id resolveConfigRecordTypeOverride(
        Ticket_Routing_Config__mdt config, Map<String, Schema.RecordTypeInfo> recordTypeInfoByDeveloperName
    ) {
        if (config == null || !config.RouteToTier2__c || String.isBlank(config.RecordType_API_Name__c)) {
            return null;
        }
        Schema.RecordTypeInfo rtInfo = recordTypeInfoByDeveloperName.get(config.RecordType_API_Name__c);
        return rtInfo != null ? rtInfo.getRecordTypeId() : null;
    }

    // Step 13 & 14: build and apply the final Case updates.
    private static void updateRoutedCases(List<RoutingUnit> units, RoutingContext ctx) {
        List<Case> casesToUpdate = new List<Case>();

        for (RoutingUnit unit : units) {
            if (unit.pendingNewContact != null) {
                unit.resolvedContactId = unit.pendingNewContact.Id;
            }

            Id recordTypeId = unit.resolvedRecordTypeId != null
                ? unit.resolvedRecordTypeId
                : (unit.isFCP ? ctx.firstClassProgramRecordTypeId : ctx.firstServiceProgramRecordTypeId);

            Case caseToUpdate = new Case(
                Id              = unit.routingCaseId,
                OwnerId         = unit.resolvedQueueId,
                RecordTypeId    = recordTypeId,
                Sub_Division__c = unit.resolvedQueueName,
                Email_Routed__c = true
            );
            if (unit.resolvedContactId != null) caseToUpdate.ContactId = unit.resolvedContactId;
            if (unit.resolvedAccountId != null) caseToUpdate.AccountId = unit.resolvedAccountId;

            if (unit.wasResolved) {
                caseToUpdate.Status = STATUS_IN_PROGRESS;
            }

            casesToUpdate.add(caseToUpdate);
        }

        if (casesToUpdate.isEmpty()) return;

        try {
            Database.update(casesToUpdate, AccessLevel.SYSTEM_MODE);
        } catch (DmlException ex) {
            throw new EmailRoutingServiceException(
                'EmailRoutingService failed to update ' + casesToUpdate.size() +
                ' Case(s) during email routing: ' + ex.getMessage(), ex
            );
        }
    }

    private static String podToQueueDevName(String podValue) {
        if (String.isBlank(podValue)) return null;
        return podValue.trim().replaceAll('\\s+', '_');
    }

    public class EmailRoutingServiceException extends Exception {}
}