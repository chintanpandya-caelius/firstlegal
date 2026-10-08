public with sharing class MyTicketsController {

    @AuraEnabled(cacheable=true)
    public static List<StatusCount> getTicketCountByStatus() {
        try {
            List<AggregateResult> results = [
                SELECT Status, COUNT(Id) cnt
                FROM Case
                WHERE OwnerId = :UserInfo.getUserId()
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