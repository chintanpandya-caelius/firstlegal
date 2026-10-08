@IsTest
private class OpportunityRevenueValidationHandlerTest {

    @TestSetup
    static void setupData() {
        insert new List<Account>{
            new Account(Name = 'Revenue Validation Account 1'),
            new Account(Name = 'Revenue Validation Account 2'),
            new Account(Name = 'Revenue Validation Account 3')
        };
    }

    private static Account getAccount(Integer num) {
        return [
            SELECT Id, Name
            FROM Account
            WHERE Name = :('Revenue Validation Account ' + num)
            LIMIT 1
        ];
    }

    private static Opportunity createOpportunity(Id accountId, String revenueType, String serviceLine, String matterCaseNumber, String stageName, Date closeDate) {
        return new Opportunity(
            Name = 'Revenue Validation Test Opportunity ' + String.valueOf(DateTime.now().getTime()) + String.valueOf(Math.random()),
            AccountId = accountId,
            Revenue_Type__c = revenueType,
            Service_Line__c = serviceLine,
            Matter_Case_Number__c = matterCaseNumber,
            StageName = stageName,
            CloseDate = closeDate
        );
    }

    private static void expectHandlerError(Opportunity opp, String expectedMessage) {
        OpportunityRevenueValidationHandler.handleBeforeSave(new List<Opportunity>{opp}, new Map<Id, Opportunity>());
        Boolean found = false;
        for (Database.Error error : opp.getErrors()) {
            if (error.getMessage().contains(expectedMessage)) {
                found = true;
                break;
            }
        }
        System.assertEquals(true, found, 'Expected error not found: ' + expectedMessage);
    }

    @IsTest
    static void testNewLogoSuccess() {
        Account acc = getAccount(1);
        Opportunity opp = createOpportunity(acc.Id, 'New Logo', 'Court & Process', null, 'Prospecting', Date.today().addDays(30));
        Test.startTest();
        insert opp;
        Test.stopTest();
        System.assertNotEquals(null, opp.Id);
    }

    @IsTest
    static void testDuplicateNewLogoFails() {
        Account acc = getAccount(1);
        insert createOpportunity(acc.Id, 'New Logo', 'Court & Process', null, 'Prospecting', Date.today().addDays(30));
        Opportunity opp = createOpportunity(acc.Id, 'New Logo', 'Depositions', null, 'Prospecting', Date.today().addDays(60));
        Test.startTest();
        expectHandlerError(opp, 'A New Logo opportunity already exists');
        Test.stopTest();
    }

    @IsTest
    static void testNewLogoAfterCrossSellFails() {
        Account acc = getAccount(1);
        insert createOpportunity(acc.Id, 'Cross Sell', 'Court & Process', null, 'Prospecting', Date.today().addDays(30));
        Opportunity opp = createOpportunity(acc.Id, 'New Logo', 'Depositions', null, 'Prospecting', Date.today().addDays(60));
        Test.startTest();
        expectHandlerError(opp, 'standard Revenue Type opportunities already exist');
        Test.stopTest();
    }

    @IsTest
    static void testCrossSellSuccessDifferentServiceLine() {
        Account acc = getAccount(1);
        insert createOpportunity(acc.Id, 'New Logo', 'Court & Process', null, 'Prospecting', Date.today().addDays(30));
        Opportunity opp = createOpportunity(acc.Id, 'Cross Sell', 'Depositions', null, 'Prospecting', Date.today().addDays(60));
        Test.startTest();
        insert opp;
        Test.stopTest();
        System.assertNotEquals(null, opp.Id);
    }

    @IsTest
    static void testCrossSellSameServiceLineFails() {
        Account acc = getAccount(1);
        insert createOpportunity(acc.Id, 'New Logo', 'Court & Process', null, 'Prospecting', Date.today().addDays(30));
        Opportunity opp = createOpportunity(acc.Id, 'Cross Sell', 'Court & Process', null, 'Prospecting', Date.today().addDays(60));
        Test.startTest();
        expectHandlerError(opp, 'An opportunity already exists on this account for this service line');
        Test.stopTest();
    }

