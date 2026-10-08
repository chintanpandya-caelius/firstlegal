trigger CampaignMemberUpdateDeleteRevokeTrigger on CampaignMember (before update, before delete) {
	if(trigger.isupdate){
        CampaignMemberUpdateRevokeHandler.beforeUpdate(Trigger.new);
    }
    if(trigger.isdelete){
        CampaignMemberDeleteRevokeHandler.beforeDelete(Trigger.old);
    }
}