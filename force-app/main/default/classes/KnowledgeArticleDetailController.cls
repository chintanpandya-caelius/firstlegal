public without sharing class KnowledgeArticleDetailController {

    @AuraEnabled(cacheable=true)
    public static KnowledgeArticleDetailControllerWrapper getKnowledgeArticle(String articleId) {
        List<Knowledge__kav> articles = Database.query(
        'SELECT Id, Title, LastPublishedDate, ArticleTotalViewCount ' +
        'FROM Knowledge__kav ' +
        'WHERE Id = :articleId ' +
        'LIMIT 1',
        AccessLevel.SYSTEM_MODE
    );

        if (articles.isEmpty()) {
            throw new AuraHandledException('Article not found or not published.');
        }
        KnowledgeArticleDetailControllerWrapper obj=new KnowledgeArticleDetailControllerWrapper(articles[0]);
        if(obj==null){
            throw new AuraHandledException('Processing failed');
        }
        return obj;
    }

    class KnowledgeArticleDetailControllerWrapper{
        @AuraEnabled public Id Id;
        @AuraEnabled public String Title;
        @AuraEnabled public String Answer;
        @AuraEnabled public DateTime LastPublishedDate;
        @AuraEnabled public Integer ArticleTotalViewCount;

        KnowledgeArticleDetailControllerWrapper(Knowledge__kav obj){
            Id = obj.Id;
            Title = obj.Title;
            LastPublishedDate = obj.LastPublishedDate;
            ArticleTotalViewCount = obj.ArticleTotalViewCount;
        }
    }
}