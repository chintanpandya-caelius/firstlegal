public with sharing class HomePageSearchController {

    @AuraEnabled(cacheable=true)
    public static List<ArticleWrapper> searchArticles(String searchTerm) {
        try {
            List<ArticleWrapper> results = new List<ArticleWrapper>();

            if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
                return results;
            }

            String searchKey = '%' + searchTerm.trim() + '%';

            List<Knowledge__kav> articles = [
                SELECT Id, KnowledgeArticleId, Title, Summary, ArticleNumber
                FROM Knowledge__kav
                WHERE PublishStatus = 'Online'
                AND (
                    Title LIKE :searchKey
                    OR Summary LIKE :searchKey
                )
                ORDER BY Title ASC
                LIMIT 20
            ];

            // List<Knowledge__kav> articles = Database.query('SELECT Id, KnowledgeArticleId, Title, Summary, ArticleNumber FROM Knowledge__kav WHERE PublishStatus = \'Online\' AND (Title LIKE :searchKey OR Summary LIKE :searchKey) ORDER BY Title ASC LIMIT 20', AccessLevel.SYSTEM_MODE);

            for (Knowledge__kav kav : articles) {
                results.add(new ArticleWrapper(kav));
            }
            return results;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ArticleWrapper> getFeaturedArticles() {
        try {
            List<Knowledge__kav> articles = [
                SELECT Id, KnowledgeArticleId, Title, Summary, ArticleNumber
                FROM Knowledge__kav
                WHERE PublishStatus = 'Online'
                ORDER BY Title ASC
                LIMIT 10
            ];

            List<ArticleWrapper> results = new List<ArticleWrapper>();
            for (Knowledge__kav kav : articles) {
                results.add(new ArticleWrapper(kav));
            }
            return results;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class ArticleWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String knowledgeArticleId;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
        @AuraEnabled public String articleNumber;

        public ArticleWrapper(Knowledge__kav kav) {
            this.id                 = kav.Id;
            this.knowledgeArticleId = kav.KnowledgeArticleId;
            this.title              = kav.Title;
            this.summary            = kav.Summary;
            this.articleNumber      = kav.ArticleNumber;
        }
    }
}