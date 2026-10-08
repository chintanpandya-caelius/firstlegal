public without sharing class PortalKnowledgeSearchController {

    private static final String PUBLISH_STATUS = 'Online';
    private static final Boolean IS_INTERNAL_VISIBLE = FeatureManagement.checkPermission('Access_All_Knowledge_Articles');

    @AuraEnabled(cacheable=true)
    public static List<ArticleWrapper> searchArticles(String searchTerm) {
        try {
            Boolean isInternalVisible = FeatureManagement.checkPermission('Access_All_Knowledge_Articles');
            List<ArticleWrapper> results = new List<ArticleWrapper>();

            if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
                return results;
            }

            String sanitized = String.escapeSingleQuotes(searchTerm.trim());
            List<String> perWordsToMatch = sanitized.split('\\s+');
            List<String> conditions = new List<String>();
            for(String word : perWordsToMatch) {
                String sanitizedWord = '%' + String.escapeSingleQuotes(word) + '%';
                conditions.add('Title LIKE \'' + sanitizedWord + '\'');
            }

            Map<String, Object> queryBinds = new Map<String, Object>{
                'status' => PUBLISH_STATUS
            };

            String queryString = 'SELECT Id, KnowledgeArticleId, Title, UrlName, Summary, ArticleNumber ' +
                                            'FROM Knowledge__kav ' +
                                            'WHERE (';

            queryString += String.join(conditions, ' OR ');
            queryString += ') ';

            if(!IS_INTERNAL_VISIBLE){
                queryString += 'AND IsVisibleInPkb = true ';
            }

            queryString += 'AND PublishStatus = :status ORDER BY LastPublishedDate DESC LIMIT 20';

            List<Knowledge__kav> articles = Database.queryWithBinds(queryString, queryBinds, AccessLevel.SYSTEM_MODE);

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
            String queryString = 'SELECT Id, KnowledgeArticleId, Title, Summary, ArticleNumber FROM Knowledge__kav WHERE PublishStatus = \'Online\'';

            if(!IS_INTERNAL_VISIBLE){
                queryString += ' AND IsVisibleInPkb = true';
            }

            queryString += ' ORDER BY Title ASC LIMIT 10';

            List<Knowledge__kav> articles = Database.query(queryString, AccessLevel.SYSTEM_MODE);

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