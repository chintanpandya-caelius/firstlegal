@IsTest(SeeAllData=true)
private class CampaignMemberDeleteRevokeHandlerTest {

    private static final String GROUP_DEVELOPER_NAME =
        'Campaign_Member_Delete_Access_Revoke';

    private static final String ERROR_MESSAGE =
        'You cannot delete this Campaign Member due to inadequate permissions';


    @IsTest
    static void testUserInPublicGroupCannotDeleteCampaignMember() {

        Group publicGroup = [
            SELECT Id
            FROM Group
            WHERE DeveloperName = :GROUP_DEVELOPER_NAME
            AND Type = 'Regular'
            LIMIT 1
        ];

        insert new GroupMember(
            GroupId = publicGroup.Id,
            UserOrGroupId = UserInfo.getUserId()
        );

        CampaignMember cm = [
            SELECT Id, CampaignId
            FROM CampaignMember
            LIMIT 1
        ];

        Test.startTest();

        CampaignMemberDeleteRevokeHandler.beforeDelete(
            new List<CampaignMember>{ cm }
        );

        Test.stopTest();

        System.assertEquals(
            ERROR_MESSAGE,
            cm.getErrors()[0].getMessage()
        );
    }


    @IsTest
    static void testBulkBeforeDelete() {

        Group publicGroup = [
            SELECT Id
            FROM Group
            WHERE DeveloperName = :GROUP_DEVELOPER_NAME
            AND Type = 'Regular'
            LIMIT 1
        ];

        insert new GroupMember(
            GroupId = publicGroup.Id,
            UserOrGroupId = UserInfo.getUserId()
        );

        List<CampaignMember> cmList = [
            SELECT Id, CampaignId
            FROM CampaignMember
            LIMIT 5
        ];

        Test.startTest();

        CampaignMemberDeleteRevokeHandler.beforeDelete(cmList);

        Test.stopTest();

        for (CampaignMember cm : cmList) {
            System.assertEquals(
                ERROR_MESSAGE,
                cm.getErrors()[0].getMessage()
            );
        }
    }
}