@IsTest
public class PopularArticlesControllerTest {

    private static final String NO_ACCESS_PREFIX = 'popular.noaccess.';
    private static final String ACCESS_PREFIX = 'popular.access.';

    @TestSetup
    static void setupData() {

        Knowledge__kav article = new Knowledge__kav(
            Title = 'Popular Test Article',
            UrlName = 'popular-test-article',
            Language = 'en_US',
            IsVisibleInPkb = true
        );

        insert article;

        Knowledge__kav savedArticle = [
            SELECT KnowledgeArticleId
            FROM Knowledge__kav
            WHERE Id = :article.Id
            LIMIT 1
        ];

        KbManagement.PublishingService.publishArticle(
            savedArticle.KnowledgeArticleId,
            true
        );

        Profile profile = [
            SELECT Id
            FROM Profile
            WHERE UserType = 'Standard'
            LIMIT 1
        ];

        User noAccessUser = new User(
            FirstName = 'Popular',
            LastName = 'NoAccess',
            Alias = 'pno',
            Email = 'popular.noaccess@example.com',
            Username =
                NO_ACCESS_PREFIX +
                String.valueOf(DateTime.now().getTime()) +
                '@example.com',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        User accessUser = new User(
            FirstName = 'Popular',
            LastName = 'Access',
            Alias = 'pall',
            Email = 'popular.access@example.com',
            Username =
                ACCESS_PREFIX +
                String.valueOf(DateTime.now().getTime()) +
                '@example.com',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        CustomPermission customPermission = [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = 'Access_All_Knowledge_Articles'
            LIMIT 1
        ];

        PermissionSet permissionSet = new PermissionSet(
            Name = 'PopularArticlesTestAccess',
            Label = 'Popular Articles Test Access'
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{
                noAccessUser,
                accessUser
            };

            insert permissionSet;

            insert new SetupEntityAccess(
                ParentId = permissionSet.Id,
                SetupEntityId = customPermission.Id
            );

            insert new PermissionSetAssignment(
                AssigneeId = accessUser.Id,
                PermissionSetId = permissionSet.Id
            );
        }
    }

    @IsTest
    static void testGetPopularArticles() {

        User noAccessUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE :NO_ACCESS_PREFIX + '%'
            LIMIT 1
        ];

        User accessUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE :ACCESS_PREFIX + '%'
            LIMIT 1
        ];

        System.runAs(noAccessUser) {

            Test.startTest();

            List<PopularArticlesController.ArticleWrapper> result =
                PopularArticlesController.getPopularArticles();

            Test.stopTest();

            System.assertEquals(1, result.size());
        }
    }

    @IsTest
    static void testArticleWrapper() {

        Knowledge__kav article = [
            SELECT Id,
                   Title,
                   UrlName,
                   Category__c,
                   ArticleTotalViewCount,
                   PublishStatus
            FROM Knowledge__kav
            LIMIT 1
        ];

        PopularArticlesController.ArticleWrapper wrapper =
            new PopularArticlesController.ArticleWrapper(article);

        PopularArticlesController.ArticleWrapper emptyWrapper =
            new PopularArticlesController.ArticleWrapper(
                new Knowledge__kav()
            );

        System.assertNotEquals(null, wrapper.id);
        System.assertEquals('Knowledge__kav', wrapper.articleType);
        System.assertEquals(0, emptyWrapper.viewCount);
    }
}