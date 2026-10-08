public with sharing class AccountTeamMemberTriggerHelper {

    private static final Set<String> SALES_ROLES = new Set<String>{
        'AE', 'AM', 'BDR', 'CCT', 'IC', 'MMAE', 'SME'
    };

    public static void handleRollup(List<AccountTeamMember> atmList) {
        Set<Id> accountIds = new Set<Id>();

        for (AccountTeamMember atm : atmList) {
            if (atm.AccountId != null) {
                accountIds.add(atm.AccountId);
            }
        }

        recalculateSalesReps(accountIds);
    }

    public static void handleUpdate(List<AccountTeamMember> newList,Map<Id, AccountTeamMember> oldMap) {
        Set<Id> accountIds = new Set<Id>();

        for (AccountTeamMember newAtm : newList) {
            AccountTeamMember oldAtm = oldMap.get(newAtm.Id);

            if (newAtm.AccountId != oldAtm.AccountId || newAtm.TeamMemberRole != oldAtm.TeamMemberRole) {

                if (newAtm.AccountId != null) {
                    accountIds.add(newAtm.AccountId);
                }

                if (oldAtm.AccountId != null) {
                    accountIds.add(oldAtm.AccountId);
                }
            }
        }

        recalculateSalesReps(accountIds);
    }

    private static void recalculateSalesReps(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }

        Map<Id, Decimal> salesRepCounts = new Map<Id, Decimal>();

        for (Id accountId : accountIds) {
            salesRepCounts.put(accountId, 0);
        }

        List<AggregateResult> accountTeamResults = [SELECT AccountId, COUNT(Id) repCount FROM AccountTeamMember
                                                    WHERE AccountId IN :accountIds
                                                    AND TeamMemberRole IN :SALES_ROLES
                                                   GROUP BY AccountId];

for (AggregateResult ar : accountTeamResults) {
    salesRepCounts.put((Id) ar.get('AccountId'),(Decimal) ar.get('repCount'));
}

        List<Account> accountsToUpdate = new List<Account>();

        for (Id accountId : accountIds) {
            accountsToUpdate.add(new Account(
                                     Id = accountId,
                                     Sales_Rep_Count__c = salesRepCounts.get(accountId)
            ));
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }

        HouseAccountHandler.updateHouseSegment(accountIds);
    }
}