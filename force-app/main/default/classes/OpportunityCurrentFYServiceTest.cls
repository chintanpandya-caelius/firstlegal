@IsTest
private class OpportunityCurrentFYServiceTest {

    @IsTest
    static void testStampCurrentFY() {
        Integer currentYear = Date.today().year();

        List<Opportunity> testOpps = new List<Opportunity>{
            // Close date in current year
            new Opportunity(
                Name = 'Current Year Opp',
                StageName = 'Prospecting',
                CloseDate = Date.newInstance(currentYear, 6, 15)
            ),
            // Close date in previous year
            new Opportunity(
                Name = 'Past Year Opp',
                StageName = 'Prospecting',
                CloseDate = Date.newInstance(currentYear - 1, 6, 15)
            ),
            // Close date in future year
            new Opportunity(
                Name = 'Future Year Opp',
                StageName = 'Prospecting',
                CloseDate = Date.newInstance(currentYear + 1, 6, 15)
            ),
            // Null close date
            new Opportunity(
                Name = 'Null Close Date Opp',
                StageName = 'Prospecting',
                CloseDate = null
            )
        };

        Test.startTest();
        OpportunityCurrentFYService.stampCurrentFY(testOpps);
        Test.stopTest();
    }

    @IsTest
    static void testBulkStampCurrentFY() {
        Integer currentYear = Date.today().year();
        List<Opportunity> bulkOpps = new List<Opportunity>();

        for (Integer i = 0; i < 200; i++) {
            bulkOpps.add(new Opportunity(
                Name = 'Bulk Opp ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.newInstance(currentYear, 1, 1)
            ));
        }

        Test.startTest();
        OpportunityCurrentFYService.stampCurrentFY(bulkOpps);
        Test.stopTest();

    }
}