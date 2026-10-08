@IsTest
public class KnowledgeBaseServiceTest {

    @TestSetup
    static void setupData() {
        String divisionValue = getDivisionValue();

        List<Knowledge__kav> articles = new List<Knowledge__kav>();

        for (Integer i = 0; i < 11; i++) {
            articles.add(
                new Knowledge__kav(
                    Title = 'Test Article ' + i + ' Alpha',
                    UrlName = 'kb-test-article-' + i,
                    Summary = 'Test summary ' + i,
                    Language = 'en_US',
                    Division__c = divisionValue,
                    IsVisibleInPkb = true
                )
            );
        }

        articles.add(
            new Knowledge__kav(
                Title = 'Invisible Test Article',
                UrlName = 'kb-invisible-article',
                Summary = 'Invisible summary',
                Language = 'en_US',
                Division__c = divisionValue,
                IsVisibleInPkb = false
            )
        );

        articles.add(
            new Knowledge__kav(
                Title = 'Blank Division Article',
                UrlName = 'kb-blank-division-article',
                Summary = 'Blank division summary',
                Language = 'en_US',
                IsVisibleInPkb = true,
                Division__c = 'Client_Care'
            )
        );

        insert articles;

        for (Knowledge__kav article : [
            SELECT KnowledgeArticleId
            FROM Knowledge__kav
            WHERE Id IN :articles
        ]) {
            KbManagement.PublishingService.publishArticle(
                article.KnowledgeArticleId,
                true
            );
        }
    }

    @IsTest
    static void testOverview() {
        String divisionValue = getDivisionValue();

        KnowledgeBaseService.testConfigurations =
            new List<Division_Configuration__mdt>{
                null,
                new Division_Configuration__mdt(
                    MasterLabel = 'Inactive',
                    Division_Value__c = divisionValue,
                    Active__c = false
                ),
                new Division_Configuration__mdt(
                    MasterLabel = 'Blank',
                    Division_Value__c = '',
                    Active__c = true
                ),
                new Division_Configuration__mdt(
                    MasterLabel = 'First Legal',
                    Division_Value__c = divisionValue,
                    Summary__c = 'Legal articles',
                    Logo_Path__c = '/resource/legal',
                    Sort_Order__c = 1,
                    Active__c = true
                ),
                new Division_Configuration__mdt(
                    MasterLabel = 'Other Division',
                    Division_Value__c = 'OTHER',
                    Summary__c = 'Other articles',
                    Logo_Path__c = '/resource/other',
                    Sort_Order__c = 2,
                    Active__c = true
                )
            };

        KnowledgeBaseService.testInternalVisibility = false;

        Test.startTest();
        List<KnowledgeBaseService.DivisionOverviewItem> result =
            KnowledgeBaseService.getDivisionOverview();
        Test.stopTest();

        System.assertEquals(2, result.size());
    }

