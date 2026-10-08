@IsTest
private class AtApprovalCommissionHandlerTest {

    /*
     * Creates a test Account.
     */
    private static Account createAccount(String state) {
        Account acc = new Account(
            Name = 'Test Commission Account',
            ShippingState = state
        );

        insert acc;
        return acc;
    }

    /*
     * Creates a test User that can be used as the CCF Agent / Member.
     *
     * Uses the current test-running user so we do not need to create
     * another User unless the lookup requires a specific User record.
     */
    private static Id getTestUserId() {
        return UserInfo.getUserId();
    }

    /*
     * Creates an Account Team Approval record.
     */
    private static Account_Team_Approval__c createApproval(
        Id accountId,
        String addRole,
        Id addMember,
        String removeRole,
        Id removeMember,
        String status,
        Date startDate,
        Date endDate,
        Date decisionDate
    ) {
        Account_Team_Approval__c approval = new Account_Team_Approval__c();

        approval.AccountId__c = accountId;
        approval.Status__c = status;
        approval.Sales_Operation_Decision_Date__c = decisionDate;

        approval.Add_Role__c = addRole;
        approval.Add_Member__c = addMember;
        approval.CCF_Start_Date__c = startDate;
        approval.Add_Service_Line__c = 'Depositions';

        approval.Remove_Role__c = removeRole;
        approval.Remove_Member__c = removeMember;
        approval.CCF_End_Date__c = endDate;

        approval.Comments__c = 'Test Commission History';

        return approval;
    }


    @IsTest
    static void testCreateCommissionHistoryForAdd_CA() {

        Account acc = createAccount('California');

        Id testUserId = getTestUserId();

        Account_Team_Approval__c oldApproval = createApproval(
            acc.Id,
            'AE',
            testUserId,
            null,
            null,
            'In Review',
            Date.today(),
            null,
            null
        );

        Account_Team_Approval__c newApproval = oldApproval.clone(
            false,
            true,
            false,
            false
        );

        newApproval.Id = oldApproval.Id;
        newApproval.Status__c = 'Approved';
        newApproval.Sales_Operation_Decision_Date__c = Date.today();

        Map<Id, Account_Team_Approval__c> oldMap =
            new Map<Id, Account_Team_Approval__c>{
                oldApproval.Id => oldApproval
            };

        Test.startTest();

        AtApprovalCommissionHandler.processApprovals(
            new List<Account_Team_Approval__c>{ newApproval },
            oldMap
        );

        Test.stopTest();

        List<Commission_History__c> histories = [
            SELECT
                Id,
                Account__c,
                CCF_Agent__c,
                Agent_Role__c,
                Role_Start_Date__c,
                Role_End_Date__c,
                Service_Line__c,
                Comments__c,
                Territory__c
            FROM Commission_History__c
            WHERE Account__c = :acc.Id
        ];

        System.assertEquals(
            1,
            histories.size(),
            'A Commission History record should be created.'
        );

        Commission_History__c history = histories[0];

        System.assertEquals(
            acc.Id,
            history.Account__c,
            'Account should be copied from the approval.'
        );

        System.assertEquals(
            testUserId,
            history.CCF_Agent__c,
            'CCF Agent should be copied from Add Member.'
        );

        System.assertEquals(
            'AE',
            history.Agent_Role__c,
            'Agent Role should be copied from Add Role.'
        );

        System.assertEquals(
            Date.today(),
            history.Role_Start_Date__c,
            'Role Start Date should be copied from CCF Start Date.'
        );

   //     System.assertEquals(
     //       'Test Service Line',
       //     history.Service_Line__c,
         //   'Service Line should be copied from Add Service Line.'
       // );

        System.assertEquals(
            'Test Commission History',
            history.Comments__c,
            'Comments should be copied from the approval.'
        );

        /*
         * If StateTerritory__mdt contains:
         * CA -> FRE;LAX;RIV;SAC;SAN;SFO;SJC;SNA
         *
         * then Territory__c should be populated.
         *
         * We only assert that it is populated because the actual
         * Custom Metadata value belongs to the org configuration.
         */
        System.assert(
            String.isNotBlank(history.Territory__c),
            'Territory should be populated for California.'
        );
    }

/*
    @IsTest
    static void testCreateCommissionHistoryForAdd_AZ() {

        Account acc = createAccount('AZ');

        Id testUserId = getTestUserId();

        Account_Team_Approval__c oldApproval = createApproval(
            acc.Id,
            'AM',
            testUserId,
            null,
            null,
            'In Review',
            Date.today(),
            null,
            null
        );

        Account_Team_Approval__c newApproval = oldApproval.clone(
            false,
            true,
            false,
            false
        );

        newApproval.Id = oldApproval.Id;
        newApproval.Status__c = 'Approved';
        newApproval.Sales_Operation_Decision_Date__c = Date.today();

        Map<Id, Account_Team_Approval__c> oldMap =
            new Map<Id, Account_Team_Approval__c>{
                oldApproval.Id => oldApproval
            };

        Test.startTest();

        AtApprovalCommissionHandler.processApprovals(
            new List<Account_Team_Approval__c>{ newApproval },
            oldMap
        );

        Test.stopTest();

        List<Commission_History__c> histories = [
            SELECT
                Id,
                Agent_Role__c,
                Territory__c
            FROM Commission_History__c
            WHERE Account__c = :acc.Id
        ];

        System.assertEquals(
            1,
            histories.size(),
            'A Commission History record should be created for Arizona.'
        );

        System.assertEquals(
            'AM',
            histories[0].Agent_Role__c
        );

        System.assert(
            String.isNotBlank(histories[0].Territory__c),
            'Territory should be populated for Arizona when metadata exists.'
        );
    }

*/
    @IsTest
    static void testCreateCommissionHistoryForAdd_NV() {

        Account acc = createAccount('Nevada');

        Id testUserId = getTestUserId();

        Account_Team_Approval__c oldApproval = createApproval(
            acc.Id,
            'BDR',
            testUserId,
            null,
            null,
            'In Review',
            Date.today(),
            null,
            null
        );

        Account_Team_Approval__c newApproval = oldApproval.clone(
            false,
            true,
            false,
            false
        );

        newApproval.Id = oldApproval.Id;
        newApproval.Status__c = 'Approved';
        newApproval.Sales_Operation_Decision_Date__c = Date.today();

        Map<Id, Account_Team_Approval__c> oldMap =
            new Map<Id, Account_Team_Approval__c>{
                oldApproval.Id => oldApproval
            };

        Test.startTest();

        AtApprovalCommissionHandler.processApprovals(
            new List<Account_Team_Approval__c>{ newApproval },
            oldMap
        );

        Test.stopTest();

        List<Commission_History__c> histories = [
            SELECT
                Id,
                Agent_Role__c,
                Territory__c
            FROM Commission_History__c
            WHERE Account__c = :acc.Id
        ];

        System.assertEquals(
            1,
            histories.size()
        );

        System.assertEquals(
            'BDR',
            histories[0].Agent_Role__c
        );

        System.assert(
            String.isNotBlank(histories[0].Territory__c),
            'Territory should be populated for Nevada when metadata exists.'
        );
    }


