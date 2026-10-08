/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EDiscoveryNotificationHandler
 * Author          : <YourName>
 * Created Date    : Sep 22, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Sep 22, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Sep 22, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class EDiscoveryNotificationHandler {

	public static void handleAfterUpdate(List<Case> newCases, Map<Id, Case> oldMap) {
		System.debug('Do Something');
	}

	public static void handleAfterInsert(List<Case> newCases) {
		System.debug('Do Something');
	}
}