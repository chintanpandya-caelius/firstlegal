public without sharing class AccountHelper {

    public static void handleBeforeSave(List<Account> newList, Map<Id, Account> oldMap) {
        for (Account acc : newList) {
            Account oldAcc = oldMap != null ? oldMap.get(acc.Id) : null;

            if (
                oldAcc != null &&
                oldAcc.Status__c == 'New' &&
                (acc.Status__c == 'Prospect' || acc.Status__c == 'Active') &&
                acc.Account_Start_Date__c == null
            ) {
                acc.Account_Start_Date__c = Date.today();
            }
        }

        AccountFcpHandler.runValidation(newList);
        AccountCustomerHandler.runValidation(newList, oldMap);
        AccountOtherRecordHandler.runValidation(newList, oldMap);
    }
}