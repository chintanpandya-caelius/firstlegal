public with sharing class TicketDetailController {

    private static String getCurrentUserContactId() {
        return [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId()].ContactId;
    }

    private static void assertOwnership(Id recordId) {
        Id contactId = (Id) getCurrentUserContactId();

        List<Case> owned = [
            SELECT Id
            FROM Case
            WHERE Id = :recordId AND ContactId = :contactId
            LIMIT 1
        ];
        if (owned.isEmpty()) {
            throw new AuraHandledException('You do not have access to this ticket.');
        }
    }

    // Soft check during edge cases
    private static Boolean checkOwnership(Id recordId) {
        Id contactId = (Id) getCurrentUserContactId();

        List<Case> owned = [
            SELECT Id
            FROM Case
            WHERE Id = :recordId AND ContactId = :contactId
            LIMIT 1
        ];
        if (owned.isEmpty()) {
            return false;
        }
        return true;
    }

    @AuraEnabled(cacheable=true)
    public static Case getTicketDetail(Id recordId) {
        Boolean hasTicketAccess = FeatureManagement.checkPermission('Access_all_tickets_related_to_Account');
        if(!hasTicketAccess){
            assertOwnership(recordId);
        }
        List<Case> results = [
            SELECT
                CaseNumber,
                Subject,
                CreatedDate,
                Status,
                Priority,
                Type,
                ClosedDate,
                Description,
                ContactId,
                Contact.Name,
                Ticket_SubType__c,
                Matter_Number__c,
                Court_Case_Number__c,
                CreatedById,
                CreatedBy.Name
            FROM Case
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (results.isEmpty()) {
            throw new AuraHandledException('Ticket not found '+recordId);
        }
        return results[0];
    }

    // --------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<SharedNote__c> getCaseComments(Id ticketId){
            if (ticketId == null) {
                throw new AuraHandledException('A ticket must be provided.');
            }

            return [
                SELECT Body__c, CreatedBy.Name, CreatedDate, Id
                FROM SharedNote__c
                WHERE Id IN (
                    SELECT Shared_Note__c
                    FROM Shared_Note_Link__c
                    WHERE Ticket__c = :ticketId
                )
                WITH USER_MODE
                ORDER BY CreatedDate DESC, Id DESC
            ];
    }

    @AuraEnabled
    public static TicketReopenService.CommentRoutingResult postComment(Id ticketId, String body) {
        TicketReopenService.assertCommentingBlocked(ticketId);
        TicketReopenService.CommentRoutingResult routing = TicketReopenService.resolveCommentRouting(ticketId);

        Boolean hasTicketAccess = FeatureManagement.checkPermission('Access_all_tickets_related_to_Account');
        Boolean isContactAdded = False; // Initializing this to track notes that are created by the ticket contact itself
        if(!hasTicketAccess){
            assertOwnership(ticketId);
            isContactAdded = True;
        }
        if(checkOwnership(ticketId) && hasTicketAccess){
            isContactAdded = True;
        }
        try {
            if (ticketId == null) {
                throw new AuraHandledException('A ticket must be provided.');
            }
            if (String.isBlank(body)) {
                throw new AuraHandledException('Note body cannot be blank.');
            }

            SharedNote__c note = new SharedNote__c(
                Body__c = body,
                Note_Type__c = SharedNoteConstants.NOTE_TYPE_EXTERNAL
            );
            insert note;

            Shared_Note_Link__c link = new Shared_Note_Link__c(
                Shared_Note__c = note.Id,
                Ticket__c = ticketId,
                Is_Contact_Added__c = isContactAdded
            );
            insert link;
            return routing;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to save note: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ContentDocumentLink> getAttachments(Id recordId) {
        Boolean hasTicketAccess = FeatureManagement.checkPermission('Access_all_tickets_related_to_Account');
        if(!hasTicketAccess){
            assertOwnership(recordId);
        }
        return [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.FileExtension,
                ContentDocument.ContentSize,
                ContentDocument.CreatedDate,
                ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            ORDER BY ContentDocument.CreatedDate DESC
        ];
    }

    // Generates short-lived download AND preview links for a single file.
    // ContentDistribution links are not gated by a Salesforce login, so
    // this checks ownership through the ContentDocumentLink -> Case chain
    // first, then issues links that expire in 1 hour to limit exposure
    // if the URL is copied, forwarded, or cached somewhere unexpected.
    //
    // Returns both ContentDownloadUrl (forces download) and
    // DistributionPublicUrl (renders inline for "preview in new tab") so
    // a single Apex call can serve both the Preview and Download buttons.
    @AuraEnabled
    public static Map<String, String> getFileUrls(Id contentVersionId) {

        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            throw new AuraHandledException('File not found.');
        }

        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :versions[0].ContentDocumentId
        ];

        Set<Id> parentIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            parentIds.add(link.LinkedEntityId);
        }

        List<Case> owned = [
            SELECT Id
            FROM Case
            WHERE Id IN :parentIds
            LIMIT 1
        ];
        if (owned.isEmpty()) {
            throw new AuraHandledException('You do not have access to this file.');
        }
        ContentDistribution dist;
        try{
         dist = new ContentDistribution(
            Name                              = 'Attachment-' + contentVersionId,
            ContentVersionId                  = contentVersionId,
            PreferencesAllowViewInBrowser      = true,
            PreferencesAllowOriginalDownload   = true,
            PreferencesNotifyOnVisit           = false,
            PreferencesPasswordRequired        = false,
            PreferencesExpires                 = true,
            ExpiryDate                         = Datetime.now().addHours(1)
        );
        Database.insert(dist, false, AccessLevel.SYSTEM_MODE);
        }
        catch(Exception e){
            throw new AuraHandledException('Content Distribution issue'+contentVersionId);
        }

        try{
        dist = [
            SELECT ContentDownloadUrl, DistributionPublicUrl
            FROM ContentDistribution
            WHERE Id = :dist.Id
            LIMIT 1
        ];}
         catch(Exception e){
            throw new AuraHandledException('Content Distribution query issue');
        }
        return new Map<String, String>{
            'downloadUrl' => dist.ContentDownloadUrl,
            'previewUrl'  => dist.DistributionPublicUrl
        };
    }
}