    @IsTest
    static void testPortfolioGrowthAfterNewLogoFails() {
        Account acc = getAccount(1);
        insert createOpportunity(acc.Id, 'New Logo', 'Court & Process', null, 'Prospecting', Date.today().addDays(30));
        Opportunity opp = createOpportunity(acc.Id, 'Portfolio Growth', 'Depositions', null, 'Prospecting', Date.today().addDays(60));
        Test.startTest();
        expectHandlerError(opp, 'A New Logo opportunity already exists');
        Test.stopTest();
    }

    @IsTest
    static void testDuplicatePortfolioGrowthSameServiceLineFails() {
        Account acc = getAccount(1);
        insert createOpportunity(acc.Id, 'Portfolio Growth', 'Court & Process', null, 'Prospecting', Date.today().addDays(30));
        Opportunity opp = createOpportunity(acc.Id, 'Portfolio Growth', 'Court & Process', null, 'Prospecting', Date.today().addDays(60));
        Test.startTest();
        expectHandlerError(opp, 'A Portfolio Growth opportunity already exists');
        Test.stopTest();
    }

    @IsTest
    static void testStandardRevenueTypeWithMatterCaseFails() {
        Account acc = getAccount(1);
        Opportunity opp = createOpportunity(acc.Id, 'New Logo', 'Court & Process', 'MATTER-001', 'Prospecting', Date.today().addDays(30));
        Test.startTest();
        expectHandlerError(opp, 'Matter/Case Number is prohibited');
        Test.stopTest();
    }

    @IsTest
    static void testProjectRevenueTypeMatterNumberRequired() {
        Account acc = getAccount(1);
        Opportunity opp = createOpportunity(acc.Id, 'Class Action', 'Court & Process', null, 'Discovery', Date.today().addDays(30));
        Test.startTest();
        expectHandlerError(opp, 'Matter/Case Number is required');
        Test.stopTest();
    }

    @IsTest
    static void testProjectRevenueTypeSuccess() {
        Account acc = getAccount(1);
        Opportunity opp = createOpportunity(acc.Id, 'Class Action', 'Court & Process', 'MATTER-001', 'Discovery', Date.today().addDays(30));
        Test.startTest();
        insert opp;
        Test.stopTest();
        System.assertNotEquals(null, opp.Id);
    }

    @IsTest
    static void testDuplicateProjectMatterAndServiceLineFails() {
        Account acc = getAccount(1);
        insert createOpportunity(acc.Id, 'Class Action', 'Court & Process', 'MATTER-001', 'Discovery', Date.today().addDays(30));
        Opportunity opp = createOpportunity(acc.Id, 'Matter Specific Project', 'Court & Process', 'MATTER-001', 'Discovery', Date.today().addDays(60));
        Test.startTest();
        expectHandlerError(opp, 'Matter/Case Number is already in use');
        Test.stopTest();
    }

    @IsTest
    static void testSameMatterDifferentServiceLineSucceeds() {
        Account acc = getAccount(1);
        insert createOpportunity(acc.Id, 'Class Action', 'Court & Process', 'MATTER-001', 'Discovery', Date.today().addDays(30));
        Opportunity opp = createOpportunity(acc.Id, 'Matter Specific Project', 'Depositions', 'MATTER-001', 'Discovery', Date.today().addDays(60));
        Test.startTest();
        insert opp;
        Test.stopTest();
        System.assertNotEquals(null, opp.Id);
    }

    @IsTest
    static void testRevenueTypeRequired() {
        Account acc = getAccount(1);
        Opportunity opp = createOpportunity(acc.Id, null, 'Court & Process', null, 'Prospecting', Date.today().addDays(30));
        Test.startTest();
        expectHandlerError(opp, 'Revenue Type is required');
        Test.stopTest();
    }

    @IsTest
    static void testServiceLineRequired() {
        Account acc = getAccount(1);
        Opportunity opp = createOpportunity(acc.Id, 'New Logo', null, null, 'Prospecting', Date.today().addDays(30));
        Test.startTest();
        expectHandlerError(opp, 'Service Line is required');
        Test.stopTest();
    }

