/**
 * @description Invocable Action for Guest User Ticket (Case) Creation (NOVA-3813).
 * Captures pre-chat values (Name, Email, Company, Location, Intent), resolves Contact & Account,
 * handles FCP / FSP Record Type assignment & Pod Queue routing, and returns the generated Ticket Number.
 * EXECUTED IN SYSTEM MODE (without sharing).
 */
public without sharing class GuestTicketCreationController {

    private static final Pattern EMAIL_PATTERN = 
        Pattern.compile('^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$');
        
    private static final Set<String> PUBLIC_DOMAINS = new Set<String>{
        'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 'icloud.com', 'aol.com'
    };

    /**
     * @description Invocable Request Wrapper for Guest Pre-Chat Data
     */
    public class TicketRequest {
        @InvocableVariable(label='First Name' description='Customer First Name' required=false)
        public String firstName;

        @InvocableVariable(label='Last Name' description='Customer Last Name' required=false)
        public String lastName;

        @InvocableVariable(label='Email' description='Customer Email Address' required=false)
        public String email;

        @InvocableVariable(label='Company Name' description='Customer Company / Firm Name' required=false)
        public String companyName;

        @InvocableVariable(label='Firm Location' description='Firm Location or Branch City' required=false)
        public String firmLocation;

        @InvocableVariable(label='Ticket Subject' description='Summary of the support inquiry' required=true)
        public String subject;

        @InvocableVariable(label='Ticket Description' description='Details / context of the inquiry' required=false)
        public String description;

        @InvocableVariable(label='Detected Intent / Category' description='Service line or category detected by bot' required=false)
        public String detectedIntent;
    }

    /**
     * @description Invocable Response Wrapper
     */
    public class TicketResponse {
        @InvocableVariable(label='Created Ticket Number' description='Customer-facing Ticket Number (CaseNumber)')
        public String ticketNumber;
    }

    @InvocableMethod(
        label='Create Guest Ticket'
        description='Creates a support ticket for guest users from pre-chat data, resolves Account/Contact, assigns Record Type & Pod Queue, and returns the Ticket Number.'
        category='Agentforce'
    )
    public static List<TicketResponse> createGuestTicket(List<TicketRequest> requests) {
        List<TicketResponse> responses = new List<TicketResponse>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        // 1. Fetch Case Record Types dynamically (No SOQL consumed)
        Map<String, Schema.RecordTypeInfo> rtByName = Schema.SObjectType.Case.getRecordTypeInfosByName();
        Map<String, Schema.RecordTypeInfo> rtByDevName = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName();

        Id fcpRecordTypeId = null;
        if (rtByName.containsKey('First Class Program')) {
            fcpRecordTypeId = rtByName.get('First Class Program').getRecordTypeId();
        } else if (rtByDevName.containsKey('First_Class_Program')) {
            fcpRecordTypeId = rtByDevName.get('First_Class_Program').getRecordTypeId();
        } else if (rtByDevName.containsKey('FCP')) {
            fcpRecordTypeId = rtByDevName.get('FCP').getRecordTypeId();
        }

        Id fspRecordTypeId = null;
        if (rtByName.containsKey('First Service Program')) {
            fspRecordTypeId = rtByName.get('First Service Program').getRecordTypeId();
        } else if (rtByDevName.containsKey('First_Service_Program')) {
            fspRecordTypeId = rtByDevName.get('First_Service_Program').getRecordTypeId();
        } else if (rtByDevName.containsKey('FSP')) {
            fspRecordTypeId = rtByDevName.get('FSP').getRecordTypeId();
        }

        // 2. Build Case-Insensitive Cache of all active Queues
        Map<String, Group> queueMap = new Map<String, Group>();
        for (Group q : [SELECT Id, DeveloperName, Name FROM Group WHERE Type = 'Queue' WITH SYSTEM_MODE]) {
            queueMap.put(q.DeveloperName.toLowerCase(), q);
        }

        List<Case> ticketsToInsert = new List<Case>();
        List<TicketResponse> tempResponses = new List<TicketResponse>();

        for (TicketRequest req : requests) {
            TicketResponse res = new TicketResponse();

            String firstName = String.isNotBlank(req.firstName) ? req.firstName.trim() : '';
            String lastName = String.isNotBlank(req.lastName) ? req.lastName.trim() : 'Guest User';
            String email = String.isNotBlank(req.email) ? req.email.trim() : '';
            String companyName = String.isNotBlank(req.companyName) ? req.companyName.trim() : '';
            String firmLocation = String.isNotBlank(req.firmLocation) ? req.firmLocation.trim() : '';
            String subject = String.isNotBlank(req.subject) ? req.subject.trim() : 'Support Request from Guest User';
            String description = String.isNotBlank(req.description) ? req.description.trim() : subject;

            Boolean emailValid = String.isNotBlank(email) && EMAIL_PATTERN.matcher(email).matches();

            Id matchedContactId = null;
            Id matchedAccountId = null;
            Boolean isFcpCustomer = false;
            String assignedPodValue = null;

            // 3. Match Contact by Email & Check Account FCP/Pod fields
            if (emailValid) {
                List<Contact> matchedContacts = [
                    SELECT Id, FirstName, LastName, Email, AccountId,
                           Account.Is_FCP_Customer__c, Account.Assigned_POD__c
                    FROM Contact 
                    WHERE Email = :email 
                    WITH SYSTEM_MODE 
                    ORDER BY LastModifiedDate DESC 
                    LIMIT 2
                ];

                if (matchedContacts.size() == 1) {
                    Contact c = matchedContacts[0];
                    matchedContactId = c.Id;
                    matchedAccountId = c.AccountId;
                    if (c.Account != null && c.Account.is_fcp_customer__c == true) {
                        isFcpCustomer = true;
                        assignedPodValue = c.Account.assigned_pod__c;
                    }
                }
            }

            // 4. Match Account if not resolved via Contact
            if (matchedAccountId == null && String.isNotBlank(companyName)) {
                List<Account> candidates = [
                    SELECT Id, Name, BillingCity, BillingState, ShippingCity, ShippingState,
                           is_fcp_customer__c, assigned_pod__c
                    FROM Account 
                    WHERE Name = :companyName 
                    WITH SYSTEM_MODE 
                    ORDER BY LastModifiedDate DESC 
                    LIMIT 20
                ];

                if (candidates.isEmpty()) {
                    String searchPattern = '%' + likeEscape(companyName) + '%';
                    candidates = [
                        SELECT Id, Name, BillingCity, BillingState, ShippingCity, ShippingState,
                               is_fcp_customer__c, assigned_pod__c
                        FROM Account 
                        WHERE Name LIKE :searchPattern 
                        WITH SYSTEM_MODE 
                        ORDER BY LastModifiedDate DESC 
                        LIMIT 20
                    ];
                }

                if (candidates.size() > 1 && String.isNotBlank(firmLocation)) {
                    List<Account> narrowed = new List<Account>();
                    for (Account a : candidates) {
                        if (matchesLocation(a, firmLocation)) {
                            narrowed.add(a);
                        }
                    }
                    if (!narrowed.isEmpty()) {
                        candidates = narrowed;
                    }
                }

                if (candidates.size() == 1) {
                    matchedAccountId = candidates[0].Id;
                    if (candidates[0].is_fcp_customer__c == true) {
                        isFcpCustomer = true;
                        assignedPodValue = candidates[0].assigned_pod__c;
                    }
                }
            }

            // 5. Fallback: Match Account via Email Domain
            if (matchedAccountId == null && emailValid) {
                String domain = email.substringAfter('@').toLowerCase();
                if (!PUBLIC_DOMAINS.contains(domain)) {
                    String domainPattern = '%' + likeEscape(domain) + '%';
                    List<Account> domainAccounts = [
                        SELECT Id, is_fcp_customer__c, assigned_pod__c 
                        FROM Account 
                        WHERE Website LIKE :domainPattern 
                        WITH SYSTEM_MODE 
                        ORDER BY LastModifiedDate DESC 
                        LIMIT 2
                    ];
                    if (domainAccounts.size() == 1) {
                        matchedAccountId = domainAccounts[0].Id;
                        if (domainAccounts[0].is_fcp_customer__c == true) {
                            isFcpCustomer = true;
                            assignedPodValue = domainAccounts[0].assigned_pod__c;
                        }
                    }
                }
            }

            // 6. Assign Record Type and Resolve Pod-Based Queue
            Id targetRecordTypeId = null;
            Id targetQueueId = null;

            if (isFcpCustomer) {
                targetRecordTypeId = fcpRecordTypeId;
                if (String.isNotBlank(assignedPodValue)) {
                    targetQueueId = resolveFcpPodQueueId(assignedPodValue, queueMap);
                } else {
                    targetQueueId = getFallbackFcpQueueId(queueMap);
                }
            } else {
                targetRecordTypeId = fspRecordTypeId;
                String targetQueueDevName = resolveFspDivisionalQueueName(req.detectedIntent, subject, description);
                if (queueMap.containsKey(targetQueueDevName.toLowerCase())) {
                    targetQueueId = queueMap.get(targetQueueDevName.toLowerCase()).Id;
                }
            }

            // 7. Instantiate Ticket (Case)
            Case ticket = new Case();
            ticket.Origin = 'Chat';
            ticket.Status = 'New';
            ticket.Subject = subject.abbreviate(255);
            ticket.Description = description.abbreviate(32000);
            ticket.SuppliedName = ((String.isNotBlank(firstName) ? firstName + ' ' : '') + lastName).abbreviate(80);
            ticket.SuppliedEmail = emailValid ? email.abbreviate(80) : null;
            ticket.SuppliedCompany = String.isNotBlank(companyName) ? companyName.abbreviate(40) : null;

            ticket.ContactId = matchedContactId;
            ticket.AccountId = matchedAccountId;

            if (targetRecordTypeId != null) {
                ticket.RecordTypeId = targetRecordTypeId;
            }
            if (targetQueueId != null) {
                ticket.OwnerId = targetQueueId;
            }

            ticketsToInsert.add(ticket);
            tempResponses.add(res);
        }

        // 8. Insert in System Mode
        if (!ticketsToInsert.isEmpty()) {
            Database.DMLOptions dmlOptions = new Database.DMLOptions();
            dmlOptions.OptAllOrNone = true;
            Database.insert(ticketsToInsert, dmlOptions);
        }

        // 9. Query Case Numbers & Return
        Set<Id> ticketIds = new Set<Id>();
        for (Case t : ticketsToInsert) {
            ticketIds.add(t.Id);
        }
        Map<Id, Case> insertedTicketMap = new Map<Id, Case>([
            SELECT Id, CaseNumber 
            FROM Case 
            WHERE Id IN :ticketIds 
            WITH SYSTEM_MODE
        ]);

        for (Integer i = 0; i < ticketsToInsert.size(); i++) {
            TicketResponse res = tempResponses[i];
            Case insertedCase = ticketsToInsert[i];
            res.ticketNumber = insertedTicketMap.get(insertedCase.Id).CaseNumber;
            responses.add(res);
        }

        return responses;
    }

    // =========================================================================
    // POD & QUEUE RESOLUTION HELPERS
    // =========================================================================

    /**
     * @description High-precision FSP Divisional Pod Resolver using scored intent matching
     */
    private static String resolveFspDivisionalQueueName(String detectedIntent, String subject, String description) {
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

        String combinedText = ((subject != null ? subject : '') + ' ' + (subject != null ? subject : '') + ' ' + 
                               (description != null ? description : '')).toLowerCase();

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

        // 1. Deposition Pod
        if (combinedText.contains('court reporter') || combinedText.contains('court reporting')) podScores.put('FSP_Deposition_POD', podScores.get('FSP_Deposition_POD') + 15);
        if (combinedText.contains('deposition') || combinedText.contains('depo')) podScores.put('FSP_Deposition_POD', podScores.get('FSP_Deposition_POD') + 10);
        if (combinedText.contains('transcript') || combinedText.contains('videography') || combinedText.contains('videographer')) podScores.put('FSP_Deposition_POD', podScores.get('FSP_Deposition_POD') + 8);

        // 2. Records Pod
        if (combinedText.contains('court record') || combinedText.contains('court records')) podScores.put('FSP_Records_POD', podScores.get('FSP_Records_POD') + 15);
        if (combinedText.contains('medical record') || combinedText.contains('records retrieval') || combinedText.contains('subpoena record')) podScores.put('FSP_Records_POD', podScores.get('FSP_Records_POD') + 12);
        if (combinedText.contains('custodian of records') || combinedText.contains('record request') || combinedText.contains('record retrieval')) podScores.put('FSP_Records_POD', podScores.get('FSP_Records_POD') + 10);
        if (combinedText.contains('records') || combinedText.contains('record')) podScores.put('FSP_Records_POD', podScores.get('FSP_Records_POD') + 3);

        // 3. Financial & Billing Pod
        if (combinedText.contains('invoice') || combinedText.contains('billing') || combinedText.contains('credit card') || combinedText.contains('refund')) podScores.put('FSP_Financial_Billing_POD', podScores.get('FSP_Financial_Billing_POD') + 10);
        if (combinedText.contains('payment') || combinedText.contains('accounting') || combinedText.contains('statement') || combinedText.contains('charge')) podScores.put('FSP_Financial_Billing_POD', podScores.get('FSP_Financial_Billing_POD') + 8);

        // 4. Investigations Pod
        if (combinedText.contains('private investigator') || combinedText.contains('skip trace') || combinedText.contains('surveillance') || combinedText.contains('background check')) podScores.put('FSP_Investigations_POD', podScores.get('FSP_Investigations_POD') + 12);
        if (combinedText.contains('investigation') || combinedText.contains('locate person') || combinedText.contains('asset search')) podScores.put('FSP_Investigations_POD', podScores.get('FSP_Investigations_POD') + 10);

        // 5. eDiscovery Pod
        if (combinedText.contains('ediscovery') || combinedText.contains('e-discovery') || combinedText.contains('document review') || combinedText.contains('relativity') || combinedText.contains('pts')) podScores.put('FSP_eDiscovery_POD', podScores.get('FSP_eDiscovery_POD') + 12);
        if (combinedText.contains('litigation support') || combinedText.contains('data processing') || combinedText.contains('load file')) podScores.put('FSP_eDiscovery_POD', podScores.get('FSP_eDiscovery_POD') + 10);

        // 6. Tech Pod
        if (combinedText.contains('login') || combinedText.contains('password') || combinedText.contains('reset password') || combinedText.contains('cannot log') || combinedText.contains('portal access')) podScores.put('FSP_Tech_POD', podScores.get('FSP_Tech_POD') + 10);
        if (combinedText.contains('portal error') || combinedText.contains('bug') || combinedText.contains('page not loading') || combinedText.contains('tech support') || combinedText.contains('system outage')) podScores.put('FSP_Tech_POD', podScores.get('FSP_Tech_POD') + 8);

        // 7. Digital Pod
        if (combinedText.contains('trial binder') || combinedText.contains('blowup') || combinedText.contains('foam board') || combinedText.contains('exhibit tab') || combinedText.contains('scanning and copying')) podScores.put('FSP_Digital_POD', podScores.get('FSP_Digital_POD') + 10);
        if (combinedText.contains('printing') || combinedText.contains('binding') || combinedText.contains('color copy') || combinedText.contains('oversized print')) podScores.put('FSP_Digital_POD', podScores.get('FSP_Digital_POD') + 8);

        // 8. Court & Process Pod
        if (combinedText.contains('service of process') || combinedText.contains('process server') || combinedText.contains('process service') || combinedText.contains('serve papers') || combinedText.contains('subpoena service')) podScores.put('FSP_Court_Process_POD', podScores.get('FSP_Court_Process_POD') + 15);
        if (combinedText.contains('efiling') || combinedText.contains('e-filing') || combinedText.contains('court filing') || combinedText.contains('file with the court') || combinedText.contains('conformed copy') || combinedText.contains('subpoena delivery')) podScores.put('FSP_Court_Process_POD', podScores.get('FSP_Court_Process_POD') + 12);
        if (combinedText.contains('courier') || combinedText.contains('messenger') || combinedText.contains('court run') || combinedText.contains('serve defendant')) podScores.put('FSP_Court_Process_POD', podScores.get('FSP_Court_Process_POD') + 10);

        String bestQueue = 'FSP_General_POD';
        Integer maxScore = 0;
        for (String queueDevName : podScores.keySet()) {
            Integer score = podScores.get(queueDevName);
            if (score > maxScore) {
                maxScore = score;
                bestQueue = queueDevName;
            }
        }

        return maxScore > 0 ? bestQueue : 'FSP_General_POD';
    }

    /**
     * @description Dynamic resolver for FCP Pod Queues (FCP POD1 - FCP POD25)
     */
    private static Id resolveFcpPodQueueId(String assignedPodValue, Map<String, Group> queueMap) {
        if (String.isBlank(assignedPodValue)) {
            return getFallbackFcpQueueId(queueMap);
        }

        String numericOnly = assignedPodValue.replaceAll('[^0-9]', '');
        String sanitized = assignedPodValue.replaceAll('[^a-zA-Z0-9_]', '_').toLowerCase();

        List<String> candidates = new List<String>{
            'fcp_pod' + numericOnly,
            'fcp_pod_' + numericOnly,
            sanitized,
            'fcp_' + sanitized
        };

        for (String candidate : candidates) {
            if (queueMap.containsKey(candidate)) {
                return queueMap.get(candidate).Id;
            }
        }

        return getFallbackFcpQueueId(queueMap);
    }

    /**
     * @description Fallback queue for FCP
     */
    private static Id getFallbackFcpQueueId(Map<String, Group> queueMap) {
        List<String> fcpFallbackCandidates = new List<String>{
            'fcp_general_pod',
            'fcp_general_queue',
            'fcp_general',
            'first_class_queue'
        };

        for (String fallbackKey : fcpFallbackCandidates) {
            if (queueMap.containsKey(fallbackKey)) {
                return queueMap.get(fallbackKey).Id;
            }
        }
        return null;
    }

    private static Boolean matchesLocation(Account a, String location) {
        String haystack = (String.valueOf(a.BillingCity) + ' ' + 
                           String.valueOf(a.BillingState) + ' ' + 
                           String.valueOf(a.ShippingCity) + ' ' + 
                           String.valueOf(a.ShippingState)).toLowerCase();
                           
        for (String token : location.toLowerCase().split('[,\\s]+')) {
            if (token.length() >= 2 && haystack.contains(token)) {
                return true;
            }
        }
        return false;
    }

    private static String likeEscape(String s) {
        return s.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }
}