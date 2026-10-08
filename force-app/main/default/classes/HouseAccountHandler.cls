public with sharing class HouseAccountHandler {

    private static Boolean isExecuting = false;

    public static void updateHouseSegment(Set<Id> accountIds) {

        if (isExecuting || accountIds == null || accountIds.isEmpty()) {
            return;
        }

        isExecuting = true;

        try {

            List<Account> accountsToUpdate = new List<Account>();

            for (Account acc : [
                SELECT Id,
                       Segment__c,
                       Sales_Rep_Count__c
                FROM Account
                WHERE Id IN :accountIds
            ]) {

                Boolean hasSalesRep = acc.Sales_Rep_Count__c != null &&
                                      acc.Sales_Rep_Count__c > 0;

                Set<String> segments = new Set<String>();

                if (!String.isBlank(acc.Segment__c)) {
                    segments.addAll(acc.Segment__c.split(';'));
                }

                if (!hasSalesRep) {
                    // Add House
                    segments.add('House');
                } else {
                    // Remove House
                    segments.remove('House');
                }

                List<String> updatedSegments = new List<String>();
                updatedSegments.addAll(segments);
                updatedSegments.sort();

                String newValue = updatedSegments.isEmpty()
                    ? null
                    : String.join(updatedSegments, ';');

                if (newValue != acc.Segment__c) {
                    accountsToUpdate.add(new Account(
                        Id = acc.Id,
                        Segment__c = newValue
                    ));
                }
            }

            if (!accountsToUpdate.isEmpty()) {
                update accountsToUpdate;
            }

        } finally {
            isExecuting = false;
        }
    }
}