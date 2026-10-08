public with sharing class KnowledgeBaseService {
    private static final String PUBLISH_STATUS = 'Online';
    private static final String ACCESS_ALL_PERMISSION = 'Access_All_Knowledge_Articles';
    private static final String DEFAULT_SORT = 'MOST_VIEWED';
    private static final Integer DEFAULT_PAGE_SIZE = 10;
    private static final Integer MAX_PAGE_SIZE = 50;
    private static final Integer MAX_OFFSET = 2000;
    private static final Boolean isGuest = UserInfo.getUserType() == 'Guest';

    private static final Map<String, String> SORT_CLAUSES = new Map<String, String>{
        'MOST_VIEWED' =>
            'ArticleTotalViewCount DESC NULLS LAST, LastPublishedDate DESC NULLS LAST, Id DESC',

        'RECENTLY_ADDED' =>
            'LastPublishedDate DESC NULLS LAST, Id DESC',

        'A_Z' =>
            'Title ASC, Id ASC'
    };

    @TestVisible
    private static List<Division_Configuration__mdt> testConfigurations;

    @TestVisible
    private static Boolean testInternalVisibility;

    public class DivisionOverviewItem {
        @AuraEnabled public String label;
        @AuraEnabled public String divisionValue;
        @AuraEnabled public String summary;
        @AuraEnabled public Integer articleCount;
        @AuraEnabled public String logoPath;
        @AuraEnabled public Decimal sortOrder;

        public DivisionOverviewItem() {
        }
    }

    public class ArticleItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
        @AuraEnabled public Datetime lastPublishedDate;
        @AuraEnabled public Integer articleTotalViewCount;

        public ArticleItem(Knowledge__kav article) {
            id = article.Id;
            title = article.Title;
            summary = article.Summary;
            lastPublishedDate = article.LastPublishedDate;
            articleTotalViewCount = article.ArticleTotalViewCount == null
                ? 0
                : article.ArticleTotalViewCount;
        }
    }

    public class DivisionPageResponse {
        @AuraEnabled public DivisionOverviewItem currentDivision;
        @AuraEnabled public Integer totalVisibleArticleCount;
        @AuraEnabled public List<ArticleItem> articles;
        @AuraEnabled public List<DivisionOverviewItem> otherDivisions;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer offset;
        @AuraEnabled public Boolean invalidDivision;

        public DivisionPageResponse() {
            articles = new List<ArticleItem>();
            otherDivisions = new List<DivisionOverviewItem>();
            hasMore = false;
            invalidDivision = false;
        }
    }

    public class ArticleBreadcrumbContext {
        @AuraEnabled public String articleTitle;
        @AuraEnabled public String divisionValue;
        @AuraEnabled public String divisionLabel;

        public ArticleBreadcrumbContext() {
        }

        public ArticleBreadcrumbContext(String articleTitle, String divisionValue, String divisionLabel) {
            this.articleTitle = articleTitle;
            this.divisionValue = divisionValue;
            this.divisionLabel = divisionLabel;
        }
    }

    public static List<DivisionOverviewItem> getDivisionOverview() {
        List<Division_Configuration__mdt> configs = getActiveConfigurations();
        if (configs.isEmpty()) {
            return new List<DivisionOverviewItem>();
        }

        Map<String, Integer> countsByDivision = getVisibleArticleCounts(configs);
        List<DivisionOverviewItem> result = new List<DivisionOverviewItem>();

        for (Division_Configuration__mdt config : configs) {
            if (String.isBlank(config.Division_Value__c)) {
                continue;
            }

            DivisionOverviewItem item = new DivisionOverviewItem();
            item.label = config.MasterLabel;
            item.divisionValue = config.Division_Value__c;
            item.summary = config.Summary__c;
            item.articleCount = countsByDivision.containsKey(config.Division_Value__c)
                ? countsByDivision.get(config.Division_Value__c)
                : 0;
            item.logoPath = config.Logo_Path__c;
            item.sortOrder = config.Sort_Order__c;
            result.add(item);
        }

        return result;
    }

    public static DivisionPageResponse getDivisionPage(
        String division,
        String searchTerm,
        String sortOption,
        Integer pageSize,
        Integer offset
    ) {
        DivisionPageResponse response = new DivisionPageResponse();
        response.pageSize = normalizePageSize(pageSize);
        response.offset = normalizeOffset(offset);

        if (String.isBlank(division)) {
            response.invalidDivision = true;
            return response;
        }

        List<DivisionOverviewItem> divisions = getDivisionOverview();
        DivisionOverviewItem currentDivision;

        for (DivisionOverviewItem divisionItem : divisions) {
            if (divisionItem.divisionValue == division.trim()) {
                currentDivision = divisionItem;
                break;
            }
        }

        if (currentDivision == null) {
            response.invalidDivision = true;
            return response;
        }

        response.currentDivision = currentDivision;
        response.totalVisibleArticleCount = currentDivision.articleCount;

        for (DivisionOverviewItem divisionItem : divisions) {
            if (divisionItem.divisionValue != currentDivision.divisionValue) {
                response.otherDivisions.add(divisionItem);
            }
        }

        List<Knowledge__kav> articleRows = queryArticles(
            currentDivision.divisionValue,
            searchTerm,
            normalizeSort(sortOption),
            response.pageSize,
            response.offset
        );

        for (Knowledge__kav article : articleRows) {
            response.articles.add(new ArticleItem(article));
        }

        response.hasMore = articleRows.size() > response.pageSize;
        if (response.hasMore) {
            response.articles.remove(response.articles.size() - 1);
        }

        return response;
    }

    public static ArticleBreadcrumbContext getArticleBreadcrumbContext(String articleId) {
        Id parsedArticleId = parseId(articleId);
        if (parsedArticleId == null) {
            return null;
        }

        Boolean internalVisible = isInternalVisible();
        Knowledge__kav article;

        if (internalVisible || isGuest) {
            List<Knowledge__kav> rows = [
                SELECT Id, Title, Division__c
                FROM Knowledge__kav
                WHERE Id = :parsedArticleId
                    AND PublishStatus = :PUBLISH_STATUS
                LIMIT 1
            ];
            article = rows.isEmpty() ? null : rows[0];
        } else {
            List<Knowledge__kav> rows = [
                SELECT Id, Title, Division__c
                FROM Knowledge__kav
                WHERE Id = :parsedArticleId
                    AND PublishStatus = :PUBLISH_STATUS
                    AND IsVisibleInPkb = true
                LIMIT 1
            ];
            article = rows.isEmpty() ? null : rows[0];
        }

        if (article == null || String.isBlank(article.Division__c)) {
            return null;
        }

        for (Division_Configuration__mdt config : getActiveConfigurations()) {
            if (config.Division_Value__c == article.Division__c) {
                return new ArticleBreadcrumbContext(
                    article.Title,
                    article.Division__c,
                    config.MasterLabel
                );
            }
        }

        return null;
    }

    private static List<Division_Configuration__mdt> getActiveConfigurations() {
        if (Test.isRunningTest() && testConfigurations != null) {
            List<Division_Configuration__mdt> activeTestConfigurations = new List<Division_Configuration__mdt>();
            for (Division_Configuration__mdt config : testConfigurations) {
                if (config != null && config.Active__c == true && String.isNotBlank(config.Division_Value__c)) {
                    activeTestConfigurations.add(config);
                }
            }
            return activeTestConfigurations;
        }

        return [
            SELECT MasterLabel, Division_Value__c, Summary__c, Logo_Path__c, Sort_Order__c, Active__c
            FROM Division_Configuration__mdt
            WHERE Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST, MasterLabel ASC
        ];
    }

    private static Map<String, Integer> getVisibleArticleCounts(
        List<Division_Configuration__mdt> configs
    ) {
        Set<String> divisionValues = new Set<String>();
        for (Division_Configuration__mdt config : configs) {
            if (String.isNotBlank(config.Division_Value__c)) {
                divisionValues.add(config.Division_Value__c);
            }
        }

        Map<String, Integer> countsByDivision = new Map<String, Integer>();
        if (divisionValues.isEmpty()) {
            return countsByDivision;
        }

        List<AggregateResult> aggregateRows;
        if (isInternalVisible() || isGuest) {
            aggregateRows = [
                SELECT Division__c divisionValue, COUNT(Id) articleCount
                FROM Knowledge__kav
                WHERE PublishStatus = :PUBLISH_STATUS
                    AND Division__c IN :divisionValues
                GROUP BY Division__c
            ];
        } else {
            aggregateRows = [
                SELECT Division__c divisionValue, COUNT(Id) articleCount
                FROM Knowledge__kav
                WHERE PublishStatus = :PUBLISH_STATUS
                    AND IsVisibleInPkb = true
                    AND Division__c IN :divisionValues
                GROUP BY Division__c
            ];
        }

        for (AggregateResult row : aggregateRows) {
            String divisionValue = (String) row.get('divisionValue');
            Integer articleCount = (Integer) row.get('articleCount');
            countsByDivision.put(divisionValue, articleCount);
        }

        return countsByDivision;
    }

    private static List<Knowledge__kav> queryArticles(
        String divisionValue,
        String searchTerm,
        String sortOption,
        Integer pageSize,
        Integer offset
    ) {
        Map<String, Object> queryBinds = new Map<String, Object>{
            'divisionValue' => divisionValue,
            'publishStatus' => PUBLISH_STATUS
        };

        List<String> conditions = new List<String>{
            'PublishStatus = :publishStatus',
            'Division__c = :divisionValue'
        };

        if (!isInternalVisible() || !isGuest) {
            conditions.add('IsVisibleInPkb = true');
        }

        List<String> searchTerms = tokenizeSearchTerm(searchTerm);
        List<String> searchConditions = new List<String>();

        for (Integer index = 0; index < searchTerms.size(); index++) {
            String bindName = 'searchTerm' + index;
            searchConditions.add('Title LIKE :' + bindName);
            queryBinds.put(bindName, '%' + searchTerms[index] + '%');
        }

        if (!searchConditions.isEmpty()) {
            conditions.add('(' + String.join(searchConditions, ' OR ') + ')');
        }

        String queryString =
            'SELECT Id, Title, Summary, LastPublishedDate, ArticleTotalViewCount ' +
            'FROM Knowledge__kav ' +
            'WHERE ' + String.join(conditions, ' AND ') + ' ' +
            'ORDER BY ' + SORT_CLAUSES.get(sortOption) + ' ' +
            'LIMIT ' + String.valueOf(pageSize + 1) + ' ' +
            'OFFSET ' + String.valueOf(offset);

        return Database.queryWithBinds(queryString, queryBinds, AccessLevel.SYSTEM_MODE);
    }

    private static List<String> tokenizeSearchTerm(String searchTerm) {
        List<String> tokens = new List<String>();
        if (String.isBlank(searchTerm)) {
            return tokens;
        }

        String trimmed = searchTerm.trim();
        if (trimmed.length() < 2) {
            return tokens;
        }

        List<String> rawTokens = trimmed.split('\\s+');
        Integer maxTerms = Math.min(rawTokens.size(), 10);

        for (Integer index = 0; index < maxTerms; index++) {
            String token = rawTokens[index];
            if (String.isNotBlank(token)) {
                tokens.add(token);
            }
        }

        return tokens;
    }

    private static String normalizeSort(String sortOption) {
        String normalized = String.isBlank(sortOption)
            ? DEFAULT_SORT
            : sortOption.trim().toUpperCase();

        return SORT_CLAUSES.containsKey(normalized) ? normalized : DEFAULT_SORT;
    }

    private static Integer normalizePageSize(Integer pageSize) {
        if (pageSize == null || pageSize <= 0) {
            return DEFAULT_PAGE_SIZE;
        }
        return Math.min(pageSize, MAX_PAGE_SIZE);
    }

    private static Integer normalizeOffset(Integer offset) {
        if (offset == null || offset < 0) {
            return 0;
        }
        return Math.min(offset, MAX_OFFSET);
    }

    private static Boolean isInternalVisible() {
        if (Test.isRunningTest() && testInternalVisibility != null) {
            return testInternalVisibility;
        }

        return FeatureManagement.checkPermission(ACCESS_ALL_PERMISSION);
    }

    private static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return (Id) value.trim();
        } catch (Exception ex) {
            return null;
        }
    }
}