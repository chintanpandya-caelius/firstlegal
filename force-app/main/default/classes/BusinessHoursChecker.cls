public without sharing class BusinessHoursChecker {
    public class Request {
        @InvocableVariable(required=false)
        public String businessHoursId;
        @InvocableVariable(required=false)
        public DateTime checkDateTime;
    }
    public class Response {
        @InvocableVariable
        public Boolean isWithinBusinessHours;
        @InvocableVariable
        public String availabilityText;
    }

    @InvocableMethod(label='Check Business Hours')
    public static List<Response> check(List<Request> requests) {
        List<Response> responses = new List<Response>();

        Set<Id> bhIds = new Set<Id>();
        for (Request req : requests) {
            if (!String.isBlank(req.businessHoursId)) {
                bhIds.add(req.businessHoursId);
            }
        }
        Map<Id, BusinessHours> bhMap = new Map<Id, BusinessHours>(
            [SELECT Id, Name, TimeZoneSidKey,
                     MondayStartTime, MondayEndTime,
                     TuesdayStartTime, TuesdayEndTime,
                     WednesdayStartTime, WednesdayEndTime,
                     ThursdayStartTime, ThursdayEndTime,
                     FridayStartTime, FridayEndTime,
                     SaturdayStartTime, SaturdayEndTime,
                     SundayStartTime, SundayEndTime
             FROM BusinessHours WHERE Id IN :bhIds WITH SYSTEM_MODE]
        );

        for (Request req : requests) {
            Response res = new Response();
            if (String.isBlank(req.businessHoursId) || !bhMap.containsKey(req.businessHoursId)) {
                res.isWithinBusinessHours = null;
                res.availabilityText = 'Business hours unavailable';
                responses.add(res);
                continue;
            }

            BusinessHours bh = bhMap.get(req.businessHoursId);
            res.isWithinBusinessHours = BusinessHours.isWithin(req.businessHoursId, req.checkDateTime);
            res.availabilityText = buildAvailabilityText(bh);
            responses.add(res);
        }
        return responses;
    }

    private static String buildAvailabilityText(BusinessHours bh) {
        List<String> lines = new List<String>();
        lines.add(formatDay('Monday', bh.MondayStartTime, bh.MondayEndTime));
        lines.add(formatDay('Tuesday', bh.TuesdayStartTime, bh.TuesdayEndTime));
        lines.add(formatDay('Wednesday', bh.WednesdayStartTime, bh.WednesdayEndTime));
        lines.add(formatDay('Thursday', bh.ThursdayStartTime, bh.ThursdayEndTime));
        lines.add(formatDay('Friday', bh.FridayStartTime, bh.FridayEndTime));
        lines.add(formatDay('Saturday', bh.SaturdayStartTime, bh.SaturdayEndTime));
        lines.add(formatDay('Sunday', bh.SundayStartTime, bh.SundayEndTime));
        return String.join(lines, '\n');
    }

    private static String formatDay(String dayName, Time startT, Time endT) {
        if (startT == null || endT == null) {
            return dayName + ': Closed';
        }
        return dayName + ': ' + formatTime(startT) + ' - ' + formatTime(endT);
    }

    private static String formatTime(Time t) {
        Integer hour = t.hour();
        Integer minute = t.minute();
        String ampm = hour < 12 ? 'AM' : 'PM';
        Integer hour12 = Math.mod(hour, 12);
        if (hour12 == 0) hour12 = 12;
        String minuteStr = minute < 10 ? '0' + minute : String.valueOf(minute);
        return hour12 + ':' + minuteStr + ' ' + ampm;
    }
}