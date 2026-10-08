public without sharing class AccountContactRelationTriggerHandler {

    public static void handle(List<AccountContactRelation> newRecords, Map<Id, AccountContactRelation> oldMap, Boolean isDelete) {
        Set<Id> accountIds = new Set<Id>();

        if (newRecords != null) {
            for (AccountContactRelation acr : newRecords) {
                if (acr.AccountId != null) {
                    accountIds.add(acr.AccountId);
                }
            }
        }

        if (oldMap != null) {
            for (AccountContactRelation acr : oldMap.values()) {
                if (acr.AccountId != null) {
                    accountIds.add(acr.AccountId);
                }
            }
        }

        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, String> accountToBillingName = new Map<Id, String>();

        // Query assigned to an explicit variable prevents compiler variable-binding bugs
        List<AccountContactRelation> acrList = [
            SELECT AccountId, Contact.Name
            FROM AccountContactRelation
            WHERE AccountId IN :accountIds
              AND ContactId != null
              AND (Roles INCLUDES ('Billing') OR Roles INCLUDES ('Billing Manager'))
            ORDER BY Primary_POC__c DESC NULLS LAST, Contact.LastName ASC NULLS LAST, Contact.FirstName ASC NULLS LAST
        ];

        for (AccountContactRelation acr : acrList) {
            if (!accountToBillingName.containsKey(acr.AccountId)) {
                accountToBillingName.put(acr.AccountId, acr.Contact.Name);
            }
        }

        List<Account> accountsToUpdate = new List<Account>();
        for (Id accountId : accountIds) {
            accountsToUpdate.add(new Account(
                Id = accountId,
                ContactName__c = accountToBillingName.get(accountId)
            ));
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
}