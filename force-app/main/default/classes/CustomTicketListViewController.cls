public without sharing class CustomTicketListViewController {

    public class TicketWrapper {
        @AuraEnabled public Id ticketId;
        @AuraEnabled public String ticketNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String contactName;
    }

    public class TicketResult {
        @AuraEnabled public List<TicketWrapper> tickets;
        @AuraEnabled public Integer totalCount;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getListViewOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        
        // These values match the logic in your getTickets method
        options.add(new Map<String, String>{ 'label' => 'My Open Tickets', 'value' => 'OPEN' });
        options.add(new Map<String, String>{ 'label' => 'My Closed Tickets', 'value' => 'CLOSED' });
        options.add(new Map<String, String>{ 'label' => 'All My Tickets', 'value' => 'ALL' });
        
        return options;
    }
	
    @AuraEnabled(cacheable=true)
    public static TicketResult getTickets(String selectedView, String searchTerm, Integer pageSize, Integer pageNumber) {
        
           List<User> users = [
            SELECT ContactId, Contact.AccountId, Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        
        Id contactId = users[0].ContactId;
        Id accountId = users[0].Contact?.AccountId;

        List<String> conditions = new List<String>();

        Boolean hasTicketAccess = FeatureManagement.checkPermission('Access_all_tickets_related_to_Account');

        if (hasTicketAccess && accountId != null) {
            conditions.add('Contact.AccountId = :accountId');
        } else {
            conditions.add('ContactId = :contactId');
        }

        if (String.isNotBlank(selectedView) && selectedView != 'ALL') {
            if (selectedView == 'OPEN') {
                conditions.add('IsClosed = false');
            } else if (selectedView == 'CLOSED') {
                conditions.add('IsClosed = true');
            } else {
                conditions.add('Status = :selectedView');
            }
        }

        String likeTerm;
        if (String.isNotBlank(searchTerm)) {
            likeTerm = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            conditions.add('(Subject LIKE :likeTerm OR CaseNumber LIKE :likeTerm)');
        }

        String baseWhere = String.join(conditions, ' AND ');

        Integer pgSize = (pageSize == null || pageSize <= 0) ? 5 : pageSize;
        Integer pgNumber = (pageNumber == null || pageNumber <= 0) ? 1 : pageNumber;
        Integer offsetVal = (pgNumber - 1) * pgSize;

        Integer totalCount = Database.countQuery('SELECT COUNT() FROM Case WHERE ' + baseWhere);

        String dataQuery =
            'SELECT Id, CaseNumber, Subject, Status, LastModifiedDate, Contact.Name ' +
            'FROM Case WHERE ' + baseWhere +
            ' ORDER BY LastModifiedDate DESC ' +
            'LIMIT :pgSize OFFSET :offsetVal';
        
        System.debug(dataQuery);

        List<Case> caseRecords = Database.query(dataQuery);

        TicketResult result = new TicketResult();
        result.tickets = new List<TicketWrapper>();
        result.totalCount = totalCount;

        for (Case c : caseRecords) {
            TicketWrapper w = new TicketWrapper();
            w.ticketId = c.Id;
            w.ticketNumber = c.CaseNumber;
            w.subject = c.Subject;
            w.status = c.Status;
            w.lastModifiedDate = c.LastModifiedDate;
            w.contactName = c.Contact != null ? c.Contact.Name : '';
            result.tickets.add(w);
        }

        return result;
    }

    // For View All List View
    @AuraEnabled(cacheable=true)
    public static TicketResult getAllTickets(
        String selectedView,
        String searchTerm
    ) {
        
        List<User> users = [
            SELECT ContactId, Contact.AccountId, Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        Id contactId = users[0].ContactId;
        Id accountId = users[0].Contact?.AccountId;

        List<String> conditions = new List<String>();

        Boolean hasTicketAccess =
            FeatureManagement.checkPermission(
                'Access_all_tickets_related_to_Account'
            );

        if (hasTicketAccess && accountId != null) {
            conditions.add(
                'Contact.AccountId = :accountId'
            );
        } else {
            conditions.add(
                'ContactId = :contactId'
            );
        }

        if (
            String.isNotBlank(selectedView) &&
            selectedView != 'ALL'
        ) {

            if (selectedView == 'OPEN') {

                conditions.add(
                    'IsClosed = false'
                );

            } else if (selectedView == 'CLOSED') {

                conditions.add(
                    'IsClosed = true'
                );

            } else {

                conditions.add(
                    'Status = :selectedView'
                );
            }
        }

        String likeTerm;

        if (String.isNotBlank(searchTerm)) {

            likeTerm = '%' + searchTerm + '%';

            conditions.add(
                '(Subject LIKE :likeTerm OR CaseNumber LIKE :likeTerm)'
            );
        }

        String baseWhere =
            String.join(conditions, ' AND ');

        /*
        * Count
        */
        Integer totalCount =
            Database.countQuery(
                'SELECT COUNT() FROM Case WHERE ' +
                baseWhere
            );

        /*
        * IMPORTANT:
        * No LIMIT.
        * No OFFSET.
        */
        String dataQuery =
            'SELECT Id, CaseNumber, Subject, Status, ' +
            'LastModifiedDate, Contact.Name ' +
            'FROM Case WHERE ' +
            baseWhere +
            ' ORDER BY LastModifiedDate DESC';

        List<Case> caseRecords =
            Database.query(dataQuery);

        TicketResult result =
            new TicketResult();

        result.tickets =
            new List<TicketWrapper>();

        result.totalCount =
            totalCount;

        for (Case c : caseRecords) {

            TicketWrapper w =
                new TicketWrapper();

            w.ticketId =
                c.Id;

            w.ticketNumber =
                c.CaseNumber;

            w.subject =
                c.Subject;

            w.status =
                c.Status;

            w.lastModifiedDate =
                c.LastModifiedDate;

            w.contactName =
                c.Contact != null
                    ? c.Contact.Name
                    : '';

            result.tickets.add(w);
        }

        return result;
    }
}