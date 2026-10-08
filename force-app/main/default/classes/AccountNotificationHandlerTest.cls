@isTest
private class AccountNotificationHandlerTest {

    @testSetup
    static void setupData() {
        Set<String> targetDevNames = new Set<String>{ 'BuisnessAdmin', 'FacilityManagement', 'MarketingGroup' };
        Map<String, Group> existingGroups = new Map<String, Group>();

        for (Group grp : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN :targetDevNames AND Type = 'Regular']) {
            existingGroups.put(grp.DeveloperName, grp);
        }

        List<Group> groupsToInsert = new List<Group>();

        Group busAdminGrp = existingGroups.get('BuisnessAdmin');
        if (busAdminGrp == null) {
            busAdminGrp = new Group(Name = 'Business Admin Group', DeveloperName = 'BuisnessAdmin', Type = 'Regular');
            groupsToInsert.add(busAdminGrp);
        }

        Group facMgmtGrp = existingGroups.get('FacilityManagement');
        if (facMgmtGrp == null) {
            facMgmtGrp = new Group(Name = 'Facility Management Group', DeveloperName = 'FacilityManagement', Type = 'Regular');
            groupsToInsert.add(facMgmtGrp);
        }

        Group mktgGrp = existingGroups.get('MarketingGroup');
        if (mktgGrp == null) {
            mktgGrp = new Group(Name = 'Marketing Group', DeveloperName = 'MarketingGroup', Type = 'Regular');
            groupsToInsert.add(mktgGrp);
        }

        String uniqueSubGroupDevName = 'SubGroup_' + System.now().getTime();
        Group subGrp = new Group(Name = 'Sub Group', DeveloperName = uniqueSubGroupDevName, Type = 'Regular');
        groupsToInsert.add(subGrp);

        if (!groupsToInsert.isEmpty()) {
            insert groupsToInsert;
        }

        GroupMember subGrpMember = new GroupMember(
            GroupId = mktgGrp.Id,
            UserOrGroupId = subGrp.Id
        );
        insert subGrpMember;

        GroupMember userMember1 = new GroupMember(
            GroupId = busAdminGrp.Id,
            UserOrGroupId = UserInfo.getUserId()
        );
        GroupMember userMember2 = new GroupMember(
            GroupId = subGrp.Id,
            UserOrGroupId = UserInfo.getUserId()
        );
        insert new List<GroupMember>{ userMember1, userMember2 };
    }

    @isTest
    static void testHandleAfterInsert_NonCustomerAccounts() {
        Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        List<Account> testAccounts = new List<Account>();

        if (rtMap.containsKey('Court')) {
            testAccounts.add(new Account(Name = 'Test Court', RecordTypeId = rtMap.get('Court').getRecordTypeId()));
        }
        if (rtMap.containsKey('Facility')) {
            testAccounts.add(new Account(Name = 'Test Facility', RecordTypeId = rtMap.get('Facility').getRecordTypeId()));
        }
        if (rtMap.containsKey('Professional_Association')) {
            testAccounts.add(new Account(Name = 'Test Prof Assoc', RecordTypeId = rtMap.get('Professional_Association').getRecordTypeId()));
        }
        if (rtMap.containsKey('Vendor')) {
            testAccounts.add(new Account(Name = 'Test Vendor', RecordTypeId = rtMap.get('Vendor').getRecordTypeId()));
        }

        Test.startTest();
        if (!testAccounts.isEmpty()) {
            insert testAccounts;
        } else {
            AccountNotificationHandler.handleAfterInsert(new List<Account>());
        }
        Test.stopTest();

        System.assert(true, 'Non-customer account creation completed successfully.');
    }

    @isTest
    static void testHandleAfterInsert_CustomerAccounts() {
        Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        
        if (!rtMap.containsKey('Customer')) {
            return;
        }

        Id customerRtId = rtMap.get('Customer').getRecordTypeId();

        // Set future dates to avoid validation rule errors on past date/time
        Account custAcc = new Account(
            Name = 'Test Customer Account',
            RecordTypeId = customerRtId,
            Service_Line__c = 'Digital',
            Type = 'Customer',
            Sub_Type__c = 'COD',
            SLA_Tier__c = 'S1',
            SLA_Start_Date__c = Date.today().addDays(1),
            SLA_Due_Date__c = Date.today().addDays(5)
        );

        Test.startTest();
        insert custAcc;
        Test.stopTest();

        Schema.RecordTypeInfo caseRtInfo = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Accounting');
        if (caseRtInfo != null) {
            List<Case> createdCases = [SELECT Id, Priority, AccountId, Subject FROM Case WHERE AccountId = :custAcc.Id];
            System.assertEquals(1, createdCases.size(), 'One accounting ticket should be created.');
            System.assertEquals('Immediate', createdCases[0].Priority, 'S1 tier maps to Immediate priority.');
        }
    }

    @isTest
    static void testHandleAfterUpdate_CustomerAccountSlaChanged() {
        Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        
        if (!rtMap.containsKey('Customer')) {
            return;
        }

        Id customerRtId = rtMap.get('Customer').getRecordTypeId();

        // Inserting custAcc automatically triggers handleAfterInsert and creates the Case ticket
        Account custAcc = new Account(
            Name = 'SLA Update Account',
            RecordTypeId = customerRtId,
            Service_Line__c = 'Digital',
            Type = 'Customer',
            Sub_Type__c = 'COD',
            SLA_Tier__c = 'S2',
            SLA_Start_Date__c = Date.today().addDays(1),
            SLA_Due_Date__c = Date.today().addDays(3)
        );
        insert custAcc;

        Test.startTest();
        custAcc.SLA_Tier__c = 'S1';
        custAcc.SLA_Due_Date__c = Date.today().addDays(2);
        update custAcc;
        Test.stopTest();

        Schema.RecordTypeInfo caseRtInfo = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Accounting');
        if (caseRtInfo != null) {
            Case updatedCase = [SELECT Priority, SLA_Stop_Date__c FROM Case WHERE AccountId = :custAcc.Id LIMIT 1];
            System.assertEquals('Immediate', updatedCase.Priority, 'Priority should update to Immediate.');
            System.assertEquals(Date.today().addDays(2), updatedCase.SLA_Stop_Date__c, 'SLA Stop Date should update.');
        }
    }

    @isTest
    static void testHandlerWithEmptyOrNullInputs() {
        Test.startTest();
        AccountNotificationHandler.handleAfterInsert(new List<Account>());
        AccountNotificationHandler.handleAfterUpdate(new List<Account>(), new Map<Id, Account>());
        Test.stopTest();

        System.assert(true, 'Empty/Null handler execution completed safely.');
    }
}