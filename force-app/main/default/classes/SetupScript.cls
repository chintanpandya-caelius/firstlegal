public class SetupScript {
    
    public class SetupScriptException extends Exception {}
    
    public static void setupQueuesAndGroups() {
        Integer totalPods = 25;
        
        // ---------- 1. DESGIN DESIRED GROUPS AND QUEUES ----------
        Map<String, String> desiredGroups = new Map<String, String>();
        Map<String, String> desiredQueues = new Map<String, String>();
        
        for (Integer i = 1; i <= totalPods; i++) {
            String podName = 'POD' + i;
            desiredGroups.put('FCP_' + podName, 'FCP ' + podName);
            desiredQueues.put('FCP_' + podName, 'FCP ' + podName);
        }
        desiredGroups.put('FSP_Digital_POD', 'FSP Digital POD');
        desiredGroups.put('FSP_Deposition_POD', 'FSP Deposition POD');
        desiredGroups.put('FSP_Court_Process_POD', 'FSP Court & Process POD');
        desiredGroups.put('FSP_Investigations_POD', 'FSP Investigations POD');
        desiredGroups.put('FSP_Records_POD', 'FSP Records POD');
        desiredGroups.put('FSP_Tech_POD', 'FSP Tech POD');
        desiredGroups.put('FSP_Financial_Billing_POD', 'FSP Financial & Billing POD');
        desiredGroups.put('FSP_General_POD', 'FSP General POD');
        
        //desiredGroups.put('General_Client_Care', 'General Client Care');
        desiredGroups.put('All_Pods', 'All Pods');
        //desiredQueues.put('General_Client_Care', 'General Client Care');
        
        desiredQueues.put('FSP_Digital_POD', 'FSP Digital POD');
        desiredQueues.put('FSP_Deposition_POD', 'FSP Deposition POD');
        desiredQueues.put('FSP_Court_Process_POD', 'FSP Court & Process POD');
        desiredQueues.put('FSP_Investigations_POD', 'FSP Investigations POD');
        desiredQueues.put('FSP_Records_POD', 'FSP Records POD');
        desiredQueues.put('FSP_Tech_POD', 'FSP Tech POD');
        desiredQueues.put('FSP_Financial_Billing_POD', 'FSP Financial & Billing POD');
        desiredQueues.put('FSP_General_POD', 'FSP General POD');
        
        // Queue DevName -> its correct owning Group DevName
        Map<String, String> queueToGroupDevName = new Map<String, String>();
        for (Integer i = 1; i <= totalPods; i++) {
            queueToGroupDevName.put('FCP_POD' + i, 'FCP_POD' + i);
        }
        queueToGroupDevName.put('FSP_Digital_POD', 'FSP_Digital_POD');
        queueToGroupDevName.put('FSP_Deposition_POD', 'FSP_Deposition_POD');
        queueToGroupDevName.put('FSP_Court_Process_POD', 'FSP_Court_Process_POD');
        queueToGroupDevName.put('FSP_Investigations_POD', 'FSP_Investigations_POD');
        queueToGroupDevName.put('FSP_Records_POD', 'FSP_Records_POD');
        queueToGroupDevName.put('FSP_Tech_POD', 'FSP_Tech_POD');
        queueToGroupDevName.put('FSP_Financial_Billing_POD', 'FSP_Financial_Billing_POD');
        queueToGroupDevName.put('FSP_General_POD', 'FSP_General_POD');
        //queueToGroupDevName.put('General_Client_Care', 'General_Client_Care');
        
        // ---------- 2. QUERY EXISTING ----------
        Map<String, Id> existingGroupIds = new Map<String, Id>();
        Map<String, Id> existingQueueIds = new Map<String, Id>();
        for (Group g : [SELECT Id, DeveloperName, Type FROM Group
                        WHERE DeveloperName IN :desiredGroups.keySet()
                        OR DeveloperName IN :desiredQueues.keySet()]) {
                            if (g.Type == 'Regular') existingGroupIds.put(g.DeveloperName, g.Id);
                            if (g.Type == 'Queue')   existingQueueIds.put(g.DeveloperName, g.Id);
                        }
        
        // ---------- 3. CREATE MISSING GROUPS ----------
        List<Group> groupsToInsert = new List<Group>();
        for (String devName : desiredGroups.keySet()) {
            if (!existingGroupIds.containsKey(devName)) {
                groupsToInsert.add(new Group(Name = desiredGroups.get(devName), DeveloperName = devName, Type = 'Regular'));
            }
        }
        if (!groupsToInsert.isEmpty()) insert groupsToInsert;
        for (Group g : groupsToInsert) existingGroupIds.put(g.DeveloperName, g.Id);
        
        // ---------- 4. CREATE MISSING QUEUES ----------
        List<Group> queuesToInsert = new List<Group>();
        for (String devName : desiredQueues.keySet()) {
            if (!existingQueueIds.containsKey(devName)) {
                queuesToInsert.add(new Group(Name = desiredQueues.get(devName), DeveloperName = devName, Type = 'Queue'));
            }
        }
        if (!queuesToInsert.isEmpty()) insert queuesToInsert;
        for (Group q : queuesToInsert) existingQueueIds.put(q.DeveloperName, q.Id);
        
        // ---------- 5. QUEUE -> SOBJECT (Case) LINKS ----------
        Set<Id> alreadyLinked = new Set<Id>();
        for (QueueSobject qs : [SELECT QueueId FROM QueueSobject
                                WHERE QueueId IN :existingQueueIds.values() AND SobjectType = 'Case']) {
                                    alreadyLinked.add(qs.QueueId);
                                }
        List<QueueSobject> linksToInsert = new List<QueueSobject>();
        for (Id qid : existingQueueIds.values()) {
            if (!alreadyLinked.contains(qid)) {
                linksToInsert.add(new QueueSobject(QueueId = qid, SobjectType = 'Case'));
            }
        }
        if (!linksToInsert.isEmpty()) insert linksToInsert;
        
        // ---------- 6. ENSURE CORRECT GROUP IS A QUEUE MEMBER ----------
        Set<String> existingMembershipKeys = new Set<String>();
        for (GroupMember gm : [SELECT GroupId, UserOrGroupId FROM GroupMember
                               WHERE GroupId IN :existingQueueIds.values()]) {
                                   existingMembershipKeys.add(gm.GroupId + '_' + gm.UserOrGroupId);
                               }
        List<GroupMember> queueMembersToInsert = new List<GroupMember>();
        for (String queueDevName : queueToGroupDevName.keySet()) {
            Id queueId = existingQueueIds.get(queueDevName);
            Id groupId = existingGroupIds.get(queueToGroupDevName.get(queueDevName));
            if (queueId == null || groupId == null) continue;
            String key = queueId + '_' + groupId;
            if (!existingMembershipKeys.contains(key)) {
                queueMembersToInsert.add(new GroupMember(GroupId = queueId, UserOrGroupId = groupId));
            }
        }
        if (!queueMembersToInsert.isEmpty()) insert queueMembersToInsert;
        
        // ---------- 7. NEST All_Pods_Members INSIDE EACH POD GROUP ----------
        Id allPodsId = existingGroupIds.get('All_Pods');
        List<GroupMember> nestingToInsert = new List<GroupMember>();
        if (allPodsId != null) {
            Set<String> existingNestKeys = new Set<String>();
            for (GroupMember gm : [SELECT GroupId, UserOrGroupId FROM GroupMember WHERE UserOrGroupId = :allPodsId]) {
                existingNestKeys.add(gm.GroupId + '_' + gm.UserOrGroupId);
            }
            for (Integer i = 1; i <= totalPods; i++) {
                Id podGroupId = existingGroupIds.get('FCP_POD' + i);
                if (podGroupId == null) continue;
                String key = podGroupId + '_' + allPodsId;
                if (!existingNestKeys.contains(key)) {
                    nestingToInsert.add(new GroupMember(GroupId = podGroupId, UserOrGroupId = allPodsId));
                }
            }
        }
        if (!nestingToInsert.isEmpty()) insert nestingToInsert;
        
        // ---------- 8. NORMALIZE: queues should ONLY contain their correct Group ----------
        // Re-query fresh membership (steps 6 may have just added rows)
        List<GroupMember> allQueueMembers = [
            SELECT Id, GroupId, UserOrGroupId
            FROM GroupMember
            WHERE GroupId IN :existingQueueIds.values()
        ];
        
        // Build reverse lookup: QueueId -> DevName
        Map<Id, String> queueIdToDevName = new Map<Id, String>();
        for (String devName : existingQueueIds.keySet()) {
            queueIdToDevName.put(existingQueueIds.get(devName), devName);
        }
        
        List<GroupMember> toDelete = new List<GroupMember>();
        for (GroupMember gm : allQueueMembers) {
            String queueDevName = queueIdToDevName.get(gm.GroupId);
            if (queueDevName == null) continue;
            
            String correctGroupDevName = queueToGroupDevName.get(queueDevName);
            Id correctGroupId = existingGroupIds.get(correctGroupDevName);
            
            if (correctGroupId == null || gm.UserOrGroupId != correctGroupId) {
                toDelete.add(gm);
            }
        }
        if (!toDelete.isEmpty()) delete toDelete;
        
        // ---------- SUMMARY ----------
        System.debug('Groups created: ' + groupsToInsert.size());
        System.debug('Queues created: ' + queuesToInsert.size());
        System.debug('Queue-Case links created: ' + linksToInsert.size());
        System.debug('Queue memberships added: ' + queueMembersToInsert.size());
        System.debug('All_Pods nestings added: ' + nestingToInsert.size());
        System.debug('queue members removed: ' + toDelete.size());
    }
    
    public static void setupDivisionalQueuesAndGroups() {
        
        Map<String, String> queueNameToDevName = new Map<String, String>{
            'Account Administration Team'            => 'Account_Administration_Team',
                'After-Hours Dispatcher Team'            => 'After_Hours_Dispatcher_Team',
                'Cash Application Team'                  => 'Cash_Application_Team',
                'Collections Team'                       => 'Collections_Team',
                'Depo Calendar Team'                     => 'Depo_Calendar_Team',
                'Depo Client Care Team'                  => 'Depo_Client_Care_Team',
                'Digital Fresno'                         => 'Digital_Fresno',
                'Digital LA Team'                        => 'Digital_LA_Team',
                'Digital San Diego Team'                 => 'Digital_San_Diego_Team',
                'Digital San Francisco/Oakland Team'     => 'Digital_San_Francisco_Oakland_Team',
                'Escalation Level 1 Team'                => 'Escalation_Level_1_Team',
                'Escalation Level 2 Team'                => 'Escalation_Level_2_Team',
                'Escalation Level 3 Team'                => 'Escalation_Level_3_Team',
                'Escalation Level 4 Team'                => 'Escalation_Level_4_Team',
                'Fairfield Process Team'                 => 'Fairfield_Process_Team',
                'Fairfield Team'                         => 'Fairfield_Team',
                'Florida Court Teams'                    => 'Florida_Court_Teams',
                'Florida Process Team'                   => 'Florida_Process_Team',
                'Fresno Court Team'                      => 'Fresno_Court_Team',
                'Fresno Process Team'                    => 'Fresno_Process_Team',
                'Investigation Specialized Team'         => 'Investigation_Specialized_Team',
                'Investigations After Hours Urgent Team' => 'Investigations_After_Hours_Urgent_Team',
                'Investigations International Team'      => 'Investigations_International_Team',
                'Investigations Skip Trace Team'         => 'Investigations_Skip_Trace_Team',
                'Investigations Summaries Team'          => 'Investigations_Summaries_Team',
                'Investigations Surveillance Team'       => 'Investigations_Surveillance_Team',
                'Investigations Team'                    => 'Investigations_Team',
                'Invoicing Team'                         => 'Invoicing_Team',
                'LA Court Team'                          => 'LA_Court_Team',
                'LA Process Team'                        => 'LA_Process_Team',
                'Las Vegas Court Team'                   => 'Las_Vegas_Court_Team',
                'Las Vegas Process Team'                 => 'Las_Vegas_Process_Team',
                'NY Info queue Team'                     => 'NY_Info_queue_Team',
                'NY Process queue Team'                  => 'NY_Process_queue_Team',
                'National Court Team'                    => 'National_Court_Team',
                'National Orders Team'                   => 'National_Orders_Team',
                'National Process Team'                  => 'National_Process_Team',
                'New York Court Team'                    => 'New_York_Court_Team',
                'Orange County Court Team'               => 'Orange_County_Court_Team',
                'Orange County Process Team'             => 'Orange_County_Process_Team',
                'Phoenix Court Team'                     => 'Phoenix_Court_Team',
                'Phoenix Process Team'                   => 'Phoenix_Process_Team',
                'Records (Interstate)'                   => 'Records_Interstate',
                'Records - Radiology'                    => 'Records_Radiology',
                'Records Billing Team'                   => 'Records_Billing_Team',
                'Records Customer Support Team'          => 'Records_Customer_Support_Team',
                'Records Driver Team'                    => 'Records_Driver_Team',
                'Records General Inquiry Team'           => 'Records_General_Inquiry_Team',
                'Records Interstate Leadership Team'     => 'Records_Interstate_Leadership_Team',
                'Records JCCP 5378 Team'                 => 'Records_JCCP_5378_Team',
                'Records Opposing Counsel Team'          => 'Records_Opposing_Counsel_Team',
                'Records Orders Team'                    => 'Records_Orders_Team',
                'Records QC Production'                  => 'Records_QC_Production',
                'Records Receiving Inquiry Team'         => 'Records_Receiving_Inquiry_Team',
                'Records Receiving Team'                 => 'Records_Receiving_Team',
                'Records Shipping Team'                  => 'Records_Shipping_Team',
                'Records Summary Team'                   => 'Records_Summary_Team',
                'Redding Team'                           => 'Redding_Team',
                'Riverside Court Team'                   => 'Riverside_Court_Team',
                'Riverside Process Team'                 => 'Riverside_Process_Team',
                'SF Court Team'                          => 'SF_Court_Team',
                'SF Process Team'                        => 'SF_Process_Team',
                'Sacramento Court Team'                  => 'Sacramento_Court_Team',
                'Sacramento Process Team'                => 'Sacramento_Process_Team',
                'San Diego Court Team'                   => 'San_Diego_Court_Team',
                'San Diego Process Team'                 => 'San_Diego_Process_Team',
                'San Jose Court Team'                    => 'San_Jose_Court_Team',
                'San Jose Orders Team'                   => 'San_Jose_Orders_Team',
                'San Jose Process Team'                  => 'San_Jose_Process_Team',
                'Texas Court Team'                       => 'Texas_Court_Team',
                'Texas Process Team'                     => 'Texas_Process_Team',
                'Tucson Court Team'                      => 'Tucson_Court_Team',
                'Tucson Process Team'                    => 'Tucson_Process_Team',
                'Ventura Court Team'                     => 'Ventura_Court_Team',
                'Ventura Process Team'                   => 'Ventura_Process_Team',
                'eDiscovery Billing Team'                => 'eDiscovery_Billing_Team',
                'eDiscovery Main Team'                   => 'eDiscovery_Main_Team',
                'eDiscovery PTS Support'                 => 'eDiscovery_PTS_Support',
                'eDiscovery Theodora Oringher PC Team'   => 'eDiscovery_Theodora_Oringher_PC_Team',
                'eFiling Dispatcher Team'                => 'eFiling_Dispatcher_Team',
                'eFiling leadership escalation Team'     => 'eFiling_leadership_escalation_Team'
                };
                    
                    // ---------- 2. QUERY EXISTING ----------
                    // Regular group and Queue share the same Name and DeveloperName (per existing
                    // convention), so one query covers both Types.
                    Map<String, Id> existingGroupIds = new Map<String, Id>();
        Map<String, Id> existingQueueIds = new Map<String, Id>();
        for (Group g : [SELECT Id, DeveloperName, Type FROM Group
                        WHERE DeveloperName IN :queueNameToDevName.values()]) {
                            if (g.Type == 'Regular') existingGroupIds.put(g.DeveloperName, g.Id);
                            if (g.Type == 'Queue')   existingQueueIds.put(g.DeveloperName, g.Id);
                        }
        
        // ---------- 3. CREATE MISSING GROUPS (idempotent safety net) ----------
        List<Group> groupsToInsert = new List<Group>();
        for (String qName : queueNameToDevName.keySet()) {
            String devName = queueNameToDevName.get(qName);
            if (!existingGroupIds.containsKey(devName)) {
                groupsToInsert.add(new Group(Name = qName, DeveloperName = devName, Type = 'Regular'));
            }
        }
        if (!groupsToInsert.isEmpty()) insert groupsToInsert;
        for (Group g : groupsToInsert) existingGroupIds.put(g.DeveloperName, g.Id);
        
        // ---------- 4. CREATE MISSING QUEUES (idempotent safety net) ----------
        List<Group> queuesToInsert = new List<Group>();
        for (String qName : queueNameToDevName.keySet()) {
            String devName = queueNameToDevName.get(qName);
            if (!existingQueueIds.containsKey(devName)) {
                queuesToInsert.add(new Group(Name = qName, DeveloperName = devName, Type = 'Queue'));
            }
        }
        if (!queuesToInsert.isEmpty()) insert queuesToInsert;
        for (Group q : queuesToInsert) existingQueueIds.put(q.DeveloperName, q.Id);
        
        // ---------- 5. QUEUE -> SOBJECT (Case) LINKS ----------
        Set<Id> alreadyLinked = new Set<Id>();
        for (QueueSobject qs : [SELECT QueueId FROM QueueSobject
                                WHERE QueueId IN :existingQueueIds.values() AND SobjectType = 'Case']) {
                                    alreadyLinked.add(qs.QueueId);
                                }
        List<QueueSobject> linksToInsert = new List<QueueSobject>();
        for (Id qid : existingQueueIds.values()) {
            if (!alreadyLinked.contains(qid)) {
                linksToInsert.add(new QueueSobject(QueueId = qid, SobjectType = 'Case'));
            }
        }
        if (!linksToInsert.isEmpty()) insert linksToInsert;
        
        // ---------- 6. ADD THE CORRECT GROUP AS A QUEUE MEMBER (additive only) ----------
        // No removal step: existing queue members are left untouched. We only add
        // the matching Regular group if it isn't already a member.
        Set<String> existingMembershipKeys = new Set<String>();
        for (GroupMember gm : [SELECT GroupId, UserOrGroupId FROM GroupMember
                               WHERE GroupId IN :existingQueueIds.values()]) {
                                   existingMembershipKeys.add(gm.GroupId + '_' + gm.UserOrGroupId);
                               }
        List<GroupMember> queueMembersToInsert = new List<GroupMember>();
        for (String devName : queueNameToDevName.values()) {
            Id queueId = existingQueueIds.get(devName);
            Id groupId = existingGroupIds.get(devName);
            if (queueId == null || groupId == null) continue;
            String key = queueId + '_' + groupId;
            if (!existingMembershipKeys.contains(key)) {
                queueMembersToInsert.add(new GroupMember(GroupId = queueId, UserOrGroupId = groupId));
            }
        }
        if (!queueMembersToInsert.isEmpty()) insert queueMembersToInsert;
        
        // ---------- SUMMARY ----------
        System.debug('Groups created: ' + groupsToInsert.size());
        System.debug('Queues created: ' + queuesToInsert.size());
        System.debug('Queue-Case links created: ' + linksToInsert.size());
        System.debug('Queue memberships added: ' + queueMembersToInsert.size());
    }
}