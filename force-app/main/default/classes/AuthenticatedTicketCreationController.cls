/**
 * @description Invocable Action for Logged-In User Ticket (Case) Creation, Record Type Assignment, Account Linkage, and Pod Routing.
 * EXECUTED IN SYSTEM MODE (without sharing):
 * - Bypasses portal user sharing, CRUD, and Field-Level Security (FLS) restrictions.
 * - Resolves User, Contact, and Account relationships seamlessly.
 * - Accurately routes to FCP Pods (1-25) or FSP Divisional Pods via scored intent matching.
 */
public without sharing class AuthenticatedTicketCreationController {

    /**
     * @description Invocable Request Wrapper
     */
    public class TicketRequest {
        @InvocableVariable(
            label='Session User ID' 
            description='Optional. The Salesforce User ID of the logged-in customer portal user. If omitted or null, UserInfo.getUserId() is used automatically.' 
            required=false
        )
        public Id userId;
        
        @InvocableVariable(
            label='Ticket Subject / Summary' 
            description='A concise title or summary for the support ticket describing the customer inquiry.' 
            required=true
        )
        public String subject;
        
        @InvocableVariable(
            label='Ticket Description / Chat Summary' 
            description='The conversational context, inquiry details, or chat transcript summary.' 
            required=false
        )
        public String description;

        @InvocableVariable(
            label='Detected Chat Intent / Category' 
            description='The service line or category selected/detected (e.g., Court & Process, Depositions, Digital, Financial, Investigations, Records, eDiscovery, Tech).' 
            required=false
        )
        public String detectedIntent;
    }

    /**
     * @description Invocable Response Wrapper
     */
    public class TicketResponse {
        @InvocableVariable(
            label='Created Ticket ID' 
            description='The internal Salesforce record ID (Case Id) of the newly created ticket.'
        )
        public Id ticketId;
        
        @InvocableVariable(
            label='Created Ticket Number' 
            description='The customer-facing Ticket Number (CaseNumber) to present to the user.'
        )
        public String ticketNumber;
        
        @InvocableVariable(
            label='Linked Contact ID' 
            description='The ID of the Contact matched via user session and linked to the ticket.'
        )
        public Id linkedContactId;

        @InvocableVariable(
            label='Linked Account ID' 
            description='The ID of the Account linked to the matched Contact and ticket.'
        )
        public Id linkedAccountId;

        @InvocableVariable(
            label='Customer Email' 
            description='The verified email address extracted directly from the user session context.'
        )
        public String customerEmail;

        @InvocableVariable(
            label='Customer First Name' 
            description='The first name of the customer for personalized messaging.'
        )
        public String customerFirstName;

        @InvocableVariable(
            label='Assigned Record Type ID' 
            description='The Record Type ID assigned to the ticket (FCP or FSP).'
        )
        public Id recordTypeId;

        @InvocableVariable(
            label='Assigned Record Type Developer Name' 
            description='The DeveloperName of the assigned Record Type.'
        )
        public String recordTypeDevName;

        @InvocableVariable(
            label='Assigned Queue ID' 
            description='The Salesforce Group ID of the Queue assigned as the Owner of this ticket.'
        )
        public Id assignedQueueId;
        
        @InvocableVariable(
            label='Assigned Queue Developer Name' 
            description='The API DeveloperName of the assigned Queue (e.g., FCP_POD14, FSP_Deposition_POD, FSP_General_POD).'
        )
        public String assignedQueueName;

        @InvocableVariable(
            label='Status Message' 
            description='A human-readable execution summary message detailing ticket creation, account linkage, and queue assignment.'
        )
        public String statusMessage;
    }

    @InvocableMethod(
        label='Create and Assign Authenticated Ticket' 
        description='Extracts session user context, links Contact & Account, assigns Record Type, evaluates FCP/FSP Pod routing, creates the Ticket, and sets Owner to Queue in System Mode.'
    )
    public static List<TicketResponse> createTicket(List<TicketRequest> requests) {
        List<TicketResponse> responses = new List<TicketResponse>();

        // 1. Fetch Case Record Types dynamically (No SOQL consumed)
        Map<String, Schema.RecordTypeInfo> rtByName = Schema.SObjectType.Case.getRecordTypeInfosByName();
        Map<String, Schema.RecordTypeInfo> rtByDevName = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName();

        Id fcpRecordTypeId = null;
        String fcpRecordTypeDevName = 'First_Class_Program';
        if (rtByName.containsKey('First Class Program')) {
            fcpRecordTypeId = rtByName.get('First Class Program').getRecordTypeId();
            fcpRecordTypeDevName = rtByName.get('First Class Program').getDeveloperName();
        } else if (rtByDevName.containsKey('First_Class_Program')) {
            fcpRecordTypeId = rtByDevName.get('First_Class_Program').getRecordTypeId();
            fcpRecordTypeDevName = 'First_Class_Program';
        } else if (rtByDevName.containsKey('FCP')) {
            fcpRecordTypeId = rtByDevName.get('FCP').getRecordTypeId();
            fcpRecordTypeDevName = 'FCP';
        }

        Id fspRecordTypeId = null;
        String fspRecordTypeDevName = 'First_Service_Program';
        if (rtByName.containsKey('First Service Program')) {
            fspRecordTypeId = rtByName.get('First Service Program').getRecordTypeId();
            fspRecordTypeDevName = rtByName.get('First Service Program').getDeveloperName();
        } else if (rtByDevName.containsKey('First_Service_Program')) {
            fspRecordTypeId = rtByDevName.get('First_Service_Program').getRecordTypeId();
            fspRecordTypeDevName = 'First_Service_Program';
        } else if (rtByDevName.containsKey('FSP')) {
            fspRecordTypeId = rtByDevName.get('FSP').getRecordTypeId();
            fspRecordTypeDevName = 'FSP';
        }

        // 2. Build Case-Insensitive Cache of all active Queues in System Context
        Map<String, Group> queueMap = new Map<String, Group>();
        for (Group q : [SELECT Id, DeveloperName, Name FROM Group WHERE Type = 'Queue']) {
            queueMap.put(q.DeveloperName.toLowerCase(), q);
        }

        List<Case> ticketsToInsert = new List<Case>();
        List<TicketResponse> tempResponses = new List<TicketResponse>();

        for (TicketRequest req : requests) {
            TicketResponse res = new TicketResponse();
            Id currentUserId = req.userId != null ? req.userId : UserInfo.getUserId();

            // 3. Extract User Context & Portal Links from Session
            String userEmail = UserInfo.getUserEmail();
            String userFirstName = UserInfo.getFirstName();
            Id matchedContactId = null;
            Id matchedAccountId = null;
            Boolean isFcpCustomer = false;
            String assignedPodValue = null;

            List<User> userRecords = [
                SELECT Id, FirstName, LastName, Email, ContactId, AccountId
                FROM User 
                WHERE Id = :currentUserId 
                LIMIT 1
            ];

            if (!userRecords.isEmpty()) {
                User u = userRecords[0];
                userEmail = u.Email;
                userFirstName = u.FirstName;
                if (u.ContactId != null) {
                    matchedContactId = u.ContactId;
                }
                if (u.AccountId != null) {
                    matchedAccountId = u.AccountId;
                }
            }

            // 4. Query / Verify Contact and Account (FCP & Pod Fields)
            if (matchedContactId != null) {
                List<Contact> directContacts = [
                    SELECT Id, FirstName, LastName, Email, AccountId,
                           Account.is_fcp_customer__c, Account.assigned_pod__c
                    FROM Contact 
                    WHERE Id = :matchedContactId 
                    LIMIT 1
                ];
                if (!directContacts.isEmpty()) {
                    Contact c = directContacts[0];
                    if (matchedAccountId == null) {
                        matchedAccountId = c.AccountId;
                    }
                    if (c.Account != null && c.Account.is_fcp_customer__c == true) {
                        isFcpCustomer = true;
                        assignedPodValue = c.Account.assigned_pod__c;
                    }
                }
            } else if (String.isNotBlank(userEmail)) {
                List<Contact> matchedContacts = [
                    SELECT Id, FirstName, LastName, Email, AccountId,
                           Account.is_fcp_customer__c, Account.assigned_pod__c
                    FROM Contact 
                    WHERE Email = :userEmail 
                    ORDER BY LastModifiedDate DESC 
                    LIMIT 1
                ];

                if (!matchedContacts.isEmpty()) {
                    Contact c = matchedContacts[0];
                    matchedContactId = c.Id;
                    matchedAccountId = c.AccountId;
                    if (String.isNotBlank(c.FirstName)) {
                        userFirstName = c.FirstName;
                    }
                    if (c.Account != null && c.Account.is_fcp_customer__c == true) {
                        isFcpCustomer = true;
                        assignedPodValue = c.Account.assigned_pod__c;
                    }
                }
            }

            res.customerEmail = userEmail;
            res.customerFirstName = userFirstName;
            res.linkedContactId = matchedContactId;
            res.linkedAccountId = matchedAccountId;

            // 5. Assign Record Type and Resolve Pod-Based Queue
            Id targetQueueId = null;
            String targetQueueDevName = '';

            // -------------------------------------------------------------------------
            // TRACK 1: FCP Customer (Account.is_fcp_customer__c == true)
            // -------------------------------------------------------------------------
            if (isFcpCustomer) {
                res.recordTypeId = fcpRecordTypeId;
                res.recordTypeDevName = fcpRecordTypeDevName;

                if (String.isNotBlank(assignedPodValue)) {
                    targetQueueId = resolveFcpPodQueueId(assignedPodValue, queueMap, res);
                } else {
                    targetQueueId = getFallbackFcpQueueId(queueMap, res);
                }
            } 
            // -------------------------------------------------------------------------
            // TRACK 2: FSP Customer (Intelligent Multi-Pod Scored Routing)
            // -------------------------------------------------------------------------
            else {
                res.recordTypeId = fspRecordTypeId;
                res.recordTypeDevName = fspRecordTypeDevName;

                targetQueueDevName = resolveFspDivisionalQueueName(req.detectedIntent, req.subject, req.description);

                if (queueMap.containsKey(targetQueueDevName.toLowerCase())) {
                    Group g = queueMap.get(targetQueueDevName.toLowerCase());
                    targetQueueId = g.Id;
                    res.assignedQueueName = g.DeveloperName;
                } else {
                    res.assignedQueueName = targetQueueDevName;
                }
            }

            // 6. Build and Link Case (Ticket)
            Case ticket = new Case();
            ticket.Origin = 'Chat';
            ticket.Subject = String.isNotBlank(req.subject) ? req.subject : 'Support Request from Logged-in Customer';
            ticket.Description = req.description;
            ticket.SuppliedEmail = userEmail;
            
            // Link Contact and Account
            ticket.ContactId = matchedContactId;
            ticket.AccountId = matchedAccountId;
            
            // Assign Record Type
            if (res.recordTypeId != null) {
                ticket.RecordTypeId = res.recordTypeId;
            }
            
            // Assign Owner to Queue
            if (targetQueueId != null) {
                ticket.OwnerId = targetQueueId;
            }

            ticketsToInsert.add(ticket);
            res.assignedQueueId = targetQueueId;
            tempResponses.add(res);
        }

        // 7. Insert Tickets in System Mode with DMLOptions
        if (!ticketsToInsert.isEmpty()) {
            Database.DMLOptions dmlOptions = new Database.DMLOptions();
            dmlOptions.OptAllOrNone = true;
            Database.insert(ticketsToInsert, dmlOptions);
        }

        // 8. Query Auto-Generated Case Numbers & Finalize Response
        Set<Id> ticketIds = new Set<Id>();
        for (Case t : ticketsToInsert) {
            ticketIds.add(t.Id);
        }
        Map<Id, Case> insertedTicketMap = new Map<Id, Case>([SELECT Id, CaseNumber FROM Case WHERE Id IN :ticketIds]);

        for (Integer i = 0; i < ticketsToInsert.size(); i++) {
            TicketResponse res = tempResponses[i];
            Case insertedCase = ticketsToInsert[i];
            res.ticketId = insertedCase.Id;
            res.ticketNumber = insertedTicketMap.get(insertedCase.Id).CaseNumber;
            res.statusMessage = 'Ticket #' + res.ticketNumber + ' successfully created (' + res.recordTypeDevName + 
                                ') with linked Account ID: ' + res.linkedAccountId + ' and assigned to ' + res.assignedQueueName;
            responses.add(res);
        }

        return responses;
    }

    /**
     * @description High-precision FSP Divisional Pod Resolver.
     * 1. Evaluates explicit detected intent first.
     * 2. Evaluates specific multi-word domain phrases.
     * 3. Calculates scored keyword matches to prevent generic words from hijacking other pods.
     */
    private static String resolveFspDivisionalQueueName(String detectedIntent, String subject, String description) {
        // Step 1: Direct Category / Intent Match if available from Bot
        if (String.isNotBlank(detectedIntent)) {
            String intentLower = detectedIntent.toLowerCase().trim();
            if (intentLower.contains('depo') || intentLower.contains('transcript') || intentLower.contains('court reporter')) {
                return 'FSP_Deposition_POD';
            } else if (intentLower.contains('record') || intentLower.contains('subpoena record') || intentLower.contains('custodian')) {
                return 'FSP_Records_POD';
            } else if (intentLower.contains('bill') || intentLower.contains('invoice') || intentLower.contains('payment') || intentLower.contains('account')) {
                return 'FSP_Financial_Billing_POD';
            } else if (intentLower.contains('investigat') || intentLower.contains('surveillance') || intentLower.contains('skip trace')) {
                return 'FSP_Investigations_POD';
            } else if (intentLower.contains('ediscovery') || intentLower.contains('litigation support') || intentLower.contains('data process')) {
                return 'FSP_eDiscovery_POD';
            } else if (intentLower.contains('tech') || intentLower.contains('portal') || intentLower.contains('login') || intentLower.contains('password')) {
                return 'FSP_Tech_POD';
            } else if (intentLower.contains('scan') || intentLower.contains('copy') || intentLower.contains('print') || intentLower.contains('binder') || intentLower.contains('digital')) {
                return 'FSP_Digital_POD';
            } else if (intentLower.contains('court') || intentLower.contains('process') || intentLower.contains('efil') || intentLower.contains('courier')) {
                return 'FSP_Court_Process_POD';
            }
        }

        // Step 2: Combine Text with subject given higher weight
        String combinedText = ((subject != null ? subject : '') + ' ' + (subject != null ? subject : '') + ' ' + 
                               (description != null ? description : '')).toLowerCase();

        // Pod Score Tally
        Map<String, Integer> podScores = new Map<String, Integer>{
            'FSP_Deposition_POD'        => 0,
            'FSP_Records_POD'           => 0,
            'FSP_Financial_Billing_POD' => 0,
            'FSP_Investigations_POD'    => 0,
            'FSP_eDiscovery_POD'        => 0,
            'FSP_Tech_POD'              => 0,
            'FSP_Digital_POD'           => 0,
            'FSP_Court_Process_POD'     => 0
        };

        // 1. Deposition Pod Keywords
        if (combinedText.contains('court reporter') || combinedText.contains('court reporting')) podScores.put('FSP_Deposition_POD', podScores.get('FSP_Deposition_POD') + 15);
        if (combinedText.contains('deposition') || combinedText.contains('depo')) podScores.put('FSP_Deposition_POD', podScores.get('FSP_Deposition_POD') + 10);
        if (combinedText.contains('transcript') || combinedText.contains('videography') || combinedText.contains('videographer')) podScores.put('FSP_Deposition_POD', podScores.get('FSP_Deposition_POD') + 8);

        // 2. Records Pod Keywords (High priority compound matches)
        if (combinedText.contains('court record') || combinedText.contains('court records')) podScores.put('FSP_Records_POD', podScores.get('FSP_Records_POD') + 15);
        if (combinedText.contains('medical record') || combinedText.contains('records retrieval') || combinedText.contains('subpoena record')) podScores.put('FSP_Records_POD', podScores.get('FSP_Records_POD') + 12);
        if (combinedText.contains('custodian of records') || combinedText.contains('record request') || combinedText.contains('record retrieval')) podScores.put('FSP_Records_POD', podScores.get('FSP_Records_POD') + 10);
        if (combinedText.contains('records') || combinedText.contains('record')) podScores.put('FSP_Records_POD', podScores.get('FSP_Records_POD') + 3);

        // 3. Financial & Billing Pod Keywords
        if (combinedText.contains('invoice') || combinedText.contains('billing') || combinedText.contains('credit card') || combinedText.contains('refund')) podScores.put('FSP_Financial_Billing_POD', podScores.get('FSP_Financial_Billing_POD') + 10);
        if (combinedText.contains('payment') || combinedText.contains('accounting') || combinedText.contains('statement') || combinedText.contains('charge')) podScores.put('FSP_Financial_Billing_POD', podScores.get('FSP_Financial_Billing_POD') + 8);

        // 4. Investigations Pod Keywords
        if (combinedText.contains('private investigator') || combinedText.contains('skip trace') || combinedText.contains('surveillance') || combinedText.contains('background check')) podScores.put('FSP_Investigations_POD', podScores.get('FSP_Investigations_POD') + 12);
        if (combinedText.contains('investigation') || combinedText.contains('locate person') || combinedText.contains('asset search')) podScores.put('FSP_Investigations_POD', podScores.get('FSP_Investigations_POD') + 10);

        // 5. eDiscovery Pod Keywords
        if (combinedText.contains('ediscovery') || combinedText.contains('e-discovery') || combinedText.contains('document review') || combinedText.contains('relativity') || combinedText.contains('pts')) podScores.put('FSP_eDiscovery_POD', podScores.get('FSP_eDiscovery_POD') + 12);
        if (combinedText.contains('litigation support') || combinedText.contains('data processing') || combinedText.contains('load file')) podScores.put('FSP_eDiscovery_POD', podScores.get('FSP_eDiscovery_POD') + 10);

        // 6. Tech Pod Keywords
        if (combinedText.contains('login') || combinedText.contains('password') || combinedText.contains('reset password') || combinedText.contains('cannot log') || combinedText.contains('portal access')) podScores.put('FSP_Tech_POD', podScores.get('FSP_Tech_POD') + 10);
        if (combinedText.contains('portal error') || combinedText.contains('bug') || combinedText.contains('page not loading') || combinedText.contains('tech support') || combinedText.contains('system outage')) podScores.put('FSP_Tech_POD', podScores.get('FSP_Tech_POD') + 8);

        // 7. Digital Pod Keywords
        if (combinedText.contains('trial binder') || combinedText.contains('blowup') || combinedText.contains('foam board') || combinedText.contains('exhibit tab') || combinedText.contains('scanning and copying')) podScores.put('FSP_Digital_POD', podScores.get('FSP_Digital_POD') + 10);
        if (combinedText.contains('printing') || combinedText.contains('binding') || combinedText.contains('color copy') || combinedText.contains('oversized print')) podScores.put('FSP_Digital_POD', podScores.get('FSP_Digital_POD') + 8);

        // 8. Court & Process Pod Keywords (SPECIFIC legal terms, NOT generic 'process' or standalone 'court')
        if (combinedText.contains('service of process') || combinedText.contains('process server') || combinedText.contains('process service') || combinedText.contains('serve papers') || combinedText.contains('subpoena service')) podScores.put('FSP_Court_Process_POD', podScores.get('FSP_Court_Process_POD') + 15);
        if (combinedText.contains('efiling') || combinedText.contains('e-filing') || combinedText.contains('court filing') || combinedText.contains('file with the court') || combinedText.contains('conformed copy') || combinedText.contains('subpoena delivery')) podScores.put('FSP_Court_Process_POD', podScores.get('FSP_Court_Process_POD') + 12);
        if (combinedText.contains('courier') || combinedText.contains('messenger') || combinedText.contains('court run') || combinedText.contains('serve defendant')) podScores.put('FSP_Court_Process_POD', podScores.get('FSP_Court_Process_POD') + 10);

        // Step 3: Find highest scoring pod
        String bestQueue = 'FSP_General_POD';
        Integer maxScore = 0;

        for (String queueDevName : podScores.keySet()) {
            Integer score = podScores.get(queueDevName);
            if (score > maxScore) {
                maxScore = score;
                bestQueue = queueDevName;
            }
        }

        // If score is 0 or unassigned, return FSP_General_POD
        return maxScore > 0 ? bestQueue : 'FSP_General_POD';
    }

    /**
     * @description Dynamic resolver for FCP Pod Queues (matches FCP POD1 through FCP POD25)
     */
    private static Id resolveFcpPodQueueId(String assignedPodValue, Map<String, Group> queueMap, TicketResponse res) {
        if (String.isBlank(assignedPodValue)) {
            return getFallbackFcpQueueId(queueMap, res);
        }

        String numericOnly = assignedPodValue.replaceAll('[^0-9]', '');
        String sanitized = assignedPodValue.replaceAll('[^a-zA-Z0-9_]', '_').toLowerCase();

        List<String> candidates = new List<String>{
            'fcp_pod' + numericOnly,   // Matches FCP_POD1, FCP_POD14, etc.
            'fcp_pod_' + numericOnly,  // Matches FCP_POD_14
            sanitized,                  // Matches direct sanitized value
            'fcp_' + sanitized          // Matches fcp_<pod>
        };

        for (String candidate : candidates) {
            if (queueMap.containsKey(candidate)) {
                Group g = queueMap.get(candidate);
                res.assignedQueueName = g.DeveloperName;
                return g.Id;
            }
        }

        return getFallbackFcpQueueId(queueMap, res);
    }

    /**
     * @description Fallback for FCP General Queue (per EC1 & EC6)
     */
    private static Id getFallbackFcpQueueId(Map<String, Group> queueMap, TicketResponse res) {
        List<String> fcpFallbackCandidates = new List<String>{
            'fcp_general_pod',
            'fcp_general_queue',
            'fcp_general',
            'first_class_queue'
        };

        for (String fallbackKey : fcpFallbackCandidates) {
            if (queueMap.containsKey(fallbackKey)) {
                Group g = queueMap.get(fallbackKey);
                res.assignedQueueName = g.DeveloperName;
                return g.Id;
            }
        }

        res.assignedQueueName = 'FCP_General_Queue';
        return null;
    }
}