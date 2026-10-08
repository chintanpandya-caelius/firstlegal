@IsTest
public class KnowledgeBaseControllerTest {

    private static void setupService() {
        KnowledgeBaseService.testConfigurations =
            new List<Division_Configuration__mdt>{
                new Division_Configuration__mdt(
                    MasterLabel = 'Client Care',
                    Division_Value__c = 'Client_Care',
                    Summary__c = 'Client Care',
                    Logo_Path__c = '/resource/clientcare',
                    Sort_Order__c = 1,
                    Active__c = true
                ),
                new Division_Configuration__mdt(
                    MasterLabel = 'Digital',
                    Division_Value__c = 'Digital',
                    Summary__c = 'Digital',
                    Logo_Path__c = '/resource/digital',
                    Sort_Order__c = 2,
                    Active__c = true
                )
            };

        KnowledgeBaseService.testInternalVisibility = false;
        KnowledgeBaseController.forceTestException = false;
    }

    @IsTest
    static void testNormalPaths() {

        setupService();

        Test.startTest();

        List<KnowledgeBaseService.DivisionOverviewItem> overview =
            KnowledgeBaseController.getDivisionOverview();

        KnowledgeBaseService.DivisionPageResponse page =
            KnowledgeBaseController.getDivisionPage(
                'Client_Care',
                null,
                'MOST_VIEWED',
                10,
                0
            );

        KnowledgeBaseService.ArticleBreadcrumbContext breadcrumb =
            KnowledgeBaseController.getArticleBreadcrumbContext(
                'not-a-valid-id'
            );

        Test.stopTest();

        System.assertNotEquals(null, overview);
        System.assertNotEquals(null, page);
        System.assertEquals(null, breadcrumb);
    }

    @IsTest
    static void testExceptionPaths() {

        setupService();

        KnowledgeBaseController.forceTestException = true;

        Test.startTest();

        Boolean overviewException = false;
        Boolean pageException = false;
        Boolean breadcrumbException = false;

        try {
            KnowledgeBaseController.getDivisionOverview();
        } catch (AuraHandledException e) {
            overviewException = true;
        }

        try {
            KnowledgeBaseController.getDivisionPage(
                'Client_Care',
                null,
                null,
                10,
                0
            );
        } catch (AuraHandledException e) {
            pageException = true;
        }

        try {
            KnowledgeBaseController.getArticleBreadcrumbContext(
                'not-a-valid-id'
            );
        } catch (AuraHandledException e) {
            breadcrumbException = true;
        }

        Test.stopTest();

        System.assertEquals(true, overviewException);
        System.assertEquals(true, pageException);
        System.assertEquals(true, breadcrumbException);
    }
}