    @IsTest
    static void testUpdateCommissionHistoryForRemoval() {

        Account acc = createAccount('California');

        Id testUserId = getTestUserId();

        /*
         * Existing open Commission History.
         */
        Commission_History__c existingHistory =
            new Commission_History__c(
                Account__c = acc.Id,
                CCF_Agent__c = testUserId,
                Agent_Role__c = 'AE',
                Role_Start_Date__c = Date.today().addDays(-30)
            );

        insert existingHistory;

        Account_Team_Approval__c oldApproval = createApproval(
            acc.Id,
            null,
            null,
            'AE',
            testUserId,
            'In Review',
            null,
            null,
            null
        );

        Account_Team_Approval__c newApproval = oldApproval.clone(
            false,
            true,
            false,
            false
        );

        newApproval.Id = oldApproval.Id;
        newApproval.Status__c = 'Approved';
        newApproval.Sales_Operation_Decision_Date__c = Date.today();
        newApproval.CCF_End_Date__c = Date.today();

        Map<Id, Account_Team_Approval__c> oldMap =
            new Map<Id, Account_Team_Approval__c>{
                oldApproval.Id => oldApproval
            };

        Test.startTest();

        AtApprovalCommissionHandler.processApprovals(
            new List<Account_Team_Approval__c>{ newApproval },
            oldMap
        );

        Test.stopTest();

        Commission_History__c updatedHistory = [
            SELECT
                Id,
                Role_Start_Date__c,
                Role_End_Date__c,
                Agent_Role__c,
                CCF_Agent__c,
                Account__c
            FROM Commission_History__c
            WHERE Id = :existingHistory.Id
        ];

        System.assertEquals(
            Date.today(),
            updatedHistory.Role_End_Date__c,
            'Role End Date should be populated from CCF End Date.'
        );

        System.assertEquals(
            'AE',
            updatedHistory.Agent_Role__c
        );

        System.assertEquals(
            testUserId,
            updatedHistory.CCF_Agent__c
        );

        System.assertEquals(
            acc.Id,
            updatedHistory.Account__c
        );
    }


