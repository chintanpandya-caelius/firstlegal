public with sharing class AccountTeamMemberTriggerHelper {
    
    /**
     * Standard roll-up handler for inserts, deletes, and undeletes
     */
    public static void handleRollup(List<AccountTeamMember> atmList) {
        Set<Id> accountIds = new Set<Id>();
        for (AccountTeamMember atm : atmList) {
            if (atm.AccountId != null) {
                accountIds.add(atm.AccountId);
            }
        }
        recalculateSalesReps(accountIds);
    }

    /**
     * Specialized update handler to check if either the Parent Account or the Team Role changed
     */
    public static void handleUpdate(List<AccountTeamMember> newList, Map<Id, AccountTeamMember> oldMap) {
        Set<Id> accountIds = new Set<Id>();
        for (AccountTeamMember newAtm : newList) {
            AccountTeamMember oldAtm = oldMap.get(newAtm.Id);
            
            // Check if the Account ID or the Role changed
            if (newAtm.AccountId != oldAtm.AccountId || newAtm.TeamMemberRole != oldAtm.TeamMemberRole) {
                if (newAtm.AccountId != null) {
                    accountIds.add(newAtm.AccountId);
                }
                if (oldAtm.AccountId != null) {
                    accountIds.add(oldAtm.AccountId); // Capture old parent in case of reparenting
                }
            }
        }
        recalculateSalesReps(accountIds);
    }

    /**
     * Recalculates Sales Rep counts on parent Accounts and updates them
     */
    private static void recalculateSalesReps(Set<Id> accountIds) {
        if (accountIds.isEmpty()) return;

        // Map to keep track of Account IDs and their updated counts
        Map<Id, Account> accountsToUpdateMap = new Map<Id, Account>();
        
        // Step 1: Initialize all target Accounts with 0 counts (to handle deletions down to zero)
        for (Id accId : accountIds) {
            accountsToUpdateMap.put(accId, new Account(Id = accId, Sales_Rep_Count__c = 0));
        }

        // Step 2: Query and count active "Sales Rep" roles on these accounts
        List<AggregateResult> groupedResults = [
            SELECT AccountId, COUNT(Id) repCount 
            FROM AccountTeamMember 
            WHERE AccountId IN :accountIds AND TeamMemberRole = 'Sales Rep'
            GROUP BY AccountId
        ];

        // Step 3: Populate the map with active counts
        for (AggregateResult ar : groupedResults) {
            Id accId = (Id)ar.get('AccountId');
            Integer count = (Integer)ar.get('repCount');
            if (accountsToUpdateMap.containsKey(accId)) {
                accountsToUpdateMap.get(accId).Sales_Rep_Count__c = count;
            }
        }

        // Step 4: Perform the DML update on the parent Accounts
        if (!accountsToUpdateMap.isEmpty()) {
            try {
                update accountsToUpdateMap.values();
            } catch (DmlException e) {
                System.debug('Error updating Account Sales Rep Counts: ' + e.getMessage());
            }
        }
    }
}