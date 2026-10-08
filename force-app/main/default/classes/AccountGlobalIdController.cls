/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Generate Global AccountId Helper for Account Quick Action Generate GlobalAccountId
* @Story Number : 9751
*/
public class AccountGlobalIdController {

    @AuraEnabled
    public static void generateGlobalAccountId(Id accountId) {

        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        System.enqueueJob(
            new AccountGlobalIdMuleSoftService(accountId)
        );
    }
}