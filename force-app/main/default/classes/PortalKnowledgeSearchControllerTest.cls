@IsTest
public class PortalKnowledgeSearchControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create multiple Knowledge Articles to test loop iterations, filtering, and sorting
        List<Knowledge__kav> articlesToInsert = new List<Knowledge__kav>{
            new Knowledge__kav(
                Title = 'Alpha Test Article',
                UrlName = 'alpha-test-article',
                Summary = 'Summary for Alpha Article',
                IsVisibleInPkb = true
            ),
            new Knowledge__kav(
                Title = 'Beta Portal Article',
                UrlName = 'beta-portal-article',
                Summary = 'Summary for Beta Article',
                IsVisibleInPkb = true
            )
        };
        insert articlesToInsert;

        // Re-query to retrieve generated KnowledgeArticleIds
        List<Knowledge__kav> insertedArticles = [
            SELECT KnowledgeArticleId 
            FROM Knowledge__kav 
            WHERE Id IN :articlesToInsert
        ];

        // Publish articles so PublishStatus = 'Online'
        for (Knowledge__kav kav : insertedArticles) {
            KbManagement.PublishingService.publishArticle(kav.KnowledgeArticleId, true);
        }
    }

    @IsTest
    static void testSearchArticles_SingleAndMultipleMatches() {
        Test.startTest();
        // Test single word match
        List<PortalKnowledgeSearchController.ArticleWrapper> alphaResults = 
            PortalKnowledgeSearchController.searchArticles('Alpha');

        // Test multi-word match (exercises split logic and OR conditions)
        List<PortalKnowledgeSearchController.ArticleWrapper> multiResults = 
            PortalKnowledgeSearchController.searchArticles('Alpha Beta');
        Test.stopTest();

        Assert.areEqual(1, alphaResults.size(), 'Should return 1 article matching "Alpha".');
        
        // Validate wrapper constructor field assignments
        PortalKnowledgeSearchController.ArticleWrapper wrapper = alphaResults[0];
        Assert.areEqual('Alpha Test Article', wrapper.title);
        Assert.isNotNull(wrapper.id, 'Id should be populated.');
        Assert.isNotNull(wrapper.knowledgeArticleId, 'KnowledgeArticleId should be populated.');
        Assert.isNotNull(wrapper.summary, 'Summary should be populated.');
        Assert.isNotNull(wrapper.articleNumber, 'ArticleNumber should be populated.');

        Assert.areEqual(2, multiResults.size(), 'Should return both articles matching "Alpha" or "Beta".');
    }

    @IsTest
    static void testSearchArticles_BlankAndShortTerms() {
        Test.startTest();
        // Tests early-return conditions (null, whitespace, < 2 characters)
        List<PortalKnowledgeSearchController.ArticleWrapper> nullResults = 
            PortalKnowledgeSearchController.searchArticles(null);
        List<PortalKnowledgeSearchController.ArticleWrapper> blankResults = 
            PortalKnowledgeSearchController.searchArticles('   ');
        List<PortalKnowledgeSearchController.ArticleWrapper> shortResults = 
            PortalKnowledgeSearchController.searchArticles('a');
        Test.stopTest();

        Assert.isTrue(nullResults.isEmpty(), 'Null search term should return an empty list.');
        Assert.isTrue(blankResults.isEmpty(), 'Blank search term should return an empty list.');
        Assert.isTrue(shortResults.isEmpty(), 'Search term under 2 characters should return an empty list.');
    }

    @IsTest
    static void testSearchArticles_NoMatch() {
        Test.startTest();
        List<PortalKnowledgeSearchController.ArticleWrapper> results = 
            PortalKnowledgeSearchController.searchArticles('NonExistentTermXYZ');
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'Unmatched term should return an empty list.');
    }

    @IsTest
    static void testGetFeaturedArticles() {
        Test.startTest();
        List<PortalKnowledgeSearchController.ArticleWrapper> results = 
            PortalKnowledgeSearchController.getFeaturedArticles();
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Featured articles query should return all published articles.');
        // Verify ORDER BY Title ASC sorting logic
        Assert.areEqual('Alpha Test Article', results[0].title);
        Assert.areEqual('Beta Portal Article', results[1].title);
    }
}