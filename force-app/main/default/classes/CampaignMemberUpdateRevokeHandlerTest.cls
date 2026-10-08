@IsTest(SeeAllData=true)
private class CampaignMemberUpdateRevokeHandlerTest {

    private static final String GROUP_DEVELOPER_NAME =
        'Campaign_Member_Update_Access_Revoke';

    private static final String ERROR_MESSAGE =
        'You cannot edit this Campaign Member since you are not the owner';


    @IsTest
    static void testNonOwnerCannotUpdateCampaignMember() {

        Group publicGroup = [
            SELECT Id
            FROM Group
            WHERE DeveloperName = :GROUP_DEVELOPER_NAME
            AND Type = 'Regular'
            LIMIT 1
        ];

        GroupMember groupMember = new GroupMember(
            GroupId = publicGroup.Id,
            UserOrGroupId = UserInfo.getUserId()
        );

        insert groupMember;

       
        CampaignMember cm = [
            SELECT Id, CampaignId, Status
            FROM CampaignMember
            WHERE Campaign.OwnerId != :UserInfo.getUserId()
            LIMIT 1
        ];

        Test.startTest();

        cm.Status = 'Sent';

        CampaignMemberUpdateRevokeHandler.beforeUpdate(
            new List<CampaignMember>{ cm }
        );

        Test.stopTest();

        System.assertEquals(
            ERROR_MESSAGE,
            cm.getErrors()[0].getMessage()
        );
    }


    @IsTest
    static void testBulkBeforeUpdate() {

        Group publicGroup = [
            SELECT Id
            FROM Group
            WHERE DeveloperName = :GROUP_DEVELOPER_NAME
            AND Type = 'Regular'
            LIMIT 1
        ];

        GroupMember groupMember = new GroupMember(
            GroupId = publicGroup.Id,
            UserOrGroupId = UserInfo.getUserId()
        );

        insert groupMember;

        List<CampaignMember> cmList = [
            SELECT Id, CampaignId, Status
            FROM CampaignMember
            WHERE Campaign.OwnerId != :UserInfo.getUserId()
            LIMIT 5
        ];

        Test.startTest();

        CampaignMemberUpdateRevokeHandler.beforeUpdate(cmList);

        Test.stopTest();

        for (CampaignMember cm : cmList) {
            System.assertEquals(
                ERROR_MESSAGE,
                cm.getErrors()[0].getMessage()
            );
        }
    }
}