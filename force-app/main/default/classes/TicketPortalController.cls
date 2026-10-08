public with sharing class TicketPortalController {

    private static final String WAITING_ON_CUSTOMER_STATUS = 'Waiting on Customer';
    private static final String ADMIN_PROFILE_NAME = 'Admin Customer User';
    private static final Integer MAX_PAGE_SIZE = 50;

    public class TicketPortalException extends Exception {}

    public class TicketWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String priority;
        @AuraEnabled public String status;

        public TicketWrapper(Case c) {
            this.id = c.Id;
            this.caseNumber = c.CaseNumber;
            this.subject = c.Subject;
            this.priority = c.Priority;
            this.status = c.Status;
        }
    }

    public class TicketPageResult {
        @AuraEnabled public List<TicketWrapper> tickets;
        @AuraEnabled public Integer totalRecords;

        public TicketPageResult(List<TicketWrapper> tickets, Integer totalRecords) {
            this.tickets = tickets;
            this.totalRecords = totalRecords;
        }
    }

    @AuraEnabled(cacheable=true)
    public static TicketPageResult getTickets(Integer pageSize, Integer pageNumber, String searchTerm, String filterType) {
        try {
            Integer safePageSize = normalizePageSize(pageSize);
            Integer safePageNumber = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
            Integer offset = (safePageNumber - 1) * safePageSize;

            RunningUserContext ctx = getRunningUserContext();

            String searchPattern = null;
            if (String.isNotBlank(searchTerm)) {
                searchPattern = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            }

            String scopeClause = ctx.isPortalAdmin ? 'AccountId = :accountIdFilter' : 'ContactId = :contactIdFilter';

            Id accountIdFilter = ctx.accountId;
            Id contactIdFilter = ctx.contactId;

            String baseWhere = ' WHERE Status = :statusFilter' + ' AND ' + scopeClause + (searchPattern != null ? ' AND (CaseNumber LIKE :searchPattern OR Subject LIKE :searchPattern)' : '');

            String statusFilter = WAITING_ON_CUSTOMER_STATUS;

            Integer totalRecords = Database.countQuery(
                'SELECT COUNT() FROM Case' + baseWhere + ' WITH USER_MODE'
            );

            List<Case> cases = Database.query(
                'SELECT Id, CaseNumber, Subject, Priority, Status FROM Case' +
                baseWhere +
                ' WITH USER_MODE' +
                ' ORDER BY LastModifiedDate DESC' +
                ' LIMIT :safePageSize OFFSET :offset'
            );

            List<TicketWrapper> wrappers = new List<TicketWrapper>();
            for (Case c : cases) {
                wrappers.add(new TicketWrapper(c));
            }

            return new TicketPageResult(wrappers, totalRecords);
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load tickets: ' + e.getMessage());
        }
    }

    private static Integer normalizePageSize(Integer requested) {
        if (requested == null || requested < 1) {
            return 5;
        }
        return Math.min(requested, MAX_PAGE_SIZE);
    }

    private class RunningUserContext {
        Id contactId;
        Id accountId;
        Boolean isPortalAdmin;
    }

    private static RunningUserContext getRunningUserContext() {
        List<User> users = [
            SELECT ContactId, Contact.AccountId, Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (users.isEmpty() || users[0].ContactId == null) {
            throw new TicketPortalException('Current user is not associated with a Contact.');
        }

        User runningUser = users[0];

        RunningUserContext ctx = new RunningUserContext();
        ctx.contactId = runningUser.ContactId;
        ctx.accountId = runningUser.Contact.AccountId;
        ctx.isPortalAdmin = runningUser.Profile.Name == ADMIN_PROFILE_NAME;
        return ctx;
    }
}