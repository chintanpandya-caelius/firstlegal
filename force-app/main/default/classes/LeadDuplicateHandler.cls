public without sharing class LeadDuplicateHandler {

    public static Boolean isRunning = false;

    private static final String BDR_QUEUE_NAME = 'BDR_Queue';
    private static final String FIRST_CLASS_QUEUE_NAME = 'First_Class_Queue';

    @TestVisible
    public static void process(List<Lead> leads, Map<Id, Lead> oldMap) {

        System.debug('=== LeadDuplicateHandler.process START ===');
        System.debug('Processing ' + (leads != null ? leads.size() : 0) + ' leads.');

        if (isRunning) {
            System.debug('LeadDuplicateHandler is already running. Exiting recursion.');
            return;
        }

        try {
            Set<Id> leadIds = new Set<Id>();

            // Leads that should actually go through duplicate matching
            List<Lead> leadsForDuplicateCheck = new List<Lead>();

            // Leads where Matched_Account__c was explicitly changed
            Set<Id> manuallyChangedMatchedAccountIds = new Set<Id>();

            for (Lead leadRec : leads) {

                if (leadRec.Id == null) {
                    System.debug('Skipping lead with null Id (uncommitted record).');
                    continue;
                }

                leadIds.add(leadRec.Id);

                if (oldMap != null &&
                    oldMap.containsKey(leadRec.Id) &&
                    leadRec.Matched_Account__c != oldMap.get(leadRec.Id).Matched_Account__c) {

                    // Matched Account was explicitly changed.
                    // Do not run FindDuplicates again.
                    System.debug('Matched_Account__c manually modified for Lead Id: ' + leadRec.Id);
                    manuallyChangedMatchedAccountIds.add(leadRec.Id);

                } else {
                    // Normal insert/update → run duplicate matching
                    leadsForDuplicateCheck.add(leadRec);
                }
            }

            if (leadIds.isEmpty()) {
                System.debug('No valid Lead Ids to process. Exiting.');
                return;
            }

            Map<String, Id> queueIds = getQueueIds();

            Id bdrQueueId = queueIds.get(BDR_QUEUE_NAME);
            Id firstClassQueueId = queueIds.get(FIRST_CLASS_QUEUE_NAME);

            System.debug('Fetched Queue IDs -> BDR Queue: ' + bdrQueueId + ' | First Class Queue: ' + firstClassQueueId);

            Map<Id, Id> leadToAccountMap = new Map<Id, Id>();

            /*
             * Only run FindDuplicates for Leads where
             * Matched_Account__c was NOT manually changed.
             */
            for (Integer startIndex = 0;
                 startIndex < leadsForDuplicateCheck.size();
                 startIndex += 50) {

                Integer endIndex = Math.min(
                    startIndex + 50,
                    leadsForDuplicateCheck.size()
                );

                List<Lead> leadBatch = new List<Lead>();

                for (Integer i = startIndex; i < endIndex; i++) {
                    leadBatch.add(leadsForDuplicateCheck[i]);
                }

                try {

                    System.debug('Executing Datacloud.FindDuplicates for batch of ' + leadBatch.size() + ' leads.');
                    List<Datacloud.FindDuplicatesResult> results =
                        Datacloud.FindDuplicates.findDuplicates(leadBatch);

                    for (Integer i = 0; i < results.size(); i++) {

                        Lead leadRec = leadBatch[i];

                        Datacloud.FindDuplicatesResult findDupeResult =
                            results[i];

                        for (Datacloud.DuplicateResult dupeResult :
                             findDupeResult.getDuplicateResults()) {

                            for (Datacloud.MatchResult matchResult :
                                 dupeResult.getMatchResults()) {

                                for (Datacloud.MatchRecord matchRecord :
                                     matchResult.getMatchRecords()) {

                                    SObject matchedRecord =
                                        matchRecord.getRecord();

                                    if (matchedRecord != null &&
                                        matchedRecord.getSObjectType() ==
                                        Account.SObjectType) {

                                        Id accountId =
                                            (Id)matchedRecord.get('Id');

                                        if (accountId != null) {

                                            System.debug('Match Found -> Lead ID: ' + leadRec.Id + ' matched with Account ID: ' + accountId);

                                            leadToAccountMap.put(
                                                leadRec.Id,
                                                accountId
                                            );

                                            break;
                                        }
                                    }
                                }

                                if (leadToAccountMap.containsKey(leadRec.Id)) {
                                    break;
                                }
                            }

                            if (leadToAccountMap.containsKey(leadRec.Id)) {
                                break;
                            }
                        }
                    }

                } catch (Exception e) {

                    System.debug(
                        LoggingLevel.ERROR,
                        'Error in Datacloud dupe check: ' +
                        e.getMessage() + '\n' + e.getStackTraceString()
                    );
                }
            }

            List<Lead> leadsToUpdate = new List<Lead>();
            Map<Id, Lead> leadToNotifyMap = new Map<Id, Lead>();

            for (Lead leadRec : leads) {

                /*
                 * If Matched_Account__c was explicitly changed,
                 * honor the user's value and DO NOT overwrite it
                 * with a duplicate match.
                 */
                if (manuallyChangedMatchedAccountIds.contains(leadRec.Id)) {

                    if (leadRec.Matched_Account__c == null) {

                        // User cleared Matched Account
                        // → First Class Queue

                        if (firstClassQueueId != null &&
                            leadRec.OwnerId != firstClassQueueId) {

                            System.debug('Manual Change -> Matched Account cleared. Assigning Lead ' + leadRec.Id + ' to First Class Queue.');

                            leadsToUpdate.add(
                                new Lead(
                                    Id = leadRec.Id,
                                    OwnerId = firstClassQueueId
                                )
                            );
                        }

                    } else {

                        // User populated Matched Account
                        // → BDR Queue

                        if (bdrQueueId != null &&
                            leadRec.OwnerId != bdrQueueId) {

                            System.debug('Manual Change -> Matched Account set. Assigning Lead ' + leadRec.Id + ' to BDR Queue.');

                            leadsToUpdate.add(
                                new Lead(
                                    Id = leadRec.Id,
                                    OwnerId = bdrQueueId
                                )
                            );
                        }
                    }

                    continue;
                }

                /*
                 * Normal duplicate matching logic
                 */
                Id matchedAccountId =
                    leadToAccountMap.get(leadRec.Id);

                if (matchedAccountId != null) {

                    // Match found → BDR Queue
                    if (leadRec.Matched_Account__c != matchedAccountId ||
                        (bdrQueueId != null &&
                         leadRec.OwnerId != bdrQueueId)) {

                        System.debug('Match Processed -> Lead ' + leadRec.Id + ' updating Matched_Account__c: ' + matchedAccountId + ' & OwnerId: ' + bdrQueueId);

                        Lead lUpd = new Lead(
                            Id = leadRec.Id,
                            Matched_Account__c = matchedAccountId
                        );

                        if (bdrQueueId != null) {
                            lUpd.OwnerId = bdrQueueId;
                        }

                        leadsToUpdate.add(lUpd);
                        leadToNotifyMap.put(leadRec.Id, leadRec);
                    }

                } else {

                    // No match → First Class Queue
                    if (leadRec.Matched_Account__c != null ||
                        (firstClassQueueId != null &&
                         leadRec.OwnerId != firstClassQueueId)) {

                        System.debug('No Match -> Clearing Matched_Account__c & assigning Lead ' + leadRec.Id + ' to First Class Queue.');

                        Lead lUpd = new Lead(
                            Id = leadRec.Id,
                            Matched_Account__c = null
                        );

                        if (firstClassQueueId != null) {
                            lUpd.OwnerId = firstClassQueueId;
                        }

                        leadsToUpdate.add(lUpd);
                    }
                }
            }

            if (!leadsToUpdate.isEmpty()) {

                System.debug('Attempting DML Update on ' + leadsToUpdate.size() + ' Leads: ' + leadsToUpdate);

                isRunning = true;

                Database.SaveResult[] updateResults = Database.update(leadsToUpdate, false);

                for (Integer i = 0; i < updateResults.size(); i++) {
                    Database.SaveResult sr = updateResults[i];
                    Lead failedLead = leadsToUpdate[i];

                    if (sr.isSuccess()) {
                        System.debug('SUCCESS: Updated Lead ID: ' + sr.getId());
                    } else {
                        for (Database.Error err : sr.getErrors()) {
                            System.debug(
                                LoggingLevel.ERROR,
                                'DML FAILURE on Lead ID (' + failedLead.Id + '): ' + 
                                err.getStatusCode() + ' - ' + err.getMessage() + 
                                ' | Fields affected: ' + err.getFields()
                            );
                        }
                    }
                }

                sendDuplicateNotifications(leadToNotifyMap);
            } else {
                System.debug('No leads required updating.');
            }

        } catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'Error in LeadDuplicateHandler.process: ' +
                e.getMessage() + '\n' + e.getStackTraceString()
            );

            throw e;

        } finally {

            isRunning = false;
            System.debug('=== LeadDuplicateHandler.process END ===');
        }
    }

    private static Map<String, Id> getQueueIds() {

        Set<String> queueNames = new Set<String>{
            BDR_QUEUE_NAME,
            FIRST_CLASS_QUEUE_NAME
        };

        List<Group> queues = [
            SELECT Id, DeveloperName
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName IN :queueNames
        ];

        Map<String, Id> queueIds = new Map<String, Id>();

        for (Group queue : queues) {
            queueIds.put(
                queue.DeveloperName,
                queue.Id
            );
        }

        if (!queueIds.containsKey(BDR_QUEUE_NAME)) {
            System.debug(LoggingLevel.WARN, 'WARNING: BDR Queue ("' + BDR_QUEUE_NAME + '") was not found in Group query.');
        }
        if (!queueIds.containsKey(FIRST_CLASS_QUEUE_NAME)) {
            System.debug(LoggingLevel.WARN, 'WARNING: First Class Queue ("' + FIRST_CLASS_QUEUE_NAME + '") was not found in Group query.');
        }

        return queueIds;
    }

    private static void sendDuplicateNotifications(
        Map<Id, Lead> leadToNotifyMap
    ) {

        System.debug('=== sendDuplicateNotifications START ===');

        if (leadToNotifyMap.isEmpty()) {
            System.debug('No leads to notify.');
            return;
        }

        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName =
                'Lead_Duplicate_Account_Notification'
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'EmailTemplate "Lead_Duplicate_Account_Notification" not found.');
            return;
        }

        Id templateId = templates[0].Id;

        List<Messaging.SingleEmailMessage> emailList =
            new List<Messaging.SingleEmailMessage>();

        for (Id leadId : leadToNotifyMap.keySet()) {

            Lead currentLead = leadToNotifyMap.get(leadId);
            Id ownerId = currentLead.OwnerId;

            if (ownerId != null &&
                String.valueOf(ownerId).startsWith('005')) {

                System.debug('Building email for User Owner ID: ' + ownerId + ' on Lead ID: ' + currentLead.Id);

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTemplateId(templateId);
                email.setTargetObjectId(ownerId);
                email.setWhatId(currentLead.Id);
                email.setSaveAsActivity(false);

                emailList.add(email);
            } else {
                System.debug('Skipping email notification: Owner ID (' + ownerId + ') is either null or a Queue/Group, not a User.');
            }
        }

        if (!emailList.isEmpty()) {

            try {

                System.debug('Sending ' + emailList.size() + ' duplicate notification emails...');

                Messaging.sendEmail(
                    emailList,
                    false
                );

                System.debug('Emails sent successfully.');

            } catch (Exception e) {

                System.debug(
                    LoggingLevel.ERROR,
                    'Error sending template emails: ' +
                    e.getMessage() + '\n' + e.getStackTraceString()
                );
            }
        }

        System.debug('=== sendDuplicateNotifications END ===');
    }
}