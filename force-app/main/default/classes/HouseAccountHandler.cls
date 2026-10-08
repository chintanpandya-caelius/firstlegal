public without sharing class HouseAccountHandler {

    private static Boolean isExecuting = false;

    public static void updateHouseSegment(Set<Id> accountIds) {

        if (isExecuting || accountIds == null || accountIds.isEmpty()) {
            return;
        }

        isExecuting = true;

        try {
            List<Account> accountsToUpdate = new List<Account>();
            Date twentyFourMonthsAgo = System.today().addMonths(-24);

            // Fetch Accounts along with qualifying Closed Won Opportunities (Amount > 0, closed in past 24 mos)
            List<Account> accounts = [
                SELECT Id, Name, Segment__c, Sales_Rep_Count__c,
                       (SELECT Id 
                        FROM Opportunities 
                        WHERE StageName = 'Closed Won' 
                          AND Amount > 0 
                          AND Amount != NULL
                          AND CloseDate >= :twentyFourMonthsAgo 
                        LIMIT 1)
                FROM Account 
                WHERE Id IN :accountIds
            ];

            for (Account acc : accounts) {

                // 1. Condition 1: No Sales Rep assigned
                Boolean hasNoSalesRep = (acc.Sales_Rep_Count__c == null || acc.Sales_Rep_Count__c == 0);
                
                // 2. Condition 2: Has qualifying Closed Won revenue
                Boolean hasQualifyingRevenue = !acc.Opportunities.isEmpty();

                Set<String> segments = new Set<String>();

                if (String.isNotBlank(acc.Segment__c)) {
                    segments.addAll(acc.Segment__c.split(';'));
                }

                // BOTH conditions must be TRUE (AND operator)
                if (hasNoSalesRep && hasQualifyingRevenue) {
                    segments.add('Growth');
                } else {
                    segments.remove('Growth');
                }

                List<String> updatedSegments = new List<String>(segments);
                updatedSegments.sort();

                String newValue = updatedSegments.isEmpty() ? null : String.join(updatedSegments, ';');

                if (newValue != acc.Segment__c) {
                    accountsToUpdate.add(new Account(Id = acc.Id, Segment__c = newValue));
                }
            }

            if (!accountsToUpdate.isEmpty()) {
                Database.update(accountsToUpdate, false);
            }

        } catch (Exception ex) {
            System.debug('Error in updateHouseSegment: ' + ex.getMessage());
            throw ex;
        } finally {
            isExecuting = false;
        }
    }
}