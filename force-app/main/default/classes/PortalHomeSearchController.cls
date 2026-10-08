public without sharing class PortalHomeSearchController {

    private static final String PUBLISH_STATUS = 'Online';
    private static final Boolean IS_INTERNAL_VISIBLE = FeatureManagement.checkPermission('Access_All_Knowledge_Articles');

    public class ArticleWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String knowledgeArticleId;
        @AuraEnabled public String title;
        @AuraEnabled public String urlName;
        @AuraEnabled public String excerpt;
        @AuraEnabled public String lastPublishedDate;

        public ArticleWrapper(Knowledge__kav kav) {
            this.id                 = kav.Id;
            this.knowledgeArticleId = kav.KnowledgeArticleId;
            this.title              = kav.Title;
            this.urlName            = kav.UrlName;
            this.excerpt            = String.isNotBlank(kav.Summary)
                                        ? kav.Summary.stripHtmlTags().abbreviate(160)
                                        : 'Click to read this article.';
            this.lastPublishedDate  = kav.LastPublishedDate != null
                                        ? kav.LastPublishedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                                        : '';
        }
    }

    public class TicketWrapper{
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;

        public TicketWrapper(Case ticket){
            this.id = ticket.Id;
            this.caseNumber = ticket.CaseNumber;
            this.subject = ticket.Subject;
        }
    }

    public class SearchResponse{
    @AuraEnabled public List<ArticleWrapper> articles;
    @AuraEnabled public List<TicketWrapper> tickets;

        public SearchResponse(List<ArticleWrapper> articles, List<TicketWrapper> tickets){
            this.articles = articles;
            this.tickets = tickets;
        }
    }

    /**
     * Returns the 3 most recently published portal-visible articles.
     * Called on initial component load.
     */
    @AuraEnabled(cacheable=true)
    public static List<ArticleWrapper> getSuggestedArticles() {
        try {
            String queryString = 'SELECT Id, KnowledgeArticleId, Title, UrlName, Summary, LastPublishedDate FROM Knowledge__kav WHERE PublishStatus = :PUBLISH_STATUS';
            
            if(!IS_INTERNAL_VISIBLE){
                queryString += ' AND IsVisibleInPkb = true';
            }

            queryString += 'ORDER BY LastPublishedDate DESC LIMIT 3';

            Map<String, Object> queryBinds = new Map<String, Object>{
                'status' => PUBLISH_STATUS
            };

            List<Knowledge__kav> articles = Database.queryWithBinds(queryString, queryBinds, AccessLevel.SYSTEM_MODE);

            List<ArticleWrapper> articleWrapperList = new List<ArticleWrapper>();
            for (Knowledge__kav article : articles) {
                articleWrapperList.add(new ArticleWrapper(article));
            }

            return articleWrapperList;

        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to load suggested articles. Please try again.'
            );
        }
    }

    /**
     * Searches portal-visible articles by keyword across Title and Summary.
     * Supports empty/blank searchTerm (returns recent articles).
     */
    @AuraEnabled(cacheable=false)
    public static SearchResponse searchArticles(String searchTerm, Integer pageSize) {
        try {
            Integer limitSize = (pageSize != null && pageSize > 0) ? Math.min(pageSize, 50) : 10;

            List<ArticleWrapper> articleWrappers = new List<ArticleWrapper>();
            List<TicketWrapper> ticketWrappers = new List<TicketWrapper>();

            if (String.isBlank(searchTerm)){
                return new SearchResponse(articleWrappers, ticketWrappers);
            }

            String sanitized = String.escapeSingleQuotes(searchTerm.trim());
            List<String> perWordsToMatch = sanitized.split('\\s+');
            List<String> conditions = new List<String>();
            for(String word : perWordsToMatch) {
                String sanitizedWord = '%' + String.escapeSingleQuotes(word) + '%';
                conditions.add('Title LIKE \'' + sanitizedWord + '\'');
            }

            Map<String, Object> queryBinds = new Map<String, Object>{
                'status' => PUBLISH_STATUS,
                'lim' => limitSize
            };

            String queryString = 'SELECT Id, KnowledgeArticleId, Title, UrlName, Summary, LastPublishedDate ' +
                                'FROM Knowledge__kav ' +
                                'WHERE (';

            queryString += String.join(conditions, ' OR ');
            queryString += ') ';

            if(!IS_INTERNAL_VISIBLE){
                queryString += 'AND IsVisibleInPkb = true ';
            }

            queryString += 'AND PublishStatus = :status ORDER BY LastPublishedDate DESC LIMIT :lim';

            List<Knowledge__kav> articles = Database.queryWithBinds(queryString, queryBinds, AccessLevel.SYSTEM_MODE);


            for (Knowledge__kav kav : articles){
                articleWrappers.add(new ArticleWrapper(kav));
            }

            String searchFilter = '%' + sanitized + '%';

            List<Case> tickets = [
                SELECT Id, CaseNumber, Subject
                FROM Case
                WHERE (CaseNumber LIKE :searchFilter OR Subject LIKE :searchFilter)
                ORDER BY LastModifiedDate DESC
                LIMIT :limitSize
            ];

            for (Case c : tickets){
                ticketWrappers.add(new TicketWrapper(c));
            }

            return new SearchResponse(articleWrappers, ticketWrappers);

        } catch (Exception e) {
            throw new AuraHandledException(
                'Search failed. Please try a different term.'
            );
        }
    }
}