public without sharing class SharedNoteController {

    private static final Integer DEFAULT_NOTE_PAGE_SIZE = 10;
    private static final Integer MAX_NOTE_PAGE_SIZE = 50;
    private static final List<String> ALLOWED_PROFILES;
    static {
        ALLOWED_PROFILES = new List<String>{'System Administrator', 'First Legal User'};
    }

    @AuraEnabled
    public static Id createSharedNote(Id ticketId, String body, String noteType) {
        try {
            if (ticketId == null) {
                throw new AuraHandledException('A ticket must be provided.');
            }
            if (String.isBlank(body)) {
                throw new AuraHandledException('Note body cannot be blank.');
            }

            SharedNote__c note = new SharedNote__c(
                Body__c = body,
                Note_Type__c = noteType
            );
            insert note;

            Shared_Note_Link__c link = new Shared_Note_Link__c(
                Shared_Note__c = note.Id,
                Ticket__c = ticketId,
                Is_Read__c = false
            );
            insert link;

            return link.Id;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to save note: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<User> getUserTagOptions() {
        return [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true
            AND Profile.Name IN :ALLOWED_PROFILES
            WITH SYSTEM_MODE
            ORDER BY Name
        ];
    }

    @AuraEnabled
    public static List<SharedNote__c> getSharedNotes(
        Id ticketId,
        Integer pageSize,
        Datetime lastCreatedDate,
        Id lastNoteId
    ) {
        if (ticketId == null) {
            return new List<SharedNote__c>();
        }

        Integer requestedPageSize = pageSize == null
            ? DEFAULT_NOTE_PAGE_SIZE
            : pageSize;

        Integer safePageSize = Math.max(
            1,
            Math.min(requestedPageSize, MAX_NOTE_PAGE_SIZE)
        );

        if (lastCreatedDate == null) {
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
                LIMIT :safePageSize
            ];
        }

        return [
            SELECT Body__c, CreatedBy.Name, CreatedDate, Id
            FROM SharedNote__c
            WHERE Id IN (
                SELECT Shared_Note__c
                FROM Shared_Note_Link__c
                WHERE Ticket__c = :ticketId
            )
            AND (
                CreatedDate < :lastCreatedDate
                OR (
                    CreatedDate = :lastCreatedDate
                    AND Id < :lastNoteId
                )
            )
            WITH USER_MODE
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT :safePageSize
        ];
    }
}