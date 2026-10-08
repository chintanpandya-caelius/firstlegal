public class ReminderStreamConfig{
    private static List<StreamDef> cachedStreams;

    public static final String TPL_REMINDER_1 = System.Label.Template_Reminder_1;
    public static final String TPL_REMINDER_2 = System.Label.Template_Reminder_2;
    public static final String TPL_REMINDER_3 = System.Label.Template_Reminder_3;
    public static final String TPL_AUTO_CLOSE = System.Label.Template_Autoclose;
    public static final String TPL_WO3P_DELAY = System.Label.Template_Waiting_on_3rd_party;
    public static final String TPL_SLA_WARNING = System.Label.Template_SLA_Warning;
    public static final String TPL_SLA_BREACH = System.Label.Template_SLA_Breach;

    //Ticket Status picklist values, hardcoded for now
    public static final String STAGE_WAITING_ON_CUSTOMER = 'Waiting on Customer';
    public static final String STAGE_WAITING_ON_3RD_PARTY = 'Waiting on 3rd Party';
    public static final String STAGE_IN_PROGRESS = 'In Progress';
    public static final String STAGE_CLOSED = 'Closed';

    public class StreamDef{
        public String streamName;
        public String businessHoursName;
        public String recordTypeDeveloperName;
        public Set<String> queueDeveloperNames;
        public Set<String> sourceEmails;
        public List<Integer> reminderIntervals;
        public List<String> reminderTemplates;
        public Boolean hasAutoClose;
        public Integer closeAfterLastReminder;
        public String autoCloseTemplate;
        public Boolean hasAgentNotify;
        public Integer agentNotifyAfterLastReminder;
        public String agentNotifyTemplate;
        public String reassignQueueDeveloperName;
        public Boolean useBusinessHours;
        public Boolean hasWo3pReminder;
        public String wo3pTemplate;
        public Integer wo3pIntervalDays;

        public StreamDef(){}
    }

    public class ConfigException extends Exception{}

    public static List<StreamDef> getStreams(){
        if(cachedStreams == null){
            cachedStreams = buildFromMetadata();
        }
        return cachedStreams;
    }

    private static List<StreamDef> buildFromMetadata(){
        List<StreamDef> result = new List<StreamDef>();

        for(Reminder_Stream__mdt row : [
            SELECT Service_Line__c,
                   Record_Type_Developer_Name__c,
            	   Business_Hour_Name__c,
                   Queues__c,
                   Source_Emails__c,
                   Reminder_Intervals__c,
                   Reminder_Email_Templates__c,
                   Auto_Close__c,
                   Close_After_Last_Reminder__c,
                   Auto_Close_Email_Template__c,
                   Notify_Agent__c,
                   Agent_Notification_Delay__c,
                   Agent_Notification_Template__c,
                   Queue_to_Reassign__c,
                   Use_Business_Hours__c,
                   Allow_Waiting_on_3rd_Person_Reminders__c,
                   Waiting_on_3rd_Person_Email_Template__c,
                   Waiting_on_3rd_Person_Interval__c
            FROM Reminder_Stream__mdt
        ]){
            result.add(mapRowToStreamDef(row));
        }

        return result;
    }

    private static StreamDef mapRowToStreamDef(Reminder_Stream__mdt row){
        StreamDef def = new StreamDef();

        def.streamName = row.Service_Line__c;
        def.recordTypeDeveloperName = nullIfBlank(row.Record_Type_Developer_Name__c);
        def.businessHoursName = nullIfBlank(row.Business_Hour_Name__c);

        def.queueDeveloperNames = splitToSet(row.Queues__c);
        def.sourceEmails = splitToSet(row.Source_Emails__c);

        List<String> intervalParts = splitToList(row.Reminder_Intervals__c);
        List<String> templateParts = splitToList(row.Reminder_Email_Templates__c);

        def.reminderIntervals = new List<Integer>();
        for(String part : intervalParts){
            def.reminderIntervals.add(Integer.valueOf(part.trim()));
        }
        def.reminderTemplates = templateParts;

        def.hasAutoClose = row.Auto_Close__c == true;
        def.closeAfterLastReminder = toInteger(row.Close_After_Last_Reminder__c);
        def.autoCloseTemplate = nullIfBlank(row.Auto_Close_Email_Template__c);

        def.hasAgentNotify = row.Notify_Agent__c == true;
        def.agentNotifyAfterLastReminder = toInteger(row.Agent_Notification_Delay__c);
        def.agentNotifyTemplate = nullIfBlank(row.Agent_Notification_Template__c);

        def.reassignQueueDeveloperName = nullIfBlank(row.Queue_to_Reassign__c);
        def.useBusinessHours = row.Use_Business_Hours__c == true;

        def.hasWo3pReminder = row.Allow_Waiting_on_3rd_Person_Reminders__c == true;
        def.wo3pTemplate = nullIfBlank(row.Waiting_on_3rd_Person_Email_Template__c);
        def.wo3pIntervalDays = toInteger(row.Waiting_on_3rd_Person_Interval__c);

        return def;
    }

    private static String nullIfBlank(String val){
        return String.isBlank(val) ? null : val;
    }

    private static Integer toInteger(Decimal val){
        return val == null ? 0 : val.intValue();
    }

    private static Set<String> splitToSet(String delimited){
        if(String.isBlank(delimited)) return null;
        Set<String> result = new Set<String>();
        for(String piece : delimited.split(';')){
            if (String.isNotBlank(piece)) {
                result.add(piece.trim());
            }
        }
        return result.isEmpty() ? null : result;
    }

    private static List<String> splitToList(String delimited){
        List<String> result = new List<String>();
        if(String.isBlank(delimited)) return result;
        for(String piece : delimited.split(';')){
            result.add(piece.trim());
        }
        return result;
    }

    public static StreamDef findStream(String recordTypeDeveloperName, String queueDeveloperName, String sourceEmail){
        for(StreamDef stream : getStreams()){
            if(stream.recordTypeDeveloperName != recordTypeDeveloperName){
                continue;
            }
            if(stream.queueDeveloperNames != null && !stream.queueDeveloperNames.contains(queueDeveloperName)){
                continue;
            }
            if(stream.sourceEmails != null){
                if(String.isBlank(sourceEmail)){
                    continue;
                }
                Boolean emailMatch = false;
                for(String validEmail : stream.sourceEmails){
                    if (sourceEmail.equalsIgnoreCase(validEmail)){
                        emailMatch = true;
                        break;
                    }
                }
                if(!emailMatch){
                    continue;
                }
            }
            return stream;
        }
        return null;
    }

    public static Integer getTotalDaysToClose(StreamDef stream){
        if(!stream.hasAutoClose) return null;
        Integer total = 0;
        for(Integer interval : stream.reminderIntervals){
            if (interval > 0) total += interval;
        }
        total += stream.closeAfterLastReminder;
        return total;
    }
}