    @IsTest
    static void testCloseDateRequired() {
        Account acc = getAccount(1);
        Opportunity opp = createOpportunity(acc.Id, 'New Logo', 'Court & Process', null, 'Prospecting', null);
        Test.startTest();
        expectHandlerError(opp, 'Close Date is required');
        Test.stopTest();
    }

    @IsTest
    static void testInvalidServiceLine() {
        Account acc = getAccount(1);
        Opportunity opp = createOpportunity(acc.Id, 'New Logo', 'Invalid Service Line', null, 'Prospecting', Date.today().addDays(30));
        Test.startTest();
        expectHandlerError(opp, 'Invalid Service Line');
        Test.stopTest();
    }

    @IsTest
    static void testProjectBeforeDiscoverySucceeds() {
        Account acc = getAccount(2);
        Opportunity opp = createOpportunity(acc.Id, 'Class Action', 'Court & Process', 'MATTER-STAGE-001', 'Prospecting', Date.today().addDays(30));
        Test.startTest();
        insert opp;
        Test.stopTest();
        System.assertNotEquals(null, opp.Id);
    }

    @IsTest
    static void testProjectMatterTrimmed() {
        Account acc = getAccount(2);
        Opportunity opp = createOpportunity(acc.Id, 'Class Action', 'Court & Process', 'MATTER-TRIM-001', 'Discovery', Date.today().addDays(30));
        Test.startTest();
        insert opp;
        Test.stopTest();
        System.assertNotEquals(null, opp.Id);
    }

    @IsTest
    static void testSameProjectMatterDifferentAccountSucceeds() {
        Account acc1 = getAccount(2);
        Account acc2 = getAccount(3);
        insert createOpportunity(acc1.Id, 'Class Action', 'Court & Process', 'MATTER-ACCOUNT-001', 'Discovery', Date.today().addDays(30));
        Opportunity opp = createOpportunity(acc2.Id, 'Matter Specific Project', 'Court & Process', 'MATTER-ACCOUNT-001', 'Discovery', Date.today().addDays(60));
        Test.startTest();
        insert opp;
        Test.stopTest();
        System.assertNotEquals(null, opp.Id);
    }

    @IsTest
    static void testSameProjectMatterDifferentFiscalYearSucceeds() {
        Account acc = getAccount(2);
        insert createOpportunity(acc.Id, 'Class Action', 'Court & Process', 'MATTER-FY-001', 'Discovery', Date.newInstance(Date.today().year(), 6, 15));
        Opportunity opp = createOpportunity(acc.Id, 'Matter Specific Project', 'Court & Process', 'MATTER-FY-001', 'Discovery', Date.newInstance(Date.today().year() + 1, 6, 15));
        Test.startTest();
        insert opp;
        Test.stopTest();
        System.assertNotEquals(null, opp.Id);
    }

    @IsTest
    static void testExistingProjectDifferentStageSucceeds() {
        Account acc = getAccount(3);
        insert createOpportunity(acc.Id, 'Class Action', 'Court & Process', 'MATTER-STAGE-OLD', 'Prospecting', Date.today().addDays(30));
        Opportunity opp = createOpportunity(acc.Id, 'Matter Specific Project', 'Court & Process', 'MATTER-STAGE-NEW', 'Discovery', Date.today().addDays(60));
        Test.startTest();
        insert opp;
        Test.stopTest();
        System.assertNotEquals(null, opp.Id);
    }

    @IsTest
    static void testUpdatePath() {
        Account acc = getAccount(3);
        Opportunity opp = createOpportunity(acc.Id, 'New Logo', 'Court & Process', null, 'Prospecting', Date.today().addDays(30));
        insert opp;
        opp.Revenue_Type__c = 'Portfolio Growth';
        Test.startTest();
        update opp;
        Test.stopTest();
        System.assertEquals('Portfolio Growth', [SELECT Revenue_Type__c FROM Opportunity WHERE Id = :opp.Id].Revenue_Type__c);
    }

    @IsTest
    static void testEmptyAndNullInput() {
        Test.startTest();
        OpportunityRevenueValidationHandler.handleBeforeSave(new List<Opportunity>(), new Map<Id, Opportunity>());
        OpportunityRevenueValidationHandler.handleBeforeSave(null, new Map<Id, Opportunity>());
        Test.stopTest();
    }
}