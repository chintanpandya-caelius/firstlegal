public with sharing class KnowledgeArticleDetailController {

    @AuraEnabled(cacheable=true)
    public static Knowledge__kav getKnowledgeArticle(String articleId) {
        // articleId can be the KnowledgeArticleId (15/18-char) or the record Id
        List<Knowledge__kav> articles = [
            SELECT Id, Title, Answer__c, LastPublishedDate, ArticleTotalViewCount
            FROM Knowledge__kav
            WHERE (Id = :articleId OR KnowledgeArticleId = :articleId)
              AND PublishStatus = 'Online'
            LIMIT 1
        ];

        if (articles.isEmpty()) {
            throw new AuraHandledException('Article not found or not published.');
        }
        return articles[0];
    }
}