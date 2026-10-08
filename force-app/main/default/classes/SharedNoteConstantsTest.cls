@IsTest
private class SharedNoteConstantsTest {

    @IsTest
    static void testConstantsValues() {
        Test.startTest();
        
        System.assertEquals(
            'External Note', 
            SharedNoteConstants.NOTE_TYPE_EXTERNAL, 
            'NOTE_TYPE_EXTERNAL should match expected string value.'
        );
        System.assertEquals(
            'Resolved', 
            SharedNoteConstants.CASE_STATUS_RESOLVED, 
            'CASE_STATUS_RESOLVED should match expected string value.'
        );
        System.assertEquals(
            'In Progress', 
            SharedNoteConstants.CASE_STATUS_IN_PROGRESS, 
            'CASE_STATUS_IN_PROGRESS should match expected string value.'
        );

        Test.stopTest();
    }
}