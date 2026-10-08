public with sharing class FL_RushKeywordChecker {

    public class Request {
        @InvocableVariable(label='Subject') public String subject;
        @InvocableVariable(label='Description') public String description;
    }

    @InvocableMethod(label='Is Rush Priority' description='True if Subject or Description contains any keyword from Rush_Priority_Keywords label')
    public static List<Boolean> isRush(List<Request> requests) {
        List<String> keywords = new List<String>();
        for (String k : System.Label.Rush_Priority_Keywords.split(',')) {
            if (String.isNotBlank(k)) keywords.add(k.trim().toUpperCase());
        }

        List<Boolean> results = new List<Boolean>();
        for (Request r : requests) {
            String text = (String.valueOf(r.subject) + ' ' + String.valueOf(r.description)).toUpperCase();
            Boolean hit = false;
            for (String k : keywords) {
                if (text.contains(k)) { hit = true; break; }
            }
            results.add(hit);
        }
        return results;
    }
}