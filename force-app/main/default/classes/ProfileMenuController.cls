/**
 * Returns the current site visitor's basic profile info (name, photo, email)
 * for use in the custom Profile Menu LWC on LWR (Build Your Own) Experience sites.
 *
 * Guest users are detected and skipped (no query) so the component can show
 * a Login button instead of throwing an access error.
 */
public with sharing class ProfileMenuController {

    @AuraEnabled(cacheable=true)
    public static UserWrapper getCurrentUser() {
        UserWrapper wrapper = new UserWrapper();
        wrapper.isGuest = (UserInfo.getUserType() == 'Guest');

        if (wrapper.isGuest) {
            return wrapper;
        }

        try {
            User u = [
                SELECT Id, Name, SmallPhotoUrl, Email
                FROM User
                WHERE Id = :UserInfo.getUserId()
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            wrapper.userId = u.Id;
            wrapper.name = u.Name;
            wrapper.photoUrl = u.SmallPhotoUrl;
            wrapper.email = u.Email;
        } catch (Exception e) {
            // Fallback if fields aren't queryable for this profile -
            // still show a name so the icon/menu doesn't break.
            wrapper.name = UserInfo.getName();
        }

        return wrapper;
    }

    public class UserWrapper {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String email;
        @AuraEnabled public Boolean isGuest = false;
    }
}