global class CalendarInviteEmailHandler implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        
        try {
            String senderEmail = email.fromAddress;
            Boolean isPrivateEvent = false;

            // 1. Parse iCalendar (.ics) attachments to detect Private flags
            if (email.binaryAttachments != null) {
                for (Messaging.InboundEmail.BinaryAttachment bAttach : email.binaryAttachments) {
                    if (bAttach.filename.endsWithIgnoreCase('.ics')) {
                        String icsContent = bAttach.body.toString();
                        if (icsContent.contains('CLASS:PRIVATE') || icsContent.contains('CLASS:CONFIDENTIAL')) {
                            isPrivateEvent = true;
                        }
                    }
                }
            }

            // 2. Domain & Unknown Email Check
            Boolean isUnresolved = TaskUnresolvedItemService.isUnknownExternalSender(senderEmail);

            if (isUnresolved) {
                // Create an Unresolved Item Task for manual association
                Task unresolvedTask = new Task();
                unresolvedTask.Subject = 'Unresolved Email/Invite: ' + email.subject;
                unresolvedTask.Description = email.plainTextBody;
                unresolvedTask.Status = 'Open';
                unresolvedTask.Priority = 'High';
                unresolvedTask.Type = 'Email';
                
                // Custom fields or Task fields used to track raw sender info
                // Make sure to add custom fields on Task if needed: Sender_Email__c
                // unresolvedTask.Sender_Email__c = senderEmail;

                insert unresolvedTask;
            } else {
                // Known Contact/Lead: Create standard Event / Task linked to record
                Event calendarEvt = new Event();
                calendarEvt.Subject = email.subject;
                calendarEvt.Description = email.plainTextBody;
                calendarEvt.StartDateTime = System.now();
                calendarEvt.EndDateTime = System.now().addHours(1);
                calendarEvt.IsPrivate = isPrivateEvent; // Automated IsPrivate mapping
                
                // Relate to matching contact
                List<Contact> matchedContacts = [SELECT Id FROM Contact WHERE Email = :senderEmail LIMIT 1];
                if (!matchedContacts.isEmpty()) {
                    calendarEvt.WhoId = matchedContacts[0].Id;
                }
                
                insert calendarEvt;
            }

            result.success = true;
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error processing inbound calendar invite: ' + e.getMessage();
        }

        return result;
    }
}