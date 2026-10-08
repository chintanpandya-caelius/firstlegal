public with sharing class TodolistController {

    @AuraEnabled(cacheable=true)
    public static ActivityDataWrapper getActivityCenterData() {
        ActivityDataWrapper wrapper = new ActivityDataWrapper();
        Id currentUserId = UserInfo.getUserId();
        Date today = Date.today();
        DateTime startOfToday = DateTime.newInstance(today, Time.newInstance(0, 0, 0, 0));

        // 1. TODAY'S ACTIVITIES (Tasks, Calls, Events, Emails)
        List<ActivityItem> todayItems = new List<ActivityItem>();

        // Today's Tasks & Calls
        for (Task t : [SELECT Id, Subject, Priority, Status, TaskSubtype, ActivityDate, What.Name, Who.Name 
                       FROM Task 
                       WHERE OwnerId = :currentUserId AND ActivityDate = :today WITH USER_MODE]) {
            todayItems.add(createTaskWrapper(t));
        }

        // Today's Events / Meetings (FIXED: Uses standard SOQL DAY_ONLY function)
        for (Event e : [SELECT Id, Subject, StartDateTime, EndDateTime, What.Name, Who.Name 
                        FROM Event 
                        WHERE OwnerId = :currentUserId 
                        AND DAY_ONLY(StartDateTime) = :today 
                        WITH USER_MODE]) {
            ActivityItem item = new ActivityItem();
            item.recordId = e.Id;
            item.recordLink = '/' + e.Id;
            item.subject = e.Subject;
            item.activityType = 'Meeting';
            item.details = (e.What != null) ? e.What.Name : ((e.Who != null) ? e.Who.Name : 'Calendar Event');
            item.status = 'Scheduled';
            item.isCompletable = false;
            todayItems.add(item);
        }

        // Today's Emails
        for (EmailMessage em : [SELECT Id, Subject, RelatedTo.Name, CreatedDate 
                                FROM EmailMessage 
                                WHERE CreatedById = :currentUserId AND CreatedDate >= :startOfToday WITH USER_MODE]) {
            ActivityItem item = new ActivityItem();
            item.recordId = em.Id;
            item.recordLink = '/' + em.Id;
            item.subject = em.Subject;
            item.activityType = 'Email';
            item.details = (em.RelatedTo != null) ? em.RelatedTo.Name : 'Sent Email';
            item.status = 'Sent';
            item.isCompletable = false;
            todayItems.add(item);
        }

        wrapper.todayActivities = todayItems;

        // 2. OVERDUE ACTIVITIES (Open Tasks & Calls due before today)
        List<ActivityItem> overdueItems = new List<ActivityItem>();
        for (Task t : [SELECT Id, Subject, Priority, Status, TaskSubtype, ActivityDate, What.Name, Who.Name 
                       FROM Task 
                       WHERE OwnerId = :currentUserId AND IsClosed = false AND ActivityDate < :today WITH USER_MODE 
                       ORDER BY ActivityDate ASC]) {
            overdueItems.add(createTaskWrapper(t));
        }

        wrapper.overdueActivities = overdueItems;

        return wrapper;
    }

    private static ActivityItem createTaskWrapper(Task t) {
        ActivityItem item = new ActivityItem();
        item.recordId = t.Id;
        item.recordLink = '/' + t.Id;
        item.subject = t.Subject;
        item.activityType = (t.TaskSubtype == 'Call') ? 'Call' : 'Task';
        item.details = (t.What != null) ? t.What.Name : ((t.Who != null) ? t.Who.Name : 'No Related Record');
        item.status = t.Status;
        item.dueDate = t.ActivityDate;
        item.isCompletable = true;
        return item;
    }

    @AuraEnabled
    public static void completeTask(Id taskId) {
        Task t = [SELECT Id, Status FROM Task WHERE Id = :taskId AND OwnerId = :UserInfo.getUserId() WITH USER_MODE LIMIT 1];
        t.Status = 'Completed';
        update as user t;
    }

    public class ActivityDataWrapper {
        @AuraEnabled public List<ActivityItem> todayActivities { get; set; }
        @AuraEnabled public List<ActivityItem> overdueActivities { get; set; }
    }

    public class ActivityItem {
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String recordLink { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String activityType { get; set; }
        @AuraEnabled public String details { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public Boolean isCompletable { get; set; }
    }
}