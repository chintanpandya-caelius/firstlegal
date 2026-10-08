public without sharing class MyTicketsController {

    @AuraEnabled(cacheable=true)
    public static List<Case> getMyTickets() {
        try {
            User currentUser = [
                SELECT ContactId 
                FROM User 
                WHERE Id = :UserInfo.getUserId() 
                LIMIT 1
            ];

            return [
                SELECT Id, CaseNumber, Subject, Status, Priority, Type, CreatedDate
                FROM Case
                WHERE ContactId = :currentUser.ContactId
                ORDER BY Status ASC, CreatedDate DESC
                LIMIT 1000
            ];

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<StatusCount> getTicketCountByStatus() {
        try {
            User currentUser = [
                SELECT ContactId 
                FROM User 
                WHERE Id = :UserInfo.getUserId() 
                LIMIT 1
            ];

            List<AggregateResult> results = [
                SELECT Status, COUNT(Id) cnt
                FROM Case
                WHERE ContactId = :currentUser.ContactId
                GROUP BY Status
                ORDER BY Status ASC
            ];

            List<StatusCount> counts = new List<StatusCount>();
            for (AggregateResult ar : results) {
                counts.add(new StatusCount(
                    (String)  ar.get('Status'),
                    (Integer) ar.get('cnt')
                ));
            }
            return counts;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class StatusCount {
        @AuraEnabled public final String  status;
        @AuraEnabled public final Integer count;

        public StatusCount(String status, Integer count) {
            this.status = status;
            this.count  = count;
        }
    }
}