    @IsTest
    static void testNonEligibleStatusDoesNotCreateHistory() {

        Account acc = createAccount('California');

        Id testUserId = getTestUserId();

        Account_Team_Approval__c oldApproval = createApproval(
            acc.Id,
            'AE',
            testUserId,
            null,
            null,
            'In Review',
            Date.today(),
            null,
            null
        );

        Account_Team_Approval__c newApproval = oldApproval.clone(
            false,
            true,
            false,
            false
        );

        newApproval.Id = oldApproval.Id;

        /*
         * Status does not change to Approved.
         */
        newApproval.Status__c = 'In Review';
        newApproval.Sales_Operation_Decision_Date__c = Date.today();

        Map<Id, Account_Team_Approval__c> oldMap =
            new Map<Id, Account_Team_Approval__c>{
                oldApproval.Id => oldApproval
            };

        Test.startTest();

        AtApprovalCommissionHandler.processApprovals(
            new List<Account_Team_Approval__c>{ newApproval },
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Commission_History__c
                WHERE Account__c = :acc.Id
            ],
            'No Commission History should be created when status is not changed to Approved.'
        );
    }


    @IsTest
    static void testDecisionDateAlreadyExistsDoesNotCreateHistory() {

        Account acc = createAccount('California');

        Id testUserId = getTestUserId();

        Date existingDecisionDate = Date.today().addDays(-1);

        Account_Team_Approval__c oldApproval = createApproval(
            acc.Id,
            'AE',
            testUserId,
            null,
            null,
            'In Review',
            Date.today(),
            null,
            existingDecisionDate
        );

        Account_Team_Approval__c newApproval = oldApproval.clone(
            false,
            true,
            false,
            false
        );

        newApproval.Id = oldApproval.Id;
        newApproval.Status__c = 'Approved';

        /*
         * Decision date was already populated on old record.
         */
        newApproval.Sales_Operation_Decision_Date__c = existingDecisionDate;

        Map<Id, Account_Team_Approval__c> oldMap =
            new Map<Id, Account_Team_Approval__c>{
                oldApproval.Id => oldApproval
            };

        Test.startTest();

        AtApprovalCommissionHandler.processApprovals(
            new List<Account_Team_Approval__c>{ newApproval },
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Commission_History__c
                WHERE Account__c = :acc.Id
            ],
            'No Commission History should be created when the decision date was already populated.'
        );
    }


    @IsTest
    static void testNonCommissionableRoleDoesNotCreateHistory() {

        Account acc = createAccount('California');

        Id testUserId = getTestUserId();

        Account_Team_Approval__c oldApproval = createApproval(
            acc.Id,
            'NON_COMM_ROLE',
            testUserId,
            null,
            null,
            'In Review',
            Date.today(),
            null,
            null
        );

        Account_Team_Approval__c newApproval = oldApproval.clone(
            false,
            true,
            false,
            false
        );

        newApproval.Id = oldApproval.Id;
        newApproval.Status__c = 'Approved';
        newApproval.Sales_Operation_Decision_Date__c = Date.today();

        Map<Id, Account_Team_Approval__c> oldMap =
            new Map<Id, Account_Team_Approval__c>{
                oldApproval.Id => oldApproval
            };

        Test.startTest();

        AtApprovalCommissionHandler.processApprovals(
            new List<Account_Team_Approval__c>{ newApproval },
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Commission_History__c
                WHERE Account__c = :acc.Id
            ],
            'No Commission History should be created for a non-commissionable role.'
        );
    }


    @IsTest
    static void testRemovalWithoutMatchingHistory() {

        Account acc = createAccount('California');

        Id testUserId = getTestUserId();

        Account_Team_Approval__c oldApproval = createApproval(
            acc.Id,
            null,
            null,
            'AE',
            testUserId,
            'In Review',
            null,
            Date.today(),
            null
        );

        Account_Team_Approval__c newApproval = oldApproval.clone(
            false,
            true,
            false,
            false
        );

        newApproval.Id = oldApproval.Id;
        newApproval.Status__c = 'Approved';
        newApproval.Sales_Operation_Decision_Date__c = Date.today();

        Map<Id, Account_Team_Approval__c> oldMap =
            new Map<Id, Account_Team_Approval__c>{
                oldApproval.Id => oldApproval
            };

        Test.startTest();

        AtApprovalCommissionHandler.processApprovals(
            new List<Account_Team_Approval__c>{ newApproval },
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Commission_History__c
                WHERE Account__c = :acc.Id
            ],
            'No Commission History should be created when there is no existing history to close.'
        );
    }


    @IsTest
    static void testNullAndEmptyInput() {

        Test.startTest();

        /*
         * Null list.
         */
        AtApprovalCommissionHandler.processApprovals(
            null,
            new Map<Id, Account_Team_Approval__c>()
        );

        /*
         * Empty list.
         */
        AtApprovalCommissionHandler.processApprovals(
            new List<Account_Team_Approval__c>(),
            new Map<Id, Account_Team_Approval__c>()
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Commission_History__c],
            'No Commission History records should be created.'
        );
    }
}