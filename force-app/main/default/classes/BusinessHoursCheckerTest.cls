@isTest
private class BusinessHoursCheckerTest {

    @isTest
    static void testCheck() {
        BusinessHours bh = [SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1];

        BusinessHoursChecker.Request req1 = new BusinessHoursChecker.Request();
        req1.businessHoursId = bh.Id;
        req1.checkDateTime = DateTime.now();

        BusinessHoursChecker.Request req2 = new BusinessHoursChecker.Request();
        req2.businessHoursId = null;
        req2.checkDateTime = DateTime.now();

        Test.startTest();
        List<BusinessHoursChecker.Response> responses = BusinessHoursChecker.check(
            new List<BusinessHoursChecker.Request>{ req1, req2 }
        );
        Test.stopTest();

        System.assertEquals(2, responses.size());
    }
}