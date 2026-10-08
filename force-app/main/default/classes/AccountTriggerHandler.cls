public with sharing class AccountTriggerHandler {

    public static void handleBeforeUpdate(List<Account> newAccounts, Map<Id, Account> oldAccountMap) {
        Id currentUserId = UserInfo.getUserId();

        for (Account newAcc : newAccounts) {
            Account oldAcc = oldAccountMap.get(newAcc.Id);

            // 1. Check if the account was ALREADY claimed before this edit operation
            if (oldAcc.Account_Assigned_User__c != null) {
                
                // 2. Block the update if the editing user is NOT the assigned user
                if (oldAcc.Account_Assigned_User__c != currentUserId) {
                    newAcc.addError('This Account has been claimed by another user and cannot be edited.');
                }
            }
        }
    }
}