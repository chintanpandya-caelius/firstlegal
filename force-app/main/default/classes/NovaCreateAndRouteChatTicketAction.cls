public with sharing class NovaCreateAndRouteChatTicketAction {
    // ─── Request ──────────────────────────────────────────────────────────────
    public class Request {

        @InvocableVariable(label='Contact Email' description='Email of the customer from pre-chat form' required=false)
        public String contactEmail;

        @InvocableVariable(label='Contact ID' description='Salesforce Contact ID if already resolved' required=false)
        public Id contactId;

        @InvocableVariable(label='Account ID' description='Salesforce Account ID if already resolved' required=false)
        public Id accountId;

        @InvocableVariable(label='Subject' description='Short subject/title of the ticket' required=true)
        public String subject;

        @InvocableVariable(label='Description' description='Full issue description from customer' required=false)
        public String description;

        @InvocableVariable(label='Priority' description='Case priority: Low, Medium, High, Critical' required=false)
        public String priority;

        @InvocableVariable(label='Case Type' description='Type of case e.g. Question, Problem, Feature Request' required=false)
        public String caseType;

        @InvocableVariable(label='Reason for Chat' description='Intent/topic captured by Agentforce pre-chat form or bot' required=false)
        public String chatReason;

        @InvocableVariable(label='Chat Transcript' description='Full bot transcript or initial customer message' required=false)
        public String chatTranscript;

        @InvocableVariable(label='Is Ambiguous Account Match' description='True if multiple Accounts matched; triggers EC3 fallback' required=false)
        public Boolean isAmbiguousAccount = false;
    }

    // ─── Result ───────────────────────────────────────────────────────────────
    public class Result {

        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Case ID')
        public Id caseId;

        @InvocableVariable(label='Case Number')
        public String caseNumber;

        @InvocableVariable(label='Classification' description='FCP or FSP')
        public String classification;

        @InvocableVariable(label='Assigned Queue Name')
        public String assignedQueueName;

        @InvocableVariable(label='Assigned Queue ID')
        public Id assignedQueueId;

        @InvocableVariable(label='Routing Log' description='Full decision audit trail returned to Agentforce')
        public String routingLog;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    // ─── Invocable Entry Point ────────────────────────────────────────────────
    @InvocableMethod(
        label       = 'Create & Route Chat Ticket (NOVA-3820)'
        description = 'Creates a Case from Agentforce chat session, classifies as FCP/FSP, and routes to the correct Omni-Channel queue.'
        category    = 'Ticket Management'
    )
    public static List<Result> createAndRouteTickets(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        Map<String, Group> queueMap = getQueueMap();

        for (Request req : requests) {
            Result res        = new Result();
            res.isSuccess     = false;
            List<String> log  = new List<String>();
            log.add('=== NOVA Chat Ticket Routing Log ===');
            log.add('Initiated: ' + System.now());

            try {
                // ── STEP 1: Resolve Contact ───────────────────────────────────
                Id resolvedContactId = req.contactId;
                Id resolvedAccountId = req.accountId;

                if (resolvedContactId == null && String.isNotBlank(req.contactEmail)) {
                    List<Contact> contacts = [
                        SELECT Id, AccountId, Name
                        FROM Contact
                        WHERE Email = :req.contactEmail
                        LIMIT 2
                    ];

                    if (contacts.size() == 1) {
                        resolvedContactId = contacts[0].Id;
                        if (resolvedAccountId == null) {
                            resolvedAccountId = contacts[0].AccountId;
                        }
                        log.add('Contact resolved via email: ' + contacts[0].Name);
                    } else if (contacts.size() > 1) {
                        req.isAmbiguousAccount = true;
                        log.add('EC2 Triggered: Multiple Contacts matched email [' + req.contactEmail + ']. Ambiguous flag set.');
                    } else {
                        log.add('EC2 Triggered: No Contact found for email [' + req.contactEmail + ']. Case created without Contact link.');
                    }
                }

                // ── STEP 2: Resolve Account ───────────────────────────────────
                Account acc = null;
                if (resolvedAccountId != null && !req.isAmbiguousAccount) {
                    List<Account> accList = [
                        SELECT Id, Name, Is_FCP_Customer__c, Assigned_POD__c
                        FROM Account
                        WHERE Id = :resolvedAccountId
                        LIMIT 1
                    ];
                    if (!accList.isEmpty()) {
                        acc = accList[0];
                        log.add('Account resolved: ' + acc.Name +
                                ' | FCP=' + acc.Is_FCP_Customer__c +
                                ' | POD=' + acc.Assigned_POD__c);
                    }
                }

                if (req.isAmbiguousAccount) {
                    log.add('EC3 Triggered: Ambiguous Account. Will default to FSP routing track.');
                }

                // ── STEP 3: Create Case (standard fields only) ────────────────
                Case newCase        = new Case();
                newCase.Subject     = req.subject;
                newCase.Description = req.description;
                newCase.Origin      = 'Chat';
                newCase.Status      = 'New';
                newCase.Priority    = String.isNotBlank(req.priority) ? req.priority : 'Medium';

                if (String.isNotBlank(req.caseType)) {
                    newCase.Type = req.caseType;
                }
                if (resolvedContactId != null) {
                    newCase.ContactId = resolvedContactId;
                }
                if (resolvedAccountId != null && !req.isAmbiguousAccount) {
                    newCase.AccountId = resolvedAccountId;
                }

                insert newCase;
                log.add('Case inserted: ' + newCase.Id);

                // Re-query for CaseNumber
                newCase = [SELECT Id, CaseNumber FROM Case WHERE Id = :newCase.Id LIMIT 1];
                log.add('Case Number: ' + newCase.CaseNumber);

                // ── STEP 4 & 5: FCP / FSP Classification ─────────────────────
                String classification;
                String targetQueueDevName;

                Boolean isFCP = (acc != null && acc.Is_FCP_Customer__c == true && !req.isAmbiguousAccount);

                if (isFCP) {
                    // AC1 — FCP Track
                    classification = 'FCP';
                    log.add('AC1: Account is FCP Customer.');

                    String podQueue = acc.Assigned_POD__c;
                    if (String.isNotBlank(podQueue) && queueMap.containsKey(podQueue)) {
                        targetQueueDevName = podQueue;
                        log.add('Routed to FCP Pod Queue: ' + targetQueueDevName);
                    } else {
                        // EC1 / EC6 — Pod queue missing or inactive
                        targetQueueDevName = QUEUE_FCP_GENERAL;
                        log.add('EC1/EC6 Fallback: FCP Pod Queue [' + podQueue + '] not found or inactive. Using FCP General Queue.');
                    }
                } else {
                    // AC2 — FSP Track
                    classification = 'FSP';
                    log.add('AC2: Ticket classified as FSP (Non-FCP / Unidentified / Ambiguous Account).');
                    targetQueueDevName = classifyFSPDivision(req.chatReason, req.chatTranscript, log);
                }

                // ── STEP 6: Safety Fallback ───────────────────────────────────
                Group targetQueue = queueMap.get(targetQueueDevName);
                if (targetQueue == null) {
                    targetQueueDevName = QUEUE_FSP_GENERAL;
                    targetQueue        = queueMap.get(QUEUE_FSP_GENERAL);
                    log.add('Safety Fallback: Target queue not found. Defaulting to FSP General Queue.');
                }

                // ── STEP 7: Update Case OwnerId only ─────────────────────────
                Case updateCase    = new Case(Id = newCase.Id);
                updateCase.OwnerId = targetQueue.Id;
                update updateCase;

                log.add('Case OwnerId set to: ' + targetQueue.Name + ' (' + targetQueueDevName + ')');
                log.add('=== Routing Complete ===');

                // ── STEP 8: Build Result ──────────────────────────────────────
                res.isSuccess         = true;
                res.caseId            = newCase.Id;
                res.caseNumber        = newCase.CaseNumber;
                res.classification    = classification;
                res.assignedQueueName = targetQueueDevName;
                res.assignedQueueId   = targetQueue.Id;
                res.routingLog        = String.join(log, '\n');

            } catch (Exception ex) {
                res.isSuccess    = false;
                res.errorMessage = ex.getMessage() + ' | Stack: ' + ex.getStackTraceString();
                log.add('ERROR: ' + res.errorMessage);
                res.routingLog   = String.join(log, '\n');
            }

            results.add(res);
        }

        return results;
    }

    // ─── FSP Division Classifier ──────────────────────────────────────────────
    private static String classifyFSPDivision(String chatReason, String chatTranscript, List<String> log) {
        String combined = (
            (String.isNotBlank(chatReason)     ? chatReason     : '') + ' ' +
            (String.isNotBlank(chatTranscript) ? chatTranscript : '')
        ).toLowerCase();

        if (String.isBlank(combined.trim())) {
            log.add('EC4 Triggered: No intent or transcript signals. Fallback to FSP General.');
            return QUEUE_FSP_GENERAL;
        }

        Map<String, Set<String>> divisionKeywords = new Map<String, Set<String>>{
            QUEUE_DIGITAL     => new Set<String>{ 'copy', 'scan', 'trial support', 'demonstrative', 'binder', 'blowup', 'imaging', 'digital print', 'digital' },
            QUEUE_DEPO        => new Set<String>{ 'deposition', 'court reporter', 'transcript', 'videography', 'reporter scheduling', 'expedite', 'rough draft', 'errata', 'solaria' },
            QUEUE_COURT_PROC  => new Set<String>{ 'efiling', 'e-filing', 'court filing', 'process serving', 'service of process', 'subpoena delivery', 'document filing', 'legal connect', 'courier' },
            QUEUE_INVESTIGATE => new Set<String>{ 'investigation', 'surveillance', 'skip trace', 'locate', 'background check', 'private investigator' },
            QUEUE_RECORDS     => new Set<String>{ 'records retrieval', 'medical records', 'subpoena duces tecum', 'custodian of records', 'document production', 'interstate records' },
            QUEUE_EDISCOVERY  => new Set<String>{ 'ediscovery', 'e-discovery', 'document review', 'litigation support', 'data processing', 'hosted review', 'pts support' },
            QUEUE_FINANCE     => new Set<String>{ 'invoicing', 'billing', 'payment', 'account balance', 'collection', 'account maintenance', 'new account' }
        };

        Map<String, Integer> scoreMap = new Map<String, Integer>();
        for (String q : divisionKeywords.keySet()) {
            Integer score = 0;
            for (String kw : divisionKeywords.get(q)) {
                if (combined.contains(kw)) score++;
            }
            if (score > 0) scoreMap.put(q, score);
        }

        String  bestMatch = null;
        Integer maxScore  = 0;
        Boolean isTie     = false;

        for (String q : scoreMap.keySet()) {
            Integer s = scoreMap.get(q);
            if      (s > maxScore)  { maxScore = s; bestMatch = q; isTie = false; }
            else if (s == maxScore) { isTie = true; }
        }

        if (maxScore > 0 && !isTie) {
            log.add('FSP Division matched: [' + bestMatch + '] with confidence score ' + maxScore);
            return bestMatch;
        } else if (isTie) {
            log.add('EC4 Triggered: Tied scores across multiple FSP divisions. Fallback to FSP General.');
        } else {
            log.add('EC4 Triggered: No keyword match. Fallback to FSP General.');
        }
        return QUEUE_FSP_GENERAL;
    }

    // ─── Queue Cache Helper ───────────────────────────────────────────────────
    private static Map<String, Group> getQueueMap() {
        Map<String, Group> queueMap = new Map<String, Group>();
        for (Group g : [SELECT Id, DeveloperName, Name FROM Group WHERE Type = 'Queue']) {
            queueMap.put(g.DeveloperName, g);
        }
        return queueMap;
    }
    private static final String QUEUE_FCP_GENERAL  = 'FCP_General';
    private static final String QUEUE_FSP_GENERAL  = 'FSP_General_POD';
    private static final String QUEUE_DIGITAL      = 'FSP_Digital_POD';
    private static final String QUEUE_DEPO         = 'FSP_Deposition_POD';
    private static final String QUEUE_COURT_PROC   = 'FSP_Court_Process_POD';
    private static final String QUEUE_INVESTIGATE  = 'FSP_Investigations_POD';
    private static final String QUEUE_RECORDS      = 'FSP_Records_POD';
    private static final String QUEUE_EDISCOVERY   = 'FSP_Tech_POD';
    private static final String QUEUE_FINANCE      = 'FSP_Financial_Billing_POD';
}