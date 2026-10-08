@IsTest
public class PortalHomeSearchControllerTest {

    private static final String NO_ACCESS_PREFIX = 'portal.search.noaccess.';
    private static final String ACCESS_PREFIX = 'portal.search.access.';

    @TestSetup
    static void setupTestData() {

        List<Case> casesToInsert = new List<Case>{
            new Case(Subject = 'Network connection issue Alpha'),
            new Case(Subject = 'Hardware failure Beta'),
            new Case(Subject = 'Portal ticket Alpha')
        };

        insert casesToInsert;

        List<Knowledge__kav> articles = new List<Knowledge__kav>();

        for (Integer i = 0; i < 4; i++) {
            articles.add(
                new Knowledge__kav(
                    Title = 'Test Article ' + i + ' Alpha',
                    UrlName = 'test-article-alpha-' + i,
                    Summary = i == 0
                        ? null
                        : '<p>This is a test summary for article ' + i + '</p>',
                    IsVisibleInPkb = true,
                    Language = 'en_US'
                )
            );
        }

        insert articles;

        List<Knowledge__kav> publishedArticles = [
            SELECT KnowledgeArticleId
            FROM Knowledge__kav
            WHERE Id IN :articles
        ];

        for (Knowledge__kav article : publishedArticles) {
            KbManagement.PublishingService.publishArticle(
                article.KnowledgeArticleId,
                true
            );
        }

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE UserType = 'Standard'
            LIMIT 1
        ];

        User noAccessUser = new User(
            FirstName = 'Portal',
            LastName = 'NoAccess',
            Alias = 'psno',
            Email = 'portal.noaccess@example.com',
            Username =
                NO_ACCESS_PREFIX +
                String.valueOf(DateTime.now().getTime()) +
                '@example.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        User accessUser = new User(
            FirstName = 'Portal',
            LastName = 'Access',
            Alias = 'psall',
            Email = 'portal.access@example.com',
            Username =
                ACCESS_PREFIX +
                String.valueOf(DateTime.now().getTime()) +
                '@example.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        CustomPermission cp = [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = 'Access_All_Knowledge_Articles'
            LIMIT 1
        ];

        PermissionSet ps = new PermissionSet(
            Name = 'PortalHomeSearchTestAccess',
            Label = 'Portal Home Search Test Access'
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{
                noAccessUser,
                accessUser
            };

            insert ps;

            insert new SetupEntityAccess(
                ParentId = ps.Id,
                SetupEntityId = cp.Id
            );

            insert new PermissionSetAssignment(
                AssigneeId = accessUser.Id,
                PermissionSetId = ps.Id
            );
        }
    }

    @IsTest
    static void testSuggestedArticlesWithAccess() {

        User u = getAccessUser();
    }

    @IsTest
    static void testSuggestedArticlesWithoutAccess() {

        User u = getNoAccessUser();

        System.runAs(u) {
            try {
                Test.startTest();
                PortalHomeSearchController.getSuggestedArticles();
                Test.stopTest();
            } catch (AuraHandledException e) {
                Test.stopTest();
            }
        }
    }

    @IsTest
    static void testSearch() {

        User u = getNoAccessUser();

        System.runAs(u) {
            Test.startTest();

            PortalHomeSearchController.SearchResponse result1 =
                PortalHomeSearchController.searchArticles(
                    'Alpha',
                    5
                );

            PortalHomeSearchController.SearchResponse result2 =
                PortalHomeSearchController.searchArticles(
                    'Test Alpha',
                    10
                );

            PortalHomeSearchController.SearchResponse result3 =
                PortalHomeSearchController.searchArticles(
                    null,
                    5
                );

            PortalHomeSearchController.SearchResponse result4 =
                PortalHomeSearchController.searchArticles(
                    '   ',
                    5
                );

            PortalHomeSearchController.SearchResponse result5 =
                PortalHomeSearchController.searchArticles(
                    'Alpha',
                    null
                );

            PortalHomeSearchController.SearchResponse result6 =
                PortalHomeSearchController.searchArticles(
                    'Alpha',
                    100
                );

            PortalHomeSearchController.SearchResponse result7 =
                PortalHomeSearchController.searchArticles(
                    'Alpha',
                    0
                );

            Test.stopTest();

            System.assertNotEquals(null, result1);
            System.assertNotEquals(null, result2);
            System.assertEquals(0, result3.articles.size());
            System.assertEquals(0, result4.articles.size());
            System.assertNotEquals(null, result5);
            System.assertNotEquals(null, result6);
            System.assertNotEquals(null, result7);
        }
    }

    @IsTest
    static void testSearchWithPermission() {

        User u = getAccessUser();

        Case c = [
            SELECT CaseNumber
            FROM Case
            WHERE Subject = 'Network connection issue Alpha'
            LIMIT 1
        ];

        System.runAs(u) {
            Test.startTest();

            PortalHomeSearchController.SearchResponse result =
                PortalHomeSearchController.searchArticles(
                    c.CaseNumber,
                    10
                );

            Test.stopTest();

            System.assertNotEquals(null, result);
        }
    }

    @IsTest
    static void testNoMatch() {

        User u = getAccessUser();

        System.runAs(u) {
            Test.startTest();

            PortalHomeSearchController.SearchResponse result =
                PortalHomeSearchController.searchArticles(
                    'XYZNoMatch123',
                    10
                );

            Test.stopTest();

            System.assertEquals(0, result.articles.size());
            System.assertEquals(0, result.tickets.size());
        }
    }

    @IsTest
    static void testArticleWrapper() {

        Knowledge__kav article = [
            SELECT Id,
                   KnowledgeArticleId,
                   Title,
                   UrlName,
                   Summary,
                   LastPublishedDate
            FROM Knowledge__kav
            WHERE PublishStatus = 'Online'
            LIMIT 1
        ];

        PortalHomeSearchController.ArticleWrapper wrapper1 =
            new PortalHomeSearchController.ArticleWrapper(article);

        PortalHomeSearchController.ArticleWrapper wrapper2 =
            new PortalHomeSearchController.ArticleWrapper(
                new Knowledge__kav()
            );

        System.assertNotEquals(null, wrapper1.id);
        System.assertNotEquals(null, wrapper1.lastPublishedDate);
        System.assertNotEquals(null, wrapper1.excerpt);

        System.assertEquals(
            'Click to read this article.',
            wrapper2.excerpt
        );

        System.assertEquals(
            '',
            wrapper2.lastPublishedDate
        );
    }

    private static User getNoAccessUser() {
        return [
            SELECT Id
            FROM User
            WHERE Username LIKE :NO_ACCESS_PREFIX + '%'
            LIMIT 1
        ];
    }

    private static User getAccessUser() {
        return [
            SELECT Id
            FROM User
            WHERE Username LIKE :ACCESS_PREFIX + '%'
            LIMIT 1
        ];
    }
}