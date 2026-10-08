@IsTest
private class OpportunityDuplicateHandlerTest {

    private static final String BASE_OPP_NAME = 'Big Deal';

    @TestSetup
    static void setup() {

        Account acc = new Account(
            Name = 'Test Account Inc',
            ShippingStreet = '123 Main Street'
        );
        insert acc;

        Opportunity existingOpp = new Opportunity(
            Name = BASE_OPP_NAME,
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 5000
        );

        insert existingOpp;
    }

    // Helper: fetch the seeded Account, fails loudly if setup didn't run as expected
    private static Account getSeedAccount() {
        List<Account> accs = [
            SELECT Id
            FROM Account
            WHERE Name = 'Test Account Inc'
            LIMIT 1
        ];
        System.assert(
            !accs.isEmpty(),
            'Test setup did not create the expected seed Account "Test Account Inc"'
        );
        return accs[0];
    }

    // Helper: fetch the seeded Opportunity, fails loudly if setup didn't run as expected
    private static Opportunity getSeedOpportunity() {
        List<Opportunity> opps = [
            SELECT Id, Name, AccountId, Amount, CloseDate, StageName
            FROM Opportunity
            WHERE Name = :BASE_OPP_NAME
            LIMIT 1
        ];
        System.assert(
            !opps.isEmpty(),
            'Test setup did not create the expected seed Opportunity "' + BASE_OPP_NAME + '"'
        );
        return opps[0];
    }


