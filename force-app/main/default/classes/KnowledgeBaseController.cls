public with sharing class KnowledgeBaseController {
    @TestVisible
	private static Boolean forceTestException = false;
    
    @AuraEnabled(cacheable=true)
    public static List<KnowledgeBaseService.DivisionOverviewItem> getDivisionOverview() {
        try {
            if (Test.isRunningTest() && forceTestException) {
                throw new AuraHandledException('Test exception');
            }
            return KnowledgeBaseService.getDivisionOverview();
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load the Knowledge Base. Please try again later.' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static KnowledgeBaseService.DivisionPageResponse getDivisionPage(
        String division,
        String searchTerm,
        String sortOption,
        Integer pageSize,
        Integer offset
    ) {
        try {
            if (Test.isRunningTest() && forceTestException) {
                throw new AuraHandledException('Test exception');
            }
            return KnowledgeBaseService.getDivisionPage(
                division,
                searchTerm,
                sortOption,
                pageSize,
                offset
            );
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load this Knowledge Base topic. Please try again later.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static KnowledgeBaseService.ArticleBreadcrumbContext getArticleBreadcrumbContext(String articleId) {
        try {
            if (Test.isRunningTest() && forceTestException) {
                throw new AuraHandledException('Test exception');
            }
            return KnowledgeBaseService.getArticleBreadcrumbContext(articleId);
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load the article breadcrumb. Please try again later.');
        }
    }
}