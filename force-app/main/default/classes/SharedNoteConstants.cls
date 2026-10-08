// This class defines the "magic strings" and other constants that are referenced stream-wide
public with sharing class SharedNoteConstants {
    public static final String NOTE_TYPE_EXTERNAL = 'External Note';
    public static final String CASE_STATUS_IN_PROGRESS = 'In Progress';
    public static final String CASE_STATUS_NEW = 'New';
    public static final Integer REOPEN_WINDOW_DAYS = 7;
    public static final Set<String> BLOCKED_INTERNAL_COMMENT_PROFILES = new Set<String>{
        'First Legal User',
        'System Administrator'
    };
}