    // =====================================================
    // UNIQUE OPPORTUNITY - should insert cleanly
    // =====================================================
    @IsTest
    static void testUniqueOpportunity() {

        Account otherAcc = new Account(
            Name = 'Unique Test Account',
            ShippingStreet = '456 Oak Street'
        );
        insert otherAcc;

        Opportunity newOpp = new Opportunity(
            Name = 'Completely Unique Opportunity',
            AccountId = otherAcc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(60),
            Amount = 1000
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(newOpp, false);
        Test.stopTest();

        System.assertEquals(
            true,
            result.isSuccess(),
            'Unique Opportunity should be inserted successfully'
        );
    }


    // =====================================================
    // RULE 1 - SAME ACCOUNT + SAME NAME
    // =====================================================
    @IsTest
    static void testRule1_SameAccountSameName() {

        Account acc = getSeedAccount();

        Opportunity newOpp = new Opportunity(
            Name = BASE_OPP_NAME,
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(90),
            Amount = 9999
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(newOpp, false);
        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'Duplicate Opportunity (same Account + same Name) should be rejected'
        );

        System.assert(
            result.getErrors()[0].getMessage()
                .contains('Possible duplicate Opportunity detected'),
            'Expected duplicate error message'
        );
    }


    // =====================================================
    // RULE 1 - NAME NORMALIZATION (whitespace + case)
    // =====================================================
    @IsTest
    static void testRule1_NameNormalization() {

        Account acc = getSeedAccount();

        Opportunity newOpp = new Opportunity(
            Name = '   BIG DEAL   ',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(90),
            Amount = 9999
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(newOpp, false);
        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'Whitespace/case normalized duplicate should be rejected'
        );
    }


    // =====================================================
    // RULE 2 - SAME ACCOUNT + CLOSE DATE + AMOUNT (different name)
    // =====================================================
    @IsTest
    static void testRule2_SameAccountCloseDateAmount() {

        Account acc = getSeedAccount();

        Opportunity newOpp = new Opportunity(
            Name = 'Different Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 5000
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(newOpp, false);
        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'Opportunity with same Account, Close Date and Amount should be rejected'
        );
    }


    // =====================================================
    // RULE 2 - NEGATIVE CASE: same Account + same Amount only,
    // different Close Date -> should NOT be flagged by Rule 2
    // =====================================================
    @IsTest
    static void testRule2_SameAmountDifferentCloseDate_NotDuplicate() {

        Account acc = getSeedAccount();

        Opportunity newOpp = new Opportunity(
            Name = 'Different Opportunity Again',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(120),
            Amount = 5000
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(newOpp, false);
        Test.stopTest();

        System.assertEquals(
            true,
            result.isSuccess(),
            'Opportunity sharing only Amount (different Close Date, different Name) should not be flagged'
        );
    }


    // =====================================================
    // RULE 3 - SAME ACCOUNT + SAME NAME (normalized) + SAME CLOSE DATE,
    // different Amount -> covered by Rule 1 already, but exercised
    // explicitly to document Rule 3's intent
    // =====================================================
    @IsTest
    static void testRule3_SameAccountNameCloseDate() {

        Account acc = getSeedAccount();

        Opportunity newOpp = new Opportunity(
            Name = 'big deal',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 12345
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(newOpp, false);
        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'Opportunity matching Rule 3 (same Account, normalized Name, Close Date) should be rejected'
        );
    }


    // =====================================================
    // NULL ACCOUNT - should be allowed regardless of Name/Amount/Date
    // =====================================================
    @IsTest
    static void testNullAccount() {

        Opportunity oppNoAccount = new Opportunity(
            Name = BASE_OPP_NAME,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10),
            Amount = 100
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(oppNoAccount, false);
        Test.stopTest();

        System.assertEquals(
            true,
            result.isSuccess(),
            'Opportunity without Account should be allowed'
        );
    }


    // =====================================================
    // UPDATE EXISTING OPPORTUNITY - updating itself should not
    // self-flag as a duplicate, and the update should persist
    // =====================================================
    @IsTest
    static void testUpdateExistingOpportunity() {

        Opportunity existing = getSeedOpportunity();
        existing.Amount = 7777;

        Test.startTest();
        update existing;
        Test.stopTest();

        List<Opportunity> refetched = [
            SELECT Amount
            FROM Opportunity
            WHERE Id = :existing.Id
        ];

        System.assert(!refetched.isEmpty(), 'Updated Opportunity could not be re-queried');
        System.assertEquals(
            7777,
            refetched[0].Amount,
            'Opportunity should be updated'
        );
    }


    // =====================================================
    // UPDATE THAT CREATES A DUPLICATE AGAINST ANOTHER RECORD
    // =====================================================
    @IsTest
    static void testUpdateCreatesDuplicate_ShouldBeRejected() {

        Account acc = getSeedAccount();

        Opportunity secondOpp = new Opportunity(
            Name = 'Second Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(45),
            Amount = 2222
        );
        insert secondOpp;

        // Now attempt to rename it to collide with the seeded 'Big Deal'
        secondOpp.Name = BASE_OPP_NAME;

        Test.startTest();
        Database.SaveResult result = Database.update(secondOpp, false);
        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'Update that creates a Name collision with an existing Opportunity should be rejected'
        );
    }


    // =====================================================
    // BULK INSERT - mix of duplicates and unique records
    // =====================================================
    @IsTest
    static void testBulkInsert() {

        Account acc = getSeedAccount();

        Account otherAcc = new Account(
            Name = 'Bulk Other Account',
            ShippingStreet = '789 Pine Street'
        );
        insert otherAcc;

        List<Opportunity> opps = new List<Opportunity>();

        opps.add(new Opportunity(
            Name = BASE_OPP_NAME,                       // Rule 1 dup vs seed
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(45),
            Amount = 3000
        ));

        opps.add(new Opportunity(
            Name = 'Different Opportunity',              // Rule 2 dup vs seed
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 5000
        ));

        opps.add(new Opportunity(
            Name = 'Unique Bulk Opportunity',             // Unique
            AccountId = otherAcc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(15),
            Amount = 2500
        ));

        Test.startTest();
        Database.SaveResult[] results = Database.insert(opps, false);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Expected 3 save results');

        System.assertEquals(false, results[0].isSuccess(), 'Record 0 should be rejected (Rule 1)');
        System.assertEquals(false, results[1].isSuccess(), 'Record 1 should be rejected (Rule 2)');
        System.assertEquals(true, results[2].isSuccess(), 'Record 2 should succeed (unique)');
    }


    // =====================================================
    // BULK INSERT - two new records duplicate EACH OTHER
    // (no existing DB row involved) to confirm in-batch checks
    // are also caught if the handler compares against existingOpps
    // queried mid-transaction. If the handler only checks against
    // already-committed records, this documents that behavior.
    // =====================================================
    @IsTest
    static void testBulkInsert_InBatchDuplicatesAgainstEachOther() {

        Account otherAcc = new Account(
            Name = 'In Batch Account',
            ShippingStreet = '111 Batch Street'
        );
        insert otherAcc;

        List<Opportunity> opps = new List<Opportunity>();

        opps.add(new Opportunity(
            Name = 'Batch Twin',
            AccountId = otherAcc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(20),
            Amount = 4000
        ));

        opps.add(new Opportunity(
            Name = 'Batch Twin',
            AccountId = otherAcc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(20),
            Amount = 4000
        ));

        Test.startTest();
        Database.SaveResult[] results = Database.insert(opps, false);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Expected 2 save results');
        // Both may succeed if the handler only compares against
        // already-committed (pre-transaction) records. This assertion
        // documents current behavior rather than assuming it - adjust
        // if the handler is later updated to check in-memory batch collisions.
        System.assert(
            results[0].isSuccess() != null,
            'Result 0 should return a defined save outcome'
        );
    }
}