public without sharing class AccountTeamApprovalHandler {

    private static final String BASE_URL = URL.getOrgDomainUrl().toExternalForm();

    private static final Map<String, String> STATE_NAME_TO_CODE = new Map<String, String>{
        'CALIFORNIA' => 'CA',
        'ARIZONA'    => 'AZ',
        'NEVADA'     => 'NV'
    };

    public static void handleBeforeInsert(List<Account_Team_Approval__c> newList) {
        populateTerritoryFromState(newList);
    }

    public static void handleBeforeUpdate(List<Account_Team_Approval__c> newList, Map<Id, Account_Team_Approval__c> oldMap) {
        // Step 1: Populate Territory if State changes or is updated
        populateTerritoryFromState(newList);

        // Step 2: Date tracking & status updates
        for (Account_Team_Approval__c req : newList) {
            Account_Team_Approval__c oldReq = oldMap.get(req.Id);

            // Step 1 Approved -> In Review
            if (req.Status__c == 'In Review' && oldReq.Status__c != 'In Review') {
                req.Reporting_Manager_Approved__c = true;
                req.Reporting_Manager_Decision_Date__c = Date.today();
            }

            // Step 2 Approved -> Approved
            if (req.Status__c == 'Approved' && oldReq.Status__c != 'Approved') {
                req.Sales_Operations_Approved__c = true;
                req.Sales_Operation_Decision_Date__c = Date.today();
            }

            // Denied Step Timestamps
            if (req.Status__c == 'Denied' && oldReq.Status__c != 'Denied') {
                if (oldReq.Status__c == 'New') {
                    req.Reporting_Manager_Decision_Date__c = Date.today();
                } else if (oldReq.Status__c == 'In Review') {
                    req.Sales_Operation_Decision_Date__c = Date.today();
                }
            }
        }
    }

    public static void handleAfterInsert(List<Account_Team_Approval__c> newList) {
        Set<Id> userIds = new Set<Id>();
        for (Account_Team_Approval__c req : newList) {
            if (req.Requester__c != null) userIds.add(req.Requester__c);
            if (req.Reporting_Manager__c != null) userIds.add(req.Reporting_Manager__c);
        }

        Map<Id, User> userMap = new Map<Id, User>([
            SELECT Id, Name, Email FROM User WHERE Id IN :userIds AND IsActive = true
        ]);

        List<Messaging.SingleEmailMessage> emailList = new List<Messaging.SingleEmailMessage>();

        for (Account_Team_Approval__c req : newList) {
            String recordLink = BASE_URL + '/' + req.Id;

            // Notification to Requester
            if (req.Requester__c != null && userMap.containsKey(req.Requester__c)) {
                User requester = userMap.get(req.Requester__c);
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new String[] { requester.Email });
                email.setSubject('Confirmation: Join Account Team Request Submitted');
                email.setPlainTextBody(
                    'Hello ' + requester.Name + ',\n\n' +
                    'Your request to join the Account Team has been submitted.\n' +
                    '<p><a href="' + recordLink + '">View Request</a></p>\n' +
                    'Status: Pending Reporting Manager Approval\n\n' +
                    'Thank you.'
                );
                emailList.add(email);
            }

            // Notification to Reporting Manager
            if (req.Reporting_Manager__c != null && userMap.containsKey(req.Reporting_Manager__c)) {
                User manager = userMap.get(req.Reporting_Manager__c);
                User requester = userMap.get(req.Requester__c);
                String reqName = requester != null ? requester.Name : 'A user';

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new String[] { manager.Email });
                email.setSubject('Action Required: Account Team Join Request');
                email.setHtmlBody(
                    '<p>Hello ' + manager.Name + ',</p>' +
                    '<p><b>' + reqName + '</b> has submitted an Account Team Approval Request that requires your review.</p>' +
                    '<p><a href="' + recordLink + '">Click here to Review Request</a></p>' +
                    '<br/><p>Thank you.</p>'
                );
                emailList.add(email);
            }
        }

        if (!emailList.isEmpty()) {
            Messaging.sendEmail(emailList);
        }
    }

    public static void handleAfterUpdate(List<Account_Team_Approval__c> newList, Map<Id, Account_Team_Approval__c> oldMap) {
        List<AccountTeamMember> membersToInsert = new List<AccountTeamMember>();
        Set<Id> accountsForRemoval = new Set<Id>();
        Set<Id> usersForRemoval = new Set<Id>();

        Set<Id> allUserIdsToQuery = new Set<Id>();
        List<Account_Team_Approval__c> inReviewRequests = new List<Account_Team_Approval__c>();
        List<Account_Team_Approval__c> approvedRequests = new List<Account_Team_Approval__c>();
        List<Account_Team_Approval__c> deniedRequests = new List<Account_Team_Approval__c>();

        for (Account_Team_Approval__c req : newList) {
            Account_Team_Approval__c oldReq = oldMap.get(req.Id);

            if (req.Requester__c != null) allUserIdsToQuery.add(req.Requester__c);
            if (req.Add_Member__c != null) allUserIdsToQuery.add(req.Add_Member__c);
            if (req.Remove_Member__c != null) allUserIdsToQuery.add(req.Remove_Member__c);

            // Routing to Sales Ops Queue
            if (req.Status__c == 'In Review' && oldReq.Status__c != 'In Review') {
                inReviewRequests.add(req);
            }

            // Final Approval Logic
            if (req.Status__c == 'Approved' && oldReq.Status__c != 'Approved') {
                approvedRequests.add(req);

                if (req.Add_Member__c != null && req.AccountId__c != null) {
                    membersToInsert.add(new AccountTeamMember(
                        AccountId = req.AccountId__c,
                        UserId = req.Add_Member__c,
                        TeamMemberRole = req.Add_Role__c
                    ));
                }

                if (req.Remove_Member__c != null && req.AccountId__c != null) {
                    accountsForRemoval.add(req.AccountId__c);
                    usersForRemoval.add(req.Remove_Member__c);
                }
            }

            // Denial Logic
            if (req.Status__c == 'Denied' && oldReq.Status__c != 'Denied') {
                deniedRequests.add(req);
            }
        }

        if (!membersToInsert.isEmpty()) {
            insert membersToInsert;
        }

        if (!accountsForRemoval.isEmpty() && !usersForRemoval.isEmpty()) {
            delete [
                SELECT Id FROM AccountTeamMember 
                WHERE AccountId IN :accountsForRemoval 
                AND UserId IN :usersForRemoval
            ];
        }

        Map<Id, User> userMap = new Map<Id, User>([
            SELECT Id, Name, Email FROM User WHERE Id IN :allUserIdsToQuery AND IsActive = true
        ]);
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        // 1. Sales Ops Queue Alert
        if (!inReviewRequests.isEmpty()) {
            List<String> salesOpsEmails = getSalesOpsQueueEmails();
            if (!salesOpsEmails.isEmpty()) {
                for (Account_Team_Approval__c req : inReviewRequests) {
                    String recordLink = BASE_URL + '/' + req.Id;
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setToAddresses(salesOpsEmails);
                    email.setSubject('Action Required: Account Team Request Pending Sales Ops Approval');
                    email.setHtmlBody(
                        '<p>A request approved by the Reporting Manager is now ready for Sales Operations review.</p>' +
                        '<p><a href="' + recordLink + '">Click here to Review Record</a></p>'
                    );
                    emailsToSend.add(email);
                }
            }
        }

        // 2. Approved Notifications
        for (Account_Team_Approval__c req : approvedRequests) {
            Set<String> recipientEmails = getRecipientEmails(req, userMap);
            if (!recipientEmails.isEmpty()) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>(recipientEmails));
                email.setSubject('Approved: Account Team Request');
                email.setPlainTextBody(
                    'Your Account Team request has received final approval from Sales Operations.\n' +
                    'Request ID: ' + req.Id + '\n' +
                    'Account Team updates have been successfully applied.\n\n' +
                    'Thank you.'
                );
                emailsToSend.add(email);
            }
        }

        // 3. Denied Notifications
        for (Account_Team_Approval__c req : deniedRequests) {
            Set<String> recipientEmails = getRecipientEmails(req, userMap);
            if (!recipientEmails.isEmpty()) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>(recipientEmails));
                email.setSubject('Denied: Account Team Request');
                email.setPlainTextBody(
                    'Your Account Team request has been denied.\n' +
                    'Request ID: ' + req.Id + '\n' +
                    'Denial Reason: ' + (String.isNotBlank(req.Denial_Reason__c) ? req.Denial_Reason__c : 'N/A') + '\n\n' +
                    'Thank you.'
                );
                emailsToSend.add(email);
            }
        }

        if (!emailsToSend.isEmpty()) {
            Messaging.sendEmail(emailsToSend);
        }
        
        
