/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Test class for AccountGlobalIdMuleSoftService, AccountGlobalIdController
* @Story Number : 9751
*/
@IsTest
private class AccountGlobalIdMuleSoftServiceTest {

    private class SuccessfulCalloutMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(
                '{' +
                    '"response": {' +
                        '"accountId": "GLOBAL-12345"' +
                    '}' +
                '}'
            );

            return res;
        }
    }

    private class NoAccountIdCalloutMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(
                '{' +
                    '"response": {}' +
                '}'
            );

            return res;
        }
    }

    private class FailedCalloutMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(
                '{' +
                    '"error": "Internal Server Error"' +
                '}'
            );

            return res;
        }
    }

    @IsTest
    static void testCreateAccountWithoutParent() {

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Test.setMock(HttpCalloutMock.class,new SuccessfulCalloutMock());

        Test.startTest();
        AccountGlobalIdMuleSoftService.createAccount(acc.Id);
        AccountGlobalIdController.generateGlobalAccountId(acc.Id);
        Test.stopTest();

        Account updatedAccount = [
            SELECT Id, Name, accountID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
    }

    @IsTest
    static void testCreateAccountWithParent() {

        Account parentAccount = new Account(
            Name = 'Test Account',
            accountID__c = 'PARENT-123'
        );

        insert parentAccount;

        Account childAccount = new Account(
            Name = 'Test Account',
            ParentId = parentAccount.Id
        );

        insert childAccount;

        Test.setMock(HttpCalloutMock.class,new SuccessfulCalloutMock());

        Test.startTest();
        AccountGlobalIdMuleSoftService.createAccount(childAccount.Id);
        Test.stopTest();

        Account updatedAccount = [
            SELECT Id, Name, ParentId, accountID__c
            FROM Account
            WHERE Id = :childAccount.Id
        ];
    }
    
    @IsTest
    static void testResponseWithoutAccountId() {

        Account acc = new Account(
            Name = 'Test No Global'
        );

        insert acc;

        Test.setMock(
            HttpCalloutMock.class,
            new NoAccountIdCalloutMock()
        );

        Test.startTest();
        AccountGlobalIdMuleSoftService.createAccount(acc.Id);
        Test.stopTest();

        Account updatedAccount = [
            SELECT Id, Name, accountID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
    }

    @IsTest
    static void testFailedCallout() {

        Account acc = new Account(
            Name = 'Test Account Failed Callout'
        );

        insert acc;

        Test.setMock(
            HttpCalloutMock.class,
            new FailedCalloutMock()
        );

        Test.startTest();
        AccountGlobalIdMuleSoftService.createAccount(acc.Id);
        Test.stopTest();

        Account updatedAccount = [
            SELECT Id, Name, accountID__c
            FROM Account
            WHERE Id = :acc.Id
        ];

    }

    @IsTest
    static void testQueueableExecution() {

        Account acc = new Account(Name = 'Test Queueable Account');
        insert acc;

        Test.setMock(
            HttpCalloutMock.class,
            new SuccessfulCalloutMock()
        );

        Test.startTest();
        System.enqueueJob(new AccountGlobalIdMuleSoftService(acc.Id));
        Test.stopTest();

        Account updatedAccount = [
            SELECT Id, accountID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
    }
}