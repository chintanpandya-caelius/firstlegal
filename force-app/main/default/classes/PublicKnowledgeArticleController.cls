public with sharing class PublicKnowledgeArticleController {

    private static final String PUBLISH_STATUS = 'Online';
    private static final String LANGUAGE_CODE  = 'en_US';

    public class ArticleWrapper {
        @AuraEnabled public final String id;
        @AuraEnabled public final String title;
        @AuraEnabled public final String urlName;
        @AuraEnabled public final String excerpt;
        @AuraEnabled public final String lastPublishedDate;

        public ArticleWrapper(Knowledge__kav kav) {
            this.id                = kav.Id;
            this.title             = kav.Title;
            this.urlName           = kav.UrlName;
            this.excerpt           = String.isNotBlank(kav.Summary)
                                        ? kav.Summary
                                        : 'Click to read this article.';
            this.lastPublishedDate = kav.LastPublishedDate != null
                                        ? kav.LastPublishedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                                        : '';
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ArticleWrapper> getSuggestedArticles() {
        try {
            List<Knowledge__kav> articles = [
                SELECT Id, Title, UrlName, Summary, LastPublishedDate
                FROM   Knowledge__kav
                WHERE  PublishStatus  = :PUBLISH_STATUS
                AND    Language       = :LANGUAGE_CODE
                AND    IsVisibleInPkb = true
                WITH   USER_MODE
                ORDER BY LastPublishedDate DESC
                LIMIT  3
            ];
            return buildWrappers(articles);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error fetching suggested articles: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<ArticleWrapper> searchPublicArticles(
        String  searchTerm,
        Integer pageSize
    ) {
        try {
            Integer limitSize    = (pageSize != null && pageSize > 0) ? pageSize : 10;
            String  searchFilter = String.isNotBlank(searchTerm)
                                        ? '%' + searchTerm.trim() + '%'
                                        : '%';

            List<Knowledge__kav> articles = [
                SELECT Id, Title, UrlName, Summary, LastPublishedDate
                FROM   Knowledge__kav
                WHERE  PublishStatus  = :PUBLISH_STATUS
                AND    Language       = :LANGUAGE_CODE
                AND    IsVisibleInPkb = true
                AND    (Title   LIKE :searchFilter
                     OR Summary LIKE :searchFilter)
                WITH   USER_MODE
                ORDER BY LastPublishedDate DESC
                LIMIT  :limitSize
            ];
            return buildWrappers(articles);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error searching articles: ' + e.getMessage()
            );
        }
    }

    private static List<ArticleWrapper> buildWrappers(List<Knowledge__kav> articles) {
        List<ArticleWrapper> wrappers = new List<ArticleWrapper>();
        for (Knowledge__kav kav : articles) {
            if (String.isBlank(kav.Title)) continue;
            wrappers.add(new ArticleWrapper(kav));
        }
        return wrappers;
    }
}