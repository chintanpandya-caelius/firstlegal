public with sharing class KnowledgeRelatedArticlesController {

    @AuraEnabled(cacheable=true)
    public static List<Knowledge__kav> getRelatedArticles(String articleId) {


        // Step 2: Fetch related articles of the same type, ordered by most viewed
        List<Knowledge__kav> related = [
            SELECT Id, Title, LastPublishedDate
            FROM Knowledge__kav
            WHERE PublishStatus = 'Online'
              AND Language = 'en_US'
            WITH USER_MODE
            ORDER BY ArticleTotalViewCount DESC NULLS LAST
            LIMIT 5
        ];

        return related;
    }
}