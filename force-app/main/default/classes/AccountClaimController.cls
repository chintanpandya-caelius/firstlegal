public without sharing class AccountClaimController {

    @AuraEnabled
    public static void claimAccount(Id accountId) {

        Account acc = [
            SELECT Id,
                   Account_Assigned_User__c,
                   Account_Status__c,
                   Account_Claimed_Date__c,
                   Is_Claimed_by_Another_User__c 
            FROM Account
            WHERE Id = :accountId
            FOR UPDATE
        ];

        // Already claimed by another user
        if (acc.Account_Assigned_User__c != null) {
            if (acc.Account_Assigned_User__c != UserInfo.getUserId()) {
                throw new AuraHandledException(
                    'This Account has already been claimed by another user.'
                );
            }
            return; // Already claimed by the current user
        }

        // Assign current user
        acc.Account_Assigned_User__c = UserInfo.getUserId();
        acc.Account_Claimed_Date__c = System.now();
        acc.Account_Status__c = 'Completed';
       acc.Is_Claimed_by_Another_User__c = true; // Set your flag field if applicable
        update acc;
    }
}