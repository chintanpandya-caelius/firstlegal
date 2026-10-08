@IsTest
private class AccountTeamApprovalHandlerTest {

    @TestSetup
    static void setupTestData() {
        // Create Test Users
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User requester = new User(
            FirstName = 'Test',
            LastName = 'Requester',
            Email = 'requester@test.com',
            Username = 'requester_' + DateTime.now().getTime() + '@test.com',
            Alias = 'treq',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );
        
        User manager = new User(
            FirstName = 'Test',
            LastName = 'Manager',
            Email = 'manager@test.com',
            Username = 'manager_' + DateTime.now().getTime() + '@test.com',
            Alias = 'tmgr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );

        User memberToAdd = new User(
            FirstName = 'Member',
            LastName = 'ToAdd',
            Email = 'addmember@test.com',
            Username = 'addmember_' + DateTime.now().getTime() + '@test.com',
            Alias = 'tadd',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );

        User memberToRemove = new User(
            FirstName = 'Member',
            LastName = 'ToRemove',
            Email = 'removemember@test.com',
            Username = 'removemember_' + DateTime.now().getTime() + '@test.com',
            Alias = 'trem',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );

        insert new List<User>{ requester, manager, memberToAdd, memberToRemove };

        // Create Test Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Existing Account Team Member to test removal logic
        AccountTeamMember existingMember = new AccountTeamMember(
            AccountId = acc.Id,
            UserId = memberToRemove.Id,
            TeamMemberRole = 'Account Manager'
        );
        insert existingMember;
    }

    @IsTest
    static void testInsertHandler() {
        User reqUser = [SELECT Id FROM User WHERE Email = 'requester@test.com' LIMIT 1];
        User mgrUser = [SELECT Id FROM User WHERE Email = 'manager@test.com' LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Account_Team_Approval__c req = new Account_Team_Approval__c(
            AccountId__c = acc.Id,
            Type__c = 'Add',
            Requester__c = reqUser.Id,
            Reporting_Manager__c = mgrUser.Id,
            Status__c = 'New'
        );

        Test.startTest();
        insert req;
        Test.stopTest();
    }

    @IsTest
    static void testUpdateToInReview() {
        User reqUser = [SELECT Id FROM User WHERE Email = 'requester@test.com' LIMIT 1];
        User mgrUser = [SELECT Id FROM User WHERE Email = 'manager@test.com' LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Account_Team_Approval__c req = new Account_Team_Approval__c(
            AccountId__c = acc.Id,
            Type__c = 'Add',
            Requester__c = reqUser.Id,
            Reporting_Manager__c = mgrUser.Id,
            Status__c = 'New'
        );
        insert req;

        Test.startTest();
        req.Status__c = 'In Review';
        update req;
        Test.stopTest();
    }

    @IsTest
    static void testUpdateToApproved() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        User reqUser = [SELECT Id FROM User WHERE Email = 'requester@test.com' LIMIT 1];
        User addMember = [SELECT Id FROM User WHERE Email = 'addmember@test.com' LIMIT 1];
        User removeMember = [SELECT Id FROM User WHERE Email = 'removemember@test.com' LIMIT 1];

        Account_Team_Approval__c req = new Account_Team_Approval__c(
            AccountId__c = acc.Id,
            Type__c = 'Add/Remove',
            Requester__c = reqUser.Id,
            Add_Member__c = addMember.Id,
            Add_Role__c = 'Sales Rep',
            Remove_Member__c = removeMember.Id,
            Status__c = 'In Review'
        );
        insert req;

        Test.startTest();
        req.Status__c = 'Approved';
        update req;
        Test.stopTest();
    }

    @IsTest
    static void testUpdateToDeniedFromNewAndInReview() {
        User reqUser = [SELECT Id FROM User WHERE Email = 'requester@test.com' LIMIT 1];
        User mgrUser = [SELECT Id FROM User WHERE Email = 'manager@test.com' LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Account_Team_Approval__c req1 = new Account_Team_Approval__c(
            AccountId__c = acc.Id,
            Type__c = 'Add',
            Requester__c = reqUser.Id,
            Reporting_Manager__c = mgrUser.Id,
            Status__c = 'New'
        );

        Account_Team_Approval__c req2 = new Account_Team_Approval__c(
            AccountId__c = acc.Id,
            Type__c = 'Remove',
            Requester__c = reqUser.Id,
            Reporting_Manager__c = mgrUser.Id,
            Status__c = 'In Review'
        );

        insert new List<Account_Team_Approval__c>{ req1, req2 };

        Test.startTest();
        req1.Status__c = 'Denied';
        req1.Denial_Reason__c = 'Not eligible';
        
        req2.Status__c = 'Denied';
        req2.Denial_Reason__c = 'Budget constraints';

        update new List<Account_Team_Approval__c>{ req1, req2 };
        Test.stopTest();
    }
}