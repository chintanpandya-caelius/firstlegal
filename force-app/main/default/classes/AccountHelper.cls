public without sharing class AccountHelper {


    public static void handleBeforeSave( List<Account> newList, Map<Id, Account> oldMap) 
    {
        AccountFcpHandler.runValidation(newList);
        AccountCustomerHandler.runValidation(newList,oldMap);
        AccountOtherRecordHandler.runValidation(newList,oldMap);
    }
}