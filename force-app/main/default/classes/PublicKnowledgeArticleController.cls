public without sharing class PublicKnowledgeArticleController {

    public class ArticleWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String urlName;
        @AuraEnabled public String excerpt;

        public ArticleWrapper(Knowledge__kav kav) {
            this.id = kav.Id;
            this.title = kav.Title;
            this.urlName = kav.UrlName;
            this.excerpt = String.isNotBlank(kav.Summary) ? kav.Summary : 'Click to read more...';
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ArticleWrapper> getSuggestedArticles() {
        List<String> targetTitles = new List<String>{
            'Getting Started',
            'How to Install the FirstConnect Local Desktop App from your Browser',
            'Logging Out of the First Legal FirstConnect Portal'
        };

        List<Knowledge__kav> articles = [
            SELECT Id, Title, UrlName, Summary
            FROM Knowledge__kav
            WHERE PublishStatus = 'Online'
            AND Title IN :targetTitles
            ORDER BY Title ASC
            LIMIT 3
        ];
        return buildWrappers(articles);
    }

    @AuraEnabled(cacheable=false)
    public static List<ArticleWrapper> searchPublicArticles(String searchTerm, Integer pageSize) {
        if (String.isBlank(searchTerm)) return new List<ArticleWrapper>();
        
        Integer limitSize = (pageSize == null) ? 10 : pageSize;
        String soslTerm = String.escapeSingleQuotes(searchTerm.trim()) + '*';
        
        // System context search
        List<List<SObject>> searchResults = [
            FIND :soslTerm IN ALL FIELDS 
            RETURNING Knowledge__kav(Id, Title, UrlName, Summary WHERE PublishStatus = 'Online') 
            LIMIT :limitSize
        ];

        return buildWrappers((List<Knowledge__kav>)searchResults[0]);
    }

    private static List<ArticleWrapper> buildWrappers(List<Knowledge__kav> articles) {
        List<ArticleWrapper> wrappers = new List<ArticleWrapper>();
        for (Knowledge__kav kav : articles) {
            wrappers.add(new ArticleWrapper(kav));
        }
        return wrappers;
    }
}