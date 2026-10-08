@isTest
private class KnowledgeAccessTest {
    @isTest
    static void testPortalUserQuery() {
        User portalUser = [SELECT Id FROM User WHERE Username = 'sanji@customerportal.com' LIMIT 1];
        System.runAs(portalUser) {
           // List<Knowledge__kav> articles = [
               // SELECT Id, Title FROM Knowledge__kav
               // WHERE Language = 'en_US' AND PublishStatus = 'Online' AND IsVisibleInCsp = TRUE
               // LIMIT 6
            //];
            //System.debug('Rows returned: ' + articles.size());
            System.runAs(portalUser) {
                Integer cnt = [SELECT COUNT() FROM Knowledge__kav];
                System.debug('Total Knowledge__kav visible: ' + cnt);
            }
        }
    }
}