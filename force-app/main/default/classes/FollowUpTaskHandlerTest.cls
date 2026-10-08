@IsTest
private class FollowUpTaskHandlerTest {


    
@IsTest
static void skipsManualFollowUpCalls() {
    Task manualCall = new Task(
        Subject = 'Manual Call',
        Type = 'Call',
        Status = 'Not Started',
        Priority = 'Normal',
        ActivityDate = Date.today(),
        OwnerId = UserInfo.getUserId(),
        Manual_Followup__c = true
    );

    Test.startTest();
    FollowUpTaskHandler.createFollowUpTasks(
        new List<Task>{ manualCall }
    );
    Test.stopTest();

    System.assertEquals(
        0,
        [SELECT COUNT()
         FROM Task
         WHERE Subject = 'Follow-up Call']
    );
}

@IsTest
static void skipsNonCallTasks() {
    Task emailTask = new Task(
        Subject = 'Send Email',
        Type = 'Email',
        Status = 'Not Started',
        Priority = 'Normal',
        ActivityDate = Date.today(),
        OwnerId = UserInfo.getUserId()
    );

    Test.startTest();
    FollowUpTaskHandler.createFollowUpTasks(
        new List<Task>{ emailTask }
    );
    Test.stopTest();

    System.assertEquals(
        0,
        [SELECT COUNT()
         FROM Task
         WHERE Subject = 'Follow-up Call']
    );
}
}