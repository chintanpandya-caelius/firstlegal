public with sharing class Lead_SendSLABreachEmail {

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable(required=true)
        public Id ownerId;
    }

    @InvocableMethod(
        label='Send Hot Lead SLA Breach Email'
        description='Sends a production-grade partial-success safe email to Lead Owners or Queue Members with Lightning app links.'
    )
    public static void sendEmailNotification(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> leadIds = new Set<Id>();
        Set<Id> queueIds = new Set<Id>();
        
        for (Request req : requests) {
            if (req.leadId != null) { leadIds.add(req.leadId); }
            if (req.ownerId != null && req.ownerId.getSObjectType() == Group.SObjectType) {
                queueIds.add(req.ownerId);
            }
        }

        Map<Id, Lead> leadMap = new Map<Id, Lead>([
            SELECT Id, Name, Company, SLA_Due_Date__c 
            FROM Lead 
            WHERE Id IN :leadIds
        ]);

        Map<Id, Set<Id>> queueUsers = new Map<Id, Set<Id>>();
        if (!queueIds.isEmpty()) {
            for (GroupMember gm : [
                SELECT GroupId, UserOrGroupId 
                FROM GroupMember 
                WHERE GroupId IN :queueIds
            ]) {
                if (gm.UserOrGroupId.getSObjectType() == User.SObjectType) {
                    if (!queueUsers.containsKey(gm.GroupId)) {
                        queueUsers.put(gm.GroupId, new Set<Id>());
                    }
                    queueUsers.get(gm.GroupId).add(gm.UserOrGroupId);
                }
            }
        }

        Set<Id> userIdsToQuery = new Set<Id>();
        for (Request req : requests) {
            if (req.ownerId != null && req.ownerId.getSObjectType() == User.SObjectType) {
                userIdsToQuery.add(req.ownerId);
            } else if (queueUsers.containsKey(req.ownerId)) {
                userIdsToQuery.addAll(queueUsers.get(req.ownerId));
            }
        }

        Map<Id, User> userMap = new Map<Id, User>([
            SELECT Id, Email 
            FROM User 
            WHERE Id IN :userIdsToQuery AND IsActive = true
        ]);

        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        Datetime currentMoment = System.now();

        for (Request req : requests) {
            Lead currentLead = leadMap.get(req.leadId);
            if (currentLead == null) { continue; }

            Set<String> recipientEmails = new Set<String>();

            if (req.ownerId != null && req.ownerId.getSObjectType() == User.SObjectType) {
                if (userMap.containsKey(req.ownerId) && userMap.get(req.ownerId).Email != null) {
                    recipientEmails.add(userMap.get(req.ownerId).Email);
                }
            } else if (queueUsers.containsKey(req.ownerId)) {
                for (Id uId : queueUsers.get(req.ownerId)) {
                    if (userMap.containsKey(uId) && userMap.get(uId).Email != null) {
                        recipientEmails.add(userMap.get(uId).Email);
                    }
                }
            }

            // Clean loop optimization guard clause
            if (recipientEmails.isEmpty()) {
                continue;
            }

            Long breachMinutes = Math.max(0, (currentMoment.getTime() - (currentLead.SLA_Due_Date__c != null ? currentLead.SLA_Due_Date__c.getTime() : currentMoment.getTime())) / 60000);
            
            Long hours = breachMinutes / 60;
            Long mins = Math.mod(breachMinutes, 60);
            String breachDuration = (hours > 0) ? (hours + ' hr ' + mins + ' min') : (mins + ' min');

            // Removed escapeHtml4() - Apex string variables assigned directly
            String structuralLeadName = currentLead.Name != null ? currentLead.Name : 'Unknown Lead';
            String unescapedCompany = currentLead.Company != null ? currentLead.Company : 'Unknown Company';
            
            String safeLeadName = structuralLeadName;
            String safeCompany = unescapedCompany;
            
            String formattedDueDate = currentLead.SLA_Due_Date__c != null ? currentLead.SLA_Due_Date__c.format() : 'N/A';
            String recordUrl = baseUrl + '/lightning/r/Lead/' + currentLead.Id + '/view';

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>(recipientEmails));
            email.setSaveAsActivity(false); 
            email.setSubject('URGENT | Hot Lead SLA Breached | ' + safeCompany);

            email.setHtmlBody(
                '<p>Hello,</p>' +
                '<p>A Hot Lead has exceeded its configured SLA and requires immediate attention.</p>' +
                '<p>' +
                '<b>Lead Name:</b> ' + safeLeadName + '<br/>' +
                '<b>Company:</b> ' + safeCompany + '<br/>' +
                '<b>SLA Due Date:</b> ' + formattedDueDate + '<br/>' +
                '<b>Breach Duration:</b> ' + breachDuration + 
                '</p>' +
                '<p><a href="' + recordUrl + '">Open Lead Record</a></p>' +
                '<p>Please review the Lead immediately.</p>'
            );

            email.setPlainTextBody(
                'Hello,\n\n' +
                'A Hot Lead has exceeded its configured SLA and requires immediate attention.\n\n' +
                'Lead Name: ' + safeLeadName + '\n' +
                'Company: ' + safeCompany + '\n' +
                'SLA Due Date: ' + formattedDueDate + '\n' +
                'Breach Duration: ' + breachDuration + '\n\n' +
                'Open Lead Record: ' + recordUrl + '\n\n' +
                'Please review the Lead immediately.'
            );

            emailsToSend.add(email);
        }

        if (!emailsToSend.isEmpty()) {
            try {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(emailsToSend, false);
                
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        for (Messaging.SendEmailError err : results[i].getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Lead_SendSLABreachEmail failed sending email element: ' + err.getMessage());
                        }
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Lead_SendSLABreachEmail failed entirely during delivery execution: ' + e.getMessage());
            }
        }
    }
}