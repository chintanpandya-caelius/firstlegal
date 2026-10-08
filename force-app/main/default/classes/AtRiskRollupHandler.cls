public with sharing class AtRiskRollupHandler {
    private static Boolean isRunning = false;

    public static void handle(List<At_Risk__c> newRecords, List<At_Risk__c> oldRecords) {
        if (isRunning) return;
        isRunning = true;
        try {
            Set<Id> accountIds = new Set<Id>();
            Set<Id> contactIds = new Set<Id>();

            if (newRecords != null) {
                for (At_Risk__c risk : newRecords) {
                    if (risk.Account__c != null) accountIds.add(risk.Account__c);
                    if (risk.Contact__c != null) contactIds.add(risk.Contact__c);
                }
            }

            if (oldRecords != null) {
                for (At_Risk__c risk : oldRecords) {
                    if (risk.Account__c != null) accountIds.add(risk.Account__c);
                    if (risk.Contact__c != null) contactIds.add(risk.Contact__c);
                }
            }

            if (!contactIds.isEmpty()) {
                for (Contact con : [SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds AND AccountId != null]) accountIds.add(con.AccountId);
            }

            Set<Id> allAccountIds = new Set<Id>();
            allAccountIds.addAll(accountIds);
            Map<Id, Id> contactAccountMap = new Map<Id, Id>();

            if (!contactIds.isEmpty()) {
                for (Contact con : [SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds]) {
                    if (con.AccountId != null) {
                        contactAccountMap.put(con.Id, con.AccountId);
                        allAccountIds.add(con.AccountId);
                    }
                }
            }

            Set<Id> allContactIds = new Set<Id>();

            if (!allAccountIds.isEmpty()) {
                for (Contact con : [SELECT Id FROM Contact WHERE AccountId IN :allAccountIds]) allContactIds.add(con.Id);
            }

            Map<Id, String> contactRisk = new Map<Id, String>();
            Map<Id, String> accountRisk = new Map<Id, String>();

            for (At_Risk__c risk : [SELECT Id, Account__c, Contact__c, Risk_Level__c, IsActive__c FROM At_Risk__c WHERE IsActive__c = true AND (Account__c IN :allAccountIds OR Contact__c IN :allContactIds)]) {
                if (String.isBlank(risk.Risk_Level__c)) continue;

                Integer riskPriority = risk.Risk_Level__c == 'High' ? 3 : risk.Risk_Level__c == 'Medium' ? 2 : risk.Risk_Level__c == 'Low' ? 1 : 0;

                if (risk.Contact__c != null) {
                    Integer existingPriority = contactRisk.containsKey(risk.Contact__c) ? (contactRisk.get(risk.Contact__c) == 'High' ? 3 : contactRisk.get(risk.Contact__c) == 'Medium' ? 2 : contactRisk.get(risk.Contact__c) == 'Low' ? 1 : 0) : 0;
                    if (!contactRisk.containsKey(risk.Contact__c) || riskPriority > existingPriority) contactRisk.put(risk.Contact__c, risk.Risk_Level__c);
                }

                if (risk.Account__c != null) {
                    Integer existingPriority = accountRisk.containsKey(risk.Account__c) ? (accountRisk.get(risk.Account__c) == 'High' ? 3 : accountRisk.get(risk.Account__c) == 'Medium' ? 2 : accountRisk.get(risk.Account__c) == 'Low' ? 1 : 0) : 0;
                    if (!accountRisk.containsKey(risk.Account__c) || riskPriority > existingPriority) accountRisk.put(risk.Account__c, risk.Risk_Level__c);
                }

                if (risk.Contact__c != null && contactAccountMap.containsKey(risk.Contact__c)) {
                    Id parentAccountId = contactAccountMap.get(risk.Contact__c);
                    Integer existingPriority = accountRisk.containsKey(parentAccountId) ? (accountRisk.get(parentAccountId) == 'High' ? 3 : accountRisk.get(parentAccountId) == 'Medium' ? 2 : accountRisk.get(parentAccountId) == 'Low' ? 1 : 0) : 0;
                    if (!accountRisk.containsKey(parentAccountId) || riskPriority > existingPriority) accountRisk.put(parentAccountId, risk.Risk_Level__c);
                }
            }

            List<Contact> contactsToUpdate = new List<Contact>();

            if (!allContactIds.isEmpty()) {
                for (Contact con : [SELECT Id, Risk_Level__c FROM Contact WHERE Id IN :allContactIds]) {
                    String newRisk = contactRisk.containsKey(con.Id) ? contactRisk.get(con.Id) : null;
                    if (con.Risk_Level__c != newRisk) {
                        con.Risk_Level__c = newRisk;
                        contactsToUpdate.add(con);
                    }
                }
            }

            if (!contactsToUpdate.isEmpty()) update contactsToUpdate;

            List<Account> accountsToUpdate = new List<Account>();

            if (!allAccountIds.isEmpty()) {
                for (Account acc : [SELECT Id, Risk_Level__c FROM Account WHERE Id IN :allAccountIds]) {
                    String newRisk = accountRisk.containsKey(acc.Id) ? accountRisk.get(acc.Id) : null;
                    if (acc.Risk_Level__c != newRisk) {
                        acc.Risk_Level__c = newRisk;
                        accountsToUpdate.add(acc);
                    }
                }
            }

            if (!accountsToUpdate.isEmpty()) update accountsToUpdate;
        } finally {
            isRunning = false;
        }
    }
}