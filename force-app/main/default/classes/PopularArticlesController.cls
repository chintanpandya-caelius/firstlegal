public without sharing class PopularArticlesController {

    @AuraEnabled(cacheable=true)
    public static List<ArticleWrapper> getPopularArticles() {
        Boolean isInternalVisible = FeatureManagement.checkPermission('Access_All_Knowledge_Articles');

        String queryString = 'SELECT  Id, Title, UrlName, Category__c, ArticleTotalViewCount, ArticleNumber, PublishStatus FROM Knowledge__kav WHERE Language = \'en_US\'';

        if(!isInternalVisible){
            queryString += ' AND IsVisibleInPkb = true';
        }

        queryString += ' ORDER BY ArticleTotalViewCount DESC NULLS LAST LIMIT 6';

        List<Knowledge__kav> articles = Database.query(queryString, AccessLevel.SYSTEM_MODE);
        
        List<ArticleWrapper> result = new List<ArticleWrapper>();
        for (Knowledge__kav a : articles) {
            result.add(new ArticleWrapper(a));
        }
        return result;
    }

    public class ArticleWrapper {
        @AuraEnabled public String  id            { get; set; }
        @AuraEnabled public String  title         { get; set; }
        @AuraEnabled public String  category      { get; set; }
        @AuraEnabled public Integer viewCount     { get; set; }
        @AuraEnabled public String  urlName       { get; set; }
        @AuraEnabled public String  publishStatus { get; set; }
        @AuraEnabled public String  articleType   { get; set; }

        public ArticleWrapper(Knowledge__kav a) {
            this.id            = a.Id;
            this.title         = a.Title;
            this.category      = a.Category__c;
            this.viewCount     = a.ArticleTotalViewCount != null
                                    ? Integer.valueOf(a.ArticleTotalViewCount)
                                    : 0;
            this.urlName       = a.UrlName;
            this.publishStatus = a.PublishStatus;
            this.articleType   = 'Knowledge__kav'; // hardcoded — Knowledge__kav is the article type
        }
    }
}