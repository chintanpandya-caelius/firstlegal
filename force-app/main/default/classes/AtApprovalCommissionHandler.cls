public without sharing class AtApprovalCommissionHandler {

    private static final Set<String> COMMISSIONABLE_ROLES = new Set<String>{
        'AE', 'AM', 'BDR', 'CCT', 'FLD', 'FLDS', 'FLED', 'FLI', 'FRR', 'IC', 'MMAE'
    };

    public static void processApprovals(
        List<Account_Team_Approval__c> newRecords,
        Map<Id, Account_Team_Approval__c> oldMap
    ) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        List<Account_Team_Approval__c> eligibleApprovals = new List<Account_Team_Approval__c>();

        for (Account_Team_Approval__c approval : newRecords) {
            Account_Team_Approval__c oldApproval = oldMap.get(approval.Id);

            if (oldApproval == null) {
                continue;
            }

            Boolean statusApproved =
                oldApproval.Status__c == 'In Review' &&
                approval.Status__c == 'Approved';

            Boolean decisionDateAdded =
                oldApproval.Sales_Operation_Decision_Date__c == null &&
                approval.Sales_Operation_Decision_Date__c != null;

            Boolean hasCommissionableRole =
                (String.isNotBlank(approval.Add_Role__c) &&
                 COMMISSIONABLE_ROLES.contains(approval.Add_Role__c)) ||
                (String.isNotBlank(approval.Remove_Role__c) &&
                 COMMISSIONABLE_ROLES.contains(approval.Remove_Role__c));

            if (statusApproved && decisionDateAdded && hasCommissionableRole) {
                eligibleApprovals.add(approval);
            }
        }

        if (eligibleApprovals.isEmpty()) {
            return;
        }

        createCommissionHistoryForAdds(eligibleApprovals);
        updateCommissionHistoryForRemovals(eligibleApprovals);
    }

    private static void createCommissionHistoryForAdds(
        List<Account_Team_Approval__c> approvals
    ) {
        Set<Id> accountIds = new Set<Id>();
        List<Account_Team_Approval__c> validAddApprovals =
            new List<Account_Team_Approval__c>();

        for (Account_Team_Approval__c approval : approvals) {
            if (
                approval.Add_Member__c != null &&
                approval.AccountId__c != null &&
                COMMISSIONABLE_ROLES.contains(approval.Add_Role__c)
            ) {
                validAddApprovals.add(approval);
                accountIds.add(approval.AccountId__c);
            }
        }

        if (validAddApprovals.isEmpty()) {
            return;
        }

        Map<Id, Account> accountsById = new Map<Id, Account>([
            SELECT Id, ShippingState
            FROM Account
            WHERE Id IN :accountIds
        ]);

        Map<String, String> stateNameToTerritoryMap =
            new Map<String, String>();

        for (StateTerritory__mdt mapping : StateTerritory__mdt.getAll().values()) {
            if (
                String.isNotBlank(mapping.State__c) &&
                String.isNotBlank(mapping.Territory__c)
            ) {
                stateNameToTerritoryMap.put(
                    mapping.State__c.trim().toUpperCase(),
                    mapping.Territory__c.trim()
                );
            }
        }

        List<Commission_History__c> commissionHistoryRecords =
            new List<Commission_History__c>();

        for (Account_Team_Approval__c approval : validAddApprovals) {
            Commission_History__c history = new Commission_History__c();

            history.Account__c = approval.AccountId__c;
            history.CCF_Agent__c = approval.Add_Member__c;
            history.Agent_Role__c = approval.Add_Role__c;
            history.Role_Start_Date__c = approval.CCF_Start_Date__c;
            history.Service_Line__c = approval.Add_Service_Line__c;
            history.Comments__c = approval.Comments__c;
            history.Reporting_Manager__c = approval.Reporting_Manager__c;

            Account accountRecord = accountsById.get(approval.AccountId__c);

            if (
                accountRecord != null &&
                String.isNotBlank(accountRecord.ShippingState)
            ) {
                String stateName =
                    accountRecord.ShippingState.trim().toUpperCase();

                if (stateNameToTerritoryMap.containsKey(stateName)) {
                    history.Territory__c =
                        stateNameToTerritoryMap.get(stateName);
                }
            }

            commissionHistoryRecords.add(history);
        }

        if (!commissionHistoryRecords.isEmpty()) {
            insert commissionHistoryRecords;
        }
    }

    private static void updateCommissionHistoryForRemovals(
        List<Account_Team_Approval__c> approvals
    ) {
        Set<Id> agentIds = new Set<Id>();
        Set<String> roles = new Set<String>();
        Set<Id> accountIds = new Set<Id>();

        List<Account_Team_Approval__c> validRemoveApprovals =
            new List<Account_Team_Approval__c>();

        for (Account_Team_Approval__c approval : approvals) {
            if (
                approval.Remove_Member__c != null &&
                approval.AccountId__c != null &&
                COMMISSIONABLE_ROLES.contains(approval.Remove_Role__c)
            ) {
                validRemoveApprovals.add(approval);
                agentIds.add(approval.Remove_Member__c);
                roles.add(approval.Remove_Role__c);
                accountIds.add(approval.AccountId__c);
            }
        }

        if (validRemoveApprovals.isEmpty()) {
            return;
        }

        List<Commission_History__c> existingHistory = [
            SELECT
                Id,
                Account__c,
                CCF_Agent__c,
                Agent_Role__c,
                Role_Start_Date__c,
                Role_End_Date__c
            FROM Commission_History__c
            WHERE Account__c IN :accountIds
            AND CCF_Agent__c IN :agentIds
            AND Agent_Role__c IN :roles
            AND Role_End_Date__c = NULL
            ORDER BY Role_Start_Date__c DESC
        ];

        Map<String, Commission_History__c> historyByKey =
            new Map<String, Commission_History__c>();

        for (Commission_History__c history : existingHistory) {
            String key = buildHistoryKey(
                history.Account__c,
                history.CCF_Agent__c,
                history.Agent_Role__c
            );

            if (!historyByKey.containsKey(key)) {
                historyByKey.put(key, history);
            }
        }

        List<Commission_History__c> recordsToUpdate =
            new List<Commission_History__c>();

        for (Account_Team_Approval__c approval : validRemoveApprovals) {
            String key = buildHistoryKey(
                approval.AccountId__c,
                approval.Remove_Member__c,
                approval.Remove_Role__c
            );

            Commission_History__c history = historyByKey.get(key);

            if (history != null) {
                history.Role_End_Date__c = approval.CCF_End_Date__c;
                recordsToUpdate.add(history);
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }

    private static String buildHistoryKey(
        Id accountId,
        Id agentId,
        String role
    ) {
        return String.valueOf(accountId) +
            '|' +
            String.valueOf(agentId) +
            '|' +
            String.valueOf(role);
    }
}