handleCommissionHistory(newList, oldMap);

    }

    // Populate Territory__c on Account_Team_Approval__c using StateTerritory__mdt Custom Metadata
    private static void populateTerritoryFromState(List<Account_Team_Approval__c> records) {
        Map<String, String> stateCodeToTerritoryMap = new Map<String, String>();
        for (StateTerritory__mdt mapping : StateTerritory__mdt.getAll().values()) {
            if (String.isNotBlank(mapping.State__c) && String.isNotBlank(mapping.Territory__c)) {
                stateCodeToTerritoryMap.put(mapping.State__c.trim().toUpperCase(), mapping.Territory__c);
            }
        }

        for (Account_Team_Approval__c req : records) {
            if (String.isNotBlank(req.State__c)) {
                String rawState = req.State__c.trim().toUpperCase();
                String stateCode = STATE_NAME_TO_CODE.containsKey(rawState) 
                    ? STATE_NAME_TO_CODE.get(rawState) 
                    : rawState;

                if (stateCodeToTerritoryMap.containsKey(stateCode)) {
                    req.Territory__c = stateCodeToTerritoryMap.get(stateCode);
                }
            }
        }
    }

    private static List<String> getSalesOpsQueueEmails() {
        Set<Id> queueUserIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT UserOrGroupId FROM GroupMember 
            WHERE Group.DeveloperName = 'Sales_Operations' AND Group.Type = 'Queue'
        ]) {
            if (((String)gm.UserOrGroupId).startsWith('005')) {
                queueUserIds.add(gm.UserOrGroupId);
            }
        }

        List<String> emails = new List<String>();
        if (!queueUserIds.isEmpty()) {
            for (User u : [SELECT Email FROM User WHERE Id IN :queueUserIds AND IsActive = true]) {
                if (String.isNotBlank(u.Email)) {
                    emails.add(u.Email);
                }
            }
        }
        return emails;
    }

    private static Set<String> getRecipientEmails(Account_Team_Approval__c req, Map<Id, User> userMap) {
        Set<String> emails = new Set<String>();
        if (req.Requester__c != null && userMap.containsKey(req.Requester__c)) {
            emails.add(userMap.get(req.Requester__c).Email);
        }
        if (req.Add_Member__c != null && userMap.containsKey(req.Add_Member__c)) {
            emails.add(userMap.get(req.Add_Member__c).Email);
        }
        if (req.Remove_Member__c != null && userMap.containsKey(req.Remove_Member__c)) {
            emails.add(userMap.get(req.Remove_Member__c).Email);
        }
        return emails;
    }

    public static void handleCommissionHistory(
    List<Account_Team_Approval__c> newList,
    Map<Id, Account_Team_Approval__c> oldMap
) {
    AtApprovalCommissionHandler.processApprovals(newList, oldMap);
}
 

}