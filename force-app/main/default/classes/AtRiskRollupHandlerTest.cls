@IsTest
private class AtRiskRollupHandlerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'At Risk Test Account'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'At Risk',
            LastName = 'Contact',
            AccountId = acc.Id,
            MailingStreet = '123 Test Street',
            MailingCity = 'Los Angeles',
            MailingState = 'California',
            MailingPostalCode = '90001',
            MailingCountry = 'United States'
        );
        insert con;
    }

    @IsTest
    static void testAccountAndContactRiskRollup() {
        Account acc = [
            SELECT Id, Risk_Level__c
            FROM Account
            LIMIT 1
        ];

        Contact con = [
            SELECT Id, AccountId, Risk_Level__c
            FROM Contact
            LIMIT 1
        ];

        At_Risk__c accountLow = new At_Risk__c(
            Account__c = acc.Id,
            Risk_Level__c = 'Low'
        );

        At_Risk__c accountHigh = new At_Risk__c(
            Account__c = acc.Id,
            Risk_Level__c = 'High'
        );

        At_Risk__c contactMedium = new At_Risk__c(
            Contact__c = con.Id,
            Risk_Level__c = 'Medium'
        );

        insert new List<At_Risk__c>{
            accountLow,
            accountHigh,
            contactMedium
        };

        Test.startTest();

        AtRiskRollupHandler.handle(
            new List<At_Risk__c>{
                accountLow,
                accountHigh,
                contactMedium
            },
            null
        );

        Test.stopTest();

        acc = [
            SELECT Risk_Level__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        con = [
            SELECT Risk_Level__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        System.assertEquals('High', acc.Risk_Level__c);
        System.assertEquals('Medium', con.Risk_Level__c);
    }

    @IsTest
    static void testRiskPriority() {
        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Contact con = [
            SELECT Id
            FROM Contact
            LIMIT 1
        ];

        At_Risk__c lowRisk = new At_Risk__c(
            Account__c = acc.Id,
            Risk_Level__c = 'Low'
        );

        At_Risk__c mediumRisk = new At_Risk__c(
            Account__c = acc.Id,
            Risk_Level__c = 'Medium'
        );

        At_Risk__c highRisk = new At_Risk__c(
            Contact__c = con.Id,
            Risk_Level__c = 'High'
        );

        insert new List<At_Risk__c>{
            lowRisk,
            mediumRisk,
            highRisk
        };

        Test.startTest();

        AtRiskRollupHandler.handle(
            new List<At_Risk__c>{
                lowRisk,
                mediumRisk,
                highRisk
            },
            null
        );

        Test.stopTest();

        acc = [
            SELECT Risk_Level__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        con = [
            SELECT Risk_Level__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        // High contact risk rolls up to the parent Account.
        System.assertEquals('High', acc.Risk_Level__c);
        System.assertEquals('High', con.Risk_Level__c);
    }

@IsTest
static void testOldRecordsAndClearRisk() {
    Account acc = [
        SELECT Id
        FROM Account
        LIMIT 1
    ];

    Contact con = [
        SELECT Id
        FROM Contact
        LIMIT 1
    ];

    At_Risk__c risk = new At_Risk__c(
        Account__c = acc.Id,
        Contact__c = con.Id,
        Risk_Level__c = 'High'
    );

    insert risk;

    At_Risk__c oldRisk = risk;

    Test.startTest();

    // First execution: apply High risk.
    AtRiskRollupHandler.handle(
        new List<At_Risk__c>{risk},
        null
    );

    // Delete the risk record.
    delete risk;

    // Second execution: use oldRecords to recalculate
    // the Account and Contact after the risk is removed.
    AtRiskRollupHandler.handle(
        new List<At_Risk__c>(),
        new List<At_Risk__c>{oldRisk}
    );

    Test.stopTest();

    acc = [
        SELECT Risk_Level__c
        FROM Account
        WHERE Id = :acc.Id
    ];

    con = [
        SELECT Risk_Level__c
        FROM Contact
        WHERE Id = :con.Id
    ];

    System.assertEquals(null, acc.Risk_Level__c);
    System.assertEquals(null, con.Risk_Level__c);
}


    @IsTest
    static void testInactiveRiskIsIgnored() {
        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Contact con = [
            SELECT Id
            FROM Contact
            LIMIT 1
        ];

        /*
         * Resolved_Date__c is yesterday.
         *
         * IsActive__c formula:
         * OR(
         *     ISBLANK(Resolved_Date__c),
         *     Resolved_Date__c > DATEVALUE(NOW())
         * )
         *
         * Therefore IsActive__c evaluates to FALSE.
         */
        At_Risk__c inactiveRisk = new At_Risk__c(
            Account__c = acc.Id,
            Contact__c = con.Id,
            Risk_Level__c = 'High',
            Resolved_Date__c = Date.today().addDays(-1)
        );

        insert inactiveRisk;

        Test.startTest();

        AtRiskRollupHandler.handle(
            new List<At_Risk__c>{inactiveRisk},
            null
        );

        Test.stopTest();

        acc = [
            SELECT Risk_Level__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        con = [
            SELECT Risk_Level__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        /*
         * Because the record is inactive, it is excluded by:
         *
         * WHERE IsActive__c = true
         */
        System.assertEquals(null, acc.Risk_Level__c);
        System.assertEquals(null, con.Risk_Level__c);
    }

    @IsTest
    static void testNullLists() {
        Test.startTest();

        AtRiskRollupHandler.handle(null, null);

        Test.stopTest();

        // No exception should be thrown.
        System.assert(true);
    }

    @IsTest
    static void testRecursionGuard() {
        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        At_Risk__c risk = new At_Risk__c(
            Account__c = acc.Id,
            Risk_Level__c = 'High'
        );

        insert risk;

        Test.startTest();

        /*
         * First call performs the rollup.
         */
        AtRiskRollupHandler.handle(
            new List<At_Risk__c>{risk},
            null
        );

        /*
         * Second call should safely return because
         * isRunning is already being guarded.
         */
        AtRiskRollupHandler.handle(
            new List<At_Risk__c>{risk},
            null
        );

        Test.stopTest();

        acc = [
            SELECT Risk_Level__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertEquals('High', acc.Risk_Level__c);
    }
}