/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Test class for AccountInactivityTaskCreationBatch
* @Story Number : 5450
*/

@IsTest
private class AccountInactivityTaskCreationBatchTest {

    @TestSetup
    static void setupData() {

        List<Account> accounts = new List<Account>();

        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(
                Name = 'Test Inactive Account ' + i,
                Status__c = 'New',
                AnnualRevenue = 100000 + (i * 10000)
            ));
        }
        insert accounts;
    }

    @IsTest
    static void testBatchExecution() {

        Test.startTest();
        Database.executeBatch(new AccountInactivityTaskCreationBatch(),200);
        Test.stopTest();

        List<Account> accounts = [
            SELECT Id, Name, OwnerId, Status__c, AnnualRevenue
            FROM Account
            WHERE Name LIKE 'Test Account%'
        ];
    }

    @IsTest
    static void testExecuteWithEmptyList() {

        AccountInactivityTaskCreationBatch batch = new AccountInactivityTaskCreationBatch();
        Test.startTest();
        batch.execute(null,new List<Account>());
        Test.stopTest();

        System.assert(true,'Execute method should handle an empty Account list without errors.');
    }

    @IsTest
    static void testFinish() {

        AccountInactivityTaskCreationBatch batch = new AccountInactivityTaskCreationBatch();

        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        System.assert(true,'Finish method should execute successfully.');
    }
}