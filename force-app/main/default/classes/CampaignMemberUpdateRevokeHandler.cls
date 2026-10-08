public class CampaignMemberUpdateRevokeHandler {
	private static final String PUBLIC_GROUP_DEVELOPER_NAME = 'Campaign_Member_Update_Access_Revoke';

    private static Boolean isCurrentUserInPublicGroup() {

        return [
            SELECT COUNT()
            FROM GroupMember
            WHERE UserOrGroupId = :UserInfo.getUserId()
            AND Group.Type = 'Regular'
            AND Group.DeveloperName = :PUBLIC_GROUP_DEVELOPER_NAME
        ] > 0;
    }
    
    public static void beforeUpdate(List<CampaignMember> Cmlist){     
        if (!isCurrentUserInPublicGroup()) {
            return;
        }

        Id currentUserId = UserInfo.getUserId();
        Set<Id> campaignIds=new Set<Id>();
        for(CampaignMember cm:cmlist){
            campaignIds.add(cm.CampaignId);
        }
        List<Campaign> cmpList=[select id, ownerid from campaign where id in :campaignIds];
        
        Map<Id,Id> campaignToOwnerMap=new Map<Id,Id>();
        
        for(Campaign cmp:cmpList){
            campaignToOwnerMap.put(cmp.id,cmp.ownerid);
        }
        for(CampaignMember cm:cmlist){
            if(campaignToOwnerMap.get(cm.campaignId)!=currentUserId){
                cm.adderror('You cannot edit this Campaign Member since you are not the owner');
            }
        }
}
}