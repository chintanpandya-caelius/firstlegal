@IsTest
private class FL_RushKeywordCheckerTest {
    @IsTest
    static void testIsRush() {
        String firstKeyword = System.Label.Rush_Priority_Keywords.split(',')[0].trim();

        FL_RushKeywordChecker.Request hit = new FL_RushKeywordChecker.Request();
        hit.subject = 'Please handle ' + firstKeyword.toLowerCase();

        FL_RushKeywordChecker.Request miss = new FL_RushKeywordChecker.Request();
        miss.subject = 'Routine request';

        List<Boolean> res = FL_RushKeywordChecker.isRush(new List<FL_RushKeywordChecker.Request>{ hit, miss });
        Assert.isTrue(res[0]);
        Assert.isFalse(res[1]);
    }
}