    @IsTest
    static void testEmptyOverview() {
        KnowledgeBaseService.testConfigurations =
            new List<Division_Configuration__mdt>();

        KnowledgeBaseService.testInternalVisibility = false;

        Test.startTest();
        List<KnowledgeBaseService.DivisionOverviewItem> result =
            KnowledgeBaseService.getDivisionOverview();
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    @IsTest
    static void testDivisionPage() {
        String divisionValue = getDivisionValue();

        KnowledgeBaseService.testConfigurations =
            getConfigurations(divisionValue);

        KnowledgeBaseService.testInternalVisibility = false;

        Test.startTest();

        KnowledgeBaseService.DivisionPageResponse response1 =
            KnowledgeBaseService.getDivisionPage(
                divisionValue,
                null,
                null,
                null,
                null
            );

        KnowledgeBaseService.DivisionPageResponse response2 =
            KnowledgeBaseService.getDivisionPage(
                divisionValue,
                'Alpha',
                'A_Z',
                2,
                0
            );

        KnowledgeBaseService.DivisionPageResponse response3 =
            KnowledgeBaseService.getDivisionPage(
                divisionValue,
                'Alpha Beta Gamma Delta Epsilon Zeta Eta Theta Iota Kappa Lambda',
                'RECENTLY_ADDED',
                2,
                -1
            );

        KnowledgeBaseService.DivisionPageResponse response4 =
            KnowledgeBaseService.getDivisionPage(
                divisionValue,
                'A',
                'INVALID',
                100,
                3000
            );

        KnowledgeBaseService.DivisionPageResponse response5 =
            KnowledgeBaseService.getDivisionPage(
                '',
                null,
                null,
                null,
                null
            );

        KnowledgeBaseService.DivisionPageResponse response6 =
            KnowledgeBaseService.getDivisionPage(
                'INVALID_DIVISION',
                null,
                null,
                null,
                null
            );

        Test.stopTest();

        System.assertEquals(false, response1.invalidDivision);
        System.assertEquals(10, response1.pageSize);
        System.assertEquals(0, response1.offset);
        System.assertEquals(true, response1.hasMore);

        System.assertEquals(false, response2.invalidDivision);
        System.assertEquals(true, response2.hasMore);

        System.assertEquals(false, response3.invalidDivision);

        System.assertEquals(false, response4.invalidDivision);
        System.assertEquals(50, response4.pageSize);
        System.assertEquals(2000, response4.offset);

        System.assertEquals(true, response5.invalidDivision);
        System.assertEquals(true, response6.invalidDivision);
    }

    @IsTest
    static void testBreadcrumbs() {
        String divisionValue = getDivisionValue();

        KnowledgeBaseService.testConfigurations =
            getConfigurations(divisionValue);

        KnowledgeBaseService.testInternalVisibility = false;

        Knowledge__kav visibleArticle = [
            SELECT Id
            FROM Knowledge__kav
            WHERE Title = 'Test Article 0 Alpha'
            LIMIT 1
        ];

        Knowledge__kav invisibleArticle = [
            SELECT Id
            FROM Knowledge__kav
            WHERE Title = 'Invisible Test Article'
            LIMIT 1
        ];

        Knowledge__kav blankDivisionArticle = [
            SELECT Id
            FROM Knowledge__kav
            WHERE Title = 'Blank Division Article'
            LIMIT 1
        ];

        Test.startTest();

        KnowledgeBaseService.ArticleBreadcrumbContext validContext =
            KnowledgeBaseService.getArticleBreadcrumbContext(
                String.valueOf(visibleArticle.Id)
            );

        KnowledgeBaseService.ArticleBreadcrumbContext blankContext =
            KnowledgeBaseService.getArticleBreadcrumbContext(
                String.valueOf(blankDivisionArticle.Id)
            );

        KnowledgeBaseService.ArticleBreadcrumbContext invisibleContext =
            KnowledgeBaseService.getArticleBreadcrumbContext(
                String.valueOf(invisibleArticle.Id)
            );

        KnowledgeBaseService.ArticleBreadcrumbContext emptyContext =
            KnowledgeBaseService.getArticleBreadcrumbContext('');

        KnowledgeBaseService.ArticleBreadcrumbContext invalidContext =
            KnowledgeBaseService.getArticleBreadcrumbContext(
                'not-an-id'
            );

        KnowledgeBaseService.testInternalVisibility = true;

        KnowledgeBaseService.ArticleBreadcrumbContext internalContext =
            KnowledgeBaseService.getArticleBreadcrumbContext(
                String.valueOf(invisibleArticle.Id)
            );

        KnowledgeBaseService.testConfigurations =
            new List<Division_Configuration__mdt>{
                new Division_Configuration__mdt(
                    MasterLabel = 'Other',
                    Division_Value__c = 'OTHER',
                    Active__c = true
                )
            };

        KnowledgeBaseService.ArticleBreadcrumbContext noMatchContext =
            KnowledgeBaseService.getArticleBreadcrumbContext(
                String.valueOf(visibleArticle.Id)
            );

        Test.stopTest();

        System.assertNotEquals(null, validContext);
        System.assertEquals(null, invisibleContext);
        System.assertEquals(null, emptyContext);
        System.assertEquals(null, invalidContext);
        System.assertNotEquals(null, internalContext);
        System.assertEquals(null, noMatchContext);
    }

    @IsTest
    static void testConstructors() {
        KnowledgeBaseService.DivisionOverviewItem division =
            new KnowledgeBaseService.DivisionOverviewItem();

        KnowledgeBaseService.DivisionPageResponse page =
            new KnowledgeBaseService.DivisionPageResponse();

        KnowledgeBaseService.ArticleBreadcrumbContext emptyBreadcrumb =
            new KnowledgeBaseService.ArticleBreadcrumbContext();

        KnowledgeBaseService.ArticleBreadcrumbContext breadcrumb =
            new KnowledgeBaseService.ArticleBreadcrumbContext(
                'Article',
                'DIV',
                'Division'
            );

        Knowledge__kav article =
            new Knowledge__kav();

        KnowledgeBaseService.ArticleItem emptyArticle =
            new KnowledgeBaseService.ArticleItem(article);

        Knowledge__kav populatedArticle = [
            SELECT Id,
                   Title,
                   Summary,
                   LastPublishedDate,
                   ArticleTotalViewCount
            FROM Knowledge__kav
            WHERE Title = 'Test Article 0 Alpha'
            LIMIT 1
        ];

        KnowledgeBaseService.ArticleItem populatedArticleItem =
            new KnowledgeBaseService.ArticleItem(populatedArticle);

        System.assertNotEquals(null, division);
        System.assertNotEquals(null, page);
        System.assertNotEquals(null, emptyBreadcrumb);
        System.assertEquals('Article', breadcrumb.articleTitle);
        System.assertEquals(0, emptyArticle.articleTotalViewCount);
        System.assertNotEquals(null, populatedArticleItem);
    }

    private static List<Division_Configuration__mdt> getConfigurations(
        String divisionValue
    ) {
        return new List<Division_Configuration__mdt>{
            new Division_Configuration__mdt(
                MasterLabel = 'First Legal',
                Division_Value__c = divisionValue,
                Summary__c = 'Legal articles',
                Logo_Path__c = '/resource/legal',
                Sort_Order__c = 1,
                Active__c = true
            ),
            new Division_Configuration__mdt(
                MasterLabel = 'Other Division',
                Division_Value__c = 'OTHER',
                Summary__c = 'Other articles',
                Logo_Path__c = '/resource/other',
                Sort_Order__c = 2,
                Active__c = true
            )
        };
    }

    private static String getDivisionValue() {
        for (
            Schema.PicklistEntry entry :
            Knowledge__kav.Division__c.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }
}